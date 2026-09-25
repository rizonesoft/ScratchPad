using Xunit;

namespace UI;

// Discovery-time skip for hook-dependent tests: boxes whose policy refuses
// low-level mouse hooks report Skipped with the Win32 error, while capable
// dev boxes run the test unchanged. Hook-dependent tests drive physical
// input by nature, so this also carries the quiet-hours gate via the shared
// UiQuietHours helper (composition, not inheritance: attributes stay sealed
// per CA1813).
// A capability skip names its owner (the section whose coverage it hides)
// and the host that owes the run (D00 T02 §44 item 3); the nightly reds a
// CAPABILITY skip that names neither.
sealed class HookFactAttribute : FactAttribute
{
    public HookFactAttribute(string owner)
    {
        Owner = owner;
        Skip = UiQuietHours.SkipOutsideWindow(DateTime.Now);
        if (Skip is null && !UiHooks.AreAvailable(out int error))
        {
            Skip = $"CAPABILITY: Low-level mouse hooks are unavailable on this host (Win32 error {error}); owner {owner}; owed on a host whose policy allows low-level mouse hooks.";
        }
    }

    public string Owner { get; }
}
