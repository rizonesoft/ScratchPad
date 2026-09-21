# Parser fixture suite for tools/NightlyParse.ps1 (D00 T02 §15 PR22).
# Self-contained: builds fixture trx plus transcript files under TEMP,
# exercises the exact shipped functions, exits nonzero on any failure.
# Covers assemblies, duplicate names, malformed trx, and every skip class.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}

$dir = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-parse-fixtures'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $dir

$trxXml = @'
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
<UnitTestResult testName="UI.OkTest" outcome="Passed" />
<UnitTestResult testName="UI.QuarantinedTest" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-20 D01-T01-S9 fixture-quarantine</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.HookTest" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: Low-level mouse hooks are unavailable on this host (Win32 error 5).</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.PrinterTest" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: No printers enumerated in this context (agent context is printer-blind); run where the spooler is visible.</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LegacyHookTest" outcome="NotExecuted"><Output><ErrorInfo><Message>Low-level mouse hooks are unavailable on this host (Win32 error 5).</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.BareSkip" outcome="NotExecuted"><Output><ErrorInfo><Message>TEMPORARY: unclassified skip</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.QuietSkip" outcome="NotExecuted"><Output><ErrorInfo><Message>Outside the quiet-hours window</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.FailedTest" outcome="Failed"><Output><ErrorInfo><Message>boom</Message></ErrorInfo></Output></UnitTestResult>
</Results></TestRun>
'@
$trx = Join-Path $dir 'fixture.trx'
$trxXml | Set-Content -Path $trx -Encoding UTF8

$logLines = @(
  'Passed!  - Failed:     1, Passed:    10, Skipped:     3, Total:    14, Duration: 1 s - UI.dll (net10.0)',
  'Failed!  - Failed:     2, Passed:     5, Skipped:     1, Total:     8, Duration: 2 s - Smoke.dll (net10.0)',
  '  Failed UI.FailedTest [12 ms]',
  '  Failed UI.OtherFail [3 ms]',
  '  Failed UI.OtherFail [4 ms]',
  '  Skipped UI.BareSkip [0 ms]',
  '  Skipped UI.BareSkip [0 ms]'
)
$log = Join-Path $dir 'fixture.log'
$logLines | Set-Content -Path $log -Encoding UTF8

$badTrx = Join-Path $dir 'truncated.trx'
'<TestRun><Results><UnitTestResult testName="UI.HalfWritt' | Set-Content -Path $badTrx -Encoding UTF8

# Assemblies: two rows parsed with per-assembly counts.
$rows = Get-TranscriptRows $log
Assert ($rows.Count -eq 2) 'two-assembly-rows' ("got $($rows.Count)")
Assert (($rows[0].Assembly -eq 'UI.dll') -and ($rows[0].Passed -eq 10) -and ($rows[0].Skipped -eq 3)) 'first-row-counts'
Assert (($rows[1].Assembly -eq 'Smoke.dll') -and ($rows[1].Failed -eq 2)) 'second-row-counts'

# Duplicate names: transcript failures plus skips dedupe by name.
$fails = Get-TranscriptFailures $log
Assert ((@($fails).Count -eq 2) -and ($fails -contains 'UI.FailedTest') -and ($fails -contains 'UI.OtherFail')) 'failure-dedupe' ($fails -join ',')
$skips = Get-TranscriptSkips $log
Assert ((@($skips).Count -eq 1) -and ($skips -contains 'UI.BareSkip')) 'skip-dedupe' ($skips -join ',')

# Malformed trx: reads as absent, never throws; enforcement fails
# closed (unproven), never green on an unclassifiable leg.
Assert ($null -eq (Get-TrxSummary $badTrx)) 'truncated-trx-null'
Assert ((Get-NonQuarantineSkips $badTrx).Ok -eq $false) 'truncated-enforcement-unproven'
Assert ((Get-NonQuarantineSkips (Join-Path $dir 'missing.trx')).Ok -eq $false) 'missing-enforcement-unproven'
Assert ($null -eq (Get-TrxSummary (Join-Path $dir 'missing.trx'))) 'missing-trx-null'

# Every skip class: quarantine plus capability (coded and legacy) pass;
# bare plus quiet-hours flag.
$enf = Get-NonQuarantineSkips $trx
$leaked = @($enf.Names)
Assert (($enf.Ok -eq $true) -and ($leaked.Count -eq 2) -and ($leaked -contains 'UI.BareSkip') -and ($leaked -contains 'UI.QuietSkip')) 'skip-classes' ($leaked -join ',')

# Strict matching: prose mentioning the tokens cannot self-allowlist;
# stamps need shape, codes need case, legacy anchors to the start.
$trxXml2 = @'
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
<UnitTestResult testName="UI.StampOk" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-20 D01-T01-S9 fixture-quarantine</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.MidQuarantine" outcome="NotExecuted"><Output><ErrorInfo><Message>flaky, QUARANTINED candidate, needs triage</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.DatelessStamp" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED incident without fields</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.CodedOk" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: Default printer is hardware</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LowerCapability" outcome="NotExecuted"><Output><ErrorInfo><Message>capability: hooks unavailable</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.MidLegacy" outcome="NotExecuted"><Output><ErrorInfo><Message>Error: No printers enumerated in this context (nested)</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LegacyPrefix" outcome="NotExecuted"><Output><ErrorInfo><Message>Default printer is hardware (USB001)</Message></ErrorInfo></Output></UnitTestResult>
</Results></TestRun>
'@
$trx2 = Join-Path $dir 'msgs.trx'
$trxXml2 | Set-Content -Path $trx2 -Encoding UTF8
$enf2 = Get-NonQuarantineSkips $trx2
$leaked2 = @($enf2.Names)
Assert (($enf2.Ok -eq $true) -and ($leaked2.Count -eq 4) -and ($leaked2 -contains 'UI.MidQuarantine') -and ($leaked2 -contains 'UI.DatelessStamp') -and ($leaked2 -contains 'UI.LowerCapability') -and ($leaked2 -contains 'UI.MidLegacy')) 'skip-strict' ($leaked2 -join ',')

# Counts: the trx sums plus the threaded assembly sum.
$sum = Get-TrxSummary $trx
Assert (($sum.Passed -eq 1) -and ($sum.FailedCount -eq 1) -and ($sum.SkippedCount -eq 6)) 'trx-sums' ("p=$($sum.Passed) f=$($sum.FailedCount) s=$($sum.SkippedCount)")
$leg = Get-LegSummary $trx $log
Assert (($leg.Passed -eq 15) -and ($leg.FailedCount -eq 3) -and ($leg.SkippedCount -eq 4)) 'leg-sums' ("p=$($leg.Passed) f=$($leg.FailedCount) s=$($leg.SkippedCount)")

# The cell equals its breakdown even when merged name-lines disagree:
# the fixture trx lists 6 skips, the transcript sums 4; the cell reads 4.
$row = Format-LegRow 'Run A' $leg $null 'fixture.log'
Assert ($row -like '| Run A | 15 passed, 3 failed, 4 skipped (UI.dll 10/1/3, Smoke.dll 5/2/1) | n/a (owns the foreground) | - | fixture.log |') 'cell-equals-breakdown' $row

# Infrastructure owns its column, never parenthesized into the counts.
$killed = [pscustomobject]@{ Passed = 1; FailedCount = 0; Failed = @(); Skipped = @(); SkippedCount = 0; Assemblies = 'UI.dll 1/0/0' }
$krow = Format-LegRow 'Run A' $killed $null 'fixture.log' 'killed at cap: unproven'
Assert ($krow -like '| Run A | 1 passed, 0 failed, 0 skipped (UI.dll 1/0/0) | n/a (owns the foreground) | killed at cap: unproven | fixture.log |') 'infra-column-split' $krow

# Null summary keeps the placeholder row with the note in Infra.
$norow = Format-LegRow 'Run B' $null $null 'missing.log' 'budget-cut (unproven)'
Assert ($norow -like '| Run B | no trx (leg skipped or produced none) | -- | budget-cut (unproven) | missing.log |') 'null-row-note' $norow

# Enforcement verdicts: green, red-with-names, not-run, unproven.
Assert ((Format-EnforcementVerdict $true @() $true) -eq '- Interactive (collection): GREEN (every skip quarantined or capability)') 'enforce-green'
Assert ((Format-EnforcementVerdict $true @('UI.BareSkip','UI.QuietSkip') $true) -eq '- Interactive (collection): RED (2 non-quarantine skips: UI.BareSkip, UI.QuietSkip)') 'enforce-red'
Assert ((Format-EnforcementVerdict $false @() $true) -eq '- Interactive (collection): n/a (leg did not run)') 'enforce-norun'
Assert ((Format-EnforcementVerdict $true @() $false) -eq '- Interactive (collection): UNPROVEN (trx missing or malformed: no skip classification)') 'enforce-unproven'
Assert ((Test-InteractiveCaptureNeeded 1 $false $true 0) -eq $true) 'capture-matrix-code'
Assert ((Test-InteractiveCaptureNeeded 0 $true $true 0) -eq $true) 'capture-matrix-killed'
Assert ((Test-InteractiveCaptureNeeded 0 $false $false 0) -eq $true) 'capture-matrix-unproven'
Assert ((Test-InteractiveCaptureNeeded 0 $false $true 2) -eq $true) 'capture-matrix-leaks'
Assert ((Test-InteractiveCaptureNeeded 0 $false $true 0) -eq $false) 'capture-matrix-green-quiet'

# Short hashes: known content, missing file.
[System.IO.File]::WriteAllText((Join-Path $dir 'hash.txt'), 'abc')
Assert ((Get-ShortHash (Join-Path $dir 'hash.txt')) -eq 'ba7816bf') 'short-hash-known' (Get-ShortHash (Join-Path $dir 'hash.txt'))
Assert ((Get-ShortHash (Join-Path $dir 'nope.dll')) -eq 'missing') 'short-hash-missing'

