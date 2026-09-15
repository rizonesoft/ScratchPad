using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

namespace Notepad.Core;

// Local persistence seam for shell state, owned by D01 T01 §1 (§9 adds
// openin.mode, §6 adds whenstarts.mode plus recentfiles, §8 adds
// pinnedfiles) and adopted by
// the D01 T02 §2 settings store when it lands: the store reads these keys
// (same file, same names) and takes over writes.
// Keys: window.x/y/width/height (int), app.theme ("system", "light",
// "dark"), whatsnew.seen (bool), openin.mode ("new-tab", "new-window"),
// whenstarts.mode ("continue", "fresh"), recentfiles (MRU-first paths),
// pinnedfiles (pinned-first paths, oldest first).
// jumplist.hash (feed fingerprint for commit-on-change).
public sealed class ShellSettings
{
    public int X { get; set; } = 50;

    public int Y { get; set; } = 50;

    public int Width { get; set; } = 900;

    public int Height { get; set; } = 650;

    public string Theme { get; set; } = "system";

    // Stock "Opening files" value, normalized through OpenInRouting: the
    // settings capture selects "Open in a new tab". The default matches the
    // capture; the fresh-install default is unconfirmed and costs one
    // string to change.
    public string OpenIn { get; set; } = OpenInRouting.NewTab;

    // Stock "When Notepad starts" value, normalized through
    // WhenStartsRouting. The default matches the fresh-install capture.
    public string WhenStarts { get; set; } = WhenStartsRouting.Continue;

    // Recent files, newest first, capped by RecentFiles.MaxCount. Appended
    // on tab close only (probed s2m1); the D01 T02 §1 submenu renders it.
    // JSON DTO: the setter serves deserialization; the List shape is the
    // reviewed settings format (same treatment as SessionData.Windows).
    [SuppressMessage("Design", "CA1002", Justification = "Settings JSON DTO; List is the reviewed store shape.")]
    [SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization.")]
    public List<string> RecentFiles { get; set; } = new();

    // Pinned files for the §8 jump list, oldest first, capped by
    // RecentFiles.MaxCount. Pins live here; the D01 T02 §1 recents submenu
    // renders the toggle that mutates them.
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1002", Justification = "Settings JSON DTO; List is the reviewed store shape.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization.")]
    public List<string> PinnedFiles { get; set; } = new();

    // Jump-list feed fingerprint, owned by D01 T01 §8: the service commits
    // only while the feed differs from this hash.
    public string JumpListHash { get; set; } = string.Empty;

    public bool WhatsNewSeen { get; set; }

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IntelligentNotepad", "settings.json");

    public static ShellSettings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<ShellSettings>(File.ReadAllText(FilePath)) ?? new ShellSettings();
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new ShellSettings();
        }
    }

    public void Save()
    {
        string path = FilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this));
        File.Move(temp, path, overwrite: true);
    }
}

// Pinned-file list behavior, owned by D01 T01 §13. Pins are oldest-first
// (pin order), uncapped (the jump-list feed caps at render), and
// case-insensitive (Windows paths). Untitled tabs have no path and never
// enter the list; their pins live in session.json only.
public static class PinnedFiles
{
    public static void NotePinned(IList<string> pinned, string? path)
    {
        if (pinned is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        foreach (string existing in pinned)
        {
            if (string.Equals(existing, path, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        pinned.Add(path);
    }

    public static void NoteUnpinned(IList<string> pinned, string? path)
    {
        if (pinned is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        for (int i = pinned.Count - 1; i >= 0; i--)
        {
            if (string.Equals(pinned[i], path, StringComparison.OrdinalIgnoreCase))
            {
                pinned.RemoveAt(i);
            }
        }
    }
}

