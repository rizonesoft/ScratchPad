namespace UI;

// The Theory twin of InteractiveFact (D00 T02 §21 item 2): the same
// discovery-time quiet-hours gate, so every data row of a fenced theory
// skips outside the foreground window and reports alone inside it.
// Always paired with [Trait("Category", "Interactive")]; QuietHoursTests
// checks both directions for this gate too. A gated Theory since D00 T02
// §37 item 3: the gate lifts while the population discovery lists.
sealed class InteractiveTheoryAttribute : GatedTheoryAttribute
{
    public InteractiveTheoryAttribute()
    {
        Gate(UiQuietHours.SkipOutsideWindow(DateTime.Now));
    }
}
