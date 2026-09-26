---
schema_version: 1
id: ui-input-residuals
domain: 00-workspace
status: draft
title: "TODO-12 -- UI Input Residuals"
depends_on: []
track: W0
---

# TODO-12 -- UI Input Residuals

> **Goal:** The UI suite's physical-input harness and binding guard are trustworthy at their edges: every mutation verdict is deterministic under mixed failures and proves a sensitive substitute, negative routing observes long enough over the state that matters, injected keys are owned and contained across processes and operator input, held chords follow one reset and counting contract, and the stock parity capture and physical debt name exactly what they prove.

> [!IMPORTANT]
> **Current state:** D00 T02 §51 (stamped 2026-09-26) made the binding mutation guard correlate each swap with its substitute's completion (`TestMutation.SwapDoneLine`, `BindingMutation.SwapEvidence` in `tests/UI/BindingMutation.cs`), attribute a kill only to an outcome assertion inside the chord's own segment (`BindingManifest.OutcomeAssertLines` in `tests/UI/BindingManifest.cs`), prove negative routing by zero dispatch over a state snapshot (`BindingMutation.RoutingProblem`), reconcile and contain stuck keys (`UiInput.ChordUp`, `UiInput.InputContainment`, `UiInput.SendChecked` in `tests/UI/UiInput.cs`), recheck input ownership before each held repeat (`UiInput.RepeatWhileOwned`), classify held chords in the app (`HeldChord` in `src/Notepad.Core/HeldChord.cs`), and capture stock Notepad's held-key behavior (`CaptureBaseline held-keys` in `tools/CaptureBaseline/Program.cs`), with the physical proof owed as D00-T02-S51-N1 and N2. Its plan review and round-5 cap left the residuals below; TODO-02, which holds §51, is at its 55-section cap, and no open file owns the UI input harness, so they live here.

## Inputs

- [`tests/UI/UiInput.cs`](../../tests/UI/UiInput.cs) -- the physical-input funnel §1 hardens (ownership, containment, recovery)
- [`tests/UI/BindingMutation.cs`](../../tests/UI/BindingMutation.cs), [`tests/UI/BindingManifest.cs`](../../tests/UI/BindingManifest.cs) -- the mutation guard whose verdict, substitute, and child-run rules §1 settles
- [`tests/UI/ChordRoutingTests.cs`](../../tests/UI/ChordRoutingTests.cs), [`tests/UI/HeldKeyTests.cs`](../../tests/UI/HeldKeyTests.cs) -- the negative-routing and held-key proofs §1 extends
- [`src/Notepad.Core/HeldChord.cs`](../../src/Notepad.Core/HeldChord.cs) -- the held-chord classifier whose reset and counting contract §1 completes
- [`tools/CaptureBaseline/Program.cs`](../../tools/CaptureBaseline/Program.cs) -- the stock capture whose settings and key ownership §1 pins
- `docs/ui-input-audit.md` -- the held-key classes, transitions, and debt mapping §1 updates
- `docs/reviews/00-workspace/D00-T02-s51.md` -- the plan-review ledger and round-5 finding each item cites
- -> XREF: D00 T02 §51 -- the binding guard section whose plan review and round-5 finding §1 carries.

## Outcome

- Every mutation case reads one deterministic verdict, from a substitute proven to change the tested state, in a child run that starts from the same state as its baseline.
- No physical key the suite did not press is ever released by it, no failed run leaves input uncontained for its parent or siblings, and every held chord resets and counts by one stated contract.

