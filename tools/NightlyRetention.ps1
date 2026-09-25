#Requires -Version 5.1
<#
.SYNOPSIS
  Executable retention gates for nightly run evidence (D00 T02 §15, D00-T02-S14-PR15).
.DESCRIPTION
  Three verbs over build/nightly (see docs/testing.md "Run-evidence
  retention"; owner DerickPayne). -Verify checks every retained run's
  bytes against its SHA256SUMS plus the tracked manifest under
  docs/nightly-evidence (missing bytes, mismatches, unlisted files,
  and manifest drift all fault). -Prune lists stamp dirs plus loose
  stamp transcripts older than -OlderThanDays (default 30) and deletes
  them only with -Execute; stamp-cited runs carry KEEP.txt and are
  exempt, unknown shapes are skipped, never auto-deleted. -Retain
  copies a stamp dir to retained/<name> with SHA256SUMS plus a tracked
  manifest and KEEP-marks the source; the copy refuses when free space
  falls below twice the source size (or -RequireFreeBytes), and any
  copy, hash, or write failure removes the partial target so no half
  retain ever stands. -Retain also refuses loud when the KEEP-exempt
  set would pass its quota (-MaxRetained runs, default 20, and
  -MaxRetainedBytes, default 2 GB, counting retained copies plus
  KEEP-marked stamp dirs; D00 T02 §22 item 2), so exempt evidence
  cannot grow into the low-disk refusal. Exactly one verb per invocation. Exit 0 clean,
  1 faults, 2 usage. The scheduled shape is a weekly -Verify plus a
  weekly -Prune -Execute from the operator's maintenance window.
#>
[CmdletBinding()]
param(
  [switch]$Verify,
  [switch]$Prune,
  [switch]$Execute,
  [switch]$Retain,
  [string]$Source = '',
  [string]$Name = '',
  [string]$Provenance = '',
  [int]$OlderThanDays = 30,
  [long]$RequireFreeBytes = 0,
  [int]$MaxRetained = 20,
  [long]$MaxRetainedBytes = 2GB,
  [string]$WorkspaceRoot = ''
)
$ErrorActionPreference = 'Stop'

$verbs = @($Verify, $Prune, $Retain | Where-Object { $_ }).Count
if ($verbs -ne 1) { Write-Output 'usage: exactly one of -Verify, -Prune, -Retain'; exit 2 }
if ($Execute -and (-not $Prune)) { Write-Output 'usage: -Execute needs -Prune'; exit 2 }
$Root = Split-Path -Parent $PSScriptRoot
# Fixture override (tools/NightlyRetention.Tests.ps1): the same verbs run
# against a temp workspace so quota and verify proofs never touch the
# real evidence.
if ($WorkspaceRoot -ne '') { $Root = (Resolve-Path $WorkspaceRoot).Path }
$NightDir = Join-Path $Root 'build\nightly'
$RetDir = Join-Path $NightDir 'retained'
$EvDir = Join-Path $Root 'docs\nightly-evidence'
$faults = 0

function Get-Sha256File([string]$Path) {
  # Lowercase SHA256 hex (direct .NET: this shell has no Get-FileHash).
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLower()
  } finally { $sha.Dispose() }
}

function Read-HashLines([string]$Path) {
  # Parses `sha256  path` lines; returns Lines plus Malformed.
  $lines = @()
  $malformed = @()
  foreach ($raw in (Get-Content $Path)) {
    $m = [regex]::Match($raw, '^([0-9a-fA-F]{64})  (\S.*\S|\S)$')
    if ($m.Success) { $lines += [pscustomobject]@{ Hash = $m.Groups[1].Value.ToLower(); Path = $m.Groups[2].Value } }
    elseif ($raw.Trim() -ne '') { $malformed += $raw }
  }
  return [pscustomobject]@{ Lines = $lines; Malformed = $malformed }
}

function Get-ManifestBlock([string]$Path) {
  # Hash lines inside the manifest's first fenced block, in order.
  $inFence = $false
  $block = @()
  foreach ($raw in (Get-Content $Path)) {
    if ($raw.Trim() -eq '```') {
      if ($inFence) { break }
      $inFence = $true
      continue
    }
    if ($inFence -and ($raw -match '^[0-9a-fA-F]{64}  \S')) { $block += $raw.Trim() }
  }
  return $block
}

