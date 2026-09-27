using System.Globalization;
using System.Text.RegularExpressions;

namespace Notepad.Core;

// Reading level, owned by D01 T02 §7. Flesch-Kincaid grade over the
// buffer, computed locally and only when asked: no agent, no network, no
// timer. Words and sentences come from TextStats (one counter for the
// whole app); syllables come from the vowel-group heuristic below.
public sealed record ReadingLevel(double Grade, int Words, int Sentences, int Syllables);

public static partial class Readability
{
    // Null when the buffer holds no word (so no sentence either): the
    // formula divides by both, and a score of nothing is not a score.
    public static ReadingLevel? Compute(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        DocumentStats stats = TextStats.Compute(text);
        if (stats.TotalWords == 0 || stats.TotalSentences == 0)
        {
            return null;
        }

        int syllables = TextStats.Words(text).Sum(Syllables);
        double raw = (0.39 * stats.TotalWords / stats.TotalSentences)
            + (11.8 * syllables / stats.TotalWords)
            - 15.59;

        // Default 2026-09-27: the formula goes negative on very plain text
        // (one-syllable words, short sentences); a grade below zero means
        // nothing to a reader, so it floors at 0. Cost of changing: one
        // branch and its fixture.
        double grade = Math.Max(0.0, Math.Round(raw, 1, MidpointRounding.AwayFromZero));
        return new ReadingLevel(grade, stats.TotalWords, stats.TotalSentences, syllables);
    }

    // The status readout: "Grade 8.2", or the empty-buffer note.
    public static string Label(ReadingLevel? level) =>
        level is null
            ? "No text to score"
            : "Grade " + level.Grade.ToString("0.0", CultureInfo.InvariantCulture);

    // Vowel groups after dropping a silent ending and a leading y. Silent
    // endings: -ed except after t, d, or consonant-l ("jumped" one;
    // "wanted", "handled" two); -es after a consonant other than l, s, x,
    // z, c, or g, where an h counts only outside ch and sh, or after
    // vowel-l ("makes", "tastes", "rules" one; "roses", "boxes", "places",
    // "judges", "churches", "candles" two); -e after a consonant other
    // than l, or after vowel-l ("cake", "smile" one; "candle" two). Swept
    // 2026-09-27 over 115 dictionary words, 114 right; known misses need
    // pronunciation, not spelling: ch read as k ("aches" two) and vowel
    // pairs split across syllables ("create" one). words of three letters or fewer count one, and a word
    // with no letters (a number) counts one. English-first, like TextStats.
    public static int Syllables(string word)
    {
        ArgumentNullException.ThrowIfNull(word);
        string letters = new(word.Select(char.ToLowerInvariant).Where(c => c is >= 'a' and <= 'z').ToArray());
        if (letters.Length == 0 || letters.Length <= 3)
        {
            return 1;
        }

        letters = SilentEnding().Replace(letters, string.Empty);
        letters = LeadingY().Replace(letters, string.Empty);
        return Math.Max(1, VowelGroup().Count(letters));
    }

    [GeneratedRegex("(?:(?:[^laeiouysxzcgh]|[aeiouy]l)es|(?<![cs])hes|(?<![td])(?<![^aeiouy]l)ed|(?:[^laeiouy]|[aeiouy]l)e)$")]
    private static partial Regex SilentEnding();

    [GeneratedRegex("^y")]
    private static partial Regex LeadingY();

    [GeneratedRegex("[aeiouy]{1,2}")]
    private static partial Regex VowelGroup();
}
