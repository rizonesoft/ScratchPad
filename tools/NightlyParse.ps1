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
  # VSTest assembly summary lines. The transcript is the authoritative
  # per-leg count; each project's trx carries its failure messages plus
  # skip reasons (D00 T02 §15, D00-T02-S13-R2-F2: per-project trx files
  # replaced the shared solution-level name every project overwrote).
  $rows = @()
  if (-not (Test-Path $LogPath)) { return $rows }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '(Passed!|Failed!)\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+),.*-\s*(\S+)\s*\(net')
    if ($m.Success) {
      $rows += [pscustomobject]@{ Assembly = $m.Groups[6].Value; Passed = [int]$m.Groups[3].Value; Failed = [int]$m.Groups[2].Value; Skipped = [int]$m.Groups[4].Value; Total = [int]$m.Groups[5].Value }
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

function Test-InteractiveCaptureNeeded([int]$Code, [bool]$Killed, [bool]$EnfOk, [int]$LeakedCount) {
  # Interactive capture trigger matrix (D00 T02 §15 R4-F2): any red
  # reason captures (suite code, kill, unclassifiable trx, leaked
  # skips), so an enforcement-only red never lands a RED run with an
  # empty Captures section. Green nights capture nothing.
  return (($Code -ne 0) -or $Killed -or (-not $EnfOk) -or ($LeakedCount -gt 0))
}

function Get-NonQuarantineSkips([string]$TrxPath) {
  # The Interactive bar excuses quarantine plus capability skips only
  # (docs/testing.md): any other skip reds the leg. xUnit's exit code
  # stays zero under skips, so the trx is the enforcement point.
  # Returns Ok plus Names (module wrapper convention): a missing or
  # malformed trx returns Ok false (fail closed: an unclassifiable leg
  # is unproven, never green; the caller reds the run -- D00 T02 §15
  # R2-F1). Classification prefers the stable CAPABILITY: reason code
  # (D00 T02 §15 item 1); the legacy free-text list covers trx from
  # binaries predating the code, fallback only.
  # Matching is strict (D00 T02 §15 R2-F2): QUARANTINED needs the stamp
  # shape (date plus id), CAPABILITY: is case-sensitive, and legacy
  # fragments anchor to the message start, so prose merely mentioning
  # the tokens cannot self-allowlist.
  $unproven = [pscustomobject]@{ Ok = $false; Names = @() }
  if (-not (Test-Path $TrxPath)) { return $unproven }
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return $unproven }
  $names = @()
  $legacyCapability = @(
    'Low-level mouse hooks are unavailable on this host',
    'No printers enumerated in this context',
    'Default printer is hardware'
  )
  foreach ($r in @($t.TestRun.Results.UnitTestResult | Where-Object { $_.outcome -eq 'NotExecuted' })) {
    $msg = ''
    if ($r.Output -and $r.Output.ErrorInfo -and $r.Output.ErrorInfo.Message) { $msg = $r.Output.ErrorInfo.Message }
    if ($msg -cmatch 'QUARANTINED \d{4}-\d{2}-\d{2} \S+') { continue }
    if ($msg -clike 'CAPABILITY:*') { continue }
    $legacy = $false
    foreach ($frag in $legacyCapability) { if ($msg -clike "$frag*") { $legacy = $true; break } }
    if ($legacy) { continue }
    $names += $r.testName
  }
  return [pscustomobject]@{ Ok = $true; Names = $names }
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

function Get-LegSummary([string[]]$TrxPaths, [string[]]$LogPaths) {
  # Multi-file merge (D00 T02 §15, D00-T02-S13-R2-F2): Run A writes one
  # trx plus one out.log per test project, so every file merges here;
  # single-file legs pass one path each. Counts stay
  # transcript-authoritative when rows exist, else trx sums. Pass each
  # log once: a repeated path would double its rows.
  $trxs = @()
  foreach ($tp in $TrxPaths) {
    $one = Get-TrxSummary $tp
    if ($null -ne $one) { $trxs += $one }
  }
  # Out-of-process legs (D00 T02 §15 PR21) split their output: the
  # transcript carries script lines, the `.out.log` siblings carry the
  # suites' stdout. Every log parses; contents are disjoint by writer.
  $rows = @()
  $failNames = @()
  $skipNames = @()
  foreach ($lp in $LogPaths) {
    $rows += Get-TranscriptRows $lp
    $failNames += Get-TranscriptFailures $lp
    $skipNames += Get-TranscriptSkips $lp
    $outLog = [System.IO.Path]::ChangeExtension($lp, '.out.log')
    if (($outLog -ne $lp) -and (Test-Path $outLog)) {
      $rows += Get-TranscriptRows $outLog
      $failNames += Get-TranscriptFailures $outLog
      $skipNames += Get-TranscriptSkips $outLog
    }
  }
  if ($rows.Count -eq 0) {
    if ($trxs.Count -eq 0) { return $null }
    $mp = ($trxs | Measure-Object Passed -Sum).Sum
    $mf = ($trxs | Measure-Object FailedCount -Sum).Sum
    $ms = ($trxs | Measure-Object SkippedCount -Sum).Sum
    $mfail = @()
    $mskip = @()
    foreach ($t in $trxs) { $mfail += $t.Failed; $mskip += $t.Skipped }
    return [pscustomobject]@{ Passed = $mp; FailedCount = $mf; Failed = $mfail; Skipped = $mskip; SkippedCount = $ms }
  }
  $p = ($rows | Measure-Object Passed -Sum).Sum
  $f = ($rows | Measure-Object Failed -Sum).Sum
  $s = ($rows | Measure-Object Skipped -Sum).Sum
  $failLines = @()
  $trxNames = @()
  foreach ($t in $trxs) {
    $failLines += $t.Failed
    $trxNames += @($t.Failed | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  }
  foreach ($n in $failNames) {
    if ($trxNames -notcontains $n) { $failLines += "  - $n : see transcript" }
  }
  $skipLines = @()
  foreach ($t in $trxs) { $skipLines += $t.Skipped }
  $trxSkipNames = @($skipLines | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  foreach ($n in $skipNames) {
    if ($trxSkipNames -notcontains $n) { $skipLines += "  - $n : see transcript" }
  }
  $asm = ($rows | ForEach-Object { "$($_.Assembly) $($_.Passed)/$($_.Failed)/$($_.Skipped)" }) -join ', '
  return [pscustomobject]@{ Passed = $p; FailedCount = $f; Failed = $failLines; Skipped = $skipLines; SkippedCount = $s; Assemblies = $asm }
}

function Test-CountConservation([string]$Leg, [string[]]$TrxPaths, [string[]]$LogPaths, [bool]$EnforceExpected, [string[]]$RunAAssemblies) {
  # Total conservation (D00 T02 §15 PR23): started equals
  # passed-plus-failed-plus-skipped-plus-other at trx level, and every
  # assembly row's Total equals its Failed-plus-Passed-plus-Skipped. Any
  # exotic outcome fails closed (a silent new class is a break, not a
  # pass). Single-assembly legs cross-check trx against transcript, and
  # multi-trx legs (Run A, D00-T02-S13-R2-F2) cross-check the grand sums
  # once every listed trx parses (a killed step's missing trx skips the
  # aggregate: the leg is already unproven without it). Completed legs
  # fail closed on missing assemblies: every expected assembly must
  # report a row (an unknown leg name breaks rather than silently
  # skipping). The Run A set flows from the caller (single source: the
  # runner's project list, D00 T02 §15 R4-F3); Run B plus Interactive
  # are definitional UI-only singletons. Returns Ok plus Breaks; the
  # caller reds the run on any break.
  $breaks = @()
  $expectedSets = @{
    'Run A'       = $RunAAssemblies
    'Run B'       = @('UI.dll')
    'Interactive' = @('UI.dll')
  }
  $results = @()
  $trxParsed = 0
  foreach ($tp in $TrxPaths) {
    if (Test-Path $tp) {
      try { $results += @(([xml](Get-Content $tp -Raw)).TestRun.Results.UnitTestResult); $trxParsed++ } catch { }
    }
  }
  if ($results.Count -gt 0) {
    $exotic = @($results | Where-Object { (@('Passed', 'Failed', 'NotExecuted') -notcontains $_.outcome) })
    if ($exotic.Count -gt 0) {
      $kinds = @($exotic | ForEach-Object { $_.outcome } | Select-Object -Unique)
      $breaks += "$Leg trx: $($exotic.Count) exotic outcomes ($($kinds -join ',')); started=$($results.Count)"
    }
  }
  $rows = @()
  foreach ($lp in $LogPaths) {
    $rows += Get-TranscriptRows $lp
    $outLog = [System.IO.Path]::ChangeExtension($lp, '.out.log')
    if (($outLog -ne $lp) -and (Test-Path $outLog)) { $rows += Get-TranscriptRows $outLog }
  }
  foreach ($row in $rows) {
    if (($row.Failed + $row.Passed + $row.Skipped) -ne $row.Total) {
      $breaks += "$Leg $($row.Assembly): $($row.Failed)+$($row.Passed)+$($row.Skipped) != Total $($row.Total)"
    }
  }
  if (($rows.Count -eq 1) -and ($results.Count -gt 0)) {
    $tp = @($results | Where-Object { $_.outcome -eq 'Passed' }).Count
    $tf = @($results | Where-Object { $_.outcome -eq 'Failed' }).Count
    $ts = @($results | Where-Object { $_.outcome -eq 'NotExecuted' }).Count
    if (($tp -ne $rows[0].Passed) -or ($tf -ne $rows[0].Failed) -or ($ts -ne $rows[0].Skipped)) {
      $breaks += "$Leg cross-level: trx $tp/$tf/$ts vs transcript $($rows[0].Passed)/$($rows[0].Failed)/$($rows[0].Skipped)"
    }
  } elseif ((@($TrxPaths).Count -gt 1) -and ($trxParsed -eq @($TrxPaths).Count) -and ($rows.Count -gt 0) -and ($results.Count -gt 0)) {
    $ap = @($results | Where-Object { $_.outcome -eq 'Passed' }).Count
    $af = @($results | Where-Object { $_.outcome -eq 'Failed' }).Count
    $as = @($results | Where-Object { $_.outcome -eq 'NotExecuted' }).Count
    $rp = ($rows | Measure-Object Passed -Sum).Sum
    $rf = ($rows | Measure-Object Failed -Sum).Sum
    $rs = ($rows | Measure-Object Skipped -Sum).Sum
    if (($ap -ne $rp) -or ($af -ne $rf) -or ($as -ne $rs)) {
      $breaks += "$Leg cross-level-aggregate: trx $ap/$af/$as vs transcript $rp/$rf/$rs"
    }
  }
  if ($EnforceExpected) {
    if (-not $expectedSets.ContainsKey($Leg)) {
      $breaks += "$Leg expected-set: unknown leg (no assembly set defined)"
    } else {
      $present = @($rows | ForEach-Object { $_.Assembly })
      foreach ($want in $expectedSets[$Leg]) {
        if ($present -notcontains $want) { $breaks += "$Leg expected-set: $want missing from assembly rows" }
      }
    }
  }
  return [pscustomobject]@{ Ok = ($breaks.Count -eq 0); Breaks = $breaks }
}

function Test-SupervisorUnderLimit([string]$SupervisorPath, [string]$LimitText) {
  # Supervisor-versus-task pin (D00 T02 §15 R2-F5): the supervisor
  # default must precede the scheduled task's kill, or scheduled hangs
  # die silent with no tombstone. Reads the live default from the
  # supervisor script plus the live PT limit text; fails closed on any
  # unreadable input. Provision calls this inside the task leg.
  if (-not (Test-Path $SupervisorPath)) { return [pscustomobject]@{ Ok = $false; Detail = 'supervisor script missing' } }
  $m = [regex]::Match((Get-Content $SupervisorPath -Raw), '\[int\]\$TimeoutSeconds\s*=\s*(\d+)')
  if (-not $m.Success) { return [pscustomobject]@{ Ok = $false; Detail = 'supervisor default unreadable' } }
  $def = [int]$m.Groups[1].Value
  $lm = [regex]::Match($LimitText, '^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$')
  if (-not $lm.Success) { return [pscustomobject]@{ Ok = $false; Detail = "task limit unparseable: $LimitText" } }
  $lim = 0
  if ($lm.Groups[1].Success) { $lim += [int]$lm.Groups[1].Value * 3600 }
  if ($lm.Groups[2].Success) { $lim += [int]$lm.Groups[2].Value * 60 }
  if ($lm.Groups[3].Success) { $lim += [int]$lm.Groups[3].Value }
  if ($lim -le 0) { return [pscustomobject]@{ Ok = $false; Detail = "task limit non-positive: $LimitText" } }
  if ($def -ge $lim) { return [pscustomobject]@{ Ok = $false; Detail = "supervisor ${def}s not under task ${lim}s" } }
  return [pscustomobject]@{ Ok = $true; Detail = "supervisor ${def}s under task ${lim}s" }
}

function Format-SoakLedger([string]$TrxDir, [string[]]$Killed, [string[]]$Cut, [string[]]$Failed, [bool]$Ran, [string]$SkipReason = '') {
  # Fourth-phase soak verdict (D00 T02 §15 PR7): per-iteration rows keep
  # the §14 mark vocabulary (proved, killed at cap: unproven, budget-cut
  # unproven) and gain a FAILED mark plus an aggregate verdict line, so
  # a red soak cannot hide behind green legs. The verdict line carries
  # machine-readable counts for the §17 trend surface, plus the
  # truncation grade (D00 T02 §15, D00-T02-S14-PR12): minimum useful
  # coverage is 3 proved per suite, and every cut or killed range owes
  # triage a re-drive or an explicit carry. The minimum grades the red,
  # never softens it. Returns Rows plus a Failed flag the caller wires
  # into the run verdict.
  $rows = @()
  $names = @()
  foreach ($i in 1..5) { $names += "ui-soak-$i" }
  foreach ($i in 1..5) { $names += "protocol-soak-$i" }
  $proved = 0
  $uiProved = 0
  $protocolProved = 0
  $failedNames = @()
  $unproven = @()
  $failures = @()
  # -SkipSoak never executes an iteration: the empty shape prints only
  # here, never from an all-failed ledger (D00 T02 §15 R2-F6). Forced
  # skips name their reason instead of the flag (D00 T02 §15 R4-F6).
  if (-not $Ran) {
    if ($SkipReason -ne '') { return [pscustomobject]@{ Rows = @("(no soak iterations ran: $SkipReason)"); Failed = $false; Failures = @() } }
    return [pscustomobject]@{ Rows = @('(no soak iterations ran: -SkipSoak)'); Failed = $false; Failures = @() } }
  foreach ($n in $names) {
    $st = Get-TrxSummary (Join-Path $TrxDir "$n.trx")
    if ($null -eq $st) {
      $covered = $false
      foreach ($c in @($Cut)) {
        if ($c -eq $n) { $covered = $true; break }
        $cm = [regex]::Match($c, '^(ui-soak|protocol-soak)-(\d+)\.\.(\d+)$')
        $nm = [regex]::Match($n, '^(ui-soak|protocol-soak)-(\d+)$')
        if ($cm.Success -and $nm.Success -and ($cm.Groups[1].Value -eq $nm.Groups[1].Value) -and ([int]$nm.Groups[2].Value -ge [int]$cm.Groups[2].Value) -and ([int]$nm.Groups[2].Value -le [int]$cm.Groups[3].Value)) { $covered = $true; break }
      }
      if ($covered) { continue }
      if ($Killed -contains $n) { $unproven += $n; $rows += "- $n : no trx (killed at cap: unproven; owes triage: re-drive or carry)" }
      elseif ($Failed -contains $n) { $unproven += $n; $rows += "- $n : no trx (failed without trx: infrastructure failure, unproven; owes triage: re-drive or carry)" }
      else { $unproven += $n; $rows += "- $n : no trx despite exit 0 (logger failure suspected: unproven; owes triage: re-drive or carry)" }
      continue
    }
    if ($Killed -contains $n) { $unproven += $n; $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (killed at cap: unproven; owes triage: re-drive or carry)" }
    elseif (($Failed -contains $n) -and ($st.FailedCount -eq 0)) { $unproven += $n; $rows += "- $n : nonzero exit, trx carries no Failed outcomes (aborted host suspected: unproven; owes triage: re-drive or carry)" }
    elseif ($st.FailedCount -gt 0) {
      $failedNames += $n; $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (FAILED)"; $rows += $st.Failed
      foreach ($fl in $st.Failed) {
        $fm = [regex]::Match($fl, '^\s*-\s*([^:]+):\s*(.*)$')
        if ($fm.Success) { $failures += [pscustomobject]@{ Test = $fm.Groups[1].Value.Trim(); Message = $fm.Groups[2].Value.Trim(); Where = $n } }
      }
    }
    else {
      $proved++
      if ($n -like 'ui-soak-*') { $uiProved++ } else { $protocolProved++ }
      $rows += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped (proved)"
    }
  }
  foreach ($c in @($Cut | Where-Object { $_ -like '*soak-*' })) {
    $unproven += $c
    $rows += "- $c : budget-cut (unproven; owes triage: re-drive or carry)"
  }
  $bits = @()
  if ($failedNames.Count -gt 0) { $bits += "FAILED: $($failedNames -join ', ')" }
  if ($unproven.Count -gt 0) { $bits += "unproven: $($unproven -join ', ')" }
  if ($bits.Count -eq 0) { $verdict = "- Verdict: GREEN ($proved/10 iterations proved)" }
  else {
    $minMet = ($uiProved -ge 3) -and ($protocolProved -ge 3)
    $grade = if ($minMet) { "degraded (minimum 3+3 met: ui=$uiProved protocol=$protocolProved)" } else { "minimum MISSED (ui=$uiProved/3 protocol=$protocolProved/3; hunt void, full re-drive owed)" }
    $verdict = "- Verdict: RED ($($bits -join '; '); $grade; fails the run like a leg)"
  }
  return [pscustomobject]@{ Rows = (@($verdict) + $rows); Failed = ($bits.Count -gt 0); Failures = $failures }
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

function Test-QuarantineWindows([string]$LedgerPath, [datetime]$Today) {
  # Quarantine window enforcement (D00 T02 §15 PR30): rows in the
  # `## Quarantine list` table whose Due predates today are overdue;
  # the caller auto-fails the run with notification. Due defaults to
  # quarantined-plus-7-days (docs/soak-and-quarantine.md). An
  # unparseable Due fails closed (a typo must not silently extend a
  # window); the header rows skip by shape. Returns Overdue entries
  # plus the open count and earliest due for the clean line.
  $overdue = @()
  $open = 0
  $earliest = ''
  if (-not (Test-Path $LedgerPath)) { return [pscustomobject]@{ Overdue = $overdue; Open = $open; EarliestDue = $earliest } }
  $lines = @(Get-Content $LedgerPath)
  $inList = $false
  foreach ($ln in $lines) {
    if ($ln -match '^## ') { $inList = ($ln -eq '## Quarantine list') }
    if (-not $inList) { continue }
    if ($ln -notmatch '^\|') { continue }
    $cells = @($ln -split '\|')
    if ($cells.Count -lt 7) { continue }
    $dueText = $cells[-2].Trim()
    if (($dueText -eq 'Due') -or ($dueText -match '^-+$')) { continue }
    $test = $cells[1].Trim()
    $owner = $cells[-4].Trim()
    $open++
    $due = [datetime]::MinValue
    if (-not [datetime]::TryParse($dueText, [ref]$due)) {
      $overdue += [pscustomobject]@{ Test = $test; Due = $dueText; Owner = $owner; Malformed = $true }
      continue
    }
    $stamp = $due.ToString('yyyy-MM-dd')
    if (($earliest -eq '') -or ($stamp -lt $earliest)) { $earliest = $stamp }
    if ($due.Date -lt $Today.Date) {
      $overdue += [pscustomobject]@{ Test = $test; Due = $stamp; Owner = $owner; Malformed = $false }
    }
  }
  return [pscustomobject]@{ Overdue = $overdue; Open = $open; EarliestDue = $earliest }
}

function Invoke-FailureCapture([string]$Leg, [string]$CaptureDir, [bool]$Killed) {
  # Best-effort failure capture (D00 T02 §15 PR13): screenshot, window
  # metadata, and the failing window's event slice land beside any
  # pre-kill dumps. Killed legs carry dumps (JobControl --dump); failed
  # legs exited before capture, so dumps read n/a. Never throws: each
  # capture is independent and failures record as notes. Returns notes.
  $notes = @()
  try { $null = New-Item -ItemType Directory -Force -Path $CaptureDir } catch { return @("- $Leg : capture dir failed: $($_.Exception.Message)") }
  $shot = Join-Path $CaptureDir "$Leg-failure.png"
  try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    try {
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      try { $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size) } finally { $g.Dispose() }
      $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
      $notes += "- $Leg : screenshot $Leg-failure.png"
    } finally { $bmp.Dispose() }
  } catch { $notes += "- $Leg : screenshot failed: $($_.Exception.Message)" }
  $wins = Join-Path $CaptureDir "$Leg-windows.txt"
  try {
    Get-Process -ErrorAction Stop | Where-Object { $_.MainWindowTitle -ne '' } | ForEach-Object { "pid=$($_.Id) $($_.ProcessName): $($_.MainWindowTitle)" } | Set-Content -Path $wins -Encoding UTF8
    $notes += "- $Leg : window metadata $Leg-windows.txt"
  } catch { $notes += "- $Leg : window list failed: $($_.Exception.Message)" }
  $evts = Join-Path $CaptureDir "$Leg-events.txt"
  try {
    $since = (Get-Date).AddMinutes(-10)
    $rows = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = 1, 2, 3 } -MaxEvents 100 -ErrorAction Stop | ForEach-Object {
      $msg = $_.Message
      if ($null -eq $msg) { $msg = '' }
      $head = ($msg -split "`r?`n")[0]
      if ($head.Length -gt 200) { $head = $head.Substring(0, 200) }
      "$($_.TimeCreated.ToString('HH:mm:ss')) id=$($_.Id) $($_.LevelDisplayName) $($_.ProviderName): $head"
    })
    if ($rows.Count -eq 0) { $rows = @('(no Application errors/warnings in the last 10 minutes)') }
    $rows | Set-Content -Path $evts -Encoding UTF8
    $notes += "- $Leg : event slice $Leg-events.txt ($($rows.Count) rows)"
  } catch {
    if ($_.Exception.Message -like '*No events were found*') {
      @('(no Application errors/warnings in the last 10 minutes)') | Set-Content -Path $evts -Encoding UTF8
      $notes += "- $Leg : event slice $Leg-events.txt (0 rows)"
    } else {
      $notes += "- $Leg : event slice failed: $($_.Exception.Message)"
    }
  }
  if (-not $Killed) { $notes += "- $Leg : no dump (process exited before capture)" }
  return $notes
}

function Invoke-BoundedTeardown($Job, [int]$BoundSeconds, [string]$What) {
  # Abandon-when-hung teardown (D00 T02 §15 R3-F2): the leg tree is
  # already dead (the job kill precedes teardown), so a stuck reap
  # abandons its handles (the OS reaps at process exit) and the run
  # continues to publication. The removal itself rides a nested job so
  # even a wedged Remove-Job cannot block past its bound; only the
  # final reap of an already-completed remover is synchronous (a fully
  # wedged runspace is the documented residual, owned by the §15
  # outer-supervisor item). Returns $true when reaped, $false when
  # abandoned.
  $done = Wait-Job -Job $Job -Timeout $BoundSeconds
  if ($null -eq $done) {
    Write-Warning "nightly: teardown of $What abandoned after ${BoundSeconds}s (handles leak to process exit; tree already dead)"
    return $false
  }
  try { Receive-Job -Job $Job -ErrorAction SilentlyContinue | Out-Null } catch { }
  $remover = Start-Job -ScriptBlock { param($id) Get-Job -Id $id -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue } -ArgumentList @($Job.Id)
  $reaped = Wait-Job -Job $remover -Timeout 30
  if ($null -eq $reaped) {
    Write-Warning "nightly: removal of $What wedged; abandoning both handles"
    return $false
  }
  Remove-Job -Job $remover -Force
  return $true
}

function Test-PrimaryPlacement([string]$TestsRoot) {
  # Suite-wide Primary guard (D00 T02 §15, D00-T02-S13-R3-F1): no
  # governed leg runs a Category=Primary test outside tests/UI (Run A
  # excludes Primary solution-wide, Run B scopes to tests/UI), so a
  # Primary trait anywhere else fails closed. A source scan, not
  # reflection, so future test projects are covered without growing
  # their own guard. Each file scans whole: comments strip per line,
  # then the text joins and the pattern spans newlines, so a trait
  # split across lines still matches with its start line computed from
  # the match offset (D00 T02 §15 R2-F3); a trait inside a block
  # comment still matches (fail closed, triage quotes the hit).
  # Returns Ok plus Strays (root-relative path:line) plus the tests/UI
  # mention count.
  $strays = @()
  $uiCount = 0
  if (-not (Test-Path $TestsRoot)) { return [pscustomobject]@{ Ok = $false; Strays = @('(tests root missing: ' + $TestsRoot + ')'); UiCount = 0 } }
  $uiRoot = Join-Path $TestsRoot 'UI'
  foreach ($f in (Get-ChildItem -Path $TestsRoot -Recurse -Filter '*.cs' -File)) {
    $rel = $f.FullName.Substring($TestsRoot.Length).TrimStart('\', '/')
    $underUi = $f.FullName.StartsWith($uiRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    $text = ((Get-Content $f.FullName) | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
    foreach ($m in [regex]::Matches($text, 'Trait\s*\(\s*"Category"\s*,\s*"Primary"\s*\)')) {
      $lineNo = (@($text.Substring(0, $m.Index) -split "`n").Count)
      if ($underUi) { $uiCount++ }
      else { $strays += ("$rel" + ':' + $lineNo) }
    }
  }
  return [pscustomobject]@{ Ok = ($strays.Count -eq 0); Strays = $strays; UiCount = $uiCount }
}

function Get-NightlyFilterLiterals([string]$NightlyPath) {
  # Every '--filter', '<literal>' test-selection literal in the governed
  # script, in file order, plus the $collectFilter default (D00 T02 §15,
  # D00-T02-S13-PR13). Comment lines never carry those shapes, so prose
  # quotes cannot collide. Returns Literals plus CollectDefault.
  $lits = @()
  $collect = ''
  if (-not (Test-Path $NightlyPath)) { return [pscustomobject]@{ Literals = $lits; CollectDefault = $collect } }
  foreach ($ln in (Get-Content $NightlyPath)) {
    $m = [regex]::Match($ln, "--filter',\s*'(Category[^']+)'")
    if ($m.Success) { $lits += $m.Groups[1].Value }
    $c = [regex]::Match($ln, '\$collectFilter\s*=\s*''(Category[^'']+)''')
    if ($c.Success) { $collect = $c.Groups[1].Value }
  }
  return [pscustomobject]@{ Literals = $lits; CollectDefault = $collect }
}

function Read-TestPopulationFile([string]$Path) {
  # Strict reader for tests/UI/TestPopulation.fingerprint (D00 T02 §15,
  # D00-T02-S13-PR13): filters, sorted member FQNs, and method plus
  # case counts per leg. Malformed input fails closed (Ok false with
  # the cause); item counts must equal their method counts.
  $bad = { param($why) return [pscustomobject]@{ Ok = $false; Error = $why } }
  if (-not (Test-Path $Path)) { return (& $bad "fingerprint missing: $Path") }
  $filters = @{}
  $counts = @{}
  $runA = @()
  $runB = @()
  $interactive = @()
  $section = ''
  foreach ($raw in (Get-Content $Path)) {
    $ln = $raw.Trim()
    if (($ln -eq '') -or $ln.StartsWith('#')) { continue }
    if ($ln -eq 'run-a:') { $section = 'run-a'; continue }
    if ($ln -eq 'run-b:') { $section = 'run-b'; continue }
    if ($ln -eq 'interactive:') { $section = 'interactive'; continue }
    $kv = [regex]::Match($ln, '^([a-z-]+):\s*(.+)$')
    if ($kv.Success -and ($raw -notmatch '^\s')) {
      $section = ''
      $filters[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim()
      continue
    }
    if (($section -eq 'run-a') -and ($raw -match '^  \S')) { $runA += $ln; continue }
    if (($section -eq 'run-b') -and ($raw -match '^  \S')) { $runB += $ln; continue }
    if (($section -eq 'interactive') -and ($raw -match '^  \S')) { $interactive += $ln; continue }
    return (& $bad "fingerprint malformed line: $raw")
  }
  foreach ($k in @('run-a-filter', 'run-b-filter', 'interactive-filter')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
  }
  foreach ($k in @('run-a-methods', 'run-a-cases', 'run-b-methods', 'run-b-cases', 'interactive-methods', 'interactive-cases')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
    $n = 0
    if (-not [int]::TryParse($filters[$k], [ref]$n)) { return (& $bad "fingerprint bad count ${k}: $($filters[$k])") }
    $counts[$k] = $n
  }
  if ($runA.Count -ne $counts['run-a-methods']) { return (& $bad "fingerprint run-a items $($runA.Count) != methods $($counts['run-a-methods'])") }
  if ($runB.Count -ne $counts['run-b-methods']) { return (& $bad "fingerprint run-b items $($runB.Count) != methods $($counts['run-b-methods'])") }
  if ($interactive.Count -ne $counts['interactive-methods']) { return (& $bad "fingerprint interactive items $($interactive.Count) != methods $($counts['interactive-methods'])") }
  return [pscustomobject]@{ Ok = $true; Error = ''; RunA = $runA; RunAFilter = $filters['run-a-filter']; RunBFilter = $filters['run-b-filter']; InteractiveFilter = $filters['interactive-filter']; RunB = $runB; Interactive = $interactive; RunAMethods = $counts['run-a-methods']; RunACases = $counts['run-a-cases']; RunBMethods = $counts['run-b-methods']; RunBCases = $counts['run-b-cases']; InteractiveMethods = $counts['interactive-methods']; InteractiveCases = $counts['interactive-cases'] }
}

function Write-TestPopulationFile([string]$Path, [string]$RunAFilter, [string]$RunBFilter, [string]$InteractiveFilter, $Discovery) {
  # Canonical writer for the fingerprint (D00 T02 §15, D00-T02-S13-PR13):
  # filters, sorted unique member FQNs, method plus case counts. Atomic
  # via same-volume rename; $Discovery carries RunA/RunB/Interactive
  # method lists plus the six counts. The header § emits by code point:
  # Windows PowerShell reads BOM-less scripts as ANSI, so a literal §
  # double-encodes on write (D00 T02 §15 R2-F7).
  $lines = @(
    "# Nightly UI test population fingerprint (D00 T02 $([char]0xA7)15, D00-T02-S13-PR13).",
    '# One --list-tests discovery per leg filter; member FQNs sorted unique.',
    '# Regen: tools/Update-TestFingerprint.ps1 (build first). Review the diff:',
    '# every membership change stales prior proofs until re-accepted here.',
    "run-a-filter: $RunAFilter",
    "run-b-filter: $RunBFilter",
    "interactive-filter: $InteractiveFilter",
    'run-a:'
  )
  foreach ($m in (@($Discovery.RunA) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-a-methods: $($Discovery.RunAMethods)"
  $lines += "run-a-cases: $($Discovery.RunACases)"
  $lines += 'run-b:'
  foreach ($m in (@($Discovery.RunB) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-b-methods: $($Discovery.RunBMethods)"
  $lines += "run-b-cases: $($Discovery.RunBCases)"
  $lines += 'interactive:'
  foreach ($m in (@($Discovery.Interactive) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "interactive-methods: $($Discovery.InteractiveMethods)"
  $lines += "interactive-cases: $($Discovery.InteractiveCases)"
  $tmp = "$Path.tmp"
  $lines -join "`r`n" | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
}

function Compare-TestPopulation([string]$FingerprintPath, [string]$NightlyPath, $Discovery) {
  # Fingerprint comparison (D00 T02 §15, D00-T02-S13-PR13): the file's
  # Run A plus Run B filters must each appear exactly once among the
  # governed script's literals (a filter edit stales the acceptance),
  # the collection default must match, and live discovery must equal
  # the accepted members plus counts. Any drift reds with names;
  # malformed input fails closed. Returns Ok plus Drifts.
  $drifts = @()
  $fp = Read-TestPopulationFile $FingerprintPath
  if (-not $fp.Ok) { return [pscustomobject]@{ Ok = $false; Drifts = @($fp.Error) } }
  $live = Get-NightlyFilterLiterals $NightlyPath
  foreach ($want in @($fp.RunAFilter, $fp.RunBFilter)) {
    $hits = @($live.Literals | Where-Object { $_ -eq $want }).Count
    if ($hits -ne 1) { $drifts += "filter '$want' appears $hits times in nightly.ps1 (want exactly once)" }
  }
  if ($live.CollectDefault -ne $fp.InteractiveFilter) { $drifts += "collection default '$($live.CollectDefault)' != fingerprinted '$($fp.InteractiveFilter)'" }
  foreach ($leg in @(@('run-a', $fp.RunA, $Discovery.RunA), @('run-b', $fp.RunB, $Discovery.RunB), @('interactive', $fp.Interactive, $Discovery.Interactive))) {
    $added = @(Compare-Object $leg[1] $leg[2] | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
    $removed = @(Compare-Object $leg[1] $leg[2] | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })
    foreach ($a in ($added | Select-Object -First 5)) { $drifts += "$($leg[0]) added: $a" }
    if ($added.Count -gt 5) { $drifts += "$($leg[0]) added: ... ($($added.Count) total)" }
    foreach ($r in ($removed | Select-Object -First 5)) { $drifts += "$($leg[0]) removed: $r" }
    if ($removed.Count -gt 5) { $drifts += "$($leg[0]) removed: ... ($($removed.Count) total)" }
  }
  $pairs = @( @('run-a-methods', $fp.RunAMethods, $Discovery.RunAMethods), @('run-a-cases', $fp.RunACases, $Discovery.RunACases), @('run-b-cases', $fp.RunBCases, $Discovery.RunBCases), @('interactive-cases', $fp.InteractiveCases, $Discovery.InteractiveCases) )
  foreach ($p in $pairs) {
    if ($p[1] -ne $p[2]) { $drifts += "$($p[0]): fingerprinted $($p[1]) vs discovered $($p[2])" }
  }
  if ($Discovery.RunAMethods -ne @($Discovery.RunA).Count) { $drifts += 'discovery run-a method list disagrees with its count (internal error)' }
  if ($Discovery.RunBMethods -ne @($Discovery.RunB).Count) { $drifts += 'discovery run-b method list disagrees with its count (internal error)' }
  if ($Discovery.InteractiveMethods -ne @($Discovery.Interactive).Count) { $drifts += 'discovery interactive method list disagrees with its count (internal error)' }
  return [pscustomobject]@{ Ok = ($drifts.Count -eq 0); Drifts = $drifts }
}

function Invoke-BoundedCapture([string]$Exe, [string[]]$ArgList, [string]$WorkDir, [int]$TimeoutSeconds) {
  # Bounded toolchain capture (D00 T02 §15 R3-F3): runs $Exe with a
  # wall cap and returns its stdout plus exit code; a hang kills the
  # job and reports Killed, so no toolchain invocation strands the run
  # past its deadline. Same job shape as Invoke-BootstrapStep, plus
  # captured output and a code file for the exit relay.
  $codeFile = Join-Path ([System.IO.Path]::GetTempPath()) ("bounded-$([Guid]::NewGuid().ToString('N')).code")
  $capJob = Start-Job -ScriptBlock {
    param($exe, $argList, $dir, $codeOut)
    Set-Location $dir
    $out = & $exe @argList 2>&1 | Out-String
    $LASTEXITCODE | Set-Content -Path $codeOut
    $out
  } -ArgumentList @($Exe, $ArgList, $WorkDir, $codeFile)
  $doneSignal = Wait-Job -Job $capJob -Timeout $TimeoutSeconds
  $killed = ($null -eq $doneSignal)
  if ($killed -and ($capJob.State -eq 'Running')) { Stop-Job -Job $capJob }
  $null = Wait-Job -Job $capJob -Timeout 60
  $text = ''
  try { $text = Receive-Job -Job $capJob | Out-String } catch { $text = "bounded capture receive failed: $($_.Exception.Message)" }
  Remove-Job -Job $capJob -Force
  $code = 1
  if (Test-Path $codeFile) {
    $rawCode = Get-Content $codeFile -Raw
    if (($null -eq $rawCode) -or ($rawCode.Trim() -eq '')) { $code = 0 } else { $code = [int]$rawCode.Trim() }
    Remove-Item $codeFile -Force
  }
  if ($killed) { $code = 1 }
  return [pscustomobject]@{ Text = $text; Code = $code; Killed = $killed }
}

function Get-ListTestsCases([string]$Dotnet, [string]$Csproj, [string]$Filter, [string]$What, [int]$TimeoutSeconds = 180) {
  # One --list-tests run against built binaries, parsed to sorted
  # unique method FQNs (theory case suffixes cut at the first paren)
  # with method plus case counts. Shared by population discovery
  # (PR13) and cut-work handoff (PR10). Bounded (D00 T02 §15 R3-F3): a
  # hang throws like a failure, so hung discovery cannot strand the run
  # past its deadline. Failure throws with $What naming the caller;
  # callers report on their red path.
  $cap = Invoke-BoundedCapture $Dotnet @('test', $Csproj, '--no-build', '--nologo', '--filter', $Filter, '--list-tests') (Split-Path -Parent $Csproj) $TimeoutSeconds
  if ($cap.Killed) { throw "discovery timed out for $What filter '$Filter' after ${TimeoutSeconds}s" }
  $text = $cap.Text
  if ($cap.Code -ne 0) { throw "discovery failed for $What filter '$Filter': $text" }
  $methods = @()
  $cases = 0
  foreach ($ln in ($text -split "`r?`n")) {
    $m = [regex]::Match($ln, '^    (\S[^(]*?)(?: \(|\(|$)')
    if (-not $m.Success) { continue }
    $cases++
    $fq = $m.Groups[1].Value.Trim()
    if ($methods -notcontains $fq) { $methods += $fq }
  }
  $methods = @($methods | Sort-Object -Unique)
  return [pscustomobject]@{ Methods = $methods; MethodCount = $methods.Count; CaseCount = $cases }
}

function Get-UiTestDiscovery([string]$Dotnet, [string]$UiCsproj, [string]$RunAFilter, [string]$RunBFilter, [string]$InteractiveFilter) {
  # Live discovery (D00 T02 §15, D00-T02-S13-PR13): one --list-tests run
  # per leg filter against the built UI binaries. Discovery failure
  # throws: an unverifiable population is a broken run, and the caller
  # reports it on the red path (never as governed green).
  $out = [pscustomobject]@{ RunA = @(); RunB = @(); Interactive = @(); RunAMethods = 0; RunACases = 0; RunBMethods = 0; RunBCases = 0; InteractiveMethods = 0; InteractiveCases = 0 }
  $legs = @(@('RunA', $RunAFilter), @('RunB', $RunBFilter), @('Interactive', $InteractiveFilter))
  foreach ($leg in $legs) {
    $one = Get-ListTestsCases $Dotnet $UiCsproj $leg[1] $leg[0]
    $out.($leg[0]) = $one.Methods
    $out.($leg[0] + 'Methods') = $one.MethodCount
    $out.($leg[0] + 'Cases') = $one.CaseCount
  }
  return $out
}

function Test-FilterPartition([string]$RunAFilter, [string]$RunBFilter, $Members) {
  # Deterministic filter-partition check (D00 T02 §15, D00-T02-S13-PR17):
  # Primary members must be absent from the Run A selection and present
  # in the Run B selection, and Interactive members must be absent from
  # Run A. Evaluates the &-of-Category-clauses sculpt vstest applies
  # (=, !=; any other clause fails closed as unsupported). $Members
  # entries carry Name plus Categories. Returns violations (empty is
  # green). A both-traits member passes here (excluded from Run A by
  # its Interactive trait, selected by Run B for its Primary one);
  # leg-uniqueness is the in-suite partition check's job (PR11).
  $violations = @()
  $select = {
    param($Filter, $Who)
    $picked = @()
    foreach ($clause in ($Filter -split '&')) {
      # Values stay bare words: any other vstest operator (|, ~,
      # parens) hiding in the value fails closed as unsupported,
      # never evaluates as a never-matching category.
      $m = [regex]::Match($clause.Trim(), '^Category(!?=)([\w.]+)$')
      if (-not $m.Success) { return [pscustomobject]@{ Picked = @(); Error = "unsupported clause in ${Who}: $($clause.Trim())" } }
    }
    foreach ($mb in $Members) {
      $in = $true
      foreach ($clause in ($Filter -split '&')) {
        $m = [regex]::Match($clause.Trim(), '^Category(!?=)([\w.]+)$')
        $want = $m.Groups[2].Value.Trim()
        $has = @($mb.Categories) -contains $want
        if ((($m.Groups[1].Value -eq '=') -and (-not $has)) -or (($m.Groups[1].Value -eq '!=') -and $has)) { $in = $false; break }
      }
      if ($in) { $picked += $mb.Name }
    }
    return [pscustomobject]@{ Picked = $picked; Error = '' }
  }
  $selA = &$select $RunAFilter 'run-a'
  if ($selA.Error -ne '') { $violations += $selA.Error }
  $selB = &$select $RunBFilter 'run-b'
  if ($selB.Error -ne '') { $violations += $selB.Error }
  $inA = @($selA.Picked)
  $inB = @($selB.Picked)
  # An errored selection is already a violation; its membership reads
  # empty, so skip the membership checks to avoid artifact doubles.
  if (($selA.Error -eq '') -and ($selB.Error -eq '')) {
    foreach ($mb in $Members) {
      $isPrimary = @($mb.Categories) -contains 'Primary'
      $isInteractive = @($mb.Categories) -contains 'Interactive'
      if ($isPrimary -and ($inA -contains $mb.Name)) { $violations += "run-a selects primary: $($mb.Name)" }
      if ($isInteractive -and ($inA -contains $mb.Name)) { $violations += "run-a selects interactive: $($mb.Name)" }
      if ($isPrimary -and ($inB -notcontains $mb.Name)) { $violations += "run-b misses primary: $($mb.Name)" }
    }
  }
  return $violations
}

function Get-StringHash([string]$Text) {
  # First 8 hex of SHA256 over UTF8 text (D00 T02 §15 PR31 incident IDs).
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 8).ToLower()
  } finally { $sha.Dispose() }
}

function Format-Incidents($Failures) {
  # Stable incident IDs (D00 T02 §15 PR31): repeated failures dedupe
  # by test plus normalized message shape (digit runs collapse, so
  # "expected 2" and "expected 3" share the incident), keeping every
  # occurrence. IDs derive from content, so the same failure keeps its
  # ID across nights for recurrence tracking. $Failures entries carry
  # Test, Message, Where. Returns report lines, busiest first.
  $groups = @{}
  $order = @()
  foreach ($f in $Failures) {
    $shape = ("$($f.Message)" -replace '\d+', '#')
    $shape = ($shape -replace '\s+', ' ').Trim()
    if ($shape.Length -gt 120) { $shape = $shape.Substring(0, 120) }
    $key = "$($f.Test)::$shape"
    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = [pscustomobject]@{ Id = "INC-$(Get-StringHash $key)"; Test = $f.Test; Message = $f.Message; Wheres = @() }
      $order += $key
    }
    $groups[$key].Wheres += $f.Where
  }
  $lines = @()
  foreach ($key in ($order | Sort-Object { -$groups[$_].Wheres.Count })) {
    $g = $groups[$key]
    $msg = $g.Message
    if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
    $lines += "- $($g.Id) ``$($g.Test)`` x$($g.Wheres.Count) ($($g.Wheres -join ', ')): $msg"
  }
  return $lines
}

function Write-AtomicReport([string[]]$Lines, [string]$Path) {
  # Same-volume rename is atomic on NTFS: a kill between the write and
  # the rename leaves the previous report, never a truncation. Shared
  # by the governed run and the outer supervisor (D00 T02 §15 PR1).
  $tmp = "$Path.tmp"
  $Lines -join "`r`n" | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
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

function Format-EnforcementVerdict([bool]$Ran, [string[]]$Leaked, [bool]$Classified) {
  # Enforcement verdict, separate from test, gate, and infrastructure
  # (D00 T02 §15 PR8): the Interactive allowlist decides quarantine
  # plus capability; anything else names names. An unclassifiable leg
  # (missing or malformed trx) is unproven, never green (D00 T02 §15
  # R2-F1); the caller reds the run.
  if (-not $Ran) { return '- Interactive (collection): n/a (leg did not run)' }
  if (-not $Classified) { return '- Interactive (collection): UNPROVEN (trx missing or malformed: no skip classification)' }
  if ($Leaked.Count -gt 0) { return "- Interactive (collection): RED ($($Leaked.Count) non-quarantine skips: $($Leaked -join ', '))" }
  return '- Interactive (collection): GREEN (every skip quarantined or capability)'
}
