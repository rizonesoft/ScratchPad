using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 3: the background birth point comes from the virtual
// screen, and a launch's observed restore rect has to match it. The three
// topology fixtures take synthetic metrics so a single-monitor box still
// pins negative-origin, stacked, and very-wide layouts.
[Collection("UI tests")]
public sealed class OffScreenBirthTests
{
    const int WindowWidth = 900;
    const int WindowHeight = 650;

    [Fact]
    public void NegativeOriginKeepsTheWindowOutside()
    {
        var screen = new UiLaunch.ScreenBounds(-3840, 0, 6400, 1440);
        AssertOutside(screen, WindowWidth, WindowHeight);
    }

    [Fact]
    public void StackedMonitorsKeepTheWindowOutside()
    {
        var screen = new UiLaunch.ScreenBounds(0, -1440, 1920, 2880);
        AssertOutside(screen, WindowWidth, WindowHeight);
    }

    [Fact]
    public void VeryWideScreenRejectsTheOldFixedPoint()
    {
        var screen = new UiLaunch.ScreenBounds(0, 0, 20000, 12000);
        Assert.True(UiLaunch.WindowIntersects(screen, 10000, 10000, WindowWidth, WindowHeight));
        AssertOutside(screen, WindowWidth, WindowHeight);
    }

    [Fact]
    public void WindowSizeStaysOutsideOnTheLeftFallback()
    {
        // The right edge is past int.MaxValue and the top has no room
        // for the window, so the birth has to step left by the full width.
        var screen = new UiLaunch.ScreenBounds(int.MaxValue - 1000, int.MinValue + 30, 2000, 800);
        (int x, int y) = AssertOutside(screen, 2000, 1500);
        Assert.True((long)x + 2000 <= screen.X, $"left fallback landed at {x},{y}");
    }

    [Fact]
    public void OverflowDoesNotWrapIntoTheScreen()
    {
        var screen = new UiLaunch.ScreenBounds(int.MaxValue - 10, 0, 100, WindowHeight);
        int wrapped = unchecked((int.MaxValue - 10) + 100);
        (int x, _) = AssertOutside(screen, WindowWidth, WindowHeight);
        Assert.NotEqual(wrapped, x);
    }

    [Fact]
    public void ObservedBirthMatchesTheDerivedPoint()
    {
        Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        ShellSettings seeded = ShellSettings.Load();
        UiLaunch.ScreenBounds screen = UiLaunch.ReadVirtualScreen();
        Assert.False(UiLaunch.WindowIntersects(screen, seeded.X, seeded.Y, seeded.Width, seeded.Height));
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            nint previous = UiDpi.Enter();
            try
            {
                nint hwnd = window.Properties.NativeWindowHandle.Value;
                var placement = new WindowPlacement { Length = Marshal.SizeOf<WindowPlacement>() };
                Assert.True(Native.GetWindowPlacement(hwnd, ref placement), "GetWindowPlacement failed");
                var normal = placement.NormalPosition;
                int width = normal.Right - normal.Left;
                int height = normal.Bottom - normal.Top;
                Assert.InRange(normal.Left, seeded.X - 8, seeded.X + 8);
                Assert.InRange(normal.Top, seeded.Y - 8, seeded.Y + 8);
                Assert.False(
                    UiLaunch.WindowIntersects(screen, normal.Left, normal.Top, width, height),
                    $"observed {normal.Left},{normal.Top} {width}x{height} intersects virtual {screen.X},{screen.Y} {screen.Width}x{screen.Height}");
            }
            finally
            {
                UiDpi.Exit(previous);
            }
        }
        finally
        {
            UiForeground.Restore(fgBefore, window.Properties.NativeWindowHandle.ValueOrDefault);
            CloseApp(app, window);
        }
    }

    // D00 T02 §18 item 2 (K1): the suite places before the show, so
    // the backgrounded re-show lands directly on the suite display
    // and no frame paints at the birth spot. The flash itself is
    // sub-millisecond (below any maintained assertion; the proof gate
    // photographs it), so this guards the mechanism end-state: after
    // Background, the placed rect sits at the suite origin. Size is
    // app-owned post-show layout, not asserted. Reads agree only on
    // the pinned 100%-secondary topology, like the placer itself.
    [Fact]
    public void BackgroundRestoreLandsOnTheSuiteDisplay()
    {
        Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            UiForeground.Background(window, fgBefore);
            nint previous = UiDpi.Enter();
            try
            {
                nint hwnd = window.Properties.NativeWindowHandle.Value;
                var placement = new WindowPlacement { Length = Marshal.SizeOf<WindowPlacement>() };
                Assert.True(Native.GetWindowPlacement(hwnd, ref placement), "GetWindowPlacement failed");
                var normal = placement.NormalPosition;
                (int x, int y) = UiForeground.SuiteDisplayOrigin();
                Assert.InRange(normal.Left, x - 8, x + 8);
                Assert.InRange(normal.Top, y - 8, y + 8);
            }
            finally
            {
                UiDpi.Exit(previous);
            }
        }
        finally
        {
            UiForeground.Restore(fgBefore, window.Properties.NativeWindowHandle.ValueOrDefault);
            CloseApp(app, window);
        }
    }

    static (int X, int Y) AssertOutside(UiLaunch.ScreenBounds screen, int width, int height)
    {
        (int x, int y) = UiLaunch.DeriveOffScreenOrigin(screen, width, height);
        Assert.False(
            UiLaunch.WindowIntersects(screen, x, y, width, height),
            $"birth {x},{y} {width}x{height} intersects virtual {screen.X},{screen.Y} {screen.Width}x{screen.Height}");
        return (x, y);
    }

    static void CloseApp(Application app, FlaUI.Core.AutomationElements.Window? window)
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

    [StructLayout(LayoutKind.Sequential)]
    struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct WindowPlacement
    {
        public int Length;
        public int Flags;
        public int ShowCmd;
        public Point MinPosition;
        public Point MaxPosition;
        public Rect NormalPosition;
    }

    static class Native
    {
        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool GetWindowPlacement(nint hwnd, ref WindowPlacement placement);
    }
}
