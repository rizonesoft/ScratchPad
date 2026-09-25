# Retention fixture suite for tools/NightlyRetention.ps1 (D00 T02 §22
# item 2). Self-contained: builds a temp workspace with stamp dirs,
# drives the real script through -WorkspaceRoot, and exits nonzero on
# any failure. Covers retain under quota, the count and byte quota
# refusals (loud, nothing copied), and verify over the result.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'NightlyRetention.ps1'

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
function Invoke-Retention([string[]]$ArgList) {
  $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $script @ArgList 2>&1 | ForEach-Object { "$_" })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out; Text = ($out -join ' | ') }
}

$ws = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-retention-fixtures'
if (Test-Path $ws) { Remove-Item $ws -Recurse -Force }
$night = Join-Path $ws 'build\nightly'
foreach ($stamp in @('2026-09-20-023001', '2026-09-21-023001', '2026-09-22-023001')) {
  $d = Join-Path $night $stamp
  $null = New-Item -ItemType Directory -Force -Path $d
  "trx for $stamp" | Set-Content -Path (Join-Path $d 'run-a-UI.trx') -Encoding UTF8
  [System.IO.File]::WriteAllBytes((Join-Path $d 'blob.bin'), (New-Object byte[] 65536))
}
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws 'docs\nightly-evidence')

# Under quota: two retains land with their manifests and KEEP marks.
$r1 = Invoke-Retention @('-Retain', '-Source', '2026-09-20-023001', '-Name', 'fx-one', '-Provenance', 'fixture', '-MaxRetained', '2', '-WorkspaceRoot', $ws)
Assert (($r1.Code -eq 0) -and ($r1.Text -like '*retain: fx-one kept*')) 'retain-under-quota' $r1.Text
$r2 = Invoke-Retention @('-Retain', '-Source', '2026-09-21-023001', '-Name', 'fx-two', '-Provenance', 'fixture', '-MaxRetained', '2', '-WorkspaceRoot', $ws)
Assert ($r2.Code -eq 0) 'retain-at-quota' $r2.Text
Assert ((Test-Path (Join-Path $ws 'docs\nightly-evidence\fx-two.md')) -and (Test-Path (Join-Path $night '2026-09-21-023001\KEEP.txt'))) 'retain-writes-manifest-and-keep'

# Count quota: a third retain refuses loud and copies nothing.
$r3 = Invoke-Retention @('-Retain', '-Source', '2026-09-22-023001', '-Name', 'fx-three', '-Provenance', 'fixture', '-MaxRetained', '2', '-WorkspaceRoot', $ws)
Assert (($r3.Code -eq 1) -and ($r3.Text -like '*QUOTA REFUSED: 3 retained runs after this retain*nothing copied*')) 'retain-over-count-refuses-loud' $r3.Text
# D00 T02 section 30 item 3: the refusal names release candidates, oldest first.
Assert ($r3.Text -like '*retain: release candidates (oldest first): retained/fx-one (*; cited by *') 'retain-refusal-names-release-candidates' $r3.Text
Assert ((-not (Test-Path (Join-Path $night 'retained\fx-three'))) -and (-not (Test-Path (Join-Path $ws 'docs\nightly-evidence\fx-three.md'))) -and (-not (Test-Path (Join-Path $night '2026-09-22-023001\KEEP.txt')))) 'retain-refusal-copies-nothing'

# Byte quota: the same retain under a tight byte cap refuses too.
$r4 = Invoke-Retention @('-Retain', '-Source', '2026-09-22-023001', '-Name', 'fx-three', '-Provenance', 'fixture', '-MaxRetained', '20', '-MaxRetainedBytes', '200000', '-WorkspaceRoot', $ws)
Assert (($r4.Code -eq 1) -and ($r4.Text -like '*QUOTA REFUSED: exempt evidence*exceeds*nothing copied*')) 'retain-over-bytes-refuses-loud' $r4.Text
Assert (-not (Test-Path (Join-Path $night 'retained\fx-three'))) 'retain-byte-refusal-copies-nothing'

