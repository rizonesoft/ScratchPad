using System.Diagnostics;
using System.Runtime.CompilerServices;
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

    // Last seed decision, consumed once by the next launch record
    // (D00 T02 §18 item 7): every UI test seeds before it launches,
    // so call-order pairing is exact in-suite; the UI collection
    // runs serial, so no lock is needed.
    static (string Move, int X, int Y)? _lastSeed;

    static string TestId(string? member, string? file) =>
        $"{(file is null ? "unknown" : Path.GetFileName(file))}:{member ?? "unknown"}";

    static (string Move, int X, int Y) TakeSeed()
    {
        (string Move, int X, int Y) seed = _lastSeed ?? ("unseeded-defaults", 0, 0);
        _lastSeed = null;
        return seed;
    }

    static Application LaunchRecorded(
        Func<Application> launch,
        string args,
        string? member,
        string? file)
    {
        (string move, int x, int y) = TakeSeed();
        string testId = TestId(member, file);
        // Every app launch arms the app's sweep log (D00 T02 §41 item 8), so
        // the launch record quotes the birth's sweep line: a scope's log when
        // one is armed, else a per-launch file the record consumes.
        string? scoped = Environment.GetEnvironmentVariable(UiLaunchDiagnostics.SweepLogVariable);
        string? priorMarker = Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable);
        string sweepLog = scoped ?? UiLaunchDiagnostics.NewSweepLogPath();
        try
        {
            Application app;
            try
            {
                if (scoped is null)
                {
                    Environment.SetEnvironmentVariable(UiLaunchDiagnostics.SweepLogVariable, sweepLog);
                    Environment.SetEnvironmentVariable(LaunchCapture.RunMarkerVariable, "1");
                }

                app = launch();
            }
            finally
            {
                if (scoped is null)
                {
                    Environment.SetEnvironmentVariable(UiLaunchDiagnostics.SweepLogVariable, null);
                    Environment.SetEnvironmentVariable(LaunchCapture.RunMarkerVariable, priorMarker);
                }
            }

            UiLaunchDiagnostics.Record(testId, args, app.ProcessId, null, move, x, y, sweepLog: sweepLog, ownsSweepLog: scoped is null);
            return app;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            string first = ex.Message.Split(["\r\n", "\n"], StringSplitOptions.None)[0];
            UiLaunchDiagnostics.Record(testId, args, null, $"{ex.GetType().Name}: {first}", "launch-failed", 0, 0);
            throw;
        }
    }

    internal static Application LaunchApp(
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null) =>
        LaunchRecorded(() => Application.Launch(AppExePath()), string.Empty, member, file);

    internal static Application LaunchAppWithArgs(
        string args,
        bool drainLaunchDrops = false,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        if (drainLaunchDrops)
        {
            LaunchDrops.Drain();
        }

        return LaunchRecorded(() => Application.Launch(AppExePath(), args), args, member, file);
    }

    // Explicit-exe launch (D00 T02 §18 item 6): tests that derive the
    // executable themselves (registered open commands, capture paths)
    // still launch through the one home, so the guard sees no bypass.
    internal static Application LaunchAppWithExe(
        string exe,
        string args,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null) =>
        LaunchRecorded(() => Application.Launch(exe, args), args, member, file);

    // Headless runs (D00 T02 §18 item 6): flag and registration probes
    // that need exit codes (plus stderr) without a window. The two
    // per-file RunHeadless copies delegate here.
    internal static int RunHeadless(
        string args,
        TimeSpan timeout,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        (string _, int x, int y) = TakeSeed();
        string testId = TestId(member, file);
        try
        {
            using var process = Process.Start(new ProcessStartInfo(AppExePath(), args) { UseShellExecute = false });
            Assert.NotNull(process);
            Assert.True(process.WaitForExit(timeout), $"headless run timed out: {args}");
            UiLaunchDiagnostics.Record(testId, args, process.Id, null, "headless", x, y, expectWindow: false);
            return process.ExitCode;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            string first = ex.Message.Split(["\r\n", "\n"], StringSplitOptions.None)[0];
            UiLaunchDiagnostics.Record(testId, args, null, $"{ex.GetType().Name}: {first}", "launch-failed", 0, 0, expectWindow: false);
            throw;
        }
    }

    internal static (int Exit, string Stderr) RunHeadlessCapture(
        string args,
        TimeSpan timeout,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        (string _, int x, int y) = TakeSeed();
        string testId = TestId(member, file);
        try
        {
            using var process = Process.Start(new ProcessStartInfo(AppExePath(), args)
            {
                UseShellExecute = false,
                RedirectStandardError = true,
            });
            Assert.NotNull(process);
            Assert.True(process.WaitForExit(timeout), $"headless run timed out: {args}");
            UiLaunchDiagnostics.Record(testId, args, process.Id, null, "headless", x, y, expectWindow: false);
            return (process.ExitCode, process.StandardError.ReadToEnd());
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            string first = ex.Message.Split(["\r\n", "\n"], StringSplitOptions.None)[0];
            UiLaunchDiagnostics.Record(testId, args, null, $"{ex.GetType().Name}: {first}", "launch-failed", 0, 0, expectWindow: false);
            throw;
        }
    }

    // Child test runs (D00 T02 §36 item 1): the binding mutation run
    // executes one covering test in a child `dotnet test` over this
    // assembly with extra environment (the mutation target and the run
    // marker), which the app it launches inherits. Output is read to the
    // end on both streams; a run past the timeout is killed and reported.
    internal static (int Exit, string Output) RunChildTest(
        string filter,
        IReadOnlyDictionary<string, string> environment,
        TimeSpan timeout,
        string extraArgs = "",
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        ArgumentNullException.ThrowIfNull(environment);
        TakeSeed();
        string testId = TestId(member, file);
        string root = AppContext.BaseDirectory;
        while (!Directory.Exists(Path.Combine(root, "tests", "UI")))
        {
            root = Path.GetDirectoryName(root) ?? throw new InvalidOperationException("repo root not found above the test assembly");
        }

        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH") is { Length: > 0 } host && File.Exists(host)
            ? host
            : Path.Combine(root, ".tools", "dotnet-win-x64", "dotnet.exe");
        string assembly = typeof(UiLaunch).Assembly.Location;
        string args = $"test \"{assembly}\" --filter \"{filter}\"" + (extraArgs.Length > 0 ? " " + extraArgs : string.Empty);
        var info = new ProcessStartInfo(dotnet, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var (name, value) in environment)
        {
            info.Environment[name] = value;
        }

        using var process = Process.Start(info);
        Assert.NotNull(process);
        UiLaunchDiagnostics.Record(testId, args, process.Id, null, "child-test", 0, 0, expectWindow: false);
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(timeout))
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
            return (-1, $"child test run killed after {timeout.TotalSeconds:0} s: {filter}\n{stdout.Result}{stderr.Result}");
        }

        return (process.ExitCode, stdout.Result + stderr.Result);
    }

    // Tool runs (D00 T02 §18 item 8): gate and probe subprocesses.
    // The caller owns the process (wait plus dispose); the start
    // itself stays in the one home, so the guard sees no bypass.
    // No window is ever expected, hence no first-window wait.
    internal static Process RunTool(
        string exe,
        string args,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        TakeSeed();
        string testId = TestId(member, file);
        try
        {
            Process? process = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false });
            Assert.NotNull(process);
            UiLaunchDiagnostics.Record(testId, args, process.Id, null, "tool", 0, 0, expectWindow: false);
            return process;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            string first = ex.Message.Split(["\r\n", "\n"], StringSplitOptions.None)[0];
            UiLaunchDiagnostics.Record(testId, args, null, $"{ex.GetType().Name}: {first}", "launch-failed", 0, 0, expectWindow: false);
            throw;
        }
    }

    // Shell launch (D00 T02 §18 item 6): protocol and URL probes that
    // need shell execution. The caller owns the process (attach plus
    // dispose); the launch itself stays in the one home.
    internal static Process? ShellLaunch(
        string url,
        [CallerMemberName] string? member = null,
        [CallerFilePath] string? file = null)
    {
        (string _, int x, int y) = TakeSeed();
        string testId = TestId(member, file);
        try
        {
            Process? process = Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            UiLaunchDiagnostics.Record(testId, url, process?.Id, null, "shell", x, y);
            return process;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            string first = ex.Message.Split(["\r\n", "\n"], StringSplitOptions.None)[0];
            UiLaunchDiagnostics.Record(testId, url, null, $"{ex.GetType().Name}: {first}", "launch-failed", 0, 0);
            throw;
        }
    }

    // Background birth (D00 T02 §11 item 2, derivation D00 T02 §18
    // item 3): under SCRATCHPAD_BACKGROUND=1 the first window
    // restores persisted geometry unclamped
    // (MainWindow.RestoreGeometry), so seeding off-screen births it
    // where no census line can call it primary. The point derives
    // from the virtual screen (never the old fixed 10000, which a
    // very-wide topology can contain), sized for this window with
    // overflow-safe placement. Explicit geometry always wins: any
    // X/Y the caller set survives, so Primary premises (which seed
    // on-primary rects) are untouched.
    static void SeedBackgroundGeometry(ShellSettings settings)
    {
        if (IsBackground() && settings.X == Untouched.X && settings.Y == Untouched.Y)
        {
            (int x, int y) = DeriveOffScreenOrigin(ReadVirtualScreen(), settings.Width, settings.Height);
            settings.X = x;
            settings.Y = y;
            _lastSeed = ("seeded-offscreen", x, y);
        }
        else if (settings.X != Untouched.X || settings.Y != Untouched.Y)
        {
            _lastSeed = ("explicit-kept", settings.X, settings.Y);
        }
        else
        {
            _lastSeed = ("unseeded-defaults", settings.X, settings.Y);
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
