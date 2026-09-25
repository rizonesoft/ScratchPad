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
@('# fixture', '', '## 9. Nine', '', 'Tracks INC-aaaa1111 (UI.A) and INC-bbbb2222 (UI.B).', '', "|   9   |   ${S}9   | Nine | -- |  [ ]   |") | Set-Content -Path (Join-Path $ws 'todo\00-workspace\TODO-02-fixture.md') -Encoding UTF8
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
# Item 2: a duplicate of an acknowledged run closes at signing.
Write-Ack 'ack-x.md' @("run: $runX sha256:$($dem[$runX].Current)", 'incidents: none', 'owner: operator', 'disposition: filed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Write-Ack 'ack-y.md' @("run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: duplicate', "evidence: $runX", 'corrective-owner: operator', 'due: 2026-10-10', "finding: $fnd", 'signed: 2026-09-25')
Save-All 'acks x and y'
$gd = Get-Gate
Assert ((@($gd.Lines | Where-Object { $_ -like "*CORRECTIVE ack-y.md ($fnd): closed (duplicate of acknowledged $runX)*" }).Count -eq 1) -and (@($gd.Lines | Where-Object { $_ -like "*CORRECTIVE ack-x.md ($fnd): open*" }).Count -eq 1)) 's39-duplicate-of-acked-run-closes-at-signing' ($gd.Lines -join ' | ')
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
# Item 7: an unrelated fixed commit fails.
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
'notes' | Set-Content -Path (Join-Path $ws 'docs\notes.md') -Encoding UTF8; $null = & git -C $ws add -A 2>&1; $null = & git -C $ws commit -q -m 'docs only' 2>&1
$docSha = ((& git -C $ws rev-parse HEAD) | Out-String).Trim()
$ErrorActionPreference = $eap
Write-Ack 'ack-y.md' @("run: $runY sha256:$($dem[$runY].Current)", 'incidents: none', 'owner: operator', 'disposition: fixed', 'corrective-owner: operator', 'due: 2026-10-10', "finding: $($docSha.Substring(0, 12))", 'signed: 2026-09-25')
Save-All 'ack y fixed by docs'
$gu = Get-Gate
Assert (@($gu.Lines | Where-Object { $_ -like "*ack-y.md: INVALID (fixed needs a commit touching src/, tests/, or the failing test's file*" }).Count -eq 1) 's39-unrelated-fixed-commit-fails' ($gu.Lines -join ' | ')
Remove-Item (Join-Path $acks 'ack-y.md'); Save-All 'drop y'
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
$w3 = Invoke-Helper @('-FileOverdue', '-Commit', '-Today', '2026-09-30', '-WorkspaceRoot', $ws)
$held.Dispose()
Assert (($w2.Text -like '*an uncommitted filing from an interrupted run was committed*') -and ($clean.Count -eq 0) -and ($w3.Code -eq 1) -and ($w3.Text -like '*another filing holds*')) 's39-interrupted-and-concurrent-filings-stay-consistent' ("$($w1.Text) || $($w2.Text) || $($w3.Text)")

Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyAck.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyAck.Tests: all green'
exit 0
