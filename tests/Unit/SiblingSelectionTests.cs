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
        Assert.Equal("sweep main=0x100 target=-32000,-32000 gen=0 pinned=0x500 skipped=0x300(preexisting)", SiblingSelection.Describe(Main, -32000, -32000, d));
        Assert.Equal("sweep-late main=0x100 target=1,2 gen=7 pinned=0x500 skipped=0x300(preexisting)", SiblingSelection.Describe(Main, 1, 2, d, null, "sweep-late", 7));
    }

    // §41 item 1: a planted same-thread interleaving. A begins, B begins and
    // its sweep claims its helper; the helper then reads as B's to any other
    // construction, whatever order the sweeps run in, and even when this
    // construction has no snapshot at all.
    [Fact]
    public void InterleavedConstructionsWindowReadsAsTheOtherConstructions()
    {
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot a = slot.Begin(SiblingSelection.Begin([0x1], UiThread));
        SiblingSnapshot b = slot.Begin(SiblingSelection.Begin([0x1], UiThread));
        const nint bHelper = 0x900;
        SiblingTopLevel helper = new(bHelper, bHelper, UiThread, IsMain: false);
        var bSweep = SiblingSelection.Decide([helper], slot.Take(b), OtherMain, slot.Claims);
        Assert.Equal(SiblingSelection.Pin, bSweep.Single().Reason);
        slot.Claim(b.Generation, [bHelper, OtherMain]);
        SiblingTopLevel claimed = helper with { ClaimMark = b.Generation };
        var aLate = SiblingSelection.Decide([claimed], a, Main, slot.Claims);
        Assert.Equal("other-construction", aLate.Single().Reason);
        var aNoSnapshot = SiblingSelection.Decide([claimed], slot.Take(a), Main, slot.Claims);
        Assert.Equal("other-construction", aNoSnapshot.Single().Reason);

        // R1-F2: a claimed handle reused by a new window (the claim mark is
        // gone) is no longer the other construction's.
        SiblingSnapshot c = SiblingSelection.Begin([], UiThread);
        Assert.Equal(SiblingSelection.Pin, SiblingSelection.Decide([helper], c, Main, slot.Claims).Single().Reason);
        Assert.True(b.Generation > a.Generation);
    }

    // §41 item 2: lifecycle edges. A reused handle value (the snapshot saw
    // and marked the handle, the new window carries no mark) is new, never
    // preexisting; a still-marked window stays preexisting; a destroyed
    // window's claim is released so its reused value starts clean; a
    // cancelled construction leaves no claims.
    [Fact]
    public void ReusedHandleNeverReadsPreexistingAndClaimsReleaseWithTheWindow()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([0x300, 0x301], UiThread, gen => [0x300, 0x301]);
        var d = SiblingSelection.Decide(
            [new(0x300, 0x300, UiThread, IsMain: false, Mark: snap.Generation), new(0x301, 0x301, UiThread, IsMain: false, Mark: 0)],
            snap,
            Main).ToDictionary(x => x.Handle, x => x.Reason);
        Assert.Equal("preexisting", d[0x300]);
        Assert.Equal(SiblingSelection.Pin, d[0x301]);

        var slot = new SiblingSnapshotSlot();
        slot.Claim(5, [0x301, 0x302]);
        slot.Release((h, gen) => h != 0x301 && gen == 5);
        Assert.False(slot.Claims.ContainsKey(0x301));
        Assert.True(slot.Claims.ContainsKey(0x302));

        SiblingSnapshot cancelled = slot.Begin(SiblingSelection.Begin([], UiThread));
        SiblingSnapshot next = slot.Begin(SiblingSelection.Begin([], UiThread));
        Assert.Null(slot.Take(cancelled));
        Assert.Equal([(nint)0x302], slot.Claims.Keys);
        Assert.Same(next, slot.Take(next));
    }

    // §41 item 3: a window the snapshot could not mark, or whose provenance
    // cannot be read, is skipped as ambiguous and reported.
    [Fact]
    public void AmbiguousProvenanceIsSkippedAndReported()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([0x300, 0x301], UiThread, gen => [0x301]);
        var d = SiblingSelection.Decide(
            [new(0x300, 0x300, UiThread, IsMain: false), new(0x302, 0x302, UiThread, IsMain: false, Readable: false)],
            snap,
            Main);
        Assert.All(d, x => Assert.Equal("ambiguous", x.Reason));
        Assert.Contains("0x300(ambiguous)", SiblingSelection.Describe(Main, 0, 0, d), StringComparison.Ordinal);
    }

    // §41 item 4: the delayed pass decides only windows born after the
    // sweep, and does nothing when another construction began since.
    [Fact]
    public void DelayedPassPinsLateHelpersOnlyWithoutAnOverlap()
    {
        SiblingSnapshot snap = SiblingSelection.Begin([0x300], UiThread);
        SiblingTopLevel[] now = [new(0x300, 0x300, UiThread, false), new(0x500, 0x500, UiThread, false), new(0x600, 0x600, UiThread, false)];
        var decided = new Dictionary<nint, SiblingTopLevel> { [0x300] = now[0], [0x500] = now[1] };
        var late = SiblingSelection.DecideLate(now, snap, Main, decided, null, anotherConstructionBegan: false);
        Assert.Equal(SiblingSelection.Pin, late.Single().Reason);
        Assert.Equal((nint)0x600, late.Single().Handle);
        var overlap = SiblingSelection.DecideLate(now, snap, Main, decided, null, anotherConstructionBegan: true);
        Assert.Equal("late-skipped-overlap", overlap.Single().Reason);

        // R3-F1: a decided handle reused by a new window (another thread) is
        // decided again, never silently skipped.
        SiblingTopLevel[] reused = [new(0x300, 0x300, UiThread, false), new(0x500, 0x500, PrintThread + 1, false)];
        var again = SiblingSelection.DecideLate(reused, snap, Main, decided, null, anotherConstructionBegan: false);
        Assert.Equal(SiblingSelection.Pin, again.Single(d => d.Handle == 0x500).Reason);
        Assert.DoesNotContain(again, d => d.Handle == 0x300);

        // R2-F1: A sweeps, then B begins and completes its sweep before A's
        // delayed pass; the pass still sees that B began.
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot a = slot.Begin(SiblingSelection.Begin([], UiThread));
        Assert.Same(a, slot.Take(a));
        Assert.False(slot.BegunSince(a));
        SiblingSnapshot b = slot.Begin(SiblingSelection.Begin([], UiThread));
        Assert.Same(b, slot.Take(b));
        Assert.True(slot.BegunSince(a));
        Assert.False(slot.BegunSince(b));
    }

    // §41 item 5: a handle re-owned, reused, or destroyed between the
    // selection and its move is skipped.
    [Fact]
    public void RevalidationSkipsReownedReusedAndGoneHandles()
    {
        SiblingTopLevel selected = new(0x500, 0x500, UiThread, IsMain: false);
        Assert.Equal(SiblingSelection.Pin, SiblingSelection.Revalidate(selected, selected, Main));
        Assert.Equal("reowned-before-move", SiblingSelection.Revalidate(selected, selected with { RootOwner = OtherMain }, Main));
        Assert.Equal(SiblingSelection.Pin, SiblingSelection.Revalidate(selected, selected with { RootOwner = Main }, Main));
        Assert.Equal("reused-before-move", SiblingSelection.Revalidate(selected, selected with { ThreadId = PrintThread }, Main));
        // R1-F1: a same-thread reuse with another class or another mark.
        Assert.Equal("reused-before-move", SiblingSelection.Revalidate(selected with { ClassName = "A" }, selected with { ClassName = "B" }, Main));
        Assert.Equal("reused-before-move", SiblingSelection.Revalidate(selected with { Mark = 3 }, selected with { Mark = 0 }, Main));
        Assert.Equal("gone-before-move", SiblingSelection.Revalidate(selected, null, Main));
    }

    // §41 item 9: the hold seam arms only under the run marker.
    [Fact]
    public void TestHoldArmsOnlyUnderTheRunMarker()
    {
        Assert.Null(TestHold.Armed(k => k == TestHold.Variable ? "h" : null));
        Assert.Equal("h", TestHold.Armed(k => k == TestHold.Variable ? "h" : k == LaunchCapture.RunMarkerVariable ? "1" : null));
        Assert.False(TestHold.WaitIfArmed(k => null));
    }
}
