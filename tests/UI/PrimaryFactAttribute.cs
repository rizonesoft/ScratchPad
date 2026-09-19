using Xunit;

namespace UI;

// Discovery-time gate for Category=Primary placement tests: they prove
// app-chosen placement on the primary without ever activating, which needs
// the no-activate background launch (SCRATCHPAD_BACKGROUND=1). Without the
// flag the app falls through to Activate and the test would steal the
// foreground, so outside the quiet window an unflagged run reports Skipped
// naming the flag; inside the window (or forced) the interruption is
// accepted exactly like an Interactive test.
sealed class PrimaryFactAttribute : FactAttribute
{
    public PrimaryFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("SCRATCHPAD_BACKGROUND") != "1"
            && !UiQuietHours.IsAllowed(DateTime.Now))
        {
            Skip = $"Primary placement needs the no-activate launch outside the foreground window ({UiQuietHours.Window} local); set SCRATCHPAD_BACKGROUND=1 (the placement command) or run inside the window (or with {UiQuietHours.ForceVariable}=1).";
        }
    }
}
