using System.Collections.Generic;
using Notepad.Core;
using Xunit;

namespace Unit;

public sealed class PrintWrapTests
{
    [Fact]
    public void GreedyBreakAtLastFittingWord()
    {
        var words = new[] { "aa", "bb", "cc" };
        var widths = new[] { 10f, 10f, 10f };
        var lines = PrintWrap.WrapWords(words, widths, 5f, 25f);
        Assert.Equal(new List<(int, int)> { (0, 2), (2, 1) }, lines);
    }

    [Fact]
    public void ExactFitStaysOnOneLine()
    {
        var words = new[] { "aa", "bb" };
        var widths = new[] { 10f, 10f };
        var lines = PrintWrap.WrapWords(words, widths, 5f, 25f);
        Assert.Single(lines);
    }

    [Fact]
    public void OverlongWordOverflowsAlone()
    {
        var words = new[] { "ok", "waytoolongword" };
        var widths = new[] { 10f, 100f };
        var lines = PrintWrap.WrapWords(words, widths, 5f, 25f);
        Assert.Equal(new List<(int, int)> { (0, 1), (1, 1) }, lines);
    }

    [Fact]
    public void EmptyParagraphYieldsOneBlankLine()
    {
        var lines = PrintWrap.WrapWords(
            System.Array.Empty<string>(), System.Array.Empty<float>(), 5f, 25f);
        Assert.Equal(new List<(int, int)> { (0, 0) }, lines);
    }
}
