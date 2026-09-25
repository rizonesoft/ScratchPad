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

Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyRetention.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyRetention.Tests: all green'
exit 0
