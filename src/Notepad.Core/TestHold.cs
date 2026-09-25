namespace Notepad.Core;

// Test-only hold before the first window (D00 T02 §41 item 9). Under the
// run marker plus SCRATCHPAD_TEST_HOLD=<name>, the app signals the named
// event <name>-held when it reaches the point just before its first
// window, then waits (bounded) for <name>-release. The UI suite reads the
// process's windows from outside while the app is held, so the first
// birth's preexisting set is checked against an observation the app's own
// snapshot did not make. Unarmed (the normal case) it returns at once.
public static class TestHold
{
    public const string Variable = "SCRATCHPAD_TEST_HOLD";

    public static readonly TimeSpan Bound = TimeSpan.FromSeconds(30);

    public static string? Armed(Func<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        string? name = environment(Variable);
        return !string.IsNullOrWhiteSpace(name) && string.Equals(environment(LaunchCapture.RunMarkerVariable), "1", StringComparison.Ordinal) ? name : null;
    }

    // Returns true when the hold ran and was released, false when unarmed
    // or when the events are missing or the bound passed (the app then
    // carries on: a hold never wedges a launch).
    public static bool WaitIfArmed(Func<string, string?> environment)
    {
        string? name = Armed(environment);
        if (name is null || !OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var held = EventWaitHandle.OpenExisting(name + "-held");
            using var release = EventWaitHandle.OpenExisting(name + "-release");
            _ = held.Set();
            return release.WaitOne(Bound);
        }
        catch (Exception ex) when (ex is WaitHandleCannotBeOpenedException or UnauthorizedAccessException or IOException)
        {
            return false;
        }
    }
}
