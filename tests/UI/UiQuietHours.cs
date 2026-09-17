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
