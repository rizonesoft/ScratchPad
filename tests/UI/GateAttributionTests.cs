using Xunit;

namespace UI;

// D00 T02 §49: the gate attributes each window to its process by (pid,
// process start time), never a run-long pid cache. The gate's own
// selftest mode runs the fixtures: a pid cached as the app and later
// reused by a foreign process is attributed to the foreign one (so it is
// never counted against ScratchPad), and an EVENT line names the
// executable it counted. No window, no foreground: it runs in Run A.
public sealed class GateAttributionTests
{
    [Fact]
    public void ReusedPidIsNeverAttributedToTheAppAndLinesNameTheExecutable()
    {
        string pointer = Path.Combine(AppContext.BaseDirectory, "fglogpath.txt");
        Assert.True(File.Exists(pointer), $"gate pointer missing at {pointer}");
        string target = File.ReadAllText(pointer).Trim();
        string exe = target.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ? Path.ChangeExtension(target, ".exe") : target;
        Assert.True(File.Exists(exe), $"gate executable missing at {exe}");
        // Both streams drain asynchronously and the whole run is bounded
        // (R1-I1): a hung selftest is killed at the bound, never waited on.
        // The start goes through the sanctioned launch home (the launch
        // guard; Run A finding).
        var (exit, output) = UiLaunch.RunToolCaptured(exe, "selftest", TimeSpan.FromSeconds(30));
        Assert.True(exit == 0, exit == -1 ? $"the gate selftest did not finish within 30 s and was killed: {output}" : $"the gate selftest failed (exit {exit}): {output}");
        Assert.Contains("selftest: reused pid attributed to Photos (not flagged): ok", output, StringComparison.Ordinal);
        Assert.Matches(@"selftest: event line names its executable \(EVENT 4660 pid=\d+ exe=[A-Za-z]:\\\S*ForegroundLog\.exe started=\d{4}-", output);
    }
}
