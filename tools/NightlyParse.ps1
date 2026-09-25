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
  # Structured failures for the incident identity contract (D00 T02
  # §22 item 3): the whole message plus the stack feed the failure
  # class, HRESULT, and stack-signature parts of the key.
  $failDetail = @($failed | ForEach-Object {
    $msg = ''
    $stack = ''
    if ($_.Output -and $_.Output.ErrorInfo) {
      if ($_.Output.ErrorInfo.Message) { $msg = "$($_.Output.ErrorInfo.Message)" }
      if ($_.Output.ErrorInfo.StackTrace) { $stack = "$($_.Output.ErrorInfo.StackTrace)" }
    }
    [pscustomobject]@{ Test = "$($_.testName)"; Message = $msg; Stack = $stack }
  })
  $passedNames = @($results | Where-Object { $_.outcome -eq 'Passed' } | ForEach-Object { "$($_.testName)" })
  return [pscustomobject]@{ Passed = $passed; FailedCount = $failed.Count; Failed = $failLines; Skipped = $skipLines; SkippedCount = $skipped.Count; FailedDetail = $failDetail; PassedNames = $passedNames }
}

function Get-TranscriptRows([string]$LogPath) {
  # VSTest assembly summary lines. The transcript is the authoritative
  # per-leg count; each project's trx carries its failure messages plus
  # skip reasons (D00 T02 §15, D00-T02-S13-R2-F2: per-project trx files
  # replaced the shared solution-level name every project overwrote).
  $rows = @()
  if (-not (Test-Path $LogPath)) { return $rows }
  foreach ($ln in (Get-Content $LogPath)) {
    # All three VSTest banners: an entirely skipped assembly prints
    # `Skipped! - Failed: 0, Passed: 0, Skipped: N` (D00 T02 §22 item 4,
    # observed on SDK 10.0.400), and dropping it would vanish the
    # assembly from conservation and the leg cell.
    $m = [regex]::Match($ln, '(Passed!|Failed!|Skipped!)\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+),.*-\s*(\S+)\s*\(net')
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
    $mdetail = @()
    $mpassed = @()
    foreach ($t in $trxs) { $mfail += $t.Failed; $mskip += $t.Skipped; $mdetail += @($t.FailedDetail); $mpassed += @($t.PassedNames) }
    return [pscustomobject]@{ Passed = $mp; FailedCount = $mf; Failed = $mfail; Skipped = $mskip; SkippedCount = $ms; FailedDetail = $mdetail; PassedNames = $mpassed }
  }
  $p = ($rows | Measure-Object Passed -Sum).Sum
  $f = ($rows | Measure-Object Failed -Sum).Sum
  $s = ($rows | Measure-Object Skipped -Sum).Sum
  $failLines = @()
  $trxNames = @()
  $failDetail = @()
  $passedNames = @()
  foreach ($t in $trxs) {
    $failLines += $t.Failed
    $trxNames += @($t.Failed | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
    $failDetail += @($t.FailedDetail)
    $passedNames += @($t.PassedNames)
  }
  foreach ($n in $failNames) {
    if ($trxNames -notcontains $n) {
      $failLines += "  - $n : see transcript"
      $failDetail += [pscustomobject]@{ Test = $n; Message = 'see transcript'; Stack = '' }
    }
  }
  $skipLines = @()
  foreach ($t in $trxs) { $skipLines += $t.Skipped }
  $trxSkipNames = @($skipLines | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  foreach ($n in $skipNames) {
    if ($trxSkipNames -notcontains $n) { $skipLines += "  - $n : see transcript" }
  }
  $asm = ($rows | ForEach-Object { "$($_.Assembly) $($_.Passed)/$($_.Failed)/$($_.Skipped)" }) -join ', '
  return [pscustomobject]@{ Passed = $p; FailedCount = $f; Failed = $failLines; Skipped = $skipLines; SkippedCount = $s; Assemblies = $asm; FailedDetail = $failDetail; PassedNames = $passedNames }
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
  # Passed test names per suite family feed incident recovery (D00 T02
  # §22 item 6): only proved or FAILED iterations count, never killed
  # or cut ones, whose trx proves nothing.
  $passedByFamily = @{ 'ui-soak' = @(); 'protocol-soak' = @() }
  # -SkipSoak never executes an iteration: the empty shape prints only
  # here, never from an all-failed ledger (D00 T02 §15 R2-F6). Forced
  # skips name their reason instead of the flag (D00 T02 §15 R4-F6).
  if (-not $Ran) {
    if ($SkipReason -ne '') { return [pscustomobject]@{ Rows = @("(no soak iterations ran: $SkipReason)"); Failed = $false; Failures = @(); PassedByFamily = $passedByFamily } }
    return [pscustomobject]@{ Rows = @('(no soak iterations ran: -SkipSoak)'); Failed = $false; Failures = @(); PassedByFamily = $passedByFamily } }
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
      foreach ($fd in @($st.FailedDetail)) { $failures += [pscustomobject]@{ Test = $fd.Test; Message = $fd.Message; Where = $n; Stack = $fd.Stack } }
      $family = $n -replace '-\d+$', ''
      $passedByFamily[$family] = @($passedByFamily[$family]) + @($st.PassedNames)
    }
    else {
      $proved++
      $family = $n -replace '-\d+$', ''
      $passedByFamily[$family] = @($passedByFamily[$family]) + @($st.PassedNames)
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
  return [pscustomobject]@{ Rows = (@($verdict) + $rows); Failed = ($bits.Count -gt 0); Failures = $failures; PassedByFamily = $passedByFamily }
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
  # plus the open count, earliest due, and open rows (D00 T02 §17
  # item 5: due-soon derivation) for the clean line.
  $overdue = @()
  $open = 0
  $earliest = ''
  $rows = @()
  if (-not (Test-Path $LedgerPath)) { return [pscustomobject]@{ Overdue = $overdue; Open = $open; EarliestDue = $earliest; OpenRows = $rows } }
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
      $rows += [pscustomobject]@{ Test = $test; Due = $dueText; Owner = $owner; Malformed = $true }
      continue
    }
    $stamp = $due.ToString('yyyy-MM-dd')
    if (($earliest -eq '') -or ($stamp -lt $earliest)) { $earliest = $stamp }
    if ($due.Date -lt $Today.Date) {
      $overdue += [pscustomobject]@{ Test = $test; Due = $stamp; Owner = $owner; Malformed = $false }
    }
    $rows += [pscustomobject]@{ Test = $test; Due = $stamp; Owner = $owner; Malformed = $false }
  }
  return [pscustomobject]@{ Overdue = $overdue; Open = $open; EarliestDue = $earliest; OpenRows = $rows }
}

function Get-DueSoonTests($OpenRows, [datetime]$Today, [int]$Days = 3) {
  # Names open windows due within Days (D00 T02 §17 item 5): the
  # morning surface warns before the window lapses. Malformed and
  # already-overdue rows never count as due-soon.
  $out = @()
  foreach ($r in @($OpenRows)) {
    $bad = $false
    try { $bad = [bool]$r.Malformed } catch { }
    if ($bad) { continue }
    $due = [datetime]::MinValue
    if (-not [datetime]::TryParse("$($r.Due)", [ref]$due)) { continue }
    $d = ($due.Date - $Today.Date).TotalDays
    if (($d -ge 0) -and ($d -le $Days)) { $out += "$($r.Test)" }
  }
  return @($out | Sort-Object -Unique)
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
    $owned = @{}
    try { $owned = Get-DescendantPids @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; ParentProcessId = [int]$_.ParentProcessId; Created = $_.CreationDate } }) $PID } catch { $owned = @{} }
    $winRows = @(Get-Process -ErrorAction Stop | Where-Object { $_.MainWindowTitle -ne '' } | ForEach-Object { Format-WindowRow $_.Id $_.ProcessName $_.MainWindowTitle ($owned.ContainsKey([int]$_.Id)) })
    $notes += @(Publish-TextCapture $CaptureDir (Split-Path -Leaf $wins) $winRows $Leg)
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
    $notes += @(Publish-TextCapture $CaptureDir (Split-Path -Leaf $evts) $rows $Leg)
    $notes += "- $Leg : event slice $Leg-events.txt ($($rows.Count) rows)"
  } catch {
    if ($_.Exception.Message -like '*No events were found*') {
      $notes += @(Publish-TextCapture $CaptureDir (Split-Path -Leaf $evts) @('(no Application errors/warnings in the last 10 minutes)') $Leg)
      $notes += "- $Leg : event slice $Leg-events.txt (0 rows)"
    } else {
      $notes += "- $Leg : event slice failed: $($_.Exception.Message)"
    }
  }
  if (-not $Killed) { $notes += "- $Leg : no dump (process exited before capture)" }
  $notes += @(Protect-CaptureDir $CaptureDir $Leg)
  return $notes
}

# Failure-capture policy (D00 T02 §22 item 1, D00-T02-S15-PR21;
# docs/testing.md "Failure-capture policy"): captures never leave the
# machine, window titles of processes the run does not own are
# redacted at write, every text capture is secret-scanned and redacted
# on a hit, and a capture directory over its size cap drops its
# screenshots. Retention follows the run evidence (30 days, prune).
# Incident lifecycle defaults (D00 T02 section 30 items 5, 6): the
# triage owner and escalation window for incidents no quarantine row
# owns, and the stamp where incident identity contract v2 began.
$script:TriageOwner = 'operator'
$script:TriageDays = 2
$script:IncidentContractV2Since = '2026-09-25-000000'
$script:CaptureOwnedProcesses = @('ScratchPad', 'testhost', 'ForegroundLog', 'JobControl')
$script:CaptureMaxBytes = 25MB
$script:CaptureFailMarker = 'SECRET-SCAN-FAILED.txt'
$script:CaptureStagingDir = '.staging'
$script:CaptureBudgetMarker = 'CAPTURE-BUDGET-TRUNCATED.txt'
$script:RunCaptureMaxBytes = 200MB
$script:SecretPatterns = @(
  @('github-token', 'gh[pousr]_[A-Za-z0-9]{36,}'),
  @('github-pat', 'github_pat_[A-Za-z0-9_]{22,}'),
  @('anthropic-key', 'sk-ant-[A-Za-z0-9_-]{20,}'),
  @('openai-key', 'sk-(?:proj-)?[A-Za-z0-9_-]{32,}'),
  @('aws-access-key', 'AKIA[0-9A-Z]{16}'),
  @('slack-token', 'xox[baprs]-[A-Za-z0-9-]{10,}'),
  @('private-key', '-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  @('bearer-token', '(?i)\bbearer\s+[A-Za-z0-9._~+/-]{20,}'),
  @('assigned-secret', '(?i)["'']?\b(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|token)["'']?\s*[:=]\s*["'']?[^\s''",;}]{6,}')
)

function Get-DescendantPids($Processes, [int]$RootPid) {
  # Run ownership for title disclosure: the root (the governed run's
  # own PID) plus every process descending from it through
  # ParentProcessId. A child created before its recorded parent is a
  # reused parent PID, not a descendant, so the walk refuses it. A
  # process whose parent already exited is not provably the run's and
  # stays unowned (its title redacts, the fail-safe direction).
  # $Processes entries carry ProcessId, ParentProcessId, Created.
  $byPid = @{}
  $kids = @{}
  foreach ($p in @($Processes)) {
    if ($null -eq $p) { continue }
    $byPid[[int]$p.ProcessId] = $p
    $pp = [int]$p.ParentProcessId
    if (-not $kids.ContainsKey($pp)) { $kids[$pp] = @() }
    $kids[$pp] += [int]$p.ProcessId
  }
  $tree = @{}
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($RootPid)
  while ($queue.Count -gt 0) {
    $n = [int]$queue.Dequeue()
    if ($tree.ContainsKey($n)) { continue }
    $tree[$n] = $true
    if (-not $kids.ContainsKey($n)) { continue }
    foreach ($c in $kids[$n]) {
      if ($c -eq $n) { continue }
      $parent = $byPid[$n]
      $child = $byPid[$c]
      if (($null -ne $parent) -and ($null -ne $child) -and ($null -ne $parent.Created) -and ($null -ne $child.Created) -and ([datetime]$child.Created -lt [datetime]$parent.Created)) { continue }
      $queue.Enqueue($c)
    }
  }
  return $tree
}

function Format-WindowRow([int]$ProcId, [string]$Name, [string]$Title, [bool]$Owned) {
  # Titles name open documents and pages, so a title survives only
  # when the process is both a kind the run launches and provably the
  # run's own (Get-DescendantPids); an operator-opened ScratchPad or
  # terminal redacts like every other foreign window.
  if ($Owned -and ($script:CaptureOwnedProcesses -contains $Name)) { return "pid=$ProcId ${Name}: $Title" }
  return "pid=$ProcId ${Name}: [title redacted]"
}

function Test-RetainableCaptures([string]$SourceDir) {
  # Retain-side enforcement of the capture policy (D00 T02 §22 item 1,
  # R3-F1): retention re-scans every text capture under the source's
  # captures-* directories itself instead of trusting the run's notes.
  # A failure marker, a secret hit, or an unreadable capture refuses
  # the retain. Returns Ok plus Reasons.
  $reasons = @()
  foreach ($d in @(Get-ChildItem -Path $SourceDir -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'captures-*' })) {
    if (Test-Path (Join-Path $d.FullName $script:CaptureFailMarker)) { $reasons += "$($d.Name)/$($script:CaptureFailMarker) present (an unscanned capture was kept)" }
    $stage = Join-Path $d.FullName $script:CaptureStagingDir
    if ((Test-Path $stage) -and (@(Get-ChildItem -LiteralPath $stage -Recurse -File -Force -ErrorAction SilentlyContinue).Count -gt 0)) { $reasons += "$($d.Name)/$($script:CaptureStagingDir) holds unscanned staged captures" }
    foreach ($f in @(Get-ChildItem -Path $d.FullName -File -ErrorAction SilentlyContinue | Where-Object { (@('.txt', '.log', '.json') -contains $_.Extension.ToLower()) -and ($_.Name -ne $script:CaptureFailMarker) })) {
      try {
        $hits = @(Test-CaptureSecrets ([System.IO.File]::ReadAllText($f.FullName)))
        if ($hits.Count -gt 0) { $reasons += "$($d.Name)/$($f.Name) holds $($hits -join ', ')" }
      } catch { $reasons += "$($d.Name)/$($f.Name) unreadable ($($_.Exception.Message))" }
    }
  }
  return [pscustomobject]@{ Ok = ($reasons.Count -eq 0); Reasons = $reasons }
}

function Publish-TextCapture([string]$CaptureDir, [string]$Name, [string[]]$Lines, [string]$Leg) {
  # Staged text capture (D00 T02 section 30 item 1): the lines land in
  # <CaptureDir>\.staging first and reach the capture directory only
  # after the secret scan passes, so no reader of the directory ever
  # sees unscanned text. A hit publishes the redaction note under the
  # capture's name instead (the staged bytes are deleted, never
  # renamed); an unreadable or undeletable staging file fails closed
  # with the scan-failure marker. Returns report notes.
  $notes = @()
  $stageDir = Join-Path $CaptureDir $script:CaptureStagingDir
  $staged = Join-Path $stageDir $Name
  $final = Join-Path $CaptureDir $Name
  try {
    $null = New-Item -ItemType Directory -Force -Path $stageDir
    @($Lines) | Set-Content -Path $staged -Encoding UTF8
    $hits = @(Test-CaptureSecrets ([System.IO.File]::ReadAllText($staged)))
    if ($hits.Count -gt 0) {
      Remove-Item -LiteralPath $staged -Force -ErrorAction Stop
      "[capture redacted by the secret scan: $($hits -join ', '); see docs/testing.md Failure-capture policy]" | Set-Content -Path $final -Encoding UTF8
      $notes += "- $Leg : SECRET-SCAN redacted $Name ($($hits -join ', '))"
    } else {
      Move-Item -LiteralPath $staged -Destination $final -Force -ErrorAction Stop
    }
  } catch {
    $why = $_.Exception.Message
    try {
      if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force -ErrorAction Stop }
      $notes += "- $Leg : SECRET-SCAN could not stage $Name ($why); capture dropped (fail closed)"
    } catch {
      $notes += "- $Leg : SECRET-SCAN FAILED: staged $Name could not be scanned ($why) or deleted ($($_.Exception.Message)); do not retain this run"
      try { Add-Content -LiteralPath (Join-Path $CaptureDir $script:CaptureFailMarker) -Value "$($script:CaptureStagingDir)/$Name" -Encoding UTF8 } catch { $notes += "- $Leg : SECRET-SCAN marker write failed: $($_.Exception.Message)" }
    }
  }
  try {
    if ((Test-Path $stageDir) -and (@(Get-ChildItem -LiteralPath $stageDir -Force -ErrorAction SilentlyContinue).Count -eq 0)) { Remove-Item -LiteralPath $stageDir -Force }
  } catch { }
  return $notes
}

function Limit-RunCaptureBudget([string]$RunDir, [long]$MaxBytes) {
  # Aggregate capture budget per run (D00 T02 section 30 item 2): all
  # captures-* directories together (screenshots, window lists, event
  # slices, dumps) stay under $MaxBytes. Over budget, files drop in a
  # stated order (screenshots, then dumps, then text captures, largest
  # first within each class) until the total fits, and a marker at the
  # run root names every dropped file with its bytes. Returns notes.
  $notes = @()
  $files = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $RunDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'captures-*' })) {
    $files += @(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $script:CaptureFailMarker })
  }
  $total = [long](($files | Measure-Object Length -Sum).Sum)
  if ($total -le $MaxBytes) { return $notes }
  $rank = { param($f) switch ($f.Extension.ToLower()) { '.png' { 0 } '.dmp' { 1 } default { 2 } } }
  $ordered = @($files | Sort-Object @{ Expression = { & $rank $_ } }, @{ Expression = 'Length'; Descending = $true })
  $dropped = @()
  foreach ($f in $ordered) {
    if ($total -le $MaxBytes) { break }
    try {
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
      $total -= $f.Length
      $dropped += "$($f.FullName.Substring($RunDir.Length).TrimStart('\', '/')) ($($f.Length) bytes)"
    } catch { $notes += "- capture budget: could not drop $($f.Name): $($_.Exception.Message)" }
  }
  $marker = Join-Path $RunDir $script:CaptureBudgetMarker
  $body = @("Capture budget truncated: the run's captures exceeded $MaxBytes bytes; dropped in order (screenshots, then dumps, then text captures, largest first):") + $dropped
  try { $body | Set-Content -Path $marker -Encoding UTF8 } catch { $notes += "- capture budget: marker write failed: $($_.Exception.Message)" }
  $notes += "- capture budget: TRUNCATED to $total of $MaxBytes bytes; dropped $($dropped.Count) file(s), listed in $($script:CaptureBudgetMarker)"
  return $notes
}

