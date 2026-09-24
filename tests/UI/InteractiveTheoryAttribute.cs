using Xunit;

namespace UI;

// The Theory twin of InteractiveFact (D00 T02 §21 item 2): the same
// discovery-time quiet-hours gate, so every data row of a fenced theory
// skips outside the foreground window and reports alone inside it.
// Always paired with [Trait("Category", "Interactive")]; QuietHoursTests
// checks both directions for this gate too.
sealed class InteractiveTheoryAttribute : TheoryAttribute
{
    public InteractiveTheoryAttribute()
    {
        Skip = UiQuietHours.SkipOutsideWindow(DateTime.Now);
    }
}