# Raising the cap on the command line lets it through.
$r5 = Invoke-Retention @('-Retain', '-Source', '2026-09-22-023001', '-Name', 'fx-three', '-Provenance', 'fixture', '-MaxRetained', '3', '-WorkspaceRoot', $ws)
Assert ($r5.Code -eq 0) 'retain-raised-cap-passes' $r5.Text

# Capture protection: a source whose capture still holds a secret, or
# carries the scan-failure marker, refuses before any byte moves.
$leak = Join-Path $night '2026-09-23-023001'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $leak 'captures-run-a')
('pid=1 x: ' + 'ghp_' + ('A1b2C3d4E5' * 4)) | Set-Content -Path (Join-Path $leak 'captures-run-a\run-a-windows.txt') -Encoding UTF8
$r6 = Invoke-Retention @('-Retain', '-Source', '2026-09-23-023001', '-Name', 'fx-leak', '-Provenance', 'fixture', '-MaxRetained', '20', '-WorkspaceRoot', $ws)
Assert (($r6.Code -eq 1) -and ($r6.Text -like '*PROTECTION REFUSED: captures-run-a/run-a-windows.txt holds github-token*nothing copied*') -and (-not (Test-Path (Join-Path $night 'retained\fx-leak')))) 'retain-refuses-unredacted-capture' $r6.Text
'clean window list' | Set-Content -Path (Join-Path $leak 'captures-run-a\run-a-windows.txt') -Encoding UTF8
'run-a-windows.txt' | Set-Content -Path (Join-Path $leak 'captures-run-a\SECRET-SCAN-FAILED.txt') -Encoding UTF8
$r7 = Invoke-Retention @('-Retain', '-Source', '2026-09-23-023001', '-Name', 'fx-leak', '-Provenance', 'fixture', '-MaxRetained', '20', '-WorkspaceRoot', $ws)
Assert (($r7.Code -eq 1) -and ($r7.Text -like '*PROTECTION REFUSED: captures-run-a/SECRET-SCAN-FAILED.txt present*')) 'retain-refuses-scan-failure-marker' $r7.Text
Remove-Item (Join-Path $leak 'captures-run-a\SECRET-SCAN-FAILED.txt') -Force
$r8 = Invoke-Retention @('-Retain', '-Source', '2026-09-23-023001', '-Name', 'fx-leak', '-Provenance', 'fixture', '-MaxRetained', '20', '-WorkspaceRoot', $ws)
Assert ($r8.Code -eq 0) 'retain-clean-capture-passes' $r8.Text

# The catalog verifies clean, then faults on a manifest without bytes.
$v1 = Invoke-Retention @('-Verify', '-WorkspaceRoot', $ws)
Assert (($v1.Code -eq 0) -and ($v1.Text -like '*all retained runs clean (4 runs)*')) 'verify-catalog-current' $v1.Text
Remove-Item (Join-Path $night 'retained\fx-two') -Recurse -Force
$v2 = Invoke-Retention @('-Verify', '-WorkspaceRoot', $ws)
Assert (($v2.Code -eq 1) -and ($v2.Text -like '*fx-two FAULT: manifest without bytes*')) 'verify-catalog-loss-faults' $v2.Text

