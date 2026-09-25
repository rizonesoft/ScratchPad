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
$resultFiles = @(Get-ChildItem $NightDir -Filter 'morning-*.result.json' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem (Join-Path $NightDir 'retained') -Filter 'result.json' -File -Recurse -ErrorAction SilentlyContinue)
foreach ($f in $resultFiles) {
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

# (1b) Trend alerts (D00 T02 §25 item 6): regression alerts the trend
# fired join the morning digest once per day, so a developing slope
# surfaces without anyone watching the trend.
try {
  $tPath = Join-Path $NightDir 'trend.md'
  if (Test-Path $tPath) {
    $tl = @(Get-Content $tPath -Encoding UTF8)
    $ai = [array]::IndexOf($tl, '## Alerts')
    $al = @()
    if ($ai -ge 0) { for ($i = $ai + 1; $i -lt $tl.Count; $i++) { if ($tl[$i] -like '## *') { break }; if ($tl[$i] -like '- ALERT *') { $al += $tl[$i].Substring(2) } } }
    if ($al.Count -gt 0) {
      # Keyed on the day alone (no result checksum), so a re-rendered
      # trend never notifies twice on one day (R1-F5).
      $ta = Invoke-NightlyNotify -Phase 'final' -RunId "trend-alert-$day" -ResultPath '' -Class 'trend-regression' -Title "Nightly trend $day : $($al.Count) alert(s)" -Lines (@($al) + @('Report: build/nightly/trend.md')) -StateDir $NightDir -Sender $sender -Now $now -NoPersist:$DryRun
      $log += "trend alerts: $($al.Count) ($($ta.Status))"
    } else { $log += 'trend alerts: none' }
  }
} catch { $log += "trend alerts: failed: $($_.Exception.Message)" }

# (1c) Overdue incidents (D00 T02 section 38 item 8): each open incident
# past its due date notifies its owner once a day (the run id names the
# incident and the day), read from the ledger the nightly keeps.
try {
  $lp = Join-Path $NightDir 'incidents.json'
  $lr = Read-IncidentLedger $lp
  if (-not $lr.Ok) { $log += "incident overdue: ledger unreadable: $($lr.Error)" }
  else {
    $od = @(Get-OverdueIncidentNotices $lr.Incidents $now.Date)
    foreach ($o in $od) {
      $on = Invoke-NightlyNotify -Phase 'final' -RunId $o.RunId -ResultPath '' -Class 'incident-overdue' -Title $o.Title -Lines @($o.Line, 'Ledger: build/nightly/incidents.json; links: docs/incident-links.md') -StateDir $NightDir -Sender $sender -NoPersist:$DryRun -Now $now
      $log += "incident overdue $($o.Id) (owner $($o.Owner)): $($on.Status)"
    }
    if ($od.Count -eq 0) { $log += 'incident overdue: none' }
  }
} catch { $log += "incident overdue: failed: $($_.Exception.Message)" }

# (1d) The published lifecycle, read through its consumer contract (D00
# T02 section 38 item 7): the newest result's block by version, or why
# triage cannot trust it; an unreadable block joins the digest.
try {
  $lastRes = @($results | Where-Object { @($_.PSObject.Properties.Name) -contains 'incidentLifecycle' }) | Sort-Object { "$($_.stamp)" } | Select-Object -Last 1
  if ($null -eq $lastRes) { $log += 'lifecycle: no result carries the block yet' }
  else {
    $lb = Read-LifecycleBlock $lastRes
    if ($lb.State -eq 'ok') { $log += "lifecycle: $($lastRes.stamp) contract v$($lb.Version), $(@($lb.Rows).Count) incident(s)" }
    else {
      $log += "lifecycle: $($lastRes.stamp) unreadable ($($lb.Error))"
      $lu = Invoke-NightlyNotify -Phase 'final' -RunId "lifecycle-unreadable-$($lastRes.stamp)" -ResultPath '' -Class 'infrastructure' -Title "Nightly $($lastRes.stamp) : incident lifecycle unreadable" -Lines @($lb.Error) -StateDir $NightDir -Sender $sender -NoPersist:$DryRun -Now $now
      $log += "lifecycle notify: $($lu.Status)"
    }
  }
} catch { $log += "lifecycle: failed: $($_.Exception.Message)" }

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