# Split output: transcript plus .out.log sibling merge into one summary.
$splitLog = Join-Path $dir 'split.log'
@('nightly: scope=fixture', 'Passed!  - Failed:     0, Passed:     7, Skipped:     0, Total:     7, Duration: 1 s - First.dll (net10.0)') | Set-Content -Path $splitLog -Encoding UTF8
@('Passed!  - Failed:     1, Passed:     3, Skipped:     2, Total:     6, Duration: 1 s - Second.dll (net10.0)', '  Failed UI.SplitFail [1 ms]') | Set-Content -Path ([System.IO.Path]::ChangeExtension($splitLog, '.out.log')) -Encoding UTF8
$split = Get-LegSummary (Join-Path $dir 'missing.trx') $splitLog
Assert (($split.Passed -eq 10) -and ($split.FailedCount -eq 1) -and ($split.SkippedCount -eq 2)) 'split-merge-sums' ("p=$($split.Passed) f=$($split.FailedCount) s=$($split.SkippedCount)")
Assert ((($split.Failed -join "`n") -like '*UI.SplitFail*') -and ($split.Assemblies -like '*First.dll 7/0/0, Second.dll 3/1/2*')) 'split-merge-names' ($split.Assemblies)

# Bounded teardown: completed jobs reap, live jobs abandon fast.
$quick = Start-Job -ScriptBlock { 'done' }
Wait-Job -Job $quick -Timeout 30 | Out-Null
Assert ((Invoke-BoundedTeardown $quick 5 'fixture-quick') -eq $true) 'teardown-reaps'
$stuck = Start-Job -ScriptBlock { Start-Sleep -Seconds 300 }
$abandonWatch = [System.Diagnostics.Stopwatch]::StartNew()
$abandoned = Invoke-BoundedTeardown $stuck 1 'fixture-stuck'
$abandonWatch.Stop()
Assert (($abandoned -eq $false) -and ($abandonWatch.Elapsed.TotalSeconds -lt 30)) 'teardown-abandons' ("result=$abandoned secs=$([int]$abandonWatch.Elapsed.TotalSeconds)")
Stop-Job -Job $stuck
Remove-Job -Job $stuck -Force

