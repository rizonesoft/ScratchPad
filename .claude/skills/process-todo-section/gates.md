# Section gates

Read the "Testing policy (operator decision 2026-10-14)" section of `docs/testing.md`. If this card and that file disagree, the file wins.

Test everything the section implemented and nothing else, and look at it: a feature the user sees is checked visually against Notepad. Take the operator's screen only for the feature's own foreground tests and its capture, which last seconds. Quote the exit code, the failed count, and the skipped count. Leave the full log under `build/`.

The whole gate:

1. The build is clean.
2. The section's tests pass: the tests it added or changed plus the existing tests of the code it touched, as one `--filter` over those classes. Unit and Protocol tests run as they are. UI tests run focus-free:

   ```powershell
   dotnet test tests/UI --filter "(FullyQualifiedName~<Class1>|FullyQualifiedName~<Class2>)&Category!=Interactive&Category!=Primary" -e SCRATCHPAD_BACKGROUND=1
   ```

   The `-e` flag is load-bearing: it is the only channel that reaches the app through the test host, and it keeps every window off the primary and never activated.
3. The feature's own Primary and Interactive tests pass, scoped by the same filter (the operator accepted this scoped interruption on 2026-10-14):

   ```powershell
   dotnet test tests/UI --filter "(<same classes>)&Category=Primary" -e SCRATCHPAD_BACKGROUND=1
   dotnet test tests/UI --filter "(<same classes>)&Category=Interactive" -e SCRATCHPAD_INTERACTIVE_FORCE=1
   ```

   Skip a step only when the section owns no test in that category.
4. Visual check, for every section that changes something the user sees. Capture the feature in the built app and look at it beside real Notepad. The default route is the feature's UI test: it seeds a fresh profile (`UiLaunch.SeedSettings`, `WhenStarts = Fresh`), drives the feature to the state the user sees, and saves `UiCapture.PrintCapture(window)` as a PNG under `build/visual/<section-id>/`, focus-free. For a fresh-launch frame only, `tools/CaptureBaseline` also works; it launches against the operator's live profile, so pass an absolute exe path and reject a frame that shows restored content:

   ```powershell
   dotnet run --project tools/CaptureBaseline -- stub (Resolve-Path Bin/ScratchPad/Debug/win-x64/ScratchPad.exe).Path build/visual/<section-id> --foreground [--element <Name>]
   ```

   Open the capture and the matching stock reference under `resources/baseline/stock/` (capture a missing one with `-- notepad`, never assume it), compare them by eye, and record the verdict in the commit body: the capture paths, then `matches Notepad` or each difference with its fix or recorded reason. A difference that is not intended is a red gate. When the surface has an `app/` golden, its `GoldenComparisonTests` case belongs to step 2.
5. `validate` is clean.

Not part of a section gate: the whole UI suite, other features' Primary or Interactive tests, and the ForegroundLog proof. Run `Bin/ForegroundLog/Debug/ForegroundLog.exe <seconds> <logpath>` beside step 2 only when the section changes focus or window placement.

Write a feature's tests focus-free (UIA patterns) wherever possible; a physical key, drag, or cursor test is the exception. Only when the host cannot run step 3 or 4 (locked session, no display) record those tests on a `Night-owed:` line (format in `todo/README.md`) and say so in the report. Never use `SCRATCHPAD_INTERACTIVE_FORCE` with a filter wider than the section's own classes, and never register a scheduled task.

The full suite belongs to phase, file, and release close (`process-phase` closeout, `process-todo-file`), never to a section.

The UI suite drives real windows and native dialogs, so two machine settings must match the golden-capture environment: dark app theme (`AppsUseLightTheme` 0, else goldens mismatch) and visible file extensions (`HideFileExt` 0, else dialog prefill reads, file-list names, and save routing shift and 6 MenuBarTests fail). Verify with `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme` and `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt`.
