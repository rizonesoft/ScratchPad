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

# (0) Interrupted publications (D00 T02 section 55 item 1): a result
# whose report never landed gets a report rebuilt from it, a report
# without a result moves to orphans/, and a recovered run the ledger
# never saw still notifies, linking what exists.
try {
  $gen = Repair-NightlyGenerations $NightDir $now -NoPersist:$DryRun
  $log += @($gen.Lines | ForEach-Object { "$_" })
  # Eligibility is the ledger's, not the repair's (R1-A2): every settled
  # result the ledger never recorded notifies, whatever its report state.
  foreach ($gr in @(Get-UnnotifiedResults $NightDir $results $now -LookbackDays $LookbackDays -Starts @((Read-StartEvidence $NightDir).Rows))) {
    $gs = "$($gr.stamp)"
    $gid = "$($gr.identity)"; if ($gid -eq '') { $gid = $gs }
    $gcls = 'infrastructure'
    try { $gcls = (Classify-NightlyOutcome $gr).Class } catch { }
    $gl = Resolve-NotifyReportLink $NightDir $gs
    $gn = Invoke-NightlyNotify -Phase 'final' -RunId $gid -ResultPath (Join-Path $NightDir "morning-$gs.result.json") -Class $gcls -Labels @(Get-OutcomeLabels $gr) -Slot (Get-NightSlotKey $gr) -Title "Nightly $(Get-ResultNight $gr) : $("$($gr.verdict)".ToUpper()) ($gcls, recovered publication)" -Lines @("The run's own notification never recorded (a crash before it); sent by the morning reconciler.", "Report: $($gl.Link)") -StateDir $NightDir -Sender $sender -Now $now -NoPersist:$DryRun
    $log += "generation $gs notify: $($gn.Status)"
  }
} catch { $log += "generation: failed: $($_.Exception.Message)" }

