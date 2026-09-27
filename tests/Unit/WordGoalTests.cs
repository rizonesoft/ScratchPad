using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §11: goal input parsing and the progress line's percent.
public sealed class WordGoalTests
{
    [Theory]
    [InlineData("500", 500)]
    [InlineData(" 1 ", 1)]
    [InlineData("1,000", 1000)]
    [InlineData("1000000", 1000000)]
    public void ValidGoalsParse(string input, int expected)
    {
        (int? goal, string? error) = WordGoal.Parse(input);
        Assert.Equal(expected, goal);
        Assert.Null(error);
    }

    [Theory]
    [InlineData(null, "Enter a whole number of words.")]
    [InlineData("", "Enter a whole number of words.")]
    [InlineData("abc", "Enter a whole number of words.")]
    [InlineData("12.5", "Enter a whole number of words.")]
    [InlineData("-5", "Enter a whole number of words.")]
    [InlineData("0", "Enter a goal of at least 1 word.")]
    [InlineData("1000001", "Enter a goal of at most 1,000,000 words.")]
    [InlineData("99999999999", "Enter a whole number of words.")]
    public void InvalidGoalsAreRefusedWithAMessage(string? input, string message)
    {
        (int? goal, string? error) = WordGoal.Parse(input);
        Assert.Null(goal);
        Assert.Equal(message, error);
    }

    [Theory]
    [InlineData(0, 100, 0.0)]
    [InlineData(25, 100, 25.0)]
    [InlineData(100, 100, 100.0)]
    [InlineData(250, 100, 100.0)]
    [InlineData(5, 0, 0.0)]
    public void PercentClampsToAFullLine(int words, int goal, double expected)
    {
        Assert.Equal(expected, WordGoal.Percent(words, goal));
    }

    [Fact]
    public void LabelNamesTheGoal()
    {
        Assert.Equal("Set word goal", WordGoal.Label(null));
        Assert.Equal("Word goal 1,500", WordGoal.Label(1500));
    }
}
