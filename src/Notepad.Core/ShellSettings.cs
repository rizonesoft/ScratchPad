using System.Text.Json;

namespace Notepad.Core;

// Local persistence seam for shell state, owned by D01 T01 §1 (§9 adds
// openin.mode, §6 adds whenstarts.mode plus recentfiles) and adopted by
// the D01 T02 §2 settings store when it lands: the store reads these keys
// (same file, same names) and takes over writes.
// Keys: window.x/y/width/height (int), app.theme ("system", "light",
// "dark"), whatsnew.seen (bool), openin.mode ("new-tab", "new-window"),
// whenstarts.mode ("continue", "fresh"), recentfiles (MRU-first paths).
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
    public List<string> RecentFiles { get; set; } = new();

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
