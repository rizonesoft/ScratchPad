namespace Notepad.Core;

// Binding mutation seam (D00 T02 §36 item 1). The binding guard proves a
// covering test presses its chord and reads state afterwards, but syntax
// cannot prove the assertion observes the command: `int observed = 0;
// Assert.Equal(0, observed);` passes every static rule. The mutation run
// proves it by execution: it launches the app with one bound command
// suppressed and requires the covering test to fail. The seam is
// test-only by construction, like the launch capture: it activates only
// when the mutation variable names a target AND the test-run marker is
// exactly "1". A target is a menu item's AutomationId (the bound handler
// returns before its host call) or `vk:<virtual key>:<modifiers>` for a
// programmatic tab accelerator (the accelerator is handled and does
// nothing).
public static class TestMutation
{
    public const string Variable = "SCRATCHPAD_TEST_MUTATE";

    // The active target, else null (no mutation).
    public static string? Active(Func<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        string? target = environment(Variable);
        return !string.IsNullOrWhiteSpace(target) && string.Equals(environment(LaunchCapture.RunMarkerVariable), "1", StringComparison.Ordinal)
            ? target
            : null;
    }

    // True when the run suppresses this bound command.
    public static bool Suppresses(string command, Func<string, string?> environment) =>
        string.Equals(Active(environment), command, StringComparison.Ordinal);

    // The target naming a programmatic accelerator by its key and modifiers.
    public static string Key(int virtualKey, int modifiers) =>
        FormattableString.Invariant($"vk:{virtualKey}:{modifiers}");
}