# Conservation: green, exotic-outcome break, row-total break, cross break.
# (Fixture names avoid reserved device prefixes: `con.*` fails Test-Path.)
$conTrx = '<TestRun><Results><UnitTestResult testName="UI.A" outcome="Passed" /><UnitTestResult testName="UI.B" outcome="Failed" /><UnitTestResult testName="UI.C" outcome="NotExecuted" /></Results></TestRun>'
$conTrx | Set-Content -Path (Join-Path $dir 'ok.trx') -Encoding UTF8
@('Passed!  - Failed:     1, Passed:     1, Skipped:     1, Total:     3, Duration: 1 s - UI.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'ok.log') -Encoding UTF8
$conGreen = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $false @()
Assert ($conGreen.Ok -eq $true) 'conservation-green' ($conGreen.Breaks -join '|')
$exoticTrx = '<TestRun><Results><UnitTestResult testName="UI.A" outcome="Passed" /><UnitTestResult testName="UI.B" outcome="Inconclusive" /></Results></TestRun>'
$exoticTrx | Set-Content -Path (Join-Path $dir 'exotic.trx') -Encoding UTF8
$conExotic = Test-CountConservation 'Fix' (Join-Path $dir 'exotic.trx') (Join-Path $dir 'missing.log') $false @()
Assert (($conExotic.Ok -eq $false) -and (($conExotic.Breaks -join '') -like '*exotic outcomes (Inconclusive)*')) 'conservation-exotic' ($conExotic.Breaks -join '|')
@('Passed!  - Failed:     1, Passed:     1, Skipped:     1, Total:     9, Duration: 1 s - UI.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'badrow.log') -Encoding UTF8
$conRow = Test-CountConservation 'Fix' (Join-Path $dir 'missing.trx') (Join-Path $dir 'badrow.log') $false @()
Assert (($conRow.Ok -eq $false) -and (($conRow.Breaks -join '') -like '*1+1+1 != Total 9*')) 'conservation-row' ($conRow.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     2, Skipped:     1, Total:     3, Duration: 1 s - UI.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'cross.log') -Encoding UTF8
$conCross = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'cross.log') $false @()
Assert (($conCross.Ok -eq $false) -and (($conCross.Breaks -join '') -like '*cross-level*')) 'conservation-cross' ($conCross.Breaks -join '|')
$conVacuous = Test-CountConservation 'Fix' (Join-Path $dir 'missing.trx') (Join-Path $dir 'missing.log') $false @()
Assert ($conVacuous.Ok -eq $true) 'conservation-vacuous'
$conMulti = Test-CountConservation 'Fix' $trx $log $false @()
Assert ($conMulti.Ok -eq $true) 'conservation-multi' ($conMulti.Breaks -join '|')
$conExpected = Test-CountConservation 'Run B' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $true @()
Assert ($conExpected.Ok -eq $true) 'conservation-expected-green' ($conExpected.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 1 s - Smoke.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'partial.log') -Encoding UTF8
$conMissing = Test-CountConservation 'Run A' (Join-Path $dir 'missing.trx') (Join-Path $dir 'partial.log') $true @('Smoke.dll', 'Unit.dll', 'Protocol.dll', 'UI.dll')
Assert (($conMissing.Ok -eq $false) -and (($conMissing.Breaks -join '') -like '*UI.dll missing*')) 'conservation-missing' ($conMissing.Breaks -join '|')
$conUnknown = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $true @()
Assert (($conUnknown.Ok -eq $false) -and (($conUnknown.Breaks -join '') -like '*unknown leg*')) 'conservation-unknown-leg' ($conUnknown.Breaks -join '|')
$conCustom = Test-CountConservation 'Run A' (Join-Path $dir 'missing.trx') (Join-Path $dir 'partial.log') $true @('Smoke.dll')
Assert ($conCustom.Ok -eq $true) 'conservation-custom-set-green' ($conCustom.Breaks -join '|')

# Quarantine windows: overdue, current, malformed, and clean ledgers.
$ledgerLines = @(
  '# Fixture ledger',
  '',
  '## Quarantine list',
  '',
  '| Test | Failure signature | First seen | Owner | Quarantined | Due |',
  '| ---- | ----------------- | ---------- | ----- | ----------- | --- |',
  '| `UI.Old` (`old-flake`) | boom | 2026-09-01 | D01 T01 §1 | 2026-09-01 | 2026-09-08 |',
  '| `UI.New` (`new-flake`) | boom | 2026-09-19 | D01 T01 §2 | 2026-09-19 | 2026-09-26 |',
  '| `UI.Bad` (`bad-flake`) | boom | 2026-09-19 | D01 T01 §3 | 2026-09-19 | someday |',
  '',
  '## Something else',
  '',
  '| Test | Failure signature | First seen | Owner | Quarantined | Due |',
  '| `UI.Elsewhere` (`x`) | boom | 2026-09-01 | D01 T01 §9 | 2026-09-01 | 2020-01-01 |'
)
$ledgerLines | Set-Content -Path (Join-Path $dir 'ledger.md') -Encoding UTF8
$quar = Test-QuarantineWindows (Join-Path $dir 'ledger.md') ([datetime]'2026-09-20')
Assert ($quar.Overdue.Count -eq 2) 'quarantine-overdue-count' ($quar.Overdue.Count)
Assert ((($quar.Overdue | Where-Object { -not $_.Malformed }).Test -join '') -like '*UI.Old*') 'quarantine-overdue-which' (($quar.Overdue | ForEach-Object { $_.Test }) -join '|')
Assert ((($quar.Overdue | Where-Object { $_.Malformed }).Test -join '') -like '*UI.Bad*') 'quarantine-malformed' (($quar.Overdue | ForEach-Object { $_.Test }) -join '|')
Assert (($quar.Open -eq 3) -and ($quar.EarliestDue -eq '2026-09-08')) 'quarantine-open-line' ("open=$($quar.Open) earliest=$($quar.EarliestDue)")
$quarClean = Test-QuarantineWindows (Join-Path $dir 'ledger.md') ([datetime]'2026-09-01')
Assert (($quarClean.Overdue.Count -eq 1) -and ($quarClean.Open -eq 3)) 'quarantine-clean-except-malformed' ($quarClean.Overdue.Count)
Assert ($quar.OpenRows.Count -eq 3) 'quarantine-openrows'
Assert ((Get-DueSoonTests $quar.OpenRows ([datetime]'2026-09-20') 3).Count -eq 0) 'duesoon-none'
Assert ((Get-DueSoonTests $quar.OpenRows ([datetime]'2026-09-24') 3) -join '|' -like '*UI.New*') 'duesoon-hit'

# Soak fourth phase: green, red-with-names, killed, and cut verdicts.
$soakDir = Join-Path $dir 'soakgreen'
$null = New-Item -ItemType Directory -Force -Path $soakDir
$greenTrx = '<TestRun><Results><UnitTestResult testName="UI.SoakOk" outcome="Passed" /></Results></TestRun>'
foreach ($n in @('ui-soak-1','ui-soak-2','ui-soak-3','ui-soak-4','ui-soak-5','protocol-soak-1','protocol-soak-2','protocol-soak-3','protocol-soak-4','protocol-soak-5')) {
  $greenTrx | Set-Content -Path (Join-Path $soakDir "$n.trx") -Encoding UTF8
}
$green = Format-SoakLedger $soakDir @() @() @() $true
Assert (($green.Failed -eq $false) -and ($green.Rows[0] -eq '- Verdict: GREEN (10/10 iterations proved)')) 'soak-green' $green.Rows[0]

$redDir = Join-Path $dir 'soakred'
$null = New-Item -ItemType Directory -Force -Path $redDir
$redTrx = '<TestRun><Results><UnitTestResult testName="UI.Flaky" outcome="Failed"><Output><ErrorInfo><Message>flake</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>'
$redTrx | Set-Content -Path (Join-Path $redDir 'ui-soak-3.trx') -Encoding UTF8
$red = Format-SoakLedger $redDir @('ui-soak-5') @('protocol-soak-1..5') @() $true
Assert ($red.Failed -eq $true) 'soak-red-flag'
Assert ($red.Rows[0] -like '- Verdict: RED (FAILED: ui-soak-3; unproven: ui-soak-1, ui-soak-2, ui-soak-4, ui-soak-5, protocol-soak-1..5*') 'soak-red-verdict' $red.Rows[0]
Assert (($red.Rows -join "`n") -like '*UI.Flaky*flake*') 'soak-red-names' ($red.Rows -join '|')
Assert (($red.Rows -join "`n") -like '*- ui-soak-5 : no trx (killed at cap: unproven; owes triage: re-drive or carry)*') 'soak-killed-row' ($red.Rows -join '|')
Assert (($red.Rows -join "`n") -like '*- protocol-soak-1..5 : budget-cut (unproven; owes triage: re-drive or carry)*') 'soak-cut-row' ($red.Rows -join '|')

$emptyDir = Join-Path $dir 'soakempty'
$null = New-Item -ItemType Directory -Force -Path $emptyDir
$empty = Format-SoakLedger $emptyDir @() @() @() $false
Assert (($empty.Failed -eq $false) -and (($empty.Rows -join '') -like '*no soak iterations ran*')) 'soak-empty' ($empty.Rows -join '|')
$forced = Format-SoakLedger $emptyDir @() @() @() $false 'build failure'
Assert (($forced.Failed -eq $false) -and (($forced.Rows -join '') -like '*no soak iterations ran: build failure*')) 'soak-forced-reason' ($forced.Rows -join '|')
foreach ($reasonCase in @(@('placement violation', 'soak-forced-placement'), @('past deadline at start', 'soak-forced-deadline'), @('population drift', 'soak-forced-drift'))) {
  $forcedCase = Format-SoakLedger $emptyDir @() @() @() $false $reasonCase[0]
  Assert (($forcedCase.Failed -eq $false) -and (($forcedCase.Rows -join '') -like "*no soak iterations ran: $($reasonCase[0])*")) $reasonCase[1] ($forcedCase.Rows -join '|')
}
$opSkip = Format-SoakLedger $emptyDir @() @() @() $false ''
Assert (($opSkip.Failed -eq $false) -and (($opSkip.Rows -join '') -like '*no soak iterations ran: -SkipSoak*')) 'soak-operator-shape' ($opSkip.Rows -join '|')

# Failed-without-trx plus exit-0-without-trx iterations land unproven
# rows; an all-failed ledger never prints the empty shape.
$failDir = Join-Path $dir 'soakfailed'
$null = New-Item -ItemType Directory -Force -Path $failDir
$fail = Format-SoakLedger $failDir @() @() @('ui-soak-2') $true
Assert (($fail.Failed -eq $true) -and ((($fail.Rows -join "`n") -like '*ui-soak-2 : no trx (failed without trx*'))) 'soak-failed-no-trx' ($fail.Rows -join '|')
Assert ((($fail.Rows -join "`n") -like '*ui-soak-1 : no trx despite exit 0*')) 'soak-exit0-no-trx' ($fail.Rows -join '|')
Assert ((($fail.Rows -join "`n") -notlike '*no soak iterations ran*')) 'soak-failed-never-empty' ($fail.Rows -join '|')
$abortTrx = '<TestRun><Results><UnitTestResult testName="UI.Aborted" outcome="Aborted" /></Results></TestRun>'
$abortTrx | Set-Content -Path (Join-Path $failDir 'ui-soak-4.trx') -Encoding UTF8
$failAbort = Format-SoakLedger $failDir @() @() @('ui-soak-2', 'ui-soak-4') $true
Assert ((($failAbort.Rows -join "`n") -like '*ui-soak-4 : nonzero exit, trx carries no Failed outcomes*')) 'soak-failed-aborted-trx' ($failAbort.Rows -join '|')
$redFailed = Format-SoakLedger $redDir @('ui-soak-5') @('protocol-soak-1..5') @('ui-soak-3') $true
Assert ((($redFailed.Rows -join "`n") -like '*ui-soak-3 : 0 passed, 1 failed, 0 skipped (FAILED)*') -and ((($redFailed.Rows -join "`n") -like '*UI.Flaky*flake*'))) 'soak-failed-keeps-names' ($redFailed.Rows -join '|')

# Truncation grades: minimum met degrades, minimum missed voids, and
# every cut range owes triage its re-drive (D00-T02-S14-PR12).
$degDir = Join-Path $dir 'soakdegraded'
$null = New-Item -ItemType Directory -Force -Path $degDir
foreach ($n in @('ui-soak-1', 'ui-soak-2', 'ui-soak-3', 'protocol-soak-1', 'protocol-soak-2', 'protocol-soak-3')) {
  $greenTrx | Set-Content -Path (Join-Path $degDir "$n.trx") -Encoding UTF8
}
$degraded = Format-SoakLedger $degDir @() @('ui-soak-4..5', 'protocol-soak-4..5') @() $true
Assert (($degraded.Failed -eq $true) -and ($degraded.Rows[0] -like '*degraded (minimum 3+3 met: ui=3 protocol=3)*')) 'soak-degraded' $degraded.Rows[0]
Assert ((($degraded.Rows -join "`n") -like '*owes triage: re-drive or carry*')) 'soak-owed' ($degraded.Rows -join '|')
$voidDir = Join-Path $dir 'soakvoid'
$null = New-Item -ItemType Directory -Force -Path $voidDir
foreach ($n in @('ui-soak-1', 'protocol-soak-1', 'protocol-soak-2')) {
  $greenTrx | Set-Content -Path (Join-Path $voidDir "$n.trx") -Encoding UTF8
}
$voided = Format-SoakLedger $voidDir @() @('ui-soak-2..5', 'protocol-soak-3..5') @() $true
Assert (($voided.Failed -eq $true) -and ($voided.Rows[0] -like '*minimum MISSED (ui=1/3 protocol=2/3; hunt void, full re-drive owed)*')) 'soak-void' $voided.Rows[0]

# Incidents: digit-shape dedupe keeps every occurrence under a stable ID.
$incIn = @(
  [pscustomobject]@{ Test = 'UI.Flaky'; Message = 'flake attempt 3 of 10'; Where = 'ui-soak-3' },
  [pscustomobject]@{ Test = 'UI.Flaky'; Message = 'flake attempt 5 of 10'; Where = 'protocol-soak-1' },
  [pscustomobject]@{ Test = 'UI.Other'; Message = 'boom'; Where = 'Run A' }
)
$inc = @(Format-Incidents $incIn)
Assert ($inc.Count -eq 2) 'incident-group-count' ($inc -join '|')
Assert ($inc[0] -eq '- INC-02f59b86 `UI.Flaky` x2 (ui-soak-3, protocol-soak-1): flake attempt 3 of 10') 'incident-dedupe-line' $inc[0]
Assert ($inc[1] -eq '- INC-493b0a11 `UI.Other` x1 (Run A): boom') 'incident-single-line' $inc[1]
$incAgain = @(Format-Incidents $incIn)
Assert (($incAgain -join "`n") -eq ($inc -join "`n")) 'incident-stable-id' ($incAgain -join '|')
Assert (@(Format-Incidents @()).Count -eq 0) 'incident-empty'
$longMsg = 'x' * 200
$incLong = @(Format-Incidents @([pscustomobject]@{ Test = 'UI.Long'; Message = $longMsg; Where = 'Run B' }))
Assert (($incLong.Count -eq 1) -and ($incLong[0].Length -lt 200)) 'incident-truncates' $incLong[0]

# Per-project merge: two trx plus two out.logs merge into one summary
# with the grand sums cross-checked (D00-T02-S13-R2-F2).
$mergeA = '<TestRun><Results><UnitTestResult testName="Smoke.S1" outcome="Passed" /><UnitTestResult testName="Smoke.S2" outcome="Failed"><Output><ErrorInfo><Message>smoke boom</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>'
$mergeA | Set-Content -Path (Join-Path $dir 'run-a-Smoke.trx') -Encoding UTF8
$mergeB = '<TestRun><Results><UnitTestResult testName="Unit.U1" outcome="Passed" /><UnitTestResult testName="Unit.U2" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-20 D00-T02-S9 probe</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>'
$mergeB | Set-Content -Path (Join-Path $dir 'run-a-Unit.trx') -Encoding UTF8
@('Passed!  - Failed:     1, Passed:     1, Skipped:     0, Total:     2, Duration: 1 s - Smoke.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'merge-Smoke.out.log') -Encoding UTF8
@('Passed!  - Failed:     0, Passed:     1, Skipped:     1, Total:     2, Duration: 1 s - Unit.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'merge-Unit.out.log') -Encoding UTF8
$merged = Get-LegSummary @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'run-a-Unit.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-Unit.out.log'))
Assert (($merged.Passed -eq 2) -and ($merged.FailedCount -eq 1) -and ($merged.SkippedCount -eq 1)) 'merge-sums' ("p=$($merged.Passed) f=$($merged.FailedCount) s=$($merged.SkippedCount)")
Assert ((($merged.Failed -join "`n") -like '*Smoke.S2*smoke boom*') -and (($merged.Skipped -join "`n") -like '*Unit.U2*QUARANTINED*')) 'merge-lines' (($merged.Failed + $merged.Skipped) -join '|')
Assert ($merged.Assemblies -eq 'Smoke.dll 1/1/0, Unit.dll 1/0/1') 'merge-assemblies' $merged.Assemblies
$mergeCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'run-a-Unit.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-Unit.out.log')) $false @()
Assert ($mergeCon.Ok -eq $true) 'merge-conservation-green' ($mergeCon.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     9, Skipped:     1, Total:     10, Duration: 1 s - Unit.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'merge-skew.out.log') -Encoding UTF8
$skewCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'run-a-Unit.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-skew.out.log')) $false @()
Assert (($skewCon.Ok -eq $false) -and (($skewCon.Breaks -join '') -like '*cross-level-aggregate*')) 'merge-conservation-skew' ($skewCon.Breaks -join '|')
$killedCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'missing-step.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-Unit.out.log')) $false @()
Assert (($killedCon.Ok -eq $true) -and ((($killedCon.Breaks -join '') -notlike '*cross-level-aggregate*'))) 'merge-conservation-killed-skips' ($killedCon.Breaks -join '|')

