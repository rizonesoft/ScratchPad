# Section gates

Read the "Testing policy (operator decision 2026-10-14)" section of `docs/testing.md`. If this card and that file disagree, the file wins.

Test what the section implemented, nothing else, and never take the operator's screen. Quote the exit code, the failed count, and the skipped count. Leave the full log under `build/`.

The whole gate:

1. The build is clean.
2. The section's tests pass: the tests it added or changed plus the existing tests of the code it touched, as one `--filter` over those classes. Unit and Protocol tests run as they are. UI tests run focus-free:

   ```powershell
   dotnet test tests/UI --filter "(FullyQualifiedName~<Class1>|FullyQualifiedName~<Class2>)&Category!=Interactive&Category!=Primary" -e SCRATCHPAD_BACKGROUND=1
   ```

   The `-e` flag is load-bearing: it is the only channel that reaches the app through the test host, and it keeps every window off the primary and never activated.
3. `validate` is clean.

Not part of a section gate: the whole UI suite, the Primary set, Interactive runs, and the ForegroundLog proof. Run `Bin/ForegroundLog/Debug/ForegroundLog.exe <seconds> <logpath>` beside step 2 only when the section changes focus or window placement.

Interactive and Primary tests the section owns are written and compiled with it, then recorded on its `Night-owed:` line (format in `todo/README.md`). They never hold the flip. Do not set `SCRATCHPAD_INTERACTIVE_FORCE` and do not register any scheduled task: the operator runs the foreground legs by hand when a phase, file, or release closes.

The full suite belongs to phase, file, and release close (`process-phase` closeout, `process-todo-file`), never to a section.

The UI suite drives real windows and native dialogs, so two machine settings must match the golden-capture environment: dark app theme (`AppsUseLightTheme` 0, else goldens mismatch) and visible file extensions (`HideFileExt` 0, else dialog prefill reads, file-list names, and save routing shift and 6 MenuBarTests fail). Verify with `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme` and `(Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt`.
