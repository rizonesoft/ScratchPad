# Acknowledgement helper fixture suite (D00 T02 section 31 items 1, 4,
# and 14). Builds a temp git workspace with RED results, drives the
# real tools/NightlyAck.ps1 end to end, and exits nonzero on any
# failure: a drafted ack validates and counts once committed, an
# invalid draft writes nothing, overdue runs file into one tracked
# table updated per night, a failed filing commit leaves a retry that
# the next filing lands, and notification state never moves an ack.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$helper = Join-Path $PSScriptRoot 'NightlyAck.ps1'

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
function Invoke-Helper([string[]]$ArgList) {
  $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $helper @ArgList 2>&1 | ForEach-Object { "$_" })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join ' | ') }
}
function Invoke-Git([string[]]$ArgList) {
  $eap = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $null = & git -C $ws @ArgList 2>&1 } finally { $ErrorActionPreference = $eap }
}

$ws = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-ack-fixtures'
if (Test-Path $ws) { Remove-Item $ws -Recurse -Force }
$nd = Join-Path $ws 'build\nightly'
$null = New-Item -ItemType Directory -Force -Path $nd, (Join-Path $ws 'docs\nightly-acks'), (Join-Path $ws 'todo\00-workspace')
$S = [string][char]0xA7
@('# fixture', '', '## 9. Nine', '', "|   9   |   ${S}9   | Nine | -- |  [ ]   |") | Set-Content -Path (Join-Path $ws 'todo\00-workspace\TODO-02-fixture.md') -Encoding UTF8
'build/' | Set-Content -Path (Join-Path $ws '.gitignore') -Encoding UTF8
Invoke-Git @('init', '-q')
Invoke-Git @('config', 'user.name', 'Fixture Operator')
Invoke-Git @('config', 'user.email', 'fixture@example.invalid')
Invoke-Git @('config', 'commit.gpgsign', 'false')
Invoke-Git @('add', '-A')
Invoke-Git @('commit', '-q', '-m', 'init')
$run = '2026-09-20-023001-pid7'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-20-023001'; day = '2026-09-20'; identity = $run; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom') } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nd 'morning-2026-09-20-023001.result.json') -Encoding UTF8

# Item 4: notification state lives apart from the result, so writing it
# never changes the checksum an ack binds to.
$before = (Get-AckDemands @((Join-Path $nd 'morning-2026-09-20-023001.result.json')))[$run].Current
'{"notifyVersion": 2, "delivered": []}' | Set-Content -Path (Join-Path $nd 'notify-state.json') -Encoding UTF8
$after = (Get-AckDemands @((Join-Path $nd 'morning-2026-09-20-023001.result.json')))[$run].Current
Assert ($before -eq $after) 'notification-state-never-moves-an-ack'

# Item 14: an invalid draft writes nothing; a valid one validates.
$bad = Invoke-Helper @('-Draft', '-Run', $run, '-Disposition', 'looked-at-it', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-Today', '2026-09-21', '-WorkspaceRoot', $ws)
Assert (($bad.Code -eq 1) -and ($bad.Text -like "*draft refused (disposition 'looked-at-it' not one of*nothing written*") -and (@(Get-ChildItem (Join-Path $ws 'docs\nightly-acks') -Filter 'ack-*.md').Count -eq 0)) 'draft-refuses-invalid-and-writes-nothing' $bad.Text
$noEvidence = Invoke-Helper @('-Draft', '-Run', $run, '-Disposition', 'fixed', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-Today', '2026-09-21', '-WorkspaceRoot', $ws)
Assert (($noEvidence.Code -eq 1) -and ($noEvidence.Text -like '*fixed needs a commit*')) 'draft-refuses-missing-evidence' $noEvidence.Text
$good = Invoke-Helper @('-Draft', '-Run', $run, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-Today', '2026-09-21', '-WorkspaceRoot', $ws)
$ackPath = Join-Path $ws "docs\nightly-acks\ack-$run.md"
Assert (($good.Code -eq 0) -and (Test-Path $ackPath)) 'draft-writes-a-valid-ack' $good.Text
$dem = Get-AckDemands @((Join-Path $nd 'morning-2026-09-20-023001.result.json'))
$g0 = Test-Acknowledgements $ws (Join-Path $ws 'docs\nightly-acks') $dem (Get-Date '2026-09-21')
Assert ($g0.Unacked -contains $run) 'drafted-ack-counts-only-once-committed' ($g0.Lines -join ' | ')

# Item 1: overdue runs file into one tracked table, committed, updated
# per night, and a failed commit retries on the next filing.
Remove-Item $ackPath
$f1 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-25', '-WorkspaceRoot', $ws)
$table = Join-Path $ws 'docs\nightly-acks\overdue-findings.md'
$row1 = @(Get-Content $table | Where-Object { $_ -like "| $run |*" })
$log1 = @(& git -C $ws log --format=%s -- docs/nightly-acks/overdue-findings.md)
Assert (($f1.Code -eq 0) -and ($row1.Count -eq 1) -and ($row1[0] -like '*| 2026-09-25 | 2026-09-25 | 1 | operator | open |') -and ($log1.Count -eq 1)) 'file-overdue-commits-one-row' ($f1.Text + ' || ' + ($log1 -join ','))
$hook = Join-Path $ws '.git\hooks\pre-commit'
"#!/bin/sh`nexit 1`n" | Set-Content -Path $hook -Encoding ASCII -NoNewline
$f2 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
$retry = Join-Path $nd 'ack-filing-retry.json'
Assert (($f2.Code -eq 1) -and (Test-Path $retry) -and ($f2.Text -like '*filing commit failed*retry recorded*')) 'file-overdue-failed-commit-records-retry' $f2.Text
Remove-Item $hook
$f3 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
$row3 = @(Get-Content $table | Where-Object { $_ -like "| $run |*" })
$log3 = @(& git -C $ws log --format=%s -- docs/nightly-acks/overdue-findings.md)
Assert (($f3.Code -eq 0) -and (-not (Test-Path $retry)) -and ($f3.Text -like '*pending filing commit retried and landed*') -and ($row3.Count -eq 1) -and ($row3[0] -like '*| 2026-09-25 | 2026-09-26 | 2 | operator | open |') -and ($log3.Count -eq 2)) 'file-overdue-retry-lands-and-updates-the-row' ($f3.Text + ' || ' + ($log3 -join ','))

Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyAck.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyAck.Tests: all green'
exit 0