# Suite-wide Primary guard: strays outside tests/UI fail closed with
# path:line, UI traits count, line comments do not count.
$placeRoot = Join-Path $dir 'placetree'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $placeRoot 'UI'), (Join-Path $placeRoot 'Unit')
@('public class A {', '    [Trait("Category", "Primary")]', '    public void P1() {}', '    // [Trait("Category", "Primary")] commented out', '}') | Set-Content -Path (Join-Path $placeRoot 'UI\A.cs') -Encoding UTF8
@('public class B {', '    [Trait( "Category" , "Primary" )]', '}') | Set-Content -Path (Join-Path $placeRoot 'Unit\B.cs') -Encoding UTF8
$place = Test-PrimaryPlacement $placeRoot
Assert (($place.Ok -eq $false) -and ($place.UiCount -eq 1)) 'placement-stray-red' ("ok=$($place.Ok) ui=$($place.UiCount) strays=$(($place.Strays -join '|'))")
Assert ((@($place.Strays).Count -eq 1) -and ($place.Strays[0] -like 'Unit\B.cs:2')) 'placement-stray-where' ($place.Strays -join '|')
Remove-Item (Join-Path $placeRoot 'Unit\B.cs') -Force
$placeClean = Test-PrimaryPlacement $placeRoot
Assert (($placeClean.Ok -eq $true) -and ($placeClean.UiCount -eq 1)) 'placement-clean-green' ("ok=$($placeClean.Ok) ui=$($placeClean.UiCount)")
$placeMissing = Test-PrimaryPlacement (Join-Path $dir 'no-such-tree')
Assert ($placeMissing.Ok -eq $false) 'placement-missing-root-red'
@('public class C {', '    [Trait(', '        "Category",', '        "Primary")]', '}') | Set-Content -Path (Join-Path $placeRoot 'Unit\C.cs') -Encoding UTF8
$placeMulti = Test-PrimaryPlacement $placeRoot
Assert (($placeMulti.Ok -eq $false) -and ((@($placeMulti.Strays) -join '|') -like '*Unit\C.cs:2*')) 'placement-multiline-stray' ($placeMulti.Strays -join '|')
Remove-Item (Join-Path $placeRoot 'Unit\C.cs') -Force

# Supervisor-versus-task pin: the supervisor default must precede the
# scheduled task kill, and unreadable inputs fail closed.
$supLive = Test-SupervisorUnderLimit (Join-Path $PSScriptRoot 'NightlySupervisor.ps1') 'PT4H'
Assert (($supLive.Ok -eq $true) -and ($supLive.Detail -eq 'supervisor 14280s under task 14400s')) 'supervisor-live-under' $supLive.Detail
$supBad = Join-Path $dir 'sup-bad.ps1'
'[int]$TimeoutSeconds = 99999,' | Set-Content -Path $supBad -Encoding UTF8
Assert ((Test-SupervisorUnderLimit $supBad 'PT4H').Ok -eq $false) 'supervisor-over-red'
Assert ((Test-SupervisorUnderLimit (Join-Path $PSScriptRoot 'NightlySupervisor.ps1') 'garbage').Ok -eq $false) 'supervisor-limit-unparseable-red'
$supEqual = Join-Path $dir 'sup-equal.ps1'
'[int]$TimeoutSeconds = 14400,' | Set-Content -Path $supEqual -Encoding UTF8
Assert ((Test-SupervisorUnderLimit $supEqual 'PT4H').Ok -eq $false) 'supervisor-equal-red'

# Bounded discovery: fast producers relay output plus exit code, hangs
# die at the cap, and the list-tests parse rides the bounded path.
$capFast = Invoke-BoundedCapture 'powershell.exe' @('-NoProfile', '-Command', 'Write-Output line-a; Write-Output line-b') $dir 30
Assert ((($capFast.Text -join '') -like '*line-a*line-b*') -and ($capFast.Code -eq 0) -and ($capFast.Killed -eq $false)) 'bounded-fast-relays' $capFast.Text
$capHang = Invoke-BoundedCapture 'powershell.exe' @('-NoProfile', '-Command', 'Start-Sleep 30') $dir 2
Assert (($capHang.Killed -eq $true) -and ($capHang.Code -eq 1)) 'bounded-hang-kills'
$capCode = Invoke-BoundedCapture 'powershell.exe' @('-NoProfile', '-Command', 'exit 3') $dir 30
Assert (($capCode.Code -eq 3) -and ($capCode.Killed -eq $false)) 'bounded-exit-relays' $capCode.Code
$stubDotnet = Join-Path $dir 'stub-dotnet.ps1'
@('param([Parameter(ValueFromRemainingArguments = $true)]$rest)', "'    UI.Fake.T1'", "'    UI.Fake.T2 (case 1)'") | Set-Content -Path $stubDotnet -Encoding UTF8
$stubList = Get-ListTestsCases $stubDotnet (Join-Path $dir 'UI.csproj') 'anything' 'stub'
Assert (($stubList.MethodCount -eq 2) -and ($stubList.CaseCount -eq 2) -and ($stubList.Methods -contains 'UI.Fake.T2')) 'bounded-discovery-parses' ($stubList.Methods -join '|')
$stubHang = Join-Path $dir 'stub-hang.ps1'
@('param([Parameter(ValueFromRemainingArguments = $true)]$rest)', 'Start-Sleep 30') | Set-Content -Path $stubHang -Encoding UTF8
$stubTimedOut = $false
try { $null = Get-ListTestsCases $stubHang (Join-Path $dir 'UI.csproj') 'anything' 'stubhang' 2 } catch { $stubTimedOut = ($_.Exception.Message -like '*timed out*') }
Assert ($stubTimedOut -eq $true) 'bounded-discovery-hang-throws'

# Fingerprint: round-trip, clean compare, member plus case plus filter
# drifts, malformed shapes, literal extraction (D00-T02-S13-PR13).
$fpDisc = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 1 }
$fpFile = Join-Path $dir 'pop.fingerprint'
Write-TestPopulationFile $fpFile 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $fpDisc
$fpRead = Read-TestPopulationFile $fpFile
Assert (($fpRead.Ok -eq $true) -and ($fpRead.RunA.Count -eq 2) -and ($fpRead.RunB.Count -eq 1) -and ($fpRead.Interactive.Count -eq 1) -and ($fpRead.RunACases -eq 3) -and ($fpRead.RunAFilter -eq 'Category!=Interactive&Category!=Primary')) 'fingerprint-roundtrip'
$fpBytes = [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($fpFile))
Assert (($fpBytes -like '*C2-A7*') -and ($fpBytes -notlike '*C3-82*')) 'fingerprint-header-encoding' $fpBytes.Substring(0, [Math]::Min(60, $fpBytes.Length))
$fakeNightly = Join-Path $dir 'nightly-fake.ps1'
@(
  '# (Category!=Interactive&Category!=Primary; prose must not match)',
  "  `$collectFilter = 'Category=Interactive'",
  "  `$stepArgs = @('test', '--filter', 'Category!=Interactive&Category!=Primary')",
  "  `$stepArgs = @('test', '--filter', 'Category=Primary')"
) | Set-Content -Path $fakeNightly -Encoding UTF8
$lits = Get-NightlyFilterLiterals $fakeNightly
Assert ((($lits.Literals -join '|') -eq 'Category!=Interactive&Category!=Primary|Category=Primary') -and ($lits.CollectDefault -eq 'Category=Interactive')) 'fingerprint-literals' (($lits.Literals -join '|') + ' / ' + $lits.CollectDefault)
$popClean = Compare-TestPopulation $fpFile $fakeNightly $fpDisc
Assert ($popClean.Ok -eq $true) 'fingerprint-clean' ($popClean.Drifts -join '|')
$driftDisc = [pscustomobject]@{ RunA = @('UI.A.T1'); RunB = @('UI.B.P1', 'UI.B.P2'); Interactive = @(); RunAMethods = 1; RunACases = 1; RunBMethods = 2; RunBCases = 2; InteractiveMethods = 0; InteractiveCases = 0 }
$popDrift = Compare-TestPopulation $fpFile $fakeNightly $driftDisc
Assert (($popDrift.Ok -eq $false) -and (($popDrift.Drifts -join '') -like '*run-b added: UI.B.P2*') -and (($popDrift.Drifts -join '') -like '*interactive removed: UI.C.I1*') -and (($popDrift.Drifts -join '') -like '*run-a-methods: fingerprinted 2 vs discovered 1*')) 'fingerprint-drift' ($popDrift.Drifts -join '|')
$skewDisc = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 9; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 1 }
$popSkew = Compare-TestPopulation $fpFile $fakeNightly $skewDisc
Assert (($popSkew.Ok -eq $false) -and (($popSkew.Drifts -join '') -like '*run-a-cases: fingerprinted 3 vs discovered 9*')) 'fingerprint-case-skew' ($popSkew.Drifts -join '|')
$swapDisc = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.X'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 1 }
$popSwap = Compare-TestPopulation $fpFile $fakeNightly $swapDisc
Assert (($popSwap.Ok -eq $false) -and (($popSwap.Drifts -join '') -like '*run-a removed: UI.A.T2*') -and (($popSwap.Drifts -join '') -like '*run-a added: UI.A.X*')) 'fingerprint-run-a-swap' ($popSwap.Drifts -join '|')
@('run-a-filter: Category!=Interactive&Category!=Primary', 'run-b-filter: Category=Primary', 'interactive-filter: Category=Interactive', 'run-a-methods: 2', 'run-a-cases: 3', 'run-b:', '  UI.B.P1', 'run-b-methods: 1', 'run-b-cases: 1', 'interactive:', '  UI.C.I1', 'interactive-methods: 1', 'interactive-cases: 1') | Set-Content -Path (Join-Path $dir 'pop-noruna.fingerprint') -Encoding UTF8
$popNoRuna = Compare-TestPopulation (Join-Path $dir 'pop-noruna.fingerprint') $fakeNightly $fpDisc
Assert (($popNoRuna.Ok -eq $false) -and (($popNoRuna.Drifts -join '') -like '*run-a items 0 != methods 2*')) 'fingerprint-run-a-required' ($popNoRuna.Drifts -join '|')
$fakeNightly2 = Join-Path $dir 'nightly-fake2.ps1'
@(
  "  `$collectFilter = 'Category=Interactive'",
  "  `$stepArgs = @('test', '--filter', 'Category!=Interactive')",
  "  `$stepArgs = @('test', '--filter', 'Category=Primary')"
) | Set-Content -Path $fakeNightly2 -Encoding UTF8
$popFilter = Compare-TestPopulation $fpFile $fakeNightly2 $fpDisc
Assert (($popFilter.Ok -eq $false) -and (($popFilter.Drifts -join '') -like "*appears 0 times*")) 'fingerprint-filter-drift' ($popFilter.Drifts -join '|')
@('run-a-filter: Category!=Interactive&Category!=Primary') | Set-Content -Path (Join-Path $dir 'pop-bad.fingerprint') -Encoding UTF8
$popBad = Compare-TestPopulation (Join-Path $dir 'pop-bad.fingerprint') $fakeNightly $fpDisc
Assert (($popBad.Ok -eq $false) -and (($popBad.Drifts -join '') -like '*missing run-b-filter*')) 'fingerprint-malformed' ($popBad.Drifts -join '|')