**Adjacency:** all=not-applicable (test-harness mechanics, an app accelerator helper's contract, and an operator capture tool; no editor state, app storage format, extension API, AI, protocol, or consent/undo surface)

**Adjacency rationale:** the section changes how the UI suite injects, attributes, and contains physical input and how the binding guard reads its verdicts; the app-side change is limited to the held-chord classifier's documented reset and counting rules, which alter no stored data or user-visible surface beyond the accelerator behavior §51 already set.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Binding guard fourth residuals | D00 T02 §51 |  [ ]   |

---

## 1. Binding Guard Fourth Residuals

Why this section exists: the §51 plan review returned 12 findings and all 12 file here, with §51's round-5 below-bar finding R5-I1 (in this file because TODO-02 reached its 55-section cap). §51 correlated swaps with execution, attributed kills to in-segment outcome assertions, separated negative routing, reconciled and contained stuck keys, classified held chords, captured stock parity, defined counting, enumerated enablement transitions, owned its physical debt, isolated child runs, and combined hold contracts with the surface matrix; these carry that through verdict precedence, substitute sensitivity, bounded negative observation, cross-process containment, operator key ownership, hold reset, stale targets, repeat identity, matrix completeness, pinned parity, one debt mapping, child state isolation, and capture key ownership. -> SOURCE: plan-review-D00-T02-s51-2026-09-26-d00t12s1 D00-T02-S51-PR1 D00-T02-S51-PR2 D00-T02-S51-PR3 D00-T02-S51-PR4 D00-T02-S51-PR5 D00-T02-S51-PR6 D00-T02-S51-PR7 D00-T02-S51-PR8 D00-T02-S51-PR9 D00-T02-S51-PR10 D00-T02-S51-PR11 D00-T02-S51-PR12 D00-T02-S51-R5-I1

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §51 -- filed from its plan review; carries the guard it settled.

- [ ] Mutation verdict precedence is defined for mixed failures (a substitute that changes state and then throws, an outcome mismatch beside a cleanup failure), so every combination reads one deterministic verdict and none reads a false kill. Done when: each mixed-failure fixture reads its documented verdict. (D00-T02-S51-PR1.)
- [ ] A substitute is valid only when its observable outcome differs from the original command's in the tested state (not equivalent, not disabled there), so every kill proves assertion sensitivity. Done when: an equivalent substitute reads an invalid case, never a kill. (D00-T02-S51-PR2.)
- [ ] Negative routing observes for a bounded period after the chord and over a defined protected state set (every tab and window, not only the active one), so a delayed dispatch or a change elsewhere cannot pass. Done when: a dispatch delayed past the immediate check, and a change to a background tab, each fail the case. (D00-T02-S51-PR3.)
- [ ] Containment propagates across processes: a child run that fails with a stuck or unknown key blocks physical input in its parent and sibling runs, and a terminated process never counts as proof its modifiers were released. Done when: a child killed with Ctrl down blocks the parent's next press with a named reason. (D00-T02-S51-PR4.)
- [ ] Injected-key ownership is reconciled with operator input during recovery: a key the operator presses while the funnel recovers is never released by it, because observing a key down cannot establish who owns it. Done when: an operator key held through a funnel recovery stays down. (D00-T02-S51-PR5.)
- [ ] Hold reset is defined for focus return and re-enablement while the key stays down: a fresh physical press is required before a one-shot command dispatches again, so a destructive command never replays. Done when: focus returning mid-hold of Ctrl+W closes nothing further. (D00-T02-S51-PR6.)
- [ ] A chord bound to its original target has a rule for a tab or control that closes, is replaced, or becomes disabled before dispatch: the chord neither acts on the stale target nor retargets another document silently. Done when: a target closed between key-down and dispatch reads the documented outcome. (D00-T02-S51-PR7.)
- [ ] An accepted repeat event has one identity across accelerator and root-route delivery, so deduplication tells two deliveries of one event from two legitimate repeats. Done when: one repeat delivered by both routes dispatches once, and two repeats dispatch twice. (D00-T02-S51-PR8.)
- [ ] The combined hold and surface matrix has a selection rule and a completeness check, and the physical debt names a successful repeatable-command hold (zoom repetition, tab cycling), so a listed subset cannot pass while a repeat path is broken. Done when: the completeness check fails on a removed matrix cell, and the debt lists a repeatable hold case. (D00-T02-S51-PR9.)
- [ ] The stock parity capture pins the Notepad version, Windows build, keyboard layout, and keyboard repeat settings, and names an owner who resolves a difference into the shipped class. Done when: a capture on unpinned settings refuses, and each class difference names its resolver. (D00-T02-S51-PR10.)
- [ ] One authoritative mapping records each held-key obligation to its evidence, superseding §43's assignment of the held-key proof to §36 explicitly, so collectors and reviewers read one owner per obligation. Done when: `docs/ui-input-audit.md` maps every held-key obligation to exactly one debt id. (D00-T02-S51-PR11.)
- [ ] Mutation child runs isolate document, settings, clipboard, and session state, and a baseline and its mutated run start from an equivalent state, so no verdict depends on leftover state. Done when: a child started over a dirty clipboard or session reads the same verdict as a clean one. (D00-T02-S51-PR12.)
- [ ] CaptureBaseline releases only the keys it injected: when an ownership check refuses before a key went down, cleanup sends no key-up for it. Done when: a capture refused at its first check sends no key-up. (D00-T02-S51-R5-I1.)
- [ ] Commit: `"workspace: settle the fourth binding guard residuals"`

**Test checkpoint:** Mixed failures read one verdict, substitutes prove sensitivity, negative routing observes long enough and widely enough, containment crosses processes, operator keys stay the operator's, holds reset only on a fresh press, stale targets never retarget, repeats have one identity, the matrix is complete, parity capture is pinned, debt maps once, child runs start equal, and the capture releases only its own keys. Cheaper substitute that fails: another assertion inside one happy-path hold.

## Verification

- [ ] `dotnet test src/ScratchPad.slnx --filter "Category!=Interactive&Category!=Primary"` under the foreground gate -- Run A green and the gate exit 0
- [ ] The section's plan-review ledger IDs read closed in its stamp
- [ ] `python3 scripts/todo-graph.py validate` clean
