using System.Diagnostics;
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
        var start = new ProcessStartInfo(exe, "selftest")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        using Process p = Process.Start(start)!;
        // Both streams drain asynchronously and the whole run is bounded
        // (R1-I1): a hung selftest is killed at the bound, never waited on.
        var stdout = new System.Text.StringBuilder();
        var stderr = new System.Text.StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data is not null) { lock (stdout) { stdout.AppendLine(e.Data); } } };
        p.ErrorDataReceived += (_, e) => { if (e.Data is not null) { lock (stderr) { stderr.AppendLine(e.Data); } } };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        if (!p.WaitForExit(30_000))
        {
            p.Kill(entireProcessTree: true);
            Assert.Fail($"the gate selftest did not finish within 30 s and was killed: {stdout}{stderr}");
        }

        p.WaitForExit();
        string output;
        lock (stdout)
        {
            output = stdout.ToString() + stderr.ToString();
        }

        Assert.True(p.ExitCode == 0, $"the gate selftest failed (exit {p.ExitCode}): {output}");
        Assert.Contains("selftest: reused pid attributed to Photos (not flagged): ok", output, StringComparison.Ordinal);
        Assert.Matches(@"selftest: event line names its executable \(EVENT 4660 pid=\d+ exe=[A-Za-z]:\\\S*ForegroundLog\.exe started=\d{4}-", output);
    }
}