# Filter partition: the fingerprinted Run A plus Run B filters select
# the synthetic population soundly, and edits breaking the partition
# surface as violations (D00-T02-S13-PR17).
$liveFp = Read-TestPopulationFile (Join-Path $PSScriptRoot '..\tests\UI\TestPopulation.fingerprint')
Assert ($liveFp.Ok -eq $true) 'filter-live-fingerprint' $liveFp.Error
$partMembers = @(
  [pscustomobject]@{ Name = 'UI.A.Default'; Categories = @() },
  [pscustomobject]@{ Name = 'UI.B.Place'; Categories = @('Primary') },
  [pscustomobject]@{ Name = 'UI.C.Fence'; Categories = @('Interactive') },
  [pscustomobject]@{ Name = 'UI.D.Both'; Categories = @('Primary', 'Interactive') }
)
$partGreen = @(Test-FilterPartition $liveFp.RunAFilter $liveFp.RunBFilter $partMembers)
Assert ($partGreen.Count -eq 0) 'filter-partition-green' ($partGreen -join '|')
$partMutA = @(Test-FilterPartition 'Category!=Interactive' $liveFp.RunBFilter $partMembers)
Assert ((($partMutA -join '') -like '*run-a selects primary: UI.B.Place*')) 'filter-mutation-runa' ($partMutA -join '|')
$partMutB = @(Test-FilterPartition $liveFp.RunAFilter 'Category=Interactive' $partMembers)
Assert ((($partMutB -join '') -like '*run-b misses primary: UI.B.Place*')) 'filter-mutation-runb' ($partMutB -join '|')
$partOr = @(Test-FilterPartition 'Category=Primary|Category=Interactive' $liveFp.RunBFilter $partMembers)
Assert ((($partOr -join '') -like '*unsupported clause in run-a*') -and (@($partOr).Count -eq 1)) 'filter-unsupported' ($partOr -join '|')

# Atomic reports: content lands intact with no .tmp residue.
Write-AtomicReport @('line-a', 'line-b') (Join-Path $dir 'atomic.md')
Assert (((Get-Content (Join-Path $dir 'atomic.md') -Raw) -replace "`r`n", '|') -eq 'line-a|line-b|') 'atomic-content'
Assert (-not (Test-Path (Join-Path $dir 'atomic.md.tmp'))) 'atomic-no-residue'

# --- D00 T02 §16 fixtures ---
$s16 = Join-Path $dir 's16'
$null = New-Item -ItemType Directory -Force -Path $s16

# Read-LatestReport: pointer resolves and verifies.
$lr = Join-Path $s16 'latest-ok'
$null = New-Item -ItemType Directory -Force -Path $lr
'2026-09-20-023001' | Set-Content -Path (Join-Path $lr 'latest.txt') -Encoding UTF8
@('# Morning report: 2026-09-20', 'Status: final', '', '- Run identity: 2026-09-20-023001-pid4242') | Set-Content -Path (Join-Path $lr 'morning-2026-09-20-023001.md') -Encoding UTF8
$r = Read-LatestReport $lr
Assert ($r.Ok -and ($r.Stamp -eq '2026-09-20-023001')) 'latest-ok' $r.Error
$lrMissing = Join-Path $s16 'latest-missing'
$null = New-Item -ItemType Directory -Force -Path $lrMissing
Assert (-not (Read-LatestReport $lrMissing).Ok) 'latest-missing-pointer'
'' | Set-Content -Path (Join-Path $lrMissing 'latest.txt') -Encoding UTF8
Assert ((Read-LatestReport $lrMissing).Error -eq 'latest.txt empty') 'latest-empty'
'2026-09-20-023002' | Set-Content -Path (Join-Path $lrMissing 'latest.txt') -Encoding UTF8
Assert ((Read-LatestReport $lrMissing).Error -like 'target missing*') 'latest-target-missing'
@('# Morning report: 2026-09-20', 'Status: pre-soak core verdicts (final report overwrites after soak)', '', '- Run identity: 2026-09-20-023002-pid9') | Set-Content -Path (Join-Path $lrMissing 'morning-2026-09-20-023002.md') -Encoding UTF8
Assert ((Read-LatestReport $lrMissing).Error -eq 'target is not final') 'latest-not-final'
@('# Morning report: 2026-09-20', 'Status: final', '', '- Run identity: 2026-09-20-999999-pid9') | Set-Content -Path (Join-Path $lrMissing 'morning-2026-09-20-023002.md') -Encoding UTF8
Assert ((Read-LatestReport $lrMissing).Error -like 'identity mismatch*') 'latest-identity-mismatch'
@('# Stood-down run: x', 'Status: stood-down') | Set-Content -Path (Join-Path $lrMissing 'morning-2026-09-20-023002.md') -Encoding UTF8
Assert ((Read-LatestReport $lrMissing).Error -eq 'target is not a morning report') 'latest-not-report'

# Get-TreeFingerprint: content, not just counts.
$gr = Join-Path $s16 'gitrepo'
$null = New-Item -ItemType Directory -Force -Path $gr
Push-Location $gr
git init -q 2>$null | Out-Null; git config user.email 't@t' 2>$null | Out-Null; git config user.name 't' 2>$null | Out-Null
'v1' | Set-Content -Path (Join-Path $gr 'a.txt') -Encoding UTF8
git add -A 2>$null | Out-Null; git commit -qm init 2>$null | Out-Null
Pop-Location
$f = Get-TreeFingerprint $gr
Assert (($f.State -eq 'clean') -and ($f.Fingerprint -eq '') -and ($f.Count -eq 0)) 'tree-clean'
'v2' | Set-Content -Path (Join-Path $gr 'a.txt') -Encoding UTF8
$f2 = Get-TreeFingerprint $gr
Assert (($f2.State -eq 'dirty') -and ($f2.Fingerprint -ne '') -and ($f2.Count -eq 1)) 'tree-dirty'
'v3-other-bytes' | Set-Content -Path (Join-Path $gr 'a.txt') -Encoding UTF8
$f3 = Get-TreeFingerprint $gr
Assert (($f3.Count -eq 1) -and ($f3.Fingerprint -ne $f2.Fingerprint)) 'tree-content-swap' "$($f2.Fingerprint) vs $($f3.Fingerprint)"
'new' | Set-Content -Path (Join-Path $gr 'b.txt') -Encoding UTF8
$f4 = Get-TreeFingerprint $gr
Assert (($f4.Count -eq 2) -and ($f4.Fingerprint -ne $f3.Fingerprint)) 'tree-add-file'
$nr = Join-Path $s16 'notrepo'
$null = New-Item -ItemType Directory -Force -Path $nr
Assert ((Get-TreeFingerprint $nr).State -eq 'unknown') 'tree-unknown'

