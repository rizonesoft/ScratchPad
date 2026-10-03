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
- [`tests/UI/TabBarTests.cs`](../../tests/UI/TabBarTests.cs) `MiddleClick` -- the one pointer helper that already reads its point inside PerMonitorV2, the pattern §2 generalizes
- -> XREF: D01 T02 §10 -- its owed hover proof (D01-T02-S10-N1) failed on the DPI-virtualized pointer §2 fixes.

## Outcome

- Every mutation case reads one deterministic verdict, from a substitute proven to change the tested state, in a child run that starts from the same state as its baseline.
- No physical key the suite did not press is ever released by it, no failed run leaves input uncontained for its parent or siblings, and every held chord resets and counts by one stated contract.

**Adjacency:** all=not-applicable (test-harness mechanics, an app accelerator helper's contract, and an operator capture tool; no editor state, app storage format, extension API, AI, protocol, or consent/undo surface)

**Adjacency rationale:** the section changes how the UI suite injects, attributes, and contains physical input and how the binding guard reads its verdicts; the app-side change is limited to the held-chord classifier's documented reset and counting rules, which alter no stored data or user-visible surface beyond the accelerator behavior §51 already set.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Binding guard fourth residuals | D00 T02 §51 |  [ ]   |
|   2   |   §2    | Pointer moves in physical coordinates | -- |  [ ]   |
|   3   |   §3    | Element clicks in physical coordinates | §2 |  [ ]   |

---

## 1. Binding Guard Fourth Residuals

Why this section exists: the §51 plan review returned 12 findings and all 12 file here, with §51's round-5 below-bar finding R5-I1 (in this file because TODO-02 reached its 55-section cap). §51 correlated swaps with execution, attributed kills to in-segment outcome assertions, separated negative routing, reconciled and contained stuck keys, classified held chords, captured stock parity, defined counting, enumerated enablement transitions, owned its physical debt, isolated child runs, and combined hold contracts with the surface matrix; these carry that through verdict precedence, substitute sensitivity, bounded negative observation, cross-process containment, operator key ownership, hold reset, stale targets, repeat identity, matrix completeness, pinned parity, one debt mapping, child state isolation, and capture key ownership. -> SOURCE: plan-review-D00-T02-s51-2026-09-26-d00t12s1 D00-T02-S51-PR1 D00-T02-S51-PR2 D00-T02-S51-PR3 D00-T02-S51-PR4 D00-T02-S51-PR5 D00-T02-S51-PR6 D00-T02-S51-PR7 D00-T02-S51-PR8 D00-T02-S51-PR9 D00-T02-S51-PR10 D00-T02-S51-PR11 D00-T02-S51-PR12 D00-T02-S51-R5-I1 run-a-s52b-2026-09-26

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
- [ ] The menu helper's close wait treats a torn-down automation tree as closed: `WaitForMenuClosed` in `tests/UI/MenuBarTests.cs` catches `InvalidOperationException` and `FlaUIException` but not the `COMException` (0x8000FFFF, E_UNEXPECTED) UIA throws when the window is closing, so File > Exit and File > Close Window failed in the §52 tip Run A (2026-09-26, run s52b) while the app did what they asked. Done when: a `COMException` from the closing window's query reads as closed, and the two tests pass across three consecutive Run A passes. (Observed failure; SOURCE run-a-s52b-2026-09-26.)
- [ ] Commit: `"workspace: settle the fourth binding guard residuals"`

**Test checkpoint:** Mixed failures read one verdict, substitutes prove sensitivity, negative routing observes long enough and widely enough, containment crosses processes, operator keys stay the operator's, holds reset only on a fresh press, stale targets never retarget, repeats have one identity, the matrix is complete, parity capture is pinned, debt maps once, child runs start equal, and the capture releases only its own keys. Cheaper substitute that fails: another assertion inside one happy-path hold.

## 2. Pointer Moves in Physical Coordinates

> **Started:** 2026-10-03T21:21:01Z

Why this section exists: testhost is DPI-unaware, so an `AutomationElement.GetClickablePoint()` read outside a PerMonitorV2 thread context arrives virtualized, and moving the real cursor to it lands up-left of the target on a scaled display. `TabBarTests.MiddleClick` already documents and avoids this ("at 150% the miss reaches whatever window sits above ours"), but four other physical-pointer sites do not: `SettingsPageTests.AccentHoverPreviewsAndRestores` (swatch and heading), `TabBarTests.DragAttemptLeavesOrderUnchanged`, `MultiWindowTests.TabDragOutsideStripDetachesNothing`, and the shared `UiInput.Wheel` funnel. On 2026-10-03 the forced collection of D01-T02-S10-N1 (run 2026-10-03-223350) failed `0 px of #66A1D0, wanted at least 40`; a screen-capture rerun on the operator box (primary at 150%) showed the Ocean swatch at about screen (208, 628) while the cursor sat at (140, 417), exactly the swatch point divided by 1.5, so no hover fired. The drag tests pass vacuously under the same miss (their assertion is no reorder), so the defect hides there. This section moves every physical pointer action through one helper that reads and moves in physical pixels, and guards the class. **Corrected 2026-10-03 (implementation diagnosis):** physical coordinates alone did not fix the hover; an in-test hit test proved the cursor on `SettingsAccent-ocean` inside the app window at DPI 144 with no preview, because `SetCursorPos` is no input event and a cursor already parked on the target (left there by the previous rerun) makes no enter transition. The helper therefore moves by an absolute `SendInput` move before pinning the pixel, and a `Hover` entry point approaches from outside the element; with both, the hover drive read `ocean fill: 403 px on hover, 0 px after leaving`. **Corrected 2026-10-04 (self-review):** "every physical pointer action" read wider than the items; FlaUI element clicks (`AutomationElement.Click()` and `DoubleClick()`), which jump the cursor to a virtualized point too, are a second call form with fenced tests that need their own away-from-the-PC proof, so they file to §3 and this section owns the three raw move forms its items and guard name.

**Needs:** Windows host (build/test)

- -> XREF: D01 T02 §10 -- its owed hover proof is the first casualty; collecting it green is this section's live proof.
- -> XREF: D00 T12 §3 -- carries the FlaUI element-click form this section's guard does not cover.
- -> SOURCE: reconcile-2026-10-03-accent-hover-dpi (Night-red 6a7661d; diagnostic frames at 150% primary scaling)

- [x] A `UiPointer` helper in `tests/UI/UiPointer.cs` reads an element's clickable point and sets the cursor inside one `UiDpi.Enter()` context, and offers the same for a physical point path (drag interpolation), returning the physical point it used. Done when: `TabBarTests.MiddleClick` uses it instead of its private `SetCursorPos` pair, with behavior unchanged. Done: `UiPointer.ClickablePoint`, `Bounds`, `MoveTo(element)`, `MoveTo(point)`, `Travel`, and `Hover` read and set inside one `UiDpi.Enter()` context, moving by an absolute `SendInput` move and proving the landed pixel with `GetCursorPos`; `TabBarTests.MiddleClick` now calls `UiPointer.MoveTo` and its private `SetCursorPos` import is gone.
- [x] Every physical pointer site goes through `UiPointer`: `SettingsPageTests.AccentHoverPreviewsAndRestores` (swatch and heading), `TabBarTests.DragAttemptLeavesOrderUnchanged`, `MultiWindowTests.TabDragOutsideStripDetachesNothing`, and `UiInput.Wheel`, plus `TitleBarIconTests.LeftClick` (**Corrected 2026-10-03:** the guard found this fifth site, a direct `SetCursorPos` already inside PerMonitorV2 and so correct, which routes through `UiPointer` so the guard has no exceptions). Done when: no `Mouse.MoveTo(` or `Mouse.Position =` remains in `tests/UI` outside `UiPointer.cs`. Done: the hover test (through `UiPointer.Hover`), both drags, `UiInput.Wheel`, and `TitleBarIconTests.LeftClick` route through `UiPointer`; the guard's live scan reads clean.
- [x] `AccentHoverPreviewsAndRestores` pins its window topmost while the pointer hovers and unpins in `finally` (`UiDpi.PinTopmost`, as the drag tests do), so an overlapping window can never take the hover. Done when: the pin and unpin read in the test. Done: `UiDpi.PinTopmost(window, true)` wraps the hover and leave with the unpin in `finally`.
- [x] A default-suite guard fails when a `tests/UI` source moves the real cursor outside `UiPointer.cs` (`Mouse.MoveTo(`, `Mouse.Position =`, or a direct `SetCursorPos`). Done when: the guard passes on the tree and a planted raw call fed to its scanner fails it with the file and line named. Done: `UiPointerGuardTests` (default suite): six planted shapes fail naming file and line, four sanctioned shapes pass, `LiveTreeScansClean` passes; population fingerprint re-accepted (run-a 283/347 to 287/359, the four guard methods only).
- [x] Commit: `"workspace: move the real pointer in physical coordinates"`

**Test checkpoint:** The default run of the new guard passes, and its planted-call fixture fails naming the site. With the operator away, `SCRATCHPAD_INTERACTIVE_FORCE=1 dotnet test tests/UI/UI.csproj --filter "FullyQualifiedName~SettingsPageTests.AccentHoverPreviewsAndRestores|FullyQualifiedName~TabBarTests.DragAttemptLeavesOrderUnchanged|FullyQualifiedName~MultiWindowTests.TabDragOutsideStripDetachesNothing|FullyQualifiedName~TabBarTests.MiddleClickClosesTheTabUnderTheCursor"` passes on the 150% primary, and `tools/nightly.ps1 -Force -CollectDebt D01-T02-S10-N1 -SkipDefault -SkipPrimary -SkipSoak` appends `Night-collected:` for D01-T02-S10-N1. Fails if the hover still finds no preview pixels or the collection reads red.

## 3. Element Clicks in Physical Coordinates

Why this section exists: FlaUI's `AutomationElement.Click()` and `DoubleClick()` move the real cursor to the element's clickable point before clicking, and testhost reads that point DPI-virtualized, so on a scaled display the click lands up-left of its target exactly as §2's raw moves did. Nine sites use them: `PinnedTabsTests.DoubleClickTogglesPinGlyph`, `PinsSurviveRelaunch`, and `CloseOthersSkipsPinned` (fenced Interactive, double-click), `LaunchTests.MissingFileOfferEnterAcceptsAsYes` (fenced Interactive), and the click fallbacks in `MenuBarTests` helpers `OpenSubmenu`, `ClickFoundItem` (the mouse-only items), `InvokeOrClick`, `ExpandCombo`, and `SelectEncoding`, which default-suite tests reach. Found in §2's self-review on 2026-10-04; §2 fixed and guarded the raw move forms only.

**Needs:** Windows host (build/test)

- -> XREF: D00 T12 §2 -- supplies the `UiPointer` helper and guard this section extends.
- -> SOURCE: reconcile-2026-10-04-element-click-dpi (grep of `.Click(` and `.DoubleClick(` under `tests/UI` on a615bf8)

- [ ] `UiPointer` gains `Click(element)` and `DoubleClick(element)` that move through `UiPointer.MoveTo` and press with FlaUI's coordinate-free `Mouse.Click(MouseButton.Left)` and `Mouse.DoubleClick(MouseButton.Left)`. Done when: both exist and every one of the nine sites calls them instead of the element method.
- [ ] The §2 guard also fails a FlaUI element click (`.Click(`, `.DoubleClick(`, `.RightClick(`, `.RightDoubleClick(` calls) and a pointed `Mouse.Click(` outside `UiPointer.cs`. Done when: planted forms fail naming file and line and the live tree scans clean.
- [ ] Commit: `"workspace: click elements in physical coordinates"`

**Test checkpoint:** The guard passes on the tree and fails its planted element-click fixtures; the default run of `MenuBarTests` passes under `SCRATCHPAD_BACKGROUND=1`; and with the operator away, `SCRATCHPAD_INTERACTIVE_FORCE=1 dotnet test tests/UI/UI.csproj --filter "FullyQualifiedName~PinnedTabsTests|FullyQualifiedName~LaunchTests.MissingFileOfferEnterAcceptsAsYes"` passes on the 150% primary. Fails if any of the nine sites still clicks a virtualized point.

## Verification

- [ ] `dotnet test src/ScratchPad.slnx --filter "Category!=Interactive&Category!=Primary"` under the foreground gate -- Run A green and the gate exit 0
- [ ] The section's plan-review ledger IDs read closed in its stamp
- [ ] `python3 scripts/todo-graph.py validate` clean
