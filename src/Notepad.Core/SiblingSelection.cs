namespace Notepad.Core;

// Background-birth sibling sweep selection (D00 T02 §26, hardened by
// D00 T02 §34 and §41). A window born in the background parks the helper
// windows its constructor created off-screen with it; everything else in
// the process must stay where it is. The decision is pure over a snapshot
// of the process's top-level windows so it is testable without a window:
//
// - A window that existed before this construction began is not ours. The
//   app marks every window it snapshots (a window property carrying the
//   snapshot's generation), so a handle value the OS reused for a new
//   window after the snapshot reads as new, not preexisting (§41 item 2);
//   a snapshotted window the app could not mark has no such proof and is
//   skipped as ambiguous (§41 item 3).
// - A window another construction claimed (its sweep pinned it, or it is
//   that construction's main) is that construction's, whatever the order
//   of the sweeps (§41 item 1): provenance, not same-thread exclusivity,
//   decides.
// - A window whose provenance cannot be read (its thread or owner query
//   failed mid-enumeration) is ambiguous: skipped and reported, never
//   pinned blind (§41 item 3).
// - A window whose root owner is another main belongs to that main.
// - A window created by a thread the app itself started for other work
//   (the print thread) is not this construction's helper, even when it is
//   unowned and appeared during the construction (§34 item 1). WinUI
//   creates some constructor-born helpers on its own framework threads, so
//   thread identity alone never decides: worker threads register
//   themselves (measured 2026-09-25: the first birth's only pinnable
//   helper came from a framework thread).
// - A main window is never swept.
// - Without a fresh snapshot (a failed or overlapping construction
//   consumed or replaced it) nothing is swept: fail safe (§34 item 4).
public static class SiblingSelection
{
    public const string Pin = "pin";

    static long generations;

    public static SiblingSnapshot Begin(IEnumerable<nint> current, uint constructingThread)
    {
        ArgumentNullException.ThrowIfNull(current);
        return new SiblingSnapshot(new HashSet<nint>(current), constructingThread, Interlocked.Increment(ref generations), null);
    }

    // The marking form (§41 item 2): `marked` is the subset of `current`
    // the app stamped with this snapshot's generation; the rest could not
    // be marked and read ambiguous if they are still unmarked at the sweep.
    public static SiblingSnapshot Begin(IEnumerable<nint> current, uint constructingThread, Func<long, IEnumerable<nint>> mark)
    {
        ArgumentNullException.ThrowIfNull(current);
        ArgumentNullException.ThrowIfNull(mark);
        long generation = Interlocked.Increment(ref generations);
        var all = new HashSet<nint>(current);
        var marked = new HashSet<nint>(mark(generation));
        marked.IntersectWith(all);
        return new SiblingSnapshot(all, constructingThread, generation, marked);
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

    public static IReadOnlyList<SiblingDecision> Decide(IEnumerable<SiblingTopLevel> current, SiblingSnapshot? snapshot, nint main, IReadOnlyDictionary<nint, long>? claims = null)
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
            decisions.Add(new SiblingDecision(w.Handle, Reason(w, snapshot, main, claims, workers)));
        }

