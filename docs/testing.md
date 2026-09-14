# Testing

Unit, smoke, UI-automation, and protocol tests each have a harness under `tests/`, and one `dotnet test` run executes every suite the host OS supports: `dotnet test src/Notepad.Neutral.slnf` on Linux, `dotnet test src/IntelligentNotepad.slnx` on Windows.

## Framework

xUnit v2 with the VSTest runner: `Microsoft.NET.Test.Sdk` 17.14.1, `xunit` 2.9.3, `xunit.runner.visualstudio` 2.8.2, pinned per project with lockfiles. Every test project targets `net10.0` and references only neutral libraries, so the suites run on Linux; Windows-only coverage comes from the UI suite driving the real binary.

xUnit v3 with the Microsoft Testing Platform runner was evaluated twice and ships nowhere: T01 §5 proved zero-test discovery on our project and xUnit's own template across many configurations, and the T02 §1 re-evaluation reproduced it on the current vendor `xunit3` template (`xunit.v3.mtp-v2` 4.0.1) retargeted to `net10.0`, where a real `[Fact]` reports `Zero tests ran` with exit code 5. Re-evaluate only when a new v3 or template release claims the discovery path fixed.

## Suites

`tests/Smoke/` holds the one wiring test that proves the harness works; `tests/Unit/` holds unit tests over the neutral libraries, starting with the framework-choice tests. `tests/UI/` drives the stub window under FlaUI (launch, title assert, close, with a failure screenshot); the ACP loopback fixture (T02 §4) arrives with its section. Test-only helpers shared between suites live under `tests/Common/` per its README.

## Commands

Run everything for the host OS with the `dotnet test` commands above. Run one suite with `dotnet test tests/Unit` (or `tests/Smoke`, `tests/UI`). Filter within a run with `--filter`, for example `dotnet test <solution> --filter Smoke`. Test output uses the default console logger; anything written under `TestResults/` is gitignored.

## CI and quarantine

CI runs the same `dotnet test` commands on every push, so a red suite fails the run. Flaky tests are quarantined by procedure (T02 §5), never deleted or silently skipped.
