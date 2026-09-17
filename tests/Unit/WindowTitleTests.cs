using Notepad.Core;
using Xunit;

namespace Unit;

public sealed class WindowTitleTests
{
    [Theory]
    [InlineData("Untitled", false, "Untitled - ScratchPad")]
    [InlineData("Untitled", true, "*Untitled - ScratchPad")]
    [InlineData("Implementation.txt", false, "Implementation.txt - ScratchPad")]
    [InlineData("Implementation.txt", true, "*Implementation.txt - ScratchPad")]
    [InlineData("hello", true, "*hello - ScratchPad")]
    public void TitleConventionMatchesNotepad(string displayName, bool dirty, string expected)
    {
        Assert.Equal(expected, WindowTitle.Format(displayName, dirty, "ScratchPad"));
    }
}
