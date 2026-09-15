namespace Notepad.Core;

// External-change detection, owned by D01 T01 §4 item 3 (neutral half). Wraps
// FileSystemWatcher and raises Changed when the watched file is written,
// renamed, or deleted; the reload prompt itself is app UI (bedtime).
public sealed class FileWatcher : IDisposable
{
    private readonly FileSystemWatcher watcher;
    private bool disposed;

    public event EventHandler? Changed;

    public FileWatcher(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        string full = Path.GetFullPath(path);
        watcher = new FileSystemWatcher(Path.GetDirectoryName(full)!, Path.GetFileName(full))
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
            EnableRaisingEvents = true,
        };
        watcher.Changed += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
        watcher.Renamed += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
        watcher.Deleted += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        if (!disposed)
        {
            disposed = true;
            watcher.Dispose();
        }
    }
}