if ($Verify) {
  if (-not (Test-Path $RetDir)) { Write-Output 'verify: no retained dir (nothing to check)'; exit 0 }
  $runs = @(Get-ChildItem -Path $RetDir -Directory)
  foreach ($run in $runs) {
    $label = "verify $($run.Name)"
    $before = $faults
    $sums = Join-Path $run.FullName 'SHA256SUMS'
    if (-not (Test-Path $sums)) { Write-Output "$label FAULT: SHA256SUMS missing"; $faults++; continue }
    $parsed = Read-HashLines $sums
    foreach ($bad in $parsed.Malformed) { Write-Output "$label FAULT: malformed sums line: $bad"; $faults++ }
    $listed = @{}
    foreach ($e in $parsed.Lines) {
      $rel = $e.Path -replace '/', '\'
      $wantPrefix = "build\nightly\retained\$($run.Name)\"
      if (-not $rel.StartsWith($wantPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output "$label FAULT: path escapes the run: $($e.Path)"; $faults++; continue
      }
      $full = Join-Path $Root $rel
      $listed[$full.ToLower()] = $true
      if (-not (Test-Path $full -PathType Leaf)) { Write-Output "$label FAULT: missing bytes: $($e.Path)"; $faults++; continue }
      try { $actual = Get-Sha256File $full }
      catch { Write-Output "$label FAULT: unreadable: $($e.Path) ($_)"; $faults++; continue }
      if ($actual -ne $e.Hash) { Write-Output "$label FAULT: checksum mismatch: $($e.Path)"; $faults++ }
    }
    foreach ($f in (Get-ChildItem -Path $run.FullName -Recurse -File)) {
      if (($f.Name -eq 'SHA256SUMS') -and ($f.DirectoryName -eq $run.FullName)) { continue }
      if (-not $listed.ContainsKey($f.FullName.ToLower())) { Write-Output "$label FAULT: unlisted file: $($f.FullName)"; $faults++ }
    }
    $manifest = Join-Path $EvDir ($run.Name + '.md')
    if (-not (Test-Path $manifest)) { Write-Output "$label FAULT: tracked manifest missing: docs/nightly-evidence/$($run.Name).md"; $faults++; continue }
    $title = (Get-Content $manifest -TotalCount 1).Trim()
    if ($title -ne "# Retained run: $($run.Name)") { Write-Output "$label FAULT: manifest title drifted: $title"; $faults++ }
    $wantBlock = @($parsed.Lines | ForEach-Object { "$($_.Hash)  $($_.Path)" })
    $gotBlock = @(Get-ManifestBlock $manifest)
    if (($wantBlock -join "`n") -ne ($gotBlock -join "`n")) {
      Write-Output "$label FAULT: manifest hash block drifts from SHA256SUMS ($($gotBlock.Count) vs $($wantBlock.Count) lines)"; $faults++
    }
    if ($faults -eq $before) { Write-Output "$label OK ($($parsed.Lines.Count) files)" }
  }
  foreach ($mf in @(Get-ChildItem -Path $EvDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
    $runName = [System.IO.Path]::GetFileNameWithoutExtension($mf.Name)
    if (-not (Test-Path (Join-Path $RetDir $runName) -PathType Container)) {
      Write-Output "verify ${runName} FAULT: manifest without bytes (loss of retained evidence is an incident)"; $faults++
    }
  }
  if ($faults -gt 0) { Write-Output "verify: $faults FAULT(S)"; exit 1 }
  Write-Output "verify: all retained runs clean ($($runs.Count) runs)"
  exit 0
}

if ($Prune) {
  $today = (Get-Date).Date
  . (Join-Path $PSScriptRoot 'NightlyParse.ps1')
  $metricsStore = Read-MetricsStore (Join-Path $NightDir 'metrics.jsonl')
  $refused = 0
  $kept = @{}
  foreach ($d in @(Get-ChildItem -Path $NightDir -Directory -ErrorAction SilentlyContinue)) {
    if (($d.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$') -and (Test-Path (Join-Path $d.FullName 'KEEP.txt'))) { $kept[$d.Name] = $true }
  }
  $plan = @()
  $skipped = 0
  foreach ($d in @(Get-ChildItem -Path $NightDir -Directory -ErrorAction SilentlyContinue)) {
    if ($d.Name -eq 'retained') { continue }
    $m = [regex]::Match($d.Name, '^(\d{4}-\d{2}-\d{2})-\d{6}$')
    if (-not $m.Success) { $skipped++; continue }
    $stampDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd', $null, 'None', [ref]$stampDate)) { $skipped++; continue }
    $age = ($today - $stampDate.Date).Days
    if ($kept.ContainsKey($d.Name)) { Write-Output "prune: keep $($d.Name)/ (KEEP: stamp-cited)"; continue }
    if ($age -le $OlderThanDays) { continue }
    # Archival before prune (D00 T02 section 32 item 9): a stamp whose
    # result has no metrics row keeps its directory until the trend has
    # archived it, and the prune says so loud.
    $arch = Test-StampArchived $NightDir $d.Name $metricsStore
    if (-not $arch.Ok) { Write-Output "prune: REFUSED $($d.Name)/ ($($arch.Reason); run tools/NightlyTrend.ps1 to archive it first)"; $refused++; continue }
    $bytes = (Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $plan += [pscustomobject]@{ Kind = 'dir'; Path = $d.FullName; Display = "$($d.Name)/ (${age}d, $([int]($bytes / 1KB)) KB)" }
  }
  foreach ($f in @(Get-ChildItem -Path $NightDir -File -ErrorAction SilentlyContinue)) {
    $m = [regex]::Match($f.Name, '^(\d{4}-\d{2}-\d{2})-\d{6}-.+\.log$')
    if (-not $m.Success) { continue }
    if ($kept.ContainsKey($m.Groups[0].Value.Substring(0, 17))) { continue }
    $stampDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd', $null, 'None', [ref]$stampDate)) { $skipped++; continue }
    $age = ($today - $stampDate.Date).Days
    if ($age -le $OlderThanDays) { continue }
    $plan += [pscustomobject]@{ Kind = 'file'; Path = $f.FullName; Display = "$($f.Name) (${age}d, $([int]($f.Length / 1KB)) KB)" }
  }
  if ($plan.Count -eq 0) { Write-Output "prune: nothing older than $OlderThanDays days ($skipped unknown shapes skipped)$(if ($refused -gt 0) { "; $refused refused (unarchived)" })"; if ($refused -gt 0) { exit 1 }; exit 0 }
  foreach ($p in $plan) { Write-Output "prune: candidate $($p.Display)" }
  if (-not $Execute) { Write-Output "prune: plan only ($($plan.Count) candidates); re-run with -Execute to delete"; if ($refused -gt 0) { exit 1 }; exit 0 }
  foreach ($p in $plan) {
    try {
      if ($p.Kind -eq 'dir') { Remove-Item -Path $p.Path -Recurse -Force } else { Remove-Item -Path $p.Path -Force }
      Write-Output "prune: deleted $($p.Display)"
    } catch { Write-Output "prune: FAULT deleting $($p.Display): $_"; $faults++ }
  }
  if ($faults -gt 0) { Write-Output "prune: $faults FAULT(S)"; exit 1 }
  Write-Output "prune: deleted $($plan.Count) paths"
  if ($refused -gt 0) { Write-Output "prune: $refused stamp dir(s) REFUSED (unarchived)"; exit 1 }
  exit 0
}

# -Retain
if (($Source -eq '') -or ($Name -eq '') -or ($Provenance -eq '')) { Write-Output 'usage: -Retain needs -Source, -Name, and -Provenance'; exit 2 }
if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { Write-Output "usage: bad run name '$Name'"; exit 2 }
$srcFull = $Source
if (-not [System.IO.Path]::IsPathRooted($srcFull)) { $srcFull = Join-Path $NightDir $Source }
try { $srcFull = (Resolve-Path $srcFull -ErrorAction Stop).Path } catch { Write-Output "retain: source missing: $Source"; exit 1 }
if (-not $srcFull.StartsWith($NightDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-Output "retain: source outside build/nightly: $Source"; exit 1
}
$target = Join-Path $RetDir $Name
$manifest = Join-Path $EvDir ($Name + '.md')
if ((Test-Path $target) -or (Test-Path $manifest)) { Write-Output "retain: target exists (no overwrite): $Name"; exit 1 }
$srcBytes = (Get-ChildItem -Path $srcFull -Recurse -File | Measure-Object Length -Sum).Sum
# Capture protection (D00 T02 §22 item 1, R3-F1): retention is the one
# path that keeps capture bytes past their 30 days, so it re-scans them
# itself and refuses on a failure marker, a secret hit, or an
# unreadable capture; nothing is copied until the source is clean.
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$prot = Test-RetainableCaptures $srcFull
if (-not $prot.Ok) {
  Write-Output "retain: PROTECTION REFUSED: $($prot.Reasons -join '; '); redact or delete the capture, then re-run; nothing copied"
  exit 1
}
# Quota over the KEEP exemptions (D00 T02 §22 item 2, D00-T02-S15-PR22):
# retained copies plus KEEP-marked stamp dirs never age out, so their
# count and bytes are capped, or stamped evidence would grow into the
# low-disk refusal it guards against. Over quota refuses loud before
# any byte moves; the operator releases a citation (or raises the cap
# on the command line, recorded with the retain) and re-runs.
$exempt = @{}
$exemptBytes = [long]0
foreach ($d in @(Get-ChildItem -Path $RetDir -Directory -ErrorAction SilentlyContinue)) {
  $exempt["retained/$($d.Name)"] = $true
  $exemptBytes += [long]((Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
}
foreach ($d in @(Get-ChildItem -Path $NightDir -Directory -ErrorAction SilentlyContinue)) {
  if (($d.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$') -and (Test-Path (Join-Path $d.FullName 'KEEP.txt'))) {
    $exempt["kept/$($d.Name)"] = $true
    $exemptBytes += [long]((Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
  }
}
$afterCount = @($exempt.Keys | Where-Object { $_ -like 'retained/*' }).Count + 1
$keptCount = @($exempt.Keys | Where-Object { $_ -like 'kept/*' }).Count
# Quota recovery (D00 T02 section 30 item 3): every refusal names the
# oldest exemptions and the tracked files citing them, so the operator
# knows what to release (docs/testing.md "Retention quota").
$releaseLine = "retain: release candidates (oldest first): $((@(Get-KeepReleaseCandidates $RetDir $NightDir $Root 3)) -join '; ')"
if (($afterCount -gt $MaxRetained) -or ($keptCount -ge $MaxRetained)) {
  Write-Output $releaseLine
  Write-Output "retain: QUOTA REFUSED: $afterCount retained runs after this retain, $keptCount KEEP-marked stamp dirs (cap $MaxRetained each); release a stamp citation or pass -MaxRetained with the reason recorded; nothing copied"
  exit 1
}
if (($exemptBytes + [long]$srcBytes * 2) -gt $MaxRetainedBytes) {
  Write-Output $releaseLine
  Write-Output "retain: QUOTA REFUSED: exempt evidence $([int]($exemptBytes / 1MB)) MB plus this retain $([int]($srcBytes * 2 / 1MB)) MB (copy plus KEEP-marked source) exceeds $([int]($MaxRetainedBytes / 1MB)) MB; release a stamp citation or pass -MaxRetainedBytes with the reason recorded; nothing copied"
  exit 1
}
$drive = (Get-Item $NightDir).PSDrive.Name
$free = (Get-PSDrive -Name $drive).Free
$need = if ($RequireFreeBytes -gt 0) { [long]$RequireFreeBytes } else { [long]($srcBytes * 2) }
if ($free -lt $need) { Write-Output "retain: low disk (free $([int]($free / 1MB)) MB, need $([int]($need / 1MB)) MB); nothing copied"; exit 1 }
try {
  Copy-Item -Path $srcFull -Destination $target -Recurse -Force
  $keepCopy = Join-Path $target 'KEEP.txt'
  if (Test-Path $keepCopy) { Remove-Item $keepCopy -Force }
  $hashLines = @()
  foreach ($f in (Get-ChildItem -Path $target -Recurse -File | Sort-Object FullName)) {
    $h = Get-Sha256File $f.FullName
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '/', '\'
    $hashLines += "$h  $rel"
  }
  $hashLines | Set-Content -Path (Join-Path $target 'SHA256SUMS') -Encoding UTF8
  $manifestBody = @("# Retained run: $Name", '', "Provenance: $Provenance. Bytes: ``build/nightly/retained/$Name/`` ($($hashLines.Count) files, ignored scratch); this manifest is the tracked hash record (D00 T02 §14 PR14).", '', '```') + $hashLines + @('```')
  if (-not (Test-Path $EvDir)) { $null = New-Item -ItemType Directory -Force -Path $EvDir }
  $manifestBody | Set-Content -Path $manifest -Encoding UTF8
  # Read-back: the retain verifies before it marks.
  $check = Read-HashLines (Join-Path $target 'SHA256SUMS')
  if (($check.Malformed.Count -gt 0) -or ($check.Lines.Count -ne $hashLines.Count)) { throw 'read-back mismatch on SHA256SUMS' }
  "retained as $Name on $((Get-Date).ToString('yyyy-MM-dd'))" | Set-Content -Path (Join-Path $srcFull 'KEEP.txt') -Encoding UTF8
  Write-Output "retain: $Name kept ($($hashLines.Count) files, $([int]($srcBytes / 1KB)) KB); source KEEP-marked"
  exit 0
} catch {
  Write-Output "retain: FAULT: $_ (removing partial target)"
  try { if (Test-Path $target) { Remove-Item $target -Recurse -Force } } catch { }
  try { if (Test-Path $manifest) { Remove-Item $manifest -Force } } catch { }
  exit 1
}
