# Soak and Quarantine Procedure

UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks. This procedure is the only sanctioned path for a flaky test: soak to find flakes, quarantine to contain them, a window to fix or remove them, and a record so nothing vanishes silently. A retry loop that hides a flake is never a substitute: retries make red green without evidence, while quarantine keeps the failure visible and owned.

## Nightly soak

Soak runs locally, usually as an unattended bedtime run: the full suite for the host OS plus five extra repetitions of the flake-prone suites (UI and Protocol), all with `trx` loggers. The CI `soak` workflow was retired on 2026-09-14; the table below shows the local command shape per OS.

| Host | Command |
| --- | ----- |
| Windows | `.tools\dotnet-win-x64\dotnet.exe test src/ScratchPad.slnx --logger trx`, then the UI and Protocol suites x5 |
| Linux | `.tools/dotnet-linux-x64/dotnet test src/Notepad.Neutral.slnf --logger trx`, then the Protocol suite x5 |

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
| `UI.AppIconTests.WindowChromeIconMatchesAsset` (`chrome-icon-uia-timeout`) | `System.TimeoutException: UIA Timeout` (inner COMException 0x80131505) attaching to the launched app. Proof: commit `c07b2c6` red on run 35234746568 attempt 1, green on the `--failed` rerun of the same commit (quoted in `docs/reviews/00-workspace/D00-T02-s7.md`). Likely cause: slow-runner UIA stall. | 2026-09-17 | D01 T01 §11 | 2026-09-17 | 2026-09-24 |
| `UI.LaunchTests.MissingFileOfferYesBindsTabAndSaveCreates` (`missing-offer-dialog-null`) | xUnit `Assert.NotNull` on the missing-file offer dialog in `WaitForDialog`: the dialog never appeared. Proof: commit `c07b2c6` red on run 35234746568 attempt 1, green on the `--failed` rerun of the same commit (quoted in `docs/reviews/00-workspace/D00-T02-s7.md`). Likely cause: slow-runner dialog delay. | 2026-09-17 | D01 T01 §8 | 2026-09-17 | 2026-09-24 |

## Fix-or-remove window

A quarantined test owes a fix or a removal decision within 7 calendar days of quarantine. Day 3 without progress, the owner posts a status note in the section they are working; day 7 with neither a fix nor a removal decision, the maintainer removes the test and records the decision as overdue-removal with the owner named. The window is per test, not per suite: each row carries its own due date.

## Removal decisions

Deleting a test without a recorded decision fails review. Every removed test gets a row here before its deletion commit lands, and reviewers check the diff for test deletions against this log.

| Test | Decision | Rationale | Date | By |
| ---- | -------- | --------- | ---- | -- |
| `Unit.DeliberatelyFlakyProbe` | removed | Deliberate §5 checkpoint probe: proven flaky (red then green, same binary), quarantined by this procedure with the suite green, then removed as designed. | 2026-09-14 | §5 implementation |
| `UI.StubWindowLaunchesShowsTitleAndCloses` | removed | D01 T01 §1 graduated the stub to the shell: the stub title it asserted no longer exists, and `MainWindowTests` covers launch, title, regions, and close. | 2026-09-14 | §1 implementation |
