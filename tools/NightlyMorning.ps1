#Requires -Version 5.1
<#
.SYNOPSIS
  Morning reconciler for the governed nightly (D00 T02 §24 items 3, 4, 8).
.DESCRIPTION
  Runs from its own scheduled task (\ScratchPad\Nightly Morning, 07:05
  daily, tools/tasks/nightly-morning.xml), independent of the nightly,
  so it reports what the nightly cannot: (1) a night with no scheduled
  start alerts immediately as scheduler-no-start once the window has
  closed; (2) routine results queued by the nightly flush as one
  morning digest toast; (3) notifications whose delivery failed are
  re-sent and removed on success. Idempotent per day through the
  notify ledger: a second run the same morning sends nothing twice.
  -DryRun prints the plan and sends nothing. Exit 0 always (a
  reconciler that fails loud to nobody helps nobody); every outcome is
  appended to build/nightly/morning-reconcile.log.
#>
[CmdletBinding()]
param(
  [string]$ExpectBy = '06:50',
  [switch]$DryRun,
  [string]$NightDir = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
. (Join-Path $PSScriptRoot 'NightlyNotify.ps1')
if ($NightDir -eq '') { $NightDir = Join-Path $Root 'build\nightly' }
$null = New-Item -ItemType Directory -Force -Path $NightDir
$now = Get-Date
$day = $now.ToString('yyyy-MM-dd')
$log = @()
$sender = { param($t, $l) if ($DryRun) { return $true } else { return (Send-NightlyToast $t $l) } }

$results = @()
foreach ($f in @(Get-ChildItem $NightDir -Filter 'morning-*.result.json' -File -ErrorAction SilentlyContinue)) {
  try { $results += (Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $log += "unreadable result $($f.Name)" }
}

# (1) No-start: independent of any governed run firing.
$ns = Get-NoStartVerdict $results $now $ExpectBy
$log += "no-start: $($ns.Line)"
if ($ns.NoStart) {
  $r = Invoke-NightlyNotify -Phase 'final' -RunId "no-start-$day" -ResultPath '' -Class 'scheduler-no-start' -Title "Nightly $day : NO START (scheduler-no-start)" -Lines @($ns.Line, "Report: build/nightly/morning-reconcile.log") -StateDir $NightDir -Sender $sender -Now $now
  $log += "no-start notify: $($r.Status) ($($r.Notes -join '; '))"
}

# (2) Digest: every queued routine notification in one toast.
$qPath = Join-Path $NightDir 'digest-queue.json'
$queue = @()
try { $queue = @(Read-JsonState $qPath @()) } catch { $log += "digest queue unreadable: $($_.Exception.Message)" }
$dg = Format-Digest $queue $day
if ($null -ne $dg) {
  $sent = $false
  try { $sent = [bool](& $sender $dg.Title @($dg.Lines + @('Report: build/nightly/morning-' + $day + '.md'))) } catch { $sent = $false }
  if ($sent) {
    if (-not $DryRun) { Write-AtomicReport @('[]') $qPath }
    $log += "digest: sent $(@($queue).Count) queued notification(s)"
  } else { $log += "digest: delivery failed, $(@($queue).Count) stay queued for the next reconcile (reports escalate via the queue age)" }
} else { $log += 'digest: nothing queued' }

# (3) Undelivered: re-send, remove on success.
foreach ($u in @(Get-ChildItem (Join-Path $NightDir 'undelivered') -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
  try {
    $p = Get-Content $u.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $ok = [bool](& $sender "$($p.title) (re-sent)" @($p.lines))
    if ($ok) { if (-not $DryRun) { Remove-Item $u.FullName -Force }; $log += "undelivered $($u.Name): re-sent" }
    else { $log += "undelivered $($u.Name): still failing" }
  } catch { $log += "undelivered $($u.Name): unreadable or failed: $($_.Exception.Message)" }
}

$stampLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss'))$(if ($DryRun) { ' (dry run)' })"
$log | ForEach-Object { Write-Output "morning: $_" }
if (-not $DryRun) {
  try { Add-Content -Path (Join-Path $NightDir 'morning-reconcile.log') -Value (@("## $stampLine") + ($log | ForEach-Object { "- $_" })) -Encoding UTF8 } catch { }
}
exit 0
