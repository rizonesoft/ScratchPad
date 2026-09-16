using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace IntelligentNotepad;

// Command-line and drop file opening, owned by D01 T01 §8. Typed paths
// (command line, double-click, redirect) answer a missing file with the
// stock create offer (Yes binds an empty tab to the path with bytes
// written on save; No skips); dropped items answer a missing file with
// the §4 NotFound notice instead (drops reference existing items, so a
// vanishing drop is an error, not an intent). Existing files open through
// the §4 engine with its failure dialogs rendered here for the first time
// (the D01 T02 §1 Open trigger reuses OpenFailureDialog). Directories
// silently skip in both entries (default; stock drop-a-folder is unprobed,
// cost one branch).
[System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1515", Justification = "Partial of the public WinUI window type; accessibility is fixed by the XAML code-behind half.")]
sealed partial class MainWindow
{
    internal async Task OpenFilesAsync(IReadOnlyList<string> files, bool offerCreate)
    {
        ArgumentNullException.ThrowIfNull(files);
        foreach (string path in files)
        {
            if (Directory.Exists(path))
            {
                continue;
            }

            if (!File.Exists(path))
            {
                if (offerCreate)
                {
                    await OfferCreateAsync(path).ConfigureAwait(true);
                }
                else
                {
                    await ShowFailureAsync(OpenFailure.NotFound).ConfigureAwait(true);
                }

                continue;
            }

            if (IsLockedFile(path))
            {
                await UnlockAndOpenAsync(path).ConfigureAwait(true);
                continue;
            }

            var options = new OpenOptions(OpenOptions.DefaultMaxBytes, LogTimestamp.Format(DateTime.Now));
            OpenResult result = await FileOpen.OpenFileAsync(path, options).ConfigureAwait(true);
            switch (result)
            {
                case OpenSuccess opened:
                    OpenDetected(path, opened);
                    break;
                case OpenFailureResult failed:
                    await ShowFailureAsync(failed.Failure, failed.Detail).ConfigureAwait(true);
                    break;
            }
        }
    }

    // D01 T01 §19: locked files detour through the unlock prompt before
    // any bytes render. The prompt retries in-dialog; Cancel skips the file
    // with no tab and nothing rendered.
    async Task<bool> UnlockAndOpenAsync(string path)
    {
        XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
        if (root is null)
        {
            return false;
        }

        var dialog = new UnlockDialog(Path.GetFileName(path), password => UnlockDetected(path, password)) { XamlRoot = root };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    void UnlockDetected(string path, string password)
    {
        DetectedFile detected = FileOpen.Detect(NoteCrypto.Unlock(File.ReadAllBytes(path), password));
        Tab tab = tabs.OpenTab(path, detected);
        tab.IsLocked = true;
        TextBox box = tabBar!.ContentFor(tab);
        box.Text = detected.Text;
        // D01 T01 §21: the unlocked encoding applies (without this a UTF-16
        // note silently re-locks as UTF-8); ApplySave also marks clean.
        tab.ApplySave(path, new SaveSpec(detected.EncodingName, detected.HasBom, detected.LineEnding.Dominant));
    }

    static bool IsLockedFile(string path)
    {
        try
        {
            byte[] prefix = new byte[NoteCrypto.Magic.Length + 1];
            using (FileStream stream = File.OpenRead(path))
            {
                if (stream.Read(prefix, 0, prefix.Length) < prefix.Length)
                {
                    return false;
                }
            }

            return NoteCrypto.IsLocked(prefix);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    void OpenDetected(string path, OpenSuccess opened)
    {
        var detected = new DetectedFile(opened.Text, opened.EncodingName, opened.HasBom, opened.LineEnding);
        Tab tab = tabs.OpenTab(path, detected);
        TextBox box = tabBar!.ContentFor(tab);
        box.Text = opened.Text;
        tab.MarkSaved();
    }

    async Task OfferCreateAsync(string path)
    {
        XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
        if (root is null)
        {
            return;
        }

        var dialog = new CreateFileDialog(path) { XamlRoot = root };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        var tab = new Tab { FilePath = path };
        tabs.Tabs.Add(tab);
        tabs.ActiveTab = tab;
        tabBar!.ContentFor(tab);
    }

    async Task ShowFailureAsync(OpenFailure failure, string? detail = null)
    {
        XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
        if (root is null)
        {
            return;
        }

        var dialog = new OpenFailureDialog(failure, detail) { XamlRoot = root };
        await dialog.ShowAsync();
    }

    // Startup opens fire before the window joins the visual tree, so
    // dialogs wait for a XamlRoot instead of skipping on first sight.
    async Task<XamlRoot?> WaitForXamlRootAsync()
    {
        for (int i = 0; i < 100 && Content?.XamlRoot is null; i++)
        {
            await Task.Delay(100).ConfigureAwait(true);
        }

        return Content?.XamlRoot;
    }

    // The §8 routed-new-window spare, captured right after NewWindow:
    // a lone Untitled is the fresh window's initial tab, anything else
    // means the window is lived-in and keeps every tab.
    internal Tab? CaptureSpareCandidate() =>
        tabs.Tabs.Count == 1 && tabs.Tabs[0].IsUntitled ? tabs.Tabs[0] : null;

    // D01 T01 §25 (/new-note): a fresh note is on screen and active. A
    // clean untitled tab already showing satisfies it (select, never
    // duplicate pristine emptiness); otherwise open one. Dirty untitled
    // tabs never count: the gesture must not hijack user content.
    internal void EnsureFreshNote()
    {
        Tab? spare = tabs.Tabs.FirstOrDefault(t => t.IsUntitled && !t.IsDirty);
        tabs.ActiveTab = spare ?? tabs.NewTab();
    }

    // Drops the spare once routed files land: the initial tab goes iff
    // it is still a clean Untitled and the window now holds more tabs
    // (skipped routes keep their usable window). Untitled-plus-clean
    // implies empty: only pathed tabs ever MarkSaved, and every box
    // edit dirties through NotifyEdited. Silent close: the tab never
    // held user content, so no prompt and no checkpoint special-case.
    internal async Task DropSpareUntitledAsync(Tab spare)
    {
        ArgumentNullException.ThrowIfNull(spare);
        if (tabBar is null || !spare.IsUntitled || spare.IsDirty || tabs.Tabs.Count < 2 || !tabs.Tabs.Contains(spare))
        {
            return;
        }

        await tabBar.RequestCloseAsync(spare).ConfigureAwait(true);
    }

    internal void WireFileDrops()
    {
        if (Content is UIElement root)
        {
            root.AllowDrop = true;
            root.DragOver += OnFilesDragOver;
            root.Drop += OnFilesDropped;
        }
    }

    void OnFilesDragOver(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            e.AcceptedOperation = DataPackageOperation.Copy;
        }
    }

    async void OnFilesDropped(object sender, DragEventArgs e)
    {
        try
        {
            IReadOnlyList<IStorageItem> items = await e.DataView.GetStorageItemsAsync();
            var paths = items.OfType<StorageFile>().Select(file => file.Path).ToList();
            if (paths.Count > 0)
            {
                await OpenFilesAsync(paths, offerCreate: false).ConfigureAwait(true);
            }
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or InvalidOperationException)
        {
            System.Diagnostics.Debug.WriteLine($"Drop open failed: {ex.Message}");
        }
    }
}
