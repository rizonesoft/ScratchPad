namespace Notepad.Core;

// Background-birth sibling sweep selection (D00 T02 §26, hardened by
// D00 T02 §34). A window born in the background parks the helper windows
// its constructor created off-screen with it; everything else in the
// process must stay where it is. The decision is pure over a snapshot of
// the process's top-level windows so it is testable without a window:
//
// - A window that existed before this construction began is not ours.
// - A window whose root owner is another main belongs to that main.
// - A window created by a thread the app itself started for other work
//   (the print thread) is not this construction's helper, even when it is
//   unowned and appeared during the construction (§34 item 1). Other
//   windows cannot interleave on the UI thread (a construction runs to its
//   sweep synchronously), and WinUI creates some constructor-born helpers
//   on its own framework threads, so thread identity alone never decides:
//   worker threads register themselves (measured 2026-09-25: the first
//   birth's only pinnable helper came from a framework thread).
// - A main window is never swept.
// - Without a fresh snapshot (a failed or overlapping construction
//   consumed or replaced it) nothing is swept: fail safe (§34 item 4).
public static class SiblingSelection
{
    public const string Pin = "pin";

    public static SiblingSnapshot Begin(IEnumerable<nint> current, uint constructingThread)
    {
        ArgumentNullException.ThrowIfNull(current);
        return new SiblingSnapshot(new HashSet<nint>(current), constructingThread);
    }

    static readonly HashSet<uint> WorkerThreads = [];
    static readonly object WorkerGate = new();

    // An app-started worker thread that may create windows registers for
    // its lifetime (dispose unregisters).
    public static IDisposable RegisterWorkerThread(uint threadId)
    {
        lock (WorkerGate)
        {
            _ = WorkerThreads.Add(threadId);
        }

        return new WorkerRegistration(threadId);
    }

    sealed class WorkerRegistration(uint threadId) : IDisposable
    {
        public void Dispose()
        {
            lock (WorkerGate)
            {
                _ = WorkerThreads.Remove(threadId);
            }
        }
    }

    public static IReadOnlyList<SiblingDecision> Decide(IEnumerable<SiblingTopLevel> current, SiblingSnapshot? snapshot, nint main)
    {
        ArgumentNullException.ThrowIfNull(current);
        HashSet<uint> workers;
        lock (WorkerGate)
        {
            workers = [.. WorkerThreads];
        }

        var decisions = new List<SiblingDecision>();
        foreach (SiblingTopLevel w in current.OrderBy(w => w.Handle))
        {
            string reason =
                snapshot is null ? "no-snapshot"
                : w.IsMain ? "main"
                : snapshot.Preexisting.Contains(w.Handle) ? "preexisting"
                : w.RootOwner != 0 && w.RootOwner != w.Handle && w.RootOwner != main ? "other-owner"
                : workers.Contains(w.ThreadId) ? "worker-thread"
                : Pin;
            decisions.Add(new SiblingDecision(w.Handle, reason));
        }

        return decisions;
    }

    // One line for the test-only sweep log: the chosen set and every skip
    // with its reason, so a proof never rests on a missed async event.
    // Each pinned handle carries its position read back right after the pin
    // (@x,y), so the log proves the pin landed at the target (§34 item 3)
    // even though a helper later follows its main.
    public static string Describe(nint main, int targetX, int targetY, IReadOnlyList<SiblingDecision> decisions, IReadOnlyDictionary<nint, (int X, int Y)>? pinnedAt = null)
    {
        ArgumentNullException.ThrowIfNull(decisions);
        string Hex(nint h) => "0x" + ((long)h).ToString("X", System.Globalization.CultureInfo.InvariantCulture);
        string At(nint h) => pinnedAt is not null && pinnedAt.TryGetValue(h, out var p) ? $"@{p.X.ToString(System.Globalization.CultureInfo.InvariantCulture)},{p.Y.ToString(System.Globalization.CultureInfo.InvariantCulture)}" : string.Empty;
        string pinned = string.Join(",", decisions.Where(d => d.Reason == Pin).Select(d => Hex(d.Handle) + At(d.Handle)));
        string skipped = string.Join(",", decisions.Where(d => d.Reason != Pin).Select(d => $"{Hex(d.Handle)}({d.Reason})"));
        return $"sweep main={Hex(main)} target={targetX.ToString(System.Globalization.CultureInfo.InvariantCulture)},{targetY.ToString(System.Globalization.CultureInfo.InvariantCulture)} pinned={pinned} skipped={skipped}";
    }
}

// Snapshot taken when a construction begins; consumed by that
// construction's sweep exactly once.
public sealed class SiblingSnapshot
{
    internal SiblingSnapshot(HashSet<nint> preexisting, uint thread)
    {
        Preexisting = preexisting;
        Thread = thread;
    }

    public IReadOnlySet<nint> Preexisting { get; }

    public uint Thread { get; }
}

public readonly record struct SiblingTopLevel(nint Handle, nint RootOwner, uint ThreadId, bool IsMain);

public readonly record struct SiblingDecision(nint Handle, string Reason);

// The construction in flight (D00 T02 §34 item 4): Begin replaces any
// snapshot a failed construction left behind, and Take hands the snapshot
// to exactly one sweep, so no birth ever reuses another's.
public sealed class SiblingSnapshotSlot
{
    SiblingSnapshot? pending;

    public void Begin(SiblingSnapshot snapshot) => pending = snapshot;

    public SiblingSnapshot? Take()
    {
        SiblingSnapshot? taken = pending;
        pending = null;
        return taken;
    }
}
