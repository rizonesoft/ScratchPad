using System.Linq;
using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §10: the accent palette and its WinUI shade keys.
public sealed class AccentThemesTests
{
    [Theory]
    [InlineData(0, "ocean", "Ocean", "#0063B1")]
    [InlineData(1, "teal", "Teal", "#00827F")]
    [InlineData(2, "forest", "Forest", "#107C10")]
    [InlineData(3, "amber", "Amber", "#CA5010")]
    [InlineData(4, "rose", "Rose", "#C30052")]
    [InlineData(5, "plum", "Plum", "#881798")]
    [InlineData(6, "graphite", "Graphite", "#5D5A58")]
    public void PaletteIsPinned(int index, string id, string name, string hex)
    {
        AccentTheme theme = AccentThemes.BuiltIn[index];
        Assert.Equal((id, name, hex), (theme.Id, theme.Name, theme.Color.Hex));
        Assert.Same(theme, AccentThemes.Find(id));
    }

    [Fact]
    public void BuiltInsAreUniqueAndNeverSystem()
    {
        Assert.Equal(7, AccentThemes.BuiltIn.Count);
        Assert.Equal(AccentThemes.BuiltIn.Count, AccentThemes.BuiltIn.Select(t => t.Id).Distinct().Count());
        Assert.DoesNotContain(AccentThemes.BuiltIn, t => t.Id == AccentThemes.System);
        Assert.Equal(AccentThemes.BuiltIn.Count, AccentThemes.BuiltIn.Select(t => t.Color).Distinct().Count());
    }

    [Theory]
    [InlineData(null, "system")]
    [InlineData("", "system")]
    [InlineData("system", "system")]
    [InlineData("rose", "rose")]
    [InlineData("Rose", "system")]
    [InlineData("neon", "system")]
    public void NormalizeFallsBackToSystem(string? id, string expected)
    {
        Assert.Equal(expected, AccentThemes.Normalize(id));
    }

    [Fact]
    public void ShadesStepTowardWhiteAndBlack()
    {
        var shades = AccentThemes.Shades(new AccentColor(100, 50, 0));
        Assert.Equal(7, shades.Count);
        Assert.Equal(new AccentColor(100, 50, 0), shades["SystemAccentColor"]);
        Assert.Equal(new AccentColor(131, 91, 51), shades["SystemAccentColorLight1"]);
        Assert.Equal(new AccentColor(162, 132, 102), shades["SystemAccentColorLight2"]);
        Assert.Equal(new AccentColor(193, 173, 153), shades["SystemAccentColorLight3"]);
        Assert.Equal(new AccentColor(80, 40, 0), shades["SystemAccentColorDark1"]);
        Assert.Equal(new AccentColor(60, 30, 0), shades["SystemAccentColorDark2"]);
        Assert.Equal(new AccentColor(40, 20, 0), shades["SystemAccentColorDark3"]);
    }

    [Fact]
    public void HexReadsTheColor()
    {
        Assert.Equal("#C30052", AccentThemes.Find("rose")!.Color.Hex);
    }
}
