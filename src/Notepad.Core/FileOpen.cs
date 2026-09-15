using System.Text;

namespace Notepad.Core;

// File open path, owned by D01 T01 §4. UI-free: detection, decoding, failure
// mapping, failure message strings, the size gate, the dialog filter spec,
// and the .LOG rule live here; rendering the dialog and the notices is app
// code (D01 T02 §1 owns the first open trigger). Notepad loads the whole
// file (past its size limit it refuses), so detection runs over all bytes;
// the async chunked read exists only to keep the UI alive.
public static class FileOpen
{
    // No stock source names a progress threshold, so this is a recorded
    // default: past 1 MiB the open reports progress. Changing it costs one
    // constant. (D01 T01 §4, phase-1 run 2.)
    public const long DefaultProgressThresholdBytes = 1024 * 1024;

    // Encoding names match the §5 Save As list exactly: ANSI, UTF-16 LE,
    // UTF-16 BE, UTF-8, UTF-8 with BOM.
    public const string AnsiName = "ANSI";
    public const string Utf16LeName = "UTF-16 LE";
    public const string Utf16BeName = "UTF-16 BE";
    public const string Utf8Name = "UTF-8";
    public const string Utf8BomName = "UTF-8 with BOM";

    static FileOpen()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    public static DetectedFile Detect(byte[] bytes)
    {
        ArgumentNullException.ThrowIfNull(bytes);
        (Encoding encoding, string name, int preamble) = DetectEncoding(bytes);
        string text = encoding.GetString(bytes, preamble, bytes.Length - preamble);
        LineEndingInfo eol = DetectLineEnding(text);
        return new DetectedFile(text, name, preamble > 0, eol);
    }

    public static async Task<OpenResult> OpenFileAsync(
        string path,
        OpenOptions options,
        IProgress<long>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(options);
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || (info.Attributes & FileAttributes.Directory) != 0)
            {
                return new OpenFailureResult(OpenFailure.NotFound);
            }

            if (info.Length > options.MaxBytes)
            {
                return new OpenFailureResult(OpenFailure.TooLarge);
            }

            byte[] bytes;
            FileStream stream = info.Open(FileMode.Open, FileAccess.Read, FileShare.Read);
            await using (stream.ConfigureAwait(false))
            {
                bytes = new byte[info.Length];
                int read = 0;
                while (read < bytes.Length)
                {
                    int n = await stream.ReadAsync(bytes.AsMemory(read), cancellationToken).ConfigureAwait(false);
                    if (n == 0)
                    {
                        break;
                    }

                    read += n;
                    if (bytes.Length >= options.ProgressThresholdBytes)
                    {
                        progress?.Report(read);
                    }
                }

                if (read != bytes.Length)
                {
                    Array.Resize(ref bytes, read);
                }
            }

            DetectedFile detected = Detect(bytes);
            string text = detected.Text;
            if (IsLogFile(text))
            {
                text = ApplyLogStamp(text, detected.LineEnding.Dominant, options.LogTimestamp);
            }

