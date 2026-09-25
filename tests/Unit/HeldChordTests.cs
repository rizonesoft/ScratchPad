using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §43 item 4: a held chord (one key-down plus auto-repeats) reads
// its documented dispatch count per command class, through the same rule
// the app runs.
public sealed class HeldChordTests
{
    [Theory]
    [InlineData("MenuViewZoomIn", 5, 5)]
    [InlineData("MenuViewZoomOut", 3, 3)]
    [InlineData("vk:9:1", 4, 4)]
    [InlineData("vk:9:5", 4, 4)]
    [InlineData("MenuFileNewTab", 5, 1)]
    [InlineData("MenuFileSave", 3, 1)]
    [InlineData("vk:84:1", 6, 1)]
    public void HeldChordDispatchesByClass(string command, int keyDowns, int dispatches)
    {
        Assert.Equal(dispatches, HeldChord.Dispatches(command, keyDowns));
    }

    [Fact]
    public void ReleaseEndsTheHoldAndMouseInvocationAlwaysRuns()
    {
        HeldChord.NotePress(true);
        Assert.True(HeldChord.Suppress("MenuFileNewTab"));
        HeldChord.NoteRelease();
        Assert.False(HeldChord.Suppress("MenuFileNewTab"));
        Assert.Equal("vk:9:1", TestMutation.Key(0x09, 1));
    }
}
