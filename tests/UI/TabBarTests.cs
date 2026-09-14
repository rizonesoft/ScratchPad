using System.Globalization;
using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// D01 T01 §3: the tab bar. Every drive here mirrors a gesture recorded live
// from Notepad 11.2607.14.0, including the negative ones: Ctrl+9 selects the
// last tab (not the ninth), Ctrl+Shift+T restores nothing after a Don't-save
// close, and a drag attempt leaves the order unchanged (stock has no reorder).
[Collection("UI tests")]
public sealed class TabBarTests
{
    readonly ITestOutputHelper output;

    public TabBarTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void InitialTabRendersFromModel()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal("Untitled - Intelligent Notepad", window.Title);
            var tabs = FindById(window, "Tabs");
            Assert.NotNull(tabs);
            var items = TabItems(window);
            Assert.Single(items);
            Assert.Equal("Untitled", items[0].Name);
            Assert.NotNull(FindButton(window, "Add New Tab"));
            Assert.NotNull(FindById(window, "TabContentBox"));
            // Clean resting tab: X glyph present, no dirty dot.
            Assert.NotNull(items[0].FindFirstDescendant(cf => cf.ByName("Close Tab")));
            Assert.Null(items[0].FindFirstDescendant(cf => cf.ByName("•")));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    // The section checkpoint: open three tabs, switch, close each. Reorder is
    // covered by DragAttemptLeavesOrderUnchanged (parity is no-reorder).
    [Fact]
    public void ThreeTabsSwitchAndClose()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(3, WaitForTabCount(window, 3));

            // Distinct content per tab proves the switch actually moves.
            SelectTab(window, 0);
            ContentBox(window).Text = "AAA";
            SelectTab(window, 1);
            ContentBox(window).Text = "BBB";
            SelectTab(window, 2);
            ContentBox(window).Text = "CCC";
            WaitForTabName(window, 0, "AAA");
            WaitForTabName(window, 1, "BBB");
            WaitForTabName(window, 2, "CCC");
            Assert.Equal("AAA", TabItemAt(window, 0).Name);
            SelectTab(window, 0);
            Assert.Equal("AAA", WaitForContent(window, "AAA"));

            // Ctrl+Tab cycles sequentially and wraps; Ctrl+1/3 jump.
            Press(window, VirtualKeyShort.TAB, withControl: true);
            Assert.Equal("BBB", WaitForContent(window, "BBB"));
            Press(window, VirtualKeyShort.TAB, withControl: true);
            Assert.Equal("CCC", WaitForContent(window, "CCC"));
            Press(window, VirtualKeyShort.TAB, withControl: true);
            Assert.Equal("AAA", WaitForContent(window, "AAA"));
            Press(window, VirtualKeyShort.KEY_3, withControl: true);
            Assert.Equal("CCC", WaitForContent(window, "CCC"));
            Press(window, VirtualKeyShort.KEY_1, withControl: true);
            Assert.Equal("AAA", WaitForContent(window, "AAA"));

            // Clearing an untitled box flips it back to clean, so each close
            // below runs silent; clear only the closing tab so the survivor
            // proves which tab went. Dirty closes have their own drives.
            SelectTab(window, 2);
            ContentBox(window).Text = string.Empty;
            WaitForTabName(window, 2, "Untitled");

            // Ctrl+W closes the active tab; the neighbor takes selection.
            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            Assert.Equal(2, WaitForTabCount(window, 2));
            Assert.Equal("BBB", WaitForContent(window, "BBB"));

            // The close glyph shuts the rest; the last close leaves zero tabs
            // with the window alive (unprobed default, recorded in §3).
            ContentBox(window).Text = string.Empty;
            CloseActiveViaGlyph(window);
            Assert.Equal(1, WaitForTabCount(window, 1));
            Assert.Equal("AAA", WaitForContent(window, "AAA"));
            ContentBox(window).Text = string.Empty;
            CloseActiveViaGlyph(window);
            Assert.Equal(0, WaitForTabCount(window, 0));
            Assert.False(app.HasExited);
            Assert.Equal("Untitled - Intelligent Notepad", window.Title);
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void NumberShortcutsAndReopenMatchNotepad()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            var add = FindButton(window, "Add New Tab");
            Assert.NotNull(add);
            for (int i = 1; i < 10; i++)
            {
                add.Invoke();
            }

