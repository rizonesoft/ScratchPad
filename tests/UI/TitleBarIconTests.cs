using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T02 §14: the extended chrome draws no caption glyph, so the app pins
// its own 16px raster left of the tab strip. Presence plus left-of-tabs
// geometry is driven here; the dressed row is eyeballed from the committed
// chrome crop beside the §11 crops.
[Collection("UI tests")]
public sealed class TitleBarIconTests
{
    [Fact]
    public void TitleBarIconPresentAndSized()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            var previous = UiDpi.Enter();
            try
            {
                var icon = FindById(window, "TitleBarIcon");
                Assert.NotNull(icon);
                var rect = icon.BoundingRectangle;
                // Physical pixels: 16 DIP at the window's own scale (the
                // host runs 150%, CI runs 100%; both read 16 DIP here).
                nint hwnd = window.Properties.NativeWindowHandle.ValueOrDefault;
                Assert.NotEqual(nint.Zero, hwnd);
                double expected = 16.0 * GetDpiForWindow(hwnd) / 96.0;
                Assert.InRange(rect.Width, expected - 1, expected + 1);
                Assert.InRange(rect.Height, expected - 1, expected + 1);
                // Geometry alone cannot tell a rendered glyph from a box
                // whose source never loaded, so the app reports decode
                // state on ItemStatus (ImageOpened/ImageFailed) and the drive
                // waits for it instead of trusting the rectangle.
                var status = Retry.While(
                    () => icon.Properties.ItemStatus.ValueOrDefault,
                    text => text != "loaded",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250));
                Assert.Equal("loaded", status.Result);
            }
            finally
            {
                UiDpi.Exit(previous);
            }
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void TitleBarIconLeftOfFirstTab()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal(1, WaitForTabCount(window, 1));
            var previous = UiDpi.Enter();
            try
            {
                double iconRight = 0;
                double tabLeft = 0;
                double delta = 0;
                var settled = Retry.While(
                    () =>
                    {
                        var icon = FindById(window, "TitleBarIcon");
                        var region = FindById(window, "TabRegion");
                        var first = TabItems(window).FirstOrDefault();
                        if (icon is null || region is null || first is null)
                        {
                            return false;
                        }

                        iconRight = icon.BoundingRectangle.Right;
                        tabLeft = first.BoundingRectangle.Left;
                        delta = Math.Abs(icon.BoundingRectangle.Center().Y - region.BoundingRectangle.Center().Y);
                        return iconRight <= tabLeft && delta <= 8;
                    },
                    settled => !settled,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250));
                Assert.True(settled.Result, $"icon right {iconRight} vs tab left {tabLeft}, off strip center by {delta}px");
            }
            finally
            {
                UiDpi.Exit(previous);
            }
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void AddButtonRealClickOpensTab()
    {
        // The §14 drag-rect regression (caption rect over the add button)
        // is invisible to UIA invoke, which bypasses hit-testing: only a
        // real cursor click through the caption zone proves the button
        // still receives its clicks. A plain Fact, red on headless hosts
        // exactly like its TabBarTests input siblings; CI is the gate.
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal(1, WaitForTabCount(window, 1));
            var add = FindButton(window, "Add New Tab");
            Assert.NotNull(add);
            UiDpi.PinTopmost(window, true);
            try
            {
                LeftClick(add);
            }
            finally
            {
                UiDpi.PinTopmost(window, false);
            }

            Assert.Equal(2, WaitForTabCount(window, 2));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static void LeftClick(AutomationElement element)
    {
        const uint down = 0x0002;
        const uint up = 0x0004;
        var previous = UiDpi.Enter();
        try
        {
            var point = element.GetClickablePoint();
            ClickNative.SetCursorPos((int)point.X, (int)point.Y);
            Thread.Sleep(100);
            ClickNative.MouseEvent(down, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(100);
            ClickNative.MouseEvent(up, 0, 0, 0, UIntPtr.Zero);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
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

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

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
        SessionData.Delete();
    }

    static AutomationElement? FindById(AutomationElement window, string id)
    {
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
    static extern uint GetDpiForWindow(nint hWnd);

    static Button? FindButton(AutomationElement scope, string name)
    {
        return Retry.WhileNull(
            () => scope.FindAllDescendants(cf => cf.ByControlType(ControlType.Button)).FirstOrDefault(button => button.Name == name)?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static class ClickNative
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
        internal static extern bool SetCursorPos(int x, int y);

        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "mouse_event")]
        [System.Runtime.InteropServices.DefaultDllImportSearchPaths(System.Runtime.InteropServices.DllImportSearchPath.System32)]
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
