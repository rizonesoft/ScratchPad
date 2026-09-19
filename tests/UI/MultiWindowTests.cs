using System.Drawing;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §9: the new-window command, per-window tab isolation, and the
// no-tear-off parity negative (stock has no detach, probed twice).
[Collection("UI tests")]
public sealed class MultiWindowTests
{
    [Fact]
    [Trait("Category", "Primary")]
    public void CtrlShiftNOpensSecondWindowAtCascade()
    {
        // Primary placement (pair §8 item 7 revision): moved to the
        // secondary the cascade premise is destroyed (no app-chosen offset
        // to assert); shown in place on the primary it passes. Focus-free:
        // InPlace shows no-activate and restores the foreground.
        SeedSettings(new ShellSettings { WhatsNewSeen = true, X = 100, Y = 100, Width = 900, Height = 650 });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var first = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.InPlace(first, fgBefore);
        Assert.NotNull(first);
        try
        {
            Assert.Single(app.GetAllTopLevelWindows(automation));
            UiInput.InvokeMenuItem(first, "MenuFile", "MenuFileNewWindow");
            Window[] windows = WaitForWindowCount(app, automation, 2);
            Assert.Equal(2, windows.Length);
            Window second = windows[0].Properties.NativeWindowHandle.Value == first.Properties.NativeWindowHandle.Value
                ? windows[1]
                : windows[0];
            Assert.NotEqual(first.BoundingRectangle.Location, second.BoundingRectangle.Location);
            Assert.Equal(TabAccessibilityName.For("Untitled", isDirty: false), TabItemAt(second, 0).Name);
            Assert.Null(second.FindFirstDescendant(cf => cf.ByAutomationId("WhatsNewDialog")));
            second.Close();
            Assert.Single(WaitForWindowCount(app, automation, 1));
        }
        finally
        {
            CloseAll(app, automation);
        }
    }

    [Fact]
    public void WindowsKeepIndependentTabs()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var first = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(first, fgBefore);
        Assert.NotNull(first);
        try
        {
            UiInput.InvokeMenuItem(first, "MenuFile", "MenuFileNewWindow");
            Window[] windows = WaitForWindowCount(app, automation, 2);
            Assert.Equal(2, windows.Length);
            Window second = windows[0].Properties.NativeWindowHandle.Value == first.Properties.NativeWindowHandle.Value
                ? windows[1]
                : windows[0];
            UiForeground.PlaceForBackground(second);
            UiInput.InvokeMenuItem(second, "MenuFile", "MenuFileNewTab");
            Assert.Equal(2, WaitForTabCount(second, 2));
            Assert.Single(TabItems(first));
            ContentBox(second).Text = "WINDOW2";
            Assert.Equal("Untitled - ScratchPad", first.Title);
            Assert.Equal(string.Empty, ContentBox(first).Text);
            second.Close();
            Assert.Single(WaitForWindowCount(app, automation, 1));
            Assert.Equal("Untitled - ScratchPad", first.Title);
        }
        finally
        {
            CloseAll(app, automation);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void TabDragOutsideStripDetachesNothing()
    {
        // Fenced (grandfather §8): drag physics IS the point (audit mouse).
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            // Stock has no tear-off (two clean drag-out negatives); parity is
            // no detach. Pin topmost so the drop lands on our window, like
            // the no-reorder drive.
            UiDpi.PinTopmost(window, true);
            try
            {
                AutomationElement tab = TabItemAt(window, 0);
                Rectangle bounds = tab.BoundingRectangle;
                var from = new Point(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2);
                var to = new Point(from.X, bounds.Bottom + 260);
                Mouse.Position = from;
                Thread.Sleep(100);
                Mouse.Down(MouseButton.Left);
                try
                {
                    for (int step = 1; step <= 10; step++)
                    {
                        Mouse.Position = new Point(
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
            Assert.Single(app.GetAllTopLevelWindows(automation));
            Assert.Single(TabItems(window));
        }
        finally
        {
            CloseAll(app, automation);
        }
    }

    [Fact]
    public void SecondWindowClosePreservesNewerExternalState()
    {
        // The stale-snapshot race: every window holds the settings it loaded,
        // so a close must merge its geometry onto freshly loaded state rather
        // than saving its snapshot whole (else a window opened before a newer
        // save clobbers it; the real victim is whatsnew.seen, flipped by the
        // first window's first-run dismiss). Staged externally instead of via
        // the dialog because the open first-run dialog swallows Ctrl+Shift+N
        // (standard ContentDialog modality); the mechanism is direction-free.
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var first = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(first, fgBefore);
        Assert.NotNull(first);
        try
        {
            UiInput.InvokeMenuItem(first, "MenuFile", "MenuFileNewWindow");
            Window[] windows = WaitForWindowCount(app, automation, 2);
            Assert.Equal(2, windows.Length);
            Window second = windows[0].Properties.NativeWindowHandle.Value == first.Properties.NativeWindowHandle.Value
                ? windows[1]
                : windows[0];
            ShellSettings newer = ShellSettings.Load();
            newer.WhatsNewSeen = false;
            newer.Save();
            second.Close();
            Assert.Single(WaitForWindowCount(app, automation, 1));
            Assert.False(ShellSettings.Load().WhatsNewSeen, "second-window close clobbered newer external state");
        }
        finally
        {
            CloseAll(app, automation);
        }
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
        // Every close snapshots the session, so a seeded launch also starts
        // session-clean; otherwise the previous test's tabs would restore.
        SessionData.Delete();
    }


    static TextBox ContentBox(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

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

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
    }

    static Window[] WaitForWindowCount(Application app, UIA3Automation automation, int expected)
    {
        var result = Retry.While(
            () => app.GetAllTopLevelWindows(automation),
            found => found.Length != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result ?? [];
    }

    static void CloseAll(Application app, UIA3Automation automation)
    {
        foreach (var window in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                // Already gone; the exit wait below is the real assertion.
            }
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
    }
}
