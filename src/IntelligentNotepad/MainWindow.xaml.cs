using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
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

    private MiddleClickHook? middleClick;

    private bool closed;

    // firstWindow selects first-launch behavior: only the first window of the
    // process restores persisted geometry and may show first-run (D01 T01
    // §9); later windows open at the OS default cascade like stock's.
    private readonly bool firstWindow;

    public MainWindow(bool firstWindow)
    {
        this.firstWindow = firstWindow;
        InitializeComponent();
        Title = WindowTitle.Format("Untitled", false, AppName);
        ExtendsContentIntoTitleBar = true;
        tabBar = new TabBar { Model = tabs };
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
        tabs.NewTab();
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
            // Loaded, not Activated: first-run must show even when the window
            // opens behind others (CI launches never take the foreground).
            root.Loaded += OnFirstLoaded;
        }

        if (firstWindow)
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
        }
    }

    private void Tabs_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems is not null)
        {
            foreach (Tab tab in e.OldItems)
            {
                tab.PropertyChanged -= ActiveTab_PropertyChanged;
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

    private void UpdateDragRects()
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        double scale = xamlRoot.RasterizationScale;
        double leftDip = AppWindow.TitleBar.LeftInset / scale;
        double captionDip = AppWindow.TitleBar.RightInset / scale;
        double contentRight = Math.Max(leftDip, tabBar.TabStripContentRight());
        double stripWidth = TabRegion.ActualWidth;
        double stripHeight = TabRegion.ActualHeight;
        var rect = new RectInt32(
            (int)Math.Round(contentRight * scale),
            0,
            (int)Math.Round(Math.Max(0, stripWidth - captionDip - contentRight) * scale),
            (int)Math.Round(stripHeight * scale));
        if (!hasDragRect || !rect.Equals(lastDragRect))
        {
            hasDragRect = true;
            lastDragRect = rect;
            AppWindow.TitleBar.SetDragRectangles([rect]);
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

        InstallMiddleClickHook();
        if (settings.WhatsNewSeen || !firstWindow)
        {
            return;
        }

        DispatcherQueue.TryEnqueue(async () =>
        {
            await ShowWhatsNewAsync().ConfigureAwait(false);
            settings.WhatsNewSeen = true;
            settings.Save();
        });
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        closed = true;

        // No close prompt here: §7 owns window-close behavior (prompt matrix,
        // silence, crash recovery). Until then tabs die with the window.
        // Every window saves geometry on close; last-closed wins the next
        // first window (default, §6 owns the multi-window restore).
        Dispose();
        PointInt32 position = AppWindow.Position;
        SizeInt32 size = AppWindow.Size;
        settings.X = position.X;
        settings.Y = position.Y;
        settings.Width = size.Width;
        settings.Height = size.Height;
        settings.Save();
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
