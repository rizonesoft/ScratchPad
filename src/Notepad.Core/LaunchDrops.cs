using System.Text.Json;

namespace Notepad.Core;

// Cross-process launch-file drops, owned by D01 T01 §8. Unpackaged
// activation carries no payload (probed: the redirected file never
// arrives, only the signal), so a secondary instance files its paths here
// before redirecting and the primary drains them on Activated. Each drop
// is one GUID-named JSON file written temp-plus-move (readers see whole
// files only); poison drops delete unread. Bare launches file an empty
// list, which reads as "open a window".
public sealed record LaunchDrop(IReadOnlyList<string> Files);

public static class LaunchDrops
{
    public static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IntelligentNotepad", "launch-drops");

    public static void Write(IReadOnlyList<string> files, string? directory = null)
    {
        ArgumentNullException.ThrowIfNull(files);
        string dir = directory ?? DirectoryPath;
        Directory.CreateDirectory(dir);
        string temp = Path.Combine(dir, Guid.NewGuid() + ".tmp");
        string target = Path.ChangeExtension(temp, ".json");
        File.WriteAllText(temp, JsonSerializer.Serialize(new LaunchDrop(files)));
        File.Move(temp, target);
    }

    // Drains every drop, oldest first, deleting each whether or not it
    // parses. Returns the concatenated file lists.
    public static IReadOnlyList<string> Drain(string? directory = null)
    {
        string dir = directory ?? DirectoryPath;
        var files = new List<string>();
        string[] drops;
        try
        {
            drops = Directory.Exists(dir) ? Directory.GetFiles(dir, "*.json") : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return files;
        }

        Array.Sort(drops, StringComparer.Ordinal);
        foreach (string drop in drops)
        {
            try
            {
                LaunchDrop? parsed = JsonSerializer.Deserialize<LaunchDrop>(File.ReadAllText(drop));
                if (parsed?.Files is not null)
                {
                    files.AddRange(parsed.Files);
                }
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            {
                // Poison: fall through to delete.
            }

            try
            {
                File.Delete(drop);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Already drained by a racing primary; the files were read.
            }
        }

        return files;
    }
}
