namespace Notepad.Core;

// Document statistics, owned by D01 T01 §14. UI-free: the panel binds to
// StatsController and renders Current; compute runs on open and refresh only,
// never while typing. The text arrives through ITextProvider until D02 T01 §1
// binds the real buffer.
public interface ITextProvider
{
    string GetText();
}

public sealed record WordCount(string Word, int Count);

public sealed record SentenceBuckets(int Small, int Medium, int Large);

public sealed record DocumentStats(
    int TotalWords,
    int TotalSentences,
    double MeanSentenceLength,
    int ShortestSentence,
    int LongestSentence,
    SentenceBuckets Buckets,
    IReadOnlyList<WordCount> TopWords,
    IReadOnlyList<string> RepeatedWords);

public static class TextStats
{
    public const int MaxTopWords = 10;
    public const int RepeatThreshold = 3;
    public const int MediumSentenceMin = 11;
    public const int LongSentenceMin = 26;

    // Small built-in English stopword set (English-first, per the section).
    private static readonly HashSet<string> StopWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "when",
        "at", "by", "for", "with", "about", "into", "through", "during",
        "of", "on", "to", "in", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "do", "does", "did", "will", "would",
        "should", "could", "can", "may", "might", "must", "shall", "it", "its",
        "this", "that", "these", "those", "i", "you", "he", "she", "we", "they",
        "them", "his", "her", "our", "your", "as", "from", "not", "no", "so",
        "than", "too", "very", "just", "over", "after", "before", "between",
        "up", "out", "also", "there", "here",
    };

    public static DocumentStats Compute(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        List<string> sentences = SplitSentences(text);
        Dictionary<string, int> counts = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> display = new(StringComparer.OrdinalIgnoreCase);
        List<int> lengths = [];
        int total = 0;
        foreach (string sentence in sentences)
        {
            List<string> words = Tokenize(sentence);
            lengths.Add(words.Count);
            foreach (string word in words)
            {
                total++;
                counts[word] = counts.TryGetValue(word, out int count) ? count + 1 : 1;
                display.TryAdd(word, word);
            }
        }

        List<WordCount> top = counts
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => display[pair.Key], StringComparer.Ordinal)
            .Take(MaxTopWords)
            .Select(pair => new WordCount(display[pair.Key], pair.Value))
            .ToList();
        List<string> repeated = counts
            .Where(pair => pair.Value >= RepeatThreshold && !StopWords.Contains(pair.Key))
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => display[pair.Key], StringComparer.Ordinal)
            .Select(pair => display[pair.Key])
            .ToList();
        return new DocumentStats(
            total,
            sentences.Count,
            lengths.Count == 0 ? 0.0 : (double)total / lengths.Count,
            lengths.Count == 0 ? 0 : lengths.Min(),
            lengths.Count == 0 ? 0 : lengths.Max(),
            new SentenceBuckets(
                lengths.Count(length => length < MediumSentenceMin),
                lengths.Count(length => length >= MediumSentenceMin && length < LongSentenceMin),
                lengths.Count(length => length >= LongSentenceMin)),
            top,
            repeated);
    }

    // A word is a maximal run of Unicode letters/digits with internal
    // apostrophes kept (don't stays one word); casing is first-seen.
    private static List<string> Tokenize(string text)
    {
        List<string> words = [];
        int i = 0;
        while (i < text.Length)
        {
            while (i < text.Length && !IsWordChar(text[i]))
            {
                i++;
            }

            int start = i;
            while (i < text.Length && IsWordChar(text[i]))
            {
                i++;
            }

            if (i > start)
            {
                string word = text.Substring(start, i - start).Trim('\'');
                if (word.Length > 0 && HasLetterOrDigit(word))
                {
                    words.Add(word);
                }
            }
        }

        return words;
    }

    private static bool IsWordChar(char c) => char.IsLetterOrDigit(c) || c == '\'';

    private static bool HasLetterOrDigit(string word)
    {
        foreach (char c in word)
        {
            if (char.IsLetterOrDigit(c))
            {
                return true;
            }
        }

        return false;
    }

    // Naive split on . / ! / ? runs; abbreviations over-split (recorded
    // limitation). A trailing fragment without a terminator still counts.
    private static List<string> SplitSentences(string text)
    {
        List<string> sentences = [];
        int start = 0;
        int i = 0;
        while (i < text.Length)
        {
            if (IsTerminator(text[i]))
            {
                string sentence = text.Substring(start, i - start);
                while (i < text.Length && IsTerminator(text[i]))
                {
                    i++;
                }

                if (Tokenize(sentence).Count > 0)
                {
                    sentences.Add(sentence);
                }

                start = i;
            }
            else
            {
                i++;
            }
        }

        string tail = text.Substring(start);
        if (Tokenize(tail).Count > 0)
        {
            sentences.Add(tail);
        }

        return sentences;
    }

    private static bool IsTerminator(char c) => c == '.' || c == '!' || c == '?';
}

// The refresh-on-demand rule as a testable seam: the panel reads Current,
// which moves only on Refresh, so typing never pays for a recompute.
public sealed class StatsController
{
    private readonly ITextProvider provider;

    public StatsController(ITextProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        this.provider = provider;
        Current = TextStats.Compute(provider.GetText() ?? string.Empty);
    }

    public DocumentStats Current { get; private set; }

    public void Refresh()
    {
        Current = TextStats.Compute(provider.GetText() ?? string.Empty);
    }
}