        return decisions;
    }

    static string Reason(SiblingTopLevel w, SiblingSnapshot? snapshot, nint main, IReadOnlyDictionary<nint, long>? claims, HashSet<uint> workers)
    {
        if (w.IsMain)
        {
            return "main";
        }

        // A claim counts only while the window still carries that claim's
        // mark (R1-F2): a claimed handle destroyed and reused by a new
        // window has lost the mark, so the stale claim is ignored.
        if (claims is not null && claims.TryGetValue(w.Handle, out long owner) && owner != (snapshot?.Generation ?? 0) && w.ClaimMark == owner)
        {
            return "other-construction";
        }

        if (!w.Readable)
        {
            return "ambiguous";
        }

        if (snapshot is null)
        {
            return "no-snapshot";
        }

        if (snapshot.Preexisting.Contains(w.Handle))
        {
            if (snapshot.Marked is null)
            {
                return "preexisting";
            }

            if (!snapshot.Marked.Contains(w.Handle))
            {
                // Never marked: nothing tells an old window from a reused
                // handle, so it is skipped and reported, not pinned blind.
                return "ambiguous";
            }

            if (w.Mark >= snapshot.Generation)
            {
                return "preexisting";
            }

            // Marked at the snapshot but the mark is gone: the window was
            // destroyed and the OS reused its handle for a new window.
        }

        if (w.RootOwner != 0 && w.RootOwner != w.Handle && w.RootOwner != main)
        {
            return "other-owner";
        }

        return workers.Contains(w.ThreadId) ? "worker-thread" : Pin;
    }

    // Revalidation immediately before a move (§41 item 5): the window read
    // again must still be the one selected (alive, same thread, same class
    // of ownership); a destroyed, reused, or re-owned handle is never
    // moved. Returns Pin when the move may proceed, else the skip reason.
    public static string Revalidate(SiblingTopLevel selected, SiblingTopLevel? now, nint main)
    {
        if (now is not { } w)
        {
            return "gone-before-move";
        }

        if (w.IsMain)
        {
            return "main";
        }

        // Identity is thread, class, and both marks (R1-F1): a handle value
        // destroyed and reused between the read and the move differs in at
        // least one unless the reuse lands on the same thread with the same
        // class and no marks, and Win32 exposes nothing further; HWND
        // values carry a reuse counter in their high word, so an exact
        // value comes back only after that counter wraps.
        if (!w.Readable || w.ThreadId != selected.ThreadId || !string.Equals(w.ClassName, selected.ClassName, StringComparison.Ordinal) || w.Mark != selected.Mark || w.ClaimMark != selected.ClaimMark)
        {
            return "reused-before-move";
        }

        return w.RootOwner != 0 && w.RootOwner != w.Handle && w.RootOwner != main ? "reowned-before-move" : Pin;
    }

    // The delayed placement pass (§41 item 4): windows that appeared after
    // the sweep are decided with the same snapshot and claims; handles the
    // sweep already decided are left alone. When another construction has
    // begun since this one's sweep, the pass does nothing (its windows
    // could be either construction's) and says so.
    public static IReadOnlyList<SiblingDecision> DecideLate(IEnumerable<SiblingTopLevel> current, SiblingSnapshot snapshot, nint main, IReadOnlySet<nint> decided, IReadOnlyDictionary<nint, long>? claims, bool anotherConstructionBegan)
    {
        ArgumentNullException.ThrowIfNull(current);
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(decided);
        var late = current.Where(w => !decided.Contains(w.Handle)).ToList();
        if (anotherConstructionBegan)
        {
            return [.. late.OrderBy(w => w.Handle).Select(w => new SiblingDecision(w.Handle, w.IsMain ? "main" : "late-skipped-overlap"))];
        }

        return Decide(late, snapshot, main, claims);
    }

    // One line for the test-only sweep log: the chosen set and every skip
    // with its reason, so a proof never rests on a missed async event.
    // Each pinned handle carries its position read back right after the pin
    // (@x,y), so the log proves the pin landed at the target (§34 item 3)
    // even though a helper later follows its main. The phase (`sweep` or
    // `sweep-late`) and the construction generation lead the line (§41).
    public static string Describe(nint main, int targetX, int targetY, IReadOnlyList<SiblingDecision> decisions, IReadOnlyDictionary<nint, (int X, int Y)>? pinnedAt = null, string phase = "sweep", long generation = 0)
    {
        ArgumentNullException.ThrowIfNull(decisions);
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        string Hex(nint h) => "0x" + ((long)h).ToString("X", inv);
        string At(nint h) => pinnedAt is not null && pinnedAt.TryGetValue(h, out var p) ? $"@{p.X.ToString(inv)},{p.Y.ToString(inv)}" : string.Empty;
        string pinned = string.Join(",", decisions.Where(d => d.Reason == Pin).Select(d => Hex(d.Handle) + At(d.Handle)));
        string skipped = string.Join(",", decisions.Where(d => d.Reason != Pin).Select(d => $"{Hex(d.Handle)}({d.Reason})"));
        return $"{phase} main={Hex(main)} target={targetX.ToString(inv)},{targetY.ToString(inv)} gen={generation.ToString(inv)} pinned={pinned} skipped={skipped}";
    }
}

