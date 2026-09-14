using Xunit;

namespace UI;

// Discovery-time skip for hook-dependent tests: boxes whose policy refuses
// low-level mouse hooks (Conclave-PC) report Skipped with the Win32 error,
// while CI and dev boxes run the test unchanged.
sealed class HookFactAttribute : FactAttribute
{
    public HookFactAttribute()
    {
        if (!UiHooks.AreAvailable(out int error))
        {
            Skip = $"Low-level mouse hooks are unavailable on this host (Win32 error {error}).";
        }
    }
}
