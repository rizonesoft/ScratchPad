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

# Malformed trx: reads as absent, never throws.
Assert ($null -eq (Get-TrxSummary $badTrx)) 'truncated-trx-null'
Assert (@(Get-NonQuarantineSkips $badTrx).Count -eq 0) 'truncated-enforcement-empty'
Assert ($null -eq (Get-TrxSummary (Join-Path $dir 'missing.trx'))) 'missing-trx-null'

# Every skip class: quarantine plus capability (coded and legacy) pass;
# bare plus quiet-hours flag.
$leaked = @(Get-NonQuarantineSkips $trx)
Assert (($leaked.Count -eq 2) -and ($leaked -contains 'UI.BareSkip') -and ($leaked -contains 'UI.QuietSkip')) 'skip-classes' ($leaked -join ',')

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

# Enforcement verdicts: green, red-with-names, not-run.
Assert ((Format-EnforcementVerdict $true @()) -eq '- Interactive (collection): GREEN (every skip quarantined or capability)') 'enforce-green'
Assert ((Format-EnforcementVerdict $true @('UI.BareSkip','UI.QuietSkip')) -eq '- Interactive (collection): RED (2 non-quarantine skips: UI.BareSkip, UI.QuietSkip)') 'enforce-red'
Assert ((Format-EnforcementVerdict $false @()) -eq '- Interactive (collection): n/a (leg did not run)') 'enforce-norun'

# Short hashes: known content, missing file.
[System.IO.File]::WriteAllText((Join-Path $dir 'hash.txt'), 'abc')
Assert ((Get-ShortHash (Join-Path $dir 'hash.txt')) -eq 'ba7816bf') 'short-hash-known' (Get-ShortHash (Join-Path $dir 'hash.txt'))
Assert ((Get-ShortHash (Join-Path $dir 'nope.dll')) -eq 'missing') 'short-hash-missing'

# Soak fourth phase: green, red-with-names, killed, and cut verdicts.
$soakDir = Join-Path $dir 'soakgreen'
$null = New-Item -ItemType Directory -Force -Path $soakDir
$greenTrx = '<TestRun><Results><UnitTestResult testName="UI.SoakOk" outcome="Passed" /></Results></TestRun>'
foreach ($n in @('ui-soak-1','ui-soak-2','ui-soak-3','ui-soak-4','ui-soak-5','protocol-soak-1','protocol-soak-2','protocol-soak-3','protocol-soak-4','protocol-soak-5')) {
  $greenTrx | Set-Content -Path (Join-Path $soakDir "$n.trx") -Encoding UTF8
}
$green = Format-SoakLedger $soakDir @() @()
Assert (($green.Failed -eq $false) -and ($green.Rows[0] -eq '- Verdict: GREEN (10/10 iterations proved)')) 'soak-green' $green.Rows[0]

$redDir = Join-Path $dir 'soakred'
$null = New-Item -ItemType Directory -Force -Path $redDir
$redTrx = '<TestRun><Results><UnitTestResult testName="UI.Flaky" outcome="Failed"><Output><ErrorInfo><Message>flake</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>'
$redTrx | Set-Content -Path (Join-Path $redDir 'ui-soak-3.trx') -Encoding UTF8
$red = Format-SoakLedger $redDir @('ui-soak-5') @('protocol-soak-1..5')
Assert ($red.Failed -eq $true) 'soak-red-flag'
Assert ($red.Rows[0] -like '- Verdict: RED (FAILED: ui-soak-3; unproven: ui-soak-5, protocol-soak-1..5*') 'soak-red-verdict' $red.Rows[0]
Assert (($red.Rows -join "`n") -like '*UI.Flaky*flake*') 'soak-red-names' ($red.Rows -join '|')
Assert (($red.Rows -join "`n") -like '*- ui-soak-5 : no trx (killed at cap: unproven)*') 'soak-killed-row' ($red.Rows -join '|')
Assert (($red.Rows -join "`n") -like '*- protocol-soak-1..5 : budget-cut (unproven)*') 'soak-cut-row' ($red.Rows -join '|')

$emptyDir = Join-Path $dir 'soakempty'
$null = New-Item -ItemType Directory -Force -Path $emptyDir
$empty = Format-SoakLedger $emptyDir @() @()
Assert (($empty.Failed -eq $false) -and (($empty.Rows -join '') -like '*no soak iterations ran*')) 'soak-empty' ($empty.Rows -join '|')

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyParse.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyParse.Tests: all green'
exit 0
