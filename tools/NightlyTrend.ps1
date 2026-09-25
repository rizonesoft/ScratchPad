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
  [switch]$Compact,
  [switch]$Restore
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$storePath = Join-Path $NightDir 'metrics.jsonl'
if ($Compact) {
  Write-Output (Compress-MetricsStore $storePath)
  exit 0
}
if ($Restore) {
  Write-Output (Restore-MetricsStore $storePath)
  exit 0
}

$results = @()
$skipped = @()
$degraded = @()
$paths = @()
$paths += @(Get-ChildItem $NightDir -Filter 'morning-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$paths += @(Get-ChildItem $NightDir -Filter 'loser-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$paths += @(Get-ChildItem (Join-Path $NightDir 'retained') -Filter 'result.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($p in ($paths | Sort-Object -Unique)) {
  $chk = Test-ResultFile $p
  if ($chk.Ok) { $results += Read-ResultFile $p }
  else {
    # Named relative to the night directory, never by an absolute path
    # (the disclosure contract, D00 T02 section 32 item 14).
    $rel = $p
    try { $nd = (Resolve-Path $NightDir).Path; if ($p.StartsWith($nd, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $p.Substring($nd.Length).TrimStart('\', '/') } } catch { }
    $skipped += "$rel ($($chk.Error))"
    # The night a broken result belongs to: its own recorded night when
    # the JSON still parses, else the date in its file name.
    $night = ''
    try { $night = Get-ResultNight (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) } catch { }
    # A retained copy is named result.json, so the date comes from the
    # nearest path segment that carries one (section 32 R3-I3).
    if ($night -notmatch '^\d{4}-\d{2}-\d{2}$') { $m = [regex]::Matches($p, '(\d{4}-\d{2}-\d{2})'); if ($m.Count -gt 0) { $night = $m[$m.Count - 1].Groups[1].Value } }
    if ($night -ne '') { $degraded += [pscustomobject]@{ Night = $night; Reason = "$(Split-Path -Leaf $p): $($chk.Error)" } }
  }
}
# Long-term metrics (D00 T02 §25 item 7): every valid result lands one
# compact row in build/nightly/metrics.jsonl (append-only, never pruned),
# and a night whose raw result retention pruned renders from its row.
$metricsNote = ''
$supersessions = @()
try {
  $mrows = @(Sync-MetricsStore $storePath $results)
  $live = @{}
  foreach ($r in $results) { $live[(Get-MetricsKey ([pscustomobject]@{ identity = "$($r.identity)"; hostKey = (Get-ResultHostKey $r) }))] = $true }
  $fromMetrics = @($mrows | Where-Object { -not $live.ContainsKey((Get-MetricsKey $_)) } | ForEach-Object { ConvertFrom-MetricsRow $_ })
  $null = Add-MergedEvidence $results $mrows
  $results += $fromMetrics
  # A backfill a native night superseded leaves the render (item 11).
  $supersessions = @($script:MetricsSupersessions | ForEach-Object { [pscustomobject]@{ Night = "$($_.night)"; Native = "$($_.native)"; Backfill = "$($_.backfill)" } })
  $superseded = @($supersessions | ForEach-Object { $_.Backfill })
  $results = @($results | Where-Object { $superseded -notcontains (Get-MetricsKey ([pscustomobject]@{ identity = "$($_.identity)"; hostKey = (Get-ResultHostKey $_) })) })
  $metricsNote = "- Metrics store: $($mrows.Count) row(s), $($fromMetrics.Count) night(s) rendered from metrics after pruning"
  if ("$script:MetricsWriteError" -ne '') { $metricsNote += "; $script:MetricsWriteError" }
  if (@($script:MetricsStaleSkipped).Count -gt 0) { $metricsNote += "; $(@($script:MetricsStaleSkipped).Count) stale result(s) older than their stored revision left unchanged" }
  if (@($script:MetricsLastMalformed).Count -gt 0) { $metricsNote += "; $(@($script:MetricsLastMalformed).Count) malformed line(s) skipped (lines $(@($script:MetricsLastMalformed) -join ', '); run tools/NightlyTrend.ps1 -Compact)" }
} catch { $metricsNote = "- Metrics store: unavailable ($($_.Exception.Message))" }
$quar = Test-QuarantineWindows $LedgerPath (Get-Date)
$dueSoon = Get-DueSoonTests $quar.OpenRows (Get-Date) 3
# The governed task's own calendar decides which nights were due (R1-C1).
# The recorded history wins over the task definition (section 40 item 3).
$schedule = Read-ScheduleHistory $ScheduleHistoryPath
if ($null -eq $schedule) { $schedule = Get-NightlySchedule (Join-Path $PSScriptRoot 'tasks/nightly-ui.xml') }
$null = Set-ResultExclusions $results (Read-NightlyExclusions $ExclusionsPath)
$script:TrendAlertGroups = @()
$lines = Format-TrendTable $results @{ Overdue = @($quar.Overdue); DueSoon = @($dueSoon) } (Get-Date) (Read-NightlyPauses $PausesPath) $degraded $supersessions $schedule
if ($metricsNote -ne '') { $lines += ''; $lines += $metricsNote; $lines += @(Format-PrunedEvidence $results) }
# The alert lifecycle (section 40 item 15): new alerts notify once,
# persisting ones stay quiet, and closed ones name how they closed.
if (@($script:TrendAlertGroups).Count -gt 0) {
  try {
    $nNew = 0; $nPer = 0; $closedAll = @()
    foreach ($g in @($script:TrendAlertGroups)) {
      $life = Update-AlertLedger @($g.Alerts) (Join-Path $NightDir 'alerts.json') $g.Evaluation @($supersessions | ForEach-Object { $_.Backfill })
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