# Test-ProjectCoverage: discovery cross-checks the executed set.
$tr = Join-Path $s16 'testsroot'
foreach ($p in @('Smoke', 'Unit', 'Protocol', 'UI')) {
  $pd = Join-Path $tr $p; $null = New-Item -ItemType Directory -Force -Path $pd
  '<Project Sdk="x"><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="1" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $pd "$p.csproj") -Encoding UTF8
}
$fx = Join-Path $tr 'Fixtures\AcpLoopback'; $null = New-Item -ItemType Directory -Force -Path $fx
'<Project Sdk="x"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup></Project>' | Set-Content -Path (Join-Path $fx 'AcpLoopback.csproj') -Encoding UTF8
$bd = Join-Path $tr 'UI\bin'; $null = New-Item -ItemType Directory -Force -Path $bd
'Microsoft.NET.Test.Sdk' | Set-Content -Path (Join-Path $bd 'Decoy.csproj') -Encoding UTF8
$c = Test-ProjectCoverage $tr @('Smoke', 'Unit', 'Protocol', 'UI')
Assert ($c.Ok -and ($c.Found.Count -eq 4)) 'coverage-clean' ($c.Found -join ',')
$c2 = Test-ProjectCoverage $tr @('Smoke', 'Unit', 'Protocol')
Assert ((-not $c2.Ok) -and ($c2.Missing -join ',' -eq 'UI')) 'coverage-missing' ($c2.Missing -join ',')
$np = Join-Path $tr 'NewSuite'; $null = New-Item -ItemType Directory -Force -Path $np
'<Project Sdk="x"><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="1" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $np 'NewSuite.csproj') -Encoding UTF8
$c3 = Test-ProjectCoverage $tr @('Smoke', 'Unit', 'Protocol', 'UI')
Assert ((-not $c3.Ok) -and ($c3.Missing -join ',' -eq 'NewSuite')) 'coverage-planted'
$lp = Join-Path $tr 'Locked'; $null = New-Item -ItemType Directory -Force -Path $lp
'<Project Sdk="x"><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="1" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $lp 'Locked.csproj') -Encoding UTF8
$fs = [System.IO.File]::Open((Join-Path $lp 'Locked.csproj'), 'Open', 'Read', 'None')
try { $cLock = Test-ProjectCoverage $tr @('Smoke', 'Unit', 'Protocol', 'UI', 'NewSuite') } finally { $fs.Close() }
Assert ((-not $cLock.Ok) -and (@($cLock.Missing) -contains 'Locked')) 'coverage-unreadable'
Remove-Item $lp -Recurse -Force
Assert ((Test-ProjectCoverage (Join-Path $s16 'no-such-root') @('UI')).Ok) 'coverage-missing-root'

# Read-TaskXml: definition parses or fails closed.
$taskXml = @'
<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><CalendarTrigger><StartBoundary>2026-09-19T02:30:00+02:00</StartBoundary><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType></Principal></Principals>
  <Settings><ExecutionTimeLimit>PT4H</ExecutionTimeLimit><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>true</StartWhenAvailable><WakeToRun>true</WakeToRun></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-File tools/nightly.ps1</Arguments></Exec></Actions>
</Task>
'@
$tx = Read-TaskXml $taskXml
Assert ($tx.Ok -and ($tx.Triggers.Count -eq 1) -and ($tx.Triggers[0].StartBoundary -eq '2026-09-19T02:30:00+02:00') -and ($tx.Arguments -eq '-File tools/nightly.ps1') -and ($tx.LogonType -eq 'InteractiveToken')) 'taskxml-ok' $tx.Error
Assert (-not (Read-TaskXml '<Task><oops').Ok) 'taskxml-malformed'
Assert ((Read-TaskXml '<NotTask/>').Error -eq 'task XML has no Task root') 'taskxml-no-root'
Assert ((Read-TaskXml '<Task><Triggers></Triggers></Task>').Error -eq 'task XML carries no triggers') 'taskxml-no-triggers'

# Test-MissingStart: staleness verdicts.
$now = [datetime]'2026-09-21 10:00:00'
$m = Test-MissingStart ([datetime]'2026-09-21 02:30:01') $now ([datetime]'2026-09-19 12:00:00') '1'
Assert ($m.Verdict -eq 'ok') 'missingstart-ok' $m.Line
$m2 = Test-MissingStart ([datetime]'2026-09-19 02:30:01') $now ([datetime]'2026-09-19 12:00:00') '1'
Assert (($m2.Verdict -eq 'missing') -and ($m2.Line -like '*MISSING*')) 'missingstart-stale'
$m3 = Test-MissingStart $null $now ([datetime]'2026-09-21 09:00:00') ''
Assert ($m3.Verdict -eq 'bootstrap') 'missingstart-bootstrap'
$m4 = Test-MissingStart ([datetime]'1899-12-30') $now ([datetime]'2026-09-18 12:00:00') ''
Assert ($m4.Verdict -eq 'missing') 'missingstart-never-old'
$m5 = Test-MissingStart ([datetime]'2026-09-21 02:30:01') $now ([datetime]'2026-09-19 12:00:00') '0x8007052E'
Assert ($m5.Line -like '*auth-shaped*') 'missingstart-auth'

# Test-TimerLaunch: timer, demand, manual, unknown, midnight wrap.
$tl = Test-TimerLaunch 'powershell.exe' 'taskeng.exe' ([datetime]'2026-09-21 02:30:01') @('02:30') ([datetime]'2026-09-21 02:30:00')
Assert ($tl.Verdict -eq 'timer') 'timerlaunch-timer' $tl.Line
$tl2 = Test-TimerLaunch 'powershell.exe' 'svchost.exe' ([datetime]'2026-09-21 04:13:43') @('02:30') ([datetime]'2026-09-21 04:13:40')
Assert ($tl2.Verdict -eq 'demand') 'timerlaunch-demand' $tl2.Line
$tl3 = Test-TimerLaunch 'powershell.exe' 'explorer.exe' ([datetime]'2026-09-21 02:30:01') @('02:30') ([datetime]'2026-09-21 02:30:00')
Assert ($tl3.Verdict -eq 'manual') 'timerlaunch-manual'
$tl4 = Test-TimerLaunch '' '' ([datetime]'2026-09-21 02:30:01') @('02:30') ([datetime]'2026-09-21 02:30:00')
Assert ($tl4.Verdict -eq 'unknown') 'timerlaunch-unknown'
$tl5 = Test-TimerLaunch 'powershell.exe' 'taskeng.exe' ([datetime]'2026-09-21 00:01:00') @('23:59') ([datetime]'2026-09-21 00:01:00')
Assert ($tl5.Verdict -eq 'timer') 'timerlaunch-wrap' $tl5.Line

# Journal roundtrip plus dead-run probe.
$jr = Join-Path $s16 'journal'
$null = New-Item -ItemType Directory -Force -Path $jr
Assert (-not (Read-RunJournal $jr).Exists) 'journal-missing'
Write-RunJournal $jr '2026-09-21-100000' 4242 ([datetime]'2026-09-21 10:00:00') 'legs'
$jj = Read-RunJournal $jr
Assert (($jj.Ok) -and ($jj.Stamp -eq '2026-09-21-100000') -and ($jj.Pid -eq 4242) -and ($jj.Phase -eq 'legs')) 'journal-roundtrip' $jj.Error
'{broken json' | Set-Content -Path (Join-Path $jr 'current.json') -Encoding UTF8
Assert (-not (Read-RunJournal $jr).Ok) 'journal-corrupt'
'{"stamp":"","phase":"legs","pid":1,"started":"2026-09-21T10:00:00"}' | Set-Content -Path (Join-Path $jr 'current.json') -Encoding UTF8
Assert ((Read-RunJournal $jr).Error -like '*stamp missing*') 'journal-shape'
$dr = Join-Path $s16 'deadrun'
$null = New-Item -ItemType Directory -Force -Path $dr
Assert (-not (Find-DeadRun $dr '2026-09-21-023001').Dead) 'deadrun-no-journal'
Write-RunJournal $dr '2026-09-20-023001' 999199 ([datetime]'2026-09-20 02:30:05') 'legs'
$sd = Join-Path $dr '2026-09-20-023001'; $null = New-Item -ItemType Directory -Force -Path $sd
'' | Set-Content -Path (Join-Path $sd 'run-a-UI.trx') -Encoding UTF8
'' | Set-Content -Path (Join-Path $sd 'run-b.trx') -Encoding UTF8
$d = Find-DeadRun $dr '2026-09-21-023001'
Assert (($d.Dead) -and ($d.Phase -eq 'legs') -and (($d.Evidence -join ';') -like '*2 trx files*')) 'dead-run' $d.Reason
@('# Morning report: 2026-09-20', 'Status: supervisor tombstone') | Set-Content -Path (Join-Path $dr 'morning-2026-09-20.md') -Encoding UTF8
$d2 = Find-DeadRun $dr '2026-09-21-023001'
Assert (($d2.Dead) -and ($d2.Tombstone -like '*morning-2026-09-20.md')) 'dead-run-tombstone'
Write-RunJournal $dr '2026-09-20-023001' $PID (Get-Process -Id $PID).StartTime 'legs'
$d3 = Find-DeadRun $dr '2026-09-21-023001'
Assert ((-not $d3.Dead) -and ($d3.Reason -like '*still alive*')) 'dead-run-live-refused'
Write-RunJournal $dr '2026-09-20-023001' 999199 ([datetime]'2026-09-20 02:30:05') 'final'
Assert (-not (Find-DeadRun $dr '2026-09-21-023001').Dead) 'dead-run-final'
$rec = Format-RecoveryRecord '2026-09-20-023001' 'legs' '2026-09-20 02:30:05' @('stamp dir 2026-09-20-023001', '2 trx files') '' '2026-09-21-023001'
Assert ((($rec -join "`n") -like '*Status: recovered-dead-run*') -and (($rec -join "`n") -like '*Verdict: RED*')) 'recovery-record'
$rec2 = Format-RecoveryRecord '2026-09-20-023001' 'legs' '2026-09-20 02:30:05' @('stamp dir') 'morning-2026-09-20.md' '2026-09-21-023001'
Assert (($rec2 -join "`n") -like '*Tombstone: morning-2026-09-20.md*') 'recovery-tombstone-link'

