<# Nightly trend renderer (D00 T02 §17 items 2, 4, 9).

Reads versioned result files (the current night dir plus retained
runs) and the quarantine ledger, renders the Markdown trend surface.
Best-effort: invalid results skip with a note, never fail the run.
#>
param(
  [string]$NightDir = 'build/nightly',
  [string]$OutFile = 'build/nightly/trend.md',
  [string]$LedgerPath = 'docs/soak-and-quarantine.md'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$results = @()
$skipped = @()
$paths = @()
$paths += @(Get-ChildItem $NightDir -Filter 'morning-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$paths += @(Get-ChildItem $NightDir -Filter 'loser-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$paths += @(Get-ChildItem (Join-Path $NightDir 'retained') -Filter 'result.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($p in ($paths | Sort-Object -Unique)) {
  $chk = Test-ResultFile $p
  if ($chk.Ok) { $results += Read-ResultFile $p }
  else { $skipped += "$p ($($chk.Error))" }
}
# Long-term metrics (D00 T02 §25 item 7): every valid result lands one
# compact row in build/nightly/metrics.jsonl (append-only, never pruned),
# and a night whose raw result retention pruned renders from its row.
$metricsNote = ''
try {
  $mrows = @(Sync-MetricsStore (Join-Path $NightDir 'metrics.jsonl') $results)
  $live = @{}
  foreach ($r in $results) { $live["$($r.identity)"] = $true }
  $fromMetrics = @($mrows | Where-Object { -not $live.ContainsKey("$($_.identity)") } | ForEach-Object { ConvertFrom-MetricsRow $_ })
  $results += $fromMetrics
  $metricsNote = "- Metrics store: $($mrows.Count) row(s), $($fromMetrics.Count) night(s) rendered from metrics after pruning"
} catch { $metricsNote = "- Metrics store: unavailable ($($_.Exception.Message))" }
$quar = Test-QuarantineWindows $LedgerPath (Get-Date)
$dueSoon = Get-DueSoonTests $quar.OpenRows (Get-Date) 3
$lines = Format-TrendTable $results @{ Overdue = @($quar.Overdue); DueSoon = @($dueSoon) }
if ($metricsNote -ne '') { $lines += ''; $lines += $metricsNote }
if ($skipped.Count -gt 0) {
  $lines += ''
  $lines += ("- Skipped invalid results: " + ($skipped -join '; '))
}
Write-AtomicReport $lines $OutFile
Write-Output ("trend: {0} nights from {1} results ({2} skipped) -> {3}" -f @(@($results | ForEach-Object { $_.day } | Sort-Object -Unique).Count, $results.Count, $skipped.Count, $OutFile))
