---
schema_version: 1
id: launch-harness-residuals
domain: 00-workspace
status: draft
title: "TODO-10 -- Launch Harness Residuals"
depends_on: []
track: W0
---

# TODO-10 -- Launch Harness Residuals

> **Goal:** The UI suite's background launch harness is trustworthy at its edges: the sibling sweep places or contains every helper a window birth creates, under overlap, failure, topology change, and load, with one verdict and independent proof; and the foreground gate attributes every event to the right process instance, reads unknowns honestly, stays private and cheap, and owns every process it starts.

> [!IMPORTANT]
> **Current state:** D00 T02 §48 (stamped 2026-09-26) made the sweep place or report overlapped helpers (`SiblingSelection.OverlapUnplaced`, `PlacementVerdict` in `src/Notepad.Core/SiblingSelection.cs`), abandon failed constructions through `SiblingSelection.ConstructOrAbandon` (used by `App.AddWindow` in `src/ScratchPad/App.xaml.cs`), log a per-pass cost line (`src/ScratchPad/MainWindow.xaml.cs`), and prove first births pinned (`FirstBirthGaps` in `tests/UI/LaunchTests.cs`). D00 T02 §49 (stamped 2026-09-26) made `tools/ForegroundLog/Program.cs` attribute events by (pid, process start time) and name the executable path, with `UiLaunch.RunToolCaptured` (`tests/UI/UiLaunch.cs`) running its selftest under one deadline. Their plan reviews and §49's round-5 cap left the residuals below; TODO-02, which holds both sections, reached its 55-section cap, so they live here.

## Inputs

- [`src/Notepad.Core/SiblingSelection.cs`](../../src/Notepad.Core/SiblingSelection.cs) -- the sweep decisions §1 extends
- [`src/ScratchPad/MainWindow.xaml.cs`](../../src/ScratchPad/MainWindow.xaml.cs) -- the app's sweep, delayed pass, and cost lines §1 hardens
- [`tests/UI/LaunchTests.cs`](../../tests/UI/LaunchTests.cs), [`tests/UI/UiLaunchDiagnostics.cs`](../../tests/UI/UiLaunchDiagnostics.cs) -- the first-birth proof and launch records §1 tightens
- [`tools/ForegroundLog/Program.cs`](../../tools/ForegroundLog/Program.cs) -- the gate §2 hardens
- [`tests/UI/UiLaunch.cs`](../../tests/UI/UiLaunch.cs) -- the sanctioned launch home whose captured tool run §2 gives a tree-owned lifetime
- `docs/reviews/00-workspace/D00-T02-s48.md`, `docs/reviews/00-workspace/D00-T02-s49.md` -- the plan-review ledgers each item cites
- -> XREF: D00 T02 §48 -- the sweep section whose plan review §1 carries.
- -> XREF: D00 T02 §49 -- the gate section whose plan review and round-5 finding §2 carries.

## Outcome

- Every helper a background birth creates ends placed, contained, or reported under one verdict, proven independently of the app's own log, within a stated budget under load.
- Every gate event names the process instance that owned the window at the event, or reads unknown, and every tool the suite starts is owned to its last descendant.

**Adjacency:** all=not-applicable (test-harness mechanics under the test-run marker and the foreground gate tooling; no editor state, app storage format, extension API, AI, protocol, or consent/undo surface)

**Adjacency rationale:** both sections change how the UI suite launches, places, observes, and attributes windows; the app-side sweep code runs only under the test-run marker and never alters a user-visible surface or stored data.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Sibling sweep fourth residuals | D00 T02 §48 |  [ ]   |
|   2   |   §2    | Gate attribution residuals | D00 T02 §49 |  [ ]   |

---

## 1. Sibling Sweep Fourth Residuals

