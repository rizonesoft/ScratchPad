using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §34: the background-birth sweep decides from a snapshot, so
// interleaving, ownership, and snapshot lifetime are provable without a
// window.
public sealed class SiblingSelectionTests
{
    const uint UiThread = 10;
    const uint PrintThread = 20;
    const nint Main = 0x100;
    const nint OtherMain = 0x200;

    [Fact]
    public void ConstructorBornHelpersPinAndEverythingElseIsSkippedWithItsReason()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([0x300, OtherMain], UiThread);
        SiblingTopLevel[] now =
        [
            new(Main, Main, UiThread, IsMain: true),
            new(OtherMain, OtherMain, UiThread, IsMain: true),
            new(0x300, 0x300, UiThread, IsMain: false),
            new(0x400, OtherMain, UiThread, IsMain: false),
            new(0x500, 0x500, UiThread, IsMain: false),
            new(0x600, Main, UiThread, IsMain: false),
        ];
        var d = SiblingSelection.Decide(now, snap, Main).ToDictionary(x => x.Handle, x => x.Reason);
        Assert.Equal("main", d[Main]);
        Assert.Equal("main", d[OtherMain]);
        Assert.Equal("preexisting", d[0x300]);
        Assert.Equal("other-owner", d[0x400]);
        Assert.Equal(SiblingSelection.Pin, d[0x500]);
        Assert.Equal(SiblingSelection.Pin, d[0x600]);
    }

    // §34 item 1: an unowned window an app worker thread (the print
    // thread) creates while this construction is in flight is not this
    // window's; a framework thread's constructor-born helper still pins.
    [Fact]
    public void InterleavedWorkerWindowIsNeverSweptButFrameworkHelpersPin()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([OtherMain], UiThread);
        using (SiblingSelection.RegisterWorkerThread(PrintThread))
        {
            var d = SiblingSelection.Decide([new(0x700, 0x700, PrintThread, IsMain: false), new(0x701, 0x701, 30, IsMain: false)], snap, Main);
            Assert.Equal("worker-thread", d.Single(x => x.Handle == 0x700).Reason);
            Assert.Equal(SiblingSelection.Pin, d.Single(x => x.Handle == 0x701).Reason);
        }

        var after = SiblingSelection.Decide([new(0x702, 0x702, PrintThread, IsMain: false)], SiblingSelection.Begin([], UiThread), Main);
        Assert.Equal(SiblingSelection.Pin, after.Single().Reason);
    }

    // §34 item 4: a failed construction's snapshot is never reused, and a
    // sweep with no fresh snapshot pins nothing.
    [Fact]
    public void FailedConstructionLeavesNoSnapshotForTheNextBirth()
    {
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot failed = slot.Begin(SiblingSelection.Begin([], UiThread));
        SiblingSnapshot next = slot.Begin(SiblingSelection.Begin([0x300], UiThread));
        Assert.Null(slot.Take(failed));
        Assert.Same(next, slot.Take(next));
        Assert.Null(slot.Take(next));
        var d = SiblingSelection.Decide([new(0x500, 0x500, UiThread, IsMain: false)], slot.Take(next), Main);
        Assert.Equal("no-snapshot", d.Single().Reason);
    }

    // §34 R1-F1: overlapping constructions never trade snapshots: A's sweep
    // after B began gets nothing, and B's sweep still gets B's.
    [Fact]
    public void OverlappingConstructionsNeverTradeSnapshots()
    {
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot a = slot.Begin(SiblingSelection.Begin([0x1], UiThread));
        SiblingSnapshot b = slot.Begin(SiblingSelection.Begin([0x2], UiThread));
        Assert.Null(slot.Take(a));
        Assert.Same(b, slot.Take(b));
    }

    // §34 item 5: the decision renders deterministically for the log.
    [Fact]
    public void DescribeListsPinnedAndSkippedInHandleOrder()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([0x300], UiThread);
        var d = SiblingSelection.Decide([new(0x500, 0x500, UiThread, false), new(0x300, 0x300, UiThread, false)], snap, Main);
        Assert.Equal("sweep main=0x100 target=-32000,-32000 pinned=0x500 skipped=0x300(preexisting)", SiblingSelection.Describe(Main, -32000, -32000, d));
    }
}