# Test-RunIdConsistency: five surfaces.
$ir = Join-Path $s16 'ids'
$null = New-Item -ItemType Directory -Force -Path $ir
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ir '2026-09-21-023001')
'2026-09-20-023001' | Set-Content -Path (Join-Path $ir 'latest.txt') -Encoding UTF8
@('# Morning report: 2026-09-20', 'Status: final', '', '- Run identity: 2026-09-20-023001-pid7') | Set-Content -Path (Join-Path $ir 'morning-2026-09-20-023001.md') -Encoding UTF8
$goodInc = @('- INC-abcdef12 `UI.OkTest` x2 (Run A): boom')
$priorGood = Read-LatestReport $ir
Assert ((Test-RunIdConsistency $ir '2026-09-21-023001' 4242 $goodInc $priorGood).Ok) 'ids-clean'
Assert (-not (Test-RunIdConsistency $ir '2026-09-21-999999' 4242 $goodInc $null).Ok) 'ids-missing-dir'
Assert (@((Test-RunIdConsistency $ir 'not-a-stamp' 4242 $goodInc $null).Breaks -like 'identity malformed*').Count -eq 1) 'ids-malformed'
'2026-09-19-023001' | Set-Content -Path (Join-Path $ir 'latest.txt') -Encoding UTF8
$priorBad = Read-LatestReport $ir
Assert (@((Test-RunIdConsistency $ir '2026-09-21-023001' 4242 $goodInc $priorBad).Breaks -like 'pointer continuity*').Count -eq 1) 'ids-pointer'
'2026-09-20-023001' | Set-Content -Path (Join-Path $ir 'latest.txt') -Encoding UTF8
'' | Set-Content -Path (Join-Path $ir 'loser-2026-09-21-023001-pid999.md') -Encoding UTF8
Assert (@((Test-RunIdConsistency $ir '2026-09-21-023001' 4242 $goodInc $null).Breaks -like 'same-second twin*').Count -eq 1) 'ids-twin'
Remove-Item (Join-Path $ir 'loser-2026-09-21-023001-pid999.md') -Force
$collide = @('- INC-abcdef12 `UI.OkTest` x1 (Run A): boom', '- INC-abcdef12 `UI.Other` x1 (Run A): bam')
Assert (@((Test-RunIdConsistency $ir '2026-09-21-023001' 4242 $collide $null).Breaks -like 'incident id collision*').Count -eq 1) 'ids-collision'
Assert (@((Test-RunIdConsistency $ir '2026-09-21-023001' 4242 @('- INC-XYZ broken') $null).Breaks -like 'incident line malformed*').Count -eq 1) 'ids-malformed-line'

# Test-PhaseDurations: baseline compare.
'{"version":1,"phases":{"run-a":{"baseline":600,"warn":1200}}}' | Set-Content -Path (Join-Path $s16 'baseline.json') -Encoding UTF8
$pd = Test-PhaseDurations (Join-Path $s16 'baseline.json') @{ 'run-a' = 100 }
Assert (($pd.Ok) -and (($pd.Lines -join ';') -like '*baseline 600s*')) 'durations-ok'
$pd2 = Test-PhaseDurations (Join-Path $s16 'baseline.json') @{ 'run-a' = 1300 }
Assert (($pd2.Ok) -and (($pd2.Lines -join ';') -like '*WARN over warn 1200s*')) 'durations-warn'
$pd3 = Test-PhaseDurations (Join-Path $s16 'baseline.json') @{ 'run-b' = 50 }
Assert (($pd3.Ok) -and (($pd3.Lines -join ';') -like '*no baseline*')) 'durations-unbaselined'
Assert (-not (Test-PhaseDurations (Join-Path $s16 'no-baseline.json') @{ 'run-a' = 1 }).Ok) 'durations-missing'

# --- D00 T02 §17 fixtures ---
$s17 = Join-Path $dir 's17'
$null = New-Item -ItemType Directory -Force -Path $s17

# Format-ToastXml: escaping plus shape.
$tx = Format-ToastXml 'Nightly <2026>&' @('a<b', 'c&d')
Assert (($tx -like '*&lt;2026&gt;&amp;*') -and ($tx -like '*ToastGeneric*')) 'toast-escape'
$tx2 = Format-ToastXml 't' @('1', '2', '3', '4', '5', '6', '7', '8')
Assert ((@($tx2 -split '<text>').Count) -eq 8) 'toast-truncate'

