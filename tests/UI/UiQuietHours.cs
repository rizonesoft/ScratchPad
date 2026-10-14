namespace UI;

// Quiet-hours gate for fenced Interactive tests: the operator's foreground
// window is 02:00-06:50 local, and outside it every fenced test reports
// Skipped instead of running, so a daytime full run can never interrupt.
// SCRATCHPAD_INTERACTIVE_WINDOW ("HH:mm-HH:mm") moves the window;
// SCRATCHPAD_INTERACTIVE_FORCE=1 runs regardless, for an explicitly accepted
// interruption. Unparseable config fails closed (skip, never run).
internal static class UiQuietHours
{
    internal const string DefaultWindow = "02:00-06:50";
    internal const string WindowVariable = "SCRATCHPAD_INTERACTIVE_WINDOW";
    internal const string ForceVariable = "SCRATCHPAD_INTERACTIVE_FORCE";

    internal static string Window =>
        Environment.GetEnvironmentVariable(WindowVariable) is { Length: > 0 } w ? w : DefaultWindow;

    internal static bool IsAllowed(DateTime now) =>
        Environment.GetEnvironmentVariable(ForceVariable) == "1"
        || (TryParseWindow(Window, out TimeSpan start, out TimeSpan end)
            && IsInWindow(now.TimeOfDay, start, end));

    internal static string? SkipOutsideWindow(DateTime now) =>
        IsAllowed(now) ? null : $"Outside the foreground window ({Window} local); fenced tests run inside it or with {ForceVariable}=1.";

    // The fenced gates' full verdict. A forced run is a daytime fenced run
    // (the section gate's scoped step, the operator's phase-close run), so
    // it first waits for the operator to go idle (UiOperatorIdle) and never
    // fights the operator's own typing. An unforced run never waits: it
    // runs fenced tests only inside the window, and a focus-free run there
    // must not stall on an idle check for tests its filter excludes.
    internal static string? SkipUnlessForegroundFree(DateTime now) =>
        SkipOutsideWindow(now)
        ?? (Environment.GetEnvironmentVariable(ForceVariable) == "1" ? UiOperatorIdle.SkipUnlessIdle() : null);

    internal static bool IsInWindow(TimeSpan time, TimeSpan start, TimeSpan end) =>
        start <= end ? time >= start && time < end : time >= start || time < end;

    internal static bool TryParseWindow(string window, out TimeSpan start, out TimeSpan end)
    {
        start = default;
        end = default;
        string[] parts = window.Split('-', StringSplitOptions.TrimEntries);
        return parts.Length == 2
            && TimeSpan.TryParse(parts[0], out start)
            && TimeSpan.TryParse(parts[1], out end);
    }
}
