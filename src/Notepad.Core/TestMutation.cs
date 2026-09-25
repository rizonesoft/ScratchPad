namespace Notepad.Core;

// Binding mutation seam (D00 T02 §36 item 1). The binding guard proves a
// covering test presses its chord and reads state afterwards, but syntax
// cannot prove the assertion observes the command: `int observed = 0;
// Assert.Equal(0, observed);` passes every static rule. The mutation run
// proves it by execution: it launches the app with one bound command
// swapped for another host member and requires the covering test to
// fail. The seam is test-only by construction, like the launch capture:
// it activates only when the mutation variable names a target AND the
// test-run marker is exactly "1". A target is a menu item's AutomationId
// or `vk:<virtual key>:<modifiers>` for a programmatic tab accelerator.
// The target `*` is the routing oracle's observe mode (§36 item 4):
// every bound command is suppressed and its dispatch is appended to the
// dispatch log, so a test can press every chord on every surface and
// read which ones reached a command, with no command's side effects.
public static class TestMutation
{
    public const string Variable = "SCRATCHPAD_TEST_MUTATE";
    public const string DispatchLogVariable = "SCRATCHPAD_TEST_DISPATCH_LOG";
    public const string ObserveAll = "*";

    // The active target, else null (no mutation).
    public static string? Active(Func<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        string? target = environment(Variable);
        return !string.IsNullOrWhiteSpace(target) && string.Equals(environment(LaunchCapture.RunMarkerVariable), "1", StringComparison.Ordinal)
            ? target
            : null;
    }

    // What a bound command does under the active mutation.
    public static MutationEffect For(string command, Func<string, string?> environment)
    {
        string? target = Active(environment);
        return target is null ? MutationEffect.None
            : string.Equals(target, ObserveAll, StringComparison.Ordinal) ? MutationEffect.Observe
            : string.Equals(target, command, StringComparison.Ordinal) ? MutationEffect.Swap
            : MutationEffect.None;
    }

    // Observe mode: one line per dispatch. Returns null on success, else
    // the failure text (a lost line would read as a suppressed chord).
    public static string? Record(string command, Func<string, string?> environment, Action<string, string>? append = null)
    {
        ArgumentNullException.ThrowIfNull(environment);
        string? log = environment(DispatchLogVariable);
        if (string.IsNullOrWhiteSpace(log))
        {
            return $"dispatch log unset: {command} dispatched with nowhere to record it";
        }

        append ??= File.AppendAllText;
        try
        {
            append(log, command + "\n");
            return null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return $"dispatch log failed: could not write {log} ({ex.GetType().Name}: {ex.Message})";
        }
    }

    // Observe mode's recorder in the app (§36 R2-F2): a lost line would read
    // as a suppressed chord, so a failed write ends the test-only process at
    // once; the routing test checks the app is alive after every press, so
    // lost evidence fails the proof instead of passing a suppress row.
    public static void RecordOrFail(string command, Func<string, string?> environment, Action<string>? fail = null)
    {
        string? error = Record(command, environment);
        if (error is not null)
        {
            (fail ?? (msg => Environment.FailFast(msg)))(error);
        }
    }

    // Swap evidence (D00 T02 §43 item 1): a swapped command appends
    // `swap:<command>` to the dispatch log when one is set, so the mutation
    // run can prove the substitute ran; best effort (a missing log leaves
    // the case inconclusive, never killed).
    public static string SwapLine(string command) => "swap:" + command;

    public static void RecordSwap(string command, Func<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        if (string.IsNullOrWhiteSpace(environment(DispatchLogVariable)))
        {
            return;
        }

        _ = Record(SwapLine(command), environment);
    }

    // The target naming a programmatic accelerator by its key and modifiers.
    public static string Key(int virtualKey, int modifiers) =>
        FormattableString.Invariant($"vk:{virtualKey}:{modifiers}");
}

// What a bound command does under the active mutation.
public enum MutationEffect
{
    // Run the command as shipped.
    None,

    // Run the substitute host member instead (this command is the target).
    Swap,

    // Run nothing and log the dispatch (observe mode).
    Observe,
}
