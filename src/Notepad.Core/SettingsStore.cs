using System.Text.Json;

namespace Notepad.Core;

// The single-writer settings store, owned by D01 T02 §2. It adopts the
// ShellSettings keys (same file, same JSON names) and owns the only file
// write: every mutation flows through Update, every persist through
// WriteSnapshot (which ShellSettings.Save delegates to, so test seeding
// keeps working). Reads are live: Current is replaced on every Update and
// Changed fires after every successful persist, so readers must re-read
// rather than hold the reference. Update reloads the file first (external
// changes merge) and rolls Current back to the file when the persist
// throws, so memory always mirrors load-or-last-persist. UI-thread
// affinity is assumed (the app mutates from the dispatcher only);
// reentrant Updates from inside Changed throw rather than nest.
//
// Versions: v0 is the unversioned file §2 inherited; v1 stamps Version and
// carries every v0 key forward unchanged. Migration runs in memory and
// persists lazily on the next Update. A file that exists but does not
// parse, deserializes to null, or claims a future version resets to
// defaults with WasResetFromCorrupt set (the app surfaces the notice
// once); a missing file means a fresh install and resets silently. Read
// IO failures also fall back silently, exactly as ShellSettings.Load did
// before §2. Unknown JSON keys round-trip untouched (JsonExtensionData),
// which is how later AI settings land without a store redesign.
public sealed class SettingsStore
{
    public const int CurrentVersion = 1;

    static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
    };

    readonly string path;
    bool notifying;

    public SettingsStore(string? path = null)
    {
        this.path = path ?? ShellSettings.FilePath;
        (ShellSettings loaded, bool reset) = LoadFrom(this.path);
        Current = loaded;
        WasResetFromCorrupt = reset;
    }

    public static SettingsStore Shared { get; } = new SettingsStore();

    public ShellSettings Current { get; private set; }

    public bool WasResetFromCorrupt { get; }

    public event EventHandler? Changed;

    public void Update(Action<ShellSettings> mutate)
    {
        ArgumentNullException.ThrowIfNull(mutate);
        if (notifying)
        {
            throw new InvalidOperationException("SettingsStore.Update must not reenter from inside Changed.");
        }

        // Reload first: out-of-band file changes (tests seeding mid-run, a
        // redirecting sibling) merge instead of being clobbered by a stale
        // snapshot. A corrupt file at Update time resets silently and the
        // persist below self-heals it; the notice is a startup concern only.
        Current = LoadFrom(path).Settings;
        mutate(Current);
        Current.Version = CurrentVersion;
        try
        {
            WriteSnapshot(Current, path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Current = LoadFrom(path).Settings;
            throw;
        }

        notifying = true;
        try
        {
            Changed?.Invoke(this, EventArgs.Empty);
        }
        finally
        {
            notifying = false;
        }
    }

    public static void WriteSnapshot(ShellSettings settings, string? path = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        string target = path ?? ShellSettings.FilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        string temp = target + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(settings, JsonOptions));
        File.Move(temp, target, overwrite: true);
    }

    internal static (ShellSettings Settings, bool WasReset) LoadFrom(string path)
    {
        // In-memory results always report the current version: a fresh or
        // reset object has nothing to migrate, and a v0 file migrates here.
        // Only the file on disk can lag, until the next Update persists.
        ShellSettings? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<ShellSettings>(File.ReadAllText(path));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return (new ShellSettings { Version = CurrentVersion }, false);
        }
        catch (JsonException)
        {
            return (new ShellSettings { Version = CurrentVersion }, true);
        }

        if (parsed is null)
        {
            return (new ShellSettings { Version = CurrentVersion }, true);
        }

        if (parsed.Version > CurrentVersion)
        {
            return (new ShellSettings { Version = CurrentVersion }, true);
        }

        parsed.Version = CurrentVersion;
        return (parsed, false);
    }
}
