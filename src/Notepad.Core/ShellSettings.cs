using System.Text.Json;

namespace Notepad.Core;

// Local persistence seam for shell state, owned by D01 T01 §1 and adopted by the
// D01 T02 §2 settings store when it lands: the store reads these keys (same file,
// same names) and takes over writes. Keys: window.x/y/width/height (int),
// app.theme ("system", "light", "dark"), whatsnew.seen (bool).
public sealed class ShellSettings
{
    public int X { get; set; } = 50;

    public int Y { get; set; } = 50;

    public int Width { get; set; } = 900;

    public int Height { get; set; } = 650;

    public string Theme { get; set; } = "system";

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
