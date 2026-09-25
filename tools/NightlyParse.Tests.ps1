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
<UnitTestResult testName="UI.HookTest" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: Low-level mouse hooks are unavailable on this host (Win32 error 5); owner D01 T01 SECT3; owed on a host whose policy allows low-level mouse hooks.</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.PrinterTest" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: No printers enumerated in this context (agent context is printer-blind); owner D01 T02 SECT5; owed on a session where the spooler is visible.</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LegacyHookTest" outcome="NotExecuted"><Output><ErrorInfo><Message>Low-level mouse hooks are unavailable on this host (Win32 error 5).</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.BareSkip" outcome="NotExecuted"><Output><ErrorInfo><Message>TEMPORARY: unclassified skip</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.QuietSkip" outcome="NotExecuted"><Output><ErrorInfo><Message>Outside the quiet-hours window</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.FailedTest" outcome="Failed"><Output><ErrorInfo><Message>boom</Message></ErrorInfo></Output></UnitTestResult>
</Results></TestRun>
'@
$trx = Join-Path $dir 'fixture.trx'
# The section sign by code point (this script reads as ANSI on 5.1).
$trxXml.Replace('SECT', [string][char]0xA7) | Set-Content -Path $trx -Encoding UTF8

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
# D00 T02 §44 item 3: owned capability skips are explained; the
# ownerless legacy form now reads unexplained and reds the leg.
Assert (($enf.Ok -eq $true) -and ($leaked.Count -eq 3) -and ($leaked -contains 'UI.BareSkip') -and ($leaked -contains 'UI.QuietSkip') -and ($leaked -contains 'UI.LegacyHookTest')) 'skip-classes' ($leaked -join ',')

# Strict matching: prose mentioning the tokens cannot self-allowlist;
# stamps need shape, codes need case, legacy anchors to the start.
$trxXml2 = @'
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
<UnitTestResult testName="UI.StampOk" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-20 D01-T01-S9 fixture-quarantine</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.MidQuarantine" outcome="NotExecuted"><Output><ErrorInfo><Message>flaky, QUARANTINED candidate, needs triage</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.DatelessStamp" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED incident without fields</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.CodedOk" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: Default printer is hardware (USB001); owner D01 T02 SECT5; owed on a host whose default printer is virtual (PDF or XPS).</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.CodedNoOwner" outcome="NotExecuted"><Output><ErrorInfo><Message>CAPABILITY: Default printer is hardware</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LowerCapability" outcome="NotExecuted"><Output><ErrorInfo><Message>capability: hooks unavailable</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.MidLegacy" outcome="NotExecuted"><Output><ErrorInfo><Message>Error: No printers enumerated in this context (nested)</Message></ErrorInfo></Output></UnitTestResult>
<UnitTestResult testName="UI.LegacyPrefix" outcome="NotExecuted"><Output><ErrorInfo><Message>Default printer is hardware (USB001)</Message></ErrorInfo></Output></UnitTestResult>
</Results></TestRun>
'@
$trx2 = Join-Path $dir 'msgs.trx'
$trxXml2.Replace('SECT', [string][char]0xA7) | Set-Content -Path $trx2 -Encoding UTF8
$enf2 = Get-NonQuarantineSkips $trx2
$leaked2 = @($enf2.Names)
Assert (($enf2.Ok -eq $true) -and ($leaked2.Count -eq 6) -and ($leaked2 -contains 'UI.MidQuarantine') -and ($leaked2 -contains 'UI.DatelessStamp') -and ($leaked2 -contains 'UI.LowerCapability') -and ($leaked2 -contains 'UI.MidLegacy') -and ($leaked2 -contains 'UI.CodedNoOwner') -and ($leaked2 -contains 'UI.LegacyPrefix') -and ($leaked2 -notcontains 'UI.CodedOk')) 'skip-strict' ($leaked2 -join ',')

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

# Incidents: soak iterations of one suite merge under a stable ID (the
# D00 T02 §22 contract; the unknown-shape fallback collapses decimals).
$incIn = @(
  [pscustomobject]@{ Test = 'UI.Flaky'; Message = 'flake attempt 3 of 10'; Where = 'ui-soak-3' },
  [pscustomobject]@{ Test = 'UI.Flaky'; Message = 'flake attempt 5 of 10'; Where = 'ui-soak-5' },
  [pscustomobject]@{ Test = 'UI.Other'; Message = 'boom'; Where = 'Run A' }
)
$inc = @(Format-Incidents $incIn)
Assert ($inc.Count -eq 2) 'incident-group-count' ($inc -join '|')
Assert ($inc[0] -eq '- INC-7ecec91d `UI.Flaky` x2 (ui-soak-3, ui-soak-5): flake attempt 3 of 10') 'incident-dedupe-line' $inc[0]
Assert ($inc[1] -eq '- INC-5fe0f954 `UI.Other` x1 (Run A): boom') 'incident-single-line' $inc[1]
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
@('schema: population/2', 'run-a-filter: Category!=Interactive&Category!=Primary', 'run-b-filter: Category=Primary', 'interactive-filter: Category=Interactive', 'run-a-methods: 2', 'run-a-cases: 3', 'run-b:', '  UI.B.P1', 'run-b-methods: 1', 'run-b-cases: 1', 'interactive:', '  UI.C.I1', 'interactive-methods: 1', 'interactive-cases: 1') | Set-Content -Path (Join-Path $dir 'pop-noruna.fingerprint') -Encoding UTF8
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
@('schema: population/2', 'run-a-filter: Category!=Interactive&Category!=Primary') | Set-Content -Path (Join-Path $dir 'pop-bad.fingerprint') -Encoding UTF8
$popBad = Compare-TestPopulation (Join-Path $dir 'pop-bad.fingerprint') $fakeNightly $fpDisc
Assert (($popBad.Ok -eq $false) -and (($popBad.Drifts -join '') -like '*missing run-b-filter*')) 'fingerprint-malformed' ($popBad.Drifts -join '|')


# Nightly evidence residuals (D00 T02 section 30).
$sec5 = "D02 T01 $([char]0xA7)5"
# Item 1: staged captures publish only after the scan.
$capDir = Join-Path $dir 'captures-stage'
$null = New-Item -ItemType Directory -Force -Path $capDir
$cleanNotes = @(Publish-TextCapture $capDir 'x-windows.txt' @('pid=1 app: [title redacted]') 'x')
Assert ((Test-Path (Join-Path $capDir 'x-windows.txt')) -and (-not (Test-Path (Join-Path $capDir '.staging'))) -and ($cleanNotes.Count -eq 0)) 'staging-clean-publishes-and-leaves-no-stage' ($cleanNotes -join '|')
$hitNotes = @(Publish-TextCapture $capDir 'x-events.txt' @('token = ' + 'ghp_' + ('A1b2C3d4E5' * 4)) 'x')
$hitText = Get-Content (Join-Path $capDir 'x-events.txt') -Raw
Assert (($hitText -like '*capture redacted by the secret scan: github-token*') -and ($hitText -notlike '*ghp_*') -and (-not (Test-Path (Join-Path $capDir '.staging'))) -and (($hitNotes -join '') -like '*SECRET-SCAN redacted x-events.txt*')) 'staging-hit-never-renamed' $hitText
$null = New-Item -ItemType Directory -Force -Path (Join-Path $capDir '.staging')
'unscanned' | Set-Content -Path (Join-Path $capDir '.staging\left.txt') -Encoding UTF8
$retain = Test-RetainableCaptures $dir
Assert (($retain.Ok -eq $false) -and (($retain.Reasons -join '') -like '*captures-stage/.staging holds unscanned staged captures*')) 'staging-leftover-refuses-retain' ($retain.Reasons -join '|')
$protNotes = @(Protect-CaptureDir $capDir 'x')
Assert ((-not (Test-Path (Join-Path $capDir '.staging'))) -and (($protNotes -join '') -like '*leftover staged captures deleted unscanned*')) 'staging-leftover-deleted-by-protect' ($protNotes -join '|')
Remove-Item $capDir -Recurse -Force
# Item 2: the aggregate budget drops screenshots, then dumps, then text.
$runDir = Join-Path $dir 'budget-run'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'captures-run-a'), (Join-Path $runDir 'captures-soak-ui-1')
[System.IO.File]::WriteAllBytes((Join-Path $runDir 'captures-run-a\run-a-failure.png'), (New-Object byte[] 4000))
[System.IO.File]::WriteAllBytes((Join-Path $runDir 'captures-soak-ui-1\testhost.dmp'), (New-Object byte[] 3000))
[System.IO.File]::WriteAllBytes((Join-Path $runDir 'captures-run-a\run-a-events.txt'), (New-Object byte[] 1000))
$budgetNotes = @(Limit-RunCaptureBudget $runDir 2500)
$markerText = Get-Content (Join-Path $runDir 'CAPTURE-BUDGET-TRUNCATED.txt') -Raw
Assert ((-not (Test-Path (Join-Path $runDir 'captures-run-a\run-a-failure.png'))) -and (-not (Test-Path (Join-Path $runDir 'captures-soak-ui-1\testhost.dmp'))) -and (Test-Path (Join-Path $runDir 'captures-run-a\run-a-events.txt')) -and ($markerText -like '*screenshots, then dumps, then text*run-a-failure.png (4000 bytes)*testhost.dmp (3000 bytes)*') -and (($budgetNotes -join '') -like '*TRUNCATED to 1000 of 2500 bytes; dropped 2 file(s)*')) 'budget-drops-in-stated-order-with-marker' (($budgetNotes -join '|') + ' / ' + $markerText)
Assert (@(Limit-RunCaptureBudget $runDir 2500).Count -eq 0) 'budget-under-cap-is-silent'
# Item 4: a missing ledger reds when earlier results carry incidents,
# and the rebuild restores them from the results.
$ledDir = Join-Path $dir 'ledger-fx'
$null = New-Item -ItemType Directory -Force -Path $ledDir
[pscustomobject]@{ version = 1; stamp = '2026-09-26-023001'; incidents = @('- INC-1a2b3c4d `UI.X.Y` x2 (ui-soak-1, ui-soak-3): Assert.NotNull() Failure') } | ConvertTo-Json | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-26-023001.result.json') -Encoding UTF8
[pscustomobject]@{ version = 1; stamp = '2026-09-27-023001'; incidents = @('- INC-1a2b3c4d `UI.X.Y` x1 (ui-soak-2): Assert.NotNull() Failure') } | ConvertTo-Json | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-27-023001.result.json') -Encoding UTF8
[pscustomobject]@{ version = 1; stamp = '2026-09-22-023001'; incidents = @('- INC-cd55f7ca `UI.Old.T` x1 (ui-soak-1): old') } | ConvertTo-Json | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-22-023001.result.json') -Encoding UTF8
$resFiles = @(Get-ChildItem $ledDir -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName })
$pres = Test-IncidentLedgerPresence (Join-Path $ledDir 'incidents.json') $resFiles '2026-09-25-000000'
Assert (($pres.Ok -eq $false) -and ($pres.Error -like 'incident ledger missing while 2 earlier result(s) carry incidents (latest 2026-09-27-023001); rebuild: *tools/NightlyLedger.ps1 -Rebuild')) 'ledger-missing-reds-with-rebuild' $pres.Error
Assert ((Test-IncidentLedgerPresence (Join-Path $ledDir 'incidents.json') @($resFiles | Where-Object { $_ -like '*09-22*' }) '2026-09-25-000000').Ok -eq $true) 'ledger-missing-before-v2-reads-empty'
$rebuilt = New-IncidentLedgerFromResults $resFiles '2026-09-25-000000' @{} @{}
Assert (($rebuilt.Count -eq 1) -and (@($rebuilt['INC-1a2b3c4d'].occurrences).Count -eq 2) -and ($rebuilt['INC-1a2b3c4d'].firstSeen -eq '2026-09-26-023001') -and ($rebuilt['INC-1a2b3c4d'].owner -eq 'operator')) 'ledger-rebuild-restores-occurrences' (($rebuilt.Keys) -join ',')
$errW = Write-IncidentLedger $rebuilt (Join-Path $ledDir 'incidents.json')
Assert (($errW -eq '') -and ((Test-IncidentLedgerPresence (Join-Path $ledDir 'incidents.json') $resFiles '2026-09-25-000000').Ok)) 'ledger-rebuilt-reads-present' $errW
# Items 6, 7, 10: default owner with a due date, finding links, the
# unlinked re-list, and the lifecycle block.
$g1 = [pscustomobject]@{ Id = 'INC-0000000a'; Test = 'UI.A.Owned'; Phase = 'run-a'; Key = 'k1'; Wheres = @('Run A') }
$g2 = [pscustomobject]@{ Id = 'INC-0000000b'; Test = 'UI.A.Stray'; Phase = 'run-a'; Key = 'k2'; Wheres = @('Run A') }
$upd = Update-IncidentLedger @{} @($g1, $g2) '2026-09-26-023001' @{} @{ 'UI.A.Owned' = $sec5 } 3 @{ 'INC-0000000a' = $sec5 }
Assert (($upd.Incidents['INC-0000000b'].owner -eq 'operator') -and ($upd.Incidents['INC-0000000b'].due -eq '2026-09-28') -and (($upd.Lines -join '') -like '*INC-0000000b ``UI.A.Stray``: new (owner operator, triage due 2026-09-28)*')) 'unowned-incident-routes-to-triage-owner' ($upd.Lines -join '|')
$unl = @(Format-UnlinkedIncidents $upd.Incidents)
Assert (($unl.Count -eq 1) -and ($unl[0] -like '*INC-0000000b*') -and ($unl[0] -notlike '*INC-0000000a*')) 'unlinked-open-incident-relists' ($unl -join '|')
$upd2 = Update-IncidentLedger $upd.Incidents @() '2026-09-27-023001' @{} @{} 3 @{ 'INC-0000000a' = $sec5; 'INC-0000000b' = 'abc1234' }
Assert (@(Format-UnlinkedIncidents $upd2.Incidents).Count -eq 0) 'linked-incident-stops-relisting'
$legacy = @{ 'INC-0000000c' = [pscustomobject]@{ id = 'INC-0000000c'; test = 'UI.L'; phase = 'run-a'; key = ''; owner = 'unassigned'; state = 'open'; firstSeen = '2026-09-26-023001'; lastSeen = '2026-09-26-023001'; closedAt = ''; closedBy = ''; occurrences = @([pscustomobject]@{ stamp = '2026-09-26-023001'; wheres = @('Run A') }); passStreak = 0; lastPassStamp = '' } }
$upd3 = Update-IncidentLedger $legacy @() '2026-09-27-023001' @{} @{} 3 @{}
Assert (($upd3.Incidents['INC-0000000c'].owner -eq 'operator') -and ($upd3.Incidents['INC-0000000c'].due -eq '2026-09-28')) 'legacy-unassigned-upgrades-to-triage-owner'
$life = @(ConvertTo-IncidentLifecycle $upd2.Incidents)
$lifeRes = Join-Path $dir 'life.result.json'
$lifeObj = [pscustomobject]@{ version = 1; stamp = 's'; day = 'd'; identity = 'i'; verdict = 'stood-down'; exit = 0; incidentLifecycle = $life; incidentLifecycleSource = 'ledger' }
$lifeObj | ConvertTo-Json -Depth 6 | Set-Content -Path $lifeRes -Encoding UTF8
Assert (((Test-ResultFile $lifeRes).Ok -eq $true) -and ($life.Count -eq 2) -and ($life[0].contract -eq 'v2') -and ($life[0].finding -eq $sec5)) 'lifecycle-block-validates' (Test-ResultFile $lifeRes).Error
$lifeObj.incidentLifecycle = @([pscustomobject]@{ id = 'INC-0000000a'; test = 'UI.A.Owned'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('s1'); firstSeen = 's1'; contract = 'v2' })
$lifeObj | ConvertTo-Json -Depth 6 | Set-Content -Path $lifeRes -Encoding UTF8
Assert (((Test-ResultFile $lifeRes).Ok -eq $false) -and ((Test-ResultFile $lifeRes).Error -like '*incidentLifecycle row INC-0000000a missing passStreak*')) 'lifecycle-missing-field-fails' (Test-ResultFile $lifeRes).Error
# R1-F2: lifecycle values validate, not only presence.
foreach ($bad in @(@{ occurrences = -1 }, @{ passStreak = 'x' }, @{ contract = 'v9' }, @{ due = '26-09-2026' })) {
  $row = [ordered]@{ id = 'INC-0000000a'; test = 'UI.A.Owned'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('s1'); firstSeen = 's1'; passStreak = 0; contract = 'v2'; due = ''; finding = '' }
  foreach ($k in $bad.Keys) { $row[$k] = $bad[$k] }
  $lifeObj.incidentLifecycle = @([pscustomobject]$row)
  $lifeObj | ConvertTo-Json -Depth 6 | Set-Content -Path $lifeRes -Encoding UTF8
  $bk = @($bad.Keys)[0]
  Assert (((Test-ResultFile $lifeRes).Ok -eq $false) -and ((Test-ResultFile $lifeRes).Error -like "*$bk*")) "lifecycle-bad-$bk-fails" (Test-ResultFile $lifeRes).Error
}
# R5-F1: a duplicate incident id fails the lifecycle block.
$dupRow = [pscustomobject]@{ id = 'INC-0000000a'; test = 'UI.A.Owned'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('s1'); firstSeen = 's1'; passStreak = 0; contract = 'v2'; due = ''; finding = '' }
$lifeObj.incidentLifecycle = @($dupRow, $dupRow)
$lifeObj | ConvertTo-Json -Depth 6 | Set-Content -Path $lifeRes -Encoding UTF8
Assert (((Test-ResultFile $lifeRes).Ok -eq $false) -and ((Test-ResultFile $lifeRes).Error -eq 'result incidentLifecycle duplicate id INC-0000000a')) 'lifecycle-duplicate-id-fails' (Test-ResultFile $lifeRes).Error
# R1-I1: the rebuild restores the latest lifecycle snapshot.
[pscustomobject]@{ version = 1; stamp = '2026-09-28-023001'; day = '2026-09-28'; identity = '2026-09-28-023001-pid1'; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycle = @([pscustomobject]@{ id = 'INC-1a2b3c4d'; test = 'UI.X.Y'; phase = 'soak'; state = 'closed'; owner = $sec5; occurrences = 3; occurrenceStamps = @('2026-09-25-023001', '2026-09-26-023001', '2026-09-27-023001'); firstSeen = '2026-09-25-023001'; lastSeen = '2026-09-27-023001'; passStreak = 3; contract = 'v2'; due = ''; finding = 'abc1234' }, [pscustomobject]@{ id = 'INC-0000aced'; test = 'UI.Aged.T'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('2026-09-25-120000'); firstSeen = '2026-09-25-120000'; lastSeen = '2026-09-25-120000'; passStreak = 1; contract = 'v2'; due = '2026-09-27'; finding = '' }) } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-28-023001.result.json') -Encoding UTF8
[pscustomobject]@{ version = 1; stamp = '2026-09-29-023001'; incidents = @(); incidentLifecycleSource = 'unavailable'; incidentLifecycle = @() } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-29-023001.result.json') -Encoding UTF8
$snapFiles = @(Get-ChildItem $ledDir -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName })
$snapMap = New-IncidentLedgerFromResults $snapFiles '2026-09-25-000000' @{} @{}
$se = $snapMap['INC-1a2b3c4d']
Assert (($se.state -eq 'closed') -and ($se.passStreak -eq 3) -and ($se.finding -eq 'abc1234') -and ($se.closedAt -eq '2026-09-28-023001') -and (@($se.occurrences).Count -eq 3) -and ($se.firstSeen -eq '2026-09-25-023001')) 'ledger-rebuild-restores-snapshot-past-an-unavailable-run' "$($se.state) $($se.passStreak) $($se.finding) $($se.closedAt) $(@($se.occurrences).Count)"
$ag = $snapMap['INC-0000aced']
Assert (($null -ne $ag) -and ($ag.test -eq 'UI.Aged.T') -and ($ag.passStreak -eq 1) -and ($ag.due -eq '2026-09-27') -and (@($ag.occurrences).Count -eq 1)) 'ledger-rebuild-restores-aged-out-incident' "$($ag.test) $($ag.passStreak)"
# R3-F2: a closed incident that recurs after the snapshot (during a
# ledger-unavailable run) rebuilds reopened with its later occurrence.
[pscustomobject]@{ version = 1; stamp = '2026-09-30-023001'; incidents = @('- INC-1a2b3c4d `UI.X.Y` x1 (ui-soak-1): Assert.NotNull() Failure'); incidentLifecycleSource = 'unavailable'; incidentLifecycle = @() } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $ledDir 'morning-2026-09-30-023001.result.json') -Encoding UTF8
$reFiles = @(Get-ChildItem $ledDir -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName })
$reMap = New-IncidentLedgerFromResults $reFiles '2026-09-25-000000' @{} @{}
$re = $reMap['INC-1a2b3c4d']
Assert (($re.state -eq 'open') -and ($re.passStreak -eq 0) -and (@($re.occurrences).Count -eq 4) -and ($re.lastSeen -eq '2026-09-30-023001') -and ($re.closedAt -eq '') -and ($re.finding -eq 'abc1234')) 'ledger-rebuild-replays-recurrence-after-snapshot' "$($re.state) $($re.passStreak) $(@($re.occurrences).Count) $($re.lastSeen)"
Remove-Item (Join-Path $ledDir 'morning-2026-09-30-023001.result.json')
# R3-F1: with the failure results aged out, a surviving snapshot still
# makes a missing ledger red.
$snapOnly = Join-Path $dir 'ledger-snaponly'
$null = New-Item -ItemType Directory -Force -Path $snapOnly
Copy-Item (Join-Path $ledDir 'morning-2026-09-28-023001.result.json') $snapOnly
$soPres = Test-IncidentLedgerPresence (Join-Path $snapOnly 'incidents.json') @(Get-ChildItem $snapOnly -Filter '*.result.json' | ForEach-Object { $_.FullName }) '2026-09-25-000000'
Assert (($soPres.Ok -eq $false) -and ($soPres.Error -like 'incident ledger missing while the 2026-09-28-023001 lifecycle snapshot holds 2 incident(s); rebuild:*')) 'ledger-missing-with-snapshot-only-reds' $soPres.Error
# R4-F1: an invalid newest snapshot fails the rebuild and the presence
# check instead of thinning history.
[pscustomobject]@{ version = 1; stamp = '2026-10-01-023001'; day = '2026-10-01'; identity = '2026-10-01-023001-pid1'; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycle = @([pscustomobject]@{ id = 'INC-1a2b3c4d'; state = 'closed'; owner = 'operator'; occurrences = 3; passStreak = 3; contract = 'v2' }) } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $ledDir 'morning-2026-10-01-023001.result.json') -Encoding UTF8
$badFiles = @(Get-ChildItem $ledDir -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName })
$badThrow = ''
try { $null = New-IncidentLedgerFromResults $badFiles '2026-09-25-000000' @{} @{} } catch { $badThrow = $_.Exception.Message }
Assert ($badThrow -like 'rebuild refused: lifecycle snapshot 2026-10-01-023001 (*) is invalid: result incidentLifecycle row INC-1a2b3c4d missing test*') 'ledger-rebuild-refuses-invalid-snapshot' $badThrow
$badPres = Test-IncidentLedgerPresence (Join-Path $ledDir 'missing.json') $badFiles '2026-09-25-000000'
Assert (($badPres.Ok -eq $false) -and ($badPres.Error -like '*lifecycle snapshot 2026-10-01-023001 (*) is invalid*')) 'ledger-presence-counts-invalid-snapshot' $badPres.Error
Remove-Item (Join-Path $ledDir 'morning-2026-10-01-023001.result.json')
$agErr = Write-IncidentLedger $snapMap (Join-Path $ledDir 'rebuilt.json')
Assert ($agErr -eq '') 'ledger-rebuild-with-snapshot-writes-back' $agErr
# Item 3: release candidates name the oldest exemptions and citations.
$wsR = Join-Path $dir 'ws-release'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $wsR 'build\nightly\retained\fx-old'), (Join-Path $wsR 'build\nightly\2026-09-21-023001'), (Join-Path $wsR 'docs'), (Join-Path $wsR 'todo')
'x' | Set-Content -Path (Join-Path $wsR 'build\nightly\retained\fx-old\a.txt')
(Get-Item (Join-Path $wsR 'build\nightly\retained\fx-old')).LastWriteTimeUtc = [datetime]::new(2026, 9, 20, 0, 0, 0, [DateTimeKind]::Utc)
'kept' | Set-Content -Path (Join-Path $wsR 'build\nightly\2026-09-21-023001\KEEP.txt')
@('# Review', 'Live proof cites retained run fx-old here.') | Set-Content -Path (Join-Path $wsR 'docs\review.md') -Encoding UTF8
$cands = @(Get-KeepReleaseCandidates (Join-Path $wsR 'build\nightly\retained') (Join-Path $wsR 'build\nightly') $wsR 3)
Assert (($cands.Count -eq 2) -and ($cands[0] -like 'retained/fx-old (2026-09-20, * MB; cited by docs/review.md:2)') -and ($cands[1] -like 'kept/2026-09-21-023001 (*; cited by nothing tracked)')) 'quota-release-candidates-name-citations' ($cands -join ' | ')

