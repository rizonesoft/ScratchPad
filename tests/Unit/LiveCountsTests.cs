using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §9: words from TextStats, reading time at 200 words per minute
// rounded up.
public sealed class LiveCountsTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 1)]
    [InlineData(200, 1)]
    [InlineData(201, 2)]
    [InlineData(1000, 5)]
    public void ReadingMinutesRoundUp(int words, int minutes)
    {
        Assert.Equal(minutes, LiveCounts.ReadingMinutes(words));
    }

    [Theory]
    [InlineData(0, "0 words")]
    [InlineData(1, "1 word, 1 min read")]
    [InlineData(9, "9 words, 1 min read")]
    [InlineData(1234, "1,234 words, 7 min read")]
    public void LabelReadsCountAndTime(int words, string expected)
    {
        Assert.Equal(expected, LiveCounts.Label(words));
    }

    [Theory]
    [InlineData("")]
    [InlineData("The quick brown fox jumps over the lazy dog.")]
    [InlineData("Don't split contractions. 3.5 counts twice! Tail fragment")]
    public void WordsMatchTheStatisticsCounter(string text)
    {
        Assert.Equal(LiveCounts.Label(TextStats.Compute(text).TotalWords), LiveCounts.Compute(text));
    }

    [Fact]
    public void PangramReadsNineWords()
    {
        Assert.Equal("9 words, 1 min read", LiveCounts.Compute("The quick brown fox jumps over the lazy dog."));
    }
}
