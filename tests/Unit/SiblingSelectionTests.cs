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
        // §48 item 1: an overlapped birth reports the helper it could not
        // place instead of dropping it silently.
        Assert.Equal(SiblingSelection.OverlapUnplaced, overlap.Single().Reason);

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

    // §48 items 1 and 2: the placement verdict fails on a visible window
    // the birth could not place (overlap-unplaced or ambiguous), and passes
    // when such a window is hidden.
    [Fact]
    public void PlacementVerdictFailsOnlyOnVisibleUnplacedWindows()
    {
        SiblingDecision[] decisions = [new(0x300, SiblingSelection.OverlapUnplaced), new(0x400, "ambiguous"), new(0x500, SiblingSelection.Pin)];
        var visible = new Dictionary<nint, SiblingTopLevel> { [0x300] = new(0x300, 0x300, UiThread, false, Visible: true), [0x400] = new(0x400, 0x400, UiThread, false, Visible: true), [0x500] = new(0x500, 0x500, UiThread, false, Visible: true) };
        var hidden = new Dictionary<nint, SiblingTopLevel> { [0x300] = new(0x300, 0x300, UiThread, false), [0x400] = new(0x400, 0x400, UiThread, false), [0x500] = new(0x500, 0x500, UiThread, false, Visible: true) };
        Assert.Equal("fail(0x300:overlap-unplaced,0x400:ambiguous)", SiblingSelection.PlacementVerdict(decisions, visible));
        Assert.Equal("pass", SiblingSelection.PlacementVerdict(decisions, hidden));
        Assert.EndsWith(" verdict=pass", SiblingSelection.Describe(Main, 1, 2, decisions, verdict: "pass"), StringComparison.Ordinal);
    }

    // §48 item 3: two constructions whose helpers come from one shared
    // framework thread: each sweep pins its own helper and leaves the other
    // construction's claimed helper untouched, both ways.
    [Fact]
    public void SharedFrameworkThreadAttributionHoldsBothWays()
    {
        const uint Framework = 30;
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot a = slot.Begin(SiblingSelection.Begin([], UiThread));
        SiblingSnapshot aTaken = slot.Take(a)!;
        var aDecided = SiblingSelection.Decide([new(Main, Main, UiThread, true), new(0x700, 0x700, Framework, false)], aTaken, Main, slot.Claims).ToDictionary(d => d.Handle, d => d.Reason);
        Assert.Equal(SiblingSelection.Pin, aDecided[0x700]);
        slot.Claim(aTaken.Generation, [0x700, Main]);
        SiblingSnapshot b = slot.Begin(SiblingSelection.Begin([], UiThread));
        SiblingSnapshot bTaken = slot.Take(b)!;
        SiblingTopLevel[] seenByB = [new(Main, Main, UiThread, true), new(OtherMain, OtherMain, UiThread, true), new(0x700, 0x700, Framework, false, ClaimMark: aTaken.Generation), new(0x800, 0x800, Framework, false)];
        var bDecided = SiblingSelection.Decide(seenByB, bTaken, OtherMain, slot.Claims).ToDictionary(d => d.Handle, d => d.Reason);
        Assert.Equal("other-construction", bDecided[0x700]);
        Assert.Equal(SiblingSelection.Pin, bDecided[0x800]);
        slot.Claim(bTaken.Generation, [0x800, OtherMain]);
        SiblingTopLevel[] seenByALate = [new(0x700, 0x700, Framework, false, ClaimMark: aTaken.Generation), new(0x800, 0x800, Framework, false, ClaimMark: bTaken.Generation)];
        var aLate = SiblingSelection.Decide(seenByALate, aTaken, Main, slot.Claims).ToDictionary(d => d.Handle, d => d.Reason);
        Assert.Equal("other-construction", aLate[0x800]);
    }

    // §48 item 6: a construction that failed before its sweep leaves no
    // pending snapshot and no claim for the next birth.
    [Fact]
    public void FailedConstructionLeavesNothingForTheNextBirth()
    {
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot failed = slot.Begin(SiblingSelection.Begin([0x300], UiThread));
        Assert.True(slot.Abandon());
        Assert.False(slot.Abandon());
        Assert.Null(slot.Take(failed));
        Assert.Empty(slot.Claims);
        SiblingSnapshot next = slot.Begin(SiblingSelection.Begin([0x300], UiThread));
        SiblingSnapshot? taken = slot.Take(next);
        Assert.NotNull(taken);
        var d = SiblingSelection.Decide([new(0x300, 0x300, UiThread, false), new(0x900, 0x900, UiThread, false)], taken, Main, slot.Claims).ToDictionary(x => x.Handle, x => x.Reason);
        Assert.Equal("preexisting", d[0x300]);
        Assert.Equal(SiblingSelection.Pin, d[0x900]);
    }

    // §48 item 6 (R1-R1): the factory's failure path, driven through the
    // helper App.AddWindow constructs every window with. A construction
    // whose base constructor begins its snapshot and then throws, before
    // the derived constructor body runs, leaves no pending snapshot or
    // claim, so the next birth sweeps clean.
    [Fact]
    public void BaseConstructorFailureThroughTheFactoryLeavesTheNextBirthClean()
    {
        var slot = new SiblingSnapshotSlot();
        SiblingSnapshot? begun = null;
        var ex = Assert.Throws<InvalidOperationException>(() => SiblingSelection.ConstructOrAbandon(() => new FailingWindow(slot, s => begun = s), () => slot.Abandon()));
        Assert.Equal("base constructor failed", ex.Message);
        Assert.NotNull(begun);
        Assert.Null(slot.Take(begun));
        Assert.Empty(slot.Claims);
        SiblingSnapshot next = slot.Begin(SiblingSelection.Begin([0x300], UiThread));
        SiblingSnapshot? taken = slot.Take(next);
        Assert.NotNull(taken);
        var d = SiblingSelection.Decide([new(0x300, 0x300, UiThread, false), new(0x900, 0x900, UiThread, false)], taken, Main, slot.Claims).ToDictionary(x => x.Handle, x => x.Reason);
        Assert.Equal("preexisting", d[0x300]);
        Assert.Equal(SiblingSelection.Pin, d[0x900]);
    }

    // A window whose base constructor begins the birth's snapshot and then
    // fails, as a WinUI base constructor can.
    class FailingBase
    {
        protected FailingBase(SiblingSnapshotSlot slot, Action<SiblingSnapshot> begun)
        {
            begun(slot.Begin(SiblingSelection.Begin([0x300], UiThread)));
            throw new InvalidOperationException("base constructor failed");
        }
    }

    sealed class FailingWindow : FailingBase
    {
        internal FailingWindow(SiblingSnapshotSlot slot, Action<SiblingSnapshot> begun)
            : base(slot, begun)
        {
        }
    }

    // §48 item 8: a target a monitor attached since now shows is recomputed
    // before the delayed move; one still off-screen is kept.
    [Fact]
    public void DelayedTargetFollowsTheTopology()
    {
        var kept = SiblingSelection.Retarget(-40000, -40000, (x, y) => true, () => (1, 1));
        Assert.Equal((-40000, -40000, false), kept);
        var moved = SiblingSelection.Retarget(-1920, 1080, (x, y) => x < -3000, () => (-40000, -40000));
        Assert.Equal((-40000, -40000, true), moved);
    }

    // §48 item 9: twenty births and teardowns keep the claim table bounded
    // by the live windows and each decision within its latency budget. This
    // bounds the pure decision; the native enumeration, pins, and delayed
    // passes are measured in the app by the UI suite's
    // LaunchTests.TwentyBirthsAndTeardownsStayWithinBudget (R1-R2).
    [Fact]
    public void RepeatedBirthsKeepClaimsAndLatencyBounded()
    {
        var slot = new SiblingSnapshotSlot();
        var live = new Dictionary<nint, long>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        long worst = 0;
        for (int i = 0; i < 20; i++)
        {
            nint main = 0x10000 + (i * 0x100);
            SiblingSnapshot t = slot.Begin(SiblingSelection.Begin(live.Keys, UiThread));
            SiblingSnapshot taken = slot.Take(t)!;
            var windows = live.Keys.Select(h => new SiblingTopLevel(h, h, UiThread, false, ClaimMark: live[h])).Append(new SiblingTopLevel(main, main, UiThread, true)).Append(new SiblingTopLevel(main + 1, main + 1, UiThread, false)).ToList();
            long before = sw.ElapsedTicks;
            _ = SiblingSelection.Decide(windows, taken, main, slot.Claims);
            worst = Math.Max(worst, sw.ElapsedTicks - before);
            slot.Claim(taken.Generation, [main, main + 1]);
            live[main] = taken.Generation;
            live[main + 1] = taken.Generation;
            if (i % 2 == 1)
            {
                // Tear down the previous window and its helper.
                nint gone = 0x10000 + ((i - 1) * 0x100);
                _ = live.Remove(gone);
                _ = live.Remove(gone + 1);
            }

            slot.Release((h, gen) => live.TryGetValue(h, out long g) && g == gen);
            Assert.True(slot.Claims.Count <= live.Count, $"claims {slot.Claims.Count} exceed live windows {live.Count} after birth {i}");
        }

        double worstMs = worst * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
        Assert.True(worstMs < 50, $"a decision took {worstMs:F1} ms (budget 50 ms)");
    }
}
