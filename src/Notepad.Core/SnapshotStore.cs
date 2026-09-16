using System.Globalization;
using System.Text.Json;

namespace Notepad.Core;

// Named local versions beside the file, owned by D01 T01 §16. UI-free: the
// versions dialog calls Take/List/ReadBytes and restores through FileOpen
// detection. Layout per file: `<filename>.snapshots/manifest.json` (nextId
// plus name/created/bytes/spec entries) with `snap-{id:0000}.bin` content
// files. Snapshot bytes are exactly what FileSave would write for the
// buffer under the tab's spec, so takes are byte-identical by construction.
public sealed record SnapshotEntry(int Id, string Name, DateTime CreatedUtc, long Bytes, string EncodingName, bool HasBom, string LineEnding);

public sealed class SnapshotManifest
{
    public int NextId { get; set; } = 1;

    [System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1002", Justification = "Manifest JSON DTO; List is the reviewed store shape.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization and null-scrubbing.")]
    public List<SnapshotEntry> Snapshots { get; set; } = new();
}

public static class SnapshotStore
{
    public const int MaxSnapshots = 10;
    public const int MaxNameLength = 80;

    public static string StoreDirFor(string filePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(filePath);
        return filePath + ".snapshots";
    }

    public static string SuggestName(DateTime momentUtc) =>
        momentUtc.ToUniversalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);

    public static IReadOnlyList<SnapshotEntry> List(string filePath)
    {
        (SnapshotManifest manifest, _) = Load(filePath);
        return manifest.Snapshots.ToList();
    }

    public static SnapshotEntry Take(string filePath, string name, string text, SaveSpec spec)
    {
        ArgumentException.ThrowIfNullOrEmpty(filePath);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(spec);
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ArgumentException("Snapshot name must not be empty.", nameof(name));
        }

        if (name.Length > MaxNameLength)
        {
            throw new ArgumentException($"Snapshot name exceeds {MaxNameLength} characters.", nameof(name));
        }

        (SnapshotManifest manifest, string dir) = Load(filePath);
        if (manifest.Snapshots.Any(entry => string.Equals(entry.Name, name, StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidOperationException($"A snapshot named '{name}' already exists.");
        }

        Directory.CreateDirectory(dir);
        int id = manifest.NextId++;
        string contentPath = ContentPath(dir, id);
        switch (FileSave.SaveFile(contentPath, text, spec))
        {
            case SaveSuccess:
                break;
            case SaveRedirect redirect:
                throw new IOException($"Snapshot write redirected: {redirect.Detail}");
            case SaveFailed failed:
                throw new IOException($"Snapshot write failed: {failed.Detail}");
            default:
                throw new IOException("Snapshot write failed.");
        }

        var entry = new SnapshotEntry(id, name, DateTime.UtcNow, new FileInfo(contentPath).Length, spec.EncodingName, spec.HasBom, spec.LineEnding);
        manifest.Snapshots.Add(entry);
        while (manifest.Snapshots.Count > MaxSnapshots)
        {
            SnapshotEntry oldest = manifest.Snapshots[0];
            manifest.Snapshots.RemoveAt(0);
            try
            {
                File.Delete(ContentPath(dir, oldest.Id));
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // The manifest is the source of truth; an orphan content
                // file is invisible and the next-Id scan heals around it.
                System.Diagnostics.Debug.WriteLine($"Snapshot evict left bytes: {ex.Message}");
            }
        }

        SaveManifest(dir, manifest);
        return entry;
    }

    public static byte[] ReadBytes(string filePath, int id)
    {
        (SnapshotManifest manifest, string dir) = Load(filePath);
        if (!manifest.Snapshots.Any(entry => entry.Id == id))
        {
            throw new FileNotFoundException($"No snapshot #{id} for '{filePath}'.");
        }

        return File.ReadAllBytes(ContentPath(dir, id));
    }

    static string ContentPath(string dir, int id) => Path.Combine(dir, $"snap-{id:0000}.bin");

    static (SnapshotManifest Manifest, string Dir) Load(string filePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(filePath);
        string dir = StoreDirFor(filePath);
        SnapshotManifest manifest = new();
        string manifestPath = Path.Combine(dir, "manifest.json");
        if (File.Exists(manifestPath))
        {
            try
            {
                manifest = JsonSerializer.Deserialize<SnapshotManifest>(File.ReadAllText(manifestPath)) ?? new();
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            {
                manifest = new();
            }
        }

        manifest.Snapshots ??= new List<SnapshotEntry>();
        manifest.Snapshots = manifest.Snapshots.Where(entry => entry is not null).ToList();

        // Heal: the sequence resumes past any content file on disk, so a
        // lost or hand-edited manifest never collides with existing bytes.
        int maxId = manifest.NextId - 1;
        if (Directory.Exists(dir))
        {
            foreach (string file in Directory.EnumerateFiles(dir, "snap-*.bin"))
            {
                string stem = Path.GetFileNameWithoutExtension(file);
                if (stem.StartsWith("snap-", StringComparison.Ordinal)
                    && int.TryParse(stem["snap-".Length..], CultureInfo.InvariantCulture, out int seen))
                {
                    maxId = Math.Max(maxId, seen);
                }
            }
        }

        manifest.NextId = Math.Max(manifest.NextId, maxId + 1);
        return (manifest, dir);
    }

    static void SaveManifest(string dir, SnapshotManifest manifest)
    {
        string path = Path.Combine(dir, "manifest.json");
        string temp = Path.Combine(dir, $"manifest-{Guid.NewGuid():N}.tmp");
        File.WriteAllText(temp, JsonSerializer.Serialize(manifest));
        File.Move(temp, path, overwrite: true);
    }
}
