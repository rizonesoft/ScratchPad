using Xunit;

namespace UI;

// Discovery-time skip for hook-dependent tests: boxes whose policy refuses
// low-level mouse hooks report Skipped with the Win32 error, while capable
// dev boxes run the test unchanged. Hook-dependent tests drive physical
// input by nature, so this also carries the quiet-hours gate via the shared
// UiQuietHours helper (composition, not inheritance: attributes stay sealed
// per CA1813).
sealed class HookFactAttribute : FactAttribute
{
    public HookFactAttribute()
    {
        Skip = UiQuietHours.SkipOutsideWindow(DateTime.Now);
        if (Skip is null && !UiHooks.AreAvailable(out int error))
        {
            Skip = $"Low-level mouse hooks are unavailable on this host (Win32 error {error}).";
        }
    }
}