// Snapshot taken when a construction begins; consumed by that
// construction's sweep exactly once. Generation orders constructions;
// Marked is the subset the app stamped (null when marking was not used).
public sealed class SiblingSnapshot
{
    internal SiblingSnapshot(HashSet<nint> preexisting, uint thread, long generation, HashSet<nint>? marked)
    {
        Preexisting = preexisting;
        Thread = thread;
        Generation = generation;
        Marked = marked;
    }

    public IReadOnlySet<nint> Preexisting { get; }

    public uint Thread { get; }

    public long Generation { get; }

    public IReadOnlySet<nint>? Marked { get; }
}

// Mark is the snapshot generation the window's mark property carries (0
// when it has none); ClaimMark is the generation of the construction whose
// claim the window carries (0 when none); Readable is false when the
// window's thread or owner could not be read (it was being destroyed
// mid-enumeration); ClassName is the window class, part of its identity.
public readonly record struct SiblingTopLevel(nint Handle, nint RootOwner, uint ThreadId, bool IsMain, long Mark = 0, bool Readable = true, string ClassName = "", long ClaimMark = 0);

public readonly record struct SiblingDecision(nint Handle, string Reason);

// The construction in flight (D00 T02 §34 item 4): each construction
// keeps the snapshot Begin returned as its token, and Take hands it back
// only to that construction, only while it is still the one in flight. A
// failed construction's snapshot is replaced by the next Begin; an
// overlapping construction's sweep gets nothing rather than another
// construction's snapshot (§34 R1-F1). Claims (§41 item 1) record which
// construction each swept window and main belongs to, so a later sweep
// reads another construction's window as that construction's.
public sealed class SiblingSnapshotSlot
{
    SiblingSnapshot? pending;
    long latestBegun;
    readonly Dictionary<nint, long> claims = [];

    public SiblingSnapshot Begin(SiblingSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        pending = snapshot;
        latestBegun = Math.Max(latestBegun, snapshot.Generation);
        return snapshot;
    }

    public SiblingSnapshot? Take(SiblingSnapshot? token)
    {
        if (token is null || !ReferenceEquals(token, pending))
        {
            return null;
        }

        pending = null;
        return token;
    }

    // True when a construction began after `token` did, whether or not it
    // has swept since (R2-F1): the late pass must not attribute windows
    // that could be the newer one's.
    public bool BegunSince(SiblingSnapshot token)
    {
        ArgumentNullException.ThrowIfNull(token);
        return latestBegun > token.Generation;
    }

    public IReadOnlyDictionary<nint, long> Claims => claims;

    public void Claim(long generation, IEnumerable<nint> handles)
    {
        ArgumentNullException.ThrowIfNull(handles);
        foreach (nint h in handles)
        {
            claims[h] = generation;
        }
    }

    // A destroyed window's claim is released so its reused handle value
    // starts clean; `alive` answers whether the handle is still the window
    // the claim was made on (alive and carrying the claim's mark).
    public void Release(Func<nint, long, bool> alive)
    {
        ArgumentNullException.ThrowIfNull(alive);
        foreach (var (h, gen) in claims.Where(kv => !alive(kv.Key, kv.Value)).ToList())
        {
            _ = claims.Remove(h);
        }
    }
}
