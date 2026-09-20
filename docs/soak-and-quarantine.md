# Soak and Quarantine Procedure

UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks. This procedure is the only sanctioned path for a flaky test: soak to find flakes, quarantine to contain them, a window to fix or remove them, and a record so nothing vanishes silently. A retry loop that hides a flake is never a substitute: retries make red green without evidence, while quarantine keeps the failure visible and owned.

## Nightly soak

Soak runs locally, usually as an unattended bedtime run: the full Windows suite plus five extra repetitions of the flake-prone suites (UI and Protocol), all with `trx` loggers; the CI `soak` workflow repeats the same shape nightly. The command below shows the local shape.

`.tools\dotnet-win-x64\dotnet.exe test src/ScratchPad.slnx --logger trx`, then the UI and Protocol suites x5.

Results stay under `TestResults/` (gitignored): the per-run console log plus the trx files, with golden-failure captures kept alongside on UI failure. Runs are linked from this doc only when they catch a flake: a quarantine entry references the run that proved the flake, so the run history stays the log and this doc stays the index.

## Soak log

| Date | Run | Result |
| ---- | --- | ------ |
| 2026-09-14 | [34808621885](https://github.com/rizonesoft/ScratchPad/actions/runs/34808621885) (dispatch) | success, 22 passed, 0 failed |
| 2026-09-14 | [34809456063](https://github.com/rizonesoft/ScratchPad/actions/runs/34809456063) (dispatch, after red-repeat fix) | success, 22 passed, 0 failed |

## Quarantine

A test that fails nondeterministically (red in one run, green in another, with no code change between) is quarantined, not deleted and not retried into silence:

1. Prove the flake: two runs of the same commit with different outcomes, or one soak run plus one local run disagreeing. Quote both.
2. Skip the test with xUnit `Skip` carrying the quarantine stamp: `[Fact(Skip = "QUARANTINED <date> <owner> <signature-id>")]`. The test stays compiled; the suite stays green; the skip reason names this doc entry.
3. Add the row to the quarantine list below. The failure signature is the stable part of the failure (exception type plus message shape, never timestamps or line heat).

A quarantined test keeps running nowhere until it is fixed (un-skipped with a passing soak behind it) or removed (with its decision recorded below).

## Quarantine list

| Test | Failure signature | First seen | Owner | Quarantined | Due |
| ---- | ----------------- | ---------- | ----- | ----------- | --- |
| `UI.TabBarTests.ContextMenuMatchesNotepad` (`ctxmenu-name-race`) | xUnit `Assert.Equal` on `TabItemAt().Name` after a context-menu close: expected one tab's name, got a surviving sibling's, so the wrong tab closed. Proof: commit `62656a2` red in the full suite, green solo (quoted in `docs/reviews/01-notepad-core/D01-T01-s6.md`). Likely cause: right-click targeting/timing under machine load or live user input during the menu drive. | 2026-09-15 | D01 T01 §3 | 2026-09-15 | 2026-09-22 |
| `UI.AppIconTests.WindowChromeIconMatchesAsset` (`chrome-icon-uia-timeout`) | `System.TimeoutException: UIA Timeout` (inner COMException 0x80131505) attaching to the launched app. Proof: commit `c07b2c6` red on run 35234746568 attempt 1, green on the `--failed` rerun of the same commit (failure text quoted in `docs/reviews/01-notepad-core/D01-T01-s32.md`). Likely cause: slow-runner UIA stall. | 2026-09-17 | D01 T01 §11 | 2026-09-17 | 2026-09-24 |
| `UI.LaunchTests.MissingFileOfferYesBindsTabAndSaveCreates` (`save-prompt-dialog-null`) | xUnit `Assert.NotNull` on the Ctrl+W save prompt in `WaitForDialog` (`SavePromptDialog`, call site `LaunchTests.cs:216`): the prompt never appeared. The missing-file offer dialog passed. Proof: commit `c07b2c6` red on run 35234746568 attempt 1, green on the `--failed` rerun of the same commit (failure text quoted in `docs/reviews/01-notepad-core/D01-T01-s32.md`). Likely cause: slow-runner dialog delay. Coverage note: §8's offer-Yes-through-save path is uncovered until reinstatement (siblings cover bind-only and the No path). | 2026-09-17 | D01 T01 §7 | 2026-09-17 | 2026-09-24 |
| `UI.SessionRestoreTests.MultiWindowSessionRestoresBothWindows` (`multiwindow-single-empty`) | xUnit `Assert.Single() Failure: The collection was empty`: session restore laid no windows. Proof: red in the 02:30 Nightly UI run, green in the governed re-run, test-identical trees (no `tests/` or `src/` changes between the runs; counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §6 | 2026-09-20 | 2026-09-27 |
| `UI.ReloadTests.DirtyReloadDiscardsEdits` (`dirty-reload-zero-tabs`) | xUnit `Assert.Equal` tab-count: expected 2, actual 0. Proof: red in the 02:30 Nightly UI run, green in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §21 | 2026-09-20 | 2026-09-27 |
| `UI.LaunchTests.LockedFileReportsLocked` (`locked-file-null`) | xUnit `Assert.NotNull`: the locked-file report never surfaced. Proof: red in the 02:30 Nightly UI run, green in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §4 | 2026-09-20 | 2026-09-27 |
| `UI.LockedResidueTests.DirtyLockedBufferStaysOutOfSessionAndRestoresAsGhost` (`locked-ghost-zero-tabs`) | xUnit `Assert.Equal` tab-count: expected 2, actual 0. Proof: red in the 02:30 Nightly UI run, green in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §30 | 2026-09-20 | 2026-09-27 |
| `UI.ReloadTests.DirtyKeepPreservesEdits` (`dirty-keep-null`) | xUnit `Assert.NotNull`. Proof: red in the 02:30 Nightly UI run, green in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §21 | 2026-09-20 | 2026-09-27 |
| `UI.DirtyPromptTests.WindowCloseWithDirtyTabsIsSilentAndRestores` (`dirty-close-com-timeout`) | `COMException 0x80131505` UIA timeout in the window-close drive; the Run A gate primary=1 is likely this test's window (same leg, dirty-tab title, not pid-proven). Proof: green twice in the 02:30 run (solution plus UI repeat), red in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: UIA stall under machine load. | 2026-09-20 | D01 T01 §7 | 2026-09-20 | 2026-09-27 |
| `UI.SessionRestoreTests.QuitAndRelaunchRestoresTabsContentsAndCarets` (`quit-relaunch-mismatch`) | xUnit `Assert.Equal` on restored contents/carets: expected 11, actual 5. Proof: green in the 02:30 collection, red in the governed re-run, test-identical trees (counts quoted in `docs/reviews/00-workspace/D00-T02-s9.md`). Likely cause: awake-operator interference or machine load during the night window. | 2026-09-20 | D01 T01 §6 | 2026-09-20 | 2026-09-27 |

## Fix-or-remove window

A quarantined test owes a fix or a removal decision within 7 calendar days of quarantine. Day 3 without progress, the owner posts a status note in the section they are working; day 7 with neither a fix nor a removal decision, the maintainer removes the test and records the decision as overdue-removal with the owner named. The window is per test, not per suite: each row carries its own due date.

## Removal decisions

Deleting a test without a recorded decision fails review. Every removed test gets a row here before its deletion commit lands, and reviewers check the diff for test deletions against this log.

| Test | Decision | Rationale | Date | By |
| ---- | -------- | --------- | ---- | -- |
| `Unit.DeliberatelyFlakyProbe` | removed | Deliberate §5 checkpoint probe: proven flaky (red then green, same binary), quarantined by this procedure with the suite green, then removed as designed. | 2026-09-14 | §5 implementation |
| `UI.StubWindowLaunchesShowsTitleAndCloses` | removed | D01 T01 §1 graduated the stub to the shell: the stub title it asserted no longer exists, and `MainWindowTests` covers launch, title, regions, and close. | 2026-09-14 | §1 implementation |
