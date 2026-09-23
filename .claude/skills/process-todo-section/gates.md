# Section gates

Read `docs/testing.md` for what each run means. If this card and that file disagree, the file wins.

Daytime proof never takes the foreground. Quote the exit code, the failed count, the skipped count, and the foreground-log verdict. Leave the full log under `build/`.

Focus-free default (off the primary, never activated):

```powershell
dotnet test tests/UI --filter "Category!=Interactive&Category!=Primary" -e SCRATCHPAD_BACKGROUND=1
```

Run `Bin/ForegroundLog/Debug/ForegroundLog.exe <seconds> <logpath>` beside it. Green means the suite passed with zero failures and the log flagged zero foreground holds and zero windows resting on the primary.

Focus-free placement (visible on the primary, still never activated):

```powershell
dotnet test tests/UI --filter "Category=Primary" -e SCRATCHPAD_BACKGROUND=1
```

Same foreground log, with `--expect-primary`. Green means the suite passed, zero foreground holds, and at least one window resting on the primary.

Interactive, foreground, cursor, and real keys. The suite itself skips outside 02:00-06:50 local:

```powershell
dotnet test tests/UI --filter "Category=Interactive"
```

Outside that window, record the skips as `Night-owed` and stamp. Do not wait for 02:00. Do not set `SCRATCHPAD_INTERACTIVE_FORCE` unless the operator accepted that interruption in this turn. The collector is the existing `\ScratchPad\Nightly UI` task at 02:30 (`tools\NightlySupervisor.ps1`). Do not register a second nightly task.

Affected suites during iteration use `dotnet test --filter`, not the whole solution. The file-level full suite belongs to `process-todo-file`.
