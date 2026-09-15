using System.Text;

namespace Notepad.Core;

// File save path, owned by D01 T01 §5. UI-free: encoding, EOL conversion,
// the atomic commit, failure mapping, and Save All orchestration live here;
// the Save As dialog and the failure notices render in app code (D01 T02 §1
// owns the first save triggers). The editor buffer (D02) supplies Text; the
// model never holds full content, so every entry point takes the text.
public static class FileSave
{
    // UTF-32 names are §4's literals: detected on open, preserved on save,
    // never offered by Save As.
    public const string Utf32LeName = "UTF-32 LE";

    public const string Utf32BeName = "UTF-32 BE";

    static FileSave()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    // Encodes text for saving: line endings normalized to the target, then
    // bytes in the named encoding with the BOM per hasBom. Encoding names are
    // the §4 list plus UTF-32 LE/BE (preserve-only). Unknown names throw:
    // saving must never guess. Unknown EOL names fall back to CRLF, the §4
    // dominant default. All encoders are strict: unencodable characters throw
    // EncoderFallbackException (surfaced as SaveFailed) instead of silently
    // writing '?' (default: stock's exact warning is unprobed; costs the
    // dialog wording when D01 T02 §1 renders it).
    public static byte[] Encode(string text, string encodingName, bool hasBom, string lineEnding)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(encodingName);
        ArgumentNullException.ThrowIfNull(lineEnding);
        string target = lineEnding switch
        {
            LineEndings.Lf => "\n",
            LineEndings.Cr => "\r",
            _ => "\r\n",
        };
        string normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        string converted = target == "\n" ? normalized : normalized.Replace("\n", target, StringComparison.Ordinal);
        Encoding encoding = encodingName switch
        {
            FileOpen.AnsiName => Encoding.GetEncoding(1252, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback),
            FileOpen.Utf16LeName => new UnicodeEncoding(bigEndian: false, byteOrderMark: false, throwOnInvalidBytes: true),
            FileOpen.Utf16BeName => new UnicodeEncoding(bigEndian: true, byteOrderMark: false, throwOnInvalidBytes: true),
            FileOpen.Utf8Name => new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true),
            FileOpen.Utf8BomName => new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true),
            Utf32LeName => new UTF32Encoding(bigEndian: false, byteOrderMark: false, throwOnInvalidCharacters: true),
            Utf32BeName => new UTF32Encoding(bigEndian: true, byteOrderMark: false, throwOnInvalidCharacters: true),
            _ => throw new ArgumentException($"Unknown encoding '{encodingName}'.", nameof(encodingName)),
        };
        byte[] body = encoding.GetBytes(converted);
        byte[] preamble = hasBom ? PreambleFor(encodingName) : [];
        byte[] bytes = new byte[preamble.Length + body.Length];
        Buffer.BlockCopy(preamble, 0, bytes, 0, preamble.Length);
        Buffer.BlockCopy(body, 0, bytes, preamble.Length, body.Length);
        return bytes;
    }

    // Explicit BOM table: the strict encoder instances above are built with
    // byteOrderMark false (their own preambles are empty by construction),
    // so the flag maps to bytes here. ANSI has no BOM; unknown names cannot
    // reach this (Encode throws first).
    static byte[] PreambleFor(string encodingName) => encodingName switch
    {
        FileOpen.Utf8Name or FileOpen.Utf8BomName => [0xEF, 0xBB, 0xBF],
        FileOpen.Utf16LeName => [0xFF, 0xFE],
        FileOpen.Utf16BeName => [0xFE, 0xFF],
        Utf32LeName => [0xFF, 0xFE, 0x00, 0x00],
        Utf32BeName => [0x00, 0x00, 0xFE, 0xFF],
        _ => [],
    };

    // Atomic save: bytes land in a same-directory temp file first (a rename
    // is only atomic on one filesystem), then move over the target, so a
    // crash keeps either the old or the new bytes, never a mix. True-crash
    // orphans keep their temp name; every caught path deletes best-effort.
    // faultBeforeCommit injects the crash point for item 1's drive.
    public static SaveResult SaveFile(string path, string text, SaveSpec spec, Action? faultBeforeCommit = null)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(spec);
        string? directory = Path.GetDirectoryName(Path.GetFullPath(path));
        string temp = Path.Combine(directory!, $".~{Guid.NewGuid():N}.tmp");
        try
        {
            byte[] bytes = Encode(text, spec.EncodingName, spec.HasBom, spec.LineEnding);
            File.WriteAllBytes(temp, bytes);
            faultBeforeCommit?.Invoke();
            File.Move(temp, path, overwrite: true);
            return new SaveSuccess();
        }
        catch (EncoderFallbackException ex)
        {
            // Nothing written yet (encoding precedes the temp file).
            return new SaveFailed(ex.Message);
        }
        catch (Exception ex) when (RedirectsToSaveAs(ex))
        {
            DeleteQuietly(temp);
            return new SaveRedirect(ex.Message);
        }
        catch (Exception ex) when ((ex is IOException or NotSupportedException) && !RedirectsToSaveAs(ex))
        {
            // Structural IO failures the redirect map declines (missing
            // directory, bad path shape): single source is RedirectsToSaveAs,
            // so the two filters cannot drift apart. Anything else (caller
            // bugs, the injected fault) propagates.
            DeleteQuietly(temp);
            return new SaveFailed(ex.Message);
        }
    }

    // Read-only and locked destinations redirect to Save As (probed: stock
    // opens Save As for both, bytes intact). One outcome, no reason: Windows
    // reports both as UnauthorizedAccessException, so the OS does not
    // reliably distinguish them. Structural IO failures (missing directory,
    // bad path shape) report instead: DirectoryNotFound and friends derive
    // from IOException, so they must opt out before the plain-IO arm.
    public static bool RedirectsToSaveAs(Exception ex)
    {
        ArgumentNullException.ThrowIfNull(ex);
        return ex switch
        {
            UnauthorizedAccessException => true,
            DirectoryNotFoundException or DriveNotFoundException or FileNotFoundException or PathTooLongException or NotSupportedException => false,
            IOException => true,
            _ => false,
        };
    }

    // Save All, walking tabs in strict tab order (probed): dirty path tabs
    // save silently, dirty untitled tabs prompt through saveAsChoice, clean
    // tabs are skipped, and a Cancel (null choice) skips that tab and
    // CONTINUES, never aborts. A mid-All redirect prompts inline Save As for
    // that tab (default, mirrors single-save; unprobed in All-flow); a
    // mid-All failure records and continues (default, mirrors cancel).
    public static IReadOnlyList<SaveAllEntry> SaveAll(TabModel model, Func<Tab, string> textOf, Func<Tab, SaveAsChoice?> saveAsChoice)
    {
        ArgumentNullException.ThrowIfNull(model);
        ArgumentNullException.ThrowIfNull(textOf);
        ArgumentNullException.ThrowIfNull(saveAsChoice);
        var entries = new List<SaveAllEntry>();
        foreach (Tab tab in model.Tabs)
        {
            if (!tab.IsDirty)
            {
                continue;
            }

            string text = textOf(tab);
            if (tab.FilePath is null)
            {
                SaveAsChoice? choice = saveAsChoice(tab);
                if (choice is null)
                {
                    entries.Add(new SaveAllEntry(tab, SaveAllOutcome.Skipped, null));
                    continue;
                }

                SaveOne(model, tab, choice.Path, new SaveSpec(choice.EncodingName, choice.HasBom, choice.LineEnding), text, entries);
                continue;
            }

            SaveResult result = SaveFile(tab.FilePath, text, new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding));
            if (result is SaveRedirect)
            {
                SaveAsChoice? choice = saveAsChoice(tab);
                if (choice is null)
                {
                    entries.Add(new SaveAllEntry(tab, SaveAllOutcome.Skipped, null));
                    continue;
                }

                SaveOne(model, tab, choice.Path, new SaveSpec(choice.EncodingName, choice.HasBom, choice.LineEnding), text, entries);
                continue;
            }

            ApplyResult(model, tab, tab.FilePath, new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding), result, entries);
        }

        return entries;
    }

    static void SaveOne(TabModel model, Tab tab, string path, SaveSpec spec, string text, List<SaveAllEntry> entries)
    {
        SaveResult result = SaveFile(path, text, spec);
        ApplyResult(model, tab, path, spec, result, entries);
    }

    static void ApplyResult(TabModel model, Tab tab, string path, SaveSpec spec, SaveResult result, List<SaveAllEntry> entries)
    {
        switch (result)
        {
            case SaveSuccess:
                tab.ApplySave(path, spec);
                entries.Add(new SaveAllEntry(tab, SaveAllOutcome.Saved, null));
                break;
            case SaveRedirect redirect:
                // Reached only for Save As-choice paths (path-tab redirects
                // prompt inline above): the chosen destination failed, so
                // that tab's save failed with the OS detail.
                entries.Add(new SaveAllEntry(tab, SaveAllOutcome.Failed, redirect.Detail));
                break;
            case SaveFailed failed:
                entries.Add(new SaveAllEntry(tab, SaveAllOutcome.Failed, failed.Detail));
                break;
        }
    }

    static void DeleteQuietly(string temp)
    {
        try
        {
            File.Delete(temp);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

}

public sealed record SaveSpec(string EncodingName, bool HasBom, string LineEnding);

public sealed record SaveAsChoice(string Path, string EncodingName, bool HasBom, string LineEnding);

public abstract record SaveResult;

public sealed record SaveSuccess : SaveResult;

public sealed record SaveRedirect(string Detail) : SaveResult;

public sealed record SaveFailed(string Detail) : SaveResult;

public enum SaveAllOutcome
{
    Saved,
    Skipped,
    Failed,
}

public sealed record SaveAllEntry(Tab Tab, SaveAllOutcome Outcome, string? Detail);

// Save failure strings, owned by D01 T01 §5 item 4. Only unmapped failures
// report (read-only and locked redirect to Save As instead); the message is
// the live OS text and the title is stock "Notepad" per the §3/§4 precedent.
// Rendered by the app when the D01 T02 §1 trigger lands.
public static class SaveMessages
{
    public const string DialogTitle = "Notepad";
}

// Save As dialog spec, owned by D01 T01 §5 items 2 and 5. Stock's dialog
// (capture `notepad-saveas-dialog-n11.2607.14.0-win25h2.png`) carries File
// name (prefilled `Untitled.txt`, or first-line plus `.txt` for content),
// Save as type (`Text documents (*.txt)` plus `All files (*.*)`), and
// Encoding (default UTF-8 for new files); it has NO line-ending dropdown.
// Applied to the picker by the D01 T02 §1 trigger.
public static class SaveDialogDefaults
{
    public static IReadOnlyList<string> FileTypeFilter { get; } = [".txt", "*"];

    public static IReadOnlyList<string> OfferedEncodings { get; } =
    [
        FileOpen.AnsiName,
        FileOpen.Utf16LeName,
        FileOpen.Utf16BeName,
        FileOpen.Utf8Name,
        FileOpen.Utf8BomName,
    ];

    public const string DefaultEncoding = FileOpen.Utf8Name;

    // New-file prefill, probed (`ZCOMBO-w5.txt` for content, `Untitled.txt`
    // for blank): display name plus `.txt`. Illegal filename characters are
    // NOT sanitized yet (unprobed what stock does; costs one Replace).
    public static string FileNameFor(string firstLine) => TabDisplayName.FromContent(firstLine) + ".txt";
}
