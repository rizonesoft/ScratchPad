<# Nightly trend renderer (D00 T02 §17 items 2, 4, 9; §25; §32).

Reads versioned result files (the current night dir plus retained
runs) and the quarantine ledger, renders the Markdown trend surface.
Best-effort: invalid results skip with a note, never fail the run, and
the night each belongs to reads degraded (section 32 item 8). Recorded
pauses in docs/nightly-pauses.md read paused, not missing (item 7).
-Compact rewrites the metrics store to its current rows after a backup
(item 10) and renders nothing; -Restore rewrites it from that backup
(section 40 item 10). Operator exclusions in docs/nightly-exclusions.md
leave every series (section 40 item 8); docs/nightly-schedule-history.md
carries the schedule's trigger history (item 3); the alert lifecycle
lands in build/nightly/alerts.json (item 15).
#>
param(
  [string]$NightDir = 'build/nightly',
  [string]$OutFile = 'build/nightly/trend.md',
  [string]$LedgerPath = 'docs/soak-and-quarantine.md',
  [string]$PausesPath = 'docs/nightly-pauses.md',
  [string]$ExclusionsPath = 'docs/nightly-exclusions.md',
  [string]$ScheduleHistoryPath = 'docs/nightly-schedule-history.md',
  [string]$HostAliasesPath = 'docs/nightly-host-aliases.md',
  [string]$AlertAcksPath = 'docs/nightly-acks/alert-acks.md',
  [switch]$Compact,
  [switch]$Restore
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$storePath = Join-Path $NightDir 'metrics.jsonl'
# Host aliases resolve before any key is read (D00 T02 section 47 item 3).
$script:HostAliases = Read-HostAliases $HostAliasesPath
if ($Compact) {
  Write-Output (Compress-MetricsStore $storePath)
  exit 0
}
if ($Restore) {
  Write-Output (Restore-MetricsStore $storePath)
  exit 0
}

# The trend's inputs (validated results, the metrics store's
# authoritative rows, superseded backfills removed) come from one shared
# loader the nightly's notification also reads (D00 T02 section 33 R2-I1).
$inputs = Get-TrendInputResults $NightDir $storePath
$results = @($inputs.Results)
$skipped = @($inputs.Skipped)
$degraded = @($inputs.Degraded)
$supersessions = @($inputs.Supersessions)
$migNotes = @($inputs.MigNotes)
$metricsNote = $inputs.MetricsNote
$quar = Test-QuarantineWindows $LedgerPath (Get-Date)
$dueSoon = Get-DueSoonTests $quar.OpenRows (Get-Date) 3
# The governed task's own calendar decides which nights were due (R1-C1).
# The recorded history wins over the task definition (section 40 item 3).
$schedule = Read-ScheduleHistory $ScheduleHistoryPath
if ($null -eq $schedule) { $schedule = Get-NightlySchedule (Join-Path $PSScriptRoot 'tasks/nightly-ui.xml') }
$null = Set-ResultExclusions $results (Read-NightlyExclusions $ExclusionsPath)
$script:TrendAlertGroups = @()
# The journaled live run (section 47 item 9): a run still going past its
# grace reads overrun on the calendar.
$running = $null
try {
  $jr = Read-RunJournal $NightDir
  if ($jr.Exists -and $jr.Ok -and ($jr.Phase -notin @('final', 'cancelled', 'failed-after-result')) -and (Test-JournalProcessAlive $jr.Pid $jr.Started)) { $running = [pscustomobject]@{ Night = (Get-NightKey $jr.Started); Started = $jr.Started.ToString('yyyy-MM-dd HH:mm') } }
} catch { $running = $null }
$lines = Format-TrendTable $results @{ Overdue = @($quar.Overdue); DueSoon = @($dueSoon) } (Get-Date) (Read-NightlyPauses $PausesPath) $degraded $supersessions $schedule $running
$lines += $migNotes
if ($metricsNote -ne '') { $lines += ''; $lines += $metricsNote; $lines += @(Format-PrunedEvidence $results) }
# The alert lifecycle (section 40 item 15): new alerts notify once,
# persisting ones stay quiet, and closed ones name how they closed.
if (@($script:TrendAlertGroups).Count -gt 0) {
  try {
    $nNew = 0; $nPer = 0; $closedAll = @()
    foreach ($g in @($script:TrendAlertGroups)) {
      $life = Update-AlertLedger @($g.Alerts) (Join-Path $NightDir 'alerts.json') $g.Evaluation @($supersessions | ForEach-Object { $_.Backfill }) (Read-AlertAcks $AlertAcksPath (Split-Path -Parent $PSScriptRoot))
      $nNew += @($life.NewIds).Count; $nPer += @($life.Persisting).Count; $closedAll += @($life.Closed)
    }
    $lines += "- Alert lifecycle: $nNew new, $nPer persisting, $(@($closedAll).Count) closed$(if (@($closedAll).Count -gt 0) { ' (' + ((@($closedAll) | ForEach-Object { "$($_.Id) $($_.State)" }) -join '; ') + ')' })"
  } catch { $lines += "- Alert lifecycle: unavailable ($($_.Exception.Message))" }
}
if ($skipped.Count -gt 0) {
  $lines += ''
  $lines += (Protect-DisclosedText ("- Skipped invalid results: " + ($skipped -join '; ')))
}
Write-AtomicReport $lines $OutFile
Write-Output ("trend: {0} nights from {1} results ({2} skipped) -> {3}" -f @(@($results | ForEach-Object { $_.day } | Sort-Object -Unique).Count, $results.Count, $skipped.Count, $OutFile))
