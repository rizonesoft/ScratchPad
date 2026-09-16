using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace Unit;

// D01 T02 §4: status-bar math fixtures. Every value below is probed
// against stock 11.2607.14.0 (see the §4 review) unless marked default.
public sealed class StatusSegmentsTests(ITestOutputHelper output)
{
    [Theory]
    [InlineData("", 0, 1, 1)]
    [InlineData("a", 0, 1, 1)]
    [InlineData("a", 1, 1, 2)]
    [InlineData("a\tb\r\ncde\r\n", 0, 1, 1)]
    [InlineData("a\tb\r\ncde\r\n", 1, 1, 2)]
    [InlineData("a\tb\r\ncde\r\n", 2, 1, 3)]
    [InlineData("a\tb\r\ncde\r\n", 3, 1, 4)]
    [InlineData("a\tb\r\ncde\r\n", 5, 2, 1)]
    [InlineData("a\tb\r\ncde\r\n", 8, 2, 4)]
    [InlineData("a\tb\r\ncde\r\n", 10, 3, 1)]
    [InlineData("aa\rbb\r", 3, 2, 1)]
    [InlineData("aa\nbb\n", 3, 2, 1)]
    [InlineData("a", 99, 1, 2)]
    [InlineData("a", -4, 1, 1)]
    public void LineColumnFollowsCaret(string text, int caret, int line, int column)
    {
        Assert.Equal((line, column), StatusSegments.LineColumn(text, caret));
    }

    [Theory]
    [InlineData("", 0)]
    [InlineData("a", 1)]
    [InlineData("a\r\n", 2)]
    [InlineData("a\tb\r\ncde\r\n", 8)]
    [InlineData("aa\rbb\r", 6)]
    [InlineData("aa\nbb\n", 6)]
    [InlineData("# T\r\n\r\nbody\r\n", 10)]
    public void CountCharactersCountsBreaksOnce(string text, int expected)
    {
        Assert.Equal(expected, StatusSegments.CountCharacters(text));
    }

    [Theory]
    [InlineData(0, "0 characters")]
    [InlineData(1, "1 character")]
    [InlineData(2, "2 characters")]
    [InlineData(297, "297 characters")]
    public void TotalTextUsesSingularOnlyAtOne(int total, string expected)
    {
        Assert.Equal(expected, StatusSegments.TotalText(total));
    }

    [Theory]
    [InlineData("a\tb\r\ncde\r\n", "a\tb\r\ncde\r\n", "8 of 8 characters")]
    [InlineData("a", "a\r\nb\r\n", "1 of 4 characters")]
    [InlineData("", "abc", "0 of 3 characters")]
    public void SelectionTextCountsSelectionOverTotal(string selected, string full, string expected)
    {
        Assert.Equal(expected, StatusSegments.SelectionText(selected, StatusSegments.CountCharacters(full)));
    }

    [Theory]
    [InlineData("CRLF", "Windows (CRLF)", " Windows (CRLF)")]
    [InlineData("LF", "Unix (LF)", " Unix (LF)")]
    [InlineData("CR", "Macintosh (CR)", " Macintosh (CR)")]
    public void EolDisplayMapsDominantConvention(string ending, string visual, string uia)
    {
        Assert.Equal(visual, StatusSegments.EolDisplay(ending));
        Assert.Equal(uia, StatusSegments.UiaEolName(ending));
    }

    [Fact]
    public void EolDisplayRejectsUnknownConvention()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => StatusSegments.EolDisplay("mixed"));
    }

    [Theory]
    [InlineData("ANSI")]
    [InlineData("UTF-16 LE")]
    [InlineData("UTF-16 BE")]
    [InlineData("UTF-8")]
    [InlineData("UTF-8 with BOM")]
    public void EncodingDisplayEchoesDetectionName(string name)
    {
        Assert.Equal(name, StatusSegments.EncodingDisplay(name));
        Assert.Equal(" " + name, StatusSegments.UiaEncodingName(name));
    }

    [Fact]
    public void EncodingDisplayRejectsUnknownName()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => StatusSegments.EncodingDisplay("Auto-Detect"));
    }

    [Theory]
    [InlineData("notes.txt", false, "Plain text")]
    [InlineData("notes.md", true, "Formatted")]
    [InlineData("NOTES.MD", true, "Formatted")]
    [InlineData(null, false, "Plain text")]
    public void ModeTextFollowsMarkdownSuffix(string? path, bool markdown, string expected)
    {
        Assert.Equal(markdown, StatusSegments.IsMarkdownFile(path));
        Assert.Equal(expected, StatusSegments.ModeText(markdown));
    }

    [Fact]
    public void ComputeBindsFullFrame()
    {
        StatusView view = StatusView.Compute("a\tb\r\ncde\r\n", 10, 0, 0, "UTF-8", "CRLF", 100, false);
        Assert.Equal("Ln 3, Col 1", view.LineColumn);
        Assert.Equal("Line 3,\nColumn 1", view.LineColumnName);
        Assert.Equal("8 characters", view.Count);
        Assert.Equal("Plain text", view.Mode);
        Assert.False(view.ModeIsButton);
        Assert.Equal("100%", view.Zoom);
        Assert.Equal("Zoom", view.ZoomName);
        Assert.Equal("Windows (CRLF)", view.Eol);
        Assert.Equal(" Windows (CRLF)", view.EolName);
        Assert.Equal("UTF-8", view.Encoding);
        Assert.Equal(" UTF-8", view.EncodingName);
    }

    [Fact]
    public void ComputeClampsWildSelection()
    {
        StatusView view = StatusView.Compute("abc", 99, 2, 99, "UTF-8", "CRLF", 100, false);
        Assert.Equal("Ln 1, Col 4", view.LineColumn);
        Assert.Equal("1 of 3 characters", view.Count);
    }

    [Fact]
    public void EmptyShowsZeroTabDefaults()
    {
        StatusView view = StatusView.Empty(100);
        Assert.Equal("Ln 1, Col 1", view.LineColumn);
        Assert.Equal("0 characters", view.Count);
        Assert.Equal("Plain text", view.Mode);
    }

    // §4 latency bar (§9 item 4 measures against it): a full recompute
    // over 1 MiB of mixed-break text must clear 500 ms (measured 9 ms on
    // the Linux dev run; the bound is the contract).
    [Fact]
    public void FullRecomputeOverOneMegabyteStaysFast()
    {
        string chunk = new string('a', 1000) + "\r\n";
        var builder = new System.Text.StringBuilder(1024 * 1024 + 1024);
        while (builder.Length < 1024 * 1024)
        {
            builder.Append(chunk);
        }

        string text = builder.ToString();
        var watch = System.Diagnostics.Stopwatch.StartNew();
        StatusView view = StatusView.Compute(text, text.Length, 0, 0, "UTF-8", "CRLF", 100, false);
        watch.Stop();
        Assert.StartsWith("Ln ", view.LineColumn, StringComparison.Ordinal);
        output.WriteLine($"STATUS-RECOMPUTE-MS={watch.ElapsedMilliseconds}");
        Assert.True(watch.ElapsedMilliseconds < 500, $"recompute took {watch.ElapsedMilliseconds} ms");
    }
}