# (1) No-start: independent of any governed run firing. The recorded
# schedule excuses paused and skipped nights, and start evidence names
# each missed night's state (section 55 items 3 and 4).
$sched = Read-NightlySchedule (Join-Path $Root 'docs/nightly-schedule-history.md')
$starts = Read-StartEvidence $NightDir
if ($starts.Unreadable -gt 0) { $log += "start evidence: $($starts.Unreadable) unreadable line(s) in starts.jsonl" }
$ns = Get-NoStartVerdict $results $now $ExpectBy $LookbackDays $sched.Enrolled $sched @($starts.Rows)
$log += "no-start: $($ns.Line)"
if ($ns.NoStart) {
  # One alert per missed date: the ledger key names the date, so a
  # later reconcile never repeats it. A night that never started is the
  # scheduler's; one that started without a result is infrastructure.
  foreach ($md in $ns.Missed) {
    $nst = "$($ns.States[$md])"
    $ncls = if ($nst -eq 'never-started') { 'scheduler-no-start' } else { 'infrastructure' }
    $nword = switch ($nst) { 'never-started' { 'NO START' } 'still-running' { 'STILL RUNNING past the window' } 'hung' { 'HUNG' } default { 'STARTED, NO RESULT' } }
    $r = Invoke-NightlyNotify -Phase 'final' -RunId "no-start-$md" -ResultPath '' -Class $ncls -Title "Nightly $md : $nword ($ncls)" -Lines @("No governed nightly result for $md (start state: $nst).", $(if ($nst -eq 'never-started') { 'Check the task is enabled and fires; run the manual backup.' } else { 'A run started for this night; read build/nightly/starts.jsonl and the run journal.' }), 'Report: build/nightly/morning-reconcile.log') -StateDir $NightDir -Sender $sender -Now $now -NoPersist:$DryRun
    $log += "no-start notify ${md} (${nst}): $($r.Status) ($($r.Notes -join '; '))"
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
    # The lifecycle ledger (section 40 item 15): only new alerts notify,
    # a persisting one raised once already, and a closed one is named.
    $lPath = Join-Path $NightDir 'alerts.json'
    # Delivery is confirmed only after the sender accepts (R1-F6), and the
    # notify key names the pending set, so a second batch on one day is
    # not swallowed as a duplicate.
    $persistN = 0
    $pend = $null
    if (Test-Path $lPath) {
      $pend = Get-PendingAlertNotifications $lPath
      $al = @($pend.Lines)
      $persistN = $pend.Persisting
    }
    if ($al.Count -gt 0) {
      # Keyed on the day alone (no result checksum), so a re-rendered
      # trend never notifies twice on one day (R1-F5).
      $pk = if ($null -ne $pend) { '-' + (Get-TextHash (@($pend.Keys) -join "`n")) } else { '' }
      $ta = Invoke-NightlyNotify -Phase 'final' -RunId "trend-alert-$day$pk" -ResultPath '' -Class 'trend-regression' -Title "Nightly trend $day : $($al.Count) alert(s)" -Lines (@($al) + @('Report: build/nightly/trend.md')) -StateDir $NightDir -Sender $sender -Now $now -NoPersist:$DryRun
      $log += "trend alerts: $($al.Count) ($($ta.Status))"
      if (($null -ne $pend) -and (-not $DryRun) -and (@('sent', 'fallback', 'queued', 'duplicate') -contains "$($ta.Status)")) { Confirm-AlertNotifications $lPath @($pend.Keys) }
    } else { $log += "trend alerts: none new$(if ($persistN -gt 0) { " ($persistN persisting, already raised)" })" }
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
  # The queue reconciles against the current lifecycle (section 55
  # item 10): the canonical runs of every result read this morning.
  $canonNow = $null
  try { $canonNow = Select-CanonicalRuns $results } catch { }
  $latestStamp = "$(@($results | Where-Object { "$($_.stamp)" -match '^\d{4}-\d{2}-\d{2}-\d{6}$' } | ForEach-Object { "$($_.stamp)" } | Sort-Object) | Select-Object -Last 1)"
  $tri = if ($latestStamp -ne '') { (Resolve-NotifyReportLink $NightDir $latestStamp).Link } else { '' }
  $df = Invoke-DigestFlush -StateDir $NightDir -Day $day -Sender $sender -NoPersist:$DryRun -Now $now -Canonical $canonNow -Results $results -TriageLink $tri
  $log += "digest: $($df.Status) ($($df.Notes -join '; '))"
} catch { $log += "digest: failed: $($_.Exception.Message)" }

# (3) Undelivered: re-send under the notify lock, remove on success.
try { $log += @(Invoke-UndeliveredResend -StateDir $NightDir -Sender $sender -NoPersist:$DryRun) } catch { $log += "undelivered: failed: $($_.Exception.Message)" }

# (4) Delivery health and the independent escalation (D00 T02 section 33
# items 4 and 6): what is still undelivered after the re-send is written
# to this log, and consecutive failing nights escalate outside the toast
# API, so a persistently failing toast surfaces without any toast.
try { $log += @(Get-MorningDeliveryLines -StateDir $NightDir -Now $now -NoPersist:$DryRun | ForEach-Object { "$_".TrimStart('-', ' ') }) } catch { $log += "delivery: failed: $($_.Exception.Message)" }

# (5) Notify-state retention and capacity (section 55 item 9).
try { $log += @(Invoke-NotifyStateRetention -StateDir $NightDir -Now $now -NoPersist:$DryRun) } catch { $log += "retention: failed: $($_.Exception.Message)" }

$stampLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss'))$(if ($DryRun) { ' (dry run)' })"
$log | ForEach-Object { Write-Output "morning: $_" }
if (-not $DryRun) {
  try { Add-Content -Path (Join-Path $NightDir 'morning-reconcile.log') -Value (@("## $stampLine") + ($log | ForEach-Object { "- $_" })) -Encoding UTF8 } catch { }
}
exit 0
