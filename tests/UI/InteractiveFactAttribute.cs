using Xunit;

namespace UI;

// Discovery-time quiet-hours gate: outside the foreground window the test
// reports Skipped naming the window, so a daytime full run can never take
// the foreground. Always paired with [Trait("Category", "Interactive")];
// QuietHoursTests fails any method carrying this attribute without the trait.
sealed class InteractiveFactAttribute : FactAttribute
{
    public InteractiveFactAttribute()
    {
        if (!UiQuietHours.IsAllowed(DateTime.Now))
        {
            Skip = $"Outside the foreground window ({UiQuietHours.Window} local); fenced tests run inside it or with {UiQuietHours.ForceVariable}=1.";
        }
    }
}
