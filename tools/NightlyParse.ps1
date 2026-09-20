# Pures for the governed nightly run (D00 T02 §9, hardened §15).
# Result parsing plus report formatting, free of run state: tools/nightly.ps1
# dot-sources this file, and the parser fixture suite
# (tools/NightlyParse.Tests.ps1, D00 T02 §15 PR22) exercises these exact
# functions. Nothing here touches the network, the schedule, or the mutex.
$ErrorActionPreference = 'Stop'

function Get-TrxSummary([string]$TrxPath) {
  if (-not (Test-Path $TrxPath)) { return $null }
  # A killed leg can leave truncated XML; a throw here would kill the
  # report under $ErrorActionPreference = 'Stop', so malformed trx reads
  # as absent (the transcript still carries the counts).
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return $null }
  $results = @($t.TestRun.Results.UnitTestResult)
  $passed = @($results | Where-Object { $_.outcome -eq 'Passed' }).Count
  $failed = @($results | Where-Object { $_.outcome -eq 'Failed' })
  $skipped = @($results | Where-Object { $_.outcome -eq 'NotExecuted' })
  $failLines = @($failed | ForEach-Object {
    $msg = ''
    if ($_.Output -and $_.Output.ErrorInfo -and $_.Output.ErrorInfo.Message) { $msg = $_.Output.ErrorInfo.Message }
    $msg = ($msg -split "`r?`n")[0]
    if ($msg.Length -gt 160) { $msg = $msg.Substring(0, 160) }
    '  - ' + $_.testName + ': ' + $msg
  })
  $skipLines = @($skipped | ForEach-Object {
    $reason = 'triage annotates'
    if ($_.Output -and $_.Output.ErrorInfo -and $_.Output.ErrorInfo.Message) { $reason = (($_.Output.ErrorInfo.Message -split "`r?`n")[0]) }
    '  - ' + $_.testName + ': ' + $reason
  })
  return [pscustomobject]@{ Passed = $passed; FailedCount = $failed.Count; Failed = $failLines; Skipped = $skipLines; SkippedCount = $skipped.Count }
}

function Get-TranscriptRows([string]$LogPath) {
  # VSTest assembly summary lines. A solution-level trx keeps only the last
  # assembly (each project overwrites LogFileName), so the transcript is the
  # authoritative per-leg count; the trx carries failure messages.
  $rows = @()
  if (-not (Test-Path $LogPath)) { return $rows }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '(Passed!|Failed!)\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),.*-\s*(\S+)\s*\(net')
    if ($m.Success) {
      $rows += [pscustomobject]@{ Assembly = $m.Groups[5].Value; Passed = [int]$m.Groups[3].Value; Failed = [int]$m.Groups[2].Value; Skipped = [int]$m.Groups[4].Value }
    }
  }
  return $rows
}

function Get-TranscriptFailures([string]$LogPath) {
  $names = @()
  if (-not (Test-Path $LogPath)) { return $names }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '^\s*Failed (\S+) \[')
    if ($m.Success -and ($names -notcontains $m.Groups[1].Value)) { $names += $m.Groups[1].Value }
  }
  return $names
}

function Get-NonQuarantineSkips([string]$TrxPath) {
  # The Interactive bar excuses quarantine plus capability skips only
  # (docs/testing.md): any other skip reds the leg. xUnit's exit code
  # stays zero under skips, so the trx is the enforcement point.
  # Classification prefers the stable CAPABILITY: reason code (D00 T02
  # §15 item 1); the legacy free-text list covers trx from binaries
  # predating the code, fallback only.
  $names = @()
  if (-not (Test-Path $TrxPath)) { return $names }
  # Same truncated-XML guard as Get-TrxSummary: malformed trx reads as
  # no skips (the transcript skip merge still reports the names).
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return $names }
  $legacyCapability = @(
    'Low-level mouse hooks are unavailable on this host',
    'No printers enumerated in this context',
    'Default printer is hardware'
  )
  foreach ($r in @($t.TestRun.Results.UnitTestResult | Where-Object { $_.outcome -eq 'NotExecuted' })) {
    $msg = ''
    if ($r.Output -and $r.Output.ErrorInfo -and $r.Output.ErrorInfo.Message) { $msg = $r.Output.ErrorInfo.Message }
    if ($msg -like '*QUARANTINED*') { continue }
    if ($msg -like 'CAPABILITY:*') { continue }
    $legacy = $false
    foreach ($frag in $legacyCapability) { if ($msg -like "*$frag*") { $legacy = $true; break } }
    if ($legacy) { continue }
    $names += $r.testName
  }
  return $names
}

function Get-TranscriptSkips([string]$LogPath) {
  $names = @()
  if (-not (Test-Path $LogPath)) { return $names }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '^\s*Skipped (\S+) \[')
    if ($m.Success -and ($names -notcontains $m.Groups[1].Value)) { $names += $m.Groups[1].Value }
  }
  return $names
}

