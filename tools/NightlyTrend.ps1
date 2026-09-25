<# Nightly trend renderer (D00 T02 §17 items 2, 4, 9; §25; §32).

Reads versioned result files (the current night dir plus retained
runs) and the quarantine ledger, renders the Markdown trend surface.
Best-effort: invalid results skip with a note, never fail the run, and
the night each belongs to reads degraded (section 32 item 8). Recorded
pauses in docs/nightly-pauses.md read paused, not missing (item 7).
-Compact rewrites the metrics store to its current rows after a backup
(item 10) and renders nothing.
#>
param(
  [string]$NightDir = 'build/nightly',
  [string]$OutFile = 'build/nightly/trend.md',
  [string]$LedgerPath = 'docs/soak-and-quarantine.md',
  [string]$PausesPath = 'docs/nightly-pauses.md',
  [switch]$Compact
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$storePath = Join-Path $NightDir 'metrics.jsonl'
if ($Compact) {
  Write-Output (Compress-MetricsStore $storePath)
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
    if ($night -notmatch '^\d{4}-\d{2}-\d{2}$') { $m = [regex]::Match((Split-Path -Leaf $p), '(\d{4}-\d{2}-\d{2})'); if ($m.Success) { $night = $m.Groups[1].Value } }
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
  foreach ($r in $results) { $live["$($r.identity)"] = $true }
  $fromMetrics = @($mrows | Where-Object { -not $live.ContainsKey("$($_.identity)") } | ForEach-Object { ConvertFrom-MetricsRow $_ })
  $results += $fromMetrics
  # A backfill a native night superseded leaves the render (item 11).
  $supersessions = @($script:MetricsSupersessions | ForEach-Object { [pscustomobject]@{ Night = "$($_.night)"; Native = "$($_.native)"; Backfill = "$($_.backfill)" } })
  $superseded = @($supersessions | ForEach-Object { $_.Backfill })
  $results = @($results | Where-Object { $superseded -notcontains "$($_.identity)" })
  $metricsNote = "- Metrics store: $($mrows.Count) row(s), $($fromMetrics.Count) night(s) rendered from metrics after pruning"
  if (@($script:MetricsLastMalformed).Count -gt 0) { $metricsNote += "; $(@($script:MetricsLastMalformed).Count) malformed line(s) skipped (lines $(@($script:MetricsLastMalformed) -join ', '); run tools/NightlyTrend.ps1 -Compact)" }
} catch { $metricsNote = "- Metrics store: unavailable ($($_.Exception.Message))" }
$quar = Test-QuarantineWindows $LedgerPath (Get-Date)
$dueSoon = Get-DueSoonTests $quar.OpenRows (Get-Date) 3
# The governed task's own calendar decides which nights were due (R1-C1).
$schedule = Get-NightlySchedule (Join-Path $PSScriptRoot 'tasks/nightly-ui.xml')
$lines = Format-TrendTable $results @{ Overdue = @($quar.Overdue); DueSoon = @($dueSoon) } (Get-Date) (Read-NightlyPauses $PausesPath) $degraded $supersessions $schedule
if ($metricsNote -ne '') { $lines += ''; $lines += $metricsNote }
if ($skipped.Count -gt 0) {
  $lines += ''
  $lines += (Protect-DisclosedText ("- Skipped invalid results: " + ($skipped -join '; ')))
}
Write-AtomicReport $lines $OutFile
Write-Output ("trend: {0} nights from {1} results ({2} skipped) -> {3}" -f @(@($results | ForEach-Object { $_.day } | Sort-Object -Unique).Count, $results.Count, $skipped.Count, $OutFile))