# Test-ResultFile: versioned shapes.
$goodResult = '{"version":1,"stamp":"2026-09-21-105146","day":"2026-09-21","identity":"2026-09-21-105146-pid1","verdict":"green","exit":0,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"green"},"env":{"os":"10.0"},"timings":{}}'
$goodResult | Set-Content -Path (Join-Path $s17 'good.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'good.result.json')).Ok) 'result-good'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0,"legs":{},"soak":{},"env":{},"timings":{}}' | Set-Content -Path (Join-Path $s17 'empty.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'empty.result.json')).Error -like 'result legs missing*') 'result-emptylegs'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"purple"},"env":{},"timings":{}}' | Set-Content -Path (Join-Path $s17 'badsoak.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'badsoak.result.json')).Error -like 'result soak verdict unknown*') 'result-badsoak'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":1,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"green"},"env":{"os":"o"},"timings":{}}' | Set-Content -Path (Join-Path $s17 'contra.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'contra.result.json')).Error -like 'result verdict green contradicts*') 'result-contra'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"red","exit":0,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"green"},"env":{"os":"o"},"timings":{}}' | Set-Content -Path (Join-Path $s17 'contra2.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'contra2.result.json')).Error -like 'result verdict red contradicts*') 'result-contra2'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"green"},"env":{},"timings":{}}' | Set-Content -Path (Join-Path $s17 'noenv.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'noenv.result.json')).Error -like 'result env unproven*') 'result-noenv'
'{oops' | Set-Content -Path (Join-Path $s17 'bad.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'bad.result.json')).Error -like 'result unreadable*') 'result-badjson'
'{"version":2,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0,"legs":{},"soak":{},"env":{},"timings":{}}' | Set-Content -Path (Join-Path $s17 'v2.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'v2.result.json')).Error -like 'result version 2*') 'result-badversion'
'{"version":1,"stamp":"s","day":"d","identity":"i","exit":0,"legs":{},"soak":{},"env":{},"timings":{}}' | Set-Content -Path (Join-Path $s17 'nofield.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'nofield.result.json')).Error -like 'result missing verdict*') 'result-missingfield'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"purple","exit":1}' | Set-Content -Path (Join-Path $s17 'purple.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'purple.result.json')).Error -like 'unknown verdict*') 'result-badverdict'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"stood-down","exit":0}' | Set-Content -Path (Join-Path $s17 'stood.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'stood.result.json')).Ok) 'result-stooddown'
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0}' | Set-Content -Path (Join-Path $s17 'thin.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'thin.result.json')).Error -like 'result missing legs*') 'result-thin'

# Classify-NightlyOutcome: one route per class.
function New-ClassResult($verdict, $patch) {
  $o = [pscustomobject]@{ verdict = $verdict; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ gate = 0; failed = 0; passed = 1; skipped = 0; killed = $false; cut = $false } }; soak = [pscustomobject]@{ verdict = 'green' } }
  foreach ($k in $patch.Keys) { $o.$k = $patch[$k] }
  return $o
}
Assert ((Classify-NightlyOutcome (New-ClassResult 'red' @{})).Class -eq 'infrastructure') 'class-uncaused'
$rt = New-ClassResult 'red' @{}; $rt.legs.'run-a'.failed = 3
Assert ((Classify-NightlyOutcome $rt).Class -eq 'test') 'class-test'
$rg = New-ClassResult 'red' @{}; $rg.legs.'run-a'.gate = 1
Assert ((Classify-NightlyOutcome $rg).Class -eq 'gate') 'class-gate'
$re = New-ClassResult 'red' @{}; $re.legs | Add-Member -NotePropertyName 'interactive' -NotePropertyValue ([pscustomobject]@{ enforcementRed = $true; failed = 0 }) -Force
Assert ((Classify-NightlyOutcome $re).Class -eq 'enforcement') 'class-enforcement'
Assert ((Classify-NightlyOutcome (New-ClassResult 'red' @{ buildError = 'MSB3027' })).Class -eq 'infrastructure') 'class-infra'
$rk = New-ClassResult 'red' @{}; $rk.legs.'run-a'.killed = $true
Assert ((Classify-NightlyOutcome $rk).Class -eq 'infrastructure') 'class-killed'
$rs = New-ClassResult 'red' @{}; $rs.soak = [pscustomobject]@{ verdict = 'red' }
Assert ((Classify-NightlyOutcome $rs).Class -eq 'degraded-soak') 'class-soak'
Assert ((Classify-NightlyOutcome (New-ClassResult 'green' @{ recovered = '2026-09-20-020000 died at legs' })).Class -eq 'recovery') 'class-recovery'
$rn = New-ClassResult 'red' @{}; $rn.scheduler = [pscustomobject]@{ voted = $true; faults = @('missing start') }
Assert ((Classify-NightlyOutcome $rn).Class -eq 'scheduler-no-start') 'class-nostart'
Assert ((Classify-NightlyOutcome (New-ClassResult 'green' @{})).Class -eq 'green') 'class-green'
Assert ((Classify-NightlyOutcome (New-ClassResult 'stood-down' @{})).Class -eq 'stood-down') 'class-stooddown'
Assert ((Classify-NightlyOutcome ([pscustomobject]@{ verdict = 'bogus' })).Class -eq 'infrastructure') 'class-unreadable'
$rp = New-ClassResult 'red' @{}; $rp.legs.'run-a'.failed = 2; $rp.legs.'run-a'.gate = 1
Assert ((Classify-NightlyOutcome $rp).Class -eq 'gate') 'class-precedence'
$rk2 = New-ClassResult 'green' @{}; $rk2.legs.'run-a' | Add-Member -NotePropertyName 'ran' -NotePropertyValue $false -Force; $rk2.legs.'run-a'.gate = $null
Assert ((Classify-NightlyOutcome $rk2).Class -eq 'green') 'class-skipped-leg'
$ts = [pscustomobject]@{ day = '2026-09-21'; stamp = 'x'; verdict = 'green'; reserve = 1; incidents = @(); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $false } }; soak = [pscustomobject]@{ verdict = 'skipped' }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; env = [pscustomobject]@{ os = 'o'; powershell = 'p'; dotnet = 'd'; session = 's'; topology = 't'; dpi = 'd'; adapters = 'a'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$tsTrend = Format-TrendTable @($ts) @{ Overdue = @(); DueSoon = @() }
Assert ((($tsTrend -join "`n") -like '*no legs ran*')) 'trend-skipped'
$tu = [pscustomobject]@{ day = '2026-09-21'; stamp = 'y'; verdict = 'red'; reserve = 1; incidents = @(); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $true; passed = 0; failed = 0; skipped = 0; gate = $null; killed = $false; cut = $false } }; soak = [pscustomobject]@{ verdict = 'skipped' }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; env = [pscustomobject]@{ os = 'o'; powershell = 'p'; dotnet = 'd'; session = 's'; topology = 't'; dpi = 'd'; adapters = 'a'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$tuTrend = Format-TrendTable @($tu) @{ Overdue = @(); DueSoon = @() }
Assert ((($tuTrend -join "`n") -like '*| unproven |*')) 'trend-unproven'
$tf = [pscustomobject]@{ day = '2026-09-21'; stamp = 'z'; verdict = 'red'; reserve = 1; incidents = @(); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $true; passed = 1; failed = 0; skipped = 0; gate = 0; killed = $false; cut = $false } }; soak = [pscustomobject]@{ verdict = 'red'; failed = @('ui-soak-3', 'protocol-soak-3'); killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; env = [pscustomobject]@{ os = 'o'; powershell = 'p'; dotnet = 'd'; session = 's'; topology = 't'; dpi = 'd'; adapters = 'a'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$tfTrend = Format-TrendTable @($tf) @{ Overdue = @(); DueSoon = @() }
Assert ((($tfTrend -join "`n") -like '*| 2026-09-21 | red | degraded-soak |*') -and ((($tfTrend -join "`n") -split "`n" | Where-Object { $_ -like '| 2026-09-21 |*' } | Select-Object -First 1) -like '*| 2 |*')) 'trend-flakes-array'

# Format-TrendTable: two nights plus a mark.
$t1 = [pscustomobject]@{ day = '2026-09-20'; stamp = '2026-09-20-041343'; verdict = 'green'; reserve = 9000; consumed = 700; timings = [pscustomobject]@{ build = 2; 'run-a' = 600; 'run-b' = 7 }; incidents = @('- INC-aaaabbbb `UI.Flake` x1 (Soak): wobble'); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ gate = 0; failed = 0; passed = 540; skipped = 9; killed = $false; cut = $false; testSeconds = 600 }; 'run-b' = [pscustomobject]@{ gate = 0; failed = 0; passed = 2; skipped = 0; killed = $false; cut = $false; testSeconds = 7 } }; soak = [pscustomobject]@{ verdict = 'green'; failed = @(); killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; env = [pscustomobject]@{ os = '10.0'; powershell = '5.1'; dotnet = '10.0.400'; session = 'u/c'; topology = 'one screen'; dpi = '144x144'; adapters = 'gpu'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$t2 = [pscustomobject]@{ day = '2026-09-21'; stamp = '2026-09-21-023001'; verdict = 'red'; reserve = 12000; incidents = @('- INC-aaaabbbb `UI.Flake` x2 (Run A): wobble'); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ gate = 0; failed = 2; passed = 538; skipped = 9; killed = $false; cut = $false; testSeconds = 700 }; 'run-b' = [pscustomobject]@{ gate = 0; failed = 0; passed = 2; skipped = 0; killed = $false; cut = $false; testSeconds = 8 } }; soak = [pscustomobject]@{ verdict = 'red'; failed = @('ui-soak-3'); killed = @(); cut = @('protocol-soak-4..5') }; quarantine = [pscustomobject]@{ overdue = @('UI.Old'); dueSoon = @(); overdueDetail = @([pscustomobject]@{ Test = 'UI.Old'; Due = '2026-09-19'; Owner = 'op' }) }; env = [pscustomobject]@{ os = '10.0'; powershell = '5.1'; dotnet = '10.0.400'; session = 'u/c'; topology = 'one screen'; dpi = '144x144'; adapters = 'gpu'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$t3 = [pscustomobject]@{ day = '2026-09-21'; stamp = 'loser-x'; verdict = 'stood-down' }
$trend = Format-TrendTable @($t1, $t2, $t3) @{ Overdue = @('UI.Old'); DueSoon = @() }
$tj = $trend -join "`n"
Assert (($tj -like '*| 2026-09-20 | green | green |*') -and ($tj -like '*| 2026-09-21 | red | test |*')) 'trend-rows'
Assert ($tj -like '*stood-down (mark)*') 'trend-mark'
Assert ($tj -like '*Flake recurrence: INC-aaaabbbb*') 'trend-recurrence'
Assert ($tj -like '*p50/median: 700*') 'trend-percentile'
Assert ($tj -like '*## Environments*2026-09-20 2026-09-20-041343*') 'trend-env'
Assert ($tj -like '*Quarantine now: 1 overdue*') 'trend-quar'
Assert ($tj -like '*| 1/0 (oldest 2d) |*') 'trend-qage'
Assert (($tj -like '*| green |*') -and ($tj -like '*| red ui-soak-3 cut=1 |*')) 'trend-soakcell'
Assert ($tj -like '*542/0/9 (98.4%)*') 'trend-rate'
Assert ($tj -like '*phases build=2s run-a=600s run-b=7s; used 700s / left 9000s (span 9700s); RunA 600s rank 1/2 pct 100*') 'trend-budget'
Assert ($tj -like '*2026-09-21-023001: phases no timings; used unknown / left 12000s; RunA 700s rank 2/2 pct 0*') 'trend-budget-partial'
$taTrend = Format-TrendTable @($t1) @{ Overdue = @([pscustomobject]@{ Test = 'UI.Old'; Due = '2026-09-17' }); DueSoon = @() } ([datetime]'2026-09-21')
Assert ((($taTrend -join "`n") -like '*Quarantine now: 1 overdue, oldest 4d: UI.Old, 0 due within 3 days*')) 'trend-oldest'

# Test-RedAcknowledged: set difference.
Assert ((Test-RedAcknowledged @('2026-09-20', '2026-09-21') @('2026-09-20', '2026-09-21')).Ok) 'ack-covered'
Assert (@((Test-RedAcknowledged @('2026-09-20', '2026-09-21') @('2026-09-20')).Unacked) -join ',' -eq '2026-09-21') 'ack-uncovered'

# Test-AckFile: owner plus day plus substance, never presence alone.
$ackGood = '# RED acknowledgement: 2026-09-20' + "`n`n" + 'Owner: operator. Signed: 2026-09-21. Run A 545/1/3 with UI.DirtyPromptTests failing on a COM timeout; Interactive 24/3/1 with two PinnedTabs NotNull failures plus one SessionRestore diff. Class infrastructure on legacy gate prose. Follow-up: quarantine on recurrence.'
$ackGood | Set-Content -Path (Join-Path $s17 'ack-good.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-good.md') '2026-09-20').Ok) 'ack-good'
'' | Set-Content -Path (Join-Path $s17 'ack-empty.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-empty.md') '2026-09-20').Ok -eq $false) 'ack-empty'
'Owner: nobody. Signed: 2026-09-21. A failure happened somewhere on some night, details to follow in a later revision of this file.' | Set-Content -Path (Join-Path $s17 'ack-noday.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-noday.md') '2026-09-20').Error -like 'ack names no day*') 'ack-noday'
'# RED acknowledgement: 2026-09-20, no owner named here but the text runs long enough to pass the substance floor with room to spare for this fixture.' | Set-Content -Path (Join-Path $s17 'ack-noowner.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-noowner.md') '2026-09-20').Error -like 'ack names no owner*') 'ack-noowner'
'Owner: operator. 2026-09-20 ack.' | Set-Content -Path (Join-Path $s17 'ack-short.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-short.md') '2026-09-20').Error -like 'ack too short*') 'ack-short'
$ackTbd = 'Owner: TBD. This acknowledgement for 2026-09-20 carries more than two hundred characters of carefully worded placeholder prose that names no failures and no cause, proving only that length plus owner-shape cannot catch a determined filler.'
$ackTbd | Set-Content -Path (Join-Path $s17 'ack-tbd.md') -Encoding UTF8
Assert ((Test-AckFile (Join-Path $s17 'ack-tbd.md') '2026-09-20').Error -like 'ack owner is a placeholder*') 'ack-tbd'

# Read-RawLines: provider decoration stripped, JSON stays small.
$rawFx = Join-Path $dir 'raw.txt'
@('- Trigger: manual (parent powershell.exe)', '| Run A (default) | 1 passed, 0 failed, 0 skipped |') | Set-Content -Path $rawFx -Encoding UTF8
$rawGot = @(Read-RawLines $rawFx)
Assert ($rawGot.Count -eq 2) 'rawline-count' ("got $($rawGot.Count)")
Assert ((@($rawGot[0].PSObject.Properties.Name) -join ',') -eq 'Length') 'rawline-stripped' (@($rawGot[0].PSObject.Properties.Name) -join ',')
if ((@($rawGot[0].PSObject.Properties.Name) -join ',') -eq 'Length') {
  $rawJson = ConvertTo-Json $rawGot[0] -Depth 8 -Compress
  Assert (($rawJson -notlike '*ReadCount*') -and ($rawJson -notlike '*PSProvider*') -and ($rawJson.Length -lt 500)) 'rawline-json-small' ("len $($rawJson.Length)")
} else { Assert $false 'rawline-json-small' 'skipped: strip regressed (serializing would hang, not fail)' }
Assert ((@(Read-RawLines (Join-Path $dir 'missing.txt')).Count -eq 0)) 'rawline-missing-empty'

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyParse.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyParse.Tests: all green'
exit 0
