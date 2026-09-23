using Screen = System.Windows.Forms.Screen;
using FlaUI.Core;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 8: the gate detects a brief primary resting
// window. A planted 1.5 s on-primary dwell (about six 250 ms polls,
// far past the seen-twice rule) trips the gate red; the same run
// with an off-screen birth stays green. The plant shows no-activate,
// so the trip proves census sensitivity, not a foreground hold
// (asserted: no FORE line names the app). The plant point derives
// from the primary monitor at runtime, so any layout works. The
// exact seen-twice boundary is phase-dependent by construction (the
// §13 lesson), so no test pins it: the plant dwells 3x past the
// two-poll minimum, which is the sensitivity claim that must hold.
// The 12 s gate window covers cold-box attach latency; the idle tail
// after the plant closes is designed waste, mirroring the nightly gate.
[Collection("UI tests")]
public sealed class GateCalibrationTests
{
    [PrimaryFact]
    [Trait("Category", "Primary")]
    public void PlantedDwellTripsTheGate()
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
            string log = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".log");
            (string gateExe, string gateArgs) = GateCommand(log);
            try
            {
                using var gateRun = UiLaunch.RunTool(gateExe, gateArgs);
                Assert.NotNull(gateRun);
                Thread.Sleep(1000);
                nint fgBefore = UiForeground.Capture();
                var primary = Screen.PrimaryScreen!.Bounds;
                UiLaunch.SeedSettings(new ShellSettings { X = primary.X + 100, Y = primary.Y + 100, WhatsNewSeen = true });
                using var app = UiLaunch.LaunchApp();
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    UiForeground.InPlace(window, fgBefore);
                    nint hwnd = window.Properties.NativeWindowHandle.Value;
                    Assert.True(SpinVisible(hwnd, TimeSpan.FromSeconds(5)), "plant never showed");
                    Thread.Sleep(1500);
                }
                finally
                {
                    CloseAll(app, automation);
                }

                Assert.True(gateRun.WaitForExit(30000), "gate did not exit");
                if (gateRun.ExitCode != 1)
                {
                    KeepFailureLog(log, gateRun.ExitCode);
                }

                Assert.Equal(1, gateRun.ExitCode);
                string[] lines = File.ReadAllLines(log);
                Assert.Contains(lines, line => line.Contains(" primary ", StringComparison.Ordinal));
                Assert.DoesNotContain(lines, IsAppForegroundLine);
            }
            finally
            {
                File.Delete(log);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }

    [Fact]
    public void NoPlantKeepsTheGateGreen()
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
            string log = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".log");
            (string gateExe, string gateArgs) = GateCommand(log);
            try
            {
                using var gateRun = UiLaunch.RunTool(gateExe, gateArgs);
                Assert.NotNull(gateRun);
                Thread.Sleep(1000);
                UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
                using var app = UiLaunch.LaunchApp();
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Thread.Sleep(1500);
                }
                finally
                {
                    CloseAll(app, automation);
                }

                Assert.True(gateRun.WaitForExit(30000), "gate did not exit");
                if (gateRun.ExitCode != 0)
                {
                    KeepFailureLog(log, gateRun.ExitCode);
                }

                Assert.Equal(0, gateRun.ExitCode);
            }
            finally
            {
                File.Delete(log);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }

    static bool IsAppForegroundLine(string line)
    {
        if (line.StartsWith("EVENT ", StringComparison.Ordinal)
            || line.StartsWith("CENSUS ", StringComparison.Ordinal))
        {
            return false;
        }

        string[] parts = line.Split(' ', 4);
        return parts.Length >= 3
            && string.Equals(parts[2], "ScratchPad", StringComparison.OrdinalIgnoreCase);
    }

    static bool SpinVisible(nint hwnd, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (UiLaunchDiagnostics.IsVisible(hwnd))
            {
                return true;
            }

            Thread.Sleep(100);
        }

        return false;
    }

    static void KeepFailureLog(string log, int exitCode)
    {
        try
        {
            string kept = Path.Combine(
                AppContext.BaseDirectory,
                "launch-diagnostics",
                $"gate-calibration-fail-{exitCode}-{DateTime.UtcNow:HHmmss}.log");
            Directory.CreateDirectory(Path.GetDirectoryName(kept)!);
            File.Copy(log, kept, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    static (string Exe, string Args) GateCommand(string log)
    {
        string pointer = Path.Combine(AppContext.BaseDirectory, "fglogpath.txt");
        Assert.True(File.Exists(pointer), $"gate pointer missing at {pointer}");
        string target = File.ReadAllText(pointer).Trim();
        if (target.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            string exe = Path.ChangeExtension(target, ".exe");
            if (File.Exists(exe))
            {
                return (exe, $"12 \"{log}\"");
            }

            return ("dotnet", $"\"{target}\" 12 \"{log}\"");
        }

        Assert.True(File.Exists(target), $"gate missing at {target}");
        return (target, $"12 \"{log}\"");
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
