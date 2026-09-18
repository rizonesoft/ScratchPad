# Testing

Unit, smoke, UI-automation, and protocol tests each have a harness under `tests/`, and one `dotnet test` run executes every suite the host OS supports: `dotnet test src/Notepad.Neutral.slnf` on Linux, `dotnet test src/ScratchPad.slnx` on Windows. The Windows run includes the fenced interactive UI tests (below), so it owns the foreground while it runs; the per-section gate is the default-filtered run, which never does.

## Framework

xUnit v2 with the VSTest runner: `Microsoft.NET.Test.Sdk` 17.14.1, `xunit` 2.9.3, `xunit.runner.visualstudio` 2.8.2, pinned per project with lockfiles. Every test project targets `net10.0` and references only neutral libraries, so the suites run on Linux; Windows-only coverage comes from the UI suite driving the real binary.

xUnit v3 with the Microsoft Testing Platform runner was evaluated twice and ships nowhere: T01 §5 proved zero-test discovery on our project and xUnit's own template across many configurations, and the T02 §1 re-evaluation reproduced it on the current vendor `xunit3` template (`xunit.v3.mtp-v2` 4.0.1) retargeted to `net10.0`, where a real `[Fact]` reports `Zero tests ran` with exit code 5. Re-evaluate only when a new v3 or template release claims the discovery path fixed.

## Suites

`tests/Smoke/` holds the one wiring test that proves the harness works; `tests/Unit/` holds unit tests over the neutral libraries, starting with the framework-choice tests. `tests/UI/` drives the stub window under FlaUI (launch, title assert, close, with a failure screenshot); the ACP loopback fixture (T02 §4) arrives with its section. Test-only helpers shared between suites live under `tests/Common/` per its README.

## Commands

Run everything for the host OS with the `dotnet test` commands above. Run one suite with `dotnet test tests/Unit` (or `tests/Smoke`, `tests/UI`). Filter within a run with `--filter`, for example `dotnet test <solution> --filter Smoke`. Test output uses the default console logger; anything written under `TestResults/` is gitignored.

## UI suite preconditions

The UI suite drives real windows and native dialogs, so two machine settings must match the golden-capture environment: dark app theme (`AppsUseLightTheme` 0, else goldens mismatch) and visible file extensions (`HideFileExt` 0, else dialog prefill reads, file-list names, and save routing shift and 6 MenuBarTests fail). Verify with `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme` and `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt`. (CI set both before its test step until 2026-09-17, when UI tests left CI; the settings still gate local runs.)

## Uninterrupted gate (D00 T02 §8)

Default run, background-safe: `dotnet test tests/UI --filter "Category!=Interactive" -e SCRATCHPAD_BACKGROUND=1`. The `-e` flag is load-bearing: it is the only channel that reaches the app through the test host (shell exports do not propagate, measured 2026-09-17), and it makes every window start minimized. The suite then moves each window to the secondary monitor (off-screen when the box has one) and drives it through UIA patterns: visible there but never activated, so no foreground and no cursor. Fenced run, visibly on demand: `dotnet test tests/UI --filter "Category=Interactive"` with no `-e` flag. Fenced tests own the foreground and the cursor (physical keys, drags, dialog clicks, geometry asserts), so run them when the interruption is yours to spend.

Foreground proof rides alongside the default run: `Bin/ForegroundLog/Debug/net10.0-windows10.0.19041.0/ForegroundLog.exe <seconds> <logpath>` polls the foreground window and exits 1 naming the run red if ScratchPad ever held it. Green means the default suite passed with zero failures AND the log flagged zero foreground holds; a passing suite with a flagged log is a gate failure (some test activated a window). The fenced set is green when it passes visibly. The input audit behind the split lives in `docs/ui-input-audit.md`.

Quiet hours hard-gate the fenced set: every `Category=Interactive` test runs under `[InteractiveFact]`, which reports Skipped outside the foreground window (02:00-06:50 local, operator schedule 2026-09-17), so even an unfiltered daytime run cannot interrupt. `SCRATCHPAD_INTERACTIVE_WINDOW` (`HH:mm-HH:mm`) moves the window and `SCRATCHPAD_INTERACTIVE_FORCE=1` runs regardless for an explicitly accepted interruption; unparseable config fails closed to skip. A reflection guard (`QuietHoursTests.EveryGatedTestCarriesTheInteractiveTrait`) fails any gated test missing its trait. A daytime full-solution run reads green-plus-skipped, never fully proven; only the nighttime run executes the fenced set.

## Golden captures

`resources/baseline/` holds stock Notepad reference captures plus goldens of our own surfaces at canonical size; `tests/UI` compares fresh captures against them under the committed `tolerance.json` policy. Captures come from `tools/CaptureBaseline`; the refresh procedure in `resources/baseline/README.md` governs re-capturing after intentional changes.

## Quarantine

Flaky tests are quarantined by procedure (`docs/soak-and-quarantine.md`, T02 §5), never deleted or silently skipped. CI telemetry and VM-based runs were retired on 2026-09-14; UI tests left CI on 2026-09-17 (CI gates build plus launch smoke only), so all suites run locally on the dev box, with the UI suite driving the real binary on the interactive session.