function Get-KeepReleaseCandidates([string]$RetDir, [string]$NightDir, [string]$Root, [int]$Count = 3) {
  # Quota recovery (D00 T02 section 30 item 3): the oldest KEEP
  # exemptions (retained copies and KEEP-marked stamp dirs), each with
  # the tracked files that cite it, so a quota refusal names what to
  # release and where the citation lives. Oldest first by write time.
  $cands = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $RetDir -Directory -ErrorAction SilentlyContinue)) { $cands += [pscustomobject]@{ Label = "retained/$($d.Name)"; Name = $d.Name; Time = $d.LastWriteTimeUtc; Path = $d.FullName } }
  foreach ($d in @(Get-ChildItem -LiteralPath $NightDir -Directory -ErrorAction SilentlyContinue)) {
    if (($d.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$') -and (Test-Path (Join-Path $d.FullName 'KEEP.txt'))) { $cands += [pscustomobject]@{ Label = "kept/$($d.Name)"; Name = $d.Name; Time = (Get-Item (Join-Path $d.FullName 'KEEP.txt')).LastWriteTimeUtc; Path = $d.FullName } }
  }
  $docs = @()
  foreach ($sub in @('todo', 'docs')) {
    $dir = Join-Path $Root $sub
    if (Test-Path $dir) { $docs += @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue) }
  }
  $lines = @()
  foreach ($c in @($cands | Sort-Object Time | Select-Object -First $Count)) {
    $cites = @()
    foreach ($f in $docs) {
      $hit = Select-String -LiteralPath $f.FullName -SimpleMatch $c.Name -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($null -ne $hit) { $cites += "$($f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'):$($hit.LineNumber)" }
      if ($cites.Count -ge 2) { break }
    }
    $mb = [int](([long]((Get-ChildItem -LiteralPath $c.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)) / 1MB)
    $lines += "$($c.Label) ($($c.Time.ToString('yyyy-MM-dd')), $mb MB; cited by $(if ($cites.Count -eq 0) { 'nothing tracked' } else { $cites -join ', ' }))"
  }
  return $lines
}

function Test-CaptureSecrets([string]$Text) {
  # Secret scan over one text capture: returns the pattern names that
  # hit (empty when clean). Names only, never the matched value.
  $hits = @()
  foreach ($p in $script:SecretPatterns) {
    if ([regex]::IsMatch("$Text", $p[1])) { $hits += $p[0] }
  }
  return $hits
}

function Protect-CaptureDir([string]$CaptureDir, [string]$Leg) {
  # Enforces the capture policy on a written capture directory: every
  # .txt/.log/.json capture is secret-scanned and, on a hit, replaced
  # whole by a redaction note naming the patterns (the scan fails that
  # capture rather than trusting a partial mask); then, when the
  # directory exceeds the size cap, screenshots drop first. Never
  # throws; returns report notes.
  $notes = @()
  if (-not (Test-Path $CaptureDir)) { return $notes }
  # Staged captures left by an interrupted write were never scanned:
  # delete them (section 30 item 1), or mark the directory unretainable.
  $stageDir = Join-Path $CaptureDir $script:CaptureStagingDir
  if (Test-Path $stageDir) {
    try { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction Stop; $notes += "- $Leg : leftover staged captures deleted unscanned (fail closed)" }
    catch {
      $notes += "- $Leg : SECRET-SCAN FAILED: leftover staged captures could not be deleted ($($_.Exception.Message)); do not retain this run"
      try { Add-Content -LiteralPath (Join-Path $CaptureDir $script:CaptureFailMarker) -Value $script:CaptureStagingDir -Encoding UTF8 } catch { }
    }
  }
  foreach ($f in @(Get-ChildItem -Path $CaptureDir -File -ErrorAction SilentlyContinue | Where-Object { (@('.txt', '.log', '.json') -contains $_.Extension.ToLower()) -and ($_.Name -ne $script:CaptureFailMarker) })) {
    try {
      $hits = @(Test-CaptureSecrets ([System.IO.File]::ReadAllText($f.FullName)))
      if ($hits.Count -gt 0) {
        "[capture redacted by the secret scan: $($hits -join ', '); see docs/testing.md Failure-capture policy]" | Set-Content -Path $f.FullName -Encoding UTF8
        $notes += "- $Leg : SECRET-SCAN redacted $($f.Name) ($($hits -join ', '))"
      }
    } catch {
      # Fail closed: a capture the scan could not read or redact is
      # deleted, never kept unscanned; if even the delete fails, the
      # note says so loudly and the run must not be retained.
      $why = $_.Exception.Message
      try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $notes += "- $Leg : SECRET-SCAN could not scan $($f.Name) ($why); capture deleted (fail closed)"
      } catch {
        $notes += "- $Leg : SECRET-SCAN FAILED: $($f.Name) could not be scanned ($why) or deleted ($($_.Exception.Message)); do not retain this run"
        # Persist the failure beside the capture: NightlyRetention.ps1
        # -Retain refuses any source carrying this marker, so a lock
        # that clears later cannot let the unscanned bytes be retained.
        try { Add-Content -LiteralPath (Join-Path $CaptureDir $script:CaptureFailMarker) -Value $f.Name -Encoding UTF8 } catch { $notes += "- $Leg : SECRET-SCAN marker write failed: $($_.Exception.Message)" }
      }
    }
  }
  try {
    $total = (@(Get-ChildItem -Path $CaptureDir -File -Recurse -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum
    if ($total -gt $script:CaptureMaxBytes) {
      foreach ($png in @(Get-ChildItem -Path $CaptureDir -Filter '*.png' -File -ErrorAction SilentlyContinue)) {
        Remove-Item $png.FullName -Force
        $notes += "- $Leg : size cap dropped $($png.Name) (capture dir $([int]($total / 1MB)) MB over $([int]($script:CaptureMaxBytes / 1MB)) MB)"
      }
    }
  } catch { $notes += "- $Leg : size cap check failed: $($_.Exception.Message)" }
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
  # Every count pair, methods and cases per leg (D00 T02 §29: run-b and
  # interactive methods were unchecked, so a methods-only drift passed).
  $pairs = @( @('run-a-methods', $fp.RunAMethods, $Discovery.RunAMethods), @('run-a-cases', $fp.RunACases, $Discovery.RunACases), @('run-b-methods', $fp.RunBMethods, $Discovery.RunBMethods), @('run-b-cases', $fp.RunBCases, $Discovery.RunBCases), @('interactive-methods', $fp.InteractiveMethods, $Discovery.InteractiveMethods), @('interactive-cases', $fp.InteractiveCases, $Discovery.InteractiveCases) )
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
  # Time-independent discovery (D00 T02 §29): outside the quiet window a
  # fenced Theory lists as one skipped case instead of its rows, so a
  # daytime regen undercounted what the 02:30 night discovers. The force
  # variable makes the fence attributes expand everywhere; the prior
  # value is restored whatever happens.
  $priorForce = $env:SCRATCHPAD_INTERACTIVE_FORCE
  $env:SCRATCHPAD_INTERACTIVE_FORCE = '1'
  try {
    $cap = Invoke-BoundedCapture $Dotnet @('test', $Csproj, '--no-build', '--nologo', '--filter', $Filter, '--list-tests') (Split-Path -Parent $Csproj) $TimeoutSeconds
  } finally {
    $env:SCRATCHPAD_INTERACTIVE_FORCE = $priorForce
  }
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

function Test-UiBuildFresh([datetime]$BinaryTimeUtc, [datetime]$NewestSourceTimeUtc, [string]$BinaryPath) {
  # Stale-build refusal (D00 T02 §29): discovery reads the built UI
  # binaries, so a test source newer than the binary means the counts
  # would describe an older tree. Returns Ok plus the instruction.
  if ($BinaryTimeUtc -lt $NewestSourceTimeUtc) {
    return [pscustomobject]@{ Ok = $false; Error = "UI build is stale: $BinaryPath ($($BinaryTimeUtc.ToString('u'))) is older than the newest tests/UI source ($($NewestSourceTimeUtc.ToString('u'))); run: dotnet build src/ScratchPad.slnx, then retry" }
  }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

function Get-UiBuildFreshness([string]$Root) {
  $dll = Join-Path $Root 'Bin\UI\Debug\UI.dll'
  if (-not (Test-Path $dll)) { return [pscustomobject]@{ Ok = $false; Error = "UI build missing: $dll; run: dotnet build src/ScratchPad.slnx, then retry" } }
  $newest = Get-ChildItem -Path (Join-Path $Root 'tests\UI') -Recurse -Include '*.cs', '*.csproj' -File |
    Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($null -eq $newest) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  return Test-UiBuildFresh (Get-Item $dll).LastWriteTimeUtc $newest.LastWriteTimeUtc $dll
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

function Get-IncidentPhase([string]$Where) {
  # Phase part of the incident identity (D00 T02 §22 item 3): the leg
  # family, so soak iterations of one suite merge while the same test
  # failing in a different leg stays its own incident.
  $w = "$Where".Trim()
  if ($w -match '^Run A') { return 'run-a' }
  if ($w -match '^Run B') { return 'run-b' }
  if ($w -match '^Interactive') { return 'interactive' }
  if ($w -match '^(ui-soak|protocol-soak)-\d+$') { return ($w -replace '-\d+$', '') }
  return ($w.ToLower() -replace '\s+', '-')
}

function Get-FailureClass([string]$Message) {
  # Failure-class part of the identity: the exception type or the xUnit
  # assertion that failed, never the values it printed. Unknown shapes
  # fall back to the first message line with decimal runs collapsed and
  # HRESULT-shaped hex kept verbatim.
  $first = ("$Message" -split "`r?`n")[0].Trim()
  $m = [regex]::Match($first, '^((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*Exception)\b')
  if ($m.Success) { return $m.Groups[1].Value }
  $m = [regex]::Match($first, '^(Assert\.\w+\(\)) Failure')
  if ($m.Success) { return "$($m.Groups[1].Value) Failure" }
  $parts = [regex]::Split($first, '(0x[0-9A-Fa-f]{8})')
  $shape = ''
  foreach ($p in $parts) {
    if ($p -match '^0x[0-9A-Fa-f]{8}$') { $shape += '0x' + $p.Substring(2).ToUpper() }
    else { $shape += ($p -replace '\d+', '#') }
  }
  $shape = ($shape -replace '\s+', ' ').Trim()
  if ($shape.Length -gt 120) { $shape = $shape.Substring(0, 120) }
  return "msg:$shape"
}

function Get-HResults([string]$Text) {
  # HRESULT part of the identity: every 0x-prefixed 8-hex code in the
  # message plus stack, uppercased, unique, in first-seen order. Digit
  # collapse never touches these, so 0x80131505 and 0x80004005 split.
  $out = @()
  foreach ($m in [regex]::Matches("$Text", '0x[0-9A-Fa-f]{8}\b')) {
    $v = '0x' + $m.Value.Substring(2).ToUpper()
    if ($out -notcontains $v) { $out += $v }
  }
  return $out
}

function Get-StackSignature([string]$Stack) {
  # Normalized stack signature: the top three frames outside the
  # runtime and test framework (System., Microsoft., Xunit.), method
  # names only. Line numbers, file paths, and argument lists drop, and
  # compiler-generated ordinals (DisplayClass12_0, b__3_1, d__5, `1)
  # collapse, so a rebuild cannot split one failure in two.
  $frames = @()
  foreach ($ln in ("$Stack" -split "`r?`n")) {
    $m = [regex]::Match($ln, '^\s*at\s+([^\(\s]+)')
    if (-not $m.Success) { continue }
    $f = $m.Groups[1].Value
    if ($f -match '^(System|Microsoft|Xunit)\.') { continue }
    $f = $f -replace 'DisplayClass\d+_\d+', 'DisplayClass#' -replace 'b__\d+_\d+', 'b__#' -replace 'b__\d+', 'b__#' -replace 'd__\d+', 'd__#' -replace '`\d+', '`#'
    $frames += $f
    if ($frames.Count -ge 3) { break }
  }
  if ($frames.Count -eq 0) { return 'nostack' }
  return ($frames -join ' < ')
}

function Get-IncidentKey($Failure) {
  # The incident identity contract (D00 T02 §22 item 3, shared with the
  # §17 recurrence report through the INC ids it hashes into): test
  # identity, phase, failure class, HRESULTs, and stack signature, in
  # that order, pipe-joined. docs/testing.md "Incident identity"
  # carries the contract; the fixture suite pins golden ids, so any
  # normalization change that would split or merge history fails there
  # first. Contract version 2 (2026-09-25); version 1 keyed on test
  # plus a digit-collapsed message and its ids do not carry over.
  $stack = ''
  if ($Failure.PSObject.Properties.Name -contains 'Stack') { $stack = "$($Failure.Stack)" }
  $hr = @(Get-HResults ("$($Failure.Message)`n$stack")) -join ','
  if ($hr -eq '') { $hr = 'nohr' }
  return "v2|$("$($Failure.Test)".Trim())|$(Get-IncidentPhase $Failure.Where)|$(Get-FailureClass $Failure.Message)|$hr|$(Get-StackSignature $stack)"
}

function Get-IncidentGroups($Failures) {
  # Groups failures into incidents under the identity contract, keeping
  # every occurrence, busiest first (first-seen order breaks ties).
  # $Failures entries carry Test, Message, Where, and optionally Stack.
  $groups = @{}
  $order = @()
  foreach ($f in @($Failures)) {
    if ($null -eq $f) { continue }
    $key = Get-IncidentKey $f
    if (-not $groups.ContainsKey($key)) {
      $first = ("$($f.Message)" -split "`r?`n")[0]
      $groups[$key] = [pscustomobject]@{ Id = "INC-$(Get-StringHash $key)"; Key = $key; Test = "$($f.Test)".Trim(); Phase = (Get-IncidentPhase $f.Where); Message = $first; Wheres = @() }
      $order += $key
    }
    $groups[$key].Wheres += $f.Where
  }
  $ranked = @()
  $i = 0
  foreach ($k in $order) { $ranked += [pscustomobject]@{ Key = $k; N = $groups[$k].Wheres.Count; R = $i }; $i++ }
  $sorted = @()
  foreach ($r in ($ranked | Sort-Object @{ Expression = 'N'; Descending = $true }, @{ Expression = 'R'; Descending = $false })) { $sorted += $groups[$r.Key] }
  return $sorted
}

function Format-Incidents($Failures) {
  # Report lines for the Incidents section: one per incident under the
  # identity contract (Get-IncidentKey), with every occurrence named.
  # IDs derive from content, so the same failure keeps its ID across
  # nights for recurrence tracking.
  $lines = @()
  foreach ($g in @(Get-IncidentGroups $Failures)) {
    $msg = $g.Message
    if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
    $lines += "- $($g.Id) ``$($g.Test)`` x$($g.Wheres.Count) ($($g.Wheres -join ', ')): $msg"
  }
  return $lines
}

function Read-IncidentLedger([string]$Path) {
  # Cross-night incident ledger (D00 T02 §22 item 6): ignored scratch
  # beside the runs (build/nightly/incidents.json), never a tracked
  # file. Missing reads as an empty ledger; a corrupt file reads as an
  # error, so the caller reds instead of minting every incident anew.
  $empty = [pscustomobject]@{ Ok = $true; Error = ''; Incidents = @{} }
  if (-not (Test-Path $Path)) { return $empty }
  try {
    $j = Get-Content $Path -Raw | ConvertFrom-Json
    $bad = { param($why) [pscustomobject]@{ Ok = $false; Error = "incident ledger invalid: $why"; Incidents = @{} } }
    if ($null -eq $j) { return (& $bad 'empty document') }
    if ($j.version -ne 1) { return [pscustomobject]@{ Ok = $false; Error = "incident ledger version $($j.version) unsupported"; Incidents = @{} } }
    if (@($j.PSObject.Properties.Name) -notcontains 'incidents') { return (& $bad 'no incidents array') }
    $map = @{}
    foreach ($e in @($j.incidents)) {
      if ($null -eq $e) { return (& $bad 'null entry') }
      $names = @($e.PSObject.Properties.Name)
      foreach ($req in @('id', 'test', 'phase', 'key', 'state', 'firstSeen', 'lastSeen', 'occurrences')) {
        if ($names -notcontains $req) { return (& $bad "entry $($e.id) lacks $req") }
      }
      if ("$($e.id)" -notmatch '^INC-[0-9a-f]{8}$') { return (& $bad "entry id malformed: $($e.id)") }
      if (@('open', 'closed') -notcontains "$($e.state)") { return (& $bad "entry $($e.id) state $($e.state)") }
      if (("$($e.test)" -eq '') -or ("$($e.phase)" -eq '')) { return (& $bad "entry $($e.id) has an empty test or phase") }
      if (@($e.occurrences).Count -eq 0) { return (& $bad "entry $($e.id) has no occurrences") }
      foreach ($o in @($e.occurrences)) {
        if ($null -eq $o) { return (& $bad "entry $($e.id) has a null occurrence") }
        $on = @($o.PSObject.Properties.Name)
        if (($on -notcontains 'stamp') -or ("$($o.stamp)" -eq '')) { return (& $bad "entry $($e.id) has an occurrence without a stamp") }
        if ($on -notcontains 'wheres') { return (& $bad "entry $($e.id) occurrence $($o.stamp) lacks wheres") }
      }
      if ($map.ContainsKey("$($e.id)")) { return (& $bad "duplicate id $($e.id)") }
      $occ = @()
      foreach ($o in @($e.occurrences)) { if ($null -ne $o) { $occ += [pscustomobject]@{ stamp = "$($o.stamp)"; wheres = @($o.wheres) } } }
      $map["$($e.id)"] = [pscustomobject]@{ id = "$($e.id)"; test = "$($e.test)"; phase = "$($e.phase)"; key = "$($e.key)"; owner = "$($e.owner)"; state = "$($e.state)"; firstSeen = "$($e.firstSeen)"; lastSeen = "$($e.lastSeen)"; closedAt = "$($e.closedAt)"; closedBy = "$($e.closedBy)"; occurrences = $occ; passStreak = [int]$e.passStreak; lastPassStamp = "$($e.lastPassStamp)"; due = "$($e.due)"; finding = "$($e.finding)" }
    }
    return [pscustomobject]@{ Ok = $true; Error = ''; Incidents = $map }
  } catch { return [pscustomobject]@{ Ok = $false; Error = "incident ledger unreadable: $($_.Exception.Message)"; Incidents = @{} } }
}

function Get-TriageDue([string]$Stamp) {
  # Escalation date for an incident routed to the triage owner: the
  # stamp's day plus $script:TriageDays (section 30 item 6).
  $m = [regex]::Match("$Stamp", '^(\d{4}-\d{2}-\d{2})')
  if (-not $m.Success) { return '' }
  return ([datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)).AddDays($script:TriageDays).ToString('yyyy-MM-dd')
}

function Read-IncidentLinks([string]$Path) {
  # Incident -> finding links triage records (section 30 item 7):
  # rows `| INC-xxxxxxxx | <finding> |` in docs/incident-links.md, where
  # the finding is a TODO ref (DNN TNN section-sign N) or a commit.
  $links = @{}
  if (-not (Test-Path $Path)) { return $links }
  foreach ($ln in (Get-Content $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^\|\s*(INC-[0-9a-f]{8})\s*\|\s*(D\d{2} T\d{2} \u00A7\d+|[0-9a-f]{7,40})\s*\|')
    if ($m.Success) { $links[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $links
}

function Format-UnlinkedIncidents([hashtable]$Incidents) {
  # Open incidents with no recorded finding re-list on every run until
  # triage links one (section 30 item 7).
  $open = @($Incidents.Keys | Sort-Object | ForEach-Object { $Incidents[$_] } | Where-Object { ($_.state -eq 'open') -and ("$($_.finding)" -eq '') })
  if ($open.Count -eq 0) { return @() }
  return @("- Unlinked open incidents (record the finding in docs/incident-links.md): " + (($open | ForEach-Object { "$($_.id) ``$($_.test)`` (owner $($_.owner), due $($_.due))" }) -join '; '))
}

function ConvertTo-IncidentLifecycle([hashtable]$Incidents) {
  # The machine contract for the lifecycle (section 30 item 10): one
  # row per ledger incident, read by notify, trend, and triage.
  return @($Incidents.Keys | Sort-Object | ForEach-Object {
    $e = $Incidents[$_]
    [pscustomobject]@{ id = "$($e.id)"; state = "$($e.state)"; owner = "$($e.owner)"; occurrences = @($e.occurrences).Count; passStreak = [int]$e.passStreak; contract = 'v2'; due = "$($e.due)"; finding = "$($e.finding)" }
  })
}

function Update-IncidentLedger([hashtable]$Ledger, $Groups, [string]$Stamp, [hashtable]$PassedByPhase, [hashtable]$Owners, [int]$RecoveryRuns = 3, [hashtable]$Links = @{}) {
  # Incident lifecycle (D00 T02 §22 item 6, D00-T02-S17-PR27): an
  # incident is created once; later sightings append an occurrence to
  # it (never a second incident, so §9's file-every-failure rule files
  # each incident once). Ownership comes from the quarantine list when
  # the test sits there, else stays as recorded, else unassigned. An
  # open incident closes only on verified recovery: its test executed
  # and passed in the same phase on $RecoveryRuns separate runs with no
  # failure between (a failure resets the streak; a run that never
  # executed the test neither counts nor resets, and any failure of the
  # same test in the same phase resets it even under another id), so a flake that
  # passes most nights cannot close and reopen nightly. A closed
  # incident seen again reopens with its history. Idempotent per
  # stamp: re-running a stamp appends or counts nothing twice.
  # Returns the updated map plus lines.
  # Section 30 items 6 and 7: an incident no quarantine row owns routes
  # to the triage owner with an escalation date (never `unassigned`),
  # and a finding link triage recorded is copied onto its incident.
  $map = @{}
  foreach ($k in $Ledger.Keys) {
    $e = $Ledger[$k]
    foreach ($field in @('due', 'finding')) { if (@($e.PSObject.Properties.Name) -notcontains $field) { $e | Add-Member -NotePropertyName $field -NotePropertyValue '' } }
    if (("$($e.owner)" -eq '') -or ("$($e.owner)" -eq 'unassigned')) { $e.owner = $script:TriageOwner }
    if (("$($e.due)" -eq '') -and ($e.owner -eq $script:TriageOwner)) { $e.due = Get-TriageDue $e.firstSeen }
    if ($Links.ContainsKey($k)) { $e.finding = $Links[$k] }
    $map[$k] = $e
  }
  $lines = @()
  $seen = @{}
  $failedHere = @{}
  foreach ($g in @($Groups)) { if ($null -ne $g) { $failedHere["$($g.Test)|$($g.Phase)"] = $true } }
  foreach ($g in @($Groups)) {
    if ($null -eq $g) { continue }
    $seen[$g.Id] = $true
    $owner = ''
    if ($Owners -and $Owners.ContainsKey($g.Test)) { $owner = $Owners[$g.Test] }
    if (-not $map.ContainsKey($g.Id)) {
      $due = ''
      if ($owner -eq '') { $owner = $script:TriageOwner; $due = Get-TriageDue $Stamp }
      $finding = if ($Links.ContainsKey($g.Id)) { $Links[$g.Id] } else { '' }
      $map[$g.Id] = [pscustomobject]@{ id = $g.Id; test = $g.Test; phase = $g.Phase; key = $g.Key; owner = $owner; state = 'open'; firstSeen = $Stamp; lastSeen = $Stamp; closedAt = ''; closedBy = ''; occurrences = @([pscustomobject]@{ stamp = $Stamp; wheres = @($g.Wheres) }); passStreak = 0; lastPassStamp = ''; due = $due; finding = $finding }
      $lines += "- $($g.Id) ``$($g.Test)``: new (owner $owner$(if ($due -ne '') { ", triage due $due" }))"
      continue
    }
    $e = $map[$g.Id]
    if ($owner -ne '') { $e.owner = $owner; $e.due = '' }
    $already = @($e.occurrences | Where-Object { "$($_.stamp)" -eq $Stamp }).Count -gt 0
    if (-not $already) { $e.occurrences = @($e.occurrences) + @([pscustomobject]@{ stamp = $Stamp; wheres = @($g.Wheres) }) }
    $e.lastSeen = $Stamp
    $e.passStreak = 0
    $n = @($e.occurrences).Count
    if ($e.state -eq 'closed') {
      $e.state = 'open'; $e.closedAt = ''; $e.closedBy = ''
      $lines += "- $($g.Id) ``$($g.Test)``: REOPENED (first seen $($e.firstSeen), $n occurrences, owner $($e.owner))"
    } else {
      $lines += "- $($g.Id) ``$($g.Test)``: recurring (first seen $($e.firstSeen), $n occurrences, owner $($e.owner))"
    }
  }
  foreach ($id in @($map.Keys | Sort-Object)) {
    $e = $map[$id]
    if (($e.state -ne 'open') -or $seen.ContainsKey($id)) { continue }
    if ($failedHere.ContainsKey("$($e.test)|$($e.phase)")) {
      # A different failure of the same test in the same phase is no
      # recovery: the streak breaks even though this id did not recur.
      if ([int]$e.passStreak -gt 0) { $lines += "- $id ``$($e.test)``: streak reset (the test failed differently in $($e.phase))" }
      $e.passStreak = 0; $e.lastPassStamp = $Stamp
      continue
    }
    $passed = @()
    if ($PassedByPhase -and $PassedByPhase.ContainsKey($e.phase)) { $passed = @($PassedByPhase[$e.phase]) }
    if ($passed -notcontains $e.test) { continue }
    if ($e.lastPassStamp -ne $Stamp) { $e.passStreak = [int]$e.passStreak + 1; $e.lastPassStamp = $Stamp }
    if ([int]$e.passStreak -ge $RecoveryRuns) {
      $e.state = 'closed'; $e.closedAt = $Stamp; $e.closedBy = "passed in $($e.phase) on $($e.passStreak) runs"
      $lines += "- $id ``$($e.test)``: CLOSED (verified recovery: passed in $($e.phase) on $($e.passStreak) runs through $Stamp; $(@($e.occurrences).Count) occurrences since $($e.firstSeen))"
    } else {
      $lines += "- $id ``$($e.test)``: recovering (passed in $($e.phase) on $($e.passStreak) of $RecoveryRuns runs)"
    }
  }
  return [pscustomobject]@{ Incidents = $map; Lines = $lines }
}

function Get-IncidentResultRows([string[]]$ResultFiles, [string]$Since) {
  # Result files at or after $Since (a stamp) that carry incident
  # lines, oldest first, each as Stamp plus parsed groups (Id, Test,
  # Phase, Key, Wheres) ready for Update-IncidentLedger.
  $rows = @()
  foreach ($f in @($ResultFiles)) {
    $o = $null
    try { $o = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if (("$($o.stamp)" -eq '') -or ("$($o.stamp)" -lt $Since)) { continue }
    $groups = @()
    foreach ($ln in @($o.incidents)) {
      $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)` x\d+ \(([^)]*)\)')
      if (-not $m.Success) { continue }
      $wheres = @($m.Groups[3].Value -split ',\s*' | Where-Object { $_ -ne '' })
      $groups += [pscustomobject]@{ Id = $m.Groups[1].Value; Test = $m.Groups[2].Value; Phase = (Get-IncidentPhase ($wheres | Select-Object -First 1)); Key = ''; Wheres = $wheres }
    }
    if ($groups.Count -gt 0) { $rows += [pscustomobject]@{ Stamp = "$($o.stamp)"; Groups = $groups } }
  }
  return @($rows | Sort-Object Stamp)
}

function Test-IncidentLedgerPresence([string]$LedgerPath, [string[]]$ResultFiles, [string]$Since) {
  # A missing ledger reads as empty only when no earlier result carries
  # incidents (section 30 item 4); otherwise every failure would re-file
  # as new, so the run reds with the rebuild instruction.
  if (Test-Path -LiteralPath $LedgerPath) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $rows = @(Get-IncidentResultRows $ResultFiles $Since)
  if ($rows.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  return [pscustomobject]@{ Ok = $false; Error = "incident ledger missing while $($rows.Count) earlier result(s) carry incidents (latest $($rows[-1].Stamp)); rebuild: powershell -NoProfile -ExecutionPolicy Bypass -File tools/NightlyLedger.ps1 -Rebuild" }
}

function New-IncidentLedgerFromResults([string[]]$ResultFiles, [string]$Since, [hashtable]$Owners, [hashtable]$Links = @{}) {
  # Rebuild (section 30 item 4): replays every retained result's
  # incidents through Update-IncidentLedger in stamp order, restoring
  # each incident with its occurrences, then overlays the latest
  # published incidentLifecycle snapshot for state, owner, pass streak,
  # due date, and finding. A result set with no snapshot restarts
  # recovery from zero (documented).
  $map = @{}
  foreach ($r in @(Get-IncidentResultRows $ResultFiles $Since)) {
    $map = (Update-IncidentLedger $map $r.Groups $r.Stamp @{} $Owners 3 $Links).Incidents
  }
  # The latest result's incidentLifecycle block (section 30 R1-I1) is the
  # last published state: restore each incident's state, owner, pass
  # streak, due date, and finding from it instead of the replay's
  # defaults, so a closed incident stays closed and recovery progress
  # and historical owners survive the loss. Only incidents the replay
  # restored are touched; the snapshot never invents one.
  $snap = $null
  $snapStamp = ''
  foreach ($f in @($ResultFiles)) {
    try { $o = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ((@($o.PSObject.Properties.Name) -contains 'incidentLifecycle') -and ("$($o.stamp)" -ge $Since) -and ("$($o.stamp)" -gt $snapStamp)) { $snap = @($o.incidentLifecycle); $snapStamp = "$($o.stamp)" }
  }
  foreach ($row in @($snap)) {
    if (($null -eq $row) -or (-not $map.ContainsKey("$($row.id)"))) { continue }
    $e = $map["$($row.id)"]
    $e.owner = "$($row.owner)"; $e.due = "$($row.due)"; $e.finding = "$($row.finding)"; $e.passStreak = [int]$row.passStreak
    if ("$($row.state)" -eq 'closed') {
      $e.state = 'closed'
      if ("$($e.closedAt)" -eq '') { $e.closedAt = $snapStamp; $e.closedBy = "restored from the $snapStamp result snapshot" }
    }
  }
  return $map
}

function Write-IncidentLedger([hashtable]$Incidents, [string]$Path) {
  # Atomic write plus read-back: a ledger that cannot be read back is a
  # failed write the caller reports, never a silent loss. Returns '' on
  # success, else the error.
  $list = @($Incidents.Keys | Sort-Object | ForEach-Object { $Incidents[$_] })
  $json = ConvertTo-Json ([pscustomobject]@{ version = 1; incidents = $list }) -Depth 8
  Write-AtomicReport @($json) $Path
  $back = Read-IncidentLedger $Path
  if (-not $back.Ok) { return $back.Error }
  if ($back.Incidents.Count -ne $Incidents.Count) { return "incident ledger read-back count $($back.Incidents.Count) != $($Incidents.Count)" }
  return ''
}

function Get-QuarantineOwners([string]$LedgerPath) {
  # Test -> owner from the quarantine list rows in
  # docs/soak-and-quarantine.md, so a quarantined flake's incident names
  # the section that owes its fix-or-remove decision.
  $owners = @{}
  if (-not (Test-Path $LedgerPath)) { return $owners }
  $inList = $false
  foreach ($ln in (Get-Content $LedgerPath -Encoding UTF8)) {
    if ($ln -match '^## Quarantine list') { $inList = $true; continue }
    if ($inList -and ($ln -match '^## ')) { break }
    if (-not $inList) { continue }
    $m = [regex]::Match($ln, '^\|\s*`([^`]+)`[^|]*\|[^|]*\|[^|]*\|\s*([^|]+?)\s*\|')
    if ($m.Success) { $owners[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $owners
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

# --- D00 T02 §16: timer verification, recovery, and evidence integrity ---

function Read-LatestReport([string]$NightDir) {
  # Resolves latest.txt to its archived morning report and verifies the
  # target (D00 T02 §16 item 10): the pointer exists, the target exists,
  # the target is a final morning report, and its run identity carries
  # the pointed stamp. Triage resolves the current report through this
  # reader (docs/testing.md), never by globbing stamp dirs.
  $ptr = Join-Path $NightDir 'latest.txt'
  if (-not (Test-Path $ptr)) { return [pscustomobject]@{ Ok = $false; Stamp = ''; Path = ''; Error = 'latest.txt missing' } }
  $first = @((Get-Content $ptr -ErrorAction SilentlyContinue)) | Select-Object -First 1
  $stamp = "$first".Trim()
  if ($stamp -eq '') { return [pscustomobject]@{ Ok = $false; Stamp = ''; Path = ''; Error = 'latest.txt empty' } }
  $target = Join-Path $NightDir "morning-$stamp.md"
  if (-not (Test-Path $target)) { return [pscustomobject]@{ Ok = $false; Stamp = $stamp; Path = $target; Error = "target missing: morning-$stamp.md" } }
  $head = @(Get-Content $target -TotalCount 14 -ErrorAction SilentlyContinue)
  if (($head.Count -eq 0) -or ($head[0] -notlike '# Morning report:*')) { return [pscustomobject]@{ Ok = $false; Stamp = $stamp; Path = $target; Error = 'target is not a morning report' } }
  if ((($head -join "`n") -notlike '*Status: final*')) { return [pscustomobject]@{ Ok = $false; Stamp = $stamp; Path = $target; Error = 'target is not final' } }
  $idLine = @($head | Where-Object { $_ -like '- Run identity:*' })
  if ($idLine.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Stamp = $stamp; Path = $target; Error = 'target carries no run identity' } }
  if ($idLine[0] -notlike "- Run identity: $stamp-pid*") { return [pscustomobject]@{ Ok = $false; Stamp = $stamp; Path = $target; Error = "identity mismatch (want $stamp-pid*)" } }
  return [pscustomobject]@{ Ok = $true; Stamp = $stamp; Path = $target; Error = '' }
}

function Read-RawLines([string]$Path) {
  # File lines without provider decoration (D00 T02 §17 backfill):
  # Get-Content hangs PSPath, PSDrive, PSProvider, ReadCount on every
  # line, and ConvertTo-Json serializes the decoration, expanding the
  # provider graph toward the depth limit (measured: a 41-char line
  # reads 25KB at depth 2; depth 8 spins to GBs and never returns).
  # The [string[]] cast strips every note property, so JSON inputs stay
  # raw. Missing or unreadable files read empty, never throw.
  $got = @(Get-Content $Path -ErrorAction SilentlyContinue)
  if ($got.Count -eq 0) { return @() }
  return @([string[]]$got)
}

function Get-TreeFingerprint([string]$Root) {
  # Content fingerprint of worktree dirt (D00 T02 §16 item 16): the
  # porcelain file list alone cannot see content swaps, so every dirty
  # path contributes its worktree-bytes hash. Clean trees fingerprint
  # empty; a git failure reads unknown (fail closed: never clean).
  $porc = @()
  try {
    $porc = @(git -C $Root status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ State = 'unknown'; Fingerprint = ''; Count = -1 } }
  } catch { return [pscustomobject]@{ State = 'unknown'; Fingerprint = ''; Count = -1 } }
  if ($porc.Count -eq 0) { return [pscustomobject]@{ State = 'clean'; Fingerprint = ''; Count = 0 } }
  $rows = @()
  foreach ($line in $porc) {
    if ($line.Length -lt 4) { continue }
    $xy = $line.Substring(0, 2)
    $path = $line.Substring(3)
    if ($path -like '* -> *') { $path = $path.Substring($path.IndexOf(' -> ') + 4) }
    $path = $path.Trim().Trim('"')
    $h = 'absent'
    $full = Join-Path $Root $path
    if (Test-Path $full -PathType Leaf) {
      try { $h = ((git -C $Root hash-object -- $full 2>$null) | Out-String).Trim() } catch { $h = 'unhashable' }
      if ($h -eq '') { $h = 'unhashable' }
    } elseif (Test-Path $full) { $h = 'dir' }
    $rows += "$xy|$path|$h"
  }
  $fp = Get-StringHash (($rows | Sort-Object) -join "`n")
  return [pscustomobject]@{ State = 'dirty'; Fingerprint = $fp; Count = $porc.Count }
}

function Test-ProjectCoverage([string]$TestsRoot, [string[]]$Executed) {
  # Discovery cross-check (D00 T02 §16 item 15): a test project is a
  # tests/*/*.csproj referencing the test SDK; every discovered
  # project must run, or the leg omits coverage silently. bin/obj
  # trees never count as sources. Discovery errors fail closed:
  # unreadable projects land in Missing, never silently out.
  # Returns Ok plus Missing names.
  $found = @()
  $unreadable = @()
  if (Test-Path $TestsRoot) {
    $covErrs = $null
    $files = @(Get-ChildItem -Path $TestsRoot -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable covErrs | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
    if (@($covErrs).Count -gt 0) { return [pscustomobject]@{ Ok = $false; Missing = @('discovery error: test tree unreadable'); Found = @() } }
    foreach ($f in $files) {
      $text = ''
      try { $text = Get-Content $f.FullName -Raw -ErrorAction Stop } catch { $unreadable += $f.BaseName; continue }
      if ($text -match 'Microsoft\.NET\.Test\.Sdk') { $found += $f.BaseName }
    }
  }
  $missing = @(@($found | Where-Object { $Executed -notcontains $_ }) + @($unreadable) | Sort-Object -Unique)
  $uniq = @($found | Sort-Object -Unique)
  if ($missing.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Missing = $missing; Found = $uniq } }
  return [pscustomobject]@{ Ok = $true; Missing = @(); Found = $uniq }
}

function Read-TaskXml([string]$XmlText) {
  # Parses a scheduled-task definition (D00 T02 §16 items 7, 9):
  # daily triggers plus action, principal, and schedule settings.
  # Malformed XML fails closed (never a partial definition).
  $xml = $null
  try { $xml = [xml]$XmlText } catch { return [pscustomobject]@{ Ok = $false; Error = "task XML does not parse: $_" } }
  if ($null -eq $xml.Task) { return [pscustomobject]@{ Ok = $false; Error = 'task XML has no Task root' } }
  $kids = @()
  try { $kids = @($xml.Task.Triggers.ChildNodes) } catch { $kids = @() }
  $trigs = @()
  foreach ($t in $kids) {
    if ("$($t.LocalName)" -match 'Trigger$') {
      $start = ''; $days = ''; $en = $true
      try { $start = "$($t.StartBoundary)" } catch { }
      try { $days = "$($t.ScheduleByDay.DaysInterval)" } catch { }
      try { if ("$($t.Enabled)" -eq 'false') { $en = $false } } catch { }
      $trigs += [pscustomobject]@{ Kind = "$($t.LocalName)"; StartBoundary = $start; DaysInterval = $days; Enabled = $en }
    }
  }
  if ($trigs.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Error = 'task XML carries no triggers' } }
  $cmd = ''; $targs = ''; $logon = ''; $limit = ''; $multi = ''; $swa = ''; $wake = ''
  try { $e = $xml.Task.Actions.Exec; if ($null -ne $e) { $cmd = "$($e.Command)".Trim(); $targs = "$($e.Arguments)".Trim() } } catch { }
  try { $logon = "$($xml.Task.Principals.Principal.LogonType)".Trim() } catch { }
  try { $limit = "$($xml.Task.Settings.ExecutionTimeLimit)".Trim() } catch { }
  try { $multi = "$($xml.Task.Settings.MultipleInstancesPolicy)".Trim() } catch { }
  try { $swa = "$($xml.Task.Settings.StartWhenAvailable)".Trim() } catch { }
  try { $wake = "$($xml.Task.Settings.WakeToRun)".Trim() } catch { }
  return [pscustomobject]@{ Ok = $true; Error = ''; Triggers = $trigs; Command = $cmd; Arguments = $targs; LogonType = $logon; ExecutionTimeLimit = $limit; MultipleInstances = $multi; StartWhenAvailable = $swa; WakeToRun = $wake }
}

function Test-MissingStart($LastRunTime, [datetime]$Now, [datetime]$Registered, [string]$LastResult, [int]$MaxAgeHours = 26) {
  # Missing-start verdict (D00 T02 §16 item 9): an enabled daily task
  # fires within MaxAgeHours; older reads MISSING, never-ran reads
  # bootstrap only while the registration itself is young.
  # Auth-shaped LastResult codes surface the credential residual
  # post-fire (no unelevated pre-fire expiry signal exists).
  $authNote = ''
  if (($LastResult -like '*0x8007052E*') -or ($LastResult -like '*0x80070569*') -or ($LastResult -like '*1326*') -or ($LastResult -like '*1385*')) { $authNote = ' (auth-shaped result: re-check stored credentials)' }
  $never = ($null -eq $LastRunTime) -or ($LastRunTime -isnot [datetime]) -or ($LastRunTime.Year -le 1900)
  if ($never) {
    $regAge = ($Now - $Registered).TotalHours
    if ($regAge -gt $MaxAgeHours) { return [pscustomobject]@{ Verdict = 'missing'; Line = "scheduler last fire: MISSING (never fired since registration $Registered)$authNote" } }
    return [pscustomobject]@{ Verdict = 'bootstrap'; Line = "scheduler last fire: bootstrap (registered $Registered, first fire pending)$authNote" }
  }
  $ageH = [math]::Round(($Now - $LastRunTime).TotalHours, 1)
  if (($Now - $LastRunTime).TotalHours -gt $MaxAgeHours) { return [pscustomobject]@{ Verdict = 'missing'; Line = "scheduler last fire: MISSING (last $LastRunTime, ${ageH}h ago; result $LastResult)$authNote" } }
  return [pscustomobject]@{ Verdict = 'ok'; Line = "scheduler last fire: $LastRunTime (${ageH}h ago; result $LastResult)$authNote" }
}

function Test-TimerLaunch([string]$ParentName, [string]$GrandparentName, [datetime]$RunStart, [string[]]$TriggerTimeOfDay, $LastRunTime, [int]$WindowMinutes = 5) {
  # Timer-vs-demand-vs-manual verdict (D00 T02 §16 items 7, 8): a
  # scheduler-parented start inside ±WindowMinutes of a defined daily
  # trigger time, with the scheduler's own LastRunTime agreeing,
  # reads timer. Trigger times ride HH:mm (daily occurrences); the
  # date and offset do not participate, so DST shifts read unknown,
  # never a false timer.
  $sched = @($ParentName, $GrandparentName) | Where-Object { ($_ -eq 'taskeng.exe') -or ($_ -eq 'svchost.exe') }
  $isSched = (@($sched).Count -gt 0)
  $inWindow = $false
  foreach ($tod in $TriggerTimeOfDay) {
    $m = [regex]::Match("$tod", '^(\d{2}):(\d{2})$')
    if (-not $m.Success) { continue }
    $t = New-TimeSpan -Hours ([int]$m.Groups[1].Value) -Minutes ([int]$m.Groups[2].Value)
    $diffMin = [math]::Abs(($RunStart.TimeOfDay - $t).TotalMinutes)
    if ($diffMin -gt 720) { $diffMin = 1440 - $diffMin }
    if ($diffMin -le $WindowMinutes) { $inWindow = $true }
  }
  $lastOk = $false
  if (($null -ne $LastRunTime) -and ($LastRunTime -is [datetime]) -and ($LastRunTime.Year -gt 1900)) {
    if ([math]::Abs(($RunStart - $LastRunTime).TotalMinutes) -le $WindowMinutes) { $lastOk = $true }
  }
  if ([string]::IsNullOrWhiteSpace("$ParentName$GrandparentName")) { return [pscustomobject]@{ Verdict = 'unknown'; Line = 'launch: unknown (no parent chain captured)' } }
  if ($isSched -and $inWindow -and $lastOk) { return [pscustomobject]@{ Verdict = 'timer'; Line = "launch: timer (scheduler-parented $ParentName/$GrandparentName, start $($RunStart.ToString('HH:mm')) in trigger window, LastRunTime agrees)" } }
  if ($isSched) { return [pscustomobject]@{ Verdict = 'demand'; Line = "launch: demand-or-recovered (scheduler-parented $ParentName/$GrandparentName outside trigger windows; operator, API, or StartWhenAvailable recovery: see LastRunTime)" } }
  return [pscustomobject]@{ Verdict = 'manual'; Line = "launch: manual (parent $ParentName)" }
}

function Write-RunJournal([string]$NightDir, [string]$Stamp, [int]$ProcId, [datetime]$Started, [string]$Phase) {
  # Atomically records this run's phase (D00 T02 §16 items 4, 12):
  # started at launch, core at core-verdict publication, final at
  # final publication. Next-start recovery reads the last-known
  # phase of any run that never reached final.
  $obj = [pscustomobject]@{ stamp = $Stamp; pid = $ProcId; started = $Started.ToString('o'); phase = $Phase }
  Write-AtomicReport @((ConvertTo-Json $obj -Compress)) (Join-Path $NightDir 'current.json')
}

function Read-RunJournal([string]$NightDir) {
  # Reads the run journal, failing closed on any malformed shape: a
  # journal that cannot prove its stamp, process, start, and phase
  # reads corrupt, and corruption with no final report reads dead.
  $p = Join-Path $NightDir 'current.json'
  if (-not (Test-Path $p)) { return [pscustomobject]@{ Exists = $false; Ok = $true; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = '' } }
  $o = $null
  try { $o = Get-Content $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return [pscustomobject]@{ Exists = $true; Ok = $false; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = "journal unreadable: $_" } }
  if (($null -eq $o.stamp) -or ("$($o.stamp)" -eq '')) { return [pscustomobject]@{ Exists = $true; Ok = $false; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = 'journal shape wrong (stamp missing)' } }
  if (($null -eq $o.phase) -or ("$($o.phase)" -eq '')) { return [pscustomobject]@{ Exists = $true; Ok = $false; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = 'journal shape wrong (phase missing)' } }
  $st = $null
  try { $st = [datetime]$o.started } catch { return [pscustomobject]@{ Exists = $true; Ok = $false; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = 'journal shape wrong (start unparseable)' } }
  $id = 0
  try { $id = [int]$o.pid } catch { return [pscustomobject]@{ Exists = $true; Ok = $false; Stamp = ''; Pid = 0; Started = $null; Phase = ''; Error = 'journal shape wrong (pid unparseable)' } }
  return [pscustomobject]@{ Exists = $true; Ok = $true; Stamp = "$($o.stamp)"; Pid = $id; Started = $st; Phase = "$($o.phase)"; Error = '' }
}

function Test-JournalProcessAlive([int]$ProcId, [datetime]$Started) {
  # PID-reuse guard: the journaled process counts alive only when a
  # process with that PID started near the journaled start instant.
  # The tolerance is deliberately narrow (2 min) so a clock jump
  # risks a spurious recovery record, never a swallowed dead run.
  try {
    $p = Get-Process -Id $ProcId -ErrorAction Stop
    return ([math]::Abs(($p.StartTime - $Started).TotalMinutes) -lt 2)
  } catch { return $false }
}

function Find-DeadRun([string]$NightDir, [string]$CurrentStamp) {
  # Next-start dead-run probe (D00 T02 §16 items 4, 12): a journaled
  # run that is not this run, never reached final, left no final
  # archive, and owns no live process died mid-flight. A same-day
  # supervisor tombstone at the fixed path links as the same
  # abandoned run instead of double-reporting the incident.
  $j = Read-RunJournal $NightDir
  if (-not $j.Exists) { return [pscustomobject]@{ Dead = $false; Stamp = ''; Phase = ''; Started = $null; Evidence = @(); Tombstone = ''; Reason = 'no journal: first run on record' } }
  if (-not $j.Ok) { return [pscustomobject]@{ Dead = $true; Stamp = ''; Phase = 'unknown (journal unreadable)'; Started = $null; Evidence = @('current.json (unparseable)'); Tombstone = ''; Reason = $j.Error } }
  if ($j.Stamp -eq $CurrentStamp) { return [pscustomobject]@{ Dead = $false; Stamp = ''; Phase = ''; Started = $null; Evidence = @(); Tombstone = ''; Reason = 'journal names this run' } }
  if ($j.Phase -eq 'final') { return [pscustomobject]@{ Dead = $false; Stamp = ''; Phase = ''; Started = $null; Evidence = @(); Tombstone = ''; Reason = "prior run $($j.Stamp) reached final" } }
  $arch = Join-Path $NightDir "morning-$($j.Stamp).md"
  if (Test-Path $arch) {
    $txt = (@(Get-Content $arch -TotalCount 10 -ErrorAction SilentlyContinue) -join "`n")
    if ($txt -like '*Status: final*') { return [pscustomobject]@{ Dead = $false; Stamp = ''; Phase = ''; Started = $null; Evidence = @(); Tombstone = ''; Reason = "final archive landed for $($j.Stamp) (journal phase lagged)" } }
  }
  if (Test-JournalProcessAlive $j.Pid $j.Started) { return [pscustomobject]@{ Dead = $false; Stamp = ''; Phase = ''; Started = $null; Evidence = @(); Tombstone = ''; Reason = "journaled process $($j.Pid) still alive: possible concurrent run, recovery refused" } }
  $ev = @()
  $sdir = Join-Path $NightDir $j.Stamp
  if (Test-Path $sdir) {
    $ev += "stamp dir $($j.Stamp)"
    $trx = @(Get-ChildItem $sdir -Filter '*.trx' -ErrorAction SilentlyContinue).Count
    $ev += "$trx trx files"
  } else { $ev += "no stamp dir $($j.Stamp)" }
  $tomb = ''
  if ($j.Stamp.Length -ge 10) {
    $fixed = Join-Path $NightDir ("morning-" + $j.Stamp.Substring(0, 10) + ".md")
    if (Test-Path $fixed) {
      $ftxt = (@(Get-Content $fixed -TotalCount 10 -ErrorAction SilentlyContinue) -join "`n")
      if ($ftxt -like '*Status: supervisor tombstone*') { $tomb = $fixed }
    }
  }
  return [pscustomobject]@{ Dead = $true; Stamp = $j.Stamp; Phase = $j.Phase; Started = $j.Started; Evidence = $ev; Tombstone = $tomb; Reason = "journaled run $($j.Stamp) died at phase $($j.Phase)" }
}

function Format-RecoveryRecord([string]$DeadStamp, [string]$Phase, $Started, [string[]]$Evidence, [string]$Tombstone, [string]$RecoveredBy) {
  # RED recovery record for a dead previous run (D00 T02 §16 item 4):
  # last-known phase plus evidence, linked to the supervisor
  # tombstone when it covers the same abandoned run.
  $lines = @("# Recovery record: $DeadStamp", 'Status: recovered-dead-run', '', "- Last-known phase: $Phase", "- Started: $Started", "- Evidence: $($Evidence -join '; ')")
  if ($Tombstone -ne '') { $lines += "- Tombstone: $Tombstone (same abandoned run; this record carries the phase detail the tombstone lacks)" }
  $lines += "- Recovered by: $RecoveredBy"
  $lines += '- Verdict: RED (previous run died mid-flight; see evidence)'
  return $lines
}

function Test-RunIdConsistency([string]$NightDir, [string]$Stamp, [int]$ProcId, [string[]]$IncidentLines, $PriorPointer) {
  # Run-identity consistency across the five evidence surfaces (D00
  # T02 §16 item 14): directories, archives, loser reports, incidents,
  # and pointers. Any break reds the run: evidence that cannot prove
  # which run it belongs to proves nothing. $PriorPointer is the
  # pre-flight Read-LatestReport result (or $null on a first run):
  # core publication repoints latest.txt at the current stamp, so a
  # late re-read would fault on the not-yet-published archive; the
  # inherited pointer verifies instead, and the next run verifies
  # this run's archive the same way (chain of custody).
  $breaks = @()
  if (-not (Test-Path (Join-Path $NightDir $Stamp))) { $breaks += "directory missing: $Stamp" }
  if ("$Stamp-pid$ProcId" -notmatch '^\d{4}-\d{2}-\d{2}-\d{6}-pid\d+$') { $breaks += "identity malformed: $Stamp-pid$ProcId" }
  if ($null -ne $PriorPointer) {
    if (-not $PriorPointer.Ok) { $breaks += "pointer continuity: $($PriorPointer.Error)" }
  }
  $self = "loser-$Stamp-pid$ProcId.md"
  $twins = @(Get-ChildItem $NightDir -Filter "loser-$Stamp-pid*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $self })
  foreach ($t in $twins) { $breaks += "same-second twin loser report: $($t.Name)" }
  $seen = @{}
  foreach ($ln in $IncidentLines) {
    $m = [regex]::Match($ln, '^- (INC-[0-9a-f]{8}) `([^`]+)`')
    if (-not $m.Success) { $breaks += "incident line malformed: $ln"; continue }
    $id = $m.Groups[1].Value; $test = $m.Groups[2].Value
    if ($seen.ContainsKey($id) -and ($seen[$id] -ne $test)) { $breaks += "incident id collision: $id on $($seen[$id]) and $test" }
    else { $seen[$id] = $test }
  }
  if ($breaks.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Breaks = $breaks } }
  return [pscustomobject]@{ Ok = $true; Breaks = @() }
}

function Test-PhaseDurations([string]$BaselinePath, [hashtable]$Actual) {
  # Duration baseline compare (D00 T02 §16 item 14): every measured
  # phase reads against its baseline plus warning threshold.
  # Over-warn surfaces as a WARN line, never a red: slowness is
  # signal, not failure. A missing baseline file reds (the tree
  # ships it); an unbaselined phase notes once without failing.
  if (-not (Test-Path $BaselinePath)) { return [pscustomobject]@{ Ok = $false; Lines = @("durations: RED (baseline file missing: $BaselinePath)") } }
  $base = $null
  try { $base = Get-Content $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return [pscustomobject]@{ Ok = $false; Lines = @("durations: RED (baseline unreadable: $_)") } }
  $lines = @()
  foreach ($k in @($Actual.Keys | Sort-Object)) {
    $v = [int]$Actual[$k]
    $entry = $null
    try { $entry = $base.phases.$k } catch { $entry = $null }
    if ($null -eq $entry) { $lines += "durations: $k ${v}s (no baseline; first measurement)"; continue }
    $b = [int]$entry.baseline; $w = [int]$entry.warn
    if ($v -gt $w) { $lines += "durations: $k ${v}s WARN over warn ${w}s (baseline ${b}s)" }
    else { $lines += "durations: $k ${v}s (baseline ${b}s, warn ${w}s)" }
  }
  return [pscustomobject]@{ Ok = $true; Lines = $lines }
}

# --- D00 T02 §17: notify, trend, and machine-readable results ---

function Format-ToastXml([string]$Title, [string[]]$Lines) {
  # Builds the toast payload (D00 T02 §17 item 1): title plus body
  # lines, XML-escaped, capped at seven (counts, trigger, top
  # incident, overdue, unacked, report, fail-closed reason: the
  # emitter's full line set; the seventh only exists when the own
  # result failed validation). Pure: fixtures pin the escaping plus
  # shape; Send-NightlyToast delivers it.
  $parts = @('<toast><visual><binding template="ToastGeneric">')
  $parts += '  <text>' + [System.Security.SecurityElement]::Escape($Title) + '</text>'
  foreach ($ln in @($Lines | Select-Object -First 7)) { $parts += '  <text>' + [System.Security.SecurityElement]::Escape($ln) + '</text>' }
  $parts += '</binding></visual></toast>'
  return ($parts -join "`n")
}

function Send-NightlyToast([string]$Title, [string[]]$Lines) {
  # Delivers the morning notification (D00 T02 §17 item 1) through a
  # Windows toast under the ScratchPad.Nightly id. Best-effort:
  # notification never reds a run, so any failure returns false
  # instead of throwing. Delivery proves via Notification Center
  # history (see the §17 item-1 proof).
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    $doc = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml((Format-ToastXml $Title $Lines))
    $t = New-Object -TypeName Windows.UI.Notifications.ToastNotification -ArgumentList $doc
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ScratchPad.Nightly').Show($t)
    return $true
  } catch { return $false }
}

function Get-EnvironmentBlock([string]$WindowSpec) {
  # Captures the environment dimensions (D00 T02 §17 item 9): OS,
  # shells, session, topology, DPI, adapters, and active settings.
  # Every probe fails soft to an unknown note: dimensions inform,
  # never vote. Scratch-proven (live capture); the trend renderer
  # formats whatever the block carries.
  $os = 'unknown'; try { $os = [Environment]::OSVersion.Version.ToString() } catch { }
  $ps = 'unknown'; try { $ps = $PSVersionTable.PSVersion.ToString() } catch { }
  $dn = 'unknown'; try { $dn = ((dotnet --version 2>$null) | Out-String).Trim() } catch { }
  $who = "$env:USERNAME/$env:SESSIONNAME"
  $topo = 'unknown'
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $topo = (([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.DeviceName) $($_.Bounds.Width)x$($_.Bounds.Height)+$($_.Bounds.X)+$($_.Bounds.Y)$(if ($_.Primary) { ' primary' })" }) -join '; ')
  } catch { $topo = 'unknown (forms unavailable)' }
  $dpi = 'unknown'
  try {
    if (-not ([System.Management.Automation.PSTypeName]'DpiProbe').Type) {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DpiProbe {
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
  [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr hmon, int type, out uint x, out uint y);
  public struct POINT { public int X; public int Y; }
}
'@ -ErrorAction Stop
    }
    $pt = New-Object -TypeName 'DpiProbe+POINT'; $pt.X = 64; $pt.Y = 64
    $hm = [DpiProbe]::MonitorFromPoint($pt, 2)
    $dx = [uint32]0; $dy = [uint32]0
    if (([DpiProbe]::GetDpiForMonitor($hm, 0, [ref]$dx, [ref]$dy) -eq 0) -and ($dx -gt 0)) { $dpi = "primary ${dx}x${dy}" } else { $dpi = 'unknown (shcore refused)' }
  } catch { $dpi = 'unknown (probe failed)' }
  $adapters = 'unknown'
  try { $adapters = ((Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name }) -join '; ') } catch { }
  $settings = "BACKGROUND=$env:SCRATCHPAD_BACKGROUND WINDOW=$env:SCRATCHPAD_INTERACTIVE_WINDOW SPEC=$WindowSpec"
  # Allowlisted and redacted at capture (D00 T02 §25 item 10).
  return (Protect-EnvironmentBlock ([pscustomobject]@{ os = $os; powershell = $ps; dotnet = $dn; session = $who; topology = $topo; dpi = $dpi; adapters = $adapters; settings = $settings }))
}

function Test-ResultFile([string]$Path, [switch]$RequireLifecycle) {
  # Validates a versioned machine-readable result (D00 T02 §17 item
  # 6): JSON parses, version is 1, identity fields read, verdict is
  # known, and green/red verdicts carry shaped legs plus soak plus
  # env (presence alone is not enough: an empty block would satisfy
  # the readers with nothing). Stood-down and cancelled verdicts
  # carry the minimal shape.
  $o = $null
  try { $o = Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return [pscustomobject]@{ Ok = $false; Error = "result unreadable: $_" } }
  $v = -1
  try { $v = [int]$o.version } catch { return [pscustomobject]@{ Ok = $false; Error = 'result version not a number' } }
  if ($v -ne 1) { return [pscustomobject]@{ Ok = $false; Error = "result version $v (want 1)" } }
  foreach ($f in @('stamp', 'day', 'identity', 'verdict', 'exit')) {
    if (($null -eq $o.$f) -or ("$($o.$f)" -eq '')) { return [pscustomobject]@{ Ok = $false; Error = "result missing $f" } }
  }
  if (@('green', 'red', 'stood-down', 'cancelled') -notcontains "$($o.verdict)") { return [pscustomobject]@{ Ok = $false; Error = "unknown verdict $($o.verdict)" } }
  $ex = 0
  try { $ex = [int]$o.exit } catch { return [pscustomobject]@{ Ok = $false; Error = 'result exit not a number' } }
  if ((@('green', 'stood-down') -contains "$($o.verdict)") -and ($ex -ne 0)) { return [pscustomobject]@{ Ok = $false; Error = "result verdict $($o.verdict) contradicts exit $ex" } }
  if ((@('red', 'cancelled') -contains "$($o.verdict)") -and ($ex -eq 0)) { return [pscustomobject]@{ Ok = $false; Error = "result verdict $($o.verdict) contradicts exit $ex" } }
  if (@('green', 'red') -contains "$($o.verdict)") {
    foreach ($f in @('legs', 'soak', 'env', 'timings')) {
      if ($null -eq $o.$f) { return [pscustomobject]@{ Ok = $false; Error = "result missing $f" } }
    }
    foreach ($leg in @('run-a', 'run-b', 'interactive')) {
      $g = $null
      try { $g = $o.legs.$leg } catch { }
      if ($null -eq $g) { return [pscustomobject]@{ Ok = $false; Error = "result legs missing $leg" } }
      try { if ($null -eq $g.ran) { return [pscustomobject]@{ Ok = $false; Error = "result legs.$leg missing ran" } } } catch { return [pscustomobject]@{ Ok = $false; Error = "result legs.$leg missing ran" } }
    }
    if (("$($o.soak.verdict)" -eq '') -or (@('green', 'red', 'skipped') -notcontains "$($o.soak.verdict)")) { return [pscustomobject]@{ Ok = $false; Error = 'result soak verdict unknown' } }
    # The block must carry at least one allowlisted field (an empty
    # block would satisfy the readers with nothing); an individual
    # missing field reads unknown (D00 T02 §25 item 8, R2-F1).
    $present = @(@($o.env.PSObject.Properties.Name) | Where-Object { $script:EnvFields -contains $_ })
    if ($present.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Error = 'result env unproven (no allowlisted field)' } }
    # Every consumed env field, with unknown-state semantics (D00 T02 §25 item 8).
    $ef = Test-EnvironmentFields $o.env
    if (-not $ef.Ok) { return [pscustomobject]@{ Ok = $false; Error = "result $($ef.Error)" } }
  }
  # Incident lifecycle block (D00 T02 section 30 item 10): required on
  # the nightly's own green/red results, validated wherever present.
  $hasLife = @($o.PSObject.Properties.Name) -contains 'incidentLifecycle'
  if ($RequireLifecycle -and (@('green', 'red') -contains "$($o.verdict)") -and (-not $hasLife)) { return [pscustomobject]@{ Ok = $false; Error = 'result missing incidentLifecycle' } }
  if ($hasLife) {
    foreach ($row in @($o.incidentLifecycle)) {
      if ($null -eq $row) { return [pscustomobject]@{ Ok = $false; Error = 'result incidentLifecycle has a null row' } }
      $names = @($row.PSObject.Properties.Name)
      foreach ($f in @('id', 'state', 'owner', 'occurrences', 'passStreak', 'contract')) {
        if (($names -notcontains $f) -or ("$($row.$f)" -eq '')) { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle row $($row.id) missing $f" } }
      }
      if ("$($row.id)" -notmatch '^INC-[0-9a-f]{8}$') { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle id malformed: $($row.id)" } }
      if (@('open', 'closed') -notcontains "$($row.state)") { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) state $($row.state)" } }
      # Values, not only presence (section 30 R1-F2): counts are whole
      # numbers (occurrences at least 1), the contract is the one this
      # code mints, and optional dates and findings keep their shapes.
      if ("$($row.occurrences)" -notmatch '^[1-9]\d*$') { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) occurrences '$($row.occurrences)' is not a positive whole number" } }
      if ("$($row.passStreak)" -notmatch '^\d+$') { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) passStreak '$($row.passStreak)' is not a whole number" } }
      if ("$($row.contract)" -ne 'v2') { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) contract '$($row.contract)' unsupported (want v2)" } }
      if (("$($row.due)" -ne '') -and ("$($row.due)" -notmatch '^\d{4}-\d{2}-\d{2}$')) { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) due '$($row.due)' is not YYYY-MM-DD" } }
      if (("$($row.finding)" -ne '') -and ("$($row.finding)" -notmatch '^(D\d{2} T\d{2} \u00A7\d+|[0-9a-f]{7,40})$')) { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycle $($row.id) finding '$($row.finding)' is not a section ref or commit" } }
    }
  }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

function Read-ResultFile([string]$Path) {
  # Reads a result file, returning $null on any failure (callers
  # that need the reason use Test-ResultFile first).
  try { return (Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Get-SchedulerState([string]$TrackedXmlPath) {
  # Live scheduler read (D00 T02 §17 item 7; the §16 pre-flight
  # logic refactored so the loser path shares it): COM runtime
  # state plus live-vs-tracked drift on triggers, action args, and
  # time limit. Impure (COM plus files); scratch-proven. Pure
  # verdicts stay in Test-MissingStart plus Test-TimerLaunch.
  $st = [pscustomobject]@{ Ok = $false; Error = ''; Enabled = $true; LastRunTime = $null; LastResult = ''; Registered = $null; Action = 'unknown'; TriggerTODs = @(); Drift = @() }
  try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $live = $svc.GetFolder('\ScratchPad').GetTask('Nightly UI')
    $st.Enabled = [bool]$live.Enabled
    $st.LastRunTime = $live.LastRunTime
    $st.LastResult = "$($live.LastTaskResult)"
    try { $st.Registered = [datetime]$live.Definition.RegistrationInfo.Date } catch { }
    $liveXml = Read-TaskXml $live.Definition.XmlText
    $trackedXml = Read-TaskXml (Get-Content $TrackedXmlPath -Raw -ErrorAction Stop)
    if (-not $liveXml.Ok) { $st.Drift += "live definition unreadable ($($liveXml.Error))" }
    elseif (-not $trackedXml.Ok) { $st.Drift += "tracked definition unreadable ($($trackedXml.Error))" }
    else {
      $lb = @($liveXml.Triggers | ForEach-Object { "$($_.Kind)|$($_.StartBoundary)|$($_.DaysInterval)|$($_.Enabled)" } | Sort-Object) -join ';'
      $tb = @($trackedXml.Triggers | ForEach-Object { "$($_.Kind)|$($_.StartBoundary)|$($_.DaysInterval)|$($_.Enabled)" } | Sort-Object) -join ';'
      if ($lb -ne $tb) { $st.Drift += 'trigger definition drifted' }
      if (($liveXml.Command -ne $trackedXml.Command) -or ($liveXml.Arguments -ne $trackedXml.Arguments)) { $st.Drift += 'action args drifted' }
      if ($liveXml.ExecutionTimeLimit -ne $trackedXml.ExecutionTimeLimit) { $st.Drift += 'time limit drifted' }
      $st.Action = "$($liveXml.Command) $($liveXml.Arguments)".Trim()
      foreach ($t in @($liveXml.Triggers | Where-Object { $_.Enabled })) {
        try { $st.TriggerTODs += ([datetime]$t.StartBoundary).ToString('HH:mm') } catch { }
      }
    }
    $st.Ok = $true
  } catch { $st.Error = "$_"; $st.Ok = $false }
  return $st
}

function Classify-NightlyOutcome($Result) {
  # Routes a night to one alert class (D00 T02 §17 item 8): test,
  # gate, enforcement, infrastructure, degraded-soak, recovery, or
  # scheduler-no-start. Precedence (documented in docs/testing.md):
  # scheduler-no-start beats infrastructure beats recovery beats
  # gate beats enforcement beats test beats degraded-soak; green
  # reads green and stood-down reads stood-down (no route). Reads
  # the result object the emitter writes (backfills included);
  # unknown shapes read infrastructure (fail closed: an unreadable
  # night routes to a human, never to silence).
  $verdict = ''
  try { $verdict = "$($Result.verdict)" } catch { }
  if (@('green', 'red', 'stood-down', 'cancelled') -notcontains $verdict) { return [pscustomobject]@{ Class = 'infrastructure'; Route = 'result unreadable: route to a human' } }
  if ($verdict -eq 'stood-down') { return [pscustomobject]@{ Class = 'stood-down'; Route = 'none (holder owns the proof)' } }
  $voted = $false
  try { $voted = [bool]$Result.scheduler.voted } catch { }
  $faults = @()
  try { $faults = @($Result.scheduler.faults) } catch { }
  $fj = $faults -join ';'
  if ($voted -and (($fj -like '*missing start*') -or ($fj -like '*task disabled*'))) { return [pscustomobject]@{ Class = 'scheduler-no-start'; Route = 'check task enabled/fires; manual backup covers the night' } }
  $be = ''
  try { $be = "$($Result.buildError)" } catch { }
  $omOk = $true
  try { $omOk = [bool]$Result.omissionOk } catch { }
  $killed = $false; $cut = $false; $gateRed = $false; $gateNull = $false
  foreach ($leg in @('run-a', 'run-b')) {
    $g = $null
    try { $g = $Result.legs.$leg } catch { }
    if ($null -eq $g) { continue }
    try { if (($null -ne $g.ran) -and (-not [bool]$g.ran)) { continue } } catch { }
    try { if ([bool]$g.killed) { $killed = $true } } catch { }
    try { if ([bool]$g.cut) { $cut = $true } } catch { }
    try { if ($null -eq $g.gate) { $gateNull = $true } elseif ([int]$g.gate -ne 0) { $gateRed = $true } } catch { $gateNull = $true }
  }
  if (($be -ne '') -or (-not $omOk) -or $killed -or $cut -or $gateNull -or ($voted -and (($fj -like '*drift*') -or ($fj -like '*unavailable*')))) { return [pscustomobject]@{ Class = 'infrastructure'; Route = 'check build/tooling/schedule; re-drive the night' } }
  $rec = 'none'
  try { $rec = "$($Result.recovered)" } catch { }
  if (($rec -ne '') -and ($rec -ne 'none')) { return [pscustomobject]@{ Class = 'recovery'; Route = 'review the dead-run record' } }
  if ($gateRed) { return [pscustomobject]@{ Class = 'gate'; Route = 'inspect foreground holds in the gate log' } }
  $enf = $false
  try { $enf = [bool]$Result.legs.interactive.enforcementRed } catch { }
  if ($enf) { return [pscustomobject]@{ Class = 'enforcement'; Route = 'quarantine or fix the bare skips' } }
  $failed = 0
  foreach ($leg in @('run-a', 'run-b', 'interactive')) {
    $o = $null
    try { $o = $Result.legs.$leg } catch { }
    if ($null -eq $o) { continue }
    try { if (($null -ne $o.ran) -and (-not [bool]$o.ran)) { continue } } catch { }
    try { $failed += [int]$o.failed } catch { }
  }
  if ($failed -gt 0) { return [pscustomobject]@{ Class = 'test'; Route = 'file findings per failure (triage)' } }
  $soakV = ''
  try { $soakV = "$($Result.soak.verdict)" } catch { }
  if ($soakV -eq 'red') { return [pscustomobject]@{ Class = 'degraded-soak'; Route = 'soak-only red: quarantine-or-fix per the flake procedure' } }
  if ($verdict -eq 'green') { return [pscustomobject]@{ Class = 'green'; Route = 'none' } }
  return [pscustomobject]@{ Class = 'infrastructure'; Route = 'red without a classified cause: route to a human' }
}

function Get-NightKey([datetime]$LocalStart) {
  # The night a run serves (D00 T02 §25 item 3): a run starting between
  # noon on D-1 and 11:59 on D belongs to night D, the morning its
  # report lands, so a manual run at 23:50 groups with the next morning
  # and a 02:30 timer run with its own date. The caller passes the start
  # in the run's own recorded timezone, so a later timezone move never
  # regroups history.
  if ($LocalStart.Hour -ge 12) { return $LocalStart.Date.AddDays(1).ToString('yyyy-MM-dd') }
  return $LocalStart.Date.ToString('yyyy-MM-dd')
}

function Get-ResultNight($Result) {
  # Grouping key for a result: its recorded night, else the night
  # derived from startUtc plus its tz offset, else the legacy day.
  try { if ("$($Result.night)" -match '^\d{4}-\d{2}-\d{2}$') { return "$($Result.night)" } } catch { }
  try {
    if (("$($Result.startUtc)" -ne '') -and ("$($Result.tz)" -match '^[+-]\d{2}:\d{2}$')) {
      # Windows PowerShell's ConvertFrom-Json turns ISO strings into
      # DateTime values; use those directly (a culture-formatted string
      # would misparse on a day-first machine), else parse invariantly.
      $raw = $Result.startUtc
      if ($raw -is [datetime]) { $u = if ($raw.Kind -eq [System.DateTimeKind]::Local) { $raw.ToUniversalTime() } else { $raw } }
      else { $u = [datetime]::Parse("$raw", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal) }
      $sign = if ("$($Result.tz)".StartsWith('-')) { -1 } else { 1 }
      $off = [TimeSpan]::Parse("$($Result.tz)".Substring(1))
      return (Get-NightKey ($u + ([TimeSpan]::FromTicks($sign * $off.Ticks))))
    }
  } catch { }
  return "$($Result.day)"
}

function Test-IsBackfill($Result) {
  # A backfilled result reconstructs a past night mechanically; its
  # fields carry provenance and it never poses as a native measurement.
  try { if ($null -ne $Result.provenance) { return $true } } catch { }
  try { if ("$($Result.note)" -like 'backfilled*') { return $true } } catch { }
  try { if ([bool]$Result.metricsBackfill) { return $true } } catch { }
  return $false
}

function Get-Percentile($Values, [double]$P) {
  # Nearest-rank percentile over numbers; $null for an empty set.
  $v = @(@($Values) | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
  if ($v.Count -eq 0) { return $null }
  $idx = [int][math]::Ceiling(($P / 100.0) * $v.Count) - 1
  if ($idx -lt 0) { $idx = 0 }
  return $v[$idx]
}

# Environment allowlist (D00 T02 §25 items 8 and 10): the eight
# dimensions the trend and the report consume, plus a backfill's basis
# note. Anything else is dropped at capture and refused by the validator.
$script:EnvFields = @('os', 'powershell', 'dotnet', 'session', 'topology', 'dpi', 'adapters', 'settings')
$script:EnvRules = [ordered]@{
  os         = '^\d+(\.\d+){1,3}$'
  powershell = '^\d+\.\d+(\.\d+){0,2}$'
  dotnet     = '^\d+\.\d+\.\d+([-.][0-9A-Za-z.]+)?$'
  session    = '^[^/\\]*/[^/\\]*$'
  topology   = '^\\\\\.\\DISPLAY\d+ \d+x\d+\+-?\d+\+-?\d+( primary)?(; \\\\\.\\DISPLAY\d+ \d+x\d+\+-?\d+\+-?\d+( primary)?)*$'
  dpi        = '^primary \d+x\d+$'
  adapters   = '^[^\r\n]{1,200}$'
  settings   = '^BACKGROUND=\S* WINDOW=\S* SPEC=\S*$'
}

function Protect-EnvironmentBlock($Env) {
  # Capture-time allowlist plus redaction (D00 T02 §25 item 10): only the
  # eight dimensions survive, a secret-shaped value is replaced by the
  # names of the patterns it hit, and drive or UNC paths collapse to
  # [path] (display device names like \\.\DISPLAY1 are not paths).
  $out = [ordered]@{}
  foreach ($k in $script:EnvFields) {
    $v = ''
    try { $v = "$($Env.$k)" } catch { }
    if ($v -eq '') { $v = 'unknown' }
    $hits = @(Test-CaptureSecrets $v)
    if ($hits.Count -gt 0) { $v = "[redacted: $($hits -join ', ')]" }
    # A path runs to the next field boundary (a ' KEY=' token, ';', '|',
    # or the end), spaces included, so a path with spaces never leaks
    # its tail (R1-F1).
    $v = [regex]::Replace($v, '(?<![\\.])\b[A-Za-z]:\\.*?(?=( [A-Z][A-Z0-9_]*=)|[;|]|$)', '[path]')
    $v = [regex]::Replace($v, '\\\\(?!\.\\)[^\\;|]+\\.*?(?=( [A-Z][A-Z0-9_]*=)|[;|]|$)', '[path]')
    $out[$k] = $v
  }
  return [pscustomobject]$out
}

function Test-EnvironmentFields($Env) {
  # Result-side environment rules (D00 T02 §25 item 8): every consumed
  # field either matches its rule or reads unknown ('unknown' or
  # 'unknown (reason)'); a missing field reads unknown (older results
  # predate the rules); an unlisted key or a secret-shaped value fails.
  if ($null -eq $Env) { return [pscustomobject]@{ Ok = $false; Error = 'env missing' } }
  foreach ($name in @($Env.PSObject.Properties.Name)) {
    if (($script:EnvFields -notcontains $name) -and ($name -ne 'basis')) { return [pscustomobject]@{ Ok = $false; Error = "env field not allowlisted: $name" } }
    # Every allowlisted field, the backfill basis note included (R1-F2).
    if (@(Test-CaptureSecrets "$($Env.$name)").Count -gt 0) { return [pscustomobject]@{ Ok = $false; Error = "env $name carries a secret-shaped value" } }
  }
  foreach ($k in $script:EnvFields) {
    if (@($Env.PSObject.Properties.Name) -notcontains $k) { continue }
    $v = "$($Env.$k)"
    if (@(Test-CaptureSecrets $v).Count -gt 0) { return [pscustomobject]@{ Ok = $false; Error = "env $k carries a secret-shaped value" } }
    if (($v -eq 'unknown') -or ($v -like 'unknown (*') -or ($v -like '`[redacted: *')) { continue }
    if ($v -notmatch $script:EnvRules[$k]) { return [pscustomobject]@{ Ok = $false; Error = "env $k malformed: '$v'" } }
  }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

function ConvertTo-MetricsRow($Result) {
  # The compact long-term row (D00 T02 §25 item 7): everything the trend
  # series need, small enough to keep forever after the raw evidence
  # prunes at 30 days.
  $num = { param($x) if ($null -eq $x) { $null } else { try { [int]$x } catch { $null } } }
  $legs = [ordered]@{}
  foreach ($leg in @('run-a', 'run-b', 'interactive')) {
    $o = $null
    try { $o = $Result.legs.$leg } catch { }
    if ($null -eq $o) { continue }
    $legs[$leg] = [ordered]@{ ran = $(try { [bool]$o.ran } catch { $false }); passed = (& $num $o.passed); failed = (& $num $o.failed); skipped = (& $num $o.skipped); gate = $(try { $o.gate } catch { $null }); killed = $(try { [bool]$o.killed } catch { $false }); cut = $(try { [bool]$o.cut } catch { $false }); testSeconds = $(try { & $num $o.testSeconds } catch { $null }) }
  }
  $incs = @()
  foreach ($ln in @($Result.incidents)) { $m = [regex]::Match("$ln", '(INC-[0-9a-f]{8}) `([^`]+)`'); if ($m.Success) { $incs += "- $($m.Groups[1].Value) ``$($m.Groups[2].Value)``" } }
  return [ordered]@{
    schema = 'metrics/1'; identity = "$($Result.identity)"; stamp = "$($Result.stamp)"; day = "$($Result.day)"; night = (Get-ResultNight $Result)
    verdict = "$($Result.verdict)"; launch = "$($Result.launch)"; simulated = $(try { [bool]$Result.simulated } catch { $false }); backfill = (Test-IsBackfill $Result)
    legs = $legs; soak = [ordered]@{ verdict = $(try { "$($Result.soak.verdict)" } catch { '' }) }
    incidents = $incs; reserve = $(try { & $num $Result.reserve } catch { $null }); consumed = $(try { & $num $Result.consumed } catch { $null })
    env = [ordered]@{ os = $(try { "$($Result.env.os)" } catch { 'unknown' }); dpi = $(try { "$($Result.env.dpi)" } catch { 'unknown' }) }
    provenance = $(try { $Result.provenance } catch { $null })
  }
}

function Sync-MetricsStore([string]$Path, $Results) {
  # Keeps one current row per result identity (D00 T02 §25 item 7). The
  # store is append-only JSON lines in ignored scratch beside the runs:
  # a result whose computed row differs from its stored one (a new
  # field such as provenance, R2-F2) appends a revision, and the last
  # row per identity wins; an unchanged result appends nothing.
  # Retention prune never touches the store, so pruned nights keep
  # their metrics. Returns the current row per identity.
  $byId = [ordered]@{}
  $rawById = @{}
  if (Test-Path $Path) {
    foreach ($ln in [System.IO.File]::ReadAllLines($Path)) {
      if ($ln.Trim() -eq '') { continue }
      try { $r = $ln | ConvertFrom-Json; if ("$($r.identity)" -ne '') { $byId["$($r.identity)"] = $r; $rawById["$($r.identity)"] = $ln.Trim() } } catch { }
    }
  }
  $add = @()
  foreach ($res in @($Results)) {
    if ($null -eq $res) { continue }
    $id = "$($res.identity)"
    if ($id -eq '') { continue }
    $json = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $res)) -Depth 6 -Compress
    if ($rawById.ContainsKey($id) -and ($rawById[$id] -eq $json)) { continue }
    $rawById[$id] = $json
    $byId[$id] = ($json | ConvertFrom-Json)
    $add += $json
  }
  if ($add.Count -gt 0) { [System.IO.File]::AppendAllText($Path, (($add -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false))) }
  return @($byId.Values)
}

function ConvertFrom-MetricsRow($Row) {
  # A metrics-only night (its raw result pruned) rendered through the
  # same trend code, flagged so its row reads (metrics).
  $legs = [pscustomobject]@{}
  foreach ($prop in @($Row.legs.PSObject.Properties)) { $legs | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
  return [pscustomobject]@{ version = 1; identity = "$($Row.identity)"; stamp = "$($Row.stamp)"; day = "$($Row.day)"; night = "$($Row.night)"; verdict = "$($Row.verdict)"; launch = "$($Row.launch)"; simulated = [bool]$Row.simulated; legs = $legs; soak = [pscustomobject]@{ verdict = "$($Row.soak.verdict)" }; incidents = @($Row.incidents); reserve = $Row.reserve; consumed = $Row.consumed; env = [pscustomobject]@{ os = "$($Row.env.os)"; dpi = "$($Row.env.dpi)" }; fromMetrics = $true; metricsBackfill = [bool]$Row.backfill; provenance = $(try { $Row.provenance } catch { $null }); timings = $null; recovered = 'none'; omissionOk = $true; buildError = ''; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() } }
}

function Get-TrendAlerts($Rows, [int]$Baseline = 7) {
  # Regression alerts from the series (D00 T02 §25 item 6), over
  # canonical native nights only (series rule): RunA duration past 125%
  # of the median of the previous nights and at least 60 s over; the
  # executed pass rate 2 points below the baseline median; and an
  # incident id on the latest night that also hit one of the two
  # nights before it. Each alert quotes its baseline and delta.
  $alerts = @()
  $r = @(@($Rows) | Where-Object { $null -ne $_ })
  if ($r.Count -lt 2) { return $alerts }
  $latest = $r[-1]
  $prev = @($r[0..($r.Count - 2)] | Select-Object -Last $Baseline)
  $la = $null
  try { $la = [double]$latest.legs.'run-a'.testSeconds } catch { }
  $pa = @($prev | ForEach-Object { try { if ($null -ne $_.legs.'run-a'.testSeconds) { [double]$_.legs.'run-a'.testSeconds } } catch { } })
  if (($null -ne $la) -and ($pa.Count -gt 0)) {
    $med = Get-Percentile $pa 50
    if (($la -gt 1.25 * $med) -and (($la - $med) -ge 60)) {
      # A zero baseline has no percentage (R3-F1): the delta rides alone.
      $pct = if ($med -gt 0) { "+$([int][math]::Round(100 * ($la - $med) / $med))%" } else { "+$([int]($la - $med))s over a zero baseline" }
      $alerts += "- ALERT runa-duration: $([int]$la)s on $(Get-ResultNight $latest) vs baseline $([int]$med)s ($pct, median of $($pa.Count) night(s))"
    }
  }
  # An unproven night (a killed or budget-cut leg) contributes no rate,
  # matching the table's denominator rule (R1-F3).
  # Change-point (sustained shift): with at least 10 measured nights,
  # the median of the last 3 against the median of the 7 before them,
  # past 120% and at least 60 s over, so a step that one noisy night
  # would not trip still surfaces (D00 T02 §25 item 6, plan review PR8).
  $allSec = @($r | ForEach-Object { try { if ($null -ne $_.legs.'run-a'.testSeconds) { [double]$_.legs.'run-a'.testSeconds } } catch { } })
  if ($allSec.Count -ge 10) {
    $recentMed = Get-Percentile @($allSec | Select-Object -Last 3) 50
    $priorMed = Get-Percentile @($allSec | Select-Object -Last 10 | Select-Object -First 7) 50
    if (($recentMed -gt 1.2 * $priorMed) -and (($recentMed - $priorMed) -ge 60)) {
      $shift = if ($priorMed -gt 0) { "+$([int][math]::Round(100 * ($recentMed - $priorMed) / $priorMed))%" } else { "+$([int]($recentMed - $priorMed))s over a zero baseline" }
      $alerts += "- ALERT runa-shift: last 3 nights median $([int]$recentMed)s vs the prior 7 nights median $([int]$priorMed)s ($shift, sustained)"
    }
  }
  $rate = { param($x) $p = 0; $f = 0; $unproven = $false; foreach ($leg in @('run-a', 'run-b', 'interactive')) { try { $o = $x.legs.$leg; if (($null -ne $o) -and (($null -eq $o.ran) -or [bool]$o.ran)) { $p += [int]$o.passed; $f += [int]$o.failed; if ([bool]$o.killed -or [bool]$o.cut) { $unproven = $true } } } catch { } }; if ((-not $unproven) -and (($p + $f) -gt 0)) { 100.0 * $p / ($p + $f) } else { $null } }
  $lr = & $rate $latest
  $pr = @($prev | ForEach-Object { & $rate $_ } | Where-Object { $null -ne $_ })
  if (($null -ne $lr) -and ($pr.Count -gt 0)) {
    $med = Get-Percentile $pr 50
    if ($lr -lt ($med - 2)) { $alerts += "- ALERT pass-rate: $([math]::Round($lr, 1))% on $(Get-ResultNight $latest) vs baseline $([math]::Round($med, 1))% ($([math]::Round($lr - $med, 1)) points, median of $($pr.Count) night(s))" }
  }
  $aliasMap = Get-IncidentAliases $Rows
  $ids = { param($x) @(@($x.incidents) | ForEach-Object { $m = [regex]::Match("$_", '(INC-[0-9a-f]{8})'); if ($m.Success) { if ($aliasMap.ContainsKey($m.Groups[1].Value)) { $aliasMap[$m.Groups[1].Value] } else { $m.Groups[1].Value } } }) }
  $li = @(& $ids $latest)
  $recent = @($r[0..($r.Count - 2)] | Select-Object -Last 2)
  foreach ($id in ($li | Sort-Object -Unique)) {
    $hits = @($recent | Where-Object { (& $ids $_) -contains $id })
    if ($hits.Count -gt 0) { $alerts += "- ALERT recurring-flake: $id on $(Get-ResultNight $latest) and $(($hits | ForEach-Object { Get-ResultNight $_ }) -join ', ')" }
  }
  return $alerts
}

function Select-CanonicalRuns($Results) {
  # One canonical run per night (item 2): simulations, stood-down
  # losers, and results without a day never count; among the rest the
  # scheduler-launched run wins (latest stamp), then an on-demand task
  # run, then the latest manual run. Every other result of the day is
  # a retry, listed with its reason, so trends count nights, not
  # attempts. Returns a hashtable day -> Canonical (identity) plus
  # Others (identity -> reason).
  $byDay = @{}
  foreach ($r in @($Results)) {
    if ($null -eq $r) { continue }
    $day = Get-ResultNight $r
    if ($day -eq '') { continue }
    $id = "$($r.identity)"
    if ($id -eq '') { $id = "$($r.stamp)" }
    if (-not $byDay.ContainsKey($day)) { $byDay[$day] = [pscustomobject]@{ Canonical = ''; Others = [ordered]@{}; Pool = @() } }
    $slot = $byDay[$day]
    $sim = $false
    try { $sim = [bool]$r.simulated } catch { }
    if ($sim) { $slot.Others[$id] = 'simulation'; continue }
    if ("$($r.verdict)" -eq 'stood-down') { $slot.Others[$id] = 'stood-down loser'; continue }
    $rank = 1
    $launch = "$($r.launch)"
    if ($launch -eq 'timer') { $rank = 3 } elseif ($launch -eq 'demand') { $rank = 2 }
    $slot.Pool += [pscustomobject]@{ Id = $id; Rank = $rank; Stamp = "$($r.stamp)"; Launch = $launch }
  }
  foreach ($day in @($byDay.Keys)) {
    $slot = $byDay[$day]
    $pick = @($slot.Pool | Sort-Object @{ Expression = 'Rank'; Descending = $true }, @{ Expression = 'Stamp'; Descending = $true }) | Select-Object -First 1
    if ($null -ne $pick) {
      $slot.Canonical = $pick.Id
      foreach ($p in $slot.Pool) { if ($p.Id -ne $pick.Id) { $slot.Others[$p.Id] = "retry ($(if ($p.Launch -eq '') { 'unknown' } else { $p.Launch }) launch; canonical $($pick.Id))" } }
    }
  }
  return $byDay
}

function Get-IncidentAliases($Rows, [string]$V2Since = $script:IncidentContractV2Since) {
  # Identity alias map (D00 T02 section 30 item 5): incident ids minted
  # under contract v1 (results stamped before $V2Since) map to the v2 id
  # of the same failure, matched on test, phase, and failure class, so
  # the recurrence report joins across the contract bump. A v1 id maps
  # only when exactly one v2 id shares its triple (ambiguity keeps the
  # old id rather than guessing). Returns old id -> new id.
  $parse = { param($ln) $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)` x\d+ \(([^)]*)\): ?(.*)$'); if (-not $m.Success) { return $null }; $where = @($m.Groups[3].Value -split ',\s*')[0]; [pscustomobject]@{ Id = $m.Groups[1].Value; Triple = "$($m.Groups[2].Value)|$(Get-IncidentPhase $where)|$(Get-FailureClass $m.Groups[4].Value)" } }
  $v1 = @{}
  $v2 = @{}
  foreach ($r in @($Rows)) {
    $stamp = "$($r.stamp)"
    foreach ($ln in @($r.incidents)) {
      $p = & $parse $ln
      if ($null -eq $p) { continue }
      if ($stamp -lt $V2Since) { $v1[$p.Id] = $p.Triple }
      else {
        if (-not $v2.ContainsKey($p.Triple)) { $v2[$p.Triple] = @() }
        if ($v2[$p.Triple] -notcontains $p.Id) { $v2[$p.Triple] += $p.Id }
      }
    }
  }
  $aliases = @{}
  foreach ($old in $v1.Keys) {
    $t = $v1[$old]
    if ($v2.ContainsKey($t) -and (@($v2[$t]).Count -eq 1) -and ($v2[$t][0] -ne $old)) { $aliases[$old] = $v2[$t][0] }
  }
  return $aliases
}

function Format-TrendTable($Results, [hashtable]$Quarantine, [datetime]$Today = (Get-Date)) {
  # Renders nights as a Markdown trend (D00 T02 §17 items 2, 4, 9):
  # one row per run plus pass-rate, duration, quarantine-age, flake,
  # gate, budget-telemetry, and environment series. Pure over
  # result objects plus the quarantine snapshot
  # (@{Overdue=@() overdue objects-or-names; DueSoon=@()}); the trend
  # script discovers both. Stood-down and cancelled verdicts render
  # as marks, never numbers. Percentiles are median/max (tiny-n
  # honest). $Today anchors the oldest-overdue age; fixtures pin it.
  $rows = @($Results | Sort-Object { "$(Get-ResultNight $_)-$($_.stamp)" })
  $aliasMap = Get-IncidentAliases $rows
  # Canonical runs (D00 T02 §24 item 2): every result keeps its row, but
  # retries, simulations, and stood-down losers are marked and stay out
  # of the p50, the budget ranks, and flake recurrence, so a retry
  # burst cannot count as extra nights or bias the series.
  $canon = Select-CanonicalRuns $rows
  $isCanon = { param($r) $cid = "$($r.identity)"; if ($cid -eq '') { $cid = "$($r.stamp)" }; $nk = Get-ResultNight $r; ($canon.ContainsKey($nk)) -and ($canon[$nk].Canonical -eq $cid) }
  # Series inclusion (D00 T02 §25 item 2): durations, percentiles, and
  # alerts read canonical native nights only (no simulation, stand-down,
  # cancellation, retry, or backfill); pass rate and recurrence read
  # canonical nights, backfills included (their counts are mechanical
  # derivations and say so).
  $isNative = { param($r) (& $isCanon $r) -and (-not (Test-IsBackfill $r)) -and (-not [bool]$(try { $r.metricsBackfill } catch { $false })) }
  $rowEntries = @()
  $nativeNights = @()
  $lines = @('# Nightly trend', '', '- Pass rate: passed / (passed + failed) over executed tests; skips (quarantine, capability, fenced) are counted apart and never in the denominator; a night with a killed or budget-cut leg reads unproven; stand-downs and cancellations are marks.', '- Series: durations, percentiles, and alerts read canonical native nights (no simulation, stand-down, cancellation, retry, or backfill); pass rate and recurrence read canonical nights with backfills marked; every row renders, retries and extras marked.', '', '| Night | Verdict | Class | Pass | RunA s | RunB s | Soak | Gates | Reserve | Quar | SoakFail | Env |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
  $allA = @()
  $incNights = @{}
  foreach ($r in $rows) {
    $day = Get-ResultNight $r; $v = "$($r.verdict)"
    if (($v -eq 'stood-down') -or ($v -eq 'cancelled')) {
      $rowEntries += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Line = "| $day | $v (mark) | - | - | - | - | - | - | - | - | - | - |" }
      continue
    }
    $c = (Classify-NightlyOutcome $r).Class
    $p = 0; $f = 0; $s = 0; $anyRan = $false
    foreach ($leg in @('run-a', 'run-b', 'interactive')) {
      $o = $null
      try { $o = $r.legs.$leg } catch { }
      if ($null -eq $o) { continue }
      try { if (($null -ne $o.ran) -and (-not [bool]$o.ran)) { continue } } catch { }
      $anyRan = $true
      try { $p += [int]$o.passed } catch { }
      try { $f += [int]$o.failed } catch { }
      try { $s += [int]$o.skipped } catch { }
    }
    $exec = $p + $f
    $killedOrCut = $false
    foreach ($leg in @('run-a', 'run-b', 'interactive')) { try { $o = $r.legs.$leg; if (($null -ne $o) -and (($null -eq $o.ran) -or [bool]$o.ran) -and ([bool]$o.killed -or [bool]$o.cut)) { $killedOrCut = $true } } catch { } }
    if ($killedOrCut) { $pass = "$p/$f/$s unproven (killed or cut leg)" }
    elseif ($exec -gt 0) { $rate = [math]::Round((100 * $p) / $exec, 1); $pass = "$p/$f/$s ($rate% of $exec executed)" }
    elseif ($anyRan) { $pass = 'unproven' }
    else { $pass = 'no legs ran' }
    $ra = '-'
    $raVal = $null
    try { if ($null -ne $r.legs.'run-a'.testSeconds) { $ra = "$($r.legs.'run-a'.testSeconds)"; $raVal = [int]$r.legs.'run-a'.testSeconds; if (& $isNative $r) { $allA += $raVal } } } catch { }
    # Every native night joins the window, measured or not (R3-F2), so
    # the last 14 nights are chosen before their measurements filter.
    if (& $isNative $r) { $nativeNights += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Seconds = $raVal } }
    $rb = '-'
    try { if ($null -ne $r.legs.'run-b'.testSeconds) { $rb = "$($r.legs.'run-b'.testSeconds)" } } catch { }
    $soak = '-'
    try {
      $soak = "$($r.soak.verdict)"
      $fraw = $r.soak.failed
      if ($fraw -is [array]) { $sfn = @($fraw | Where-Object { $_ -is [string] }); if ($sfn.Count -gt 0) { $soak += ' ' + ($sfn -join ',') } }
      elseif (([int]$fraw) -gt 0) { $soak += " failed=$fraw" }
      $skn = @($r.soak.killed | Where-Object { $null -ne $_ }).Count; $scn = @($r.soak.cut | Where-Object { $null -ne $_ }).Count
      if ($skn -gt 0) { $soak += " killed=$skn" }
      if ($scn -gt 0) { $soak += " cut=$scn" }
    } catch { }
    $gates = '-'
    try {
      $ga = '-'; $gb = '-'
      try { if ($null -ne $r.legs.'run-a') { $la = $r.legs.'run-a'; $ga = if ((($null -ne $la.ran) -and (-not [bool]$la.ran))) { 'skip' } elseif ($null -eq $la.gate) { 'null' } else { "$($la.gate)" } } } catch { }
      try { if ($null -ne $r.legs.'run-b') { $lb = $r.legs.'run-b'; $gb = if ((($null -ne $lb.ran) -and (-not [bool]$lb.ran))) { 'skip' } elseif ($null -eq $lb.gate) { 'null' } else { "$($lb.gate)" } } } catch { }
      $gates = "$ga/$gb"
    } catch { }
    $res = '-'
    try { if ($null -ne $r.reserve) { $res = "$($r.reserve)s" } } catch { }
    $od = 0; $ds = 0
    try { $od = @($r.quarantine.overdue | Where-Object { $null -ne $_ }).Count } catch { }
    try { $ds = @($r.quarantine.dueSoon | Where-Object { $null -ne $_ }).Count } catch { }
    $qage = ''
    try {
      $nd = [datetime]::MinValue
      if ([datetime]::TryParse("$($r.day)", [ref]$nd)) {
        $ba = -1
        foreach ($qe in @($r.quarantine.overdueDetail)) {
          if (($null -eq $qe) -or ($null -eq $qe.Due)) { continue }
          $qd = [datetime]::MinValue
          if (-not [datetime]::TryParse("$($qe.Due)", [ref]$qd)) { continue }
          $a = [int](($nd.Date - $qd.Date).TotalDays)
          if ($a -gt $ba) { $ba = $a }
        }
        if ($ba -ge 0) { $qage = " (oldest ${ba}d)" }
      }
    } catch { }
    $sf = 0
    try { $fv = $r.soak.failed; if ($fv -is [array]) { $sf = @($fv).Count } else { $sf = [int]$fv } } catch { }
    $envShort = 'unknown'
    try { $envShort = "$($r.env.dpi) $($r.env.os)" } catch { }
    $nightCell = if (& $isCanon $r) { $day } else { "$day (retry)" }
    if (Test-IsBackfill $r) { $nightCell += ' (backfill)' }
    if ([bool]$(try { $r.fromMetrics } catch { $false })) { $nightCell += ' (metrics)' }
    $rowEntries += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Line = "| $nightCell | $v | $c | $pass | $ra | $rb | $soak | $gates | $res | $od/$ds$qage | $sf | $envShort |" }
  }
  # Missing nights (D00 T02 §25 item 4): every night between the first
  # and last canonical night with no result at all renders as missing.
  $canonNights = @($canon.Keys | Where-Object { $canon[$_].Canonical -ne '' } | Sort-Object)
  $allNights = @($rowEntries | ForEach-Object { $_.Night })
  if ($canonNights.Count -ge 2) {
    $d0 = [datetime]::ParseExact($canonNights[0], 'yyyy-MM-dd', $null)
    $d1 = [datetime]::ParseExact($canonNights[-1], 'yyyy-MM-dd', $null)
    for ($d = $d0.AddDays(1); $d -lt $d1; $d = $d.AddDays(1)) {
      $ds = $d.ToString('yyyy-MM-dd')
      if ($allNights -notcontains $ds) { $rowEntries += [pscustomobject]@{ Night = $ds; Stamp = ''; Line = "| $ds | missing | - | no result | - | - | - | - | - | - | - | - |" } }
    }
  }
  $lines += @($rowEntries | Sort-Object Night, Stamp | ForEach-Object { $_.Line })
  foreach ($r in $rows) {
    if (-not (& $isCanon $r)) { continue }
    $incs = @()
    try { $incs = @($r.incidents) } catch { }
    foreach ($ln in $incs) {
      $m = [regex]::Match("$ln", '(INC-[0-9a-f]{8}) `([^`]+)`')
      if ($m.Success) {
        $id = $m.Groups[1].Value
        if ($aliasMap.ContainsKey($id)) { $id = $aliasMap[$id] }
        if (-not $incNights.ContainsKey($id)) { $incNights[$id] = @() }
        $incNights[$id] += (Get-ResultNight $r)
      }
    }
  }
  $rec = @($incNights.Keys | Where-Object { (@($incNights[$_] | Sort-Object -Unique).Count) -gt 1 } | Sort-Object)
  $lines += ''
  if ($aliasMap.Count -gt 0) { $lines += ("- Identity aliases (contract v1 to v2): " + ((@($aliasMap.Keys | Sort-Object) | ForEach-Object { "$_ -> $($aliasMap[$_])" }) -join '; ')) }
  if ($rec.Count -gt 0) { $lines += ("- Flake recurrence: " + (($rec | ForEach-Object { "$_ ($($incNights[$_] -join ', '))" }) -join '; ')) }
  else { $lines += '- Flake recurrence: none across rendered nights' }
  $canonCount = @($canon.Keys | Where-Object { $canon[$_].Canonical -ne '' }).Count
  $lines += "- Canonical nights: $canonCount of $($rows.Count) results (retries, simulations, and stood-down losers stay out of the p50, the budget ranks, and recurrence)"
  # Launch evidence behind the latest canonical night's incidents
  # (D00 T02 §24 item 14), one click from the trend.
  $latest = @($rows | Where-Object { & $isCanon $_ }) | Select-Object -Last 1
  if ($null -ne $latest) {
    $ev = $null
    try { $ev = $latest.incidentEvidence } catch { }
    if ($null -ne $ev) {
      foreach ($prop in @($ev.PSObject.Properties)) { $lines += "- Incident evidence ($($latest.day)): $($prop.Name) $(@($prop.Value) -join '; ')" }
    }
  }
  # Tail percentiles over the last 14 canonical native nights (D00 T02
  # §25 item 5): the sample count plus p50, p90, and p95, so a tail
  # regression and its confidence read at a glance.
  $win = @($nativeNights | Sort-Object Night, Stamp | Select-Object -Last 14 | Where-Object { $null -ne $_.Seconds } | ForEach-Object { $_.Seconds })
  if ($win.Count -gt 0) {
    $lines += "- RunA test-seconds (canonical native nights, last 14): n=$($win.Count), p50 $(Get-Percentile $win 50), p90 $(Get-Percentile $win 90), p95 $(Get-Percentile $win 95), max $(($win | Measure-Object -Maximum).Maximum)"
  }
  else { $lines += '- RunA test-seconds: no measurements' }
  $qo = 0; $qs = 0
  try { $qo = @($Quarantine['Overdue'] | Where-Object { $null -ne $_ }).Count } catch { }
  try { $qs = @($Quarantine['DueSoon'] | Where-Object { $null -ne $_ }).Count } catch { }
  $oldest = ''
  try {
    $cands = @($Quarantine['Overdue'] | Where-Object { ($null -ne $_) -and ($null -ne $_.Due) })
    $best = $null; $bestAge = -1
    foreach ($c in $cands) {
      $dd = [datetime]::MinValue
      if (-not [datetime]::TryParse("$($c.Due)", [ref]$dd)) { continue }
      $age = [int](($Today.Date - $dd.Date).TotalDays)
      if ($age -gt $bestAge) { $bestAge = $age; $best = $c }
    }
    if ($null -ne $best) { $oldest = ", oldest $($bestAge)d: $($best.Test)" }
  } catch { }
  $lines += "- Quarantine now: $qo overdue$oldest, $qs due within 3 days"
  # Backfill provenance (D00 T02 §25 item 9): every backfilled row quotes
  # where each field came from and how far to trust it.
  foreach ($r in $rows) {
    $pv = $null
    try { $pv = $r.provenance } catch { }
    if ($null -eq $pv) { continue }
    $bits = @($pv.PSObject.Properties | ForEach-Object { "$($_.Name) $($_.Value.confidence) from $($_.Value.source)" })
    $lines += "- Backfill provenance ($(Get-ResultNight $r) $($r.stamp)): $($bits -join '; ')"
  }
  $lines += ''
  $lines += '## Alerts'
  $lines += ''
  $alerts = @(Get-TrendAlerts @($rows | Where-Object { & $isNative $_ }))
  if ($alerts.Count -eq 0) { $lines += '(none)' } else { $lines += $alerts }
  $lines += ''
  $lines += '## Budget'
  $lines += ''
  $ranked = @($allA | Sort-Object)
  foreach ($r in $rows) {
    if ((("$($r.verdict)") -eq 'stood-down') -or (("$($r.verdict)") -eq 'cancelled')) { continue }
    $ph = 'no timings'
    try {
      $tp = @()
      $tobj = $r.timings
      if ($null -ne $tobj) {
        $names = @()
        if ($tobj -is [hashtable]) { try { $names = @($tobj.Keys) } catch { } }
        else { try { $names = @($tobj.PSObject.Properties.Name) } catch { } }
        foreach ($k in ($names | Sort-Object)) {
          $vv = $null
          try { $vv = $tobj.$k } catch { try { $vv = $tobj[$k] } catch { } }
          if ($null -ne $vv) { $tp += "$k=${vv}s" }
        }
      }
      if ($tp.Count -gt 0) { $ph = ($tp -join ' ') }
    } catch { }
    $bud = 'budget unknown'
    try {
      $used = $null; $left = $null
      try { if ($null -ne $r.consumed) { $used = [int]$r.consumed } } catch { }
      try { if ($null -ne $r.reserve) { $left = [int]$r.reserve } } catch { }
      if (($null -ne $used) -and ($null -ne $left)) { $bud = "used ${used}s / left ${left}s (span $($used + $left)s)" }
      elseif ($null -ne $used) { $bud = "used ${used}s / left unknown" }
      elseif ($null -ne $left) { $bud = "used unknown / left ${left}s" }
    } catch { }
    $rk = 'RunA unranked'
    try {
      $mine = $null
      try { if ($null -ne $r.legs.'run-a'.testSeconds) { $mine = [int]$r.legs.'run-a'.testSeconds } } catch { }
      if (($null -ne $mine) -and ($ranked.Count -gt 0)) {
        $pos = 1
        foreach ($v in $ranked) { if ([int]$v -lt $mine) { $pos++ } else { break } }
        $n = $ranked.Count
        $pct = 'n/a'
        if ($n -gt 1) { $pct = [string][int][math]::Round((100 * ($pos - 1)) / ($n - 1)) }
        $rk = "RunA ${mine}s rank $pos/$n pct $pct"
      }
    } catch { }
    $lines += "- $($r.day) $($r.stamp): phases $ph; $bud; $rk"
  }
  $lines += ''
  $lines += '## Environments'
  $lines += ''
  foreach ($r in $rows) {
    if ((("$($r.verdict)") -eq 'stood-down') -or (("$($r.verdict)") -eq 'cancelled')) { continue }
    $e = 'unknown'
    try { $e = "OS $($r.env.os); PS $($r.env.powershell); dotnet $($r.env.dotnet); $($r.env.session); $($r.env.topology); $($r.env.dpi); $($r.env.adapters); $($r.env.settings)" } catch { }
    $lines += "- $($r.day) $($r.stamp): $e"
  }
  return $lines
}

function Test-AckFile([string]$Path, [string]$Day) {
  # Ack validity (D00 T02 §17 item 3): a sign-off names its owner plus
  # its day and carries substance (failures plus cause cannot fit in
  # 200 chars, so shorter files read unsigned, never acked). An empty
  # or anonymous file must never suppress a RED.
  if (-not (Test-Path $Path -PathType Leaf)) { return [pscustomobject]@{ Ok = $false; Error = 'ack missing' } }
  $text = ''
  try { $text = [string](Get-Content $Path -Raw -ErrorAction Stop) } catch { return [pscustomobject]@{ Ok = $false; Error = 'ack unreadable' } }
  if ($text -notmatch 'Owner:\s*\S+') { return [pscustomobject]@{ Ok = $false; Error = 'ack names no owner' } }
  if ($text -match '(?im)^Owner:\s*(TBD|TODO|TBS|XXX|none|n/a|unknown)\s*(\.|$)') { return [pscustomobject]@{ Ok = $false; Error = 'ack owner is a placeholder' } }
  if ($text -notmatch [regex]::Escape($Day)) { return [pscustomobject]@{ Ok = $false; Error = 'ack names no day' } }
  if ($text.Length -lt 200) { return [pscustomobject]@{ Ok = $false; Error = 'ack too short to carry cause' } }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

# Acknowledgement v2 (D00 T02 §23): an ack binds to immutable run
# identities plus their result checksums and incident ids, carries a
# structured disposition, and counts only once committed, so git
# history is its append-only integrity record. v1 day-keyed files
# (Test-AckFile) stay valid only for runs on or before the cutover day.
$script:AckV1Cutover = '2026-09-21'
$script:AckDueDays = 3
$script:AckDispositions = @('fixed', 'filed', 'quarantined', 'environment', 'expected', 'duplicate')

function Get-FileSha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLower()
  } finally { $sha.Dispose() }
}

function Get-AckDemands($ResultFiles) {
  # One demand per RED or cancelled run identity (D00 T02 §23 items 1
  # and 4): retained copies, reruns, and re-emitted results of one run
  # dedupe onto its identity, carrying every checksum seen for it (the
  # checksum covers the schema version field, so the key is run,
  # checksum, and version). $ResultFiles are paths; unreadable files
  # are skipped (the result gate reds them elsewhere). Returns a
  # hashtable identity -> Day, Shas, Paths, Current (the checksum of
  # the most recently written copy), Incidents (that copy's INC ids),
  # and AllIncidents (the union across copies).
  $demands = @{}
  foreach ($p in @($ResultFiles)) {
    if (-not (Test-Path $p -PathType Leaf)) { continue }
    $r = $null
    try { $r = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
    if ($null -eq $r) { continue }
    if (@('red', 'cancelled') -notcontains "$($r.verdict)") { continue }
    $id = "$($r.identity)"
    if ($id -eq '') { $id = "$($r.stamp)" }
    if ($id -eq '') { continue }
    if (-not $demands.ContainsKey($id)) { $demands[$id] = [pscustomobject]@{ Id = $id; Day = "$($r.day)"; Shas = @(); Incidents = @(); Paths = @(); Current = ''; CurrentTime = [datetime]::MinValue; AllIncidents = @() } }
    $d = $demands[$id]
    $sha = Get-FileSha256 $p
    if ($d.Shas -notcontains $sha) { $d.Shas += $sha }
    $d.Paths += $p
    # The most recently written copy is the run's current result: an ack
    # must match it, so an older retained copy can never keep a changed
    # result acknowledged.
    $copyInc = @()
    foreach ($ln in @($r.incidents)) {
      $m = [regex]::Match("$ln", '(INC-[0-9a-f]{8})')
      if ($m.Success -and ($copyInc -notcontains $m.Groups[1].Value)) { $copyInc += $m.Groups[1].Value }
    }
    foreach ($i in $copyInc) { if ($d.AllIncidents -notcontains $i) { $d.AllIncidents += $i } }
    # Incidents follow the current copy, so a rewrite that removes or
    # corrects an incident is acknowledged against what it says now.
    $wt = (Get-Item -LiteralPath $p).LastWriteTimeUtc
    if ($wt -ge $d.CurrentTime) { $d.Current = $sha; $d.CurrentTime = $wt; $d.Incidents = $copyInc }
  }
  return $demands
}

function Read-AckFrontmatter([string]$Text) {
  # The leading `---` block of an ack file: `key: value` lines, with
  # `run:` repeatable. Returns Ok, Fields (last value per key), Runs
  # (each `run:` value), and Error.
  $lines = @("$Text" -split "`r?`n")
  if (($lines.Count -lt 3) -or ($lines[0].Trim() -ne '---')) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Error = 'no frontmatter' } }
  $fields = @{}
  $runs = @()
  $closed = $false
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln.Trim() -eq '---') { $closed = $true; break }
    if ($ln.Trim() -eq '') { continue }
    $m = [regex]::Match($ln, '^([a-z][a-z0-9-]*):\s*(.*?)\s*$')
    if (-not $m.Success) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Error = "frontmatter line malformed: $ln" } }
    if ($m.Groups[1].Value -eq 'run') { $runs += $m.Groups[2].Value } else { $fields[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  if (-not $closed) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Error = 'frontmatter not closed' } }
  return [pscustomobject]@{ Ok = $true; Fields = $fields; Runs = $runs; Error = '' }
}

function Test-AckV2([string]$Text, [hashtable]$Demands) {
  # Validates one v2 ack against the live demands (D00 T02 §23 items 1
  # and 2): every named run is a known RED identity whose recorded
  # checksum matches a copy of its result, the incident list equals the
  # run's incident ids, and the disposition is structured (enum,
  # corrective owner, due date on or after signing, linked finding).
  # Prose length proves nothing, so it is never checked. Returns Ok,
  # Acked (run ids), Stale (runs whose result changed after the ack),
  # and Errors.
  $fm = Read-AckFrontmatter $Text
  if (-not $fm.Ok) { return [pscustomobject]@{ Ok = $false; Acked = @(); Stale = @(); Errors = @($fm.Error) } }
  $f = $fm.Fields
  $errs = @()
  if ("$($f['ack-version'])" -ne '2') { $errs += "ack-version must be 2 (got '$($f['ack-version'])')" }
  foreach ($req in @('owner', 'disposition', 'corrective-owner', 'due', 'finding', 'signed', 'incidents')) {
    if (-not $f.ContainsKey($req) -or ("$($f[$req])" -eq '')) { $errs += "missing $req" }
  }
  $placeholder = '^(TBD|TODO|TBS|XXX|none|n/a|unknown|\?)$'
  foreach ($who in @('owner', 'corrective-owner')) {
    if ($f.ContainsKey($who) -and ("$($f[$who])" -match $placeholder)) { $errs += "$who is a placeholder" }
  }
  if ($f.ContainsKey('disposition') -and ($script:AckDispositions -notcontains "$($f['disposition'])")) { $errs += "disposition '$($f['disposition'])' not one of $($script:AckDispositions -join ', ')" }
  $signed = [datetime]::MinValue
  $due = [datetime]::MinValue
  $signedOk = $f.ContainsKey('signed') -and [datetime]::TryParseExact("$($f['signed'])", 'yyyy-MM-dd', $null, 'None', [ref]$signed)
  $dueOk = $f.ContainsKey('due') -and [datetime]::TryParseExact("$($f['due'])", 'yyyy-MM-dd', $null, 'None', [ref]$due)
  if ($f.ContainsKey('signed') -and -not $signedOk) { $errs += "signed is not a YYYY-MM-DD date" }
  if ($f.ContainsKey('due') -and -not $dueOk) { $errs += "due is not a YYYY-MM-DD date" }
  if ($signedOk -and $dueOk -and ($due -lt $signed)) { $errs += 'due precedes signed' }
  if ($f.ContainsKey('finding') -and ("$($f['finding'])" -notmatch '^(D\d{2} T\d{2} \u00A7\d+|INC-[0-9a-f]{8}|[0-9a-f]{7,40})$')) { $errs += "finding '$($f['finding'])' is not a section ref, incident id, or commit" }
  if ($fm.Runs.Count -eq 0) { $errs += 'names no run' }
  $acked = @()
  $stale = @()
  $named = @()
  foreach ($rv in $fm.Runs) {
    $m = [regex]::Match($rv, '^(\S+)\s+sha256:([0-9a-f]{64})$')
    if (-not $m.Success) { $errs += "run line malformed: $rv"; continue }
    $id = $m.Groups[1].Value
    $sha = $m.Groups[2].Value
    if ($named -contains $id) { $errs += "run named twice: $id"; continue }
    $named += $id
    if (-not $Demands.ContainsKey($id)) { $errs += "run $id is not a known RED"; continue }
    $d = $Demands[$id]
    if ($d.Current -ne $sha) { $stale += $id; continue }
    $acked += $id
  }
  if ($f.ContainsKey('incidents') -and ($errs.Count -eq 0)) {
    $listed = @()
    if ("$($f['incidents'])" -ne 'none') { $listed = @("$($f['incidents'])" -split '[,\s]+' | Where-Object { $_ -ne '' }) }
    $want = @()
    foreach ($id in $acked) { foreach ($i in @($Demands[$id].Incidents)) { if ($want -notcontains $i) { $want += $i } } }
    # A stale run is judged by its STALE line, never by its incidents:
    # what it carried when signed may be gone from every surviving copy
    # (an in-place rewrite), so while any named run is stale, extra
    # listed incidents are tolerated (an extra id suppresses nothing).
    # Every acknowledged run's current incidents must still be listed.
    $missing = @($want | Where-Object { $listed -notcontains $_ })
    $extra = @()
    if ($stale.Count -eq 0) { $extra = @($listed | Where-Object { $want -notcontains $_ }) }
    if ($missing.Count -gt 0) { $errs += "incidents missing: $($missing -join ', ')" }
    if ($extra.Count -gt 0) { $errs += "incidents not in the acked runs: $($extra -join ', ')" }
  }
  if ($errs.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Acked = @(); Stale = $stale; Errors = $errs } }
  return [pscustomobject]@{ Ok = $true; Acked = $acked; Stale = $stale; Errors = @() }
}

function Get-AckHistory([string]$Root, [string]$RelPath) {
  # The append-only integrity record (D00 T02 §23 item 5): an ack
  # counts only once committed with the working copy equal to HEAD, and
  # its history is the git log of the file (trunk never amends or
  # force-pushes, so the log only grows). Returns Committed, Dirty,
  # Entries (commit, author, date), and Error.
  $out = [pscustomobject]@{ Committed = $false; Dirty = $false; Entries = @(); Error = '' }
  $eap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $log = @(git -C $Root log --follow --format='%H|%an|%aI' -- $RelPath 2>$null)
    if ($LASTEXITCODE -ne 0) {
      # A repository with no commits yet fails `git log`; that history
      # is empty (uncommitted), not unverifiable.
      $null = git -C $Root rev-parse -q --verify HEAD 2>$null
      if ($LASTEXITCODE -ne 0) { return $out }
      $out.Error = 'git log failed'; return $out
    }
    foreach ($l in $log) {
      $p = "$l" -split '\|', 3
      if ($p.Count -eq 3) { $out.Entries += [pscustomobject]@{ Commit = $p[0]; Author = $p[1]; Date = $p[2] } }
    }
    $out.Committed = ($out.Entries.Count -gt 0)
    $st = @(git -C $Root status --porcelain -- $RelPath 2>$null)
    if ($LASTEXITCODE -ne 0) { $out.Error = 'git status failed'; $out.Committed = $false; return $out }
    $out.Dirty = ($st.Count -gt 0)
  } catch { $out.Error = "git unavailable: $($_.Exception.Message)" } finally { $ErrorActionPreference = $eap }
  return $out
}

function Test-FindingExists([string]$Root, [string]$Finding, [string[]]$KnownIncidents) {
  # Existence behind a linked finding (D00 T02 §23 R1-F2): a section ref
  # names a real `## N.` heading in its TODO file, an INC id is one this
  # tree has seen (the run demands or the incident ledger), and a commit
  # resolves in the repository. Syntax alone links nothing.
  $m = [regex]::Match($Finding, '^D(\d{2}) T(\d{2}) \u00A7(\d+)$')
  if ($m.Success) {
    $files = @(Get-ChildItem (Join-Path $Root 'todo') -Directory -Filter "$($m.Groups[1].Value)-*" -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem $_.FullName -File -Filter "TODO-$($m.Groups[2].Value)-*.md" -ErrorAction SilentlyContinue })
    foreach ($f in $files) {
      foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName)) { if ($ln -match "^## $($m.Groups[3].Value)\. ") { return $true } }
    }
    return $false
  }
  if ($Finding -match '^INC-[0-9a-f]{8}$') { return (@($KnownIncidents) -contains $Finding) }
  if ($Finding -match '^[0-9a-f]{7,40}$') {
    # Windows PowerShell turns native stderr into a terminating error
    # under Stop even when redirected, so the probe runs with the
    # preference scoped to Continue and reads only the exit code.
    $found = $false
    $eap = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $null = git -C $Root cat-file -e "$Finding^{commit}" 2>&1; $found = ($LASTEXITCODE -eq 0) } catch { $found = $false } finally { $ErrorActionPreference = $eap }
    return $found
  }
  return $false
}

function Test-Acknowledgements([string]$Root, [string]$AckDir, [hashtable]$Demands, [datetime]$Today) {
  # The whole gate (D00 T02 §23): v2 acks (committed, clean, valid)
  # plus v1 day files for runs on or before the cutover acknowledge
  # demands; everything else stays unacked with its due date, and a
  # past-due demand escalates and stages a finding stub. Returns Ok,
  # Unacked (ids), Lines (report section), Staged (Filings stubs),
  # Overdue (ids).
  $acked = @{}
  $lines = @()
  $staged = @()
  $knownIncidents = @()
  foreach ($id in @($Demands.Keys)) { $knownIncidents += @($Demands[$id].Incidents) }
  $ledgerRead = Read-IncidentLedger (Join-Path $Root 'build\nightly\incidents.json')
  if ($ledgerRead.Ok) { $knownIncidents += @($ledgerRead.Incidents.Keys) }
  foreach ($file in @(Get-ChildItem $AckDir -Filter 'ack-*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $rel = ($file.FullName.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/'
    $text = ''
    try { $text = [System.IO.File]::ReadAllText($file.FullName) } catch { $lines += "- $($file.Name): unreadable (ignored)"; continue }
    $isV2 = ($text -match '\A\s*---\r?\n')
    if ((-not $isV2) -and ($file.BaseName -match '^ack-(\d{4}-\d{2}-\d{2})$')) {
      $day = $Matches[1]
      if ([string]::CompareOrdinal($day, $script:AckV1Cutover) -gt 0) { $lines += "- $($file.Name): v1 day file after the $($script:AckV1Cutover) cutover (ignored; write a v2 ack naming each run)"; continue }
      if (-not (Test-AckFile $file.FullName $day).Ok) { $lines += "- $($file.Name): v1 ack invalid (ignored)"; continue }
      $n = 0
      foreach ($id in @($Demands.Keys)) { if ($Demands[$id].Day -eq $day) { $acked[$id] = "v1 $($file.Name)"; $n++ } }
      $lines += "- $($file.Name): v1 legacy, acknowledges $n run(s) of $day"
      continue
    }
    $hist = Get-AckHistory $Root $rel
    if ($hist.Error -ne '') { $lines += "- $($file.Name): history unverifiable ($($hist.Error)); ignored"; continue }
    if (-not $hist.Committed) { $lines += "- $($file.Name): uncommitted (ignored until committed: git history is the integrity record)"; continue }
    if ($hist.Dirty) { $lines += "- $($file.Name): edited since its last commit (ignored until committed)"; continue }
    $v = Test-AckV2 $text $Demands
    $histText = (@($hist.Entries | ForEach-Object { "$($_.Commit.Substring(0, 7)) $($_.Author) $($_.Date)" }) -join '; ')
    if ($v.Ok) {
      # The linked finding must exist: an invented section, incident, or
      # commit links no corrective work.
      $fnd = "$((Read-AckFrontmatter $text).Fields['finding'])"
      if (-not (Test-FindingExists $Root $fnd $knownIncidents)) { $v = [pscustomobject]@{ Ok = $false; Acked = @(); Stale = $v.Stale; Errors = @("finding $fnd not found") } }
    }
    if (-not $v.Ok) { $lines += "- $($file.Name): INVALID ($($v.Errors -join '; ')); history $histText"; continue }
    foreach ($id in $v.Acked) { $acked[$id] = $file.Name }
    $staleNote = if ($v.Stale.Count -gt 0) { "; STALE for $($v.Stale -join ', ') (result changed after the ack: re-ack with the new checksum)" } else { '' }
    $ackedText = if (@($v.Acked).Count -gt 0) { $v.Acked -join ', ' } else { 'nothing current' }
    $lines += "- $($file.Name): acknowledges $ackedText$staleNote; history $histText"
  }
  $unacked = @()
  $overdue = @()
  foreach ($id in @($Demands.Keys | Sort-Object)) {
    if ($acked.ContainsKey($id)) { continue }
    $unacked += $id
    $d = $Demands[$id]
    $dayDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact("$($d.Day)", 'yyyy-MM-dd', $null, 'None', [ref]$dayDate)) { $lines += "- UNACKED $id (day unreadable: escalate operator)"; $overdue += $id; continue }
    $dueDate = $dayDate.AddDays($script:AckDueDays)
    $late = ($Today.Date - $dueDate.Date).Days
    if ($late -gt 0) {
      $overdue += $id
      $lines += "- OVERDUE ack: $id (RED $($d.Day), due $($dueDate.ToString('yyyy-MM-dd')), $late day(s) overdue): escalate operator"
      $staged += "- STAGED ack-overdue $id : RED $($d.Day) unacknowledged $late day(s) past due; file under D00 T02 $([char]0xA7)9 triage or write docs/nightly-acks/ack-<name>.md naming it (incidents: $(if ($d.Incidents.Count -gt 0) { $d.Incidents -join ', ' } else { 'none' }))"
    } else {
      $lines += "- UNACKED $id (RED $($d.Day), due $($dueDate.ToString('yyyy-MM-dd')))"
    }
  }
  return [pscustomobject]@{ Ok = ($unacked.Count -eq 0); Unacked = $unacked; Lines = $lines; Staged = $staged; Overdue = $overdue }
}