# D00 T02 section 32 item 9: a stamp dir whose result has no metrics row
# refuses to prune; once the trend archives it, the prune proceeds.
$old = Join-Path $night '2026-07-01-023001'
$null = New-Item -ItemType Directory -Force -Path $old
'trx' | Set-Content -Path (Join-Path $old 'run-a-UI.trx') -Encoding UTF8
[pscustomobject]@{ version = 1; stamp = '2026-07-01-023001'; day = '2026-07-01'; identity = '2026-07-01-023001-pid5'; verdict = 'green'; exit = 0 } | ConvertTo-Json | Set-Content -Path (Join-Path $night 'morning-2026-07-01-023001.result.json') -Encoding UTF8
$pr1 = Invoke-Retention @('-Prune', '-Execute', '-WorkspaceRoot', $ws)
Assert (($pr1.Code -eq 1) -and ($pr1.Text -like '*prune: REFUSED 2026-07-01-023001/ (result 2026-07-01-023001-pid5 has no metrics row; run tools/NightlyTrend.ps1 to archive it first)*') -and (Test-Path $old)) 'prune-refuses-unarchived-stamp' $pr1.Text
# Archive it the way the trend does: a full row computed from the result.
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$null = Sync-MetricsStore (Join-Path $night 'metrics.jsonl') @((Get-Content (Join-Path $night 'morning-2026-07-01-023001.result.json') -Raw | ConvertFrom-Json))
$pr2 = Invoke-Retention @('-Prune', '-Execute', '-WorkspaceRoot', $ws)
Assert ((-not (Test-Path $old)) -and ($pr2.Text -like '*prune: deleted 2026-07-01-023001/*')) 'prune-proceeds-once-archived' $pr2.Text

# D00 T02 §45 item 3: the protected lifecycle snapshot counts against the
# byte quota, is named on every quota refusal apart from the release
# candidates, and keeps its stamp directory through prune.
$ws3 = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-retention-snapshot'
if (Test-Path $ws3) { Remove-Item $ws3 -Recurse -Force }
$night3 = Join-Path $ws3 'build\nightly'
$snapStamp = '2026-09-18-023001'
foreach ($st in @($snapStamp, '2026-09-19-023001')) {
  $d3 = Join-Path $night3 $st
  $null = New-Item -ItemType Directory -Force -Path $d3
  [System.IO.File]::WriteAllBytes((Join-Path $d3 'blob.bin'), (New-Object byte[] 65536))
}
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws3 'docs\nightly-evidence')
$pad = 'x' * 200000
$snapRow = [pscustomobject]@{ id = 'INC-0000aaaa'; test = 'UI.S.T'; phase = 'run-a'; key = 'k'; state = 'open'; owner = 'operator'; occurrences = 1; occurrenceStamps = @($snapStamp); occurrenceWheres = @('run-a'); firstSeen = $snapStamp; lastSeen = $snapStamp; passStreak = 0; lastPassStamp = ''; closedAt = ''; closedBy = ''; contract = 'v2'; due = ''; finding = '' }
[pscustomobject]@{ version = 1; stamp = $snapStamp; day = '2026-09-18'; identity = "$snapStamp-pid1"; verdict = 'stood-down'; exit = 0; incidents = @(); incidentLifecycleSource = 'ledger'; incidentLifecycle = @($snapRow); pad = $pad } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $night3 "morning-$snapStamp.result.json") -Encoding UTF8
$q = Invoke-Retention @('-Retain', '-Source', '2026-09-19-023001', '-Name', 'fx-snap', '-Provenance', 'fixture', '-MaxRetained', '20', '-MaxRetainedBytes', '250000', '-WorkspaceRoot', $ws3)
Assert (($q.Code -eq 1) -and ($q.Text -like "*retain: protected (counted, never released): lifecycle snapshot $snapStamp (morning-$snapStamp.result.json,*") -and ($q.Text -like '*QUOTA REFUSED: exempt evidence*') -and (-not (Test-Path (Join-Path $night3 'retained\fx-snap')))) 's45-quota-names-and-counts-the-snapshot' $q.Text
$pr = Invoke-Retention @('-Prune', '-OlderThanDays', '0', '-WorkspaceRoot', $ws3)
Assert ($pr.Text -like "*prune: keep $snapStamp/ (protected lifecycle snapshot)*") 's45-prune-keeps-the-snapshot-stamp' $pr.Text
Remove-Item $ws3 -Recurse -Force
Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyRetention.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyRetention.Tests: all green'
exit 0
