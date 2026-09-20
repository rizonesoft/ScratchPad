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
    // Off-screen birth coordinate, shared with the funnel's
    // single-monitor fallback (UiForeground.PickSuiteOrigin).
    internal const int OffScreen = 10000;

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
    // off-screen births it where no census line can see it and the
    // R2 birth flashes (61 per Run A at the 50,50 cascade) never
    // paint. Explicit geometry always wins: any X/Y the caller set
    // survives, so Primary premises (which seed on-primary rects)
    // are untouched.
    static void SeedBackgroundGeometry(ShellSettings settings)
    {
        if (IsBackground() && settings.X == Untouched.X && settings.Y == Untouched.Y)
        {
            settings.X = OffScreen;
            settings.Y = OffScreen;
        }
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
