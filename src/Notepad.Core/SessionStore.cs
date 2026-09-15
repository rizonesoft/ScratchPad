using System.Text.Json;

namespace Notepad.Core;

// Session and recent-files persistence, owned by D01 T01 §6. Every rule here
// was recorded live from stock Notepad 11.2607.14.0 (captures in
// `resources/baseline/session/`, probe transcripts in the §6 review):
//
// - Quit (last-window close) snapshots everything with no prompts: all tabs,
//   their carets, and unsaved plus dirty buffers. Relaunch restores all four.
// - Closing a non-last window drops its tabs silently (clean) or after the
//   §7 dirty prompt; nothing merges into survivors (probed s2merge: the
//   survivor kept only its own tab and the relaunch showed just it).
// - Carets restore exactly (probed 27 to 27 twice, plus Ln 5, Col 3 visible
//   in the restored capture); the active tab restores (probed s2l2).
// - Window geometry does NOT restore (two clean negatives); the session
//   stores no rects and restore skips geometry.
// - Recents record on TAB close only (decisive s2m1: open records nothing,
//   window close records nothing, tab close records immediately), newest
//   first, capped at 10 with oldest evicted (s2m2), cleared without confirm
//   by the "Clear list" entry while the Recent item itself stays.
// - A session tab whose file is missing resurrects as an empty tab; the
//   "Cannot find the {path} file." OK notice fires lazily on activation,
//   the tab survives OK, and the next snapshot drops it (probed s2missing).
public sealed class SessionData
{
    public List<SessionWindow> Windows { get; set; } = new();

    // Index into Windows of the window to activate. Only the last close
    // knows it for certain (the closing window was active); intermediate
    // snapshots carry the previous value clamped. Crash-exactness arrives
    // with the §7 continuous checkpoint.
    public int ActiveWindow { get; set; }

    // A session holding nothing but one empty untitled tab carries no state
    // worth keeping: snapshots skip writing it (quit stays file-clean and
    // geometry restores across the relaunch), and launch treats a stale one
    // as no session. Anything else, even one empty tab beside a file tab,
    // persists and restores (the empty tab is window state there).
    public bool IsTrivial =>
        Windows.Count == 1
        && Windows[0].Tabs.Count == 1
        && Windows[0].Tabs[0].Path is null
        && string.IsNullOrEmpty(Windows[0].Tabs[0].Content);

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IntelligentNotepad", "session.json");

    public static SessionData Load() => LoadFrom(FilePath);

    public static SessionData LoadFrom(string path)
    {
        try
        {
            SessionData? data = JsonSerializer.Deserialize<SessionData>(File.ReadAllText(path));
            if (data is null)
            {
                return new SessionData();
            }

            data.Windows ??= new List<SessionWindow>();
            // Hand-edited sessions can null anything nullable in JSON; every
            // null below once threw out of launch (review round 1).
            data.Windows = data.Windows.Where(w => w is not null).ToList();
            foreach (SessionWindow window in data.Windows)
            {
                window.Tabs ??= new List<SessionTab>();
                window.Tabs = window.Tabs.Where(t => t is not null).ToList();
                foreach (SessionTab tab in window.Tabs)
                {
                    tab.Encoding ??= "UTF-8";
                    tab.LineEnding ??= "CRLF";
                }
            }

            return data;
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new SessionData();
        }
    }

    public void Save() => SaveTo(FilePath);

    public void SaveTo(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this));
        File.Move(temp, path, overwrite: true);
    }

    // Fresh-start mode discards the session on quit (recorded default: the
    // stock label is "Start new session and discard unsaved changes", and
    // flipping back to continue must not resurrect. Cost of changing: keep
    // the file and flip-back restores the pre-fresh session instead).
    public static void Delete()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                File.Delete(FilePath);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            System.Diagnostics.Debug.WriteLine($"Session delete skipped: {ex.Message}");
        }
    }
}

public sealed class SessionWindow
{
    public List<SessionTab> Tabs { get; set; } = new();

    public int Active { get; set; }
}

// Privacy review, D01 T01 §6 item 5: the store format names every field.
// Persisted per tab: Path (absolute file path, null for untitled), Content
// (full buffer text for dirty or untitled tabs, null for clean file tabs
// which reload from disk), Caret (UTF-16 offset), Encoding (name, used when
// Content is present so saves round-trip), HasBom, LineEnding. Per window:
// the ordered tab list plus Active (tab index). Global: ActiveWindow. No
// rects (stock does not restore geometry). The file lives at
// %LocalAppData%\IntelligentNotepad\session.json, written atomically via
// temp-plus-move; it is never synced, never attached to telemetry, and never
// written to logs. Unsaved buffers exist on this disk only.
public sealed class SessionTab
{
    public string? Path { get; set; }

    public string? Content { get; set; }

    public int Caret { get; set; }

    public string Encoding { get; set; } = "UTF-8";

    public bool HasBom { get; set; }

    public string LineEnding { get; set; } = "CRLF";
}

// One tab's live state, handed to the capture rules. MainWindow builds it
// from the Tab plus its content box; tests build it by hand.
public sealed record TabSnapshot(
    string? Path,
    string? Content,
    int Caret,
    bool IsDirty,
    string Encoding,
    bool HasBom,
    string LineEnding);

// Pure snapshot rules, unit-driven. `exists` is File.Exists in the app.
public static class SessionCapture
{
    public static SessionWindow CaptureWindow(
        IReadOnlyList<TabSnapshot> tabs,
        int activeIndex,
        Func<string, bool> exists)
    {
        ArgumentNullException.ThrowIfNull(tabs);
        ArgumentNullException.ThrowIfNull(exists);
        var window = new SessionWindow();
        int active = 0;
        for (int i = 0; i < tabs.Count; i++)
        {
            TabSnapshot tab = tabs[i];
            if (tab.Path is not null && !tab.IsDirty && !exists(tab.Path))
            {
                // Clean tabs over missing files drop (probed s2missing: the
                // deleted file's tab never survives a second cycle).
                continue;
            }

            if (i == activeIndex)
            {
                active = window.Tabs.Count;
            }

            window.Tabs.Add(new SessionTab
            {
                Path = tab.Path,
                Content = tab.IsDirty || tab.Path is null ? tab.Content ?? string.Empty : null,
                Caret = Math.Max(0, tab.Caret),
                Encoding = tab.Encoding,
                HasBom = tab.HasBom,
                LineEnding = tab.LineEnding,
            });
        }

        window.Active = window.Tabs.Count == 0 ? 0 : Math.Clamp(active, 0, window.Tabs.Count - 1);
        return window;
    }
}

// Recent-files list behavior. Stored MRU-first on ShellSettings.RecentFiles
// (stock keeps it in settings.dat); the rendered submenu lands with D01
// T02 §1, which walks it there.
public static class RecentFiles
{
    // Probed s2m2: twelve tab closes leave the ten newest.
    public const int MaxCount = 10;

    // Records a tab close (probed s2m1: tab close is the only trigger; opens
    // and window closes record nothing). Recloses move to the front,
    // case-insensitively: Windows paths.
    public static void NoteClosed(List<string> recents, string? path)
    {
        if (recents is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        for (int i = recents.Count - 1; i >= 0; i--)
        {
            if (string.Equals(recents[i], path, StringComparison.OrdinalIgnoreCase))
            {
                recents.RemoveAt(i);
            }
        }

        recents.Insert(0, path);
        while (recents.Count > MaxCount)
        {
            recents.RemoveAt(recents.Count - 1);
        }
    }

    public static void Clear(List<string>? recents) => recents?.Clear();
}
