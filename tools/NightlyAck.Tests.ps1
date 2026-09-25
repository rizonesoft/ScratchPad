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
@('# fixture', '', '## 9. Nine', '', '- [ ] Fix INC-aaaa1111 (UI.A) and INC-bbbb2222 (UI.B).', '', "|   9   |   ${S}9   | Nine | -- |  [ ]   |") | Set-Content -Path (Join-Path $ws 'todo\00-workspace\TODO-02-fixture.md') -Encoding UTF8
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

# R1-I2: a run with two incidents drafts only with per-incident cover.
$run2 = '2026-09-21-023001-pid8'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-21-023001'; day = '2026-09-21'; identity = $run2; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom', '- INC-bbbb2222 `UI.B` x1 (Run A): bang') } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nd 'morning-2026-09-21-023001.result.json') -Encoding UTF8
$noCover = Invoke-Helper @('-Draft', '-Run', $run2, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-Today', '2026-09-22', '-WorkspaceRoot', $ws)
Assert (($noCover.Code -eq 1) -and ($noCover.Text -like '*uncovered*')) 'draft-two-incidents-needs-cover' $noCover.Text
$withAll = Invoke-Helper @('-Draft', '-Run', $run2, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-CoversAll', '-Today', '2026-09-22', '-WorkspaceRoot', $ws)
Assert (($withAll.Code -eq 0) -and ((Get-Content (Join-Path $ws "docs\nightly-acks\ack-$run2.md") -Raw) -like '*covers-all: yes*')) 'draft-covers-all-passes' $withAll.Text
Remove-Item (Join-Path $ws "docs\nightly-acks\ack-$run2.md")
# R1-I1: filing uses the nightly's SLA: a test-failure RED is overdue a
# day after its run although the three-day default has not passed.
$run3 = '2026-09-27-023001-pid9'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-27-023001'; day = '2026-09-27'; identity = $run3; verdict = 'red'; exit = 1; startUtc = '2026-09-27T00:30:01.0000000Z'; tz = '+02:00'; incidents = @(); legs = [pscustomobject]@{ 'run-a' = [pscustomobject]@{ ran = $true; failed = 1; gate = 0 }; 'run-b' = [pscustomobject]@{ ran = $true; failed = 0; gate = 0 }; interactive = [pscustomobject]@{ ran = $false } } } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $nd 'morning-2026-09-27-023001.result.json') -Encoding UTF8
$fs = Invoke-Helper @('-FileOverdue', '-Today', '2026-09-28', '-WorkspaceRoot', $ws)
Assert (($fs.Code -eq 0) -and (@(Get-Content $table | Where-Object { $_ -like "| $run3 |*" }).Count -eq 1)) 'file-overdue-uses-the-nightly-sla' $fs.Text
# R2 parity: the helper refuses a cover the gate would refuse.
$badCover = Invoke-Helper @('-Draft', '-Run', $run2, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', "D00 T02 ${S}9", '-Cover', "INC-aaaa1111 filed D99 T99 ${S}999; INC-bbbb2222 filed D00 T02 ${S}9", '-Today', '2026-09-22', '-WorkspaceRoot', $ws)
Assert (($badCover.Code -eq 1) -and ($badCover.Text -like '*cover INC-aaaa1111 finding D99 T99*999 not found*')) 'draft-refuses-a-cover-the-gate-refuses' $badCover.Text
# ---- Section 39: acknowledgement second residuals --------------------
$acks = Join-Path $ws 'docs\nightly-acks'
function Get-Dem { $fs = @(Get-ChildItem $nd -Filter 'morning-*.result.json' | ForEach-Object { $_.FullName }); $fs += @(Get-ChildItem (Join-Path $nd 'retained') -Filter 'result.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }); return (Get-AckDemands $fs (Read-ResultClassifications $nd)) }
function Write-Ack([string]$Name, [string[]]$Front, [string]$Body = 'Why: the failing run was triaged; the finding carries the fix and the cause is recorded here for review.') {
  [System.IO.File]::WriteAllText((Join-Path $acks $Name), ((@('---', 'ack-version: 2') + $Front + @('---', '', $Body)) -join "`n") + "`n")
}
function Save-All([string]$Msg, [string]$Date = '') {
  $eap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    if ($Date -ne '') { $env:GIT_AUTHOR_DATE = $Date; $env:GIT_COMMITTER_DATE = $Date }
    $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m $Msg 2>&1
  } finally { Remove-Item Env:\GIT_AUTHOR_DATE -ErrorAction SilentlyContinue; Remove-Item Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue; $ErrorActionPreference = $eap }
}
function Get-Gate { return (Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-09-28')) }
$fnd = "D00 T02 ${S}9"
$runX = '2026-09-24-023001-pid21'
$runY = '2026-09-24-120001-pid22'
foreach ($r in @(@($runX, '2026-09-24'), @($runY, '2026-09-24'))) {
  [pscustomobject]@{ version = 1; revision = 1; stamp = $r[0].Substring(0, 17); day = $r[1]; identity = $r[0]; verdict = 'red'; exit = 1; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nd "morning-$($r[0].Substring(0, 17)).result.json") -Encoding UTF8
}
$dem = Get-Dem
# Item 2 (tightened by section 46 item 1): a duplicate of an acknowledged
# run links that run's surviving action and stays open while it is open.
Write-Ack 'ack-x.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Write-Ack 'ack-y.md' @("run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: duplicate', "evidence: $runX", 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'acks x and y'
$gd = Get-Gate
Assert ((@($gd.Lines | Where-Object { $_ -like "*CORRECTIVE ack-y.md ($fnd): open (duplicate of $runX; open while its action ack-x.md ($fnd) is open*" }).Count -eq 1) -and (@($gd.Lines | Where-Object { $_ -like "*CORRECTIVE ack-x.md ($fnd): open*" }).Count -eq 1)) 's46-duplicate-stays-open-naming-the-surviving-action' ($gd.Lines -join ' | ')
# Item 7: duplicate references cannot cycle.
Write-Ack 'ack-x.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: duplicate', "evidence: $runY", 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'x duplicate of y'
$gc = Get-Gate
Assert ((@($gc.Lines | Where-Object { $_ -like '*duplicate CYCLE*' }).Count -eq 2) -and ($gc.Unacked -contains $runX) -and ($gc.Unacked -contains $runY)) 's39-duplicate-cycle-acknowledges-nothing' ($gc.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-x.md'), (Join-Path $acks 'ack-y.md')
Save-All 'drop x y'
# Item 3: the response clock: an on-time first ack stays on time after a
# late replacement; a late first ack stays late after one.
$dem = Get-Dem
Write-Ack 'ack-x.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'x on time' '2026-09-25T10:00:00+02:00'
Write-Ack 'ack-x.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-12', "finding: $fnd", 'signed: 2026-09-30') 'Why: replaced after the deadline with a later due date; the cause stays as first recorded, this text is longer to keep the substance.'
Save-All 'x replaced late' '2026-09-30T10:00:00+02:00'
Write-Ack 'ack-y.md' @("run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-29')
Save-All 'y late' '2026-09-29T10:00:00+02:00'
Write-Ack 'ack-y.md' @("run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-11', "finding: $fnd", 'signed: 2026-09-30') 'Why: a replacement signed after the response deadline; it cannot make the first response on time, and this body carries the cause.'
Save-All 'y replaced' '2026-09-30T11:00:00+02:00'
$gl = Get-Gate
Assert ((@($gl.Lines | Where-Object { $_ -like "*LATE response: $runY first acknowledged 2026-09-29*" }).Count -eq 1) -and (@($gl.Lines | Where-Object { $_ -like "*LATE response: $runX*" }).Count -eq 0)) 's39-response-and-corrective-clocks-stay-apart' ($gl.Lines -join ' | ')
# Item 4: two acks for one run in one commit tie and fail closed; naming
# the superseded file in replaces: resolves it.
Write-Ack 'ack-x2.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-30')
Write-Ack 'ack-x3.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-30')
Save-All 'x2 and x3 together'
$gt = Get-Gate
Assert ((@($gt.Lines | Where-Object { $_ -like "*$runX TIE: ack-x2.md, ack-x3.md land in one commit*" }).Count -eq 1) -and ($gt.Unacked -contains $runX)) 's39-same-commit-tie-fails-closed' ($gt.Lines -join ' | ')
Write-Ack 'ack-x3.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-30', 'replaces: ack-x2.md')
Write-Ack 'ack-x2.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-11', "finding: $fnd", 'signed: 2026-09-30')
Save-All 'x3 replaces x2'
$gr = Get-Gate
Assert (($gr.Unacked -notcontains $runX) -and (@($gr.Lines | Where-Object { $_ -like "*$runX governed by ack-x3.md*" }).Count -eq 1)) 's39-replaces-resolves-the-tie' ($gr.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-x.md'), (Join-Path $acks 'ack-x2.md'), (Join-Path $acks 'ack-x3.md'), (Join-Path $acks 'ack-y.md')
Save-All 'drop timing acks'
# Items 5 and 13: a mixed batch (quarantined and duplicate covers, each
# with its own evidence) validates; a revision that drops an incident
# keeps its open corrective action, and an older revision written later
# is flagged.
$qdoc = Join-Path $ws 'docs\soak-and-quarantine.md'
@('# Soak', '', '## Quarantine list', '', '| Test | Since | Window | Owner |', '| --- | --- | --- | --- |', "| ``UI.A`` | 2026-09-20 | 7d | D00 T02 ${S}9 |") | Set-Content -Path $qdoc -Encoding UTF8
Save-All 'quarantine list'
$dem = Get-Dem
Write-Ack 'ack-run2.md' @("run: $run2 sha256:$($dem[$run2].Current)", 'incidents: INC-aaaa1111, INC-bbbb2222', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", "cover: INC-aaaa1111 quarantined $fnd evidence UI.A", "cover: INC-bbbb2222 duplicate $fnd evidence $runX", 'signed: 2026-09-25')
Save-All 'ack run2 mixed batch'
$gm = Get-Gate
Assert (($gm.Unacked -notcontains $run2) -and (@($gm.Lines | Where-Object { $_ -like '*ack-run2.md: acknowledges*' }).Count -eq 1)) 's39-mixed-batch-covers-carry-their-evidence' ($gm.Lines -join ' | ')
Copy-Item (Join-Path $nd 'morning-2026-09-21-023001.result.json') (Join-Path $nd 'retained-rev1.json')
[pscustomobject]@{ version = 1; revision = 2; stamp = '2026-09-21-023001'; day = '2026-09-21'; identity = $run2; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom') } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nd 'morning-2026-09-21-023001.result.json') -Encoding UTF8
$gv = Get-Gate
Assert (($gv.Unacked -contains $run2) -and (@($gv.Lines | Where-Object { $_ -like '*CORRECTIVE ack-run2.md (INC-bbbb2222*open*revised after signing*' }).Count -eq 1)) 's39-revision-drop-keeps-the-open-action' ($gv.Lines -join ' | ')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $nd 'retained\late')
Start-Sleep -Milliseconds 1100
Copy-Item (Join-Path $nd 'retained-rev1.json') (Join-Path $nd 'retained\late\result.json')
(Get-Item (Join-Path $nd 'retained\late\result.json')).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
$gg = Get-Gate
Assert (@($gg.Lines | Where-Object { $_ -like "*REVISION regression: $run2 revision 1*written after revision 2*" }).Count -eq 1) 's39-lower-revision-written-later-is-flagged' ($gg.Lines -join ' | ')
Remove-Item (Join-Path $nd 'retained\late') -Recurse; Remove-Item (Join-Path $nd 'retained-rev1.json')
# R1-F3: a revised run's action still escalates once overdue.
$gvo = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-12')
Assert ((@($gvo.CorrectiveOverdue) -contains 'ack-run2.md') -and (@($gvo.Lines | Where-Object { $_ -like '*CORRECTIVE ack-run2.md (INC-bbbb2222*OVERDUE since 2026-10-10*revised after signing*' }).Count -eq 1)) 's39-revised-run-actions-still-escalate' ($gvo.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-run2.md'); Save-All 'drop run2 ack'
# Item 7: an unrelated fixed commit fails.
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
'notes' | Set-Content -Path (Join-Path $ws 'docs\notes.md') -Encoding UTF8; $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m 'docs only' 2>&1
$docSha = ((& git -C $ws rev-parse HEAD) | Out-String).Trim()
$ErrorActionPreference = $eap
Write-Ack 'ack-y.md' @("run: $run sha256:$($dem[$run].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $($docSha.Substring(0, 12))", 'signed: 2026-09-25')
Save-All 'ack y fixed by docs'
$gu = Get-Gate
Assert (@($gu.Lines | Where-Object { $_ -like "*ack-y.md: INVALID (fixed needs a commit that touches the failing test's file or names the test or incident*" }).Count -eq 1) 's39-unrelated-fixed-commit-fails' ($gu.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-y.md'); Save-All 'drop y'
# R1-F1: a code commit that neither touches the test's file nor names the
# test or incident is not a fix.
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws 'src')
'class Other {}' | Set-Content -Path (Join-Path $ws 'src\Other.cs') -Encoding UTF8
Save-All 'refactor Other'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $srcSha = ((& git -C $ws rev-parse HEAD) | Out-String).Trim(); $ErrorActionPreference = $eap
$dem = Get-Dem
Write-Ack 'ack-y.md' @("run: $run sha256:$($dem[$run].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $($srcSha.Substring(0, 12))", 'signed: 2026-09-25')
Save-All 'ack fixed by unrelated code'
$gs = Get-Gate
'class A2 {}' | Set-Content -Path (Join-Path $ws 'src\Other.cs') -Encoding UTF8
Save-All 'fix INC-aaaa1111 in Other'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $namedSha = ((& git -C $ws rev-parse HEAD) | Out-String).Trim(); $ErrorActionPreference = $eap
Write-Ack 'ack-y.md' @("run: $run sha256:$($dem[$run].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $($namedSha.Substring(0, 12))", 'signed: 2026-09-25')
Save-All 'ack fixed by named commit'
$gs2 = Get-Gate
Assert ((@($gs.Lines | Where-Object { $_ -like "*ack-y.md: INVALID (fixed needs a commit that touches the failing test's file or names the test or incident*" }).Count -eq 1) -and ($gs2.Unacked -notcontains $run)) 's39-fixed-commit-must-address-the-failure' (($gs.Lines + $gs2.Lines) -join ' | ')
Remove-Item (Join-Path $acks 'ack-y.md'); Save-All 'drop y'
# R1-F2: a cycle through cover-level duplicates acknowledges nothing.
$dem = Get-Dem
Write-Ack 'ack-run2.md' @("run: $run2 sha256:$($dem[$run2].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", "cover: INC-aaaa1111 duplicate $fnd evidence $run", 'signed: 2026-09-25')
Write-Ack 'ack-run.md' @("run: $run sha256:$($dem[$run].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: duplicate', "evidence: $run2", 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'cover cycle'
$gcc = Get-Gate
Assert ((@($gcc.Lines | Where-Object { $_ -like '*duplicate CYCLE*' }).Count -eq 2) -and ($gcc.Unacked -contains $run) -and ($gcc.Unacked -contains $run2)) 's39-cover-level-duplicate-cycle-acknowledges-nothing' ($gcc.Lines -join ' | ')
# R1-F5: a draft that would close a cycle is reported as not effective.
Remove-Item (Join-Path $acks 'ack-run.md'); Save-All 'drop run ack'
$drc = Invoke-Helper @('-Draft', '-Run', $run, '-Disposition', 'duplicate', '-Evidence', $run2, '-Owner', 'operator', '-Finding', $fnd, '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
Assert (($drc.Code -eq 1) -and ($drc.Text -like "*the gate would NOT acknowledge $run once committed*CYCLE*")) 's39-draft-reports-governance-not-only-the-checksum' $drc.Text
Remove-Item (Join-Path $acks "ack-$run.md") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $acks 'ack-run2.md'); Save-All 'drop run2 ack'
# R1-F4: a run added to an older ack reads its own, later response time.
$dem = Get-Dem
Write-Ack 'ack-xy.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'ack x on time' '2026-09-25T09:00:00+02:00'
Write-Ack 'ack-xy.md' @("run: $runX sha256:$($dem[$runX].Current)", "run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-30')
Save-All 'add y late' '2026-09-30T09:00:00+02:00'
$gxy = Get-Gate
Assert ((@($gxy.Lines | Where-Object { $_ -like "*LATE response: $runY first acknowledged 2026-09-30*" }).Count -eq 1) -and (@($gxy.Lines | Where-Object { $_ -like "*LATE response: $runX*" }).Count -eq 0)) 's39-run-added-to-an-older-ack-reads-its-own-time' ($gxy.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-xy.md'); Save-All 'drop xy'
# ---- Round 2 (section 39 R2-F1..F4) ----
$runZ = '2026-09-26-023001-pid30'
$zPath = Join-Path $nd 'morning-2026-09-26-023001.result.json'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-26-023001'; day = '2026-09-26'; identity = $runZ; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom', '- INC-bbbb2222 `UI.B` x1 (Run A): bang') } | ConvertTo-Json -Depth 5 | Set-Content -Path $zPath -Encoding UTF8
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws 'tests\UI')
'class A { }' | Set-Content -Path (Join-Path $ws 'tests\UI\A.cs') -Encoding UTF8
Save-All 'fix the A test'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $shaA = ((& git -C $ws rev-parse HEAD) | Out-String).Trim().Substring(0, 12); $ErrorActionPreference = $eap
# R2-F1: a cover's evidence answers for its own incident.
$dem = Get-Dem
Write-Ack 'ack-z.md' @("run: $runZ sha256:$($dem[$runZ].Current)", 'incidents: INC-aaaa1111, INC-bbbb2222', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $shaA", "cover: INC-aaaa1111 fixed $shaA", "cover: INC-bbbb2222 fixed $shaA", 'signed: 2026-09-26')
Save-All 'ack z fixed both by the A commit'
$gz = Get-Gate
Assert ((@($gz.Lines | Where-Object { $_ -like "*ack-z.md: INVALID (*cover INC-bbbb2222: fixed needs a commit that touches the failing test's file or names the test or incident*" }).Count -eq 1) -and (@($gz.Lines | Where-Object { $_ -like '*cover INC-aaaa1111:*' }).Count -eq 0)) 's39-cover-evidence-answers-for-its-own-incident' ($gz.Lines -join ' | ')
# R2-F2: an edit that drops a cover keeps that cover's action open.
Write-Ack 'ack-z.md' @("run: $runZ sha256:$($dem[$runZ].Current)", 'incidents: INC-aaaa1111, INC-bbbb2222', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", "cover: INC-aaaa1111 filed $fnd", "cover: INC-bbbb2222 filed $fnd", 'signed: 2026-09-26')
Save-All 'ack z filed'
[pscustomobject]@{ version = 1; revision = 2; stamp = '2026-09-26-023001'; day = '2026-09-26'; identity = $runZ; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom') } | ConvertTo-Json -Depth 5 | Set-Content -Path $zPath -Encoding UTF8
$dem = Get-Dem
Write-Ack 'ack-z.md' @("run: $runZ sha256:$($dem[$runZ].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-27')
Save-All 'ack z re-signed without B'
$gzd = Get-Gate
Assert (($gzd.Unacked -notcontains $runZ) -and (@($gzd.Lines | Where-Object { $_ -like "*CORRECTIVE ack-z.md (INC-bbbb2222 $fnd (dropped from the ack*): open*" }).Count -eq 1)) 's39-dropped-cover-keeps-its-action' ($gzd.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-z.md'); Save-All 'drop z'
# R2-F3: acks on incomparable merged branches tie.
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$mainBr = ((& git -C $ws rev-parse --abbrev-ref HEAD) | Out-String).Trim()
$base = ((& git -C $ws rev-parse HEAD) | Out-String).Trim()
$ErrorActionPreference = $eap
$dem = Get-Dem
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $null = & git -C $ws checkout -q -b b1 2>&1; $ErrorActionPreference = $eap
Write-Ack 'ack-z1.md' @("run: $runZ sha256:$($dem[$runZ].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-27')
Save-All 'b1 ack'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $null = & git -C $ws checkout -q -b b2 $base 2>&1; $ErrorActionPreference = $eap
Write-Ack 'ack-z2.md' @("run: $runZ sha256:$($dem[$runZ].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-11', "finding: $fnd", 'signed: 2026-09-27')
Save-All 'b2 ack'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$null = & git -C $ws checkout -q $mainBr 2>&1; $null = & git -C $ws merge -q --no-edit b1 2>&1; $null = & git -C $ws merge -q --no-edit b2 2>&1
$ErrorActionPreference = $eap
$gb = Get-Gate
Assert ((@($gb.Lines | Where-Object { ($_ -like "*$runZ TIE: ack-z*") -and ($_ -like "*ack-z1.md*") -and ($_ -like "*ack-z2.md*") }).Count -eq 1) -and ($gb.Unacked -contains $runZ)) 's39-incomparable-branches-tie' ($gb.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-z1.md'), (Join-Path $acks 'ack-z2.md'); Save-All 'drop z1 z2'
# R2-F4: first sight records an unclassified result, so a later proof
# relabel stays operational; after the cutover an unrecorded one is
# operational anyway.
$nrPath = Join-Path $nd 'morning-2026-09-27-120001.result.json'
$nr = [pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-27-120001'; day = '2026-09-27'; identity = '2026-09-27-120001-pid31'; verdict = 'red'; exit = 1; incidents = @() }
$nr | ConvertTo-Json -Depth 5 | Set-Content -Path $nrPath -Encoding UTF8
$reg = Register-UnclassifiedResults $nd @($nrPath)
$nr | Add-Member -NotePropertyName proof -NotePropertyValue $true -Force
$nr | Add-Member -NotePropertyName proofSource -NotePropertyValue 'switches' -Force
$nr | ConvertTo-Json -Depth 5 | Set-Content -Path $nrPath -Encoding UTF8
$q1 = (Get-Dem)['2026-09-27-120001-pid31'].Queue
$lpPath = Join-Path $nd 'morning-2026-09-27-130001.result.json'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-27-130001'; day = '2026-09-27'; identity = '2026-09-27-130001-pid32'; verdict = 'red'; exit = 1; proof = $true; proofSource = 'switches'; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path $lpPath -Encoding UTF8
$q2 = (Get-Dem)['2026-09-27-130001-pid32'].Queue
Remove-Item $nrPath, $lpPath, $zPath
Assert (($reg -ge 1) -and ($q1 -eq 'operational') -and ($q2 -eq 'operational')) 's39-unclassified-results-cannot-be-relabeled' "$reg $q1 $q2"

# ---- Sign-off (section 39 R3-F1..F5) ----
# R3-F1: a same-named file outside tests/ is not the test's file.
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws 'docs')
'notes' | Set-Content -Path (Join-Path $ws 'docs\A.md') -Encoding UTF8
Save-All 'docs page'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $docA = ((& git -C $ws rev-parse HEAD) | Out-String).Trim().Substring(0, 12); $ErrorActionPreference = $eap
$dem = Get-Dem
Write-Ack 'ack-y.md' @("run: $run sha256:$($dem[$run].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $docA", 'signed: 2026-09-25')
Save-All 'ack fixed by docs A'
$g31 = Get-Gate
Assert (@($g31.Lines | Where-Object { $_ -like "*ack-y.md: INVALID (fixed needs a commit that touches the failing test's file*" }).Count -eq 1) 's39-same-named-file-outside-tests-is-no-fix' ($g31.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-y.md'); Save-All 'drop y'
# R3-F2 and R3-F5: a single-incident ack revised to drop the incident and
# replace its finding keeps the original action, shown with its own due.
$runW = '2026-09-26-093001-pid33'
$wPath = Join-Path $nd 'morning-2026-09-26-093001.result.json'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-26-093001'; day = '2026-09-26'; identity = $runW; verdict = 'red'; exit = 1; incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom') } | ConvertTo-Json -Depth 5 | Set-Content -Path $wPath -Encoding UTF8
$dem = Get-Dem
Write-Ack 'ack-w.md' @("run: $runW sha256:$($dem[$runW].Current)", 'incidents: INC-aaaa1111', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-26')
Save-All 'ack w filed'
[pscustomobject]@{ version = 1; revision = 2; stamp = '2026-09-26-093001'; day = '2026-09-26'; identity = $runW; verdict = 'red'; exit = 1; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path $wPath -Encoding UTF8
$dem = Get-Dem
Write-Ack 'ack-w.md' @("run: $runW sha256:$($dem[$runW].Current)", 'incidents: none', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-20', "finding: $docA", 'signed: 2026-09-27')
Save-All 'ack w re-signed as fixed'
$g32 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-12')
Assert ((@($g32.Lines | Where-Object { $_ -like "*CORRECTIVE ack-w.md ($fnd (dropped from the ack, opened*)): OVERDUE since 2026-10-10*" }).Count -eq 1)) 's39-dropped-top-level-action-keeps-its-own-due' ($g32.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-w.md'), $wPath; Save-All 'drop w'
# R3-F3: with an empty ledger, a post-cutover result relabeled proof is
# operational, and first sight records it operational.
$emptyNd = Join-Path $ws 'build\empty-nd'
$null = New-Item -ItemType Directory -Force -Path $emptyNd
$rp = Join-Path $emptyNd 'morning-2026-09-27-140001.result.json'
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-27-140001'; day = '2026-09-27'; identity = '2026-09-27-140001-pid34'; verdict = 'red'; exit = 1; proof = $true; proofSource = 'switches'; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path $rp -Encoding UTF8
$qEmpty = (Get-AckDemands @($rp) (Read-ResultClassifications $emptyNd))['2026-09-27-140001-pid34'].Queue
$null = Register-UnclassifiedResults $emptyNd @($rp)
$qReg = (Read-ResultClassifications $emptyNd)['2026-09-27-140001-pid34'].Queue
Remove-Item $emptyNd -Recurse
Assert (($qEmpty -eq 'operational') -and ($qReg -eq 'operational')) 's39-empty-ledger-and-first-sight-stay-operational' "$qEmpty $qReg"
# R3-F4: two uncommitted drafts for one run tie in the prediction.
$d1 = Invoke-Helper @('-Draft', '-Run', $runY, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', $fnd, '-Out', (Join-Path $acks 'ack-d1.md'), '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
$d2 = Invoke-Helper @('-Draft', '-Run', $runY, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', $fnd, '-Out', (Join-Path $acks 'ack-d2.md'), '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
Remove-Item (Join-Path $acks 'ack-d1.md'), (Join-Path $acks 'ack-d2.md') -ErrorAction SilentlyContinue
Assert (($d1.Code -eq 0) -and ($d2.Code -eq 1) -and ($d2.Text -like "*would NOT acknowledge $runY*TIE*")) 's39-staged-drafts-tie-in-the-prediction' "$($d1.Text) || $($d2.Text)"

# Item 6: an unreadable result is recorded and, once repaired, maps to
# its identity with the corruption kept on record.
$badPath = Join-Path $nd 'morning-2026-09-23-023001.result.json'
'{ not json' | Set-Content -Path $badPath -Encoding UTF8
$crec = Join-Path $nd 'ack-corruption.json'
$c1 = @(Update-CorruptionRecord $crec (Get-Dem) '2026-09-24')
[pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-23-023001'; day = '2026-09-23'; identity = '2026-09-23-023001-pid23'; verdict = 'red'; exit = 1; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path $badPath -Encoding UTF8
$c2 = @(Update-CorruptionRecord $crec (Get-Dem) '2026-09-25')
Assert ((($c1 -join '') -like '*morning-2026-09-23-023001.result.json unreadable since 2026-09-24*demanded as unreadable:*') -and (($c2 -join '') -like '*unreadable since 2026-09-24*restored 2026-09-25 as 2026-09-23-023001-pid23*')) 's39-repaired-result-maps-and-keeps-its-record' (($c1 + $c2) -join ' | ')
Remove-Item $badPath
# Item 10: a result published operational stays operational when edited
# to proof afterwards.
$pubPath = Join-Path $nd 'morning-2026-09-22-023001.result.json'
$pub = [pscustomobject]@{ version = 1; revision = 1; stamp = '2026-09-22-023001'; day = '2026-09-22'; identity = '2026-09-22-023001-pid24'; verdict = 'red'; exit = 1; proof = $false; proofSource = ''; incidents = @() }
$pub | ConvertTo-Json -Depth 5 | Set-Content -Path $pubPath -Encoding UTF8
$null = Add-ResultClassification $nd $pub (Get-FileSha256 $pubPath)
$pub.proof = $true; $pub.proofSource = 'switches'
$pub | ConvertTo-Json -Depth 5 | Set-Content -Path $pubPath -Encoding UTF8
$pq = (Get-Dem)['2026-09-22-023001-pid24'].Queue
Remove-Item $pubPath
Assert ($pq -eq 'operational') 's39-proof-relabel-after-publication-stays-operational' $pq
# Item 12: -Draft reports pending; -Status reads pending, then effective.
$dr = Invoke-Helper @('-Draft', '-Run', $runX, '-Disposition', 'filed', '-Owner', 'operator', '-Finding', $fnd, '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
$st1 = Invoke-Helper @('-Status', '-Run', $runX, '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
Save-All 'commit the drafted ack'
$st2 = Invoke-Helper @('-Status', '-Run', $runX, '-Today', '2026-09-26', '-WorkspaceRoot', $ws)
Assert (($dr.Text -like "*PENDING: the gate acknowledges $runX once this file is committed*") -and ($st1.Text -like "*$runX PENDING*") -and ($st2.Code -eq 0) -and ($st2.Text -like "*$runX EFFECTIVE*")) 's39-helper-reports-pending-then-effective' ("$($dr.Text) || $($st1.Text) || $($st2.Text)")
# Items 8 and 9: authority, scope, interruption, and overlap.
$prevCc = $env:CLAUDECODE
$env:CLAUDECODE = ''
$na = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-29', '-WorkspaceRoot', $ws)
$env:CLAUDECODE = $prevCc
'stray' | Set-Content -Path (Join-Path $ws 'stray.txt') -Encoding UTF8
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $null = & git -C $ws add stray.txt 2>&1; $ErrorActionPreference = $eap
$sc = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-29', '-WorkspaceRoot', $ws)
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $null = & git -C $ws reset -q stray.txt 2>&1; $ErrorActionPreference = $eap
Remove-Item (Join-Path $ws 'stray.txt')
Assert (($na.Code -eq 1) -and ($na.Text -like '*-Commit runs only in the Claude writer session*') -and ($sc.Code -eq 1) -and ($sc.Text -like '*other files are staged (stray.txt)*')) 's39-commit-authority-and-scope' ("$($na.Text) || $($sc.Text)")
Remove-Item (Join-Path $nd 'ack-filing-retry.json') -ErrorAction SilentlyContinue
$w1 = Invoke-Helper @('-FileOverdue', '-Today', '2026-09-30', '-WorkspaceRoot', $ws)
$w2 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-30', '-WorkspaceRoot', $ws)
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $clean = @(& git -C $ws status --porcelain -- docs/nightly-acks/overdue-findings.md 2>$null); $ErrorActionPreference = $eap
$held = [System.IO.File]::Open((Join-Path $nd 'ack-filing.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$w3 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-30', '-LockWaitSeconds', '1', '-WorkspaceRoot', $ws)
$held.Dispose()
Assert (($w2.Text -like '*an uncommitted filing from an interrupted run was committed*') -and ($clean.Count -eq 0) -and ($w3.Code -eq 1) -and ($w3.Text -like '*another filing held*for 1 s*')) 's39-interrupted-and-concurrent-filings-stay-consistent' ("$($w1.Text) || $($w2.Text) || $($w3.Text)")
# Section 46 item 12: a filing waits for a held lock and lands once it is
# released, so two filings in flight both record.
$holder = Start-Job -ScriptBlock { param($p) $h = [System.IO.File]::Open($p, 'OpenOrCreate', 'ReadWrite', 'None'); Start-Sleep -Seconds 3; $h.Dispose() } -ArgumentList (Join-Path $nd 'ack-filing.lock')
Start-Sleep -Milliseconds 800
$prevCc2 = $env:CLAUDECODE; $env:CLAUDECODE = '1'
$w4 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-10-01', '-LockWaitSeconds', '30', '-WorkspaceRoot', $ws)
$null = Wait-Job $holder -Timeout 10; Remove-Job $holder -Force
$row4 = @(Get-Content $table | Where-Object { $_ -like '*| 2026-10-01 |*' })
Assert (($w4.Code -eq 0) -and ($row4.Count -ge 1)) 's46-a-waiting-filing-lands-after-the-lock' $w4.Text
# Section 46 item 12: a lost receipt (the commit landed, the retry record
# survived) is told apart and commits nothing again.
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $before5 = @(& git -C $ws log --format=%H -- docs/nightly-acks/overdue-findings.md 2>$null).Count; $ErrorActionPreference = $eap
[pscustomobject]@{ table = $table; failed = '2026-10-01T02:00:00Z'; error = 'simulated lost receipt' } | ConvertTo-Json | Set-Content -Path (Join-Path $nd 'ack-filing-retry.json') -Encoding UTF8
$w5 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-10-01', '-WorkspaceRoot', $ws)
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $after5 = @(& git -C $ws log --format=%H -- docs/nightly-acks/overdue-findings.md 2>$null).Count; $ErrorActionPreference = $eap
$env:CLAUDECODE = $prevCc2
Assert (($w5.Code -eq 0) -and ($w5.Text -like '*lost commit receipt*nothing recommitted*') -and ($after5 -eq $before5) -and (-not (Test-Path (Join-Path $nd 'ack-filing-retry.json')))) 's46-lost-receipt-commits-once' "$($w5.Text) || $before5 -> $after5"

# ---- Section 46: acknowledgement third residuals ---------------------
# A fresh workspace, so earlier fixtures' acks and results never mix in.
Remove-Item $ws -Recurse -Force
$ws = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-ack-s46'
if (Test-Path $ws) { Remove-Item $ws -Recurse -Force }
$nd = Join-Path $ws 'build\nightly'
$acks = Join-Path $ws 'docs\nightly-acks'
$null = New-Item -ItemType Directory -Force -Path $nd, $acks, (Join-Path $ws 'todo\00-workspace'), (Join-Path $ws 'tests\UI')
@('# fixture', '', '## 9. Nine', '', '- [ ] Fix INC-cccc3333 (UI.C.T) and INC-dddd4444 (UI.C.T).', '', '## 10. Ten', '', 'Prose naming INC-eeee5555 without an item.', '', "|   9   |   ${S}9   | Nine | -- |  [ ]   |", "|   10  |   ${S}10  | Ten | -- |  [ ]   |") | Set-Content -Path (Join-Path $ws 'todo\00-workspace\TODO-02-fixture.md') -Encoding UTF8
'build/' | Set-Content -Path (Join-Path $ws '.gitignore') -Encoding UTF8
'class C { }' | Set-Content -Path (Join-Path $ws 'tests\UI\C.cs') -Encoding UTF8
Invoke-Git @('init', '-q'); Invoke-Git @('config', 'user.name', 'Fixture Operator'); Invoke-Git @('config', 'user.email', 'fixture@example.invalid'); Invoke-Git @('config', 'commit.gpgsign', 'false')
Invoke-Git @('add', '-A'); Invoke-Git @('commit', '-q', '-m', 'init')
function New-Red([string]$Id, [string]$Day, [string[]]$Inc, [int]$Rev = 1, [string]$Path = '') {
  $st = $Id.Substring(0, 17)
  if ($Path -eq '') { $Path = Join-Path $nd "morning-$st.result.json" }
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
  [pscustomobject]@{ version = 1; revision = $Rev; stamp = $st; day = $Day; identity = $Id; verdict = 'red'; exit = 1; incidents = @($Inc) } | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}
$fnd9 = "D00 T02 ${S}9"
# Item 4: lateness reads the committer date, so a backdated author date on
# a late commit still reads late.
$runA = '2026-10-02-023001-pid40'
New-Red $runA '2026-10-02' @('- INC-cccc3333 `UI.C.T` x1 (Run A): boom')
$dem = Get-Dem
Write-Ack 'ack-a.md' @("run: $runA sha256:$($dem[$runA].Current)", 'incidents: INC-cccc3333', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-02')
$eap = $ErrorActionPreference
try { $ErrorActionPreference = 'Continue'; $env:GIT_AUTHOR_DATE = '2026-10-02T03:00:00+02:00'; $env:GIT_COMMITTER_DATE = '2026-10-09T10:00:00+02:00'; $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m 'ack a (backdated author)' 2>&1 } finally { Remove-Item Env:\GIT_AUTHOR_DATE -ErrorAction SilentlyContinue; Remove-Item Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue; $ErrorActionPreference = $eap }
$g4 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
Assert (@($g4.Lines | Where-Object { $_ -like "*LATE response: $runA first acknowledged 2026-10-09T10:00:00*" }).Count -eq 1) 's46-backdated-author-date-still-reads-late' ($g4.Lines -join ' | ')
# Item 2: a withdrawal keeps the open action of the ack it releases.
Write-Ack 'ack-w.md' @("run: $runA sha256:$($dem[$runA].Current)", 'owner: operator', 'disposition: withdrawn', 'signed: 2026-10-10')
Save-All 'withdraw a'
$g2 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
Assert (($g2.Unacked -contains $runA) -and (@($g2.Lines | Where-Object { $_ -like "*CORRECTIVE ack-a.md ($fnd9): open*no longer governs its run*" }).Count -eq 1)) 's46-withdrawn-ack-keeps-its-open-action' ($g2.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-w.md'), (Join-Path $acks 'ack-a.md'); Save-All 'drop a and w'
# Item 9: a fix closes only on a later passing run; filed needs an item.
$runB = '2026-10-03-023001-pid41'
New-Red $runB '2026-10-03' @('- INC-dddd4444 `UI.C.T` x1 (Run A): boom')
'class C { int fixedIt; }' | Set-Content -Path (Join-Path $ws 'tests\UI\C.cs') -Encoding UTF8
Save-All 'fix the C test'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $shaC = ((& git -C $ws rev-parse HEAD) | Out-String).Trim().Substring(0, 12); $ErrorActionPreference = $eap
$dem = Get-Dem
Write-Ack 'ack-b.md' @("run: $runB sha256:$($dem[$runB].Current)", 'incidents: INC-dddd4444', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $shaC", 'signed: 2026-10-03')
Save-All 'ack b fixed'
$g9 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
$open9 = @($g9.Lines | Where-Object { $_ -like "*CORRECTIVE ack-b.md ($shaC): open*awaiting a passing run of INC-dddd4444*" }).Count
# Item 13: the status view names the governing ack, the deadline, the
# owners, the pending incident, and what blocks it.
$st13 = Invoke-Helper @('-Status', '-Run', $runB, '-Today', '2026-10-10', '-WorkspaceRoot', $ws)
[pscustomobject]@{ version = 1; incidents = @([pscustomobject]@{ id = 'INC-dddd4444'; test = 'UI.C.T'; phase = 'run-a'; key = 'k'; owner = 'operator'; state = 'open'; firstSeen = '2026-10-03-023001'; lastSeen = '2026-10-03-023001'; closedAt = ''; closedBy = ''; occurrences = @([pscustomobject]@{ stamp = '2026-10-03-023001'; wheres = @('run-a') }); passStreak = 1; lastPassStamp = '2099-01-01-023001'; due = ''; finding = '' }) } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $nd 'incidents.json') -Encoding UTF8
$g9b = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
$closed9 = @($g9b.Lines | Where-Object { $_ -like "*CORRECTIVE ack-b.md ($shaC): closed (commit $shaC, verified by a later pass)*" }).Count
$item9 = (Test-SectionMentions $ws $fnd9 @('INC-cccc3333')) -and (-not (Test-SectionMentions $ws "D00 T02 ${S}10" @('INC-eeee5555')))
Assert (($open9 -eq 1) -and ($closed9 -eq 1) -and $item9) 's46-fix-needs-a-later-pass-and-filed-needs-an-item' "open=$open9 closed=$closed9 item=$item9 || $($g9.Lines -join ' | ')"
Assert (($st13.Text -like "*governing: ack-b.md*") -and ($st13.Text -like '*deadline: 2026-10-03T08:00:00*') -and ($st13.Text -notlike '*blocking: ack-b.md: acknowledges*') -and ($st13.Text -like '*owners: owner operator, corrective-owner operator*') -and ($st13.Text -like '*incident INC-dddd4444: pending*') -and ($st13.Text -like "*blocking: CORRECTIVE ack-b.md ($shaC): open*")) 's46-status-explains-a-run' $st13.Text
Remove-Item (Join-Path $nd 'incidents.json')
# Item 3: a revised result keeps its original due.
$runC = '2026-10-04-023001-pid42'
New-Red $runC '2026-10-04' @()
New-Red $runC '2026-10-20' @() 2 (Join-Path $nd 'retained\c-rev2\result.json')
$g3 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
Assert (@($g3.Lines | Where-Object { $_ -like "*OVERDUE ack: $runC (RED*due 2026-10-07T23:59:59*" }).Count -eq 1) 's46-revised-result-keeps-its-original-due' ($g3.Lines -join ' | ')
# Item 6: an invalid revision 2 keeps revision 1 current and is flagged.
$runD = '2026-10-05-023001-pid43'
New-Red $runD '2026-10-05' @()
$revOne = (Get-Dem)[$runD].Current
[pscustomobject]@{ version = 1; revision = 2; stamp = $runD.Substring(0, 17); day = '2026-10-05'; identity = $runD; verdict = 'red'; exit = 0; incidents = @() } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nd 'morning-2026-10-05-999999.result.json') -Encoding UTF8
$d6 = Get-Dem
$g6 = Test-Acknowledgements $ws $acks $d6 (Get-Date '2026-10-06')
Assert (($d6[$runD].Current -eq $revOne) -and (@($g6.Lines | Where-Object { $_ -like "*REVISION conflict: $runD revision 2 (morning-2026-10-05-999999.result.json) is invalid (verdict red contradicts exit 0)*revision 1 stays current*" }).Count -eq 1)) 's46-invalid-revision-never-supersedes' ($g6.Lines -join ' | ')
Remove-Item (Join-Path $nd 'morning-2026-10-05-999999.result.json')
# Item 8: a damaged result deleted before repair keeps its demand.
$bad8 = Join-Path $nd 'morning-2026-10-06-023001.result.json'
'{ damaged' | Set-Content -Path $bad8 -Encoding UTF8
$null = Update-CorruptionRecord (Join-Path $nd 'ack-corruption.json') (Get-Dem) '2026-10-06'
Remove-Item $bad8
$g8 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-07')
Assert (($g8.Unacked -contains 'unreadable:morning-2026-10-06-023001.result.json') -and (@($g8.Lines | Where-Object { $_ -like '*UNACKED unreadable:morning-2026-10-06-023001.result.json (UNREADABLE result*deleted or renamed while unreadable*' }).Count -eq 1)) 's46-deleted-damage-stays-demanded' ($g8.Lines -join ' | ')
# Item 7: a repair that lands on a run with its own demand merges: the
# earlier deadline carries and the damaged file's ack stays on record.
$runE = '2026-10-08-023001-pid44'
New-Red $runE '2026-10-08' @()
$recE = @{ version = 1; entries = @([pscustomobject]@{ file = 'morning-2026-10-01-023001.result.json'; firstSeen = '2026-10-01'; reason = 'unreadable'; restored = $runE; restoredOn = '2026-10-08'; sha = ('a' * 64) }) }
[pscustomobject]$recE | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $nd 'ack-corruption.json') -Encoding UTF8
Write-Ack 'ack-e-damaged.md' @("run: unreadable:morning-2026-10-01-023001.result.json sha256:$('a' * 64)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-02')
Save-All 'ack the damaged file'
$g7 = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-09')
Assert ((@($g7.Lines | Where-Object { $_ -like "*CORRUPTION merge: unreadable:morning-2026-10-01-023001.result.json restored as $runE*" }).Count -eq 1) -and (@($g7.Lines | Where-Object { $_ -like '*ack-e-damaged.md: acknowledges nothing current; STALE for unreadable:morning-2026-10-01-023001.result.json*' }).Count -eq 1) -and (@($g7.Lines | Where-Object { $_ -like "*OVERDUE ack: $runE (RED 2026-10-08, due 2026-10-04T23:59:59*" }).Count -eq 1) -and (@($g7.Lines | Where-Object { $_ -like "*CORRECTIVE ack-e-damaged.md ($fnd9): open*" }).Count -eq 1)) 's46-repair-collision-keeps-both-histories' ($g7.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-e-damaged.md'); Remove-Item (Join-Path $nd 'ack-corruption.json'); Save-All 'drop e'
# Item 11: two covers for one incident refuse, and a coverage fault
# rejects only the run carrying that incident.
$runF = '2026-10-09-023001-pid45'
$runG = '2026-10-09-120001-pid46'
New-Red $runF '2026-10-09' @('- INC-f0000001 `UI.C.T` x1 (Run A): boom', '- INC-f0000002 `UI.C.T` x1 (Run A): boom')
New-Red $runG '2026-10-09' @('- INC-f0000003 `UI.C.T` x1 (Run A): boom')
$dF = Get-Dem
$covText = ((@('---', 'ack-version: 2', "run: $runF sha256:$($dF[$runF].Current)", "run: $runG sha256:$($dF[$runG].Current)", 'incidents: INC-f0000001, INC-f0000002, INC-f0000003', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", "cover: INC-f0000001 filed $fnd9", "cover: INC-f0000001 expected $fnd9", "cover: INC-f0000002 filed $fnd9", "cover: INC-f0000003 filed $fnd9", 'signed: 2026-10-09', '---')) -join "`n") + "`n"
$v11 = Test-AckV2 $covText $dF
$soloText = ((@('---', 'ack-version: 2', "run: $runF sha256:$($dF[$runF].Current)", 'incidents: INC-f0000001, INC-f0000002', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", "cover: INC-f0000001 filed $fnd9", "cover: INC-f0000001 expected $fnd9", "cover: INC-f0000002 filed $fnd9", 'signed: 2026-10-09', '---')) -join "`n") + "`n"
$v11b = Test-AckV2 $soloText $dF
Assert ($v11.Ok -and (@($v11.Acked) -contains $runG) -and (@($v11.Acked) -notcontains $runF) -and (@($v11.Rejected | Where-Object { ($_.Run -eq $runF) -and ($_.Why -like '*cover names INC-f0000001 twice*') }).Count -eq 1) -and (-not $v11b.Ok) -and (($v11b.Errors -join ' ') -like '*cover names INC-f0000001 twice*')) 's46-overlapping-covers-refuse-and-reject-only-their-run' "acked=$($v11.Acked -join ',') rejected=$(@($v11.Rejected | ForEach-Object { $_.Run }) -join ',') || $($v11b.Errors -join '; ')"
# Item 10: an edited classification line reads tampered.
$cls = Join-Path $ws 'cls'
$null = New-Item -ItemType Directory -Force -Path $cls
$null = Add-ResultClassification $cls ([pscustomobject]@{ identity = 'run-1'; stamp = '2026-10-10-023001'; proof = $false }) ('1' * 64)
$null = Add-ResultClassification $cls ([pscustomobject]@{ identity = 'run-2'; stamp = '2026-10-10-120001'; proof = $true; proofSource = 'switches' }) ('2' * 64)
$okMap = Read-ResultClassifications $cls
$okTamper = "$($script:ResultClassTampered)"
$ledgerFile = Join-Path $cls $script:ResultClassLedger
$clsLines = [System.IO.File]::ReadAllLines($ledgerFile)
$clsLines[0] = $clsLines[0].Replace('"queue":"operational"', '"queue":"proof"')
[System.IO.File]::WriteAllLines($ledgerFile, $clsLines)
$badMap = Read-ResultClassifications $cls
Assert (($okTamper -eq '') -and ($okMap['run-2'].Queue -eq 'proof') -and ("$($script:ResultClassTampered)" -like 'line 1 was edited*') -and (-not $badMap.ContainsKey('run-1'))) 's46-edited-classification-reads-tampered' "$($script:ResultClassTampered)"
# Item 5: acks on two merged branches tie; a resolution naming every
# competing head in replaces: decides deterministically.
$runH = '2026-10-10-023001-pid47'
New-Red $runH '2026-10-10' @()
Save-All 'result h'
$dH = Get-Dem
$eap = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  $base = ((& git -C $ws rev-parse --abbrev-ref HEAD) | Out-String).Trim()
  $null = & git -C $ws checkout -q -b h1 2>&1
  Write-Ack 'ack-h1.md' @("run: $runH sha256:$($dH[$runH].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-10')
  $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m 'ack h1' 2>&1
  $null = & git -C $ws checkout -q $base 2>&1
  Write-Ack 'ack-h2.md' @("run: $runH sha256:$($dH[$runH].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-10')
  $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m 'ack h2' 2>&1
  $null = & git -C $ws merge -q --no-edit h1 2>&1
} finally { $ErrorActionPreference = $eap }
$g5a = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
Write-Ack 'ack-h3.md' @("run: $runH sha256:$($dH[$runH].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'replaces: ack-h1.md, ack-h2.md', 'signed: 2026-10-10')
Save-All 'resolve h'
$g5b = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
$g5c = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-10')
Assert ((@($g5a.Lines | Where-Object { $_ -like "*$runH TIE*" }).Count -eq 1) -and ($g5b.Governing[$runH] -eq 'ack-h3.md') -and ($g5c.Governing[$runH] -eq 'ack-h3.md') -and ($g5b.Unacked -notcontains $runH)) 's46-merge-resolution-decides-deterministically' (($g5a.Lines + @('||') + $g5b.Lines) -join ' | ')

# Section 46 R1-F1: two covers for a single listed incident refuse too.
$runT = '2026-10-11-023001-pid48'
New-Red $runT '2026-10-11' @('- INC-f0000004 `UI.C.T` x1 (Run A): boom')
$dT = Get-Dem
$oneText = ((@('---', 'ack-version: 2', "run: $runT sha256:$($dT[$runT].Current)", 'incidents: INC-f0000004', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", "cover: INC-f0000004 filed $fnd9", "cover: INC-f0000004 expected $fnd9", 'signed: 2026-10-11', '---')) -join "`n") + "`n"
$vOne = Test-AckV2 $oneText $dT
Assert ((-not $vOne.Ok) -and (($vOne.Errors -join ' ') -like '*cover names INC-f0000004 twice*')) 's46-single-incident-overlap-refuses' ($vOne.Errors -join '; ')
# Section 46 R1-F2: a duplicate chain P -> Q -> R waits on R's open action.
$runP = '2026-10-12-023001-pid49'; $runQ = '2026-10-12-120001-pid50'; $runR = '2026-10-12-180001-pid51'
foreach ($r in @($runP, $runQ, $runR)) { New-Red $r '2026-10-12' @() }
$dPQR = Get-Dem
Write-Ack 'ack-r.md' @("run: $runR sha256:$($dPQR[$runR].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-12')
Write-Ack 'ack-q.md' @("run: $runQ sha256:$($dPQR[$runQ].Current)", 'incidents: none', 'owner: operator', 'disposition: duplicate', "evidence: $runR", 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-12')
Write-Ack 'ack-p.md' @("run: $runP sha256:$($dPQR[$runP].Current)", 'incidents: none', 'owner: operator', 'disposition: duplicate', "evidence: $runQ", 'corrective-owner: operator', 'due: 2026-12-01', "finding: $fnd9", 'signed: 2026-10-12')
Save-All 'acks p q r'
$gChain = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-12')
Assert ((@($gChain.Lines | Where-Object { $_ -like "*CORRECTIVE ack-p.md ($fnd9): open (duplicate of $runQ; open while its action ack-q.md ($fnd9) is open*" }).Count -eq 1) -and (@($gChain.Lines | Where-Object { $_ -like "*CORRECTIVE ack-q.md ($fnd9): open (duplicate of $runR; open while its action ack-r.md ($fnd9) is open*" }).Count -eq 1)) 's46-duplicate-chain-waits-on-the-end' ($gChain.Lines -join ' | ')
# Section 46 R1-I2: status counts a superseded ack's open action.
Write-Ack 'ack-q2.md' @("run: $runQ sha256:$($dPQR[$runQ].Current)", 'incidents: none', 'owner: operator', 'disposition: expected', "finding: $fnd9", 'corrective-owner: operator', 'due: 2026-12-01', 'signed: 2026-10-13')
Save-All 'ack q2 supersedes q'
$stQ = Invoke-Helper @('-Status', '-Run', $runQ, '-Today', '2026-10-13', '-WorkspaceRoot', $ws)
Assert (($stQ.Text -like '*governing: ack-q2.md*') -and ($stQ.Text -like '*blocking: CORRECTIVE ack-q.md (D00 T02 *9): open*')) 's46-status-counts-superseded-actions' $stQ.Text
# Section 46 R1-C1: withdrawing a fixed ack in place keeps its historical
# action bound to the incidents that version listed.
$runS = '2026-10-14-023001-pid52'
New-Red $runS '2026-10-14' @('- INC-dddd4444 `UI.C.T` x1 (Run A): boom')
$dS = Get-Dem
Write-Ack 'ack-s.md' @("run: $runS sha256:$($dS[$runS].Current)", 'incidents: INC-dddd4444', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-12-01', "finding: $shaC", 'signed: 2026-10-14')
Save-All 'ack s fixed'
Write-Ack 'ack-s.md' @("run: $runS sha256:$($dS[$runS].Current)", 'owner: operator', 'disposition: withdrawn', 'signed: 2026-10-15')
Save-All 'withdraw s in place'
$gS = Test-Acknowledgements $ws $acks (Get-Dem) (Get-Date '2026-10-15')
Assert (@($gS.Lines | Where-Object { $_ -like "*CORRECTIVE ack-s.md ($shaC (dropped from the ack*): open*awaiting a passing run of INC-dddd4444*" }).Count -eq 1) 's46-in-place-withdrawal-keeps-the-verification-debt' ($gS.Lines -join ' | ')
# Section 46 R1-I1: status reads the deadline the gate enforces,
# inheritance from a corruption repair included.
[pscustomobject]@{ version = 1; entries = @([pscustomobject]@{ file = 'morning-2026-10-01-023001.result.json'; firstSeen = '2026-10-01'; reason = 'unreadable'; restored = $runE; restoredOn = '2026-10-08'; sha = ('a' * 64) }) } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $nd 'ack-corruption.json') -Encoding UTF8
$stE = Invoke-Helper @('-Status', '-Run', $runE, '-Today', '2026-10-09', '-WorkspaceRoot', $ws)
Remove-Item (Join-Path $nd 'ack-corruption.json')
Assert ($stE.Text -like '*deadline: 2026-10-04T23:59:59*') 's46-status-reads-the-inherited-deadline' $stE.Text
# Section 46 R1-R1: two filings for different runs in flight at once both
# record, and neither is refused.
$runU = '2026-10-16-023001-pid53'; $runV = '2026-10-16-120001-pid54'
New-Red $runU '2026-10-16' @(); New-Red $runV '2026-10-16' @()
$tableS = Join-Path $acks 'overdue-findings.md'
$prevCc3 = $env:CLAUDECODE; $env:CLAUDECODE = '1'
$jobs = @()
foreach ($day in @('2026-10-25', '2026-10-26')) {
  $jobs += Start-Job -ScriptBlock { param($h, $d, $w) $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $h -FileOverdue -Commit -Today $d -WorkspaceRoot $w 2>&1 | ForEach-Object { "$_" }); [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($o -join ' | ') } } -ArgumentList $helper, $day, $ws
}
$res = @($jobs | ForEach-Object { $null = Wait-Job $_ -Timeout 120; Receive-Job $_; Remove-Job $_ -Force })
$env:CLAUDECODE = $prevCc3
$rowsUV = @(Get-Content $tableS | Where-Object { ($_ -like "| $runU |*") -or ($_ -like "| $runV |*") })
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $dirtyUV = @(& git -C $ws status --porcelain -- docs/nightly-acks/overdue-findings.md 2>$null); $ErrorActionPreference = $eap
Assert ((@($res | Where-Object { $_.Code -eq 0 }).Count -eq 2) -and (@($res | Where-Object { $_.Text -like '*another filing held*' }).Count -eq 0) -and ($rowsUV.Count -eq 2) -and ($dirtyUV.Count -eq 0)) 's46-concurrent-filings-both-record' (@($res | ForEach-Object { "$($_.Code): $($_.Text)" }) -join ' || ')

Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyAck.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyAck.Tests: all green'
exit 0