Why this section exists: the §48 plan review returned 16 findings; 15 file here (in this file because TODO-02 reached its 55-section cap) and 1 is rejected with its reason in the §48 findings file. §48 placed or reported overlapped helpers, failed visible unplaced ones, proved shared-thread attribution, bounded the recorder, required every first-birth helper pinned, abandoned failed constructions, correlated diagnostics by generation, revalidated topology, and measured the cost; these carry that through terminal overlap outcomes, containment, one verdict, unobtrusive births, adversarial attribution, the move race, topology during the move, recorder limits, independent reconciliation, queued teardown, log faults, harder workloads, the dialog proof, one contract, and a compact summary. -> SOURCE: plan-review-D00-T02-s48-2026-09-26-d00t10s1 D00-T02-S48-PR1 D00-T02-S48-PR2 D00-T02-S48-PR3 D00-T02-S48-PR4 D00-T02-S48-PR5 D00-T02-S48-PR6 D00-T02-S48-PR7 D00-T02-S48-PR8 D00-T02-S48-PR9 D00-T02-S48-PR10 D00-T02-S48-PR11 D00-T02-S48-PR12 D00-T02-S48-PR13 D00-T02-S48-PR15 D00-T02-S48-PR16

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §48 -- filed from its plan review; carries the sweep it settled.

- [ ] Overlapping constructions have a retry deadline, fairness, and a terminal outcome, so a deferred helper never stays unplaced indefinitely. Done when: a helper deferred past its deadline reads a terminal failure. (D00-T02-S48-PR1.)
- [ ] A failed placement verdict contains what it reports: the launch terminates safely and owned windows are cleaned up. Done when: a visible ambiguous helper leaves no window on screen after the failure. (D00-T02-S48-PR2.)
- [ ] One authoritative placement verdict covers initial, deferred, ambiguous, and timed-out outcomes, with §41's reported-only late helpers corrected to it. Done when: each outcome reads one verdict and §41 carries the correction. (D00-T02-S48-PR3.)
- [ ] Background births stay unobtrusive throughout construction: no transient on-screen exposure and no foreground activation before placement. Done when: a recorded birth shows no on-screen frame and no activation. (D00-T02-S48-PR4.)
- [ ] An unowned helper's construction provenance has a stated contract with adversarial overlapping fixtures, so a claim never simply encodes whichever construction saw it first. Done when: an adversarial overlap attributes each helper to its own construction. (D00-T02-S48-PR5.)
- [ ] The race between revalidation and the move (destruction, handle reuse, re-ownership) has a deterministic fixture and an explicit achievable safety guarantee. Done when: a handle reused between check and move is never moved. (D00-T02-S48-PR6.)
- [ ] A topology change during or right after the delayed move has bounded recomputation, post-move validation, and a terminal failure. Done when: a monitor attached mid-move ends with the helper off-screen or a failure. (D00-T02-S48-PR7.)
- [ ] The location recorder's coverage, readiness, drain completion, timeout, and capacity are numeric acceptance criteria. Done when: each limit has a fixture that trips it. (D00-T02-S48-PR8.)
- [ ] The first-birth proof reconciles each helper's identity and final position independently of the app's log. Done when: a helper logged as pinned but read elsewhere by the test fails. (D00-T02-S48-PR9.)
- [ ] Cancellation and teardown while deferred placement is queued cannot move reused handles or retain dead constructions. Done when: closing a window before its delayed pass leaves nothing queued. (D00-T02-S48-PR10.)
- [ ] Missing, truncated, or unwritable sweep logs have a defined effect on the proof verdict, with fault fixtures. Done when: an unwritable log reds the proof instead of passing. (D00-T02-S48-PR11.)
- [ ] The budget holds under sustained overlap and failure workloads, not only twenty clean births, with a recovery criterion. Done when: overlapped and failing births stay within the budget. (D00-T02-S48-PR12.)
- [ ] §34's owned-dialog proof runs against the current sweep on the current candidate. Done when: the owned-dialog test passes on the stamped candidate. (D00-T02-S48-PR13.)
- [ ] One consolidated current sweep contract maps each invariant to its owner and proof, correcting §41's exclusive-interleaving checkpoint. Done when: every invariant names its owner section and fixture. (D00-T02-S48-PR15.)
- [ ] Each launch carries a compact diagnostic summary (generation, verdict, unresolved helper count, failure reason). Done when: a concurrent-launch failure reads its summary line. (D00-T02-S48-PR16.)
- [ ] Commit: `"workspace: settle the fourth sibling sweep residuals"`

**Test checkpoint:** Overlaps end, failures contain, one verdict rules, births stay unobtrusive, attribution resists adversaries, the move race and topology changes are safe, the recorder has limits, reconciliation is independent, teardown clears queued work, log faults red, the budget holds under load, the dialog proof reruns, one contract maps owners, and each launch summarizes itself. Cheaper substitute that fails: another log field no test reads.

