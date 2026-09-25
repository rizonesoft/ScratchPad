using Notepad.Core;

namespace UI;

// D00 T02 §36 item 4: one owner for the routing oracle's observe mode.
// It arms the mutation seam with `*` (every bound command runs nothing
// and logs its dispatch), names the dispatch log, and sets the test-run
// marker, all inherited by the launched app; on dispose it restores the
// prior values and deletes the log, like LaunchCaptureScope.
internal sealed class DispatchLogScope : IDisposable
{
    readonly string? priorTarget = Environment.GetEnvironmentVariable(TestMutation.Variable);
    readonly string? priorLog = Environment.GetEnvironmentVariable(TestMutation.DispatchLogVariable);
    readonly string? priorMarker = Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable);
    int consumed;

    internal DispatchLogScope()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"scratchpad-dispatch-{Guid.NewGuid():N}.log");
        Environment.SetEnvironmentVariable(TestMutation.Variable, TestMutation.ObserveAll);
        Environment.SetEnvironmentVariable(TestMutation.DispatchLogVariable, Path);
        Environment.SetEnvironmentVariable(LaunchCapture.RunMarkerVariable, "1");
    }

    internal string Path { get; }

    // The dispatches logged since the last call, after a settle window.
    internal string[] Next(TimeSpan settle)
    {
        Thread.Sleep(settle);
        string[] all = File.Exists(Path) ? File.ReadAllLines(Path).Where(l => l.Length > 0).ToArray() : [];
        string[] fresh = all[consumed..];
        consumed = all.Length;
        return fresh;
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable(TestMutation.Variable, priorTarget);
        Environment.SetEnvironmentVariable(TestMutation.DispatchLogVariable, priorLog);
        Environment.SetEnvironmentVariable(LaunchCapture.RunMarkerVariable, priorMarker);
        try
        {
            File.Delete(Path);
        }
        catch (IOException)
        {
            // Best-effort cleanup; the assertion already ran.
        }
        catch (UnauthorizedAccessException)
        {
            // Same: never mask the test's own verdict.
        }
    }
}