# Gate before the night (D00 T02 section 29): methods-only drift on the
# run-b and interactive legs fails, the 2026-09-25 drift line
# reproduces exactly, discovery forces the fence open so a daytime
# listing expands fenced Theories, and a stale build refuses.
$methOnly = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 2; RunBCases = 1; InteractiveMethods = 3; InteractiveCases = 1 }
$popMeth = Compare-TestPopulation $fpFile $fakeNightly $methOnly
Assert (($popMeth.Ok -eq $false) -and (($popMeth.Drifts -join '|') -like '*run-b-methods: fingerprinted 1 vs discovered 2*') -and (($popMeth.Drifts -join '|') -like '*interactive-methods: fingerprinted 1 vs discovered 3*')) 'fingerprint-methods-only-drift' ($popMeth.Drifts -join '|')
$d37 = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 37 }
$fp37 = Join-Path $dir 'pop37.fingerprint'
Write-TestPopulationFile $fp37 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $d37
$d42 = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 42 }
$pop42 = Compare-TestPopulation $fp37 $fakeNightly $d42
Assert (($pop42.Ok -eq $false) -and (('population drift: ' + ($pop42.Drifts -join '; ')) -eq 'population drift: interactive-cases: fingerprinted 37 vs discovered 42')) 'fingerprint-reproduces-2026-09-25' ($pop42.Drifts -join '|')
$stubEnv = Join-Path $dir 'stub-env.ps1'
@('param([Parameter(ValueFromRemainingArguments = $true)]$rest)', "'    UI.Env.Force' + `$env:SCRATCHPAD_INTERACTIVE_FORCE") | Set-Content -Path $stubEnv -Encoding UTF8
$priorForce = $env:SCRATCHPAD_INTERACTIVE_FORCE
$env:SCRATCHPAD_INTERACTIVE_FORCE = 'operator-value'
$envList = Get-ListTestsCases $stubEnv (Join-Path $dir 'UI.csproj') 'anything' 'stubenv'
$afterForce = $env:SCRATCHPAD_INTERACTIVE_FORCE
$env:SCRATCHPAD_INTERACTIVE_FORCE = $priorForce
Assert ((@($envList.Methods) -contains 'UI.Env.Force1') -and ($afterForce -eq 'operator-value')) 'discovery-forces-the-fence-and-restores' ((@($envList.Methods) -join '|') + ' / ' + $afterForce)
$t0 = [datetime]::new(2026, 9, 25, 10, 0, 0, [DateTimeKind]::Utc)
$staleBuild = Test-UiBuildFresh $t0 $t0.AddMinutes(5) 'Bin\UI\Debug\UI.dll'
$freshBuild = Test-UiBuildFresh $t0.AddMinutes(5) $t0 'Bin\UI\Debug\UI.dll'
Assert (($staleBuild.Ok -eq $false) -and ($staleBuild.Error -like 'UI build is stale:*run: dotnet build src/ScratchPad.slnx*') -and ($freshBuild.Ok -eq $true)) 'fingerprint-stale-build-refuses' $staleBuild.Error