            Assert.Equal(10, WaitForTabCount(window, 10));
            for (int i = 0; i < 10; i++)
            {
                SelectTab(window, i);
                ContentBox(window).Text = $"TAB{i}";
            }

            for (int i = 0; i < 10; i++)
            {
                WaitForTabName(window, i, $"TAB{i}");
            }

            // Ctrl+3 is positional; Ctrl+9 selects the last tab (probed).
            Press(window, VirtualKeyShort.KEY_3, withControl: true);
            Assert.Equal("TAB2", WaitForContent(window, "TAB2"));
            Press(window, VirtualKeyShort.KEY_9, withControl: true);
            Assert.Equal("TAB9", WaitForContent(window, "TAB9"));

            // Shift+Tab walks back one. Clearing the box makes the close a
            // clean empty-untitled close, which stacks nothing: reopen is a
            // no-op (Notepad's no-restore parity for empty untitled tabs).
            Press(window, VirtualKeyShort.TAB, withControl: true, withShift: true);
            Assert.Equal("TAB8", WaitForContent(window, "TAB8"));
            ContentBox(window).Text = string.Empty;
            WaitForTabName(window, 8, "Untitled");
            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            Assert.Equal(9, WaitForTabCount(window, 9));
            Press(window, VirtualKeyShort.KEY_T, withControl: true, withShift: true);
            Thread.Sleep(500);
            Assert.Equal(9, WaitForTabCount(window, 9));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void DragAttemptLeavesOrderUnchanged()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(3, WaitForTabCount(window, 3));
            SelectTab(window, 0);
            ContentBox(window).Text = "AAA";
            SelectTab(window, 1);
            ContentBox(window).Text = "BBB";
            SelectTab(window, 2);
            ContentBox(window).Text = "CCC";
            WaitForTabName(window, 0, "AAA");
            WaitForTabName(window, 1, "BBB");
            WaitForTabName(window, 2, "CCC");

            // Real mouse travel like the middle-click drive: pin topmost so an
            // overlapping window cannot receive the drag (which would pass
            // vacuously, since the assertion is no reorder).
            UiDpi.PinTopmost(window, true);
            try
            {
                var before = TabItems(window);
                var from = before[0].GetClickablePoint();
                var to = before[2].GetClickablePoint();
                Mouse.Position = from;
                Thread.Sleep(100);
                Mouse.Down(MouseButton.Left);
                try
                {
                    for (int step = 1; step <= 10; step++)
                    {
                        Mouse.Position = new System.Drawing.Point(
                            (from.X * (10 - step) + to.X * step) / 10,
                            (from.Y * (10 - step) + to.Y * step) / 10);
                        Thread.Sleep(50);
                    }
                }
                finally
                {
                    Mouse.Up(MouseButton.Left);
                }
            }
            finally
            {
                UiDpi.PinTopmost(window, false);
            }