function Get-LegSummary([string]$TrxPath, [string]$LogPath) {
  $trx = Get-TrxSummary $TrxPath
  $rows = Get-TranscriptRows $LogPath
  if ($rows.Count -eq 0) { return $trx }
  $p = ($rows | Measure-Object Passed -Sum).Sum
  $f = ($rows | Measure-Object Failed -Sum).Sum
  $s = ($rows | Measure-Object Skipped -Sum).Sum
  $failLines = @()
  $trxNames = @()
  if ($null -ne $trx) {
    $failLines += $trx.Failed
    $trxNames = @($trx.Failed | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  }
  foreach ($n in (Get-TranscriptFailures $LogPath)) {
    if ($trxNames -notcontains $n) { $failLines += "  - $n : see transcript" }
  }
  $skipLines = @()
  if ($null -ne $trx) { $skipLines += $trx.Skipped }
  $trxSkipNames = @($skipLines | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  foreach ($n in (Get-TranscriptSkips $LogPath)) {
    if ($trxSkipNames -notcontains $n) { $skipLines += "  - $n : see transcript" }
  }
  $asm = ($rows | ForEach-Object { "$($_.Assembly) $($_.Passed)/$($_.Failed)/$($_.Skipped)" }) -join ', '
  return [pscustomobject]@{ Passed = $p; FailedCount = $f; Failed = $failLines; Skipped = $skipLines; SkippedCount = $s; Assemblies = $asm }
}

function Format-SoakLedger([string]$TrxDir, [string[]]$Killed, [string[]]$Cut) {
  # Fourth-phase soak verdict (D00 T02 §15 PR7): per-iteration rows keep
  # the §14 mark vocabulary (proved, killed at cap: unproven, budget-cut
  # unproven) and gain a FAILED mark plus an aggregate verdict line, so
  # a red soak cannot hide behind green legs. The verdict line carries
  # machine-readable counts for the §17 trend surface. Returns Rows plus
  # a Failed flag the caller wires into the run verdict.
  $rows = @()
  $names = @()
  foreach ($i in 1..5) { $names += "ui-soak-$i" }
  foreach ($i in 1..5) { $names += "protocol-soak-$i" }
  $proved = 0
  $failedNames = @()
  $unproven = @()
  foreach ($n in $names) {
    $st = Get-TrxSummary (Join-Path $TrxDir "$n.trx")
    if ($null -eq $st) {
      if ($Killed -contains $n) { $unproven += $n; $rows += "- $n : no trx (killed at cap: unproven)" }
      continue
    }
    if ($Killed -contains $n) { $unproven += $n; $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (killed at cap: unproven)" }
    elseif ($st.FailedCount -gt 0) { $failedNames += $n; $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (FAILED)"; $rows += $st.Failed }
    else { $proved++; $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (proved)" }
  }
  foreach ($c in @($Cut | Where-Object { $_ -like '*soak-*' })) {
    $unproven += $c
    $rows += "- $c : budget-cut (unproven)"
  }
  if ($rows.Count -eq 0) { return [pscustomobject]@{ Rows = @('(no soak iterations ran: -SkipSoak or budget-cut before the first)'); Failed = $false } }
  $bits = @()
  if ($failedNames.Count -gt 0) { $bits += "FAILED: $($failedNames -join ', ')" }
  if ($unproven.Count -gt 0) { $bits += "unproven: $($unproven -join ', ')" }
  if ($bits.Count -eq 0) { $verdict = "- Verdict: GREEN ($proved/10 iterations proved)" }
  else { $verdict = "- Verdict: RED ($($bits -join '; '); fails the run like a leg)" }
  return [pscustomobject]@{ Rows = (@($verdict) + $rows); Failed = ($bits.Count -gt 0) }
}

function Format-LegRow([string]$Leg, $Sum, $Gate, [string]$LogName, [string]$Note = '') {
  # Test, gate, and infrastructure verdicts report in separate cells
  # (D00 T02 §15 PR8): the infrastructure note owns its column, never
  # parenthesized into the counts.
  if ($null -eq $Sum) {
    $noInfra = if ($Note -ne '') { $Note } else { '-' }
    return "| $Leg | no trx (leg skipped or produced none) | -- | $noInfra | $($LogName) |"
  }
  # The cell's skip count is the assembly sum (D00 T02 §15 item 2), so it
  # equals the per-assembly breakdown by construction; the merged
  # name-lines stay best-effort evidence below the counts.
  $skips = if ($null -ne $Sum.SkippedCount) { $Sum.SkippedCount } else { $Sum.Skipped.Count }
  $gate = if ($null -eq $Gate) { 'n/a (owns the foreground)' } else { "exit $($Gate.GateCode) $($Gate.Verdict)" }
  $counts = "$($Sum.Passed) passed, $($Sum.FailedCount) failed, $skips skipped"
  if ($Sum.Assemblies) { $counts += " ($($Sum.Assemblies))" }
  $infra = if ($Note -ne '') { $Note } else { '-' }
  return "| $Leg | $counts | $gate | $infra | $($LogName) |"
}

function Get-ShortHash([string]$Path) {
  # First 8 hex of SHA256 for snapshot identity (D00 T02 §15 PR9).
  if (-not (Test-Path $Path)) { return 'missing' }
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hash = $sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))
      return ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 8).ToLower()
    } finally { $sha.Dispose() }
  } catch { return 'unreadable' }
}

function Format-EnforcementVerdict([bool]$Ran, [string[]]$Leaked) {
  # Enforcement verdict, separate from test, gate, and infrastructure
  # (D00 T02 §15 PR8): the Interactive allowlist decides quarantine
  # plus capability; anything else names names.
  if (-not $Ran) { return '- Interactive (collection): n/a (leg did not run)' }
  if ($Leaked.Count -gt 0) { return "- Interactive (collection): RED ($($Leaked.Count) non-quarantine skips: $($Leaked -join ', '))" }
  return '- Interactive (collection): GREEN (every skip quarantined or capability)'
}
