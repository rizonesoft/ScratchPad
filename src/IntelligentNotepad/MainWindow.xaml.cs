using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Notepad.Core;
using Windows.Foundation;
using Windows.Graphics;
using Windows.System;
using WinRT.Interop;

namespace IntelligentNotepad;

public sealed partial class MainWindow : Window, IDisposable
{
    private const string AppName = "Intelligent Notepad";

    private readonly ShellSettings settings = ShellSettings.Load();

    private readonly TabModel tabs = new();

    private TabBar? tabBar;
    bool statsDialogOpen;
    bool snapshotsDialogOpen;
    bool templatesDialogOpen;

    private MiddleClickHook? middleClick;

    private bool closed;

    // firstWindow selects first-launch behavior: only the first window of the
    // process restores persisted geometry and may show first-run (D01 T01
    // §9); later windows open at the OS default cascade like stock's.
    private readonly bool firstWindow;

    // Tabs restored over missing files, owed the lazy "Cannot find" notice
    // on first activation (D01 T01 §6). Once per tab instance.
    private readonly HashSet<Guid> missingNotice = new();

    public MainWindow(bool firstWindow, SessionWindow? restore = null)
    {
        this.firstWindow = firstWindow;
        InitializeComponent();
        Title = WindowTitle.Format("Untitled", false, AppName);
        ExtendsContentIntoTitleBar = true;
        tabBar = new TabBar { Model = tabs };
        WireFileDrops();
        // Crash checkpoint feed (D01 T01 §7): every box edit restarts
        // the App debounce, so a kill restores seconds-old buffers.
        tabBar.TabsEdited += (_, _) =>
        {
            if (Application.Current is App app)
            {
                app.NotifyTabsEdited();
            }
        };
        // D01 T01 §13: pin toggles re-commit the jump list (pins feed it).
        tabBar.PinToggled += (_, _) => App.RefreshJumpList();

        // The HWND is not valid in the constructor; installing here silently
        // subclasses nothing. First activation owns the install.
        Activated += OnFirstActivated;
        TabRegion.Content = tabBar;
        // Layout passes also fire during teardown, when transforms and the
        // AppWindow are half-disconnected; touching them stows a crash
        // (0xC000027B). The closed flag parks this handler for those passes.
        tabBar.LayoutUpdated += (_, _) =>
        {
            if (closed)
            {
                return;
            }

            tabBar.ShrinkTabsToFit();
            UpdateDragRects();
            UpdateMiddleClickStrip();
        };
        tabs.PropertyChanged += Tabs_PropertyChanged;
        tabs.Tabs.CollectionChanged += Tabs_CollectionChanged;
        if (restore is null)
        {
            tabs.NewTab();
        }
        else
        {
            RestoreSessionWindow(restore);
        }
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = settings.Theme switch
            {
                "light" => ElementTheme.Light,
                "dark" => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
            AddTabAccelerators(root, tabBar);
            AddAccel(root, VirtualKey.N, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, OpenNewWindow);
            // D01 T01 §14: stats panel. Ctrl+Shift+G is free in-tree with no
            // stock meaning; the menu trigger is deferred to D01 T02 §1.
            AddAccel(root, VirtualKey.G, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => { _ = ShowStatsPanelAsync(); });
            // D01 T01 §16: file snapshots. Ctrl+Shift+H is free in-tree
            // (H for history); the menu trigger is deferred to D01 T02 §1.
            AddAccel(root, VirtualKey.H, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => { _ = ShowSnapshotsPanelAsync(); });
            // D01 T01 §17: new-from-template picker. Ctrl+Shift+E is free
            // in-tree (T taken by new-tab/reopen, E for tEmplate); the menu
            // trigger is deferred to D01 T02 §1.
            AddAccel(root, VirtualKey.E, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => { _ = ShowTemplatesPanelAsync(); });
            // Loaded, not Activated: first-run must show even when the window
            // opens behind others (CI launches never take the foreground).
            root.Loaded += OnFirstLoaded;
        }

        // Restored sessions skip geometry: stock reopens session windows at
        // its default positions, never where they were (two clean negatives).
        if (firstWindow && restore is null)
        {
            RestoreGeometry();
        }

        Closed += OnClosed;
    }

    // Ctrl+Shift+N, recorded live from Notepad (D01 T01 §9): a same-size
    // window at the OS cascade with one untitled tab.
    private static void OpenNewWindow()
    {
        if (Application.Current is App app)
        {
            app.NewWindow();
        }
    }