## 2. Gate Attribution Residuals

Why this section exists: the §49 plan review returned 12 findings; 11 file here with §49's round-5 finding R5-I1 (in this file because TODO-02 reached its 55-section cap) and 1 is rejected with its reason in the §49 findings file. §49 attributed each gate event to its process by pid and start time and named the executable in every line; these carry that through event-time ownership, atomic reads, unknown outcomes, recognition rules, evidence joins, one identity everywhere, detection controls, path privacy, lookup cost, historical reassessment, and one stale-chord case from the §43 surface its false red came from. -> SOURCE: plan-review-D00-T02-s49-2026-09-26-d00t10s2 D00-T02-S49-PR1 D00-T02-S49-PR2 D00-T02-S49-PR3 D00-T02-S49-PR4 D00-T02-S49-PR5 D00-T02-S49-PR6 D00-T02-S49-PR7 D00-T02-S49-PR9 D00-T02-S49-PR10 D00-T02-S49-PR11 D00-T02-S49-PR12 D00-T02-S49-R5-I1

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §49 -- filed from its plan review and its round-5 cap; carries the gate attribution it settled.

- [ ] A delayed event is attributed to the process that owned the window when the event occurred, or reads unresolved. Done when: a queued event after pid and window reuse reads unresolved, never the new owner. (D00-T02-S49-PR1.)
- [ ] Identity is read atomically: executable path and creation time from one process instance, with window ownership revalidated. Done when: a process exiting between the two reads yields no mixed identity. (D00-T02-S49-PR2.)
- [ ] Access-denied, exited, and unavailable metadata read an explicit unknown attribution with a defined effect on the gate verdict. Done when: an unknown attribution neither blames ScratchPad nor reads clean silently. (D00-T02-S49-PR3.)
- [ ] ScratchPad is recognized by the expected executable and the launched process instances, not a name. Done when: an unrelated executable named ScratchPad never trips the gate. (D00-T02-S49-PR4.)
- [ ] Leak bundles and launch diagnostics join by process instance, not pid alone. Done when: a reused pid never attaches another process's bundle. (D00-T02-S49-PR5.)
- [ ] EVENT, census, deduplication, and event-versus-census reconciliation share one identity. Done when: no stale counter or false mismatch after a relabel. (D00-T02-S49-PR6.)
- [ ] Controls prove detection is preserved: a replacement ScratchPad process on a reused pid still trips the gate, and an unchanged process stays attributed. Done when: the replacement fixture trips the gate. (D00-T02-S49-PR7.)
- [ ] Executable paths are redacted consistently with §18's privacy intent while still identifying the executable. Done when: a profile path reads redacted and the executable still identifies. (D00-T02-S49-PR9.)
- [ ] Lookup cost is bounded and handles are released under event bursts. Done when: a burst fixture stays within its time bound and leaks no handle. (D00-T02-S49-PR10.)
- [ ] Gate evidence recorded before the attribution fix is marked for reassessment without rewriting history. Done when: each pre-fix green names its attribution version. (D00-T02-S49-PR11.)
- [ ] A chord whose original target is destroyed or disabled mid-chord never delivers a stale command (the §43 surface, recorded here with its owner). Done when: a tab closed mid-chord receives nothing. (D00-T02-S49-PR12.)
- [ ] The captured tool run owns its whole process tree (a job object or equivalent), so a timeout after the parent exits still terminates a pipe-holding descendant, and the result says what was terminated. Done when: a tool that exits leaving a pipe-holding child ends with the child terminated and named. (D00-T02-S49-R5-I1.)
- [ ] Commit: `"workspace: settle the gate attribution residuals"`

**Test checkpoint:** Events attribute at event time, reads are atomic, unknowns are explicit, recognition is by instance, evidence joins by instance, identities agree, detection is controlled both ways, paths stay private, lookups are bounded, history is marked, stale chords go nowhere, and captured tool runs own their whole tree. Cheaper substitute that fails: a longer log line.

## Verification

- [ ] `dotnet test src/ScratchPad.slnx --filter "Category!=Interactive&Category!=Primary"` under the foreground gate -- Run A green and the gate exit 0
- [ ] Each section's plan-review ledger IDs read closed in its stamp
- [ ] `python3 scripts/todo-graph.py validate` clean
