using System.Globalization;

namespace Notepad.Core;

// Live word count and reading time for the status strip, owned by D01 T02
// §9. Words come from TextStats (the Statistics dialog's counter), so the
// strip and the dialog never disagree; the shell debounces the call off
// the keystroke path and runs it on a worker thread.
public static class LiveCounts
{
    // Default 2026-09-27: 200 words per minute, a common silent-reading
    // estimate for general prose, rounded up so any text reads at least
    // "1 min". Cost of changing: this constant and its fixtures.
    public const int WordsPerMinute = 200;

    public static int ReadingMinutes(int words) =>
        words <= 0 ? 0 : (words + WordsPerMinute - 1) / WordsPerMinute;

    public static string Label(int words)
    {
        if (words <= 0)
        {
            return "0 words";
        }

        string count = words.ToString("N0", CultureInfo.InvariantCulture);
        string noun = words == 1 ? "word" : "words";
        return $"{count} {noun}, {ReadingMinutes(words).ToString(CultureInfo.InvariantCulture)} min read";
    }

    public static string Compute(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return Label(TextStats.Compute(text).TotalWords);
    }
}