# Population gate residuals (D00 T02 section 37).
# Item 5: a Theory row swapped at an equal case count drifts by hash.
$caseA = @('UI.A.T1', 'UI.A.T2(x: 1)', 'UI.A.T2(x: 2)')
$caseSwap = @('UI.A.T1', 'UI.A.T2(x: 1)', 'UI.A.T2(x: 3)')
$dh1 = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 1; RunACaseHash = (Get-CaseHash $caseA); RunBCaseHash = (Get-CaseHash @('UI.B.P1')); InteractiveCaseHash = (Get-CaseHash @('UI.C.I1')) }
$fpHash = Join-Path $dir 'pop-hash.fingerprint'
Write-TestPopulationFile $fpHash 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $dh1
$dh2 = [pscustomobject]@{ RunA = @('UI.A.T1', 'UI.A.T2'); RunB = @('UI.B.P1'); Interactive = @('UI.C.I1'); RunAMethods = 2; RunACases = 3; RunBMethods = 1; RunBCases = 1; InteractiveMethods = 1; InteractiveCases = 1; RunACaseHash = (Get-CaseHash $caseSwap); RunBCaseHash = (Get-CaseHash @('UI.B.P1')); InteractiveCaseHash = (Get-CaseHash @('UI.C.I1')) }
$popSame = Compare-TestPopulation $fpHash $fakeNightly $dh1
$popRow = Compare-TestPopulation $fpHash $fakeNightly $dh2
Assert (($popSame.Ok -eq $true) -and ($popRow.Ok -eq $false) -and (@($popRow.Drifts).Count -eq 2) -and ($popRow.Drifts[0] -like 'run-a case rows changed: fingerprinted hash * vs discovered *') -and ($popRow.Drifts[1] -like 'run-a re-accept after review: *Update-TestFingerprint*')) 's37-theory-row-swap-at-equal-count-drifts' ($popRow.Drifts -join '|')
# D00 T02 §44 item 2: two rows with one display name hash apart from one,
# and a reordered listing hashes the same.
Assert (((Get-CaseHash @('UI.A.T(x: 1)', 'UI.A.T(x: 1)')) -ne (Get-CaseHash @('UI.A.T(x: 1)'))) -and ((Get-CaseHash @('UI.B', 'UI.A', 'UI.A')) -eq (Get-CaseHash @('UI.A', 'UI.B', 'UI.A'))) -and ((@(Get-CaseIdentityRows @('UI.A', 'UI.A')) -join ',') -eq 'UI|UI.A,UI|UI.A#2')) 's44-identity-counts-duplicates-and-ignores-order'
# D00 T02 §44 item 8: with case rows recorded, a row swap names the
# removed and the added row and the regen command.
$dr1 = $dh1.PSObject.Copy(); $dr1 | Add-Member -NotePropertyName RunACaseRows -NotePropertyValue @(Get-CaseIdentityRows $caseA) -Force
$dr2 = $dh2.PSObject.Copy(); $dr2 | Add-Member -NotePropertyName RunACaseRows -NotePropertyValue @(Get-CaseIdentityRows $caseSwap) -Force
$fpRows = Join-Path $dir 'pop-rows.fingerprint'
Write-TestPopulationFile $fpRows 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $dr1
$popNamed = Compare-TestPopulation $fpRows $fakeNightly $dr2
$namedText = @($popNamed.Drifts) -join '|'
Assert (($popNamed.Ok -eq $false) -and ($namedText -like '*run-a case removed: UI|UI.A.T2(x: 2)*') -and ($namedText -like '*run-a case added: UI|UI.A.T2(x: 3)*') -and ($namedText -like '*re-accept after review:*')) 's44-row-swap-names-the-cases' $namedText
# D00 T02 §44 item 4: per-case debt reconciles by count per name: a
# retried row (executed twice, listed once) owes nothing, a duplicate
# display name listed twice and executed once owes one, a skipped row stays
# owed.
$dbt = @(Get-UnexecutedCaseRows @('UI.R.Retry', 'UI.D.Dup(x: 1)', 'UI.D.Dup(x: 1)', 'UI.S.Skip') @('UI.R.Retry', 'UI.R.Retry', 'UI.D.Dup(x: 1)') 'fixture')
Assert (($dbt.Count -eq 2) -and ((@($dbt | Where-Object { $_ -like '- Night-owed: UI.D.Dup | 1 of 2 cases unexecuted*cases: UI.D.Dup(x: 1)' }).Count) -eq 1) -and ((@($dbt | Where-Object { $_ -like '- Night-owed: UI.S.Skip | 1 of 1 cases unexecuted*' }).Count) -eq 1) -and ((@($dbt | Where-Object { $_ -like '*UI.R.Retry*' }).Count) -eq 0)) 's44-retry-and-duplicate-keep-the-right-owed-count' ($dbt -join ' || ')
# D00 T02 §44 item 5: a collection green on two of three owed rows keeps
# one owed.
$left = @(Close-OwedCases @('UI.T.M(x: 1)', 'UI.T.M(x: 2)', 'UI.T.M(x: 3)') @('UI.T.M(x: 1)', 'UI.T.M(x: 3)'))
Assert (($left.Count -eq 1) -and ($left[0] -eq 'UI.T.M(x: 2)')) 's44-collection-closes-each-case-on-its-own-row' ($left -join ',')
# D00 T02 §44 item 6: a recovery streak built under one population reads
# stale after a regen that swaps a row, and never closes on it.
$popFpA = Join-Path $dir 'pop-idA.fingerprint'
$popFpB = Join-Path $dir 'pop-idB.fingerprint'
Write-TestPopulationFile $popFpA 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $dr1
Write-TestPopulationFile $popFpB 'Category!=Interactive&Category!=Primary' 'Category=Primary' 'Category=Interactive' $dr2
$idA = Get-PopulationIdentity $popFpA
$idB = Get-PopulationIdentity $popFpB
$popLed = @{ 'INC-aaaa1111' = [pscustomobject]@{ id = 'INC-aaaa1111'; test = 'UI.A.T1'; phase = 'run-a'; key = 'k'; owner = 'operator'; state = 'open'; firstSeen = 's0'; lastSeen = 's0'; closedAt = ''; closedBy = ''; occurrences = @(); passStreak = 0; lastPassStamp = '' } }
$passed = @{ 'run-a' = @('UI.A.T1') }
$u1 = Update-IncidentLedger $popLed @() 's1' $passed @{} 3 @{} $idA
$u2 = Update-IncidentLedger $u1.Incidents @() 's2' $passed @{} 3 @{} $idA
$u3 = Update-IncidentLedger $u2.Incidents @() 's3' $passed @{} 3 @{} $idB
Assert (($idA -ne $idB) -and ($idA -ne 'unknown') -and ($u3.Incidents['INC-aaaa1111'].state -eq 'open') -and ([int]$u3.Incidents['INC-aaaa1111'].passStreak -eq 1) -and ((@($u3.Lines | Where-Object { $_ -like '*streak reset (population*the earlier passes stand stale)*' }).Count) -eq 1)) 's44-proof-reads-stale-after-a-row-swap-regen' ($u3.Lines -join ' | ')
# D00 T02 §44 R1-F5: a streak recorded before populations were (no
# streakPopulation) resets at its first population-bound pass.
$legLed = @{ 'INC-bbbb2222' = [pscustomobject]@{ id = 'INC-bbbb2222'; test = 'UI.A.T1'; phase = 'run-a'; key = 'k'; owner = 'operator'; state = 'open'; firstSeen = 's0'; lastSeen = 's0'; closedAt = ''; closedBy = ''; occurrences = @(); passStreak = 2; lastPassStamp = 's9' } }
$legU = Update-IncidentLedger $legLed @() 's10' @{ 'run-a' = @('UI.A.T1') } @{} 3 @{} $idA
Assert (($legU.Incidents['INC-bbbb2222'].state -eq 'open') -and ([int]$legU.Incidents['INC-bbbb2222'].passStreak -eq 1) -and ((@($legU.Lines | Where-Object { $_ -like '*streak reset (population unrecorded ->*' }).Count) -eq 1)) 's44-unrecorded-population-streak-resets' ($legU.Lines -join ' | ')
# D00 T02 §44 R1-F2: a retried case counts once per attempt set, so it
# never discharges its unexecuted twin.
$att = @(Merge-AttemptNames @(@('UI.D.Dup'), @('UI.D.Dup')))
$twin = @(Get-UnexecutedCaseRows @('UI.D.Dup', 'UI.D.Dup') $att 'fixture')
$twinClose = @(Close-OwedCases @('UI.D.Dup', 'UI.D.Dup') (Merge-AttemptNames @(@('UI.D.Dup'), @('UI.D.Dup'))))
Assert (($att.Count -eq 1) -and ($twin.Count -eq 1) -and ($twin[0] -like '*UI.D.Dup | 1 of 2 cases unexecuted*') -and ($twinClose.Count -eq 1)) 's44-retry-never-discharges-a-twin' (($twin + $twinClose) -join ' || ')
# D00 T02 §44 R1-F1: a truncated display name adds its method's
# test-data source digest, so an argument changed past the cut changes the
# identity; an untruncated listing adds nothing.
$srcDir = Join-Path $dir 'trunc-src'
$null = New-Item -ItemType Directory -Force -Path $srcDir
$srcA = @('public sealed class TruncTests', '{', '    [Theory]', '    [InlineData("a very long argument that runs well past the fifty character cut AAA")]', '    public void Long(string s) { }', '}')
$srcA | Set-Content -Path (Join-Path $srcDir 'TruncTests.cs') -Encoding UTF8
$cutName = 'UI.TruncTests.Long(s: "a very long argument that runs well past the fifty c"' + ([string][char]0xB7 * 3) + ')'
$rowA = @(Get-TruncatedCaseSourceRows $srcDir @($cutName))
($srcA -replace 'AAA', 'BBB') | Set-Content -Path (Join-Path $srcDir 'TruncTests.cs') -Encoding UTF8
$rowB = @(Get-TruncatedCaseSourceRows $srcDir @($cutName))
$rowNone = @(Get-TruncatedCaseSourceRows $srcDir @('UI.TruncTests.Short(s: "x")'))
Assert (($rowA.Count -eq 1) -and ($rowA[0] -like 'UI.TruncTests.Long#args-source *') -and ($rowA[0] -ne $rowB[0]) -and ($rowNone.Count -eq 0) -and ((Get-CaseHash (@($cutName) + $rowA)) -ne (Get-CaseHash (@($cutName) + $rowB)))) 's44-argument-past-the-cut-changes-identity' (($rowA + $rowB) -join ' | ')
# D00 T02 §44 R1-F4: the carried debt closes each case only on its own
# green row tonight, and stays whole when the leg did not run.
$carried = Resolve-CarriedCaseDebt @('UI.T.M(x: 1)', 'UI.T.M(x: 2)', 'UI.T.M(x: 3)') @('UI.T.M(x: 1)', 'UI.T.M(x: 3)') $true
$idle = Resolve-CarriedCaseDebt @('UI.T.M(x: 2)') @('UI.T.M(x: 2)') $false
Assert ((@($carried.Still).Count -eq 1) -and ($carried.Still[0] -eq 'UI.T.M(x: 2)') -and ($carried.Line -eq '- Carried per-case debt: 2 of 3 earlier owed case(s) closed on their own green rows; 1 still owed') -and (@($idle.Still).Count -eq 1) -and (@(Get-OwedCaseNames @('- Night-owed: UI.T.M | 2 of 3 cases unexecuted (x) | collector filter: FullyQualifiedName=UI.T.M | cases: UI.T.M(x: 1) ;; UI.T.M(x: 2)')).Count -eq 2)) 's44-carried-debt-closes-per-case' $carried.Line
# D00 T02 §44 R2-F6: the streak's population persists through the
# ledger file, the lifecycle row, and a rebuild, so an unchanged
# population keeps counting across nights.
$spDir = Join-Path $dir 's44-streakpop'
$null = New-Item -ItemType Directory -Force -Path $spDir
$spLed = @{ 'INC-0000f001' = [pscustomobject]@{ id = 'INC-0000f001'; test = 'UI.SP.T'; phase = 'run-a'; key = 'k'; owner = 'operator'; state = 'open'; firstSeen = 's0'; lastSeen = 's0'; closedAt = ''; closedBy = ''; occurrences = @([pscustomobject]@{ stamp = 's0'; wheres = @('run-a') }); passStreak = 0; lastPassStamp = ''; due = ''; finding = '' } }
$spPass = @{ 'run-a' = @('UI.SP.T') }
$sp1 = Update-IncidentLedger $spLed @() 's1' $spPass @{} 3 @{} 'pop-a'
$null = Write-IncidentLedger $sp1.Incidents (Join-Path $spDir 'incidents.json')
$spRead = Read-IncidentLedger (Join-Path $spDir 'incidents.json')
$sp2 = Update-IncidentLedger $spRead.Incidents @() 's2' $spPass @{} 3 @{} 'pop-a'
$spRow = @(ConvertTo-IncidentLifecycle $sp2.Incidents)[0]
Assert (($spRead.Incidents['INC-0000f001'].streakPopulation -eq 'pop-a') -and ([int]$sp2.Incidents['INC-0000f001'].passStreak -eq 2) -and ((@($sp2.Lines) -join '') -notlike '*streak reset*') -and ($spRow.streakPopulation -eq 'pop-a')) 's44-streak-population-persists' ((@($sp2.Lines) -join ' | ') + " row=$($spRow.streakPopulation)")
# D00 T02 §44 R2-F2: an owed twin closes only when every listed copy of
# its display name ran green in one collection.
$tw1 = @(Close-OwedCases @('UI.D.Dup') @('UI.D.Dup') @('UI.D.Dup', 'UI.D.Dup'))
$tw2 = @(Close-OwedCases @('UI.D.Dup') @('UI.D.Dup', 'UI.D.Dup') @('UI.D.Dup', 'UI.D.Dup'))
$tw3 = @(Close-OwedCases @('UI.D.One') @('UI.D.One') @('UI.D.One'))
Assert (($tw1.Count -eq 1) -and ($tw2.Count -eq 0) -and ($tw3.Count -eq 0)) 's44-twin-closes-only-when-every-copy-ran' "tw1=$($tw1.Count) tw2=$($tw2.Count) tw3=$($tw3.Count)"
# D00 T02 §44 R2-F4 and R2-F5: carried obligations merge per case, and an
# unreadable newer result is named while the older one's debt carries.
$mo = @(Merge-OwedCases @('UI.M.A', 'UI.M.B') @('UI.M.A'))
$poDir = Join-Path $dir 's44-prevowed'
$null = New-Item -ItemType Directory -Force -Path $poDir
[pscustomobject]@{ version = 1; stamp = '2026-09-20-023001'; owedCases = @('UI.P.X(a: 1)') } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $poDir 'morning-2026-09-20-023001.result.json') -Encoding UTF8
'{ not json' | Set-Content -Path (Join-Path $poDir 'morning-2026-09-21-023001.result.json') -Encoding UTF8
$po = Read-PreviousOwedCases $poDir '2026-09-22-023001'
Assert (($mo.Count -eq 2) -and (@($mo | Where-Object { $_ -eq 'UI.M.A' }).Count -eq 1) -and (@($po.Owed).Count -eq 1) -and ($po.Owed[0] -eq 'UI.P.X(a: 1)') -and ($po.From -eq 'morning-2026-09-20-023001.result.json') -and (@($po.Unreadable).Count -eq 1) -and ($po.Unreadable[0] -like 'morning-2026-09-21-023001.result.json*')) 's44-carried-debt-merges-and-survives-a-corrupt-result' "mo=$($mo -join ',') from=$($po.From) bad=$($po.Unreadable -join ',')"
# D00 T02 §44 R2-F1: the args-source digest covers a multiline attribute
# and a data member's transitive static helpers.
$msDir = Join-Path $dir 'trunc-multi'
$null = New-Item -ItemType Directory -Force -Path $msDir
$msA = @('public sealed class MultiTests', '{', '    static string Tail() => "AAA";', '    public static IEnumerable<object[]> Rows()', '    {', '        yield return new object[] { "a long argument well beyond the fifty character cut " + Tail() };', '    }', '', '    [Theory]', '    [InlineData("first",', '        "second line CCC")]', '    [MemberData(nameof(Rows))]', '    public void Long(string s, string t = "") { }', '}')
$msA | Set-Content -Path (Join-Path $msDir 'MultiTests.cs') -Encoding UTF8
$msName = 'UI.MultiTests.Long(s: "a long argument well beyond the fifty character c"' + ([string][char]0xB7 * 3) + ')'
$msRow1 = @(Get-TruncatedCaseSourceRows $msDir @($msName))
($msA -replace 'AAA', 'BBB') | Set-Content -Path (Join-Path $msDir 'MultiTests.cs') -Encoding UTF8
$msRow2 = @(Get-TruncatedCaseSourceRows $msDir @($msName))
($msA -replace 'CCC', 'DDD') | Set-Content -Path (Join-Path $msDir 'MultiTests.cs') -Encoding UTF8
$msRow3 = @(Get-TruncatedCaseSourceRows $msDir @($msName))
Assert (($msRow1.Count -eq 1) -and ($msRow1[0] -notlike '*unresolved') -and ($msRow1[0] -ne $msRow2[0]) -and ($msRow1[0] -ne $msRow3[0])) 's44-args-source-covers-multiline-and-helpers' (($msRow1 + $msRow2 + $msRow3) -join ' | ')
# D00 T02 §44 item 7: a count-only (versionless) fingerprint refuses,
# naming its version and the regen command.
$fpOld = Join-Path $dir 'pop-old.fingerprint'
@('run-a-filter: Category!=Interactive&Category!=Primary', 'run-b-filter: Category=Primary', 'interactive-filter: Category=Interactive', 'run-a-methods: 0', 'run-a-cases: 0', 'run-b-methods: 0', 'run-b-cases: 0', 'interactive-methods: 0', 'interactive-cases: 0') | Set-Content -Path $fpOld -Encoding UTF8
$oldRead = Read-TestPopulationFile $fpOld
Assert ((-not $oldRead.Ok) -and ($oldRead.Error -like 'fingerprint schema missing (count-only format) is not population/2; regenerate: *Update-TestFingerprint.ps1*')) 's44-old-format-refuses-with-the-command' $oldRead.Error
$noHash = @(Get-Content $fpHash | Where-Object { $_ -notlike 'run-b-case-hash:*' })
$noHash | Set-Content -Path (Join-Path $dir 'pop-nohash.fingerprint') -Encoding UTF8
Assert ((Read-TestPopulationFile (Join-Path $dir 'pop-nohash.fingerprint')).Error -eq 'fingerprint missing run-b-case-hash') 's37-case-hash-required'
# Item 4: forced discovery restores a prior unset value, and restores
# when the body throws.
[Environment]::SetEnvironmentVariable('SCRATCHPAD_INTERACTIVE_FORCE', $null, 'Process')
[Environment]::SetEnvironmentVariable('SCRATCHPAD_DISCOVERY_LISTING', $null, 'Process')
$inside = Invoke-WithForcedDiscovery { "$env:SCRATCHPAD_INTERACTIVE_FORCE/$env:SCRATCHPAD_DISCOVERY_LISTING" }
Assert (($inside -eq '1/1') -and (-not (Test-Path Env:\SCRATCHPAD_INTERACTIVE_FORCE)) -and (-not (Test-Path Env:\SCRATCHPAD_DISCOVERY_LISTING))) 's37-forced-discovery-prior-unset-stays-unset' $inside
$env:SCRATCHPAD_INTERACTIVE_FORCE = 'operator-value'
$threwBody = ''
try { Invoke-WithForcedDiscovery { throw 'discovery blew up' } } catch { $threwBody = "$_" }
$afterThrow = $env:SCRATCHPAD_INTERACTIVE_FORCE
$env:SCRATCHPAD_INTERACTIVE_FORCE = $priorForce
Assert (($threwBody -eq 'discovery blew up') -and ($afterThrow -eq 'operator-value') -and (-not (Test-Path Env:\SCRATCHPAD_DISCOVERY_LISTING))) 's37-forced-discovery-restores-on-throw' "$threwBody / $afterThrow"
# Item 2: a shared build input newer than the binary refuses.
$bRoot = Join-Path $dir 'build-inputs'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $bRoot 'tests\UI'), (Join-Path $bRoot 'src\App'), (Join-Path $bRoot 'Bin\UI\Debug')
'<Project><ItemGroup><ProjectReference Include="..\..\src\App\App.csproj" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $bRoot 'tests\UI\UI.csproj') -Encoding UTF8
'<Project />' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
'class A {}' | Set-Content -Path (Join-Path $bRoot 'src\App\A.cs') -Encoding UTF8
'<Project />' | Set-Content -Path (Join-Path $bRoot 'Directory.Build.props') -Encoding UTF8
'dll' | Set-Content -Path (Join-Path $bRoot 'Bin\UI\Debug\UI.dll') -Encoding UTF8
$tOld = [datetime]::new(2026, 9, 25, 9, 0, 0, [DateTimeKind]::Utc)
foreach ($f in @('tests\UI\UI.csproj', 'src\App\App.csproj', 'src\App\A.cs', 'Directory.Build.props')) { (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld }
(Get-Item (Join-Path $bRoot 'Bin\UI\Debug\UI.dll')).LastWriteTimeUtc = $tOld.AddMinutes(10)
# The build's content digest (D00 T02 §44 item 1), written as the build
# target would, so the fresh fixture is fresh by content too.
$bDigest = Get-BuildInputsDigest $bRoot (Get-UiSdkVersion $bRoot)
[System.IO.File]::WriteAllText((Join-Path $bRoot 'Bin\UI\Debug\build-inputs.digest'), $bDigest.Digest + "`n" + ($bDigest.Lines -join "`n") + "`n")
$freshB = Get-UiBuildFreshness $bRoot
(Get-Item (Join-Path $bRoot 'Directory.Build.props')).LastWriteTimeUtc = $tOld.AddMinutes(20)
$staleShared = Get-UiBuildFreshness $bRoot
(Get-Item (Join-Path $bRoot 'Directory.Build.props')).LastWriteTimeUtc = $tOld
(Get-Item (Join-Path $bRoot 'src\App\A.cs')).LastWriteTimeUtc = $tOld.AddMinutes(20)
$staleRef = Get-UiBuildFreshness $bRoot
# R1-F2: an ancestor Directory.Build.props below the root, an imported
# targets file outside the tree, and a linked source outside the project
# directory each count.
$null = New-Item -ItemType Directory -Force -Path (Join-Path $bRoot 'build-shared'), (Join-Path $bRoot 'shared-src')
'<Project />' | Set-Content -Path (Join-Path $bRoot 'tests\Directory.Build.props') -Encoding UTF8
'<Project />' | Set-Content -Path (Join-Path $bRoot 'build-shared\Extra.targets') -Encoding UTF8
'class L {}' | Set-Content -Path (Join-Path $bRoot 'shared-src\Linked.cs') -Encoding UTF8
'<Project><Import Project="..\..\build-shared\Extra.targets" /><ItemGroup><Compile Include="..\..\shared-src\Linked.cs" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
foreach ($f in @('tests\Directory.Build.props', 'build-shared\Extra.targets', 'shared-src\Linked.cs', 'src\App\App.csproj')) { (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld }
$ancestorHits = @()
foreach ($f in @('tests\Directory.Build.props', 'build-shared\Extra.targets', 'shared-src\Linked.cs')) {
  (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld.AddMinutes(30)
  $r = Get-UiBuildFreshness $bRoot
  if ((-not $r.Ok) -and ($r.Error -like "*$f*")) { $ancestorHits += $f }
  (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld
}
Assert ($ancestorHits.Count -eq 3) 's37-ancestor-import-and-linked-inputs-refuse' ($ancestorHits -join '|')
# R2-F2: a property-built import resolves (built-in directory property and
# a literal property), and an unresolvable one refuses by name.
'<Project><PropertyGroup><SharedDir>..\..\build-shared</SharedDir></PropertyGroup><Import Project="$(MSBuildThisFileDirectory)$(SharedDir)\Extra.targets" /></Project>' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
(Get-Item (Join-Path $bRoot 'src\App\App.csproj')).LastWriteTimeUtc = $tOld
(Get-Item (Join-Path $bRoot 'build-shared\Extra.targets')).LastWriteTimeUtc = $tOld.AddMinutes(30)
$propStale = Get-UiBuildFreshness $bRoot
(Get-Item (Join-Path $bRoot 'build-shared\Extra.targets')).LastWriteTimeUtc = $tOld
'<Project><Import Project="$(NotDefinedAnywhere)\x.targets" /></Project>' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
(Get-Item (Join-Path $bRoot 'src\App\App.csproj')).LastWriteTimeUtc = $tOld
$propUnknown = Get-UiBuildFreshness $bRoot
'<Project />' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
(Get-Item (Join-Path $bRoot 'src\App\App.csproj')).LastWriteTimeUtc = $tOld
Assert (($propStale.Ok -eq $false) -and ($propStale.Error -like '*build-shared\Extra.targets*') -and ($propUnknown.Ok -eq $false) -and ($propUnknown.Error -like '*unresolved build input path(s): $(NotDefinedAnywhere)\x.targets in src\App\App.csproj*')) 's37-property-paths-resolve-or-refuse' "$($propStale.Error) | $($propUnknown.Error)"
# R3-F2: a property defined with its own file's directory resolves
# against its definition, and a missing resolved item refuses; R3-F3: a
# wildcard item outside the project counts every file it matches.
'<Project><PropertyGroup><SharedDir>$(MSBuildThisFileDirectory)build-shared\</SharedDir></PropertyGroup></Project>' | Set-Content -Path (Join-Path $bRoot 'Directory.Build.props') -Encoding UTF8
'<Project><Import Project="$(SharedDir)Extra.targets" /><ItemGroup><Compile Include="..\..\shared-src\**\*.cs" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
foreach ($f in @('Directory.Build.props', 'src\App\App.csproj')) { (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld }
(Get-Item (Join-Path $bRoot 'build-shared\Extra.targets')).LastWriteTimeUtc = $tOld.AddMinutes(30)
$defStale = Get-UiBuildFreshness $bRoot
(Get-Item (Join-Path $bRoot 'build-shared\Extra.targets')).LastWriteTimeUtc = $tOld
(Get-Item (Join-Path $bRoot 'shared-src\Linked.cs')).LastWriteTimeUtc = $tOld.AddMinutes(30)
$wildStale = Get-UiBuildFreshness $bRoot
(Get-Item (Join-Path $bRoot 'shared-src\Linked.cs')).LastWriteTimeUtc = $tOld
'<Project><ItemGroup><None Include="..\..\gone\Missing.txt" /></ItemGroup></Project>' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
(Get-Item (Join-Path $bRoot 'src\App\App.csproj')).LastWriteTimeUtc = $tOld
$missing = Get-UiBuildFreshness $bRoot
'<Project />' | Set-Content -Path (Join-Path $bRoot 'Directory.Build.props') -Encoding UTF8
'<Project />' | Set-Content -Path (Join-Path $bRoot 'src\App\App.csproj') -Encoding UTF8
foreach ($f in @('Directory.Build.props', 'src\App\App.csproj')) { (Get-Item (Join-Path $bRoot $f)).LastWriteTimeUtc = $tOld }
Assert (($defStale.Ok -eq $false) -and ($defStale.Error -like '*build-shared\Extra.targets*') -and ($wildStale.Ok -eq $false) -and ($wildStale.Error -like '*shared-src\Linked.cs*') -and ($missing.Ok -eq $false) -and ($missing.Error -like '*resolves to missing*Missing.txt*')) 's37-definition-dir-wildcards-and-missing-items' "$($defStale.Error) | $($wildStale.Error) | $($missing.Error)"
# R2-F1: case-distinct Theory rows stay distinct in the hash and the debt.
Assert ((Get-CaseHash @('UI.X.T(s: "a")', 'UI.X.T(s: "A")')) -ne (Get-CaseHash @('UI.X.T(s: "a")'))) 's37-case-hash-is-ordinal'
$caseRows = @(Get-UnexecutedCaseRows @('UI.X.T(s: "a")', 'UI.X.T(s: "A")') @('UI.X.T(s: "a")') 'fixture')
Assert (($caseRows.Count -eq 1) -and ($caseRows[0] -like '*UI.X.T | 1 of 2 cases unexecuted*')) 's37-debt-is-ordinal' ($caseRows -join '|')
Assert (($freshB.Ok -eq $true) -and ($staleShared.Ok -eq $false) -and ($staleShared.Error -like '*newest build input (Directory.Build.props)*') -and ($staleRef.Ok -eq $false) -and ($staleRef.Error -like '*src\App\A.cs*')) 's37-shared-and-referenced-inputs-refuse' "$($staleShared.Error) | $($staleRef.Error)"
# Item 6: one of three Theory rows run keeps two owed.
$owedRows = @(Get-UnexecutedCaseRows @('UI.X.Theory(n: 1)', 'UI.X.Theory(n: 2)', 'UI.X.Theory(n: 3)', 'UI.X.Fact') @('UI.X.Theory(n: 2)', 'UI.X.Fact') 'fixture kill')
Assert (($owedRows.Count -eq 1) -and ($owedRows[0] -eq '- Night-owed: UI.X.Theory | 2 of 3 cases unexecuted (fixture kill) | collector filter: FullyQualifiedName=UI.X.Theory | cases: UI.X.Theory(n: 1) ;; UI.X.Theory(n: 3)')) 's37-partial-theory-keeps-two-owed' ($owedRows -join '|')
$trxPart = Join-Path $dir 'partial.trx'
'<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results><UnitTestResult testName="UI.X.Theory(n: 2)" outcome="Passed" /><UnitTestResult testName="UI.X.Skip" outcome="NotExecuted" /></Results></TestRun>' | Set-Content -Path $trxPart -Encoding UTF8
$exec = @(Get-TrxExecutedNames $trxPart)
Assert (($exec.Count -eq 1) -and ($exec[0] -eq 'UI.X.Theory(n: 2)') -and (@(Get-TrxExecutedNames (Join-Path $dir 'no.trx')).Count -eq 0)) 's37-trx-executed-names' ($exec -join '|')
# Item 1: a red CI population check refuses; green passes; pending and
# absent read as not verified.
$runsRed = @([pscustomobject]@{ databaseId = 42; status = 'completed'; conclusion = 'failure' })
$jobsRed = [pscustomobject]@{ jobs = @([pscustomobject]@{ name = 'build-windows'; steps = @([pscustomobject]@{ name = 'Build solution'; conclusion = 'success' }, [pscustomobject]@{ name = 'Check test population fingerprint'; conclusion = 'failure' }) }) }
$gRed = Get-CandidateCiGate $runsRed $jobsRed 'abc1234'
$jobsGreen = [pscustomobject]@{ jobs = @([pscustomobject]@{ name = 'build-windows'; steps = @([pscustomobject]@{ name = 'Check test population fingerprint'; conclusion = 'success' }) }) }
$gGreen = Get-CandidateCiGate @([pscustomobject]@{ databaseId = 43; status = 'completed'; conclusion = 'success' }) $jobsGreen 'abc1234'
$gPending = Get-CandidateCiGate @([pscustomobject]@{ databaseId = 44; status = 'in_progress'; conclusion = '' }) ([pscustomobject]@{ jobs = @() }) 'abc1234'
$gNone = Get-CandidateCiGate @() $null 'abc1234'
$aGreen = Resolve-CiAdmission $gGreen $false
$aPending = Resolve-CiAdmission $gPending $false
$aNone = Resolve-CiAdmission $gNone $false
$aOverride = Resolve-CiAdmission $gNone $true
$aRedOverride = Resolve-CiAdmission $gRed $true
# R3-F1: a green HEAD does not admit a dirty tree.
$aDirty = Resolve-CiAdmission $gGreen $false 'dirty'
Assert (($aDirty.Admitted -eq $false) -and ($aDirty.Line -like '*the built tree is dirty, so CI did not check this candidate*')) 's37-green-head-does-not-admit-a-dirty-tree' $aDirty.Line
Assert (($aGreen.Admitted -eq $true) -and ($aPending.Admitted -eq $false) -and ($aNone.Admitted -eq $false) -and ($aNone.Line -like '*only a green CI population check admits it*') -and ($aOverride.Admitted -eq $true) -and ($aOverride.Line -like '*admitted without CI verification (-AllowUnverifiedCi)') -and ($aRedOverride.Admitted -eq $false)) 's37-only-green-admits' "$($aNone.Line) | $($aOverride.Line)"
Assert (($gRed.State -eq 'red') -and ($gRed.Line -eq 'CI population check failure on abc1234 (run 42): the population is refused') -and ($gGreen.State -eq 'green') -and ($gPending.State -eq 'pending') -and ($gNone.State -eq 'none') -and ($gNone.Line -like '*no build.yml run for abc1234*')) 's37-red-ci-check-refuses-the-population' "$($gRed.Line) | $($gGreen.Line) | $($gPending.Line) | $($gNone.Line)"

# Nightly evidence second residuals (D00 T02 section 38).
$s38 = Join-Path $dir 's38'
$null = New-Item -ItemType Directory -Force -Path $s38
# Item 1: a staged file altered between scan and publish refuses; the
# staging directory carries only the running account's rule; a
# crash-left staging directory is swept at run start.
$capT = Join-Path $s38 'captures-tamper'
$null = New-Item -ItemType Directory -Force -Path $capT
$aclSeen = $null
$tamper = @(Publish-TextCapture $capT 'win.txt' @('pid=1 ScratchPad: doc') 'interactive' { param($f) $script:aclSeen = [System.IO.Directory]::GetAccessControl((Split-Path -Parent $f)); Add-Content -LiteralPath $f -Value 'token: sk-live-injected-after-scan' })
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$aclRules = @($script:aclSeen.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
Assert ((-not (Test-Path (Join-Path $capT 'win.txt'))) -and (($tamper -join '') -like '*refused win.txt (the staged bytes changed between the scan and the publish)*') -and ($script:aclSeen.AreAccessRulesProtected) -and ($aclRules.Count -eq 1) -and ($aclRules[0].IdentityReference -eq $me)) 's38-staging-tamper-refuses-and-acl-is-own' (($tamper -join '|') + " rules=$($aclRules.Count)")
$okPub = @(Publish-TextCapture $capT 'clean.txt' @('pid=1 ScratchPad: doc') 'interactive')
Assert ((Test-Path (Join-Path $capT 'clean.txt')) -and ($okPub.Count -eq 0)) 's38-staging-clean-publishes' ($okPub -join '|')
$crash = Join-Path $s38 '2026-09-25-020000\captures-interactive\.staging'
$null = New-Item -ItemType Directory -Force -Path $crash
'unscanned' | Set-Content -Path (Join-Path $crash 'left.txt') -Encoding UTF8
$sweep = @(Clear-StaleCaptureStaging $s38)
Assert ((-not (Test-Path $crash)) -and (($sweep -join '') -like '*swept crash-left 2026-09-25-020000\captures-interactive\.staging*')) 's38-crash-left-staging-swept' ($sweep -join '|')
# Item 2: screenshots cover app-owned ScratchPad windows only; a
# full-memory dump retains only behind the disclosure marker.
$winsFix = @(
  [pscustomobject]@{ ProcessId = 10; Name = 'ScratchPad'; Rect = [pscustomobject]@{ X = 100; Y = 50; Width = 800; Height = 600 } },
  [pscustomobject]@{ ProcessId = 11; Name = 'ScratchPad'; Rect = [pscustomobject]@{ X = 0; Y = 0; Width = 800; Height = 600 } },
  [pscustomobject]@{ ProcessId = 12; Name = 'pwsh'; Rect = [pscustomobject]@{ X = 0; Y = 0; Width = 800; Height = 600 } },
  [pscustomobject]@{ ProcessId = 13; Name = 'ScratchPad'; Rect = [pscustomobject]@{ X = 0; Y = 0; Width = 0; Height = 0 } }
)
$rects = @(Get-OwnedWindowRects $winsFix @{ 10 = $true; 12 = $true; 13 = $true })
Assert (($rects.Count -eq 1) -and ($rects[0].ProcessId -eq 10) -and ($rects[0].X -eq 100) -and ($rects[0].Width -eq 800)) 's38-screenshot-app-owned-bounds-only' (($rects | ForEach-Object { $_.ProcessId }) -join ',')
$dumpSrc = Join-Path $s38 'retain-src'
$dumpCap = Join-Path $dumpSrc 'captures-interactive'
$null = New-Item -ItemType Directory -Force -Path $dumpCap
$hdr = New-Object byte[] 64
[System.Text.Encoding]::ASCII.GetBytes('MDMP').CopyTo($hdr, 0)
[System.BitConverter]::GetBytes([UInt64]2).CopyTo($hdr, 24)
[System.IO.File]::WriteAllBytes((Join-Path $dumpCap '4242.dmp'), $hdr)
$fullRefused = Test-RetainableCaptures $dumpSrc
'approved for triage of INC-1a2b3c4d' | Set-Content -Path (Join-Path $dumpCap $script:DumpDisclosureMarker) -Encoding UTF8
$fullGated = Test-RetainableCaptures $dumpSrc
Remove-Item (Join-Path $dumpCap $script:DumpDisclosureMarker)
[System.BitConverter]::GetBytes([UInt64]0).CopyTo($hdr, 24)
[System.IO.File]::WriteAllBytes((Join-Path $dumpCap '4242.dmp'), $hdr)
$minimalRefused = Test-RetainableCaptures $dumpSrc
[System.IO.File]::WriteAllBytes((Join-Path $dumpCap 'interactive-failure-1.png'), [byte[]](137, 80, 78, 71))
$pngRefused = Test-RetainableCaptures $dumpSrc
'approved' | Set-Content -Path (Join-Path $dumpCap $script:DumpDisclosureMarker) -Encoding UTF8
$allGated = Test-RetainableCaptures $dumpSrc
Assert (($fullRefused.Ok -eq $false) -and (($fullRefused.Reasons -join '') -like '*4242.dmp is a full-memory dump; retain needs CAPTURE-DISCLOSURE-APPROVED.txt*') -and ($fullGated.Ok -eq $true) -and ($minimalRefused.Ok -eq $false) -and (($pngRefused.Reasons -join '') -like '*interactive-failure-1.png is a screenshot; retain needs*') -and ($allGated.Ok -eq $true) -and ((Get-DumpMemoryKind (Join-Path $s38 'no.dmp')) -eq 'unreadable')) 's38-full-heap-dump-retains-only-behind-its-gate' ($fullRefused.Reasons -join '|')
# R3-F1: a window that never renders is abandoned at the bound.
$hungNote = @(Invoke-WindowRender ([pscustomobject]@{ ProcessId = 77; Handle = 0; Width = 10; Height = 10 }) (Join-Path $s38 'hung.png') 'interactive' 2 { param($h, $w, $hh, $o) Start-Sleep -Seconds 60; $true })
Assert ((($hungNote -join '') -like '*screenshot of pid 77 abandoned (the window did not render within 2 s)*') -and (-not (Test-Path (Join-Path $s38 'hung.png')))) 's38-hung-window-render-is-bounded' ($hungNote -join '|')
# Item 3: an oversized dump is refused at capture time and the marker
# names it (the real JobControl, capped at 1 KB).
$jc = Join-Path $PSScriptRoot '..\Bin\JobControl\Debug\JobControl.exe'
if (Test-Path $jc) {
  $jDump = Join-Path $s38 'dumps'
  $jOut = & $jc 'run' '--job' "Global\s38-fixture-$PID" '--out' (Join-Path $s38 'jc.log') '--timeout' '2' '--dump' $jDump '--dump-max' '1024' '--' (Join-Path $PSHOME 'powershell.exe') '-NoProfile' '-Command' 'Start-Sleep -Seconds 30' 2>&1
  $refusedText = if (Test-Path (Join-Path $jDump 'CAPTURE-REFUSED.txt')) { Get-Content (Join-Path $jDump 'CAPTURE-REFUSED.txt') -Raw } else { '' }
  Assert (($refusedText -match '\d+\.dmp refused: stopped at the 1024-byte cap during capture') -and (@(Get-ChildItem $jDump -Filter '*.dmp' -ErrorAction SilentlyContinue).Count -eq 0) -and ("$jOut" -match 'dumped=0')) 's38-oversized-dump-refused-at-capture' ("$refusedText | $jOut")
  # R1-F1: under a cap it fits, the streamed dump is a valid minidump.
  $jDump2 = Join-Path $s38 'dumps-ok'
  $null = & $jc 'run' '--job' "Global\s38-fixture2-$PID" '--out' (Join-Path $s38 'jc2.log') '--timeout' '2' '--dump' $jDump2 '--dump-max' '104857600' '--' (Join-Path $PSHOME 'powershell.exe') '-NoProfile' '-Command' 'Start-Sleep -Seconds 30' 2>&1
  $okDumps = @(Get-ChildItem $jDump2 -Filter '*.dmp' -ErrorAction SilentlyContinue)
  Assert (($okDumps.Count -ge 1) -and ((Get-DumpMemoryKind $okDumps[0].FullName) -eq 'minimal') -and (-not (Test-Path (Join-Path $jDump2 'CAPTURE-REFUSED.txt')))) 's38-streamed-dump-under-cap-is-valid' "$($okDumps.Count) $(if ($okDumps.Count) { Get-DumpMemoryKind $okDumps[0].FullName })"
} else { Assert $false 's38-oversized-dump-refused-at-capture' "JobControl missing at $jc (build tools/JobControl first)" }
# Item 4: with the ledger and every result gone, the initialization
# record reds; a fresh reset lets a new ledger start.
$recFile = Join-Path $s38 'incident-ledger.md'
@('# Incident ledger record', 'Ledger started: 2026-09-25 (contract v2)') | Set-Content -Path $recFile -Encoding UTF8
$wiped = Test-IncidentLedgerPresence (Join-Path $s38 'incidents.json') @() '2026-09-25-000000' $recFile ([datetime]'2026-10-02')
Add-Content -Path $recFile -Value 'Reset: 2026-10-02 operator cleared the lab host' -Encoding UTF8
$reset = Test-IncidentLedgerPresence (Join-Path $s38 'incidents.json') @() '2026-09-25-000000' $recFile ([datetime]'2026-10-02')
$futRec = Join-Path $s38 'incident-ledger-future.md'
@('Ledger started: 2026-09-25 (contract v2)', 'Reset: 2026-10-09 pre-approved') | Set-Content -Path $futRec -Encoding UTF8
$futureReset = Test-IncidentLedgerPresence (Join-Path $s38 'incidents.json') @() '2026-09-25-000000' $futRec ([datetime]'2026-10-02')
Assert ($futureReset.Ok -eq $false) 's38-future-reset-authorizes-nothing' $futureReset.Error
$emptyStamp = Test-LifecycleRows @([pscustomobject]@{ id = 'INC-0000000a'; test = 'UI.T'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @(''); firstSeen = 's'; passStreak = 0; contract = 'v2' })
$futRes = Join-Path $s38 'future.result.json'
[pscustomobject]@{ version = 1; stamp = '2026-09-30-023001'; day = '2026-09-30'; identity = 'x-pid1'; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycleVersion = 9; incidentLifecycle = @() } | ConvertTo-Json -Depth 6 | Set-Content -Path $futRes -Encoding UTF8
$futValid = Test-ResultFile $futRes
Assert (($emptyStamp -like '*empty occurrence stamp*') -and ($futValid.Ok -eq $false) -and ($futValid.Error -like '*version 9 is newer*')) 's38-empty-stamp-and-future-version-invalid' "$emptyStamp | $($futValid.Error)"
$noRecord = Test-IncidentLedgerPresence (Join-Path $s38 'incidents.json') @() '2026-09-25-000000' (Join-Path $s38 'none.md') ([datetime]'2026-10-02')
Assert (($wiped.Ok -eq $false) -and ($wiped.Error -like '*records the ledger started 2026-09-25: incident history was lost; if the loss is intended, add *Reset: 2026-10-02 <reason>*') -and ($reset.Ok -eq $true) -and ($noRecord.Ok -eq $true)) 's38-full-wipe-reds-on-the-initialization-record' $wiped.Error
# Item 5: ledger -> result -> rebuild reproduces every ledger field.
$rtDir = Join-Path $s38 'roundtrip'
$null = New-Item -ItemType Directory -Force -Path $rtDir
$rtLedger = @{
  'INC-0a0b0c0d' = [pscustomobject]@{ id = 'INC-0a0b0c0d'; test = 'UI.R.Closed'; phase = 'interactive'; key = 'v2|UI.R.Closed|interactive|Assert.Equal() Failure||A.B.C'; owner = 'D01 T01 S9'; state = 'closed'; firstSeen = '2026-09-25-023001'; lastSeen = '2026-09-26-023001'; closedAt = '2026-09-29-023001'; closedBy = 'recovered: 3 passing runs'; occurrences = @([pscustomobject]@{ stamp = '2026-09-25-023001'; wheres = @('interactive') }, [pscustomobject]@{ stamp = '2026-09-26-023001'; wheres = @('interactive', 'ui-soak-2') }); passStreak = 3; lastPassStamp = '2026-09-29-023001'; due = '2026-09-27'; finding = 'abc1234' }
  'INC-0e0f0a0b' = [pscustomobject]@{ id = 'INC-0e0f0a0b'; test = 'UI.R.Open'; phase = 'run-a'; key = 'v2|UI.R.Open|run-a|TimeoutException|0x80131505|X.Y'; owner = 'operator'; state = 'open'; firstSeen = '2026-09-28-023001'; lastSeen = '2026-09-28-023001'; closedAt = ''; closedBy = ''; occurrences = @([pscustomobject]@{ stamp = '2026-09-28-023001'; wheres = @('run-a') }); passStreak = 1; lastPassStamp = '2026-09-29-023001'; due = '2026-09-30'; finding = '' }
}
[pscustomobject]@{ version = 1; stamp = '2026-09-29-023001'; day = '2026-09-29'; identity = '2026-09-29-023001-pid1'; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycleVersion = 1; incidentLifecycle = @(ConvertTo-IncidentLifecycle $rtLedger) } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $rtDir 'morning-2026-09-29-023001.result.json') -Encoding UTF8
$rtBack = New-IncidentLedgerFromResults @((Join-Path $rtDir 'morning-2026-09-29-023001.result.json')) '2026-09-25-000000' @{} @{}
$rtDiffs = @()
foreach ($id in $rtLedger.Keys) {
  $a = $rtLedger[$id]; $b = $rtBack[$id]
  if ($null -eq $b) { $rtDiffs += "$id missing"; continue }
  foreach ($f in @('id', 'test', 'phase', 'key', 'owner', 'state', 'firstSeen', 'lastSeen', 'closedAt', 'closedBy', 'passStreak', 'lastPassStamp', 'due', 'finding')) { if ("$($a.$f)" -ne "$($b.$f)") { $rtDiffs += "$id.$f '$($a.$f)' vs '$($b.$f)'" } }
  $ao = (@($a.occurrences) | ForEach-Object { "$($_.stamp)=$(@($_.wheres) -join ',')" }) -join ';'
  $bo = (@($b.occurrences) | ForEach-Object { "$($_.stamp)=$(@($_.wheres) -join ',')" }) -join ';'
  if ($ao -ne $bo) { $rtDiffs += "$id.occurrences '$ao' vs '$bo'" }
}
Assert (($rtDiffs.Count -eq 0) -and ($rtBack.Count -eq 2)) 's38-rebuild-round-trip-is-lossless' ($rtDiffs -join '|')
# Item 6: split, merged, and unmapped aliases read as defined.
$alRows = @(
  [pscustomobject]@{ stamp = '2026-09-20-023001'; incidents = @('- INC-00000001 `UI.S.Split` x1 (interactive): Assert.True() Failure', '- INC-00000002 `UI.M.Merge` x1 (run-a): Assert.NotNull() Failure', '- INC-00000003 `UI.M.Merge` x1 (run-a): Assert.NotNull() Failure', '- INC-00000004 `UI.U.Gone` x1 (run-a): Assert.Equal() Failure', '- INC-00000005 `UI.O.One` x1 (run-a): Assert.Equal() Failure') },
  [pscustomobject]@{ stamp = '2026-09-26-023001'; incidents = @('- INC-0000000a `UI.S.Split` x1 (interactive): Assert.True() Failure', '- INC-0000000b `UI.M.Merge` x1 (run-a): Assert.NotNull() Failure', '- INC-0000000e `UI.O.One` x1 (run-a): Assert.Equal() Failure') },
  [pscustomobject]@{ stamp = '2026-09-27-023001'; incidents = @('- INC-0000000c `UI.S.Split` x1 (interactive): Assert.True() Failure') }
)
$alRep = Get-IncidentAliasReport $alRows
Assert (($alRep.Aliases['INC-00000005'] -eq 'INC-0000000e') -and (-not $alRep.Aliases.ContainsKey('INC-00000001')) -and (-not $alRep.Aliases.ContainsKey('INC-00000002')) -and (-not $alRep.Aliases.ContainsKey('INC-00000003')) -and (($alRep.Split['INC-00000001'] -join ',') -eq 'INC-0000000a,INC-0000000c') -and (($alRep.Merged['INC-0000000b'] -join ',') -eq 'INC-00000002,INC-00000003') -and (($alRep.Unmapped -join ',') -eq 'INC-00000004')) 's38-alias-split-merge-unmapped-defined' ("split=$($alRep.Split.Keys -join ',') merged=$($alRep.Merged.Keys -join ',') unmapped=$($alRep.Unmapped -join ',')")
# Item 7: the lifecycle block's consumer contract.
$lbAbsent = Read-LifecycleBlock ([pscustomobject]@{ version = 1; stamp = '2026-09-20-023001' })
$lbLegacy = Read-LifecycleBlock ([pscustomobject]@{ version = 1; stamp = '2026-09-26-023001'; incidentLifecycle = @([pscustomobject]@{ id = 'INC-0000000a'; test = 'UI.T'; phase = 'run-a'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('s'); firstSeen = 's'; passStreak = 0; contract = 'v2' }) })
$lbFuture = Read-LifecycleBlock ([pscustomobject]@{ version = 1; stamp = '2026-09-26-023001'; incidentLifecycleVersion = 2; incidentLifecycle = @() })
$lbInvalid = Read-LifecycleBlock ([pscustomobject]@{ version = 1; stamp = '2026-09-26-023001'; incidentLifecycleVersion = 1; incidentLifecycle = @([pscustomobject]@{ id = 'INC-0000000a'; test = 'UI.T'; phase = 'run-a'; state = 'half-open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @('s'); firstSeen = 's'; passStreak = 0; contract = 'v2' }) })
Assert (($lbInvalid.State -eq 'invalid') -and ($lbInvalid.Error -like '*state half-open*')) 's38-lifecycle-rows-validate-on-read' $lbInvalid.Error
Assert (($lbAbsent.State -eq 'absent') -and ($lbLegacy.State -eq 'ok') -and ($lbLegacy.Version -eq 1) -and (@($lbLegacy.Rows).Count -eq 1) -and ($lbFuture.State -eq 'unsupported') -and ($lbFuture.Error -like '*version 2 is newer than this reader (1)*')) 's38-lifecycle-consumer-contract' "$($lbAbsent.State) $($lbLegacy.State) $($lbFuture.State)"
[pscustomobject]@{ version = 1; stamp = '2026-09-30-023001'; day = '2026-09-30'; identity = '2026-09-30-023001-pid1'; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycleVersion = 2; incidentLifecycle = @() } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $rtDir 'morning-2026-09-30-023001.result.json') -Encoding UTF8
$futSnap = Get-LatestLifecycleSnapshot @(Get-ChildItem $rtDir -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName }) '2026-09-25-000000'
Assert ($futSnap.Error -like '*2026-09-30-023001*unreadable: incidentLifecycleVersion 2 is newer*') 's38-future-lifecycle-version-refuses-the-rebuild' $futSnap.Error
# Item 8: one policy file; an overdue incident notifies its owner.
$polOk = Read-IncidentPolicy (Join-Path $PSScriptRoot 'incident-policy.json')
'{ "triageOwner": "", "triageDays": 0 }' | Set-Content -Path (Join-Path $s38 'bad-policy.json') -Encoding UTF8
$polBad = Read-IncidentPolicy (Join-Path $s38 'bad-policy.json')
$overdue = @(Get-OverdueIncidentNotices $rtLedger ([datetime]'2026-10-02'))
# R3-F2: an impossible due date is named alone; the batch goes on.
$badDue = @{ 'INC-0000bad1' = [pscustomobject]@{ id = 'INC-0000bad1'; test = 'UI.B'; state = 'open'; owner = 'operator'; due = '2026-02-30' }; 'INC-0e0f0a0b' = $rtLedger['INC-0e0f0a0b'] }
$badBatch = @(Get-OverdueIncidentNotices $badDue ([datetime]'2026-10-02'))
Assert (($badBatch.Count -eq 2) -and (@($badBatch | Where-Object { $_.RunId -like 'incident-baddue-INC-0000bad1-*' }).Count -eq 1) -and (@($badBatch | Where-Object { $_.Id -eq 'INC-0e0f0a0b' }).Count -eq 1)) 's38-invalid-due-date-never-aborts-the-batch' (($badBatch | ForEach-Object { $_.RunId }) -join '|')
Assert (($polOk.Ok -eq $true) -and ($polOk.Owner -eq $script:TriageOwner) -and ($polOk.Days -eq $script:TriageDays) -and ($polBad.Ok -eq $false) -and ($overdue.Count -eq 1) -and ($overdue[0].Id -eq 'INC-0e0f0a0b') -and ($overdue[0].Owner -eq 'operator') -and ($overdue[0].RunId -eq 'incident-overdue-INC-0e0f0a0b-2026-10-02')) 's38-policy-and-overdue-owner-notice' (($overdue | ForEach-Object { $_.Title }) -join '|')
# Item 9: a failed filing stays unlinked and re-lists; the retry links
# once; linking again records nothing; a conflicting link refuses.
$linkFile = Join-Path $s38 'incident-links.md'
@('# Incident links', '', '| Incident | Finding | Note |', '| --- | --- | --- |') | Set-Content -Path $linkFile -Encoding UTF8
$l1 = Add-IncidentLink $linkFile 'INC-0e0f0a0b' 'abc1234' { param($f, $t) throw 'disk full' }
$stillUnlinked = @(Format-UnlinkedIncidents @{ 'INC-0e0f0a0b' = [pscustomobject]@{ id = 'INC-0e0f0a0b'; test = 'UI.R.Open'; state = 'open'; finding = (Read-IncidentLinks $linkFile)['INC-0e0f0a0b']; owner = 'operator'; due = '2026-09-30' } })
$l2 = Add-IncidentLink $linkFile 'INC-0e0f0a0b' 'abc1234'
$l3 = Add-IncidentLink $linkFile 'INC-0e0f0a0b' 'abc1234'
$l4 = Add-IncidentLink $linkFile 'INC-0e0f0a0b' 'def5678'
$linkRows = @(Get-Content $linkFile | Where-Object { $_ -like '| INC-0e0f0a0b |*' })
Assert (($l1.Status -eq 'failed') -and ($stillUnlinked.Count -eq 1) -and ($l2.Status -eq 'linked') -and ($l3.Status -eq 'already') -and ($l4.Status -eq 'conflict') -and ($linkRows.Count -eq 1) -and (-not (Test-Path "$linkFile.tmp"))) 's38-failed-then-retried-filing-links-once' "$($l1.Status) $($l2.Status) $($l3.Status) $($l4.Status) rows=$($linkRows.Count)"

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
$tx2 = Format-ToastXml 't' @('1', '2', '3', '4', '5', '6', '7', '8', '9')
Assert ((@($tx2 -split '<text>').Count) -eq 9) 'toast-truncate'

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
'{"version":1,"stamp":"s","day":"d","identity":"i","verdict":"green","exit":0,"legs":{"run-a":{"ran":true},"run-b":{"ran":true},"interactive":{"ran":true}},"soak":{"verdict":"green"},"env":{"dpi":"primary 96x96"},"timings":{}}' | Set-Content -Path (Join-Path $s17 'noos.result.json') -Encoding UTF8
Assert ((Test-ResultFile (Join-Path $s17 'noos.result.json')).Ok) 'result-missing-os-reads-unknown' ((Test-ResultFile (Join-Path $s17 'noos.result.json')).Error)
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
Assert ((($tsTrend -join "`n") -like '*| skip/- |*')) 'trend-gatesskip'
$tu = [pscustomobject]@{ day = '2026-09-21'; stamp = 'y'; verdict = 'red'; reserve = 1; incidents = @(); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $true; passed = 0; failed = 0; skipped = 0; gate = $null; killed = $false; cut = $false } }; soak = [pscustomobject]@{ verdict = 'skipped' }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; env = [pscustomobject]@{ os = 'o'; powershell = 'p'; dotnet = 'd'; session = 's'; topology = 't'; dpi = 'd'; adapters = 'a'; settings = 's' }; buildError = ''; omissionOk = $true; recovered = 'none'; scheduler = [pscustomobject]@{ voted = $false; faults = @() } }
$tuTrend = Format-TrendTable @($tu) @{ Overdue = @(); DueSoon = @() }
Assert ((($tuTrend -join "`n") -like '*| unproven |*')) 'trend-unproven'
Assert ((($tuTrend -join "`n") -like '*| null/- |*')) 'trend-gatesnull'
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
Assert ($tj -like '*RunA test-seconds (canonical native nights, last 14): n=2, p50 600, p90 700, p95 700 (= max: n=2 < 20), max 700*') 'trend-percentile'
Assert ($tj -like '*## Environments*2026-09-20 2026-09-20-041343*') 'trend-env'
Assert ($tj -like '*Quarantine now: 1 overdue*') 'trend-quar'
Assert ($tj -like '*| 1/0 (oldest 2d) |*') 'trend-qage'
Assert (($tj -like '*| green |*') -and ($tj -like '*| red ui-soak-3 cut=1 |*')) 'trend-soakcell'
Assert ($tj -like '*542/0/9 (100% of 542 executed)*') 'trend-rate'
Assert ($tj -like '*phases build=2s run-a=600s run-b=7s; used 700s / left 9000s (span 9700s); RunA 600s rank 1/2 pct 0*') 'trend-budget'
Assert ($tj -like '*2026-09-21-023001: phases no timings; used unknown / left 12000s; RunA 700s rank 2/2 pct 100*') 'trend-budget-partial'
$taTrend = Format-TrendTable @($t1) @{ Overdue = @([pscustomobject]@{ Test = 'UI.Old'; Due = '2026-09-17' }); DueSoon = @() } ([datetime]'2026-09-21')
Assert ((($taTrend -join "`n") -like '*Quarantine now: 1 overdue, oldest 4d: UI.Old, 0 due within 3 days*')) 'trend-oldest'


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

# D00 T02 §22 item 4: the all-skipped VSTest banner keeps its row, and
# an all-skipped assembly conserves green (observed on SDK 10.0.400).
$s22 = Join-Path $dir 's22'
$null = New-Item -ItemType Directory -Force -Path $s22
$skipLog = Join-Path $s22 'allskip.log'
@('Skipped! - Failed:     0, Passed:     0, Skipped:     2, Total:     2, Duration: 1 ms - UI.dll (net10.0)') | Set-Content -Path $skipLog -Encoding UTF8
$skipRows = @(Get-TranscriptRows $skipLog)
Assert (($skipRows.Count -eq 1) -and ($skipRows[0].Assembly -eq 'UI.dll') -and ($skipRows[0].Skipped -eq 2) -and ($skipRows[0].Total -eq 2)) 'allskip-banner-row' ($skipRows | Out-String)
$skipTrx = Join-Path $s22 'allskip.trx'
'<TestRun><Results><UnitTestResult testName="UI.Q1" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-25 D01-T01-S8 fx</Message></ErrorInfo></Output></UnitTestResult><UnitTestResult testName="UI.Q2" outcome="NotExecuted"><Output><ErrorInfo><Message>QUARANTINED 2026-09-25 D01-T01-S8 fx</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>' | Set-Content -Path $skipTrx -Encoding UTF8
$skipCons = Test-CountConservation 'Run B' @($skipTrx) @($skipLog) $true @()
Assert ($skipCons.Ok) 'allskip-conserves-green' ($skipCons.Breaks -join '; ')
$skipLeg = Get-LegSummary @($skipTrx) @($skipLog)
Assert (($null -ne $skipLeg) -and ($skipLeg.SkippedCount -eq 2) -and ($skipLeg.Assemblies -eq 'UI.dll 0/0/2')) 'allskip-leg-cell' ($skipLeg | Out-String)
$oldLog = Join-Path $s22 'oldbanner.log'
@('Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 8 ms - Smoke.dll (net10.0)') | Set-Content -Path $oldLog -Encoding UTF8
Assert (@(Get-TranscriptRows $oldLog).Count -eq 1) 'allskip-passed-banner-still-parses'

# D00 T02 §22 item 3: the incident identity contract.
$stackA = "   at FlaUI.Core.Tools.Com.Call[T](Func``1 nativeAction)`n   at FlaUI.UIA3.UIA3Automation.FromHandle(IntPtr hwnd)`n   at UI.UiApp.Attach(Application app) in R:\x\tests\UI\UiApp.cs:line 22`n   at UI.LaunchTests.LargeFileOpensResponsively() in R:\x\tests\UI\LaunchTests.cs:line 422`n   at System.RuntimeMethodHandle.InvokeMethod(ObjectHandleOnStack target)"
$stackMoved = $stackA.Replace('line 22', 'line 31').Replace('line 422', 'line 450')
$hrA = [pscustomobject]@{ Test = 'UI.LaunchTests.LargeFileOpensResponsively'; Message = "System.TimeoutException : UIA Timeout`n---- System.Runtime.InteropServices.COMException : Operation timed out. (0x80131505)"; Where = 'Run A'; Stack = $stackA }
$hrB = [pscustomobject]@{ Test = 'UI.LaunchTests.LargeFileOpensResponsively'; Message = "System.TimeoutException : UIA Timeout`n---- System.Runtime.InteropServices.COMException : Unspecified error (0x80004005)"; Where = 'Run A'; Stack = $stackA }
$hrRepeat = [pscustomobject]@{ Test = 'UI.LaunchTests.LargeFileOpensResponsively'; Message = "System.TimeoutException : UIA Timeout`n---- System.Runtime.InteropServices.COMException : Operation timed out. (0x80131505)"; Where = 'Run A'; Stack = $stackMoved }
$hrGroups = @(Get-IncidentGroups @($hrA, $hrB, $hrRepeat))
Assert ($hrGroups.Count -eq 2) 'incident-hresult-splits' (($hrGroups | ForEach-Object { $_.Key }) -join ' || ')
Assert ((@($hrGroups | Where-Object { $_.Wheres.Count -eq 2 }).Count -eq 1)) 'incident-true-repeat-merges' (($hrGroups | ForEach-Object { "$($_.Id) x$($_.Wheres.Count)" }) -join ', ')
Assert ((Get-StackSignature $stackA) -eq 'FlaUI.Core.Tools.Com.Call[T] < FlaUI.UIA3.UIA3Automation.FromHandle < UI.UiApp.Attach') 'incident-stack-signature' (Get-StackSignature $stackA)
Assert ((Get-StackSignature "   at UI.T.<>c__DisplayClass12_0.<Run>b__3_1() in a.cs:line 9`n   at UI.T.<Go>d__5.MoveNext()") -eq (Get-StackSignature "   at UI.T.<>c__DisplayClass7_2.<Run>b__1_0() in a.cs:line 40`n   at UI.T.<Go>d__9.MoveNext()")) 'incident-stack-ordinals-collapse'
Assert ((Get-StackSignature '') -eq 'nostack') 'incident-stack-empty'
Assert ((Get-FailureClass "Assert.Equal() Failure: Values differ`nExpected: 2`nActual:   3") -eq 'Assert.Equal() Failure') 'incident-class-assert'
Assert ((Get-FailureClass 'System.TimeoutException : UIA Timeout') -eq 'System.TimeoutException') 'incident-class-exception'
Assert ((Get-FailureClass 'code 0x80131505 after 12 tries') -eq 'msg:code 0x80131505 after # tries') 'incident-class-fallback-keeps-hresult'
$eqA = [pscustomobject]@{ Test = 'UI.T.Counts'; Message = "Assert.Equal() Failure: Values differ`nExpected: 2`nActual:   3"; Where = 'ui-soak-1'; Stack = '   at UI.T.Counts() in T.cs:line 10' }
$eqB = [pscustomobject]@{ Test = 'UI.T.Counts'; Message = "Assert.Equal() Failure: Values differ`nExpected: 4`nActual:   7"; Where = 'ui-soak-4'; Stack = '   at UI.T.Counts() in T.cs:line 12' }
$nn = [pscustomobject]@{ Test = 'UI.T.Counts'; Message = 'Assert.NotNull() Failure: Value is null'; Where = 'ui-soak-2'; Stack = '   at UI.T.Counts() in T.cs:line 10' }
$other = [pscustomobject]@{ Test = 'UI.T.Counts'; Message = "Assert.Equal() Failure: Values differ`nExpected: 2`nActual:   3"; Where = 'Run A'; Stack = '   at UI.T.Counts() in T.cs:line 10' }
$cg = @(Get-IncidentGroups @($eqA, $eqB, $nn, $other))
Assert ($cg.Count -eq 3) 'incident-class-and-phase-split' (($cg | ForEach-Object { $_.Key }) -join ' || ')
Assert (($cg[0].Wheres -join ',') -eq 'ui-soak-1,ui-soak-4') 'incident-soak-iterations-merge' ($cg[0].Wheres -join ',')
# Golden ids pin the contract: a normalization change that would split
# or merge history fails here before it reaches a night.
Assert ((Get-IncidentKey $hrA) -eq 'v2|UI.LaunchTests.LargeFileOpensResponsively|run-a|System.TimeoutException|0x80131505|FlaUI.Core.Tools.Com.Call[T] < FlaUI.UIA3.UIA3Automation.FromHandle < UI.UiApp.Attach') 'incident-golden-key' (Get-IncidentKey $hrA)
Assert ($hrGroups[0].Id -eq 'INC-9990c490') 'incident-golden-id-hresult' $hrGroups[0].Id
Assert ($cg[0].Id -eq 'INC-b7ad6ae4') 'incident-golden-id-assert' $cg[0].Id

# Structured trx failures: message plus stack plus passed names.
$stTrx = Join-Path $s22 'stack.trx'
'<TestRun><Results><UnitTestResult testName="UI.Ok" outcome="Passed" /><UnitTestResult testName="UI.Bad" outcome="Failed"><Output><ErrorInfo><Message>System.TimeoutException : UIA Timeout</Message><StackTrace>   at UI.UiApp.Attach() in UiApp.cs:line 22</StackTrace></ErrorInfo></Output></UnitTestResult></Results></TestRun>' | Set-Content -Path $stTrx -Encoding UTF8
$stSum = Get-TrxSummary $stTrx
Assert ((@($stSum.FailedDetail).Count -eq 1) -and ($stSum.FailedDetail[0].Stack -like '*UiApp.Attach*') -and ($stSum.FailedDetail[0].Message -like 'System.TimeoutException*')) 'trx-failed-detail' ($stSum.FailedDetail | Out-String)
Assert ((@($stSum.PassedNames) -join ',') -eq 'UI.Ok') 'trx-passed-names' (@($stSum.PassedNames) -join ',')

# D00 T02 §22 item 6: the incident lifecycle.
$qDoc = Join-Path $s22 'quarantine.md'
@('# Soak', '', '## Quarantine list', '', '| Test | Failure signature | First seen | Owner | Quarantined | Due |', '| ---- | ----------------- | ---------- | ----- | ----------- | --- |', '| `UI.T.Counts` (`counts-race`) | sig | 2026-09-20 | D01 T01 §3 | 2026-09-20 | 2026-09-27 |', '', '## Removal decisions') | Set-Content -Path $qDoc -Encoding UTF8
$owners = Get-QuarantineOwners $qDoc
Assert (($owners.Count -eq 1) -and ($owners['UI.T.Counts'] -eq 'D01 T01 §3')) 'lifecycle-owner-from-quarantine' ($owners | Out-String)
$ledgerFx = Join-Path $s22 'incidents.json'
$l0 = Read-IncidentLedger $ledgerFx
Assert ($l0.Ok -and ($l0.Incidents.Count -eq 0)) 'lifecycle-missing-reads-empty'
$u1 = Update-IncidentLedger $l0.Incidents @(Get-IncidentGroups @($eqA, $hrA)) '2026-09-25-023005' @{ 'run-a' = @('UI.Ok') } $owners
Assert ((@($u1.Lines | Where-Object { $_ -like '*: new (owner*' }).Count -eq 2) -and ($u1.Incidents.Count -eq 2)) 'lifecycle-creates-once' ($u1.Lines -join ' | ')
Assert (@($u1.Lines | Where-Object { $_ -like '*UI.T.Counts*new (owner D01 T01 §3)*' }).Count -eq 1) 'lifecycle-assigns-owner' ($u1.Lines -join ' | ')
Assert ((Write-IncidentLedger $u1.Incidents $ledgerFx) -eq '') 'lifecycle-write-readback'
$l1 = Read-IncidentLedger $ledgerFx
$u2 = Update-IncidentLedger $l1.Incidents @(Get-IncidentGroups @($eqB)) '2026-09-26-023005' @{ 'run-a' = @('UI.LaunchTests.LargeFileOpensResponsively'); 'ui-soak' = @() } $owners
$eqId = (@(Get-IncidentGroups @($eqA)))[0].Id
$hrId = (@(Get-IncidentGroups @($hrA)))[0].Id
Assert (($u2.Incidents.Count -eq 2) -and (@($u2.Incidents[$eqId].occurrences).Count -eq 2) -and ($u2.Incidents[$eqId].state -eq 'open')) 'lifecycle-repeat-appends' ($u2.Lines -join ' | ')
Assert (($u2.Incidents[$hrId].state -eq 'open') -and (@($u2.Lines | Where-Object { $_ -like "*$hrId*recovering (passed in run-a on 1 of 3 runs)*" }).Count -eq 1)) 'lifecycle-one-pass-is-not-recovery' ($u2.Lines -join ' | ')
$null = Write-IncidentLedger $u2.Incidents $ledgerFx
$l2 = Read-IncidentLedger $ledgerFx
Assert ([int]$l2.Incidents[$hrId].passStreak -eq 1) 'lifecycle-streak-persists' "$($l2.Incidents[$hrId].passStreak)"
$u2b = Update-IncidentLedger $l2.Incidents @(Get-IncidentGroups @($eqB)) '2026-09-26-023005' @{ 'run-a' = @('UI.LaunchTests.LargeFileOpensResponsively') } $owners
Assert ((@($u2b.Incidents[$eqId].occurrences).Count -eq 2) -and ([int]$u2b.Incidents[$hrId].passStreak -eq 1)) 'lifecycle-idempotent-per-stamp' "occ $(@($u2b.Incidents[$eqId].occurrences).Count) streak $($u2b.Incidents[$hrId].passStreak)"
$u3 = Update-IncidentLedger $l2.Incidents @() '2026-09-27-023005' @{ 'run-a' = @('UI.T.Counts', 'UI.LaunchTests.LargeFileOpensResponsively') } $owners
Assert ($u3.Incidents[$eqId].state -eq 'open') 'lifecycle-other-phase-pass-keeps-open' $u3.Incidents[$eqId].state
$u3b = Update-IncidentLedger $u3.Incidents @() '2026-09-28-023005' @{ 'run-a' = @('UI.LaunchTests.LargeFileOpensResponsively') } $owners
Assert (($u3b.Incidents[$hrId].state -eq 'closed') -and (@($u3b.Lines | Where-Object { $_ -like "*$hrId*CLOSED (verified recovery: passed in run-a on 3 runs*" }).Count -eq 1)) 'lifecycle-recovery-closes' ($u3b.Lines -join ' | ')
$lR = Read-IncidentLedger $ledgerFx
$uReset = Update-IncidentLedger $lR.Incidents @(Get-IncidentGroups @($hrRepeat)) '2026-09-28-023005' @{} $owners
Assert (($uReset.Incidents[$hrId].state -eq 'open') -and ([int]$uReset.Incidents[$hrId].passStreak -eq 0)) 'lifecycle-failure-resets-streak' "$($uReset.Incidents[$hrId].state) $($uReset.Incidents[$hrId].passStreak)"
$u4 = Update-IncidentLedger $u3b.Incidents @(Get-IncidentGroups @($hrRepeat)) '2026-09-29-023005' @{} $owners
Assert (($u4.Incidents[$hrId].state -eq 'open') -and (@($u4.Lines | Where-Object { $_ -like "*$hrId*REOPENED*" }).Count -eq 1) -and (@($u4.Incidents[$hrId].occurrences).Count -eq 2)) 'lifecycle-reopens-with-history' ($u4.Lines -join ' | ')
'{ not json' | Set-Content -Path (Join-Path $s22 'bad.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'bad.json')).Ok -eq $false) 'lifecycle-corrupt-fails-closed'
'{"version":1}' | Set-Content -Path (Join-Path $s22 'noarray.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'noarray.json')).Error -like '*no incidents array*') 'lifecycle-missing-array-fails-closed' (Read-IncidentLedger (Join-Path $s22 'noarray.json')).Error
$goodEntry = '{"id":"INC-0123abcd","test":"UI.X","phase":"run-a","key":"k","state":"open","firstSeen":"s","lastSeen":"s","occurrences":[{"stamp":"s","wheres":["Run A"]}]}'
('{"version":1,"incidents":[' + $goodEntry + ',' + $goodEntry + ']}') | Set-Content -Path (Join-Path $s22 'dup.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'dup.json')).Error -like '*duplicate id INC-0123abcd*') 'lifecycle-duplicate-id-fails-closed' (Read-IncidentLedger (Join-Path $s22 'dup.json')).Error
('{"version":1,"incidents":[{"id":"INC-0123abcd","test":"UI.X","state":"open"}]}') | Set-Content -Path (Join-Path $s22 'thin.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'thin.json')).Error -like '*lacks phase*') 'lifecycle-missing-field-fails-closed' (Read-IncidentLedger (Join-Path $s22 'thin.json')).Error
('{"version":1,"incidents":[' + $goodEntry + ']}') | Set-Content -Path (Join-Path $s22 'one.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'one.json')).Ok) 'lifecycle-valid-entry-reads'
('{"version":1,"incidents":[' + $goodEntry.Replace('[{"stamp":"s","wheres":["Run A"]}]', '[null]') + ']}') | Set-Content -Path (Join-Path $s22 'nullocc.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'nullocc.json')).Error -like '*null occurrence*') 'lifecycle-null-occurrence-fails-closed' (Read-IncidentLedger (Join-Path $s22 'nullocc.json')).Error
('{"version":1,"incidents":[' + $goodEntry.Replace('{"stamp":"s","wheres":["Run A"]}', '{"wheres":["Run A"]}') + ']}') | Set-Content -Path (Join-Path $s22 'nostamp.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'nostamp.json')).Error -like '*occurrence without a stamp*') 'lifecycle-stampless-occurrence-fails-closed' (Read-IncidentLedger (Join-Path $s22 'nostamp.json')).Error
('{"version":1,"incidents":[' + $goodEntry.Replace('{"stamp":"s","wheres":["Run A"]}', '{"stamp":"s"}') + ']}') | Set-Content -Path (Join-Path $s22 'nowheres.json') -Encoding UTF8
Assert ((Read-IncidentLedger (Join-Path $s22 'nowheres.json')).Error -like '*lacks wheres*') 'lifecycle-whereless-occurrence-fails-closed' (Read-IncidentLedger (Join-Path $s22 'nowheres.json')).Error
$lX = Read-IncidentLedger $ledgerFx
$xId = (@(Get-IncidentGroups @($hrA)))[0].Id
$lX.Incidents[$xId].state = 'open'; $lX.Incidents[$xId].passStreak = 2; $lX.Incidents[$xId].lastPassStamp = '2026-09-27-023005'
$uX = Update-IncidentLedger $lX.Incidents @(Get-IncidentGroups @($hrB)) '2026-09-30-023005' @{ 'run-a' = @('UI.LaunchTests.LargeFileOpensResponsively') } $owners
Assert (([int]$uX.Incidents[$xId].passStreak -eq 0) -and ($uX.Incidents[$xId].state -eq 'open') -and (@($uX.Lines | Where-Object { $_ -like "*$xId*streak reset*" }).Count -eq 1)) 'lifecycle-different-failure-resets-streak' ($uX.Lines -join ' | ')

# D00 T02 §22 item 1: the failure-capture policy.
$planted = 'pid=1 chrome: token ' + 'ghp_' + ('A1b2C3d4E5' * 4)
Assert ((@(Test-CaptureSecrets $planted) -join ',') -eq 'github-token') 'capture-planted-secret-fails-scan' (@(Test-CaptureSecrets $planted) -join ',')
Assert (@(Test-CaptureSecrets 'pid=4 ScratchPad: Untitled - ScratchPad').Count -eq 0) 'capture-clean-text-passes'
Assert (@(Test-CaptureSecrets ('password = ' + 'hunter2hunter2')).Count -eq 1) 'capture-assigned-secret'
Assert (@(Test-CaptureSecrets ('password = "' + 'hunter2hunter2"')).Count -eq 1) 'capture-assigned-secret-quoted'
Assert (@(Test-CaptureSecrets ('{"password":"' + 'hunter2hunter2"}')).Count -eq 1) 'capture-assigned-secret-json'
Assert (@(Test-CaptureSecrets ('token=' + 'abcdefghi')).Count -eq 1) 'capture-assigned-secret-bare-token'
Assert (@(Test-CaptureSecrets 'tokens used: 123456').Count -eq 0) 'capture-token-count-is-not-a-secret'
Assert ((Format-WindowRow 7 'chrome' 'Bank statement - Chrome' $false) -eq 'pid=7 chrome: [title redacted]') 'capture-foreign-title-redacted'
Assert ((Format-WindowRow 9 'ScratchPad' 'big8.txt - ScratchPad' $true) -eq 'pid=9 ScratchPad: big8.txt - ScratchPad') 'capture-owned-title-kept'
Assert ((Format-WindowRow 3 'pwsh' 'R:\private\path - pwsh' $true) -eq 'pid=3 pwsh: [title redacted]') 'capture-operator-shell-title-redacted'
Assert ((Format-WindowRow 8 'ScratchPad' 'diary.txt - ScratchPad' $false) -eq 'pid=8 ScratchPad: [title redacted]') 'capture-operator-scratchpad-title-redacted'
$t0 = Get-Date '2026-09-25T02:30:00'
$procs = @(
  [pscustomobject]@{ ProcessId = 100; ParentProcessId = 4; Created = $t0 },
  [pscustomobject]@{ ProcessId = 200; ParentProcessId = 100; Created = $t0.AddSeconds(5) },
  [pscustomobject]@{ ProcessId = 300; ParentProcessId = 200; Created = $t0.AddSeconds(9) },
  [pscustomobject]@{ ProcessId = 400; ParentProcessId = 999; Created = $t0.AddSeconds(9) },
  [pscustomobject]@{ ProcessId = 500; ParentProcessId = 100; Created = $t0.AddHours(-3) }
)
$tree = Get-DescendantPids $procs 100
Assert ((@($tree.Keys | Sort-Object) -join ',') -eq '100,200,300') 'capture-owned-pids-descend-from-run' (@($tree.Keys | Sort-Object) -join ',')
$capFx = Join-Path $s22 'captures-run-a'
$null = New-Item -ItemType Directory -Force -Path $capFx
$planted | Set-Content -Path (Join-Path $capFx 'run-a-windows.txt') -Encoding UTF8
'12:00:01 id=1000 Error App: crashed' | Set-Content -Path (Join-Path $capFx 'run-a-events.txt') -Encoding UTF8
[System.IO.File]::WriteAllBytes((Join-Path $capFx 'run-a-failure.png'), (New-Object byte[] 4096))
$capNotes = @(Protect-CaptureDir $capFx 'run-a')
$winAfter = Get-Content (Join-Path $capFx 'run-a-windows.txt') -Raw
Assert (($winAfter -notlike '*ghp_*') -and ($winAfter -like '*redacted by the secret scan: github-token*')) 'capture-secret-redacted-whole' $winAfter
Assert (@($capNotes | Where-Object { $_ -like '*SECRET-SCAN redacted run-a-windows.txt (github-token)*' }).Count -eq 1) 'capture-secret-noted' ($capNotes -join ' | ')
Assert ((Get-Content (Join-Path $capFx 'run-a-events.txt') -Raw) -like '*crashed*') 'capture-clean-file-untouched'
Assert (Test-Path (Join-Path $capFx 'run-a-failure.png')) 'capture-under-cap-keeps-screenshot'
# A capture the scan cannot read is never kept unscanned: while another
# handle holds it exclusively, neither read nor delete can succeed, and
# the note says so loudly.
$lockedCap = Join-Path $capFx 'run-a-locked.txt'
$planted | Set-Content -Path $lockedCap -Encoding UTF8
$lockHandle = [System.IO.File]::Open($lockedCap, 'Open', 'ReadWrite', 'None')
try { $lockNotes = @(Protect-CaptureDir $capFx 'run-a') } finally { $lockHandle.Dispose() }
Assert (@($lockNotes | Where-Object { $_ -like '*SECRET-SCAN FAILED: run-a-locked.txt could not be scanned*do not retain this run*' }).Count -eq 1) 'capture-unscannable-undeletable-fails-loud' ($lockNotes -join ' | ')
Assert ((Get-Content (Join-Path $capFx 'SECRET-SCAN-FAILED.txt') -Raw) -like '*run-a-locked.txt*') 'capture-failure-marker-persists'
$retOk = Test-RetainableCaptures $s22
Assert ((-not $retOk.Ok) -and (@($retOk.Reasons | Where-Object { $_ -like '*SECRET-SCAN-FAILED.txt present*' }).Count -eq 1) -and (@($retOk.Reasons | Where-Object { $_ -like '*run-a-locked.txt holds github-token*' }).Count -eq 1)) 'capture-retain-refuses-marker-and-secret' ($retOk.Reasons -join ' | ')
$lockNotes2 = @(Protect-CaptureDir $capFx 'run-a')
Assert ((@($lockNotes2 | Where-Object { $_ -like '*SECRET-SCAN redacted run-a-locked.txt*' }).Count -eq 1)) 'capture-rescan-after-unlock-redacts' ($lockNotes2 -join ' | ')
$capWas = $script:CaptureMaxBytes
$script:CaptureMaxBytes = 1024
$capNotes2 = @(Protect-CaptureDir $capFx 'run-a')
$script:CaptureMaxBytes = $capWas
Assert ((-not (Test-Path (Join-Path $capFx 'run-a-failure.png'))) -and (@($capNotes2 | Where-Object { $_ -like '*size cap dropped run-a-failure.png*' }).Count -eq 1)) 'capture-over-cap-drops-screenshot' ($capNotes2 -join ' | ')


# D00 T02 §23: acknowledgements bind to runs, dispositions structure,
# deadlines escalate, demands dedupe, and git history is the record.
$s23 = Join-Path $dir 's23'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $s23 'build\nightly\retained\copy')
function New-RedResult([string]$Path, [string]$Identity, [string]$Day, [string[]]$Incidents, [string]$Verdict = 'red') {
  $o = [pscustomobject]@{ version = 1; stamp = $Identity.Substring(0, 17); day = $Day; identity = $Identity; verdict = $Verdict; exit = $(if ($Verdict -eq 'green') { 0 } else { 1 }); incidents = @($Incidents) }
  (ConvertTo-Json $o -Depth 5) | Set-Content -Path $Path -Encoding UTF8
}
$runA1 = '2026-09-22-023001-pid100'
$runA2 = '2026-09-22-120501-pid200'
$runOld = '2026-09-20-023001-pid300'
$nd = Join-Path $s23 'build\nightly'
New-RedResult (Join-Path $nd "morning-$($runA1.Substring(0, 17)).result.json") $runA1 '2026-09-22' @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
Copy-Item (Join-Path $nd "morning-$($runA1.Substring(0, 17)).result.json") (Join-Path $nd 'retained\copy\result.json')
New-RedResult (Join-Path $nd "morning-$($runA2.Substring(0, 17)).result.json") $runA2 '2026-09-22' @()
New-RedResult (Join-Path $nd "morning-$($runOld.Substring(0, 17)).result.json") $runOld '2026-09-20' @()
New-RedResult (Join-Path $nd 'morning-2026-09-22-130000.result.json') '2026-09-22-130000-pid400' '2026-09-22' @() 'green'
$resFiles = @(Get-ChildItem $nd -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName }) + @((Join-Path $nd 'retained\copy\result.json'))
$dem = Get-AckDemands $resFiles
Assert (($dem.Count -eq 3) -and ($dem.ContainsKey($runA1)) -and ($dem.ContainsKey($runA2)) -and (-not $dem.ContainsKey('2026-09-22-130000-pid400'))) 'ack-demand-per-red-run' ((@($dem.Keys) | Sort-Object) -join ',')
Assert ((@($dem[$runA1].Shas).Count -eq 1) -and (@($dem[$runA1].Paths).Count -eq 2)) 'ack-rerun-copies-demand-once' "shas $(@($dem[$runA1].Shas).Count) paths $(@($dem[$runA1].Paths).Count)"
Assert ((@($dem[$runA1].Incidents) -join ',') -eq 'INC-aaaa1111') 'ack-demand-carries-incidents'
$shaA1 = $dem[$runA1].Shas[0]
$shaA2 = $dem[$runA2].Shas[0]
function New-Ack([string[]]$Runs, [hashtable]$Over = @{}) {
  $sect = [string][char]0xA7
  $f = [ordered]@{ 'ack-version' = '2'; owner = 'operator'; disposition = 'filed'; 'corrective-owner' = "D00 T02 ${sect}9"; due = '2026-09-30'; finding = "D00 T02 ${sect}29"; signed = '2026-09-25'; incidents = 'INC-aaaa1111' }
  foreach ($k in $Over.Keys) { $f[$k] = $Over[$k] }
  $lines = @('---')
  foreach ($r in $Runs) { $lines += "run: $r" }
  foreach ($k in $f.Keys) { if ($null -ne $f[$k]) { $lines += "${k}: $($f[$k])" } }
  $lines += @('---', '', 'Why: the failing run was triaged and filed.')
  return ($lines -join "`n")
}
$ackOne = New-Ack @("$runA1 sha256:$shaA1")
$v1 = Test-AckV2 $ackOne $dem
Assert ($v1.Ok -and ((@($v1.Acked) -join ',') -eq $runA1)) 'ack-v2-valid' ($v1.Errors -join '; ')
$gate0 = @($dem.Keys | Where-Object { @($v1.Acked) -notcontains $_ })
Assert ($gate0 -contains $runA2) 'ack-same-day-second-red-stays-unacked' ($gate0 -join ',')
$prose = "Owner: operator. 2026-09-22 acknowledged. " + ('This run failed and the cause is known and understood by the operator. ' * 5)
Assert ((Test-AckV2 $prose $dem).Errors -contains 'no frontmatter') 'ack-prose-without-disposition-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ disposition = $null }) $dem).Errors | Where-Object { $_ -eq 'missing disposition' }).Count -eq 1) 'ack-missing-disposition-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ disposition = 'looked-at-it' }) $dem).Errors | Where-Object { $_ -like "disposition 'looked-at-it' not one of*" }).Count -eq 1) 'ack-unknown-disposition-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ 'corrective-owner' = 'TBD' }) $dem).Errors | Where-Object { $_ -eq 'corrective-owner is a placeholder' }).Count -eq 1) 'ack-placeholder-owner-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ due = '2026-09-20' }) $dem).Errors | Where-Object { $_ -eq 'due precedes signed' }).Count -eq 1) 'ack-due-before-signed-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ finding = 'see chat' }) $dem).Errors | Where-Object { $_ -like "finding 'see chat'*" }).Count -eq 1) 'ack-unlinked-finding-fails'
Assert (@((Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1") @{ incidents = 'none' }) $dem).Errors | Where-Object { $_ -eq 'incidents missing: INC-aaaa1111' }).Count -eq 1) 'ack-must-name-run-incidents'
Assert (@((Test-AckV2 (New-Ack @("2026-09-22-999999-pid9 sha256:$shaA1")) $dem).Errors | Where-Object { $_ -like 'run * is not a known RED' }).Count -eq 1) 'ack-unknown-run-fails'
$both = Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1", "$runA2 sha256:$shaA2")) $dem
Assert ($both.Ok -and (@($both.Acked).Count -eq 2)) 'ack-batch-names-each-run' ($both.Errors -join '; ')
$stale = Test-AckV2 (New-Ack @("$runA1 sha256:$('0' * 64)")) $dem
Assert ((@($stale.Stale) -join ',') -eq $runA1) 'ack-changed-result-reads-stale' ("stale $(@($stale.Stale) -join ',') errs $($stale.Errors -join '; ')")

# The gate over a real git repo: committed acks count, uncommitted and
# dirty ones do not, history quotes every edit, v1 day files stop at
# the cutover, and past-due demands escalate with a staged filing.
$repo = Join-Path $s23 'repo'
$ackDir = Join-Path $repo 'docs\nightly-acks'
$null = New-Item -ItemType Directory -Force -Path $ackDir
& git -C $repo init -q 2>$null
& git -C $repo config user.name 'Fixture Operator'
& git -C $repo config user.email 'fixture@example.invalid'
& git -C $repo config commit.gpgsign false
& git -C $repo config core.autocrlf false
$null = New-Item -ItemType Directory -Force -Path (Join-Path $repo 'todo\00-workspace')
@('# fixture', '', '## 9. Nine', '', 'Tracks INC-aaaa1111 (UI.A) and INC-bbbb2222 (UI.B).', '', '## 29. Twenty-nine', '', 'Tracks INC-aaaa1111 (UI.A) and INC-bbbb2222 (UI.B).') | Set-Content -Path (Join-Path $repo 'todo\00-workspace\TODO-02-fixture.md') -Encoding UTF8
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-a.md'), $ackOne)
$g0 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ((@($g0.Lines | Where-Object { $_ -like '*ack-2026-09-22-a.md: uncommitted*' }).Count -eq 1) -and ($g0.Unacked -contains $runA1)) 'ack-uncommitted-ignored' ($g0.Lines -join ' | ')
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack a' 2>$null
$g1 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($g1.Unacked -notcontains $runA1) -and ($g1.Unacked -contains $runA2) -and ($g1.Unacked -contains $runOld)) 'ack-committed-counts' (($g1.Unacked -join ',') + ' || ' + ($g1.Lines -join ' | '))
$edited = $ackOne.Replace('Why: the failing run was triaged and filed.', 'Why: triaged, filed, and the fix is queued.')
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-a.md'), $edited)
$g2 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ((@($g2.Lines | Where-Object { $_ -like '*edited since its last commit*' }).Count -eq 1) -and ($g2.Unacked -contains $runA1)) 'ack-dirty-edit-ignored' ($g2.Lines -join ' | ')
& git -C $repo commit -q -am 'ack a edited' 2>$null
$g3 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
$hl = @($g3.Lines | Where-Object { $_ -like '*ack-2026-09-22-a.md: acknowledges*' })
Assert (($hl.Count -eq 1) -and (([regex]::Matches($hl[0], 'Fixture Operator')).Count -eq 2)) 'ack-edit-history-quoted' ($g3.Lines -join ' | ')
$v1Text = 'Owner: operator. Signed: 2026-09-20. ' + ('The 2026-09-20 run failed on an infrastructure fault that was diagnosed and fixed. ' * 3)
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-20.md'), $v1Text)
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22.md'), $v1Text.Replace('2026-09-20', '2026-09-22'))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'v1 files' 2>$null
$g4 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($g4.Unacked -notcontains $runOld) -and (@($g4.Lines | Where-Object { $_ -like '*ack-2026-09-20.md: v1 legacy, acknowledges 1 run(s)*' }).Count -eq 1)) 'ack-v1-before-cutover-counts' ($g4.Lines -join ' | ')
Assert (($g4.Unacked -contains $runA2) -and (@($g4.Lines | Where-Object { $_ -like '*ack-2026-09-22.md: v1 day file after the 2026-09-21 cutover*' }).Count -eq 1)) 'ack-v1-after-cutover-ignored' ($g4.Lines -join ' | ')
Assert ((@($g4.Overdue).Count -eq 0) -and (@($g4.Lines | Where-Object { $_ -like "*UNACKED $runA2 (RED 2026-09-22, due 2026-09-25T23:59:59*)*" }).Count -eq 1)) 'ack-due-date-shown' ($g4.Lines -join ' | ')
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-b.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ finding = 'deadbeef'; incidents = 'none' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack b bogus commit' 2>$null
$g4b = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($g4b.Unacked -contains $runA2) -and (@($g4b.Lines | Where-Object { $_ -like '*ack-2026-09-22-b.md: INVALID (finding deadbeef not found)*' }).Count -eq 1)) 'ack-invented-commit-fails' ($g4b.Lines -join ' | ')
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-b.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ finding = "D99 T99 $([char]0xA7)999"; incidents = 'none' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack b bogus section' 2>$null
Assert (@((Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')).Lines | Where-Object { $_ -like '*ack-2026-09-22-b.md: INVALID (finding D99 T99*999 not found)*' }).Count -eq 1) 'ack-invented-section-fails'
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-b.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ finding = 'INC-deadbeef'; incidents = 'none' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack b bogus incident' 2>$null
Assert (@((Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')).Lines | Where-Object { $_ -like '*ack-2026-09-22-b.md: INVALID (finding INC-deadbeef not found)*' }).Count -eq 1) 'ack-invented-incident-fails'
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-b.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ finding = 'INC-aaaa1111'; incidents = 'none'; evidence = "D00 T02 $([char]0xA7)9" }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack b known incident' 2>$null
Assert ((Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')).Unacked -notcontains $runA2) 'ack-known-incident-passes'
# Section 39 item 7: a `fixed` commit must touch code; the fixture's
# fix commit touches the failing test's file.
$null = New-Item -ItemType Directory -Force -Path (Join-Path $repo 'tests\UI')
'class A {}' | Set-Content -Path (Join-Path $repo 'tests\UI\A.cs') -Encoding UTF8
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'fix UI.A' 2>$null
$realSha = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-b.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ finding = $realSha.Substring(0, 12); incidents = 'none'; disposition = 'fixed' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack b real commit' 2>$null
$g4c = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ($g4c.Unacked -notcontains $runA2) 'ack-real-commit-finding-passes' ($g4c.Lines -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-b.md') 2>$null; & git -C $repo commit -q -m 'drop ack b' 2>$null
# R1-F3: a v2 ack with a day-shaped name is still v2.
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-23.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'v2 with a day name' 2>$null
$g4d = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($g4d.Unacked -notcontains $runA2) -and (@($g4d.Lines | Where-Object { $_ -like "*ack-2026-09-23.md: acknowledges $runA2*" }).Count -eq 1)) 'ack-v2-day-named-file-counts' ($g4d.Lines -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-23.md') 2>$null; & git -C $repo commit -q -m 'drop day-named v2' 2>$null
# R2-F3: a renamed ack keeps its whole history.
& git -C $repo mv (Join-Path $ackDir 'ack-2026-09-22-a.md') (Join-Path $ackDir 'ack-2026-09-22-renamed.md') 2>$null; & git -C $repo commit -q -m 'rename ack a' 2>$null
$g4e = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
$hr = @($g4e.Lines | Where-Object { $_ -like '*ack-2026-09-22-renamed.md: acknowledges*' })
Assert (($hr.Count -eq 1) -and (([regex]::Matches($hr[0], 'Fixture Operator')).Count -eq 3)) 'ack-rename-keeps-history' ($g4e.Lines -join ' | ')
& git -C $repo mv (Join-Path $ackDir 'ack-2026-09-22-renamed.md') (Join-Path $ackDir 'ack-2026-09-22-a.md') 2>$null; & git -C $repo commit -q -m 'rename back' 2>$null
$g5 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-28')
Assert ((($g5.Overdue) -contains $runA2) -and (@($g5.Lines | Where-Object { $_ -like "*OVERDUE ack: $runA2 (RED 2026-09-22, due 2026-09-25T23:59:59*, 3 day(s) overdue): escalate operator*" }).Count -eq 1)) 'ack-past-deadline-escalates' ($g5.Lines -join ' | ')
Assert (@($g5.Staged | Where-Object { $_ -like "*STAGED ack-overdue $runA2 *" }).Count -eq 1) 'ack-past-deadline-stages-finding' ($g5.Staged -join ' | ')
# R1-F1: a newer rewrite of the result makes an ack that matches only the
# older retained copy stale.
$primaryA1 = Join-Path $nd "morning-$($runA1.Substring(0, 17)).result.json"
(Get-Item (Join-Path $nd 'retained\copy\result.json')).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-10)
New-RedResult $primaryA1 $runA1 '2026-09-22' @('- INC-aaaa1111 `UI.A` x1 (Run A): boom', '- INC-bbbb2222 `UI.B` x1 (Run A): later')
$demNew = Get-AckDemands $resFiles
Assert ((@($demNew[$runA1].Shas).Count -eq 2) -and ($demNew[$runA1].Current -ne $shaA1)) 'ack-current-is-newest-copy' "shas $(@($demNew[$runA1].Shas).Count)"
$staleOld = Test-AckV2 $ackOne $demNew
Assert ((@($staleOld.Stale) -join ',') -eq $runA1) 'ack-older-copy-cannot-ack-changed-result' ("stale $(@($staleOld.Stale) -join ',') acked $(@($staleOld.Acked) -join ',')")
# R2-F1: a batch keeps acknowledging its unchanged run while the other
# goes stale, even though it lists the stale run's old incidents.
$batch = Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1", "$runA2 sha256:$shaA2") @{ incidents = 'INC-aaaa1111' }) $demNew
Assert ($batch.Ok -and ((@($batch.Acked) -join ',') -eq $runA2) -and ((@($batch.Stale) -join ',') -eq $runA1)) 'ack-batch-survives-a-stale-run' ("ok $($batch.Ok) acked $(@($batch.Acked) -join ',') stale $(@($batch.Stale) -join ',') errs $($batch.Errors -join '; ')")
# R2-F2: incidents follow the current copy: a rewrite that drops one is
# acknowledged by what it says now.
Start-Sleep -Milliseconds 50
New-RedResult $primaryA1 $runA1 '2026-09-22' @('- INC-bbbb2222 `UI.B` x1 (Run A): later')
$demDrop = Get-AckDemands $resFiles
$curA1 = $demDrop[$runA1].Current
Assert (((@($demDrop[$runA1].Incidents) -join ',') -eq 'INC-bbbb2222') -and ((@($demDrop[$runA1].AllIncidents) | Sort-Object) -join ',') -eq 'INC-aaaa1111,INC-bbbb2222') 'ack-incidents-follow-current-copy' ("cur $(@($demDrop[$runA1].Incidents) -join ',') all $(@($demDrop[$runA1].AllIncidents) -join ',')")
$cur = Test-AckV2 (New-Ack @("$runA1 sha256:$curA1") @{ incidents = 'INC-bbbb2222' }) $demDrop
Assert ($cur.Ok -and ((@($cur.Acked) -join ',') -eq $runA1)) 'ack-current-incidents-pass' ($cur.Errors -join '; ')
# R3-F1: an in-place rewrite with no older copy left still leaves the
# batch acknowledging its unchanged run.
$onlyPrimary = @($resFiles | Where-Object { $_ -notlike '*retained*' })
$demInPlace = Get-AckDemands $onlyPrimary
Assert ((@($demInPlace[$runA1].AllIncidents) -join ',') -eq 'INC-bbbb2222') 'ack-inplace-rewrite-has-no-old-copy' (@($demInPlace[$runA1].AllIncidents) -join ',')
$inPlace = Test-AckV2 (New-Ack @("$runA1 sha256:$shaA1", "$runA2 sha256:$shaA2") @{ incidents = 'INC-aaaa1111' }) $demInPlace
Assert ($inPlace.Ok -and ((@($inPlace.Acked) -join ',') -eq $runA2) -and ((@($inPlace.Stale) -join ',') -eq $runA1)) 'ack-batch-survives-inplace-rewrite' ("ok $($inPlace.Ok) errs $($inPlace.Errors -join '; ')")
Assert (-not (Test-AckV2 (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'INC-aaaa1111' }) $demInPlace).Ok) 'ack-extra-incident-still-fails-without-stale'
# D00 T02 section 31: the acknowledgement lifecycle past the signature.
$S = [string][char]0xA7
$s31 = Join-Path $dir 's31'
$n31 = Join-Path $s31 'build\nightly'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $n31 'retained\c')
function New-Res31([string]$Name, [hashtable]$Fields) {
  $o = [ordered]@{ version = 1; stamp = '2026-09-26-023001'; day = '2026-09-26'; identity = '2026-09-26-023001-pid1'; verdict = 'red'; exit = 1; incidents = @() }
  foreach ($k in $Fields.Keys) { $o[$k] = $Fields[$k] }
  $path = Join-Path $n31 $Name
  (ConvertTo-Json ([pscustomobject]$o) -Depth 6) | Set-Content -Path $path -Encoding UTF8
  return $path
}
# Item 5: revisions order copies; equal revisions that differ conflict.
$r1 = New-Res31 'morning-2026-09-26-023001.result.json' @{ revision = 2; note = 'rev two' }
$r2 = New-Res31 'retained\c\result.json' @{ revision = 1; note = 'rev one, written later' }
$dRev = Get-AckDemands @($r1, $r2)
Assert ($dRev['2026-09-26-023001-pid1'].Current -eq (Get-FileSha256 $r1)) 'ack-revision-orders-copies-not-write-time' "$($dRev['2026-09-26-023001-pid1'].Current)"
$r3 = New-Res31 'retained\c\result.json' @{ revision = 2; note = 'rev two, different bytes' }
$dCon = Get-AckDemands @($r1, $r3)
$vCon = Test-AckV2 (New-Ack @("2026-09-26-023001-pid1 sha256:$(Get-FileSha256 $r1)") @{ incidents = 'none' }) $dCon
Assert ((-not $vCon.Ok) -and (($vCon.Errors -join '') -like '*conflicting result copies at revision 2*')) 'ack-equal-revision-copies-conflict' ($vCon.Errors -join '; ')
Remove-Item $r3
# Item 6: a green retry never erases the earlier RED's demand.
$rg = New-Res31 'morning-2026-09-26-120000.result.json' @{ identity = '2026-09-26-120000-pid2'; stamp = '2026-09-26-120000'; verdict = 'green'; exit = 0 }
$dRetry = Get-AckDemands @($r1, $rg)
Assert ($dRetry.ContainsKey('2026-09-26-023001-pid1') -and (-not $dRetry.ContainsKey('2026-09-26-120000-pid2'))) 'ack-red-then-green-retry-still-demands'
# Item 7: a skip-all proof run queues apart and never stages.
$rp = New-Res31 'morning-2026-09-26-090000.result.json' @{ identity = '2026-09-26-090000-pid3'; stamp = '2026-09-26-090000'; legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $false }; 'run-b' = [pscustomobject]@{ ran = $false }; interactive = [pscustomobject]@{ ran = $false } }; soak = [pscustomobject]@{ ran = $false; verdict = 'skipped' } }
$rf = New-Res31 'morning-2026-09-26-100000.result.json' @{ identity = '2026-09-26-100000-pid4'; stamp = '2026-09-26-100000'; proof = $true }
# Item 11: an unreadable result raises its own demand.
'{ not json' | Set-Content -Path (Join-Path $n31 'morning-2026-09-26-110000.result.json') -Encoding UTF8
$dQ = Get-AckDemands @($r1, $rp, $rf, (Join-Path $n31 'morning-2026-09-26-110000.result.json'))
Assert (($dQ['2026-09-26-090000-pid3'].Queue -eq 'proof') -and ($dQ['2026-09-26-100000-pid4'].Queue -eq 'proof') -and ($dQ['2026-09-26-023001-pid1'].Queue -eq 'operational')) 'ack-proof-runs-queue-apart'
Assert ($dQ.ContainsKey('unreadable:morning-2026-09-26-110000.result.json') -and ($dQ['unreadable:morning-2026-09-26-110000.result.json'].Day -eq '2026-09-26')) 'ack-unreadable-result-demands' ((@($dQ.Keys) | Sort-Object) -join ',')
$emptyAcks = Join-Path $s31 'acks-empty'
$null = New-Item -ItemType Directory -Force -Path $emptyAcks
$gQ = Test-Acknowledgements $s31 $emptyAcks $dQ (Get-Date '2026-10-05')
Assert ((@($gQ.ProofUnacked) -contains '2026-09-26-090000-pid3') -and (@($gQ.Unacked) -notcontains '2026-09-26-090000-pid3') -and (@($gQ.Staged | Where-Object { $_ -like '*090000-pid3*' }).Count -eq 0) -and (@($gQ.Unacked) -contains 'unreadable:morning-2026-09-26-110000.result.json') -and (@($gQ.Lines | Where-Object { $_ -like '*UNREADABLE result morning-2026-09-26-110000.result.json*' }).Count -eq 1)) 'ack-proof-never-escalates-unreadable-does' ($gQ.Lines -join ' | ')
# Item 8: the SLA shortens the deadline, and the boundary is inclusive.
$slaDem = [pscustomobject]@{ Id = 'x'; Day = '2026-09-26'; Result = [pscustomobject]@{ startUtc = '2026-09-26T00:30:00.0000000Z'; tz = '+02:00' } }
$dDef = Get-AckDue $slaDem 0
$dSla = Get-AckDue $slaDem 4
Assert (($dDef.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture) -eq '2026-09-29T23:59:59+02:00') -and ($dSla.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture) -eq '2026-09-26T06:30:00+02:00')) 'ack-sla-shortens-the-default' "$dDef / $dSla"
$slaDemands = @{ 'x' = [pscustomobject]@{ Id = 'x'; Day = '2026-09-26'; Queue = 'operational'; Shas = @(); Incidents = @(); Paths = @(); Current = ''; AllIncidents = @(); Conflict = @(); Unreadable = $false; Result = $slaDem.Result } }
$atDue = Test-Acknowledgements $s31 $emptyAcks $slaDemands ($dSla.LocalDateTime) { param($r) 4 }
$pastDue = Test-Acknowledgements $s31 $emptyAcks $slaDemands ($dSla.LocalDateTime.AddSeconds(1)) { param($r) 4 }
Assert ((@($atDue.Overdue).Count -eq 0) -and (@($pastDue.Overdue) -contains 'x')) 'ack-sla-boundary-inclusive' (($atDue.Lines + $pastDue.Lines) -join ' | ')
# Item 3: each disposition carries its evidence.
$evDem = @{ 'r1' = [pscustomobject]@{ Id = 'r1' }; 'r2' = [pscustomobject]@{ Id = 'r2' } }
Assert ((@(Test-DispositionEvidence @{ disposition = 'fixed'; finding = "D00 T02 ${S}9" } @('r1') $evDem $repo)[0]) -like 'fixed needs a commit*') 'ack-fixed-without-commit-fails'
Assert ((@(Test-DispositionEvidence @{ disposition = 'duplicate'; finding = "D00 T02 ${S}9"; evidence = 'r1' } @('r1') $evDem $repo)[0]) -like 'duplicate needs evidence naming the other known RED*') 'ack-duplicate-of-itself-fails'
Assert (@(Test-DispositionEvidence @{ disposition = 'duplicate'; finding = "D00 T02 ${S}9"; evidence = 'r2' } @('r1') $evDem $repo).Count -eq 0) 'ack-duplicate-of-another-run-passes'
Assert ((@(Test-DispositionEvidence @{ disposition = 'environment'; finding = "D00 T02 ${S}9"; evidence = 'no/such/record.json' } @('r1') $evDem $repo)[0]) -like 'environment needs evidence*') 'ack-environment-without-record-fails'
# Item 9: a batch covers each incident.
$b2 = [pscustomobject]@{ Id = 'b2'; Day = '2026-09-26'; Queue = 'operational'; Shas = @('a' * 64); Incidents = @('INC-aaaa1111', 'INC-bbbb2222'); Paths = @(); Current = ('a' * 64); AllIncidents = @(); Conflict = @(); Unreadable = $false; Result = $null }
$bDem = @{ 'b2' = $b2 }
$bOne = New-Ack @("b2 sha256:$('a' * 64)") @{ incidents = 'INC-aaaa1111, INC-bbbb2222' }
$bOne = $bOne.Replace("`n---`n", "`ncover: INC-aaaa1111 filed D00 T02 ${S}29`n---`n")
Assert (((Test-AckV2 $bOne $bDem).Errors -join '') -like '*leaves INC-bbbb2222 uncovered*') 'ack-batch-uncovered-incident-fails' ((Test-AckV2 $bOne $bDem).Errors -join '; ')
$bTwo = $bOne.Replace("`n---`n", "`ncover: INC-bbbb2222 fixed abc1234`n---`n")
Assert ((Test-AckV2 $bTwo $bDem).Ok) 'ack-batch-covered-per-incident-passes' ((Test-AckV2 $bTwo $bDem).Errors -join '; ')
$bAll = (New-Ack @("b2 sha256:$('a' * 64)") @{ incidents = 'INC-aaaa1111, INC-bbbb2222' }).Replace("`n---`n", "`ncovers-all: yes`n---`n")
Assert ((Test-AckV2 $bAll $bDem).Ok) 'ack-batch-covers-all-passes'
# Items 2, 10, 12 over the git fixture: corrective actions, withdrawal,
# and recovery never closing an investigation.
Add-Content -Path (Join-Path $repo 'todo\00-workspace\TODO-02-fixture.md') -Value @('', '| Order | Section | Title | Depends | Status |', '| --- | --- | --- | --- | --- |', "|   9   |   ${S}9   | Nine | -- |  [ ]   |", "|   29  |   ${S}29   | Twenty-nine | -- |  [x]   |") -Encoding UTF8
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'rows' 2>$null
Assert ((Test-SectionStamped $repo "D00 T02 ${S}29") -and (-not (Test-SectionStamped $repo "D00 T02 ${S}9"))) 'ack-section-stamped-reads-the-row'
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-c.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none'; finding = "D00 T02 ${S}9"; due = '2026-09-26' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack c' 2>$null
$gC = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-28')
Assert ((@($gC.Corrective | Where-Object { $_ -like '*ack-2026-09-22-a.md*closed (D00 T02*29 stamped)*' }).Count -eq 1) -and (@($gC.Corrective | Where-Object { $_ -like '*ack-2026-09-22-c.md*OVERDUE since 2026-09-26: escalate D00 T02*9*' }).Count -eq 1) -and (@($gC.CorrectiveOverdue) -contains 'ack-2026-09-22-c.md')) 'ack-corrective-actions-escalate-and-close-on-evidence' ($gC.Corrective -join ' | ')
Start-Sleep -Seconds 1
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-w.md'), (@('---', 'ack-version: 2', "run: $runA2 sha256:$shaA2", 'owner: operator', 'disposition: withdrawn', 'signed: 2026-09-27', '---', '', 'Withdrawn: the filing was wrong.') -join "`n"))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'withdraw c' 2>$null
$gW = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($gW.Unacked -contains $runA2) -and (@($gW.Lines | Where-Object { $_ -like "*$runA2 released by ack-2026-09-22-w.md (withdrawn)*" }).Count -eq 1)) 'ack-withdrawal-re-demands' ($gW.Lines -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-w.md') (Join-Path $ackDir 'ack-2026-09-22-c.md') 2>$null; & git -C $repo commit -q -m 'drop c and w' 2>$null
$null = New-Item -ItemType Directory -Force -Path (Join-Path $repo 'build\nightly')
Write-IncidentLedger @{ 'INC-aaaa1111' = [pscustomobject]@{ id = 'INC-aaaa1111'; test = 'UI.A'; phase = 'run-a'; key = ''; owner = 'operator'; state = 'closed'; firstSeen = 's'; lastSeen = 's'; closedAt = 's2'; closedBy = 'passed in run-a on 3 runs'; occurrences = @([pscustomobject]@{ stamp = 's'; wheres = @('Run A') }); passStreak = 3; lastPassStamp = 's2'; due = ''; finding = '' } } (Join-Path $repo 'build\nightly\incidents.json') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-i.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none'; finding = 'INC-aaaa1111'; evidence = "D00 T02 ${S}9"; due = '2026-09-30' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack i' 2>$null
$gI = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ((@($gI.Corrective | Where-Object { $_ -like '*ack-2026-09-22-i.md (INC-aaaa1111): open, due 2026-09-30*' }).Count -eq 1)) 'ack-recovered-incident-keeps-investigation-open' ($gI.Corrective -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-i.md') 2>$null; & git -C $repo commit -q -m 'drop i' 2>$null
Remove-Item (Join-Path $repo 'build') -Recurse -Force
# R3-F2: a cover's own remediation stays visible when the top-level
# finding is stamped.
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-k.md'), (New-Ack @("$runA1 sha256:$shaA1", "$runA2 sha256:$shaA2") @{ incidents = 'INC-aaaa1111'; finding = "D00 T02 ${S}29" }).Replace("`n---`n", "`ncover: INC-aaaa1111 filed D00 T02 ${S}9`n---`n"))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack k' 2>$null
$gK = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ((@($gK.Corrective | Where-Object { $_ -like '*ack-2026-09-22-k.md (D00 T02*29): closed*' }).Count -eq 1) -and (@($gK.Corrective | Where-Object { $_ -like '*ack-2026-09-22-k.md (INC-aaaa1111 D00 T02*9): open*' }).Count -eq 1)) 'ack-cover-remediation-stays-visible' ($gK.Corrective -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-k.md') 2>$null; & git -C $repo commit -q -m 'drop k' 2>$null
# R1-F1, R1-F2: invalid results demand; an explicit proof: false stays
# operational even with no legs run.
$rInv = New-Res31 'morning-2026-09-26-130000.result.json' @{ identity = '2026-09-26-130000-pid5'; verdict = 'exploded' }
$rNoId = New-Res31 'morning-2026-09-26-140000.result.json' @{ identity = ''; stamp = '' }
$rOp = New-Res31 'morning-2026-09-26-150000.result.json' @{ identity = '2026-09-26-150000-pid6'; proof = $false; legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $false }; 'run-b' = [pscustomobject]@{ ran = $false }; interactive = [pscustomobject]@{ ran = $false } }; soak = [pscustomobject]@{ ran = $false; verdict = 'skipped' } }
$dInv = Get-AckDemands @($rInv, $rNoId, $rOp)
Assert ($dInv.ContainsKey('unreadable:morning-2026-09-26-130000.result.json') -and $dInv.ContainsKey('unreadable:morning-2026-09-26-140000.result.json') -and ($dInv['2026-09-26-150000-pid6'].Queue -eq 'operational')) 'ack-invalid-results-demand-and-explicit-proof-false-stays-operational' ((@($dInv.Keys) | Sort-Object) -join ',')
# R1-F3: a cover line's finding must exist.
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-v.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none' }).Replace("`n---`n", "`ncover: INC-aaaa1111 filed D99 T99 ${S}999`n---`n"))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack v bogus cover' 2>$null
$gV = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (@($gV.Lines | Where-Object { $_ -like '*ack-2026-09-22-v.md: INVALID (cover INC-aaaa1111 finding D99 T99*999 not found)*' }).Count -eq 1) 'ack-cover-finding-must-exist' ($gV.Lines -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-v.md') 2>$null; & git -C $repo commit -q -m 'drop v' 2>$null
# R1-F4: with identical timestamps, the later commit still governs.
$env:GIT_AUTHOR_DATE = '2026-09-24T10:00:00+02:00'; $env:GIT_COMMITTER_DATE = '2026-09-24T10:00:00+02:00'
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-z.md'), (New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none' }))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'ack z' 2>$null
[System.IO.File]::WriteAllText((Join-Path $ackDir 'ack-2026-09-22-a2.md'), (@('---', 'ack-version: 2', "run: $runA2 sha256:$shaA2", 'owner: operator', 'disposition: withdrawn', 'signed: 2026-09-24', '---', '', 'Withdrawn.') -join "`n"))
& git -C $repo add -A 2>$null; & git -C $repo commit -q -m 'withdraw z' 2>$null
Remove-Item Env:\GIT_AUTHOR_DATE; Remove-Item Env:\GIT_COMMITTER_DATE
$gT = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert (($gT.Unacked -contains $runA2) -and (@($gT.Lines | Where-Object { $_ -like "*$runA2 released by ack-2026-09-22-a2.md (withdrawn)*" }).Count -eq 1)) 'ack-commit-graph-order-governs-over-equal-timestamps' ($gT.Lines -join ' | ')
& git -C $repo rm -q (Join-Path $ackDir 'ack-2026-09-22-z.md') (Join-Path $ackDir 'ack-2026-09-22-a2.md') 2>$null; & git -C $repo commit -q -m 'drop z a2' 2>$null
# R2-F1: contradictory or mis-versioned results demand as invalid.
$rBadEx = New-Res31 'morning-2026-09-26-160000.result.json' @{ identity = '2026-09-26-160000-pid7'; exit = 0 }
$rBadVer = New-Res31 'morning-2026-09-26-170000.result.json' @{ identity = '2026-09-26-170000-pid8'; version = 9 }
$rBadRev = New-Res31 'morning-2026-09-26-180000.result.json' @{ identity = '2026-09-26-180000-pid9'; revision = 0 }
$dBad = Get-AckDemands @($rBadEx, $rBadVer, $rBadRev)
Assert (($dBad['unreadable:morning-2026-09-26-160000.result.json'].Invalid -eq 'verdict red contradicts exit 0') -and ($dBad['unreadable:morning-2026-09-26-170000.result.json'].Invalid -like "schema version '9'*") -and ($dBad['unreadable:morning-2026-09-26-180000.result.json'].Invalid -like "revision '0'*")) 'ack-invalid-shapes-demand-with-their-reason' ((@($dBad.Keys) | Sort-Object) -join ',')
# R2-F2: the queue follows the current copy.
$rqOld = New-Res31 'retained\c\result.json' @{ identity = '2026-09-26-190000-pid10'; revision = 1; proof = $true }
$rqNew = New-Res31 'morning-2026-09-26-190000.result.json' @{ identity = '2026-09-26-190000-pid10'; revision = 2; proof = $false }
Assert ((Get-AckDemands @($rqOld, $rqNew))['2026-09-26-190000-pid10'].Queue -eq 'operational') 'ack-queue-follows-the-current-revision'
Remove-Item $rqOld
# R2-F3: a cover line carries the evidence its own disposition needs.
$fmCov = Read-AckFrontmatter ((New-Ack @("$runA2 sha256:$shaA2") @{ incidents = 'none' }).Replace("`n---`n", "`ncover: INC-aaaa1111 fixed D00 T02 ${S}9`n---`n"))
$covErr = @(Test-AckEvidence $repo $fmCov @($runA2) $dem @('INC-aaaa1111'))
Assert (($covErr -join '') -like '*cover INC-aaaa1111: fixed needs a commit*') 'ack-cover-disposition-needs-its-evidence' ($covErr -join '; ')
# Item 1: overdue filings dedupe to one row updated per night.
$of1 = Update-OverdueFindings @() @([pscustomobject]@{ Id = 'run-x'; What = 'RED 2026-09-20'; Incidents = 'none' }) '2026-09-24'
$of2 = Update-OverdueFindings $of1.Lines @([pscustomobject]@{ Id = 'run-x'; What = 'RED 2026-09-20'; Incidents = 'none' }) '2026-09-25'
$of3 = Update-OverdueFindings $of2.Lines @([pscustomobject]@{ Id = 'run-x'; What = 'RED 2026-09-20'; Incidents = 'none' }) '2026-09-26'
$ofSame = Update-OverdueFindings $of3.Lines @([pscustomobject]@{ Id = 'run-x'; What = 'RED 2026-09-20'; Incidents = 'none' }) '2026-09-26'
$ofAck = Update-OverdueFindings $of3.Lines @() '2026-09-27'
$rowX = @($of3.Lines | Where-Object { $_ -like '| run-x |*' })
Assert (($rowX.Count -eq 1) -and ($rowX[0] -eq '| run-x | RED 2026-09-20 | none | 2026-09-24 | 2026-09-26 | 3 | operator | open |') -and $of2.Changed -and (-not $ofSame.Changed) -and (@($ofAck.Lines | Where-Object { $_ -like '| run-x |*| acked |' }).Count -eq 1)) 'ack-overdue-files-once-and-updates' ($of3.Lines -join ' / ')
# R3-F1: filed evidence must exist; R3-C1: only an acknowledged run
# reads acked, a still-demanded one stays open, a vanished one clears.
Assert ((@(Test-DispositionEvidence @{ disposition = 'filed'; finding = 'INC-aaaa1111'; evidence = "D99 T99 ${S}999" } @('r1') $evDem $repo)[0]) -like 'filed needs a section ref that exists*') 'ack-filed-evidence-section-must-exist'
$ofGone = Update-OverdueFindings $of3.Lines @() '2026-09-27' 'operator' @() @()
$ofPend = Update-OverdueFindings $of3.Lines @() '2026-09-27' 'operator' @() @('run-x')
$ofYes = Update-OverdueFindings $of3.Lines @() '2026-09-27' 'operator' @('run-x') @()
Assert ((@($ofGone.Lines | Where-Object { $_ -like '| run-x |*| cleared |' }).Count -eq 1) -and (@($ofPend.Lines | Where-Object { $_ -like '| run-x |*| open |' }).Count -eq 1) -and (@($ofYes.Lines | Where-Object { $_ -like '| run-x |*| acked |' }).Count -eq 1)) 'ack-overdue-row-acked-only-when-acknowledged' (($ofGone.Lines + $ofPend.Lines) -join ' / ')
# R1-F4: a history git cannot verify never counts.
[System.IO.File]::WriteAllText((Join-Path $repo '.git\index'), 'not an index')
$g6 = Test-Acknowledgements $repo $ackDir $dem (Get-Date '2026-09-24')
Assert ((@($g6.Lines | Where-Object { $_ -like '*ack-2026-09-22-a.md: history unverifiable (git status failed); ignored*' }).Count -eq 1) -and ($g6.Unacked -contains $runA1)) 'ack-unverifiable-history-ignored' ($g6.Lines -join ' | ')
Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyParse.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyParse.Tests: all green'
exit 0
