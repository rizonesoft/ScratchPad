using Notepad.Core;
using Xunit;

namespace Unit;

public sealed class WindowTitleTests
{
    [Theory]
    [InlineData("Untitled", false, "Untitled - Intelligent Notepad")]
    [InlineData("Untitled", true, "*Untitled - Intelligent Notepad")]
    [InlineData("Implementation.txt", false, "Implementation.txt - Intelligent Notepad")]
    [InlineData("Implementation.txt", true, "*Implementation.txt - Intelligent Notepad")]
    [InlineData("hello", true, "*hello - Intelligent Notepad")]
    public void TitleConventionMatchesNotepad(string displayName, bool dirty, string expected)
    {
        Assert.Equal(expected, WindowTitle.Format(displayName, dirty, "Intelligent Notepad"));
    }
}