            return new OpenSuccess(text, detected.EncodingName, detected.HasBom, detected.LineEnding);
        }
        catch (Exception ex) when (MapFailure(ex) is { } failure)
        {
            return new OpenFailureResult(failure, ex.Message);
        }
    }

    // Maps the known open failures; unknown exceptions (including
    // cancellation) return null so the filter lets them propagate.
    public static OpenFailure? MapFailure(Exception ex)
    {
        ArgumentNullException.ThrowIfNull(ex);
        return ex switch
        {
            FileNotFoundException => OpenFailure.NotFound,
            DirectoryNotFoundException => OpenFailure.NotFound,
            UnauthorizedAccessException => OpenFailure.Unreadable,
            IOException => OpenFailure.Locked,
            _ => null,
        };
    }

    // Detection order is a recorded default (bedtime stock probe confirms):
    // BOM, then the UTF-16 null pattern, then strict UTF-8, else ANSI. The
    // null pattern must precede UTF-8 because BOM-less UTF-16 ASCII is also
    // valid UTF-8 (NULs are legal); checking UTF-8 first would never find it.
    // UTF-32 BOMs decode as UTF-32: outside the §4 list, but misdecoding them
    // would corrupt, and opening must never corrupt.
    static (Encoding Encoding, string Name, int Preamble) DetectEncoding(byte[] bytes)
    {
        if (bytes.Length >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF)
        {
            return (new UTF32Encoding(bigEndian: true, byteOrderMark: false), "UTF-32 BE", 4);
        }

        if (bytes.Length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00)
        {
            return (Encoding.UTF32, "UTF-32 LE", 4);
        }

        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        {
            return (Encoding.UTF8, Utf8BomName, 3);
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
        {
            return (Encoding.BigEndianUnicode, Utf16BeName, 2);
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
        {
            return (Encoding.Unicode, Utf16LeName, 2);
        }

        if (LooksLikeUtf16Le(bytes))
        {
            return (Encoding.Unicode, Utf16LeName, 0);
        }

        if (LooksLikeUtf16Be(bytes))
        {
            return (Encoding.BigEndianUnicode, Utf16BeName, 0);
        }

        if (IsStrictUtf8(bytes))
        {
            return (Encoding.UTF8, Utf8Name, 0);
        }

        // ANSI is windows-1252 by recorded default: the system codepage varies
        // by locale and the neutral core cannot ask the OS. Localizing to the
        // active ACP later costs one lookup at this call site.
        return (Encoding.GetEncoding(1252), AnsiName, 0);
    }

    static bool LooksLikeUtf16Le(byte[] bytes)
    {
        if (bytes.Length < 4 || bytes.Length % 2 != 0)
        {
            return false;
        }

        for (int i = 0; i < bytes.Length; i += 2)
        {
            if (bytes[i + 1] != 0)
            {
                return false;
            }
        }

        return true;
    }

    static bool LooksLikeUtf16Be(byte[] bytes)
    {
        if (bytes.Length < 4 || bytes.Length % 2 != 0)
        {
            return false;
        }

        for (int i = 0; i < bytes.Length; i += 2)
        {
            if (bytes[i] != 0)
            {
                return false;
            }
        }

        return true;
    }

    static bool IsStrictUtf8(byte[] bytes)
    {
        try
        {
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true).GetCharCount(bytes);
            return true;
        }
        catch (DecoderFallbackException)
        {
            return false;
        }
    }

    public static LineEndingInfo DetectLineEnding(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        int crlf = 0;
        int lf = 0;
        int cr = 0;
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] == '\r')
            {
                if (i + 1 < text.Length && text[i + 1] == '\n')
                {
                    crlf++;
                    i++;
                }
                else
                {
                    cr++;
                }
            }
            else if (text[i] == '\n')
            {
                lf++;
            }
        }

        // Plurality wins; ties break CRLF, LF, CR; no endings means CRLF (the
        // Tab and new-file default). Recorded default: stock's mixed-ending
        // rule is bedtime-probed, and costs one comparison to change.
        string dominant = (crlf, lf, cr) switch
        {
            (0, 0, 0) => LineEndings.Crlf,
            _ when crlf >= lf && crlf >= cr => LineEndings.Crlf,
            _ when lf >= cr => LineEndings.Lf,
            _ => LineEndings.Cr,
        };
        return new LineEndingInfo(crlf, lf, cr, dominant);
    }

    // Case-sensitive ".LOG" is a recorded default (bedtime stock probe
    // confirms); the separator keeps the stamp on its own line.
    public static bool IsLogFile(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        int end = text.IndexOfAny(['\r', '\n']);
        string first = end < 0 ? text : text[..end];
        return first.Equals(".LOG", StringComparison.Ordinal);
    }

    public static string ApplyLogStamp(string text, string dominantLineEnding, string formattedTimestamp)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(formattedTimestamp);
        string eol = dominantLineEnding switch
        {
            LineEndings.Lf => "\n",
            LineEndings.Cr => "\r",
            _ => "\r\n",
        };

        // Stock appends eol plus the stamp plus eol unconditionally (probed
        // 2026-09-15, file bytes after stock save: ".LOG CRLF body CRLF CRLF
        // stamp CRLF"). A file ending in a newline gains a blank line before
        // the stamp. The stamp text is the app's `{now:t} {now:d}` call.
        return text + eol + formattedTimestamp + eol;
    }
}

