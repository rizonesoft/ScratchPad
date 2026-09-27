using System.IO;

using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §7: Flesch-Kincaid grade, 0.39 (words/sentences) + 11.8
// (syllables/words) - 15.59, rounded to one decimal and floored at 0.
// Reference values are hand-computed from dictionary syllable counts for
// words where the heuristic and the dictionary agree.
public sealed class ReadabilityTests
{
    [Theory]
    [InlineData("the", 1)]
    [InlineData("cat", 1)]
    [InlineData("quick", 1)]
    [InlineData("cake", 1)]
    [InlineData("over", 2)]
    [InlineData("lazy", 2)]
    [InlineData("candle", 2)]
    [InlineData("yellow", 2)]
    [InlineData("reading", 2)]
    [InlineData("matters", 2)]
    [InlineData("improves", 2)]
    [InlineData("education", 4)]
    [InlineData("opportunity", 5)]
    [InlineData("2026", 1)]
    [InlineData("Don't", 1)]
    public void SyllablesMatchTheDictionary(string word, int expected)
    {
        Assert.Equal(expected, Readability.Syllables(word));
    }

    [Fact]
    public void PolysyllabicTextScoresHigh()
    {
        // 5 words, 2 sentences, 4+2+5+2+2 = 15 syllables:
        // 0.39 * 2.5 + 11.8 * 3 - 15.59 = 20.785 -> 20.8.
        var level = Readability.Compute("Education improves opportunity. Reading matters.");
        Assert.NotNull(level);
        Assert.Equal(5, level.Words);
        Assert.Equal(2, level.Sentences);
        Assert.Equal(15, level.Syllables);
        Assert.Equal(20.8, level.Grade);
        Assert.Equal("Grade 20.8", Readability.Label(level));
    }

    [Fact]
    public void PangramScoresEarlyGrade()
    {
        // 9 words, 1 sentence, 11 syllables:
        // 0.39 * 9 + 11.8 * 11 / 9 - 15.59 = 2.342 -> 2.3.
        var level = Readability.Compute("The quick brown fox jumps over the lazy dog.");
        Assert.NotNull(level);
        Assert.Equal((9, 1, 11), (level.Words, level.Sentences, level.Syllables));
        Assert.Equal(2.3, level.Grade);
    }

    [Fact]
    public void PlainTextFloorsAtZero()
    {
        // 6 one-syllable words, 1 sentence: 2.34 + 11.8 - 15.59 = -1.45.
        var level = Readability.Compute("The cat sat on the mat.");
        Assert.NotNull(level);
        Assert.Equal(0.0, level.Grade);
        Assert.Equal("Grade 0.0", Readability.Label(level));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   \r\n\t ")]
    [InlineData("... !!! ???")]
    public void EmptyOrWordlessBufferHasNoScore(string text)
    {
        Assert.Null(Readability.Compute(text));
        Assert.Equal("No text to score", Readability.Label(null));
    }

    [Fact]
    public void UnterminatedTextCountsAsOneSentence()
    {
        // TextStats counts a trailing fragment as a sentence, so a buffer
        // with words but no terminator still scores.
        var level = Readability.Compute("Reading matters");
        Assert.NotNull(level);
        Assert.Equal(1, level.Sentences);
    }

    [Fact]
    public void WordsAndSentencesComeFromTextStats()
    {
        const string text = "One two three. Four five! Six?";
        var stats = TextStats.Compute(text);
        var level = Readability.Compute(text);
        Assert.NotNull(level);
        Assert.Equal(stats.TotalWords, level.Words);
        Assert.Equal(stats.TotalSentences, level.Sentences);
        Assert.Equal(stats.TotalWords, TextStats.Words(text).Count);
    }

    [Fact]
    public void ScoringSourceTouchesNoNetwork()
    {
        // The on-demand rule's negative: the scorer's source names no
        // network API, so nothing it runs can phone home.
        string dir = System.AppContext.BaseDirectory;
        while (dir is not null && !Directory.Exists(Path.Combine(dir, "src", "Notepad.Core")))
        {
            dir = Path.GetDirectoryName(dir)!;
        }

        Assert.NotNull(dir);
        string source = File.ReadAllText(Path.Combine(dir, "src", "Notepad.Core", "Readability.cs"));
        string[] banned = ["System.Net", "HttpClient", "WebRequest", "Socket", "Uri("];
        foreach (string api in banned)
        {
            Assert.DoesNotContain(api, source, System.StringComparison.Ordinal);
        }
    }
}
