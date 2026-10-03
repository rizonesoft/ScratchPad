---
schema_version: 1
id: ci-soak
domain: 00-workspace
status: draft
title: "TODO-13 -- CI Soak"
depends_on: []
track: W0
---

# TODO-13 -- CI Soak

> **Goal:** The scheduled `soak` workflow is green and truthful: it builds the gate tools its tests launch, runs a population and environment that are an explicit decision rather than an accident, says in `docs/soak-and-quarantine.md` exactly what it runs, and every test it cannot pass on a hosted runner is fixed, fenced with a written capability reason, or quarantined through the sanctioned procedure, never silently red.

> [!IMPORTANT]
> **Current state:** `.github/workflows/soak.yml` (cron `17 3 * * *`, `windows-2025`, 60-minute limit) builds only `src/ScratchPad.slnx`, then runs `dotnet test src/ScratchPad.slnx` unfiltered with no `-e SCRATCHPAD_BACKGROUND=1`, then repeats UI and Protocol five times. `tools/ForegroundLog` and `tools/JobControl` belong to no solution (the local nightly builds them itself, `tools/nightly.ps1` around `$GateExe`), so tests that launch `Bin\ForegroundLog\Debug\ForegroundLog.exe` fail on the runner. Soak was last green on 2026-09-14 (dispatch runs 34808621885 and 34809456063); every scheduled run since 2026-09-15 is red. Since 2026-09-26 the same seven UI tests fail (run 37112221697 on 12b662c: Failed 7, Passed 323, Skipped 69): `GateAttributionTests.ReusedPidIsNeverAttributedToTheAppAndLinesNameTheExecutable` (gate executable missing), `GateCalibrationTests.NoPlantKeepsTheGateGreen` (gate exit 1), `LaunchTests.TwentyBirthsAndTeardownsStayWithinBudget`, `LaunchTests.WindowBirthLeavesOtherWindowsHelpersInPlace`, and `LaunchTests.FirstBirthPreexistingSetMatchesAnOutsideObservation` (no sweep or delayed-pass line in the runner's `scratchpad-sweep-*.log`), `LaunchTests.HelperBornAfterTheSweepIsParkedByTheDelayedPass` (the late-helper seam planted nothing), and `OffScreenBirthTests.BackgroundRestoreLandsOnTheSuiteDisplay` (Left 124 outside 1916-1932; its comment says the reads agree only on the pinned 100%-secondary topology). They came from D00 T02 §18 (a922f86), §26 (95fdf99), §41 (7cda042), §48 (158b528), and §49 (d3d405c), each green locally at its stamp with the gate built. `docs/soak-and-quarantine.md` line 7 says the CI soak "repeats the same shape nightly", which soak.yml does not, and its soak log ends at 2026-09-14. `build.yml` runs no tests by operator decision 2026-09-17.

## Inputs

- [`.github/workflows/soak.yml`](../../.github/workflows/soak.yml) -- the workflow both sections change
- [`docs/soak-and-quarantine.md`](../../docs/soak-and-quarantine.md) -- the soak and quarantine procedure §1 corrects and §2 follows (quarantine rows, soak log)
- [`docs/testing.md`](../../docs/testing.md) -- the governed Run A shape (filter plus background env) §1 aligns to
- [`tools/nightly.ps1`](../../tools/nightly.ps1) -- how the local nightly builds the gate tools, the pattern §1 mirrors
- [`tests/UI/HookFactAttribute.cs`](../../tests/UI/HookFactAttribute.cs), [`tests/UI/PrinterFactAttribute.cs`](../../tests/UI/PrinterFactAttribute.cs) -- the capability-skip pattern §2 fences with
- -> XREF: D00 T02 §5 -- shipped the soak workflow and the procedure doc this file brings back to green and truth.
- -> XREF: D00 T02 §16 -- owns the local timer-fired night (including its `gh` preflight); this file owns the hosted soak, and both are the regression evidence the plan reads.
- -> SOURCE: reconcile-2026-10-03-soak-red (operator reconciliation 2026-10-03; soak runs 34948541619 through 37112221697)

## Outcome

- A scheduled soak run builds `ForegroundLog` and `JobControl`, runs the decided population with the decided environment, and concludes success on two consecutive scheduled occurrences.
- `docs/soak-and-quarantine.md` states the CI soak's real shape and its differences from the local nightly, and its soak log records the red streak and the first green.
- None of the seven failing tests is deleted; each reads fixed, fenced with a written capability reason, or quarantined with a row.

**Adjacency:** all=not-applicable (CI workflow, test-harness capability gates, and operator docs; nothing ships in the app, stores user data, or reaches app users)

**Adjacency rationale:** The work changes a GitHub Actions workflow, at most test attributes or harness code under `tests/UI/`, and the soak procedure doc. The app binary, its settings store, and every user-facing surface are untouched, and the tests' own behavior contracts stay owned by the sections that wrote them, so no adjacency key applies.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Gate tools built and the governed population in CI soak | D00 T02 §5 |  [ ]   |
|   2   |   §2    | Runner failures resolved and soak green | §1 |  [ ]   |

---

## 1. Gate Tools Built and the Governed Population in CI Soak

Why this section exists: soak.yml builds only the solution, so every test that launches the ForegroundLog gate fails on the runner with "gate executable missing", and its unfiltered, background-less test step runs a population and environment the governed local run (`docs/testing.md` Run A) never runs, so a red soak says nothing about the gated suite. This section makes the runner able to run what the suite needs and makes the population a recorded decision. It must not weaken any test: fencing and quarantine belong to §2, under the procedure.

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §5 -- the workflow and procedure doc this section corrects.

- [ ] `soak.yml` builds `tools/ForegroundLog/ForegroundLog.csproj` and `tools/JobControl/JobControl.csproj` after the solution build, and fails the job naming the missing file when `Bin/ForegroundLog/Debug/ForegroundLog.exe` or the JobControl exe is absent afterwards. Done when: a dispatched soak run shows both build steps green and `GateAttributionTests.ReusedPidIsNeverAttributedToTheAppAndLinesNameTheExecutable` passes in it. Cheaper substitute: skipping gate tests in CI.
- [ ] The soak's population and environment are an explicit decision, recorded with its cost of changing: by default the test and repeat steps run per test project with the governed Run A filter `Category!=Interactive&Category!=Primary` and `-e SCRATCHPAD_BACKGROUND=1` (as `docs/testing.md` Run A), because Interactive and Primary tests need a foreground and a primary-display contract a hosted runner does not prove; cost of changing: running them in CI needs a runner display contract and an owner for its proofs. Done when: soak.yml's test and repeat steps carry the filter and environment, and the dispatched run's trx files contain no Interactive or Primary test execution.
- [ ] `docs/soak-and-quarantine.md` states the CI soak's real shape (gate tools built, filter, background environment, five repeats of UI and Protocol, no ForegroundLog run alongside) and how it differs from the local nightly, replacing the "repeats the same shape nightly" claim at line 7. Done when: every step the paragraph names matches a step in soak.yml on the candidate.
- [ ] Commit: `"workspace: build the gate tools and run the governed population in CI soak"`

**Test checkpoint:** Dispatch the soak workflow on the candidate (`gh workflow run soak --ref main`) and quote from its log the two gate-tool build steps green, `GateAttributionTests.ReusedPidIsNeverAttributedToTheAppAndLinesNameTheExecutable` passed, and the UI summary line; quote a trx query showing zero tests with Category Interactive or Primary executed. Fails if the gate exe is missing, the attribution test fails, or a fenced category runs.

## 2. Runner Failures Resolved and Soak Green

Why this section exists: after §1, the six remaining failures (`GateCalibrationTests.NoPlantKeepsTheGateGreen`, the three sweep-log `LaunchTests`, `LaunchTests.HelperBornAfterTheSweepIsParkedByTheDelayedPass`, and `OffScreenBirthTests.BackgroundRestoreLandsOnTheSuiteDisplay`) passed locally at their stamps, so each is either a runner-environment limit (display topology, desktop session, hook delivery) or a product defect the runner exposes. Neither may be resolved by deleting or silently skipping the test. This section diagnoses each from runner evidence, then fixes it, fences it with a written capability reason, quarantines it under the procedure, or files a product defect with an owner.

**Needs:** Windows host (build/test)

- [ ] On failure, soak.yml uploads the runner's `scratchpad-sweep-*.log` files from the temp directory and a display-topology dump (virtual screen bounds, each monitor's bounds and DPI, the primary) as a named artifact. Done when: a failing dispatched run's artifact contains both, quoted by name.
- [ ] Each of the six failures has a recorded diagnosis in this section's review record: runner cause or product cause, with the artifact line that shows it. Done when: six diagnoses read, each quoting its evidence.
- [ ] Each runner-cause failure is fixed in the test or harness, or fenced with a capability attribute in the `HookFactAttribute` pattern whose skip reason names the missing capability (for example a pinned 100%-secondary topology), with a quarantine row in `docs/soak-and-quarantine.md` only for a genuine flake under that procedure; no test is deleted or skipped without its written reason. Done when: each of the six reads fixed, fenced with its capability reason, or quarantined with its row, and the local Run A still executes every fenced test.
- [ ] Each product-cause failure files through `add-todo` with an owner and dependency instead of being fenced. Done when: each such failure names its filed section, or the review record states that none was found.
- [ ] The soak log in `docs/soak-and-quarantine.md` gains one row summarizing the 2026-09-15 to green red streak with its causes, and one row per green scheduled run proving this section. Done when: the rows read with run links.
- [ ] Commit: `"workspace: resolve the runner-only soak failures"`

**Test checkpoint:** Two consecutive scheduled soak runs on the candidate or its descendants conclude success, quoted with their run IDs and UI summary lines, and every one of the original seven tests reads passed, fenced with its capability reason, or quarantined with its row in those runs' trx. Fails if any of the seven is skipped without a written reason or quarantine row, or if either run is red.

## Verification

- [ ] Two consecutive scheduled soak runs green, quoted
- [ ] `docs/soak-and-quarantine.md` matches soak.yml
- [ ] `python3 scripts/todo-graph.py validate` clean