public static class LineEndings
{
    public const string Crlf = "CRLF";
    public const string Lf = "LF";
    public const string Cr = "CR";
}

// The .LOG stamp text, owned by D01 T01 §4 item 9: stock writes short-time,
// space, short-date in the current culture (probed 2026-09-15: "02:07
// 2026/09/15" where t was "02:07" and d was "2026/09/15"). The app calls this
// when it builds OpenOptions; D02 T01 §5's F5 insert matches it.
public static class LogTimestamp
{
    public static string Format(DateTime moment) => $"{moment:t} {moment:d}";
}

// Stock shows no size refusal up to 512 MiB (probed 2026-09-15: 64/256/512
// MiB all open, no redirect dialog in stock 11.2607), so our 1 GiB cap is an
// engineering default, not parity: whole-file reads cannot pass 2 GiB, and a
// guessed stock limit would refuse files stock opens. Changing it costs one
// constant; tests pass small values.
public sealed record OpenOptions(long MaxBytes, string LogTimestamp)
{
    public const long DefaultMaxBytes = 1024L * 1024 * 1024;

    public long ProgressThresholdBytes { get; init; } = FileOpen.DefaultProgressThresholdBytes;
}

public enum OpenFailure
{
    NotFound,
    Locked,
    Unreadable,
    TooLarge,
}

public abstract record OpenResult;

public sealed record OpenSuccess(string Text, string EncodingName, bool HasBom, LineEndingInfo LineEnding) : OpenResult;

public sealed record OpenFailureResult(OpenFailure Failure, string? Detail = null) : OpenResult;

// Failure and notice strings, owned by D01 T01 §4 items 2 and 8. The
// missing and locked wordings are stock-verbatim (captures
// `notepad-fail-missing/locked-n11.2607.14.0-win25h2.png`); the dialog
// title is stock "Notepad" per the stamped §3 prompt precedent. Unreadable
// shows the live OS message carried in OpenFailureResult.Detail; the
// fallback covers direct MapFailure consumers only. The too-large wording
// is ours (stock refuses nothing up to 512 MiB). The app renders these in
// an OK-only dialog when the D01 T02 §1 trigger lands.
public static class OpenMessages
{
    public const string DialogTitle = "Notepad";

    public const string NotFoundText = "The system cannot find the path specified.";

    public const string LockedText = "The process cannot access the file because it is being used by another process.";

    public const string TooLargeText = "The file is too large to open.";

    public const string UnreadableFallbackText = "Access is denied.";

    public static string MessageFor(OpenFailure failure, string? detail = null) => failure switch
    {
        OpenFailure.NotFound => NotFoundText,
        OpenFailure.Locked => LockedText,
        OpenFailure.TooLarge => TooLargeText,
        OpenFailure.Unreadable => string.IsNullOrEmpty(detail) ? UnreadableFallbackText : detail,
        _ => throw new ArgumentOutOfRangeException(nameof(failure)),
    };
}

// Open dialog defaults, owned by D01 T01 §4 item 7. Stock's type dropdown
// defaults to "Text documents (*.txt)" with an all-files switch and
// Encoding "Auto-Detect" (capture
// `notepad-open-dialog-n11.2607.14.0-win25h2.png`); we always auto-detect,
// so the spec is the filter list only, first entry default. Explicit
// encoding is D01 T01 §29. Applied to the picker by the D01 T02 §1 trigger.
public static class OpenDialogDefaults
{
    public static IReadOnlyList<string> FileTypeFilter { get; } = [".txt", "*"];
}

public sealed record DetectedFile(string Text, string EncodingName, bool HasBom, LineEndingInfo LineEnding);

public sealed record LineEndingInfo(int Crlf, int Lf, int Cr, string Dominant);