    // Tab shortcuts, recorded live from Notepad (D01 T01 §3): Ctrl+T new,
    // Ctrl+W close, Ctrl+Tab / Ctrl+Shift+Tab cycle, Ctrl+1..8 positional,
    // Ctrl+9 last, Ctrl+Shift+T reopen. Main number row only; NumPad parity
    // is unprobed. Attached to the root so they fire from any focus.
    private static void AddTabAccelerators(UIElement scope, TabBar bar)
    {
        AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control, bar.NewTab);
        AddAccel(scope, VirtualKey.W, VirtualKeyModifiers.Control, bar.RequestCloseActive);
        AddAccel(scope, VirtualKey.Tab, VirtualKeyModifiers.Control, bar.CycleNext);
        AddAccel(scope, VirtualKey.Tab, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, bar.CyclePrevious);
        AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, bar.ReopenLast);
        for (int number = 1; number <= 9; number++)
        {
            int captured = number;
            AddAccel(scope, (VirtualKey)(0x30 + captured), VirtualKeyModifiers.Control, () => bar.GotoNumber(captured));
        }
    }

    private static void AddAccel(UIElement scope, VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accel = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accel.Invoked += (_, args) =>
        {
            action();
            args.Handled = true;
        };
        scope.KeyboardAccelerators.Add(accel);
    }

    private void Tabs_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(TabModel.ActiveTab))
        {
            ShowActiveTab();
            UpdateTitle();
            // The lazy missing notice: owed once per restored-missing tab, on
            // first activation (stock shows it then, never at restore). If the
            // tree is not visual yet the flag stays for the next activation.
            if (tabs.ActiveTab is Tab now && now.FilePath is not null
                && missingNotice.Contains(now.Id) && !File.Exists(now.FilePath))
            {
                _ = ShowMissingNoticeAsync(now);
            }
        }
    }

    private async Task ShowMissingNoticeAsync(Tab tab)
    {
        if (tab.FilePath is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        missingNotice.Remove(tab.Id);
        try
        {
            var dialog = new MissingFileDialog(tab.FilePath) { XamlRoot = xamlRoot };
            await dialog.ShowAsync();
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            // The tree died between the check and the show (window closed
            // under the notice). Once-semantics already consumed; no retry.
            Debug.WriteLine($"Missing notice skipped: {ex.Message}");
        }
    }

    // Rebuilds this window's tabs from a session record (D01 T01 §6), in
    // order with the recorded active tab, contents, and carets. Clean file
    // tabs reload from disk; dirty and untitled tabs take the recorded
    // buffer; missing files resurrect as empty tabs owed the lazy notice.
    private void RestoreSessionWindow(SessionWindow record)
    {
        ArgumentNullException.ThrowIfNull(record);
        if (tabBar is null)
        {
            tabs.NewTab();
            return;
        }

        foreach (SessionTab saved in record.Tabs)
        {
            if (saved.Path is not null && saved.Content is null)
            {
                RestoreCleanFileTab(saved);
            }
            else
            {
                RestoreBufferTab(saved);
            }
        }

        if (tabs.Tabs.Count == 0)
        {
            tabs.NewTab();
        }
        else
        {
            tabs.ActiveTab = tabs.Tabs[Math.Clamp(record.Active, 0, tabs.Tabs.Count - 1)];
        }
    }

    private void RestoreCleanFileTab(SessionTab saved)
    {
        string path = saved.Path!;
        if (TryDetectFile(path) is not DetectedFile detected)
        {
            // Flag after activating: the build-time activation must not raise
            // the notice; only the final active tab (or a later click) does.
            var ghost = new Tab { FilePath = path, IsPinned = saved.IsPinned };
            tabs.Tabs.Add(ghost);
            tabs.ActiveTab = ghost;
            missingNotice.Add(ghost.Id);
            return;
        }

        Tab tab = tabs.OpenTab(path, detected);
        tab.IsPinned = saved.IsPinned;
        TextBox box = tabBar!.ContentFor(tab);
        box.Text = detected.Text;
        // Explicit: programmatic Text sets on pre-show boxes do not reliably
        // raise TextChanged (observed: restored untitled tabs kept a clean
        // model under filled boxes), so restore notifies directly instead of
        // depending on the event. Duplicate calls are safe (same content).
        tab.NotifyEdited(detected.Text);
        tab.MarkSaved();
        box.SelectionStart = Math.Min(Math.Max(0, saved.Caret), box.Text.Length);
    }

    private void RestoreBufferTab(SessionTab saved)
    {
        string content = saved.Content ?? string.Empty;
        Tab tab;
        if (saved.Path is null)
        {
            tab = tabs.NewTab();
            tab.IsPinned = saved.IsPinned;
        }
        else
        {
            tab = new Tab
            {
                FilePath = saved.Path,
                Encoding = saved.Encoding,
                HasBom = saved.HasBom,
                LineEnding = saved.LineEnding,
                IsPinned = saved.IsPinned,
            };
            tabs.Tabs.Add(tab);
            tabs.ActiveTab = tab;
            if (!File.Exists(saved.Path))
            {
                missingNotice.Add(tab.Id);
            }
        }

        TextBox box = tabBar!.ContentFor(tab);
        box.Text = content;
        // Explicit for the same pre-show reason as the clean-file path: the
        // model must match the filled box even if TextChanged never fires.
        tab.NotifyEdited(content);
        box.SelectionStart = Math.Min(Math.Max(0, saved.Caret), box.Text.Length);
    }

    // Sync open for restore: the window appears with its tabs, like stock.
    // NotFound (including Exists-then-deleted races) means missing; other
    // failures degrade to an empty kept tab with no notice, recoverable via
    // reopen once §8/T02 land (recorded default; cost: a failure notice).
    static DetectedFile? TryDetectFile(string path)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > int.MaxValue)
            {
                return null;
            }

            return FileOpen.Detect(File.ReadAllBytes(path));
        }
        catch (Exception ex) when (FileOpen.MapFailure(ex) is not null)
        {
            return null;
        }
        catch (OutOfMemoryException)
        {
            // A giant file must degrade to a ghost tab, never brick launch:
            // the session persists, so a throw here would crash every start.
            return null;
        }
    }

    // The session record for this window's live tabs, read by App on close.
    internal SessionWindow CaptureSessionWindow()
    {
        var snapshots = new List<TabSnapshot>(tabs.Tabs.Count);
        foreach (Tab tab in tabs.Tabs)
        {
            string? content = null;
            int caret = 0;
            if (tabBar is not null)
            {
                TextBox box = tabBar.ContentFor(tab);
                content = box.Text;
                caret = box.SelectionStart;
            }

            snapshots.Add(new TabSnapshot(
                tab.FilePath, content, caret, tab.IsDirty, tab.Encoding, tab.HasBom, tab.LineEnding, tab.IsPinned));
        }

        int active = tabs.ActiveTab is null ? 0 : tabs.Tabs.IndexOf(tabs.ActiveTab);
        return SessionCapture.CaptureWindow(snapshots, active, File.Exists);
    }

    private void Tabs_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems is not null)
        {
            foreach (Tab tab in e.OldItems)
            {
                tab.PropertyChanged -= ActiveTab_PropertyChanged;
                missingNotice.Remove(tab.Id);
                // Recents record tab closes only (probed s2m1). Window teardown
                // removes no tabs, so closes-with-the-window stay unrecorded,
                // like stock. Merged onto fresh settings like geometry: every
                // window tab-closes against the same file.
                if (tab.FilePath is not null)
                {
                    ShellSettings fresh = ShellSettings.Load();
                    RecentFiles.NoteClosed(fresh.RecentFiles, tab.FilePath);
                    fresh.Save();
                    App.RefreshJumpList();
                }
            }
        }

        if (e.NewItems is not null)
        {
            foreach (Tab tab in e.NewItems)
            {
                tab.PropertyChanged += ActiveTab_PropertyChanged;
            }
        }
    }

    private void ActiveTab_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is Tab tab && ReferenceEquals(tab, tabs.ActiveTab)
            && e.PropertyName is nameof(Tab.DisplayName) or nameof(Tab.IsDirty))
        {
            UpdateTitle();
        }
    }

    private void ShowActiveTab()
    {
        EditorRegion.Content = tabs.ActiveTab is Tab active && tabBar is not null
            ? tabBar.ContentFor(active)
            : null;
    }

    // D01 T01 §14: the stats panel over the active tab's buffer (empty
    // when no tab is active, so the trigger stays always-enabled). Each
    // open constructs a fresh controller: compute lands on open and never
    // while typing, and Refresh re-reads on demand.
    internal async Task ShowStatsPanelAsync()
    {
        // Review round 1: never stack two dialogs (a second ShowAsync
        // throws); the modal usually swallows the repeat press, so the
        // flag is belt-and-braces and the single-dialog drive below is
        // the observable contract.
        if (statsDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        statsDialogOpen = true;
        try
        {
            var dialog = new StatsDialog(new ActiveTabTextProvider(ActiveTabText)) { XamlRoot = xamlRoot };
            await dialog.ShowAsync();
        }
        finally
        {
            statsDialogOpen = false;
        }
    }

    string ActiveTabText()
    {
        if (tabs.ActiveTab is not Tab active || tabBar is null)
        {
            return string.Empty;
        }

        return tabBar.ContentFor(active).Text ?? string.Empty;
    }

    // D01 T01 §16: named local versions over the active tab. The dialog
    // takes through SnapshotStore and restores through FileOpen detection;
    // MainWindow only injects the buffer, the dirty flag, the save path
    // (§5 engine plus ApplySave, mirroring the §7 save branch), and the §7
    // prompt name.
    internal async Task ShowSnapshotsPanelAsync()
    {
        if (snapshotsDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        snapshotsDialogOpen = true;
        try
        {
            Tab? active = tabs.ActiveTab;
            SaveSpec spec = active is null
                ? new SaveSpec("UTF-8", false, "CRLF")
                : new SaveSpec(active.Encoding, active.HasBom, active.LineEnding);
            var dialog = new SnapshotsDialog(
                active?.FilePath,
                ActiveTabText,
                () => active?.IsDirty == true,
                spec,
                text => SaveSnapshotBuffer(active, text),
                restored =>
                {
                    if (active is not null && tabBar is not null)
                    {
                        tabBar.ContentFor(active).Text = restored;
                    }
                },
                () => active is null ? "Untitled.txt" : TabBar.PromptName(active),
                () => ShowSnapshotsPanelAsync())
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            snapshotsDialogOpen = false;
        }
    }

    // D01 T01 §17: new-from-template picker over the §2 tab flow. The dialog
    // expands the chosen template; MainWindow only opens the new tab with
    // the expanded body (mirroring the restore fill path) and roots the
    // custom store at the settings seam.
    internal async Task ShowTemplatesPanelAsync()
    {
        if (templatesDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        templatesDialogOpen = true;
        try
        {
            string directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "IntelligentNotepad", "templates");
            var dialog = new TemplatesDialog(new TemplateStore(directory), ActiveTabText, UseTemplate)
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            templatesDialogOpen = false;
        }
    }

    void UseTemplate(string expanded)
    {
        if (tabBar is null)
        {
            return;
        }

        Tab tab = tabs.NewTab();
        TextBox box = tabBar.ContentFor(tab);
        box.Text = expanded;
        // Explicit like the restore fill path: pre-show boxes do not
        // reliably raise TextChanged, so the model is notified directly.
        // Blank bodies stay clean (untitled tabs are dirty exactly when
        // they hold content); every other template opens dirty.
        tab.NotifyEdited(expanded);
    }

    static SaveResult SaveSnapshotBuffer(Tab? tab, string text)
    {
        if (tab?.FilePath is null)
        {
            return new SaveFailed("No file path.");
        }

        var spec = new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding);
        SaveResult result = FileSave.SaveFile(tab.FilePath, text, spec);
        if (result is SaveSuccess)
        {
            tab.ApplySave(tab.FilePath, spec);
        }

        return result;
    }

    // The hook reports physical client pixels; the strip hit-tests DIP.
    private bool OnMiddleDown(Point physical)
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return false;
        }

        double scale = xamlRoot.RasterizationScale;
        return tabBar.TryCloseTabAt(new Point(physical.X / scale, physical.Y / scale));
    }

    private void UpdateTitle()
    {
        Title = tabs.ActiveTab?.WindowTitle(AppName) ?? WindowTitle.Format("Untitled", false, AppName);
    }

    // Explicit drag rectangles instead of SetTitleBar: the whole-strip drag
    // region swallowed right-clicks into the system menu, so the tab context
    // menu never opened. Only the empty strip right of the tabs (and left of
    // the caption buttons) drags; tabs and the add button stay fully
    // interactive. Insets and drag rects are physical pixels; XAML measures
    // DIP, converted by the rasterization scale.
    private RectInt32 lastDragRect;

    private bool hasDragRect;

    private double lastTopGap;

    private void UpdateDragRects()
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        double scale = xamlRoot.RasterizationScale;
        double leftDip = AppWindow.TitleBar.LeftInset / scale;
        double captionDip = AppWindow.TitleBar.RightInset / scale;
        tabBar.SetCaptionInset(captionDip);
        double contentRight = Math.Max(leftDip, tabBar.TabStripContentRight());
        double stripWidth = TabRegion.ActualWidth;
        double stripHeight = TabRegion.ActualHeight;
        var rect = new RectInt32(
            (int)Math.Round(contentRight * scale),
            0,
            (int)Math.Round(Math.Max(0, stripWidth - captionDip - contentRight) * scale),
            (int)Math.Round(stripHeight * scale));
        double topGap = tabBar.TabStripContentTop();
        RectInt32[] rects = [rect];
        if (topGap > 0.5 && contentRight > leftDip + 0.5)
        {
            rects = [rect, new RectInt32(
                (int)Math.Round(leftDip * scale),
                0,
                (int)Math.Round((contentRight - leftDip) * scale),
                (int)Math.Round(topGap * scale))];
        }

        if (!hasDragRect || !rect.Equals(lastDragRect) || Math.Abs(topGap - lastTopGap) > 0.5)
        {
            hasDragRect = true;
            lastDragRect = rect;
            lastTopGap = topGap;
            AppWindow.TitleBar.SetDragRectangles(rects);
        }
    }

    public void Dispose()
    {
        middleClick?.Dispose();
    }

    private void OnFirstActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnFirstActivated;
        InstallMiddleClickHook();
    }

    // Loaded fires even when activation never does (CI launches never take
    // the foreground), so it backstops the install; whichever fires first wins.
    // A host can refuse the hook outright (Conclave-PC policy fails
    // SetWindowsHookEx): middle-click-to-close degrades away instead of
    // taking the app down, and the UI suite skips that test there.
    private void InstallMiddleClickHook()
    {
        if (middleClick is not null)
        {
            return;
        }

        try
        {
            middleClick = new MiddleClickHook(WindowNative.GetWindowHandle(this), OnMiddleDown, DispatcherQueue);
        }
        catch (InvalidOperationException ex)
        {
            Debug.WriteLine($"Middle-click hook unavailable: {ex.Message}");
        }
    }

    // Every layout pass refreshes the hook's cached tab bounds, so its
    // callback hit-tests from data and never reenters XAML mid-input.
    private void UpdateMiddleClickStrip()
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        middleClick?.UpdateTabs(tabBar.TabHitRects(), xamlRoot.RasterizationScale);
    }

    private void RestoreGeometry()
    {
        int width = Math.Max(100, settings.Width);
        int height = Math.Max(100, settings.Height);
        AppWindow.MoveAndResize(new RectInt32(settings.X, settings.Y, width, height));
    }

    private void OnFirstLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement root)
        {
            root.Loaded -= OnFirstLoaded;
        }

        // D01 T01 §11: window chrome icon. Loaded, not the constructor: the
        // HWND is invalid there, and not first-activation: background launches
        // never activate. The exe icon (ApplicationIcon) covers the taskbar.
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "notepad.ico"));
        InstallMiddleClickHook();
        if (settings.WhatsNewSeen || !firstWindow)
        {
            return;
        }

        DispatcherQueue.TryEnqueue(async () =>
        {
            await ShowWhatsNewAsync().ConfigureAwait(false);
            ShellSettings fresh = ShellSettings.Load();
            fresh.WhatsNewSeen = true;
            fresh.Save();
        });
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        closed = true;

        // No close prompt here, by probe, not by omission (D01 T01 §7):
        // stock closes windows with dirty tabs silently for one tab and
        // for many (both probed with zero dialogs), preserving everything
        // for session restore. The prompt matrix is tab-close only. The
        // session snapshot runs first: App sees the closing window plus
        // its survivors and applies the survivors-or-self rule.
        if (Application.Current is App app)
        {
            app.SnapshotSession(this);
        }

        // Geometry merges onto freshly loaded state: with several windows,
        // each holds a stale snapshot, and a whole-object save would clobber
        // a sibling's newer flag (notably WhatsNewSeen). Last-closed still
        // wins the geometry.
        Dispose();
        PointInt32 position = AppWindow.Position;
        SizeInt32 size = AppWindow.Size;
        ShellSettings fresh = ShellSettings.Load();
        fresh.X = position.X;
        fresh.Y = position.Y;
        fresh.Width = size.Width;
        fresh.Height = size.Height;
        fresh.Save();
    }

    private async void WhatsNewButton_Click(object sender, RoutedEventArgs e)
    {
        await ShowWhatsNewAsync().ConfigureAwait(false);
    }

    private async Task ShowWhatsNewAsync()
    {
        if (Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        var dialog = new WhatsNewDialog { XamlRoot = xamlRoot };
        await dialog.ShowAsync();
    }
}