            Thread.Sleep(500);
            var after = TabItems(window);
            Assert.Equal(3, after.Count);
            SelectTab(window, 0);
            Assert.Equal("AAA", WaitForContent(window, "AAA"));
            SelectTab(window, 1);
            Assert.Equal("BBB", WaitForContent(window, "BBB"));
            SelectTab(window, 2);
            Assert.Equal("CCC", WaitForContent(window, "CCC"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void DirtyClosePromptsAndCancelKeepsTheTab()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            ContentBox(window).Text = "FIRST";
            Assert.StartsWith("*", WaitForTitle(window, "*"), StringComparison.Ordinal);
            Assert.NotNull(TabItemAt(window, 0).FindFirstDescendant(cf => cf.ByName("•")));

            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            var dialog = WaitForDialog(window);
            Assert.NotNull(dialog);
            var message = dialog.FindFirstDescendant(cf => cf.ByText("Do you want to save changes to FIRST.txt?"));
            Assert.NotNull(message);
            Assert.NotNull(FindButton(dialog, "Save"));
            Assert.NotNull(FindButton(dialog, "Don't save"));
            Assert.NotNull(FindButton(dialog, "Cancel"));

            var cancel = FindButton(dialog, "Cancel");
            Assert.NotNull(cancel);
            cancel.Invoke();
            Assert.True(WaitForGone(window, "SavePromptDialog", TimeSpan.FromSeconds(10)), "prompt did not close on Cancel");
            Assert.Single(TabItems(window));
            Assert.StartsWith("*", WaitForTitle(window, "*"), StringComparison.Ordinal);
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void DontSaveClosesAndNeverReopens()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            ContentBox(window).Text = "FIRST";
            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            var dialog = WaitForDialog(window);
            Assert.NotNull(dialog);
            var dontSave = FindButton(dialog, "Don't save");
            Assert.NotNull(dontSave);
            dontSave.Invoke();
            Assert.True(WaitForGone(window, "SavePromptDialog", TimeSpan.FromSeconds(10)), "prompt did not close on Don't save");
            Assert.Equal(0, WaitForTabCount(window, 0));

            // Notepad's no-restore parity: discarded closes never reopen.
            Press(window, VirtualKeyShort.KEY_T, withControl: true, withShift: true);
            Thread.Sleep(500);
            Assert.Equal(0, WaitForTabCount(window, 0));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void ContextMenuMatchesNotepad()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(3, WaitForTabCount(window, 3));
            SelectTab(window, 0);
            ContentBox(window).Text = "AAA";
            SelectTab(window, 1);
            ContentBox(window).Text = "BBB";
            SelectTab(window, 2);
            ContentBox(window).Text = "CCC";
            WaitForTabName(window, 0, "AAA");
            WaitForTabName(window, 1, "BBB");
            WaitForTabName(window, 2, "CCC");

            // Real right-button input like the middle-click drive: pin topmost
            // so an overlapping window cannot swallow the clicks instead.
            UiDpi.PinTopmost(window, true);
            try
            {
                ContextMenuDrives(window);
            }
            finally
            {
                UiDpi.PinTopmost(window, false);
            }
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static void ContextMenuDrives(Window window)
    {
        // The four items match live Notepad exactly.
        TabItemAt(window, 0).RightClick();
        Assert.NotNull(WaitForMenuItem(window, "New tab"));
        Assert.NotNull(WaitForMenuItem(window, "Close tab"));
        Assert.NotNull(WaitForMenuItem(window, "Close other tabs"));
        Assert.NotNull(WaitForMenuItem(window, "Close tabs to the right"));
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(300);

        // Close-right hits the dirty CCC tab, so the prompt appears and
        // Don't-save takes it; the survivors keep their names.
        TabItemAt(window, 1).RightClick();
        var closeRight = WaitForMenuItem(window, "Close tabs to the right");
        Assert.NotNull(closeRight);
        closeRight.Invoke();
        var dirty = WaitForDialog(window);
        Assert.NotNull(dirty);
        var dontSave = FindButton(dirty, "Don't save");
        Assert.NotNull(dontSave);
        dontSave.Invoke();
        Assert.True(WaitForGone(window, "SavePromptDialog", TimeSpan.FromSeconds(10)), "prompt did not close on Don't save");
        Assert.Equal(2, WaitForTabCount(window, 2));
        Assert.Equal("AAA", TabItemAt(window, 0).Name);
        Assert.Equal("BBB", TabItemAt(window, 1).Name);

        // Clean tabs close silent.
        SelectTab(window, 0);
        ContentBox(window).Text = string.Empty;
        WaitForTabName(window, 0, "Untitled");
        SelectTab(window, 1);
        ContentBox(window).Text = string.Empty;
        WaitForTabName(window, 1, "Untitled");
        TabItemAt(window, 0).RightClick();
        var closeOthers = WaitForMenuItem(window, "Close other tabs");
        Assert.NotNull(closeOthers);
        closeOthers.Invoke();
        Assert.Equal(1, WaitForTabCount(window, 1));
        Assert.Equal("Untitled", TabItemAt(window, 0).Name);

        TabItemAt(window, 0).RightClick();
        var newTab = WaitForMenuItem(window, "New tab");
        Assert.NotNull(newTab);
        newTab.Invoke();
        Assert.Equal(2, WaitForTabCount(window, 2));
    }

    [Fact]
    public void MiddleClickClosesTheTabUnderTheCursor()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(2, WaitForTabCount(window, 2));
            SelectTab(window, 0);
            ContentBox(window).Text = "AAA";
            SelectTab(window, 1);
            ContentBox(window).Text = "BBB";
            WaitForTabName(window, 0, "AAA");
            WaitForTabName(window, 1, "BBB");

            // Middle-click the non-active tab: cursor position wins. Clean
            // only the clicked tab so its close runs silent while the AAA
            // survivor proves which tab went.
            SelectTab(window, 1);
            ContentBox(window).Text = string.Empty;
            WaitForTabName(window, 1, "Untitled");
            SelectTab(window, 0);
            // Real input needs the top of the Z order, not just focus: an
            // overlapping window would receive (and keep) the click instead.
            UiDpi.PinTopmost(window, true);
            try
            {
                MiddleClick(TabItemAt(window, 1));
            }
            finally
            {
                UiDpi.PinTopmost(window, false);
            }

            Assert.Equal(1, WaitForTabCount(window, 1));
            Assert.Equal("AAA", WaitForContent(window, "AAA"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void OverflowShrinksTabsWithoutScrollChrome()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            var tabs = FindById(window, "Tabs");
            Assert.NotNull(tabs);
            var add = FindButton(window, "Add New Tab");
            Assert.NotNull(add);
            for (int i = 1; i < 15; i++)
            {
                add.Invoke();
            }

            Assert.Equal(15, WaitForTabCount(window, 15));
            WaitForLayout(window);
            var items = TabItems(window);
            double strip = tabs.BoundingRectangle.Width;
            output.WriteLine($"strip {strip}px, widths {string.Join(",", items.ConvertAll(i => ((int)i.BoundingRectangle.Width).ToString(CultureInfo.InvariantCulture)))}");

            // Shrink-to-fit like stock (narrow 25-tab probe: widths 3..128,
            // selected widest, no scroll UI): every tab keeps a nonzero
            // width, all fit the strip, the selected tab is the widest.
            // Ratios only: physical pixels scale with DPI.
            double selectedWidth = 0;
            double total = 0;
            foreach (var item in items)
            {
                double width = item.BoundingRectangle.Width;
                Assert.True(width > 0, "a tab has no width: the strip virtualized instead of shrinking");
                total += width;
                if (item.Patterns.SelectionItem.PatternOrDefault?.IsSelected == true)
                {
                    selectedWidth = width;
                }
            }

            Assert.True(selectedWidth > 0, "no selected tab");
            Assert.True(total <= strip + 10, $"tabs overflow the strip: {total}px on {strip}px");
            foreach (var item in items)
            {
                Assert.True(item.BoundingRectangle.Width <= selectedWidth + 1, $"unselected tab wider than selected: {item.BoundingRectangle.Width}px vs {selectedWidth}px");
            }

            foreach (var button in tabs.FindAllDescendants(cf => cf.ByControlType(ControlType.Button)))
            {
                Assert.DoesNotContain("Scroll", button.Name ?? string.Empty, StringComparison.OrdinalIgnoreCase);
            }
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static void Press(Window window, VirtualKeyShort key, bool withControl, bool withShift = false)
    {
        window.Focus();
        Thread.Sleep(150);
        if (withShift)
        {
            using (Keyboard.Pressing(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT))
            {
                Keyboard.Press(key);
            }
        }
        else if (withControl)
        {
            using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
            {
                Keyboard.Press(key);
            }
        }
        else
        {
            Keyboard.Press(key);
        }

        Thread.Sleep(250);
    }

    static void SelectTab(Window window, int index)
    {
        var pattern = TabItemAt(window, index).Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
    }

    // A real middle-button event: FlaUI's middle-click never lands the close.
    // The clickable point is queried inside the PerMonitorV2 context with the
    // cursor move: testhost is DPI-unaware, so a point read outside arrives
    // virtualized and the cursor lands up-left of the tab (at 150% the miss
    // reaches whatever window sits above ours instead).
    static void MiddleClick(AutomationElement element)
    {
        const uint down = 0x0020;
        const uint up = 0x0040;
        var previous = UiDpi.Enter();
        try
        {
            var point = element.GetClickablePoint();
            NativeMethods.SetCursorPos((int)point.X, (int)point.Y);
            Thread.Sleep(100);
            NativeMethods.MouseEvent(down, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(100);
            NativeMethods.MouseEvent(up, 0, 0, 0, UIntPtr.Zero);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    static void CloseActiveViaGlyph(Window window)
    {
        var items = TabItems(window);
        AutomationElement? selected = null;
        foreach (var item in items)
        {
            if (item.Patterns.SelectionItem.PatternOrDefault?.IsSelected == true)
            {
                selected = item;
            }
        }

        Assert.NotNull(selected);
        var close = selected.FindFirstDescendant(cf => cf.ByName("Close Tab"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        Thread.Sleep(250);
    }

    static TextBox ContentBox(Window window)
    {
        var box = FindById(window, "TabContentBox")?.AsTextBox();
        Assert.NotNull(box);
        return box;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    // Direct indexing flaked once (an empty list mid-churn after SelectTab):
    // UIA can lag the model by a beat, so single-item reads poll briefly.
    // Genuine emptiness still fails, after 5s instead of instantly.
    static AutomationElement TabItemAt(Window window, int index)
    {
        var items = Retry.While(
            () => TabItems(window),
            found => found.Count <= index,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result ?? [];
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        return items[index];
    }

    // Setup verification, not redundancy: SelectTab returns before the model
    // round-trips, and under CI load the editor box can lag a beat behind
    // the selection, landing a content set on the wrong tab (two CI reds,
    // same dialog assert, green locally). The auto-name only matches when
    // the set reached its tab through the full chain.
    static void WaitForTabName(Window window, int index, string expected)
    {
        string? NameAt()
        {
            var found = TabItems(window);
            return found.Count > index ? found[index].Name : null;
        }

        var result = Retry.While(
            NameAt,
            name => name != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.Equal(expected, result);
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
    }

    // Rapid adds outrun layout; zero-width tabs have not measured yet.
    static void WaitForLayout(Window window)
    {
        Retry.While(
            () => TabItems(window),
            items => items.Any(item => item.BoundingRectangle.Width <= 0),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
    }

    static string WaitForContent(Window window, string expected)
    {
        var result = Retry.While(
            () => ContentBox(window).Text,
            text => text != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result ?? string.Empty;
    }

    // The UIA window title lags the WinUI Title set by a frame or two.
    static string WaitForTitle(Window window, string prefix)
    {
        var result = Retry.While(
            () => window.Title,
            title => title is null || !title.StartsWith(prefix, StringComparison.Ordinal),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result ?? string.Empty;
    }

    static AutomationElement? WaitForDialog(Window window) =>
        Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;

    static MenuItem? WaitForMenuItem(Window window, string name) =>
        Retry.WhileNull(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).FirstOrDefault(item => item.Name == name)?.AsMenuItem(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;

    static bool WaitForGone(Window window, string automationId, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)) is null)
            {
                return true;
            }

            Thread.Sleep(250);
        }

        return false;
    }

    static Application LaunchApp()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return Application.Launch(appPath);
    }

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
    }

    static AutomationElement? FindById(AutomationElement window, string id)
    {
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static Button? FindButton(AutomationElement scope, string name)
    {
        return Retry.WhileNull(
            () => scope.FindAllDescendants(cf => cf.ByControlType(ControlType.Button)).FirstOrDefault(button => button.Name == name)?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static class NativeMethods
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll", EntryPoint = "mouse_event")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern void MouseEvent(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    }

    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            // Already gone; the exit wait below is the real assertion.
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!app.HasExited)
        {
            app.Kill();
        }

        Assert.True(app.HasExited, "app did not exit after Close");
    }
}
