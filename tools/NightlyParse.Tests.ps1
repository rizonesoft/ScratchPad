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
$conGreen = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $false
Assert ($conGreen.Ok -eq $true) 'conservation-green' ($conGreen.Breaks -join '|')
$exoticTrx = '<TestRun><Results><UnitTestResult testName="UI.A" outcome="Passed" /><UnitTestResult testName="UI.B" outcome="Inconclusive" /></Results></TestRun>'
$exoticTrx | Set-Content -Path (Join-Path $dir 'exotic.trx') -Encoding UTF8
$conExotic = Test-CountConservation 'Fix' (Join-Path $dir 'exotic.trx') (Join-Path $dir 'missing.log') $false
Assert (($conExotic.Ok -eq $false) -and (($conExotic.Breaks -join '') -like '*exotic outcomes (Inconclusive)*')) 'conservation-exotic' ($conExotic.Breaks -join '|')
@('Passed!  - Failed:     1, Passed:     1, Skipped:     1, Total:     9, Duration: 1 s - UI.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'badrow.log') -Encoding UTF8
$conRow = Test-CountConservation 'Fix' (Join-Path $dir 'missing.trx') (Join-Path $dir 'badrow.log') $false
Assert (($conRow.Ok -eq $false) -and (($conRow.Breaks -join '') -like '*1+1+1 != Total 9*')) 'conservation-row' ($conRow.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     2, Skipped:     1, Total:     3, Duration: 1 s - UI.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'cross.log') -Encoding UTF8
$conCross = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'cross.log') $false
Assert (($conCross.Ok -eq $false) -and (($conCross.Breaks -join '') -like '*cross-level*')) 'conservation-cross' ($conCross.Breaks -join '|')
$conVacuous = Test-CountConservation 'Fix' (Join-Path $dir 'missing.trx') (Join-Path $dir 'missing.log') $false
Assert ($conVacuous.Ok -eq $true) 'conservation-vacuous'
$conMulti = Test-CountConservation 'Fix' $trx $log $false
Assert ($conMulti.Ok -eq $true) 'conservation-multi' ($conMulti.Breaks -join '|')
$conExpected = Test-CountConservation 'Run B' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $true
Assert ($conExpected.Ok -eq $true) 'conservation-expected-green' ($conExpected.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 1 s - Smoke.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'partial.log') -Encoding UTF8
$conMissing = Test-CountConservation 'Run A' (Join-Path $dir 'missing.trx') (Join-Path $dir 'partial.log') $true
Assert (($conMissing.Ok -eq $false) -and (($conMissing.Breaks -join '') -like '*UI.dll missing*')) 'conservation-missing' ($conMissing.Breaks -join '|')
$conUnknown = Test-CountConservation 'Fix' (Join-Path $dir 'ok.trx') (Join-Path $dir 'ok.log') $true
Assert (($conUnknown.Ok -eq $false) -and (($conUnknown.Breaks -join '') -like '*unknown leg*')) 'conservation-unknown-leg' ($conUnknown.Breaks -join '|')

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

# Failed-without-trx plus exit-0-without-trx iterations land unproven
# rows; an all-failed ledger never prints the empty shape.
$failDir = Join-Path $dir 'soakfailed'
$null = New-Item -ItemType Directory -Force -Path $failDir
$fail = Format-SoakLedger $failDir @() @() @('ui-soak-2') $true
Assert (($fail.Failed -eq $true) -and ((($fail.Rows -join "`n") -like '*ui-soak-2 : no trx (failed without trx*'))) 'soak-failed-no-trx' ($fail.Rows -join '|')
Assert ((($fail.Rows -join "`n") -like '*ui-soak-1 : no trx despite exit 0*')) 'soak-exit0-no-trx' ($fail.Rows -join '|')
Assert ((($fail.Rows -join "`n") -notlike '*no soak iterations ran*')) 'soak-failed-never-empty' ($fail.Rows -join '|')

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
$mergeCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'run-a-Unit.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-Unit.out.log')) $false
Assert ($mergeCon.Ok -eq $true) 'merge-conservation-green' ($mergeCon.Breaks -join '|')
@('Passed!  - Failed:     0, Passed:     9, Skipped:     1, Total:     10, Duration: 1 s - Unit.dll (net10.0)') | Set-Content -Path (Join-Path $dir 'merge-skew.out.log') -Encoding UTF8
$skewCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'run-a-Unit.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-skew.out.log')) $false
Assert (($skewCon.Ok -eq $false) -and (($skewCon.Breaks -join '') -like '*cross-level-aggregate*')) 'merge-conservation-skew' ($skewCon.Breaks -join '|')
$killedCon = Test-CountConservation 'Run A' @((Join-Path $dir 'run-a-Smoke.trx'), (Join-Path $dir 'missing-step.trx')) @((Join-Path $dir 'merge-Smoke.out.log'), (Join-Path $dir 'merge-Unit.out.log')) $false
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

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyParse.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyParse.Tests: all green'
exit 0
