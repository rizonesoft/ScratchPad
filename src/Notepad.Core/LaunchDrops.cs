using System.Text.Json;

namespace Notepad.Core;

// Cross-process launch-file drops, owned by D01 T01 §8. Unpackaged
// activation carries no payload (probed: the redirected file never
// arrives, only the signal), so a secondary instance files its paths here
// before redirecting and the primary drains them on Activated. Each drop
// is one GUID-named JSON file written temp-plus-move (readers see whole
// files only); poison drops delete unread. Bare launches file an empty
// list, which reads as "open a window". D01 T01 §25 adds the new-note
// flag (default false, so pre-flag JSON still parses).
public sealed record LaunchDrop(IReadOnlyList<string> Files, bool NewNote = false);

public static class LaunchDrops
{
    public static string DirectoryPath => Path.Combine(AppDataDir.Root, "launch-drops");

    public static void Write(IReadOnlyList<string> files, string? directory = null, bool newNote = false)
    {
        ArgumentNullException.ThrowIfNull(files);
        string dir = directory ?? DirectoryPath;
        Directory.CreateDirectory(dir);
        string temp = Path.Combine(dir, Guid.NewGuid() + ".tmp");
        string target = Path.ChangeExtension(temp, ".json");
        File.WriteAllText(temp, JsonSerializer.Serialize(new LaunchDrop(files, newNote)));
        File.Move(temp, target);
    }

    // Drains every drop, oldest first, deleting each whether or not it
    // parses. Returns the concatenated file lists.
    public static IReadOnlyList<string> Drain(string? directory = null) =>
        DrainAll(directory).SelectMany(drop => drop.Files).ToList();

    // Full drain: drops with their flags, oldest first. Drain() is the
    // files-only projection; both delete every drop they read.
    public static IReadOnlyList<LaunchDrop> DrainAll(string? directory = null)
    {
        string dir = directory ?? DirectoryPath;
        var drops = new List<LaunchDrop>();
        string[] paths;
        try
        {
            paths = Directory.Exists(dir) ? Directory.GetFiles(dir, "*.json") : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return drops;
        }

        Array.Sort(paths, StringComparer.Ordinal);
        foreach (string path in paths)
        {
            try
            {
                LaunchDrop? parsed = JsonSerializer.Deserialize<LaunchDrop>(File.ReadAllText(path));
                if (parsed?.Files is not null)
                {
                    drops.Add(parsed);
                }
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            {
                // Poison: fall through to delete.
            }

            try
            {
                File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Already drained by a racing primary; the files were read.
            }
        }

        return drops;
    }
}
