using Notepad.Core;
using Xunit;

namespace Unit;

public sealed class PrintCodesTests
{
    static readonly PrintContext Ctx = new("9/17/2026", "1:23 PM", "notes.txt", 2);

    [Fact]
    public void EveryCodeExpands()
    {
        var (left, center, right) = PrintCodes.ExpandParts("&l&f&c&d &t&r&p", Ctx);
        Assert.Equal("notes.txt", left);
        Assert.Equal("9/17/2026 1:23 PM", center);
        Assert.Equal("2", right);
    }

    [Fact]
    public void DefaultsMatchStock()
    {
        Assert.Equal("&f", PrintCodes.DefaultHeader);
        Assert.Equal("Page &p", PrintCodes.DefaultFooter);
        var (left, _, _) = PrintCodes.ExpandParts(PrintCodes.DefaultHeader, Ctx);
        Assert.Equal("notes.txt", left);
        var (footer, _, _) = PrintCodes.ExpandParts(PrintCodes.DefaultFooter, Ctx);
        Assert.Equal("Page 2", footer);
    }

    [Fact]
    public void TextBeforeAnyCodeLandsLeft()
    {
        var (left, center, right) = PrintCodes.ExpandParts("draft &c mid", Ctx);
        Assert.Equal("draft ", left);
        Assert.Equal(" mid", center);
        Assert.Equal(string.Empty, right);
    }

    [Fact]
    public void LaterSwitchesWin()
    {
        var (left, center, right) = PrintCodes.ExpandParts("&lA&cB&lC&rD", Ctx);
        Assert.Equal("AC", left);
        Assert.Equal("B", center);
        Assert.Equal("D", right);
    }

    [Fact]
    public void AmpersandEscapesAndUnknownsStayLiteral()
    {
        var (left, _, _) = PrintCodes.ExpandParts("A&&B &q &", Ctx);
        Assert.Equal("A&B &q &", left);
    }

    [Fact]
    public void EmptiesStayEmpty()
    {
        var (left, center, right) = PrintCodes.ExpandParts(string.Empty, Ctx);
        Assert.Equal(string.Empty, left);
        Assert.Equal(string.Empty, center);
        Assert.Equal(string.Empty, right);
        var (l2, c2, r2) = PrintCodes.ExpandParts("&l&c&r", Ctx);
        Assert.Equal(string.Empty, l2);
        Assert.Equal(string.Empty, c2);
        Assert.Equal(string.Empty, r2);
    }
}
