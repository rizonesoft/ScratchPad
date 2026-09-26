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
        HeldChord.NotePress(true, _ => { });
        Assert.True(HeldChord.Suppress("MenuFileNewTab"));
        HeldChord.NoteRelease();
        Assert.False(HeldChord.Suppress("MenuFileNewTab"));
        // R1-F1: the repeat flag lives for one input message; its deferred
        // reset runs before any later mouse click or focus change.
        Action? reset = null;
        HeldChord.NotePress(true, a => reset = a);
        Assert.True(HeldChord.Suppress("MenuFileSave"));
        Assert.NotNull(reset);
        reset();
        Assert.False(HeldChord.Suppress("MenuFileSave"));
        Assert.Equal("vk:9:1", TestMutation.Key(0x09, 1));
    }

    // D00 T02 §51 item 6: a release and re-press is a second deliberate
    // press (Ctrl+T held, released, pressed again opens a second tab), and
    // focus loss mid-hold ends the hold, so nothing stays suppressed.
    [Fact]
    public void ReleaseAndRepressAndInterruptedHoldsReset()
    {
        string newTab = TestMutation.Key(0x54, 1);
        Assert.Equal(1, HeldChord.Count(newTab, "dddu"));
        Assert.Equal(2, HeldChord.Count(newTab, "dddudd"));
        Assert.Equal(2, HeldChord.Count(newTab, "ddfd"));
        Assert.Equal(4, HeldChord.Count("MenuViewZoomIn", "ddfddu"));
    }

    // §51 item 8: one counting definition. A chord registered twice (two
    // bound handlers reached by one key event) dispatches once per event:
    // once per hold for one-shot, once per accepted repeat for repeatable.
    [Fact]
    public void ChordRegisteredTwiceDispatchesOncePerEvent()
    {
        Assert.Equal(1, HeldChord.Count("MenuFileNewTab", "ddddu", registrations: 2));
        Assert.Equal(4, HeldChord.Count("MenuViewZoomIn", "ddddu", registrations: 2));
        Assert.Equal(HeldChord.Dispatches("MenuViewZoomIn", 4), HeldChord.Count("MenuViewZoomIn", "ddddu", registrations: 3));
        // Mouse invocation opens no key event and always dispatches.
        HeldChord.Reset();
        Assert.False(HeldChord.ShouldSkip("MenuFileNewTab"));
        Assert.False(HeldChord.ShouldSkip("MenuFileNewTab"));
    }

}
