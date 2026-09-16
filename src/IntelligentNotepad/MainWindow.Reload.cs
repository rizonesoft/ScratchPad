using System.Collections.Specialized;
using System.ComponentModel;
using System.Security.Cryptography;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// External-change reload prompts, owned by D01 T01 §21. One FileWatcher
// per pathed tab; our own commits baseline via FileSave.WroteFile so they
// never prompt, disk bytes matching the buffer auto-resolve clean, and
// anything else pends until window and tab are both active, then asks.
[System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1515", Justification = "Partial of the public WinUI window type; accessibility is fixed by the XAML code-behind half.")]
sealed partial class MainWindow
{
    readonly Dictionary<Guid, FileWatcher> reloadWatchers = new();
    readonly Dictionary<string, byte[]> reloadBaselines = new(StringComparer.OrdinalIgnoreCase);
    readonly HashSet<Guid> pendingReloads = [];
    readonly Dictionary<Guid, byte[]> reloadPendingHashes = new();
    bool reloadPromptOpen;
    bool windowActive = true;

    void StartReloadWatching()
    {
        tabs.Tabs.CollectionChanged += ReloadTabsChanged;
        foreach (Tab tab in tabs.Tabs)
        {
            WatchTab(tab);
        }

        Activated += OnActivatedForReload;
        FileSave.WroteFile += OnWroteFile;
    }

    void StopReloadWatching()
    {
        FileSave.WroteFile -= OnWroteFile;
        Activated -= OnActivatedForReload;
        tabs.Tabs.CollectionChanged -= ReloadTabsChanged;
        foreach (Tab tab in tabs.Tabs)
        {
            tab.PropertyChanged -= ReloadTabPropertyChanged;
        }

        foreach (FileWatcher watcher in reloadWatchers.Values)
        {
            watcher.Dispose();
        }

        reloadWatchers.Clear();
        pendingReloads.Clear();
        reloadPendingHashes.Clear();
        reloadBaselines.Clear();
    }

    void OnActivatedForReload(object sender, WindowActivatedEventArgs args)
    {
        // CI launches never take the foreground, so the window starts
        // logically active and only Deactivated clears it.
        windowActive = args.WindowActivationState != WindowActivationState.Deactivated;
        if (windowActive)
        {
            _ = CheckPendingReloadsAsync();
        }
    }

    void OnWroteFile(object? _, FileWroteEventArgs args)
    {
        string full;
        try
        {
            full = Path.GetFullPath(args.Path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or ArgumentException)
        {
            return;
        }

        reloadBaselines[full] = SHA256.HashData(args.Bytes);
        foreach (Tab tab in tabs.Tabs)
        {
            if (tab.FilePath is not null && string.Equals(FullPathOrEmpty(tab.FilePath), full, StringComparison.OrdinalIgnoreCase))
            {
                DropPending(tab.Id);
            }
        }
    }

    void ReloadTabsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems is not null)
        {
            foreach (Tab tab in e.OldItems)
            {
                UnwatchTab(tab);
            }
        }

        if (e.NewItems is not null)
        {
            foreach (Tab tab in e.NewItems)
            {
                WatchTab(tab);
            }
        }

        if (e.Action == NotifyCollectionChangedAction.Reset)
        {
            foreach (Tab tab in tabs.Tabs)
            {
                WatchTab(tab);
            }
        }
    }

    void ReloadTabPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is Tab tab && e.PropertyName == nameof(Tab.FilePath))
        {
            UnwatchTab(tab);
            WatchTab(tab);
        }
    }

    void WatchTab(Tab tab)
    {
        tab.PropertyChanged -= ReloadTabPropertyChanged;
        tab.PropertyChanged += ReloadTabPropertyChanged;
        if (tab.FilePath is null || reloadWatchers.ContainsKey(tab.Id))
        {
            return;
        }

        try
        {
            var watcher = new FileWatcher(tab.FilePath);
            Guid id = tab.Id;
            watcher.Changed += (_, _) => OnWatchedFileChanged(id);
            reloadWatchers[id] = watcher;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            System.Diagnostics.Debug.WriteLine($"Reload watch skipped: {ex.Message}");
        }
    }

    void DropPending(Guid id)
    {
        pendingReloads.Remove(id);
        reloadPendingHashes.Remove(id);
    }

    void UnwatchTab(Tab tab)
    {
        tab.PropertyChanged -= ReloadTabPropertyChanged;
        if (reloadWatchers.Remove(tab.Id, out FileWatcher? watcher))
        {
            watcher.Dispose();
        }

        DropPending(tab.Id);
    }

    void OnWatchedFileChanged(Guid id)
    {
        // FileSystemWatcher raises on a background thread; everything below
        // touches UI-bound state, so marshal home (dropped when closing).
        DispatcherQueue.TryEnqueue(() => ResolveWatcherEvent(id));
    }

    void ResolveWatcherEvent(Guid id)
    {
        Tab? tab = tabs.Tabs.FirstOrDefault(t => t.Id == id);
        if (tab?.FilePath is null || tabBar is null)
        {
            return;
        }

        byte[] disk;
        try
        {
            disk = File.ReadAllBytes(tab.FilePath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            pendingReloads.Add(id);
            _ = CheckPendingReloadsAsync();
            return;
        }

        byte[] hash = SHA256.HashData(disk);
        if (reloadBaselines.TryGetValue(FullPathOrEmpty(tab.FilePath), out byte[]? baseline) && hash.SequenceEqual(baseline))
        {
            return;
        }

        if (pendingReloads.Contains(id)
            && reloadPendingHashes.TryGetValue(id, out byte[]? asked) && hash.SequenceEqual(asked))
        {
            return;
        }

        if (DiskMatchesBuffer(tab, disk))
        {
            reloadBaselines[FullPathOrEmpty(tab.FilePath)] = hash;
            DropPending(id);
            tab.MarkSaved();
            return;
        }

        pendingReloads.Add(id);
        _ = CheckPendingReloadsAsync();
    }

    bool DiskMatchesBuffer(Tab tab, byte[] disk)
    {
        if (tabBar is null || tab.FilePath is null)
        {
            return false;
        }

        string buffer = tabBar.ContentFor(tab).Text ?? string.Empty;
        byte[] encoded;
        try
        {
            encoded = FileSave.Encode(buffer, tab.Encoding, tab.HasBom, tab.LineEnding);
        }
        catch (Exception ex) when (ex is EncoderFallbackException or ArgumentException)
        {
            return false;
        }

        return SHA256.HashData(encoded).AsSpan().SequenceEqual(SHA256.HashData(disk));
    }

    async Task CheckPendingReloadsAsync()
    {
        if (reloadPromptOpen || Content?.XamlRoot is not XamlRoot root || !windowActive)
        {
            return;
        }

        reloadPromptOpen = true;
        try
        {
            Tab? active = tabs.ActiveTab;
            while (active?.FilePath is not null && pendingReloads.Contains(active.Id))
            {
                byte[] disk;
                try
                {
                    disk = await File.ReadAllBytesAsync(active.FilePath).ConfigureAwait(true);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    disk = [];
                }

                if (disk.Length > 0 && DiskMatchesBuffer(active, disk))
                {
                    DropPending(active.Id);
                    reloadBaselines[FullPathOrEmpty(active.FilePath)] = SHA256.HashData(disk);
                    active.MarkSaved();
                    active = tabs.ActiveTab;
                    continue;
                }

                reloadPendingHashes[active.Id] = SHA256.HashData(disk);
                var dialog = new ReloadDialog(Path.GetFileName(active.FilePath), active.IsDirty) { XamlRoot = root };
                ContentDialogResult answer = await dialog.ShowAsync();
                DropPending(active.Id);
                if (answer == ContentDialogResult.Primary)
                {
                    await ReloadTabAsync(active).ConfigureAwait(true);
                }
                else
                {
                    KeepTab(active);
                }

                active = tabs.ActiveTab;
            }
        }
        finally
        {
            reloadPromptOpen = false;
        }

        // A switch or event that landed while the flag was held gets one
        // more pass; the guard below (not the finally) owns the recursion,
        // so an idle window terminates instead of overflowing the stack.
        if (windowActive && Content?.XamlRoot is not null
            && tabs.ActiveTab is Tab next && next.FilePath is not null && pendingReloads.Contains(next.Id))
        {
            _ = CheckPendingReloadsAsync();
        }
    }

    async Task ReloadTabAsync(Tab tab)
    {
        if (tab.FilePath is null || tabBar is null)
        {
            return;
        }

        byte[] disk;
        try
        {
            disk = await File.ReadAllBytesAsync(tab.FilePath).ConfigureAwait(true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            if (Content?.XamlRoot is XamlRoot root)
            {
                await new MissingFileDialog(tab.FilePath) { XamlRoot = root }.ShowAsync();
            }

            KeepTab(tab);
            return;
        }

        if (NoteCrypto.IsLocked(disk))
        {
            if (await UnlockAndOpenAsync(tab.FilePath).ConfigureAwait(true))
            {
                reloadBaselines[FullPathOrEmpty(tab.FilePath)] = SHA256.HashData(disk);
            }
            else
            {
                KeepTab(tab);
            }

            return;
        }

        DetectedFile detected = FileOpen.Detect(disk);
        tabBar.SetBoxText(tab, detected.Text);
        tab.ApplySave(tab.FilePath, new SaveSpec(detected.EncodingName, detected.HasBom, detected.LineEnding.Dominant));
        reloadBaselines[FullPathOrEmpty(tab.FilePath)] = SHA256.HashData(disk);
    }

    void KeepTab(Tab tab)
    {
        if (tab.FilePath is null || tabBar is null)
        {
            return;
        }

        try
        {
            reloadBaselines[FullPathOrEmpty(tab.FilePath)] = SHA256.HashData(File.ReadAllBytes(tab.FilePath));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            reloadBaselines.Remove(FullPathOrEmpty(tab.FilePath));
        }

        tab.NotifyEdited(tabBar.ContentFor(tab).Text ?? string.Empty);
    }

    static string FullPathOrEmpty(string path)
    {
        try
        {
            return Path.GetFullPath(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or ArgumentException)
        {
            return string.Empty;
        }
    }
}
