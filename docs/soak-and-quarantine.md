# Soak and Quarantine Procedure

UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks. This procedure is the only sanctioned path for a flaky test: soak to find flakes, quarantine to contain them, a window to fix or remove them, and a record so nothing vanishes silently. A retry loop that hides a flake is never a substitute: retries make red green without evidence, while quarantine keeps the failure visible and owned.

## Nightly soak

The `soak` workflow (`.github/workflows/soak.yml`) runs on schedule at 03:17 UTC and on manual dispatch. It runs the full suite on both OSes plus five extra repetitions of the flake-prone suites (UI and Protocol), all with `trx` loggers. Each job carries a timeout (45 min Linux, 60 min Windows); expected wall time is under 15 minutes per job.

| Job | Scope | Repeats |
| --- | ----- | ------- |
| soak-linux | `src/Notepad.Neutral.slnf`, full test | Protocol suite x5 |
| soak-windows | `src/IntelligentNotepad.slnx`, full test | UI suite x5, Protocol suite x5 |

Results go to the workflow run page: the per-step logs plus the `soak-results-linux` and `soak-results-windows` artifacts (trx files, default retention), with `golden-failures-soak` uploaded on UI failure. Runs are linked from this doc only when they catch a flake: a quarantine entry references the run that proved the flake, so the run history stays the log and this doc stays the index.

## Soak log

| Date | Run | Result |
| ---- | --- | ------ |
| 2026-09-14 | _first run link lands with the §5 stamp_ | _pending_ |

## Quarantine

A test that fails nondeterministically (red in one run, green in another, with no code change between) is quarantined, not deleted and not retried into silence:

1. Prove the flake: two runs of the same commit with different outcomes, or one soak run plus one local run disagreeing. Quote both.
2. Skip the test with xUnit `Skip` carrying the quarantine stamp: `[Fact(Skip = "QUARANTINED <date> <owner> <signature-id>")]`. The test stays compiled; the suite stays green; the skip reason names this doc entry.
3. Add the row to the quarantine list below. The failure signature is the stable part of the failure (exception type plus message shape, never timestamps or line heat).

A quarantined test keeps running nowhere until it is fixed (un-skipped with a passing soak behind it) or removed (with its decision recorded below).

## Quarantine list

| Test | Failure signature | First seen | Owner | Quarantined | Due |
| ---- | ----------------- | ---------- | ----- | ----------- | --- |
| _(empty)_ | | | | | |

## Fix-or-remove window

A quarantined test owes a fix or a removal decision within 7 calendar days of quarantine. Day 3 without progress, the owner posts a status note in the section they are working; day 7 with neither a fix nor a removal decision, the maintainer removes the test and records the decision as overdue-removal with the owner named. The window is per test, not per suite: each row carries its own due date.

## Removal decisions

Deleting a test without a recorded decision fails review. Every removed test gets a row here before its deletion commit lands, and reviewers check the diff for test deletions against this log.

| Test | Decision | Rationale | Date | By |
| ---- | -------- | --------- | ---- | -- |
| `Unit.DeliberatelyFlakyProbe` | removed | Deliberate §5 checkpoint probe: proven flaky (red then green, same binary), quarantined by this procedure with the suite green, then removed as designed. | 2026-09-14 | §5 implementation |
