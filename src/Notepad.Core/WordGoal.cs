using System.Globalization;
using System.Text.RegularExpressions;

namespace Notepad.Core;

// Session word goal, owned by D01 T02 §11. The goal lives only in the
// window that set it (never persisted, never synced): the status strip
// holds it and the §9 live count feeds its progress line.
//
// Default 2026-09-27: progress reads the active document's live word
// count against the goal (the words the strip already shows), not words
// added since the goal was set. Cost of changing: a baseline captured at
// set time and one subtraction.
public static partial class WordGoal
{
    public const int Max = 1_000_000;

    // Whole numbers 1..Max; surrounding spaces and correctly grouped
    // thousands separators ("1,000") are accepted, misplaced ones ("1,,0",
    // "10,", "1,00") are refused. Returns the goal, or null with the
    // message to show.
    public static (int? Goal, string? Error) Parse(string? input)
    {
        string text = (input ?? string.Empty).Trim();
        if (!Grouped().IsMatch(text)
            || !int.TryParse(text, NumberStyles.AllowThousands, CultureInfo.InvariantCulture, out int goal))
        {
            return (null, "Enter a whole number of words.");
        }

        if (goal < 1)
        {
            return (null, "Enter a goal of at least 1 word.");
        }

        if (goal > Max)
        {
            return (null, $"Enter a goal of at most {Max.ToString("N0", CultureInfo.InvariantCulture)} words.");
        }

        return (goal, null);
    }

    // Percent of the goal reached, 0..100; reaching or passing the goal
    // is a full line.
    public static double Percent(int words, int goal) =>
        goal <= 0 ? 0 : Math.Clamp(words * 100.0 / goal, 0, 100);

    [GeneratedRegex(@"\A(?:\d+|\d{1,3}(?:,\d{3})+)\z")]
    private static partial Regex Grouped();

    public static string Label(int? goal) =>
        goal is int g ? $"Word goal {g.ToString("N0", CultureInfo.InvariantCulture)}" : "Set word goal";
}
