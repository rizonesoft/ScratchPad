# Testing

Unit, smoke, UI-automation, and protocol tests each have a harness under `tests/`, and one `dotnet test` run executes every suite the host OS supports: `dotnet test src/Notepad.Neutral.slnf` on Linux, `dotnet test src/ScratchPad.slnx` on Windows.

## Framework

xUnit v2 with the VSTest runner: `Microsoft.NET.Test.Sdk` 17.14.1, `xunit` 2.9.3, `xunit.runner.visualstudio` 2.8.2, pinned per project with lockfiles. Every test project targets `net10.0` and references only neutral libraries, so the suites run on Linux; Windows-only coverage comes from the UI suite driving the real binary.

xUnit v3 with the Microsoft Testing Platform runner was evaluated twice and ships nowhere: T01 §5 proved zero-test discovery on our project and xUnit's own template across many configurations, and the T02 §1 re-evaluation reproduced it on the current vendor `xunit3` template (`xunit.v3.mtp-v2` 4.0.1) retargeted to `net10.0`, where a real `[Fact]` reports `Zero tests ran` with exit code 5. Re-evaluate only when a new v3 or template release claims the discovery path fixed.

## Suites

`tests/Smoke/` holds the one wiring test that proves the harness works; `tests/Unit/` holds unit tests over the neutral libraries, starting with the framework-choice tests. `tests/UI/` drives the stub window under FlaUI (launch, title assert, close, with a failure screenshot); the ACP loopback fixture (T02 §4) arrives with its section. Test-only helpers shared between suites live under `tests/Common/` per its README.

## Commands

Run everything for the host OS with the `dotnet test` commands above. Run one suite with `dotnet test tests/Unit` (or `tests/Smoke`, `tests/UI`). Filter within a run with `--filter`, for example `dotnet test <solution> --filter Smoke`. Test output uses the default console logger; anything written under `TestResults/` is gitignored.

## Golden captures

`resources/baseline/` holds stock Notepad reference captures plus goldens of our own surfaces at canonical size; `tests/UI` compares fresh captures against them under the committed `tolerance.json` policy. Captures come from `tools/CaptureBaseline`; the refresh procedure in `resources/baseline/README.md` governs re-capturing after intentional changes.

## CI and quarantine

CI runs the same `dotnet test` commands on every push, so a red suite fails the run. Flaky tests are quarantined by procedure (T02 §5), never deleted or silently skipped.

## Automation hosts

The Conclave-PC Hyper-V VM is the shared UI-automation host (agent SSH plus RDP; connection details in the Conclave vault under `Conclave-PC VM`). Its policy refuses low-level mouse hooks, so the app runs there without middle-click-to-close and `MiddleClickClosesTheTabUnderTheCursor` skips with the Win32 error in the skip reason; every other UI test runs identically, and CI plus dev boxes still run the full suite with no skips.

## CI telemetry

Every `build` run on `main` is measured for lag (wall plus step split; queue time runs about 5s) and quality (per-suite counts against the local run, conclusion). CI runs the identical suites with the identical tests: no test carries an xUnit `Skip`, and the Windows job runs the full solution including the UI suite's real-input drives (middle-click through `mouse_event`, cursor-travel drag, right-clicks, `SendInput` keyboard) on the runner's interactive session. Counts match the local runs exactly everywhere below; the Linux job holds steady near 35s. CI renders 800x600 dark at 100% DPI, so DPI-sensitive coverage still needs a local run (§3 phase-log note). Method: `gh run view <id> --json jobs` for the step split, `gh run view <id> --log | grep 'Passed!'` for counts. Each telemetry batch records every run since the previous batch; the batch's own run lands in the next batch.

| Run | Windows wall | Provision | Build | Test | UI (win) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 34813967613 | 11m32s | 9m38s | 50s | 38s | 9/9 | §1 stamp run |
| 34814832086 | 10m35s | 8m34s | 56s | 40s | 9/9 | success |
| 34815770936 | 12m03s | 9m23s | 76s | 59s | red | `Test solution` failed: cold-start launch flake |
| 34816231797 | 12m25s | 10m23s | 56s | 38s | 9/9 | §2 stamp run |
| 34817277397 | 10m32s | 8m15s | 74s | 30s | 9/9 | success |
| 34828749529 | 13m05s | 10m25s | 57s | 68s | 18/18 | §3 stamp run, pre-cache workflow; real-mouse drives green |
| 34829833626 attempt 1 | 9m41s | 6m35s | 69s | 92s | 17/18 | first run with cache steps; all misses, nothing saved yet; ContextMenu dialog assert red |
| 34829833626 rerun | 12m38s | 9m33s | 62s | 93s | 17/18 | cache missed again: post save steps skip on a failed job (fixed with `save-always`); same ContextMenu assert |
