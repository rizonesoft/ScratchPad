# Section gates

Read the "Testing policy (operator decision 2026-10-14)" section of `docs/testing.md`. If this card and that file disagree, the file wins.

Test everything the section implemented and nothing else. The design is accepted as it stands (`docs/design-contract.md`): a visible change gets one capture and a look for defects, not a comparison with Notepad. Take the operator's screen only for the feature's own foreground tests, which last seconds. Quote the exit code, the failed count, and the skipped count. Leave the full log under `build/`.

The whole gate:

1. The build is clean.
2. The section's tests pass: the tests it added or changed plus the existing tests of the code it touched, as one `--filter` over those classes. Unit and Protocol tests run as they are. UI tests run focus-free:

   ```powershell
   dotnet test tests/UI --filter "(FullyQualifiedName~<Class1>|FullyQualifiedName~<Class2>)&Category!=Interactive&Category!=Primary" -e SCRATCHPAD_BACKGROUND=1
   ```

   Add `|Visual=Golden` inside the parentheses only when the section changes the main window, the tab strip or the settings page: those three surfaces carry the goldens. Every other section leaves the goldens to the phase-close run.

   The `-e` flag is load-bearing: it is the only channel that reaches the app through the test host, and it keeps every window off the primary and never activated.
3. The feature's own Primary and Interactive tests pass, scoped by the same filter (the operator accepted this scoped interruption on 2026-10-14):

   ```powershell
   dotnet test tests/UI --filter "(<same classes>)&Category=Primary" -e SCRATCHPAD_BACKGROUND=1
   dotnet test tests/UI --filter "(<same classes>)&Category=Interactive" -e SCRATCHPAD_INTERACTIVE_FORCE=1
   ```

   Skip a step only when the section owns no test in that category. The Interactive run first waits until the operator has not touched the keyboard or mouse for 60 seconds (`SCRATCHPAD_IDLE_SECONDS`, default 60; it gives up after `SCRATCHPAD_IDLE_MAX_WAIT_SECONDS`, default 900), so it never fights the operator's typing. If the operator stays active, the fenced tests skip as `Operator active`; say so in the `Verified:` evidence and the phase-close run covers them. Never lower the idle settings to get past an active operator.
4. Visual check, for a section that changes something the user sees. Save one focus-free capture of the changed surface (`UiCapture.CaptureState` or `UiCapture.PrintCapture` from the feature's UI test, written under `build/visual/`), open it, and look for defects: clipping, misalignment, a wrong theme color, a missing control. Fix what you find. Do not compare it with stock Notepad and do not record a verdict in the commit. Add a golden only for a new major surface or when the operator asks; run a new golden three times before committing it, and refresh an existing one by the procedure in `resources/baseline/README.md`.
5. `validate` is clean.

Not part of a section gate: the whole UI suite, other features' Primary or Interactive tests, and the ForegroundLog proof. Run `Bin/ForegroundLog/Debug/ForegroundLog.exe <seconds> <logpath>` beside step 2 only when the section changes focus or window placement.

Write a feature's tests focus-free (UIA patterns) wherever possible; a physical key, drag, or cursor test is the exception. Only when the host cannot run step 3 (locked session, no display) leave those tests to the phase-close run and say so in the `Verified:` evidence and the report. Never use `SCRATCHPAD_INTERACTIVE_FORCE` with a filter wider than the section's own classes, and never register a scheduled task.

The full suite belongs to phase, file, and release close (`process-phase` closeout), never to a section.

The UI suite drives real windows and native dialogs, so two machine settings must match the golden-capture environment: dark app theme (`AppsUseLightTheme` 0, else goldens mismatch) and visible file extensions (`HideFileExt` 0, else dialog prefill reads, file-list names, and save routing shift and 6 MenuBarTests fail). Verify with `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme` and `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt`.
