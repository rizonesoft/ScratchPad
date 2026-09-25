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
  [int]$LookbackDays = 7,
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
$ns = Get-NoStartVerdict $results $now $ExpectBy $LookbackDays
$log += "no-start: $($ns.Line)"
if ($ns.NoStart) {
  # One alert per missed date: the ledger key names the date, so a
  # later reconcile never repeats it.
  foreach ($md in $ns.Missed) {
    $r = Invoke-NightlyNotify -Phase 'final' -RunId "no-start-$md" -ResultPath '' -Class 'scheduler-no-start' -Title "Nightly $md : NO START (scheduler-no-start)" -Lines @("No governed nightly result for $md.", 'Check the task is enabled and fires; run the manual backup.', 'Report: build/nightly/morning-reconcile.log') -StateDir $NightDir -Sender $sender -Now $now -NoPersist:$DryRun
    $log += "no-start notify ${md}: $($r.Status) ($($r.Notes -join '; '))"
  }
}

# (2) Digest: every queued routine notification, whole, in
# build/nightly/digest-<day>.md plus one summary toast; a failed send
# falls back to the undelivered set.
try {
  $df = Invoke-DigestFlush -StateDir $NightDir -Day $day -Sender $sender -NoPersist:$DryRun -Now $now
  $log += "digest: $($df.Status) ($($df.Notes -join '; '))"
} catch { $log += "digest: failed: $($_.Exception.Message)" }

# (3) Undelivered: re-send under the notify lock, remove on success.
try { $log += @(Invoke-UndeliveredResend -StateDir $NightDir -Sender $sender -NoPersist:$DryRun) } catch { $log += "undelivered: failed: $($_.Exception.Message)" }

$stampLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss'))$(if ($DryRun) { ' (dry run)' })"
$log | ForEach-Object { Write-Output "morning: $_" }
if (-not $DryRun) {
  try { Add-Content -Path (Join-Path $NightDir 'morning-reconcile.log') -Value (@("## $stampLine") + ($log | ForEach-Object { "- $_" })) -Encoding UTF8 } catch { }
}
exit 0
