using System.Runtime.InteropServices;
using FlaUI.Core;
using Notepad.Core;
using Xunit;

namespace UI;

// Central launch helpers (D00 T02 §11): the per-file LaunchApp,
// LaunchAppWithArgs, SeedSettings, SeedSettingsFile, and AppExePath copies (21 plus 23 plus 1
// plus 13 plus 15 at filing) delegate here, so background birth
// behavior is set in exactly one place. Four files drain launch
// drops inside their copies (JumpListTask, Launch,
// ProtocolHandler, TabAccessibility); they pass drainLaunchDrops,
// default off everywhere else (draining at launch would hide drops
// a later assert owns).
internal static class UiLaunch
{
    internal const string BackgroundVariable = "SCRATCHPAD_BACKGROUND";

    // Untouched geometry reads off a default instance, so the
    // explicit-geometry rule below tracks ShellSettings instead of
    // a second copy of its 50/50 defaults.
    static readonly ShellSettings Untouched = new();

    internal static bool IsBackground() =>
        Environment.GetEnvironmentVariable(BackgroundVariable) == "1";

    internal static string AppExePath()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return appPath;
    }

    internal static Application LaunchApp() => Application.Launch(AppExePath());

    internal static Application LaunchAppWithArgs(string args, bool drainLaunchDrops = false)
    {
        if (drainLaunchDrops)
        {
            LaunchDrops.Drain();
        }

        return Application.Launch(AppExePath(), args);
    }

    // Background birth (D00 T02 §11 item 2): under
    // SCRATCHPAD_BACKGROUND=1 the first window restores persisted
    // geometry unclamped (MainWindow.RestoreGeometry), so seeding
    // off-screen births it where no census line can call it primary.
    // Explicit geometry always wins: any X/Y the caller set survives,
    // so Primary premises (which seed on-primary rects) are untouched.
    // §18 item 3 replaces the fixed point with a virtual-screen derivation.
    static void SeedBackgroundGeometry(ShellSettings settings)
    {
        if (IsBackground() && settings.X == Untouched.X && settings.Y == Untouched.Y)
        {
            settings.X = 10000;
            settings.Y = 10000;
        }
    }

    // Virtual-screen rectangle from SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN /
    // SM_CXVIRTUALSCREEN / SM_CYVIRTUALSCREEN. Read on a PerMonitorV2 thread
    // so the numbers are physical pixels, matching AppWindow.MoveAndResize.
    internal static ScreenBounds ReadVirtualScreen()
    {
        nint previous = UiDpi.Enter();
        try
        {
            return new ScreenBounds(
                NativeMetrics.GetSystemMetrics(NativeMetrics.SmXVirtualScreen),
                NativeMetrics.GetSystemMetrics(NativeMetrics.SmYVirtualScreen),
                NativeMetrics.GetSystemMetrics(NativeMetrics.SmCxVirtualScreen),
                NativeMetrics.GetSystemMetrics(NativeMetrics.SmCyVirtualScreen));
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    internal static (int X, int Y) CurrentOffScreenBirth(int windowWidth, int windowHeight) =>
        DeriveOffScreenOrigin(ReadVirtualScreen(), windowWidth, windowHeight);

    // The window rect must miss the virtual screen on at least one axis.
    // Preference is a full window-width past the right edge, then flush
    // with that edge, then the same pair above, to the left, and below.
    // A side is skipped when the coordinate does not fit in an int, which
    // is the overflow case: the next side is used instead of wrapping.
    internal static (int X, int Y) DeriveOffScreenOrigin(ScreenBounds screen, int windowWidth, int windowHeight)
    {
        int width = Math.Max(1, windowWidth);
        int height = Math.Max(1, windowHeight);
        long right = (long)screen.X + screen.Width;
        long bottom = (long)screen.Y + screen.Height;
        (int X, int Y)? placed =
            Place(right + width, screen.Y, width, height, screen)
            ?? Place(right, screen.Y, width, height, screen)
            ?? Place(screen.X, (long)screen.Y - height - height, width, height, screen)
            ?? Place(screen.X, (long)screen.Y - height, width, height, screen)
            ?? Place((long)screen.X - width - width, screen.Y, width, height, screen)
            ?? Place((long)screen.X - width, screen.Y, width, height, screen)
            ?? Place(screen.X, bottom + height, width, height, screen)
            ?? Place(screen.X, bottom, width, height, screen);
        if (placed is null)
        {
            throw new InvalidOperationException(
                $"no off-screen birth for virtual {screen.X},{screen.Y} {screen.Width}x{screen.Height} window {width}x{height}");
        }

        return placed.Value;
    }

    internal static bool WindowIntersects(ScreenBounds screen, int x, int y, int width, int height)
    {
        long winRight = (long)x + width;
        long winBottom = (long)y + height;
        long screenRight = (long)screen.X + screen.Width;
        long screenBottom = (long)screen.Y + screen.Height;
        return x < screenRight && screen.X < winRight && y < screenBottom && screen.Y < winBottom;
    }

    static (int X, int Y)? Place(long x, long y, int width, int height, ScreenBounds screen)
    {
        if (x < int.MinValue || y < int.MinValue || x > int.MaxValue || y > int.MaxValue)
        {
            return null;
        }

        if (x > int.MaxValue - width || y > int.MaxValue - height)
        {
            return null;
        }

        int ix = (int)x;
        int iy = (int)y;
        if (WindowIntersects(screen, ix, iy, width, height))
        {
            return null;
        }

        return (ix, iy);
    }

    internal readonly record struct ScreenBounds(int X, int Y, int Width, int Height);

    static class NativeMetrics
    {
        internal const int SmXVirtualScreen = 76;
        internal const int SmYVirtualScreen = 77;
        internal const int SmCxVirtualScreen = 78;
        internal const int SmCyVirtualScreen = 79;

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetSystemMetrics(int index);
    }

    internal static void SeedSettings(ShellSettings settings, bool drainLaunchDrops = false)
    {
        SeedBackgroundGeometry(settings);

        settings.Save();
        // Every close snapshots the session, so a seeded launch also
        // starts session-clean; otherwise the previous test's tabs
        // would restore (and absence-asserting cases would lie).
        SessionData.Delete();
        if (drainLaunchDrops)
        {
            LaunchDrops.Drain();
        }
    }

    // Path-returning seed (SettingsPageTests): same background rule,
    // but the caller owns session cleanup plus the settings file,
    // so no delete here. R1 fix: the per-file copy bypassed
    // off-screen birth for 10 launches.
    internal static string SeedSettingsFile(ShellSettings settings)
    {
        string path = ShellSettings.FilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        SeedBackgroundGeometry(settings);
        settings.Save();
        return path;
    }
}
