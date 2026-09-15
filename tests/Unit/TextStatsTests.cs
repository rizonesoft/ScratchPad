using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §14 (neutral half): stats engine over the tests/Fixtures/stats
// fixture plus the refresh-on-demand rule. The panel is app UI (bedtime).
public sealed class TextStatsTests
{
    private static string Fixture(params string[] parts) =>
        Path.Combine([AppContext.BaseDirectory, "Fixtures", ..parts]);

    [Fact]
    public void SampleFixtureTopWordsMatchExactly()
    {
        DocumentStats stats = TextStats.Compute(File.ReadAllText(Fixture("stats", "sample.txt")));
        Assert.Equal(9, stats.TotalWords);
        Assert.Equal(3, stats.TotalSentences);
        WordCount[] expected =
        [
            new("The", 3),
            new("cat", 3),
            new("ate", 1),
            new("sat", 1),
            new("slept", 1),
        ];
        Assert.Equal(expected, stats.TopWords);
    }

    [Fact]
    public void SampleFixtureSentenceStatsMatchExactly()
    {
        DocumentStats stats = TextStats.Compute(File.ReadAllText(Fixture("stats", "sample.txt")));
        Assert.Equal(3.0, stats.MeanSentenceLength);
        Assert.Equal(3, stats.ShortestSentence);
        Assert.Equal(3, stats.LongestSentence);
        Assert.Equal(new SentenceBuckets(3, 0, 0), stats.Buckets);
    }

    [Fact]
    public void SampleFixtureFlagsRepeatedNonStopwordOnly()
    {
        DocumentStats stats = TextStats.Compute(File.ReadAllText(Fixture("stats", "sample.txt")));
        Assert.Single(stats.RepeatedWords);
        Assert.Equal("cat", stats.RepeatedWords[0], StringComparer.Ordinal);
    }

    [Fact]
    public void SentenceBucketsClassifyShortMediumLong()
    {
        const string Medium = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen";
        const string Long = "w01 w02 w03 w04 w05 w06 w07 w08 w09 w10 w11 w12 w13 w14 w15 w16 w17 w18 w19 w20 w21 w22 w23 w24 w25 w26 w27 w28 w29 w30";
        DocumentStats stats = TextStats.Compute($"The cat sat. {Medium}. {Long}.");
        Assert.Equal(3, stats.TotalSentences);
        Assert.Equal(new SentenceBuckets(1, 1, 1), stats.Buckets);
        Assert.Equal(16.0, stats.MeanSentenceLength);
        Assert.Equal(3, stats.ShortestSentence);
        Assert.Equal(30, stats.LongestSentence);
    }

    [Fact]
    public void CountingIsCaseInsensitiveAndKeepsApostrophes()
    {
        DocumentStats stats = TextStats.Compute("Cat CAT cat don't stop");
        Assert.Equal(5, stats.TotalWords);
        Assert.Equal(new WordCount("Cat", 3), stats.TopWords[0]);
        Assert.Contains(new WordCount("don't", 1), stats.TopWords);
    }

    [Fact]
    public void UnicodeLettersCountAsWords()
    {
        DocumentStats stats = TextStats.Compute("café naïve café");
        Assert.Equal(3, stats.TotalWords);
        Assert.Equal(new WordCount("café", 2), stats.TopWords[0]);
    }

    [Fact]
    public void EmptyAndWhitespaceYieldZeros()
    {
        foreach (string text in new[] { "", "  \n\t " })
        {
            DocumentStats stats = TextStats.Compute(text);
            Assert.Equal(0, stats.TotalWords);
            Assert.Equal(0, stats.TotalSentences);
            Assert.Equal(0.0, stats.MeanSentenceLength);
            Assert.Equal(new SentenceBuckets(0, 0, 0), stats.Buckets);
            Assert.Empty(stats.TopWords);
            Assert.Empty(stats.RepeatedWords);
        }
    }

    [Fact]
    public void ControllerComputesOnOpenAndOnlyOnRefresh()
    {
        MutableProvider provider = new() { Text = "one two" };
        StatsController controller = new(provider);
        Assert.Equal(2, controller.Current.TotalWords);
        provider.Text = "one two three four";
        Assert.Equal(2, controller.Current.TotalWords);
        controller.Refresh();
        Assert.Equal(4, controller.Current.TotalWords);
    }

    [Fact]
    public void NullInputsThrow()
    {
        Assert.Throws<ArgumentNullException>(() => TextStats.Compute(null!));
        Assert.Throws<ArgumentNullException>(() => new StatsController(null!));
    }

    private sealed class MutableProvider : ITextProvider
    {
        public string Text { get; set; } = string.Empty;

        public string GetText() => Text;
    }
}
