using Notepad.Core;

namespace UI;

// D00 T02 §28 item 7: one owner for the launch capture seam in the UI
// suite. It sets the capture variable and the test-run marker the app
// requires (both are inherited by the launched app), and on dispose
// restores both prior values and deletes the capture file, so no test
// leaks an armed seam or a stray capture into the next one.
internal sealed class LaunchCaptureScope : IDisposable
{
    readonly string? priorCapture = Environment.GetEnvironmentVariable(LaunchCapture.CaptureVariable);
    readonly string? priorMarker = Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable);

    internal LaunchCaptureScope(string? path = null)
    {
        Path = path ?? System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"scratchpad-launch-{Guid.NewGuid():N}.txt");
        Environment.SetEnvironmentVariable(LaunchCapture.CaptureVariable, Path);
        Environment.SetEnvironmentVariable(LaunchCapture.RunMarkerVariable, "1");
    }

    internal string Path { get; }

    internal string[] Lines() =>
        File.Exists(Path) ? File.ReadAllLines(Path).Where(l => l.Length > 0).ToArray() : [];

    // The first capture, then a settle window: a second dispatch of the
    // same press lands inside it, so exactly-once is observable.
    internal string[] WaitForCapture(TimeSpan settle)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline && Lines().Length == 0)
        {
            Thread.Sleep(200);
        }

        if (Lines().Length > 0)
        {
            Thread.Sleep(settle);
        }

        return Lines();
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable(LaunchCapture.CaptureVariable, priorCapture);
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
