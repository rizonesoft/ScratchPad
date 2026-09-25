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
  foreach ($r in @($t.TestRun.Results.UnitTestResult | Where-Object { $_.outcome -eq 'NotExecuted' })) {
    $msg = ''
    if ($r.Output -and $r.Output.ErrorInfo -and $r.Output.ErrorInfo.Message) { $msg = $r.Output.ErrorInfo.Message }
    if ($msg -cmatch 'QUARANTINED \d{4}-\d{2}-\d{2} \S+') { continue }
    # A capability skip is explained only when it names its owner and the
    # host that owes the run (D00 T02 §44 item 3); the ownerless forms,
    # the pre-code legacy fragments included, now read unexplained.
    if (Test-CapabilitySkip $msg) { continue }
    $names += $r.testName
  }
  return [pscustomobject]@{ Ok = $true; Names = $names }
}

function Test-CapabilitySkip([string]$Message) {
  # `CAPABILITY: <why>; owner DNN TNN <section sign>N; owed on <host>.`
  # (D00 T02 §44 item 3). The section sign is built by code point: Windows
  # PowerShell reads this BOM-less script as ANSI.
  $sec = [char]0xA7
  return ($Message -cmatch ('^CAPABILITY: .+; owner D\d{2} T\d{2} ' + $sec + '\d+; owed on \S.*'))
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
  # Capture-time authorization (section 45 item 2): with binary captures
  # refused by policy no screenshot is rendered at all and the refusal is
  # the note (the dump was never requested: Get-DumpArgs).
  if (-not $script:BinaryCapturesAllowed) {
    $notes += "- $Leg : CAPTURE-REFUSED screenshot and dump (binaryCaptures is off in tools/incident-policy.json, or the policy is unreadable); no binary capture taken"
  } else {
  # Screenshots cover app-owned windows only (section 38 item 2): each
  # window of a ScratchPad process the run launched, clipped to its own
  # bounds; the rest of the desktop (the operator's windows) is never
  # captured. No owned window means no screenshot.
  try {
    Add-Type -AssemblyName System.Drawing
    $ownedPids = @{}
    try { $ownedPids = Get-DescendantPids @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; ParentProcessId = [int]$_.ParentProcessId; Created = $_.CreationDate } }) $PID } catch { $ownedPids = @{} }
    $wins = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.Id; Name = $_.ProcessName; Handle = $_.MainWindowHandle; Rect = (Get-WindowRect $_.MainWindowHandle) } })
    $rects = @(Get-OwnedWindowRects $wins $ownedPids)
    if ($rects.Count -eq 0) { $notes += "- $Leg : no screenshot (no app-owned window was open)" }
    $n = 0
    foreach ($r in $rects) {
      $n++
      $shot = Join-Path $CaptureDir "$Leg-failure-$n.png"
      # The window renders its own content (PrintWindow with
      # PW_RENDERFULLCONTENT, R1-F2), so a window covering it on screen
      # contributes no pixels; screen pixels are never copied. The render
      # runs in a separate job process bounded by the render timeout
      # (R3-F1): a hung window costs one note, never the report.
      $notes += @(Invoke-WindowRender $r $shot $Leg $script:WindowRenderTimeoutSeconds)
    }
  } catch { $notes += "- $Leg : screenshot failed: $($_.Exception.Message)" }
  }
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
  if ((-not $Killed) -and $script:BinaryCapturesAllowed) { $notes += "- $Leg : no dump (process exited before capture)" }
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
# One authoritative source (section 38 item 8): tools/incident-policy.json
# names the triage owner and the escalation window; the defaults above
# stand only if it is absent, and an unreadable file is reported.
$script:IncidentPolicyError = ''
function Read-IncidentPolicy([string]$Path) {
  if (-not (Test-Path $Path)) { return [pscustomobject]@{ Ok = $false; Error = "incident policy missing: $Path"; Owner = ''; Days = 0 } }
  try {
    $j = Get-Content $Path -Raw | ConvertFrom-Json
    if (("$($j.triageOwner)" -eq '') -or ("$($j.triageDays)" -notmatch '^[1-9]\d*$')) { return [pscustomobject]@{ Ok = $false; Error = "incident policy invalid: triageOwner must be named and triageDays a positive whole number ($Path)"; Owner = ''; Days = 0 } }
    # Capture-time authorization (D00 T02 section 45 item 2): binaryCaptures
    # decides whether screenshots and dumps are taken at all. Absent reads
    # true (the recorded default); anything but a JSON boolean is invalid.
    $bin = $true
    if ($null -ne $j.PSObject.Properties['binaryCaptures']) {
      if ($j.binaryCaptures -isnot [bool]) { return [pscustomobject]@{ Ok = $false; Error = "incident policy invalid: binaryCaptures must be true or false ($Path)"; Owner = ''; Days = 0; BinaryCaptures = $false } }
      $bin = [bool]$j.binaryCaptures
    }
    return [pscustomobject]@{ Ok = $true; Error = ''; Owner = "$($j.triageOwner)"; Days = [int]$j.triageDays; BinaryCaptures = $bin }
  } catch { return [pscustomobject]@{ Ok = $false; Error = "incident policy unreadable: $($_.Exception.Message)"; Owner = ''; Days = 0 } }
}
$policy = Read-IncidentPolicy (Join-Path $PSScriptRoot 'incident-policy.json')
# Binary captures fail closed: an unreadable or invalid policy takes no
# screenshot and no dump (section 45 item 2).
$script:BinaryCapturesAllowed = $false
if ($policy.Ok) { $script:TriageOwner = $policy.Owner; $script:TriageDays = $policy.Days; $script:BinaryCapturesAllowed = $policy.BinaryCaptures } else { $script:IncidentPolicyError = $policy.Error }
$script:IncidentContractV2Since = '2026-09-25-000000'
$script:CaptureOwnedProcesses = @('ScratchPad', 'testhost', 'ForegroundLog', 'JobControl')
$script:CaptureMaxBytes = 25MB
$script:CaptureFailMarker = 'SECRET-SCAN-FAILED.txt'
$script:CaptureStagingDir = '.staging'
# Per-run ledger checkpoint (D00 T02 section 45 item 4) and the last
# rebuild's gaps and base, for the rebuild command's report.
$script:LedgerCheckpointName = 'incidents.checkpoint.json'
$script:LedgerRebuildGaps = @()
$script:LedgerRebuildBase = ''
$script:LedgerRebuildStamp = ''
$script:CaptureBudgetMarker = 'CAPTURE-BUDGET-TRUNCATED.txt'
$script:RunCaptureMaxBytes = 200MB
# Per-capture cap and reservation (section 38 item 3): a dump over the
# cap is refused at capture time (JobControl --dump-max), and a dump is
# attempted only while the disk keeps the cap plus the markers free.
$script:CaptureFileMaxBytes = 100MB
$script:WindowRenderTimeoutSeconds = 15
$script:CaptureRefusedMarker = 'CAPTURE-REFUSED.txt'
$script:DumpDisclosureMarker = 'CAPTURE-DISCLOSURE-APPROVED.txt'
# Ledger initialization record (section 38 item 4).
$script:LedgerRecordPath = 'docs/incident-ledger.md'
# The lifecycle block's consumer contract version (section 38 item 7).
$script:LifecycleContractVersion = 1
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

function Get-WindowRect([IntPtr]$Handle) {
  if (-not ('NightlyWin32Rect' -as [type])) {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NightlyWin32Rect { [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; } [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags); }'
  }
  $r = New-Object NightlyWin32Rect+RECT
  if (-not [NightlyWin32Rect]::GetWindowRect($Handle, [ref]$r)) { return $null }
  return [pscustomobject]@{ X = $r.Left; Y = $r.Top; Width = ($r.Right - $r.Left); Height = ($r.Bottom - $r.Top) }
}

function Invoke-WindowRender($Rect, [string]$Path, [string]$Leg, [int]$TimeoutSeconds, [scriptblock]$Render = $null) {
  # One window rendered to a PNG in a background job (its own process), so
  # a window that never answers WM_PRINT is abandoned at the bound and the
  # job is stopped. $Render replaces the job body in fixtures. Returns
  # report notes.
  $body = if ($null -ne $Render) { $Render } else {
    {
      param($handle, $w, $h, $out)
      Add-Type -AssemblyName System.Drawing
      Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NightlyPrint { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags); }'
      $bmp = New-Object System.Drawing.Bitmap $w, $h
      try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $ok = $false
        try { $hdc = $g.GetHdc(); try { $ok = [NightlyPrint]::PrintWindow([IntPtr]$handle, $hdc, 2) } finally { $g.ReleaseHdc($hdc) } } finally { $g.Dispose() }
        if ($ok) { $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png) }
        $ok
      } finally { $bmp.Dispose() }
    }
  }
  $job = Start-Job -ScriptBlock $body -ArgumentList @([long]$Rect.Handle, $Rect.Width, $Rect.Height, $Path)
  try {
    if ($null -eq (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
      Stop-Job -Job $job
      if (Test-Path $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
      return @("- $Leg : screenshot of pid $($Rect.ProcessId) abandoned (the window did not render within $TimeoutSeconds s); none kept")
    }
    $ok = @(Receive-Job -Job $job -ErrorAction SilentlyContinue) | Select-Object -Last 1
    if (($ok -eq $true) -and (Test-Path $Path)) { return @("- $Leg : screenshot $(Split-Path -Leaf $Path) (pid $($Rect.ProcessId) window content only)") }
    return @("- $Leg : screenshot of pid $($Rect.ProcessId) failed (PrintWindow refused); none kept")
  } finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
}

function Get-OwnedWindowRects($Windows, [hashtable]$OwnedPids) {
  # The screenshot set (section 38 item 2): windows whose process the run
  # owns (Get-DescendantPids) and whose name is a kind the run launches,
  # with a real area. $Windows entries carry ProcessId, Name, Rect.
  return @(@($Windows) | Where-Object {
    ($null -ne $_) -and ($null -ne $_.Rect) -and $OwnedPids.ContainsKey([int]$_.ProcessId) -and ($_.Name -eq 'ScratchPad') -and ($_.Rect.Width -gt 0) -and ($_.Rect.Height -gt 0)
  } | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; Handle = $_.Handle; X = $_.Rect.X; Y = $_.Rect.Y; Width = $_.Rect.Width; Height = $_.Rect.Height } })
}

function Get-DumpMemoryKind([string]$Path) {
  # A minidump's header (MINIDUMP_HEADER): signature MDMP at 0, Flags as
  # a little-endian ULONG64 at 24. MiniDumpWithFullMemory is 0x2. Returns
  # full, minimal, or unreadable.
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      $b = New-Object byte[] 32
      if ($fs.Read($b, 0, 32) -lt 32) { return 'unreadable' }
    } finally { $fs.Dispose() }
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'MDMP') { return 'unreadable' }
    $flags = [System.BitConverter]::ToUInt64($b, 24)
    if (($flags -band 2) -ne 0) { return 'full' }
    return 'minimal'
  } catch { return 'unreadable' }
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
    # Binary captures (section 38 item 2, R1-F2): screenshots and dumps
    # cannot be secret-scanned, so every one retains only behind the
    # explicit disclosure marker in its capture directory; a full-memory
    # dump or an unreadable dump header is named as such.
    $gated = Test-Path (Join-Path $d.FullName $script:DumpDisclosureMarker)
    foreach ($bin in @(Get-ChildItem -Path $d.FullName -File -Recurse -ErrorAction SilentlyContinue | Where-Object { @('.png', '.dmp') -contains $_.Extension.ToLower() })) {
      $what = 'a screenshot'
      if ($bin.Extension -ieq '.dmp') {
        $kind = Get-DumpMemoryKind $bin.FullName
        if ($kind -eq 'unreadable') { $reasons += "$($d.Name)/$($bin.Name) has an unreadable dump header"; continue }
        $what = $(if ($kind -eq 'full') { 'a full-memory dump' } else { 'a minidump' })
      }
      if (-not $gated) { $reasons += "$($d.Name)/$($bin.Name) is $what; retain needs $($script:DumpDisclosureMarker) beside it" }
    }
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

function New-StagingDirectory([string]$Path) {
  # The staging directory carries the run's own ACL (D00 T02 section 38
  # item 1): inheritance off, full control for the account running the
  # nightly and nobody else, so no other user's process can write into
  # the bytes between the scan and the publish.
  $null = New-Item -ItemType Directory -Force -Path $Path
  $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $acl = New-Object System.Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
  # .NET directly: Set-Acl's module does not load in every host session.
  [System.IO.Directory]::SetAccessControl($Path, $acl)
}

function Get-DumpArgs([string]$DumpDir, [long]$DumpMax) {
  # JobControl dump flags (section 45 item 2): with binary captures
  # refused by policy the supervisor is never asked for a dump, so none
  # is written; otherwise the per-capture cap binds as before.
  if (-not $script:BinaryCapturesAllowed) { return @() }
  return @('--dump', $DumpDir, '--dump-max', "$DumpMax")
}

function Test-ReparsePoint([System.IO.FileSystemInfo]$Item) {
  return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Remove-TreeNoFollow([string]$Path) {
  # Deletes a directory tree without ever entering a reparse point (D00
  # T02 section 45 item 1): a junction or symlink inside is removed as a
  # link, so its target's content survives.
  foreach ($c in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)) {
    if (Test-ReparsePoint $c) {
      if ($c.PSIsContainer) { [System.IO.Directory]::Delete($c.FullName, $false) } else { [System.IO.File]::Delete($c.FullName) }
    } elseif ($c.PSIsContainer) { Remove-TreeNoFollow $c.FullName }
    else { $c.Attributes = 'Normal'; [System.IO.File]::Delete($c.FullName) }
  }
  [System.IO.Directory]::Delete($Path, $false)
}

function Get-LiveRunStamps([string]$NightDir, [string]$CurrentStamp) {
  # The stamps whose staging a sweep must spare (section 45 item 1): this
  # run's own, plus the journaled run while its process is alive and it
  # has not reached final. A journal that cannot be read spares nothing
  # extra but is reported by the dead-run probe.
  $live = @()
  if ("$CurrentStamp" -ne '') { $live += $CurrentStamp }
  $j = Read-RunJournal $NightDir
  if ($j.Exists -and $j.Ok -and ($j.Phase -ne 'final') -and (Test-JournalProcessAlive $j.Pid $j.Started)) { $live += $j.Stamp }
  return @($live | Sort-Object -Unique)
}

function Clear-StaleCaptureStaging([string]$NightDir, [string]$CurrentStamp = '', [string[]]$LiveStamps = $null) {
  # A run that crashed mid-capture leaves .staging directories whose
  # bytes were never scanned; the next run sweeps them at its start
  # (section 38 item 1). The sweep is bounded (section 45 item 1): it
  # looks only at <NightDir>\<stamp>\captures-*\.staging where <stamp>
  # is a validated run-stamp name, skips the live runs (this one, and
  # the journaled run while its process lives), never enters or deletes
  # through a reparse point at any level, and deletes a tree without
  # following links inside it. Returns report notes.
  $notes = @()
  $live = if ($null -ne $LiveStamps) { @($LiveStamps) } else { @(Get-LiveRunStamps $NightDir $CurrentStamp) }
  foreach ($s in @(Get-ChildItem -LiteralPath $NightDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$' })) {
    if (Test-ReparsePoint $s) { $notes += "- capture staging: skipped stamp $($s.Name) (a reparse point; never followed)"; continue }
    if ($live -contains $s.Name) { continue }
    foreach ($c in @(Get-ChildItem -LiteralPath $s.FullName -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'captures-*' })) {
      if (Test-ReparsePoint $c) { $notes += "- capture staging: skipped $($s.Name)\$($c.Name) (a reparse point; never followed)"; continue }
      $st = Get-Item -LiteralPath (Join-Path $c.FullName $script:CaptureStagingDir) -Force -ErrorAction SilentlyContinue
      if ($null -eq $st) { continue }
      $rel = "$($s.Name)\$($c.Name)\$($script:CaptureStagingDir)"
      if (Test-ReparsePoint $st) { $notes += "- capture staging: left $rel (a reparse point, not a staging directory; do not retain that run)"; continue }
      try { Remove-TreeNoFollow $st.FullName; $notes += "- capture staging: swept crash-left $rel" }
      catch { $notes += "- capture staging: could not sweep $rel ($($_.Exception.Message)); do not retain that run" }
    }
  }
  return $notes
}

function Get-BytesSha256([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '') } finally { $sha.Dispose() }
}

function Publish-TextCapture([string]$CaptureDir, [string]$Name, [string[]]$Lines, [string]$Leg, [scriptblock]$BeforeMove = $null) {
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
    New-StagingDirectory $stageDir
    @($Lines) | Set-Content -Path $staged -Encoding UTF8
    # Scan exactly the bytes that will publish (section 38 item 1): the
    # scan reads the staged bytes once, their hash is kept, and the move
    # happens only if the file still hashes the same.
    $scannedBytes = [System.IO.File]::ReadAllBytes($staged)
    $scannedHash = Get-BytesSha256 $scannedBytes
    $hits = @(Test-CaptureSecrets ([System.Text.Encoding]::UTF8.GetString($scannedBytes)))
    if ($hits.Count -gt 0) {
      Remove-Item -LiteralPath $staged -Force -ErrorAction Stop
      "[capture redacted by the secret scan: $($hits -join ', '); see docs/testing.md Failure-capture policy]" | Set-Content -Path $final -Encoding UTF8
      $notes += "- $Leg : SECRET-SCAN redacted $Name ($($hits -join ', '))"
    } else {
      if ($null -ne $BeforeMove) { & $BeforeMove $staged }
      if ((Get-BytesSha256 ([System.IO.File]::ReadAllBytes($staged))) -ne $scannedHash) {
        Remove-Item -LiteralPath $staged -Force -ErrorAction Stop
        $notes += "- $Leg : SECRET-SCAN refused $Name (the staged bytes changed between the scan and the publish); capture dropped (fail closed)"
      } else {
        Move-Item -LiteralPath $staged -Destination $final -Force -ErrorAction Stop
      }
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
  $rows = @{ 'run-a' = @(); 'run-b' = @(); 'interactive' = @() }
  $section = ''
  foreach ($raw in (Get-Content $Path)) {
    $ln = $raw.Trim()
    if (($ln -eq '') -or $ln.StartsWith('#')) { continue }
    if ($ln -eq 'run-a:') { $section = 'run-a'; continue }
    if ($ln -eq 'run-b:') { $section = 'run-b'; continue }
    if ($ln -eq 'interactive:') { $section = 'interactive'; continue }
    $rm = [regex]::Match($ln, '^(run-a|run-b|interactive)-case-rows:$')
    if ($rm.Success) { $section = 'rows:' + $rm.Groups[1].Value; continue }
    if ($section.StartsWith('rows:') -and ($raw -match '^  \S')) { $rows[$section.Substring(5)] += $ln; continue }
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
  # The format version first (D00 T02 §44 item 7).
  $ver = if ($filters.ContainsKey('schema')) { $filters['schema'] } else { 'missing (count-only format)' }
  if ($ver -ne $script:PopulationSchema) { return (& $bad "fingerprint schema $ver is not $script:PopulationSchema; regenerate: $script:PopulationRegen") }
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
  # Case identity (D00 T02 section 37 item 5): each leg's case rows hash,
  # so a Theory row swapped at an equal total still drifts.
  foreach ($k in @('run-a-case-hash', 'run-b-case-hash', 'interactive-case-hash')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
  }
  return [pscustomobject]@{ Ok = $true; Error = ''; RunA = $runA; RunAFilter = $filters['run-a-filter']; RunBFilter = $filters['run-b-filter']; InteractiveFilter = $filters['interactive-filter']; RunB = $runB; Interactive = $interactive; RunAMethods = $counts['run-a-methods']; RunACases = $counts['run-a-cases']; RunBMethods = $counts['run-b-methods']; RunBCases = $counts['run-b-cases']; InteractiveMethods = $counts['interactive-methods']; InteractiveCases = $counts['interactive-cases']; RunACaseHash = $filters['run-a-case-hash']; RunBCaseHash = $filters['run-b-case-hash']; InteractiveCaseHash = $filters['interactive-case-hash']; RunACaseRows = @($rows['run-a']); RunBCaseRows = @($rows['run-b']); InteractiveCaseRows = @($rows['interactive']) }
}

function Get-CaseIdentityRows($Cases, [string]$Assembly = 'UI') {
  # The case-row representation (D00 T02 §44 item 2): each row is
  # `<assembly>|<display name>` (the display name carries the Theory
  # arguments in xunit's deterministic encoding), rows sort ordinally, and
  # a display name listed twice keeps both rows (the second reads
  # `#2`), so duplicates count and discovery order never matters.
  $list = New-Object 'System.Collections.Generic.List[string]'
  foreach ($c in @($Cases)) { if ($null -ne $c) { $list.Add("$c") } }
  $list.Sort([StringComparer]::Ordinal)
  $rows = @()
  $seen = @{}
  foreach ($c in $list) {
    $k = "$c"
    $n = if ($seen.ContainsKey($k)) { $seen[$k] + 1 } else { 1 }
    $seen[$k] = $n
    $rows += $(if ($n -gt 1) { "$Assembly|$c#$n" } else { "$Assembly|$c" })
  }
  return $rows
}

function Get-SourceMemberBlock([string[]]$Lines, [int]$Start) {
  # One C# member's full text from its declaration line (D00 T02 section
  # 44 R2-F1): braces are balanced across lines (string and char literals
  # aside), and an expression-bodied or field member ends at the `;` that
  # closes it at depth zero. Bounded at 4000 lines.
  $out = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $opened = $false
  for ($i = $Start; ($i -lt $Lines.Count) -and ($i -lt ($Start + 4000)); $i++) {
    $ln = $Lines[$i]
    $out.Add($ln)
    $bare = [regex]::Replace($ln, '"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''', '""')
    $bare = [regex]::Replace($bare, '//.*$', '')
    foreach ($ch in $bare.ToCharArray()) {
      if ($ch -eq '{') { $depth++; $opened = $true }
      elseif ($ch -eq '}') { $depth-- }
    }
    if ($opened -and ($depth -le 0)) { break }
    if ((-not $opened) -and ($depth -le 0) -and $bare.TrimEnd().EndsWith(';')) { break }
  }
  return ($out -join "`n")
}

function Get-TruncatedCaseSourceRows([string]$TestDir, $Cases) {
  # Identity for argument text a display name leaves out (D00 T02 section
  # 44 R1-F1, R2-F1). xunit cuts a long argument at 50 characters and
  # marks the cut with an ellipsis (U+00B7 x3 or '...'); for each method
  # with such a row, the rows return `<Class.Method>#args-source <hash>`
  # over the method's whole attribute block (every line back to the
  # previous member, so multiline attributes count), the full text of
  # every data member the attributes name (MemberData, ClassData, and any
  # typeof(T) source, whose declaring file counts whole), and, followed
  # transitively, the full text of every static member of the class those
  # blocks reference. A method whose source cannot be found reads
  # `unresolved`.
  $cut = ([string][char]0xB7) * 3
  $methods = @(@($Cases) | Where-Object { ("$_".Contains($cut)) -or ("$_".Contains('"...')) } | ForEach-Object { ("$_" -split '\(', 2)[0].Trim() } | Sort-Object -Unique)
  if ($methods.Count -eq 0) { return @() }
  $sources = @{}
  foreach ($f in @(Get-ChildItem -Path $TestDir -Filter '*.cs' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | Sort-Object FullName)) { $sources[$f.FullName] = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8) }
  $rows = @()
  foreach ($m in $methods) {
    $name = ($m -split '\.')[-1]
    $cls = ($m -split '\.')[-2]
    $block = $null
    foreach ($key in @($sources.Keys | Sort-Object)) {
      $lines = $sources[$key]
      if (-not (@($lines) -match "\bclass $cls\b")) { continue }
      for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch "\b(void|Task)\s+$name\s*\(") { continue }
        # The attribute block: every line back to the previous member's
        # end (a line ending in `}` or `;`, an opening brace, or a blank).
        $j = $i - 1
        while (($j -ge 0) -and ($lines[$j].Trim() -ne '') -and (-not ($lines[$j].TrimEnd() -match '[;{}]$'))) { $j-- }
        $attrs = if (($j + 1) -le ($i - 1)) { @($lines[($j + 1)..($i - 1)]) } else { @() }
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add(($attrs -join "`n"))
        $attrText = $attrs -join "`n"
        # Static members of the class file, by name.
        $statics = @{}
        for ($k = 0; $k -lt $lines.Count; $k++) {
          $sm = [regex]::Match($lines[$k], '\bstatic\b[^=(;{]*?\b([A-Za-z_]\w*)\s*(?:\(|=>|=|\{|;)')
          if ($sm.Success -and (-not $statics.ContainsKey($sm.Groups[1].Value))) { $statics[$sm.Groups[1].Value] = $k }
        }
        $queue = New-Object System.Collections.Generic.Queue[string]
        foreach ($mm in [regex]::Matches($attrText, '(?:MemberData|ClassData)\(\s*(?:nameof\(\s*(\w+)\s*\)|"(\w+)"|typeof\(\s*(\w+)\s*\))')) {
          foreach ($g in 1..3) { if ($mm.Groups[$g].Success) { $queue.Enqueue($mm.Groups[$g].Value) } }
        }
        # A data source on another type (MemberType = typeof(T), ClassData)
        # counts its declaring file whole.
        foreach ($tm in [regex]::Matches($attrText, 'typeof\(\s*(\w+)\s*\)')) {
          $t = $tm.Groups[1].Value
          foreach ($k2 in @($sources.Keys | Sort-Object)) { if (@($sources[$k2]) -match "\b(class|record|struct) $t\b") { $parts.Add("file " + (Split-Path -Leaf $k2) + "`n" + ($sources[$k2] -join "`n")) } }
        }
        $seen = @{}
        while ($queue.Count -gt 0) {
          $mem = $queue.Dequeue()
          if ($seen.ContainsKey($mem) -or (-not $statics.ContainsKey($mem))) { continue }
          $seen[$mem] = $true
          $body = Get-SourceMemberBlock $lines $statics[$mem]
          $parts.Add($body)
          # Transitive: static members the body names are data too.
          foreach ($idm in [regex]::Matches($body, '\b([A-Za-z_]\w*)\b')) { $id = $idm.Groups[1].Value; if ($statics.ContainsKey($id) -and (-not $seen.ContainsKey($id))) { $queue.Enqueue($id) } }
        }
        $block = $parts -join "`n----`n"
        break
      }
      if ($null -ne $block) { break }
    }
    if ($null -eq $block) { $rows += "$m#args-source unresolved"; continue }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($block))) -replace '-', '').Substring(0, 16).ToLowerInvariant() } finally { $sha.Dispose() }
    $rows += "$m#args-source $h"
  }
  return $rows
}

function Merge-AttemptNames($Attempts) {
  # Executed names over several attempts of one run (D00 T02 section 44
  # R1-F2): a retry re-executes the cases it covers, so each name counts
  # at its highest count in any one attempt, never the sum, and a retried
  # case never discharges an unexecuted twin.
  $best = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  foreach ($attempt in @($Attempts)) {
    $one = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
    foreach ($n in @($attempt)) { if ($null -ne $n) { $k = "$n".Trim(); $one[$k] = $(if ($one.ContainsKey($k)) { $one[$k] } else { 0 }) + 1 } }
    foreach ($k in $one.Keys) { if ((-not $best.ContainsKey($k)) -or ($one[$k] -gt $best[$k])) { $best[$k] = $one[$k] } }
  }
  $out = @()
  foreach ($k in $best.Keys) { for ($i = 0; $i -lt $best[$k]; $i++) { $out += $k } }
  return $out
}

function Get-CaseHash($Cases) {
  # Case-row identity: SHA-256 over the identity rows (Get-CaseIdentityRows:
  # assembly-qualified, ordinal-sorted, duplicates counted), first 16 hex;
  # 'none' when the discovery carries no case list (fixtures built by hand).
  if ($null -eq $Cases) { return 'none' }
  # Ordinal identity (D00 T02 section 37 R2-F1): PowerShell sorting and
  # uniqueness ignore case, which would fold rows differing only by a
  # string argument's casing.
  $text = (@(Get-CaseIdentityRows $Cases) -join "`n")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
  return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 16).ToLowerInvariant()
}

# The fingerprint format (D00 T02 §44 item 7): readers refuse any other
# version with the regen command, so an old count-only file never reads.
$script:PopulationSchema = 'population/2'
$script:PopulationRegen = 'powershell -File tools/Update-TestFingerprint.ps1 (after a fresh build)'

function Get-DiscoveryCaseRows($Discovery, [string]$Leg) {
  $p = $Discovery.PSObject.Properties[$Leg + 'CaseRows']
  if ($null -eq $p -or $null -eq $p.Value) { return @() }
  return @($p.Value)
}

function Get-DiscoveryCaseHash($Discovery, [string]$Leg) {
  $p = $Discovery.PSObject.Properties[$Leg + 'CaseHash']
  if ($null -eq $p -or [string]::IsNullOrEmpty("$($p.Value)")) { return 'none' }
  return "$($p.Value)"
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
    "schema: $script:PopulationSchema",
    "run-a-filter: $RunAFilter",
    "run-b-filter: $RunBFilter",
    "interactive-filter: $InteractiveFilter",
    'run-a:'
  )
  foreach ($m in (@($Discovery.RunA) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-a-methods: $($Discovery.RunAMethods)"
  $lines += "run-a-cases: $($Discovery.RunACases)"
  $lines += "run-a-case-hash: $(Get-DiscoveryCaseHash $Discovery 'RunA')"
  $lines += 'run-a-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'RunA')) { $lines += "  $r" }
  $lines += 'run-b:'
  foreach ($m in (@($Discovery.RunB) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-b-methods: $($Discovery.RunBMethods)"
  $lines += "run-b-cases: $($Discovery.RunBCases)"
  $lines += "run-b-case-hash: $(Get-DiscoveryCaseHash $Discovery 'RunB')"
  $lines += 'run-b-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'RunB')) { $lines += "  $r" }
  $lines += 'interactive:'
  foreach ($m in (@($Discovery.Interactive) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "interactive-methods: $($Discovery.InteractiveMethods)"
  $lines += "interactive-cases: $($Discovery.InteractiveCases)"
  $lines += "interactive-case-hash: $(Get-DiscoveryCaseHash $Discovery 'Interactive')"
  $lines += 'interactive-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'Interactive')) { $lines += "  $r" }
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
  foreach ($h in @(@('run-a', $fp.RunACaseHash, 'RunA'), @('run-b', $fp.RunBCaseHash, 'RunB'), @('interactive', $fp.InteractiveCaseHash, 'Interactive'))) {
    $live = Get-DiscoveryCaseHash $Discovery $h[2]
    if ($h[1] -ne $live) {
      $drifts += "$($h[0]) case rows changed: fingerprinted hash $($h[1]) vs discovered $live"
      # The rows themselves (D00 T02 §44 item 8): which cases were added
      # and removed, and the command that re-accepts them.
      $was = @($fp.($h[2] + 'CaseRows'))
      $now = @(Get-DiscoveryCaseRows $Discovery $h[2])
      if (($was.Count -gt 0) -or ($now.Count -gt 0)) {
        $addedRows = @($now | Where-Object { $was -cnotcontains $_ })
        $removedRows = @($was | Where-Object { $now -cnotcontains $_ })
        foreach ($r in ($removedRows | Select-Object -First 5)) { $drifts += "$($h[0]) case removed: $r" }
        if ($removedRows.Count -gt 5) { $drifts += "$($h[0]) case removed: ... ($($removedRows.Count) total)" }
        foreach ($r in ($addedRows | Select-Object -First 5)) { $drifts += "$($h[0]) case added: $r" }
        if ($addedRows.Count -gt 5) { $drifts += "$($h[0]) case added: ... ($($addedRows.Count) total)" }
      }
      $drifts += "$($h[0]) re-accept after review: $script:PopulationRegen"
    }
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
    # Output decodes as UTF-8 whatever the console codepage (D00 T02
    # section 44 R1-F1), so listed names never vary by host.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
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

function Invoke-WithForcedDiscovery([scriptblock]$Body) {
  # Discovery-time environment (D00 T02 section 29, section 37 items 3
  # and 4): the Interactive force opens the quiet-hours fence and the
  # listing variable lifts every gated Theory's discovery-time skip, so a
  # listing expands the same rows on every host at any hour. Both prior
  # values come back whatever the body does: a prior unset stays unset,
  # and a body that throws still restores before the throw propagates.
  $names = @('SCRATCHPAD_INTERACTIVE_FORCE', 'SCRATCHPAD_DISCOVERY_LISTING')
  $prior = @{}
  foreach ($n in $names) { $prior[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
  try {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, '1', 'Process') }
    return (& $Body)
  } finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $prior[$n], 'Process') }
  }
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
  $cap = Invoke-WithForcedDiscovery { Invoke-BoundedCapture $Dotnet @('test', $Csproj, '--no-build', '--nologo', '--filter', $Filter, '--list-tests') (Split-Path -Parent $Csproj) $TimeoutSeconds }
  if ($cap.Killed) { throw "discovery timed out for $What filter '$Filter' after ${TimeoutSeconds}s" }
  $text = $cap.Text
  if ($cap.Code -ne 0) { throw "discovery failed for $What filter '$Filter': $text" }
  $methods = @()
  $caseNames = @()
  $cases = 0
  foreach ($ln in ($text -split "`r?`n")) {
    $m = [regex]::Match($ln, '^    (\S[^(]*?)(?: \(|\(|$)')
    if (-not $m.Success) { continue }
    $cases++
    $caseNames += $ln.Trim()
    $fq = $m.Groups[1].Value.Trim()
    if ($methods -notcontains $fq) { $methods += $fq }
  }
  $methods = @($methods | Sort-Object -Unique)
  # A display name cut short hides the rest of its arguments (R1-F1): each
  # method with a truncated row adds a row for the digest of its test-data
  # source, so changing an argument past the cut changes the identity.
  $identity = @($caseNames) + @(Get-TruncatedCaseSourceRows (Split-Path -Parent $Csproj) $caseNames)
  return [pscustomobject]@{ Methods = $methods; MethodCount = $methods.Count; CaseCount = $cases; Cases = $caseNames; CaseHash = (Get-CaseHash $identity); CaseRows = @(Get-CaseIdentityRows $identity) }
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

function Get-UiBuildInputs([string]$Root) {
  # Every build input of the UI binaries (D00 T02 section 37 item 2):
  # tests/UI plus each project it references, transitively (sources,
  # XAML, project files), plus the shared build inputs at the root
  # (Directory.Build.*, Directory.Packages.props, global.json,
  # NuGet.config, .editorconfig). Configuration identity: discovery reads
  # Bin/UI/Debug, the configuration the nightly builds (its snapshot line
  # says config Debug), so a Release-only build reads as missing or stale.
  # R1-F2: besides each project directory, every ancestor
  # Directory.Build.* between a project and the root, every file an
  # MSBuild file imports (<Import Project>), and every linked item outside
  # the project directory (Compile, None, Content, Page, EmbeddedResource,
  # Manifest, and the other file item types) count, followed transitively.
  # Paths built from MSBuild properties resolve against the built-in
  # directory properties and every literal property the visited files
  # define (R2-F2); a path that still names an unresolved property lands
  # in $script:UiBuildUnresolved, and freshness refuses rather than skip it.
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $dirs = @()
  $extra = @{}
  $props = @{}
  $pending = New-Object System.Collections.Generic.List[object]
  $queue = New-Object System.Collections.Generic.Queue[string]
  $queue.Enqueue((Join-Path $Root 'tests\UI\UI.csproj'))
  $seen = @{}
  do {
  while ($queue.Count -gt 0) {
    $file = [System.IO.Path]::GetFullPath($queue.Dequeue())
    if ($seen.ContainsKey($file) -or -not (Test-Path $file)) { continue }
    $seen[$file] = $true
    $extra[$file] = $true
    $here = Split-Path -Parent $file
    $text = Get-Content $file -Raw
    # A property's own $(MSBuildThisFileDirectory) is its defining file's
    # directory, fixed where it is defined (R3-F2); two different
    # definitions of one name make it ambiguous, and a path using it
    # stays unresolved instead of guessing evaluation order.
    foreach ($pm in [regex]::Matches($text, '<([A-Za-z_][\w.]*)>([^<]*)</\1>')) {
      $pn = $pm.Groups[1].Value
      $pv = $pm.Groups[2].Value.Trim().Replace('$(MSBuildThisFileDirectory)', ($here.TrimEnd('\') + '\'))
      if (-not $props.ContainsKey($pn)) { $props[$pn] = $pv }
      elseif ($props[$pn] -ne $pv) { $props[$pn] = '$(__ambiguous__' + $pn + ')' }
    }
    if ($file -like '*proj') {
      $dirs += $here
      foreach ($m in [regex]::Matches($text, '<ProjectReference\s+Include="([^"]+)"')) { $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'queue'; From = $file }) }
      $d = $here
      while ($d.Length -ge $rootFull.Length) {
        foreach ($n in @('Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props')) {
          $f = Join-Path $d $n
          if (Test-Path $f) { $queue.Enqueue($f) }
        }
        $parent = Split-Path -Parent $d
        if ([string]::IsNullOrEmpty($parent) -or ($parent -eq $d)) { break }
        $d = $parent
      }
    }
    foreach ($m in [regex]::Matches($text, '<Import\s+Project="([^"]+)"')) { $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'queue'; From = $file }) }
    foreach ($m in [regex]::Matches($text, '<(?:Compile|None|Content|Page|EmbeddedResource|ApplicationDefinition|Manifest|Resource|AdditionalFiles|PRIResource)\s+Include="([^"]+)"')) {
      $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'file'; From = $file })
    }
  }
  # The queue drained: resolve what the files seen so far reference, now
  # that their literal properties are known; newly queued files may
  # define more, so drain and resolve again until nothing new arrives.
  $later = New-Object System.Collections.Generic.List[object]
  foreach ($p in $pending) {
    $path = Resolve-MsBuildPath $p.Raw $p.Dir $p.From $props
    if ($null -eq $path) { $later.Add($p); continue }
    if ($path.Contains('*')) {
      # A wildcard item (R3-F3): every file it matches is an input.
      foreach ($hit in @(Expand-MsBuildWildcard $path)) { $extra[$hit] = $true }
    } elseif ($p.Kind -eq 'queue') { if (-not $seen.ContainsKey($path)) { $queue.Enqueue($path) } }
    elseif (Test-Path $path -PathType Leaf) { $extra[$path] = $true }
    elseif ($p.Kind -eq 'file') {
      # A resolved item that names no file cannot be proved older than the
      # binary (R3-F2): report it instead of dropping it.
      $later.Add(@{ Dir = $p.Dir; Raw = "$($p.Raw) (resolves to missing $path)"; Kind = 'missing'; From = $p.From })
    }
  }
  $pending = $later
  } while ($queue.Count -gt 0)
  $script:UiBuildUnresolved = @($pending | ForEach-Object { "$($_.Raw) in $($_.From.Substring($rootFull.Length).TrimStart('\\'))" })
  $files = @()
  foreach ($d in ($dirs | Sort-Object -Unique)) {
    $files += @(Get-ChildItem -Path $d -Recurse -Include '*.cs', '*.csproj', '*.xaml', '*.props', '*.targets', '*.resw', '*.json' -File |
      Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' })
  }
  foreach ($n in @('Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props', 'global.json', 'NuGet.config', '.editorconfig')) {
    $f = Join-Path $Root $n
    if (Test-Path $f) { $extra[[System.IO.Path]::GetFullPath($f)] = $true }
  }
  foreach ($k in $extra.Keys) { $files += Get-Item $k }
  return $files
}

function Expand-MsBuildWildcard([string]$Pattern) {
  # MSBuild item wildcards: `*` within a segment, `**` across segments.
  # The walk starts at the longest wildcard-free prefix directory.
  $segments = $Pattern -split '\\'
  $fixed = @()
  foreach ($seg in $segments) { if ($seg.Contains('*')) { break } ; $fixed += $seg }
  $base = $fixed -join '\'
  if (-not (Test-Path $base -PathType Container)) { return @() }
  $rx = '^' + (([regex]::Escape($Pattern)) -replace '\\\*\\\*\\\\', '(?:.*\\)?' -replace '\\\*', '[^\\]*') + '$'
  return @(Get-ChildItem -Path $base -Recurse -File | Where-Object { $_.FullName -match $rx -and $_.FullName -notmatch '\\(obj|bin)\\' } | ForEach-Object { $_.FullName })
}

function Resolve-MsBuildPath([string]$Raw, [string]$Dir, [string]$From, $Props) {
  # One MSBuild path: built-in directory properties, then literal
  # properties, repeated until nothing changes; null while any $(...)
  # stays unresolved.
  $v = $Raw
  $builtin = @{ MSBuildThisFileDirectory = ($Dir.TrimEnd('\') + '\'); MSBuildProjectDirectory = $Dir; MSBuildThisFileFullPath = $From }
  for ($i = 0; $i -lt 8 -and $v -match '\$\(([\w.]+)\)'; $i++) {
    $v = [regex]::Replace($v, '\$\(([\w.]+)\)', {
      param($m)
      $n = $m.Groups[1].Value
      if ($builtin.ContainsKey($n)) { return $builtin[$n] }
      if ($Props.ContainsKey($n)) { return $Props[$n] }
      return $m.Value
    })
  }
  if ($v -match '\$\(') { return $null }
  if (-not [System.IO.Path]::IsPathRooted($v)) { $v = Join-Path $Dir $v }
  if ($v.Contains('*')) {
    # Windows PowerShell's GetFullPath rejects wildcards: normalize the
    # wildcard-free prefix and keep the pattern segments as written.
    $segs = $v -split '\\'
    $cut = 0
    while (($cut -lt $segs.Count) -and (-not $segs[$cut].Contains('*'))) { $cut++ }
    return ([System.IO.Path]::GetFullPath(($segs[0..($cut - 1)] -join '\')).TrimEnd('\') + '\' + ($segs[$cut..($segs.Count - 1)] -join '\'))
  }
  return [System.IO.Path]::GetFullPath($v)
}

# Content provenance for the UI build (D00 T02 section 44 item 1).

function Get-FileSha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
}

function Get-BuildInputsDigest([string]$Root, [string]$Sdk, $Inputs = $null) {
  # One line per input (`<root-relative path> <sha256>`, ordinal-sorted),
  # the restore result, and the SDK version; the digest is SHA-256 over
  # the lines. $Inputs overrides the discovered set (fixtures).
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $files = if ($null -ne $Inputs) { @($Inputs) } else { @(Get-UiBuildInputs $Root | ForEach-Object { $_.FullName }) }
  $assets = Join-Path $rootFull 'tests\UI\obj\project.assets.json'
  if ((Test-Path $assets) -and ($null -eq $Inputs)) { $files += $assets }
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($f in $files) {
    $full = [System.IO.Path]::GetFullPath("$f")
    $rel = if ($full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $full.Substring($rootFull.Length + 1) } else { $full }
    $hash = if (Test-Path -LiteralPath $full) { Get-FileSha256 $full } else { 'missing' }
    $lines.Add("$($rel.Replace('\', '/')) $hash")
  }
  $lines.Sort([StringComparer]::Ordinal)
  $lines.Add("sdk $Sdk")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $digest = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))) -replace '-', '').Substring(0, 16).ToLowerInvariant() } finally { $sha.Dispose() }
  return [pscustomobject]@{ Digest = $digest; Lines = @($lines) }
}

function Test-BuildInputsDigest([string]$Root, [string]$DigestFile, [string]$Sdk, $Inputs = $null) {
  # The content freshness check: the digest recorded beside the binary at
  # build time must equal the inputs' digest now. Names the first
  # differing entry so the refusal says what changed.
  if (-not (Test-Path $DigestFile)) { return [pscustomobject]@{ Ok = $false; Error = "UI build has no content digest ($DigestFile); an incremental build that compiles nothing writes none, so rebuild: dotnet build src/ScratchPad.slnx --no-incremental" } }
  $recorded = @(Get-Content -LiteralPath $DigestFile)
  $now = Get-BuildInputsDigest $Root $Sdk $Inputs
  if (($recorded.Count -gt 0) -and ($recorded[0].Trim() -eq $now.Digest)) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $was = @($recorded | Select-Object -Skip 1 | Where-Object { $_ -ne '' })
  $changed = @($now.Lines | Where-Object { $was -cnotcontains $_ }) + @($was | Where-Object { $now.Lines -cnotcontains $_ })
  $first = if ($changed.Count -gt 0) { ($changed[0] -split ' ', 2)[0] } else { '?' }
  return [pscustomobject]@{ Ok = $false; Error = "UI build is stale by content: its build inputs changed since the build (first: $first; $($changed.Count) differing entries, timestamps notwithstanding); rebuild without incremental skips (a timestamp-restored input would not recompile): dotnet build src/ScratchPad.slnx --no-incremental" }
}

function Get-UiSdkVersion([string]$Root) {
  # The SDK the build records (NETCoreSdkVersion): the repo-local
  # toolchain's version, else the PATH one, else '' when neither answers.
  try { $dn = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'; if (-not (Test-Path $dn)) { $dn = 'dotnet' }; return "$(& $dn --version)".Trim() } catch { return '' }
}

function Get-UiBuildFreshness([string]$Root) {
  $dll = Join-Path $Root 'Bin\UI\Debug\UI.dll'
  if (-not (Test-Path $dll)) { return [pscustomobject]@{ Ok = $false; Error = "UI build missing: $dll; run: dotnet build src/ScratchPad.slnx, then retry" } }
  $inputs = @(Get-UiBuildInputs $Root)
  if (@($script:UiBuildUnresolved).Count -gt 0) {
    # An input the check cannot locate cannot be proved older than the
    # binary (R2-F2): refuse, naming each.
    return [pscustomobject]@{ Ok = $false; Error = "UI build freshness unprovable: unresolved build input path(s): $($script:UiBuildUnresolved -join '; ')" }
  }
  $newest = $inputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($null -eq $newest) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $r = Test-UiBuildFresh (Get-Item $dll).LastWriteTimeUtc $newest.LastWriteTimeUtc $dll
  if (-not $r.Ok) { $r.Error = $r.Error -replace 'the newest tests/UI source', "its newest build input ($($newest.FullName.Substring($Root.Length).TrimStart('\')))"; return $r }
  # Content freshness (D00 T02 section 44 item 1): the digest the build
  # recorded beside the binary must equal the inputs' digest now, so an
  # edit whose timestamp was restored, a deletion, or a property or SDK
  # change is caught where timestamps say fresh.
  return (Test-BuildInputsDigest $Root (Join-Path $Root 'Bin\UI\Debug\build-inputs.digest') (Get-UiSdkVersion $Root))
}

function Get-UnexecutedCaseRows($ListedCases, $ExecutedNames, [string]$Why) {
  # Per-case debt (D00 T02 section 37 item 6, section 15's promise):
  # every listed case the leg never executed stays owed, grouped by
  # method, so a Theory with one of three rows run keeps two owed. The
  # collector reruns the method filter (every row of it).
  # Ordinal identity (R2-F1): a case differing only by casing is its own
  # case, so executing one never discharges the other.
  # Reconciliation is by count per display name (D00 T02 §44 item 4): a
  # name listed twice owes two rows, a retry executing it twice never
  # discharges more than was listed, and skipped or aborted rows (absent
  # from the executed names) stay owed.
  $ran = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  foreach ($e in @($ExecutedNames)) { if ($null -ne $e) { $k = "$e".Trim(); $ran[$k] = $(if ($ran.ContainsKey($k)) { $ran[$k] } else { 0 }) + 1 } }
  $byMethod = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
  $order = New-Object System.Collections.Generic.List[string]
  foreach ($c in @($ListedCases)) {
    if ($null -eq $c) { continue }
    $name = "$c".Trim()
    $method = ($name -split '\(', 2)[0].Trim()
    if (-not $byMethod.ContainsKey($method)) { $byMethod[$method] = @{ Listed = 0; Owed = 0; Cases = (New-Object System.Collections.Generic.List[string]) }; $order.Add($method) }
    $byMethod[$method].Listed++
    if ($ran.ContainsKey($name) -and ($ran[$name] -gt 0)) { $ran[$name]-- }
    else { $byMethod[$method].Owed++; $byMethod[$method].Cases.Add($name) }
  }
  $rows = @()
  foreach ($k in $order) {
    $v = $byMethod[$k]
    # The row names its owed cases (item 5), so a collection closes each
    # case only on its own green execution.
    if ($v.Owed -gt 0) { $rows += "- Night-owed: $k | $($v.Owed) of $($v.Listed) cases unexecuted ($Why) | collector filter: FullyQualifiedName=$k | cases: $(@($v.Cases) -join ' ;; ')" }
  }
  return $rows
}

function Close-OwedCases([string[]]$OwedCases, [string[]]$PassedNames, $ListedCases = $null) {
  # Per-case closure (D00 T02 §44 item 5): the collector reruns the
  # method, and each owed case closes only when its own row executed
  # green. A display name the listing carries more than once (R2-F2)
  # names indistinguishable twins, so no single green row can tell which
  # twin ran: its owed copies close only when every listed copy of the
  # name ran green in the same collection. Without a listing each name
  # counts as listed once (the §44 item 5 behavior). Returns the cases
  # still owed.
  $green = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  foreach ($p in @($PassedNames)) { if ($null -ne $p) { $k = "$p".Trim(); $green[$k] = $(if ($green.ContainsKey($k)) { $green[$k] } else { 0 }) + 1 } }
  $listed = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  foreach ($l in @($ListedCases)) { if ($null -ne $l) { $k = "$l".Trim(); $listed[$k] = $(if ($listed.ContainsKey($k)) { $listed[$k] } else { 0 }) + 1 } }
  $left = @()
  foreach ($c in @($OwedCases)) {
    if ($null -eq $c) { continue }
    $k = "$c".Trim()
    $g = if ($green.ContainsKey($k)) { $green[$k] } else { 0 }
    $copies = if ($listed.ContainsKey($k)) { $listed[$k] } else { 1 }
    if ($copies -gt 1) {
      # Twins: all or nothing.
      if ($g -ge $copies) { continue }
      $left += $k
      continue
    }
    if ($g -gt 0) { $green[$k] = $g - 1 } else { $left += $k }
  }
  return $left
}

function Get-OwedCaseNames([string[]]$Rows) {
  # The case names the per-case owed rows name (`| cases: a ;; b`).
  $names = @()
  foreach ($r in @($Rows)) {
    $m = [regex]::Match("$r", '\| cases: (.+)$')
    if ($m.Success) { $names += @($m.Groups[1].Value -split ' ;; ' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
  }
  return $names
}

function Get-TrxPassedNames([string]$TrxPath) {
  # The cases a trx records green, once per test case (R3-I1): a case
  # counts when its last result passed, so a retry that passed after a
  # failure is one green case and never two. Missing or unreadable reads
  # as none.
  return @(Get-TrxCaseResults $TrxPath | Where-Object { $_.Last -eq 'Passed' } | ForEach-Object { $_.Name })
}

function Resolve-CarriedCaseDebt($PreviousOwed, [string[]]$PassedTonight, [bool]$InteractiveRan, $ListedCases = $null) {
  # Per-case debt across nights (D00 T02 section 44 R1-F4): the cases the
  # last result still owed close only on their own green row tonight
  # (Close-OwedCases); when the interactive leg did not run, all stay owed.
  # Returns Still (the cases still owed) and the report Line.
  $prev = @(@($PreviousOwed) | Where-Object { "$_" -ne '' })
  if ($prev.Count -eq 0) { return [pscustomobject]@{ Still = @(); Line = '' } }
  # Wrapped whole: an if expression unrolls a one-element array.
  $still = @(if ($InteractiveRan) { Close-OwedCases $prev $PassedTonight $ListedCases } else { $prev })
  $closed = $prev.Count - $still.Count
  return [pscustomobject]@{ Still = $still; Line = "- Carried per-case debt: $closed of $($prev.Count) earlier owed case(s) closed on their own green rows; $($still.Count) still owed" }
}

function Merge-OwedCases($Tonight, $Carried) {
  # One obligation per case (D00 T02 section 44 R2-F4): tonight's owed
  # cases and the earlier ones still owed overlap when a case went
  # unexecuted on both nights, so each name counts at its larger count,
  # never the sum (Merge-AttemptNames' rule).
  return @(Merge-AttemptNames (@(, @($Tonight)) + @(, @($Carried))))
}

function Read-PreviousOwedCases([string]$NightDir, [string]$Stamp) {
  # The earlier owed cases (section 44 R2-F5): the newest result before
  # $Stamp that reads; an unreadable newer result is named, never taken
  # as no debt, and the walk continues to the next older result, so a
  # corrupt result cannot erase outstanding obligations. Returns Owed,
  # From (the result read), and Unreadable (names).
  $bad = @()
  $cands = @(Get-ChildItem -LiteralPath $NightDir -Filter 'morning-*.result.json' -File -ErrorAction SilentlyContinue | Where-Object { ($_.Name -match '^morning-(\d{4}-\d{2}-\d{2}-\d{6})\.result\.json$') -and ($Matches[1] -lt $Stamp) } | Sort-Object Name -Descending)
  foreach ($f in $cands) {
    try {
      # A result must validate as a result (R3-R1): `{}` or a partial
      # document is refused like unparseable JSON, never read as no debt.
      $v = Test-ResultFile $f.FullName
      if (-not $v.Ok) { throw $v.Error }
      $o = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      $fs = ($f.Name -replace '^morning-', '') -replace '\.result\.json$', ''
      if ("$($o.stamp)" -ne $fs) { throw "stamp $($o.stamp) disagrees with its file name" }
      $owedProp = $o.PSObject.Properties['owedCases']
      if (($null -ne $owedProp) -and ($null -ne $owedProp.Value) -and (@(@($owedProp.Value) | Where-Object { $_ -isnot [string] }).Count -gt 0)) { throw 'owedCases is not a list of case names' }
      return [pscustomobject]@{ Owed = @(@($o.owedCases) | Where-Object { "$_" -ne '' }); From = $f.Name; Unreadable = $bad }
    } catch { $bad += "$($f.Name) ($($_.Exception.Message))" }
  }
  return [pscustomobject]@{ Owed = @(); From = ''; Unreadable = $bad }
}

function Get-PopulationIdentity([string]$FingerprintPath) {
  # The population a proof stands on (D00 T02 §44 item 6): the three legs'
  # case hashes, so a regen that swaps a case row changes it while a
  # comment or ordering edit does not. 'unknown' when unreadable.
  $fp = Read-TestPopulationFile $FingerprintPath
  if (-not $fp.Ok) { return 'unknown' }
  return (Get-CaseHash @("run-a=$($fp.RunACaseHash)", "run-b=$($fp.RunBCaseHash)", "interactive=$($fp.InteractiveCaseHash)"))
}

function Get-TrxCaseResults([string]$TrxPath) {
  # One entry per test case the trx records (D00 T02 section 44 R3-I1):
  # results group by the case's testId (executionId when a row has none),
  # so repeated results of one case (a retry) count once while two cases
  # sharing a display name stay two. Each entry carries the name, whether
  # any result executed (Passed or Failed), and the last result's outcome.
  # Missing or truncated trx reads as none.
  if (-not (Test-Path $TrxPath)) { return @() }
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return @() }
  $byCase = [ordered]@{}
  $n = 0
  foreach ($r in @($t.TestRun.Results.UnitTestResult)) {
    if ($null -eq $r) { continue }
    $n++
    $id = "$($r.testId)"
    if ($id -eq '') { $id = "$($r.executionId)" }
    if ($id -eq '') { $id = "row-$n" }
    if (-not $byCase.Contains($id)) { $byCase[$id] = [pscustomobject]@{ Name = "$($r.testName)"; Executed = $false; Last = '' } }
    if (@('Passed', 'Failed') -contains "$($r.outcome)") { $byCase[$id].Executed = $true }
    $byCase[$id].Last = "$($r.outcome)"
  }
  return @($byCase.Values)
}

function Get-TrxExecutedNames([string]$TrxPath) {
  # Test names the trx records as run (Passed or Failed), once per test
  # case (R3-I1); skipped rows never executed.
  return @(Get-TrxCaseResults $TrxPath | Where-Object { $_.Executed } | ForEach-Object { $_.Name })
}

function Get-CandidateCiGate($Runs, $Jobs, [string]$Sha, [string]$Step = 'Check test population fingerprint') {
  # The CI population check gates the night (D00 T02 section 37 item 1).
  # $Runs is `gh run list --commit <sha> --workflow build.yml --json
  # databaseId,status,conclusion` output (newest first); $Jobs is `gh run
  # view <id> --json jobs` for the newest run. Returns State (green, red,
  # pending, none) plus the line the report quotes; Resolve-CiAdmission
  # decides admission.
  $run = @($Runs) | Where-Object { $null -ne $_ } | Select-Object -First 1
  if ($null -eq $run) { return [pscustomobject]@{ State = 'none'; Line = "CI population check not verified: no build.yml run for $Sha" } }
  $found = $null
  foreach ($j in @($Jobs.jobs)) { foreach ($s in @($j.steps)) { if ("$($s.name)" -eq $Step) { $found = $s } } }
  if ($null -eq $found) {
    if ("$($run.status)" -ne 'completed') { return [pscustomobject]@{ State = 'pending'; Line = "CI population check not verified: run $($run.databaseId) is $($run.status)" } }
    return [pscustomobject]@{ State = 'none'; Line = "CI population check not verified: run $($run.databaseId) has no '$Step' step" }
  }
  $c = "$($found.conclusion)"
  if ($c -eq 'success') { return [pscustomobject]@{ State = 'green'; Line = "CI population check green on $Sha (run $($run.databaseId))" } }
  if ($c -in @('failure', 'cancelled', 'timed_out')) { return [pscustomobject]@{ State = 'red'; Line = "CI population check $c on $Sha (run $($run.databaseId)): the population is refused" } }
  return [pscustomobject]@{ State = 'pending'; Line = "CI population check not verified: step '$Step' in run $($run.databaseId) reads '$c'" }
}

function Resolve-CiAdmission($Gate, [bool]$AllowUnverified, [string]$TreeState = 'clean') {
  # Admission (D00 T02 section 37 R1-F1): only green admits. Red, pending,
  # or unverifiable CI refuses the population, naming the state; the
  # operator override admits a non-red state and the line says so. A red
  # check is never overridden.
  # A dirty or unreadable tree is not the commit CI checked (R3-F1): a
  # green HEAD vouches for nothing the working tree changed, so it reads
  # as not verified.
  if (($Gate.State -eq 'green') -and ($TreeState -ne 'clean')) {
    $Gate = [pscustomobject]@{ State = 'none'; Line = "$($Gate.Line), but the built tree is $TreeState, so CI did not check this candidate" }
  }
  if ($Gate.State -eq 'green') { return [pscustomobject]@{ State = $Gate.State; Admitted = $true; Line = $Gate.Line } }
  if (($Gate.State -ne 'red') -and $AllowUnverified) {
    return [pscustomobject]@{ State = $Gate.State; Admitted = $true; Line = "$($Gate.Line); admitted without CI verification (-AllowUnverifiedCi)" }
  }
  $why = if ($Gate.State -eq 'red') { $Gate.Line } else { "$($Gate.Line); the population is refused (only a green CI population check admits it; -AllowUnverifiedCi overrides a non-red state)" }
  return [pscustomobject]@{ State = $Gate.State; Admitted = $false; Line = $why }
}

function Get-CandidateCiState([string]$Root, [string]$Sha) {
  # Live read through gh; any failure reads as not verified, never red.
  try {
    $runs = & gh run list --commit $Sha --workflow build.yml --json databaseId,status,conclusion --limit 1 2>$null | Out-String | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "gh run list exited $LASTEXITCODE" }
    $jobs = $null
    $first = @($runs) | Select-Object -First 1
    if ($null -ne $first) {
      $jobs = & gh run view $first.databaseId --json jobs 2>$null | Out-String | ConvertFrom-Json
      if ($LASTEXITCODE -ne 0) { throw "gh run view exited $LASTEXITCODE" }
    }
    return Get-CandidateCiGate $runs $jobs $Sha
  } catch {
    return [pscustomobject]@{ State = 'none'; Line = "CI population check not verified: $($_.Exception.Message)" }
  }
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
    $out | Add-Member -NotePropertyName ($leg[0] + 'CaseHash') -NotePropertyValue $one.CaseHash -Force
    $out | Add-Member -NotePropertyName ($leg[0] + 'CaseRows') -NotePropertyValue @($one.CaseRows) -Force
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
      $map["$($e.id)"] = [pscustomobject]@{ id = "$($e.id)"; test = "$($e.test)"; phase = "$($e.phase)"; key = "$($e.key)"; owner = "$($e.owner)"; state = "$($e.state)"; firstSeen = "$($e.firstSeen)"; lastSeen = "$($e.lastSeen)"; closedAt = "$($e.closedAt)"; closedBy = "$($e.closedBy)"; occurrences = $occ; passStreak = [int]$e.passStreak; lastPassStamp = "$($e.lastPassStamp)"; due = "$($e.due)"; finding = "$($e.finding)"; streakPopulation = "$(if ($null -ne $e.PSObject.Properties['streakPopulation']) { $e.streakPopulation })" }
    }
    return [pscustomobject]@{ Ok = $true; Error = ''; Incidents = $map; Stamp = "$(if ($null -ne $j.PSObject.Properties['stamp']) { $j.stamp })" }
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

function Add-IncidentLink([string]$Path, [string]$Id, [string]$Finding, [scriptblock]$Writer = $null) {
  # Records one incident -> finding link (section 38 item 9), idempotent:
  # an id already linked to the same finding writes nothing; an id
  # linked to another finding refuses (triage decides, never an
  # overwrite); a failed write leaves the file as it was, so the incident
  # stays unlinked and re-lists next run. The write is temp plus rename
  # with read-back. Returns Status (linked, already, conflict, failed)
  # plus Line.
  if ($Id -notmatch '^INC-[0-9a-f]{8}$') { return [pscustomobject]@{ Status = 'failed'; Line = "link refused: '$Id' is not an incident id" } }
  if ($Finding -notmatch '^(D\d{2} T\d{2} \u00A7\d+|[0-9a-f]{7,40})$') { return [pscustomobject]@{ Status = 'failed'; Line = "link refused: '$Finding' is not a section ref or commit" } }
  $links = Read-IncidentLinks $Path
  if ($links.ContainsKey($Id)) {
    if ($links[$Id] -eq $Finding) { return [pscustomobject]@{ Status = 'already'; Line = "$Id already links $Finding" } }
    return [pscustomobject]@{ Status = 'conflict'; Line = "link refused: $Id already links $($links[$Id]), not $Finding" }
  }
  try {
    $text = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { "# Incident links`n`n| Incident | Finding | Note |`n| --- | --- | --- |`n" }
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    $text += "| $Id | $Finding | |`n"
    $tmp = "$Path.tmp"
    if ($null -ne $Writer) { & $Writer $tmp $text } else { [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false))) }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
  } catch {
    if (Test-Path "$Path.tmp") { Remove-Item "$Path.tmp" -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Status = 'failed'; Line = "link write failed for $Id ($($_.Exception.Message)); it stays unlinked and re-lists next run" }
  }
  $back = Read-IncidentLinks $Path
  if ($back[$Id] -ne $Finding) { return [pscustomobject]@{ Status = 'failed'; Line = "link read-back failed for $Id" } }
  return [pscustomobject]@{ Status = 'linked'; Line = "$Id -> $Finding" }
}

function Get-OverdueIncidentNotices([hashtable]$Incidents, [datetime]$Today) {
  # Owner notifications for open incidents past their due date (section
  # 38 item 8): one per incident, naming its owner, keyed by id and day
  # so the morning reconcile sends each once a day.
  $out = @()
  foreach ($k in ($Incidents.Keys | Sort-Object)) {
    $e = $Incidents[$k]
    if ("$($e.state)" -ne 'open') { continue }
    # A due date that is not a real day is named, never fatal to the batch
    # (R3-F2).
    $due = [datetime]::MinValue
    if (-not [datetime]::TryParseExact("$($e.due)", 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$due)) {
      if ("$($e.due)" -ne '') { $out += [pscustomobject]@{ Id = "$($e.id)"; Owner = "$($e.owner)"; Due = "$($e.due)"; RunId = "incident-baddue-$($e.id)-$($Today.ToString('yyyy-MM-dd'))"; Title = "Incident $($e.id) has an invalid due date"; Line = "$($e.id) ``$($e.test)`` carries due date '$($e.due)', not a real day; triage corrects it in the ledger" } }
      continue
    }
    if ($due -ge $Today) { continue }
    $owner = if ("$($e.owner)" -eq '') { $script:TriageOwner } else { "$($e.owner)" }
    $out += [pscustomobject]@{ Id = "$($e.id)"; Owner = $owner; Due = "$($e.due)"; RunId = "incident-overdue-$($e.id)-$($Today.ToString('yyyy-MM-dd'))"; Title = "Incident $($e.id) overdue (owner $owner, due $($e.due))"; Line = "$($e.id) ``$($e.test)`` is open past its due date $($e.due); owner ${owner}: link its finding in docs/incident-links.md or close it" }
  }
  return $out
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
    # Identity and history ride each row (section 30 R2-F2), so a rebuild
    # restores an incident whose original results have aged out.
    # Lossless (section 38 item 5): the key, closure, last pass, and each
    # occurrence's wheres ride the row too, so a rebuild reproduces every
    # ledger field.
    [pscustomobject]@{ id = "$($e.id)"; test = "$($e.test)"; phase = "$($e.phase)"; key = "$($e.key)"; state = "$($e.state)"; owner = "$($e.owner)"; occurrences = @($e.occurrences).Count; occurrenceStamps = @(@($e.occurrences) | ForEach-Object { "$($_.stamp)" }); occurrenceWheres = @(@($e.occurrences) | ForEach-Object { (@($_.wheres) | Where-Object { $null -ne $_ } | ForEach-Object { "$_" }) -join ',' }); firstSeen = "$($e.firstSeen)"; lastSeen = "$($e.lastSeen)"; closedAt = "$($e.closedAt)"; closedBy = "$($e.closedBy)"; passStreak = [int]$e.passStreak; streakPopulation = "$(if ($null -ne $e.PSObject.Properties['streakPopulation']) { $e.streakPopulation })"; lastPassStamp = "$($e.lastPassStamp)"; contract = 'v2'; due = "$($e.due)"; finding = "$($e.finding)" }
  })
}

function Update-IncidentLedger([hashtable]$Ledger, $Groups, [string]$Stamp, [hashtable]$PassedByPhase, [hashtable]$Owners, [int]$RecoveryRuns = 3, [hashtable]$Links = @{}, [string]$Population = '', [string]$NotQualifying = '') {
  # Verified recovery counts only qualifying runs (D00 T02 section 45
  # item 6): a run named not qualifying ($NotQualifying: aborted, killed
  # or budget-cut, a stub or simulation, or evidence that failed its own
  # checks) records its failures as occurrences but neither advances
  # nor resets any streak. Per test, a run that skipped or quarantined
  # the test never executed it, which already neither counts nor resets.
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
    if ($NotQualifying -eq '') { $e.passStreak = 0 }
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
    if ($NotQualifying -ne '') {
      if ([int]$e.passStreak -gt 0) { $lines += "- $id ``$($e.test)``: streak held at $($e.passStreak) of $RecoveryRuns (run not qualifying: $NotQualifying)" }
      continue
    }
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
    # A streak stands on one test population (D00 T02 §44 item 6): passes
    # recorded against another case population read stale, so updating
    # the fingerprint never revives old evidence toward a closure.
    if ($Population -ne '') {
      if (@($e.PSObject.Properties.Name) -notcontains 'streakPopulation') { $e | Add-Member -NotePropertyName streakPopulation -NotePropertyValue '' }
      # A streak recorded before populations were (an empty population)
      # has no provenance either (R1-F5): it resets like a changed one.
      if (([int]$e.passStreak -gt 0) -and ("$($e.streakPopulation)" -ne $Population)) {
        $was = if ("$($e.streakPopulation)" -eq '') { 'unrecorded' } else { "$($e.streakPopulation)" }
        $lines += "- $id ``$($e.test)``: streak reset (population $was -> ${Population}: the earlier passes stand stale)"
        $e.passStreak = 0
      }
      $e.streakPopulation = $Population
    }
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

function Read-LifecycleBlock($Result) {
  # The lifecycle block's consumer contract (section 38 item 7; the table
  # in docs/testing.md): a result without the block (written before
  # section 30) reads Absent with no rows; a block without a version is
  # version 1 (written before this contract); a version this code does
  # not know reads Unsupported and is never trusted. Every consumer
  # (the presence check, the rebuild, notify, trend, triage) reads the
  # block through here.
  if ($null -eq $Result) { return [pscustomobject]@{ State = 'absent'; Version = 0; Rows = @(); Error = '' } }
  $names = @($Result.PSObject.Properties.Name)
  if ($names -notcontains 'incidentLifecycle') { return [pscustomobject]@{ State = 'absent'; Version = 0; Rows = @(); Error = '' } }
  $v = 1
  if ($names -contains 'incidentLifecycleVersion') {
    if ("$($Result.incidentLifecycleVersion)" -notmatch '^[1-9]\d*$') { return [pscustomobject]@{ State = 'unsupported'; Version = 0; Rows = @(); Error = "incidentLifecycleVersion '$($Result.incidentLifecycleVersion)' is not a positive whole number" } }
    $v = [int]$Result.incidentLifecycleVersion
  }
  if ($v -gt $script:LifecycleContractVersion) { return [pscustomobject]@{ State = 'unsupported'; Version = $v; Rows = @(); Error = "incidentLifecycleVersion $v is newer than this reader ($($script:LifecycleContractVersion))" } }
  # Rows validate against the contract's types, enums, and invariants
  # (R1-F4): the same checks the result validator runs.
  $rowErr = Test-LifecycleRows @($Result.incidentLifecycle)
  if ($rowErr -ne '') { return [pscustomobject]@{ State = 'invalid'; Version = $v; Rows = @(); Error = $rowErr } }
  return [pscustomobject]@{ State = 'ok'; Version = $v; Rows = @($Result.incidentLifecycle | Where-Object { $null -ne $_ }); Error = '' }
}

function Test-LifecycleRows($Rows) {
  # The lifecycle row contract (section 38 item 7): returns '' when every
  # row holds, else the first violation. Shared by Read-LifecycleBlock and
  # Test-ResultFile, so a consumer and the validator never disagree.
  $lifeIds = @{}
  foreach ($row in @($Rows)) {
    if ($null -eq $row) { return 'result incidentLifecycle has a null row' }
    if ($lifeIds.ContainsKey("$($row.id)")) { return "result incidentLifecycle duplicate id $($row.id)" }
    $lifeIds["$($row.id)"] = $true
    $names = @($row.PSObject.Properties.Name)
    foreach ($f in @('id', 'test', 'phase', 'state', 'owner', 'occurrences', 'firstSeen', 'passStreak', 'contract')) {
      if (($names -notcontains $f) -or ("$($row.$f)" -eq '')) { return "result incidentLifecycle row $($row.id) missing $f" }
    }
    if ("$($row.id)" -notmatch '^INC-[0-9a-f]{8}$') { return "result incidentLifecycle id malformed: $($row.id)" }
    if (@('open', 'closed') -notcontains "$($row.state)") { return "result incidentLifecycle $($row.id) state $($row.state)" }
    if ("$($row.occurrences)" -notmatch '^[1-9]\d*$') { return "result incidentLifecycle $($row.id) occurrences '$($row.occurrences)' is not a positive whole number" }
    if (($names -notcontains 'occurrenceStamps') -or (@($row.occurrenceStamps).Count -ne [int]"$($row.occurrences)")) { return "result incidentLifecycle $($row.id) occurrenceStamps disagree with occurrences ($($row.occurrences))" }
    # Every occurrence names its stamp (R2-F2): an empty one would rebuild
    # as a lost occurrence.
    if (@(@($row.occurrenceStamps) | Where-Object { "$_" -notmatch '^\S+$' }).Count -gt 0) { return "result incidentLifecycle $($row.id) has an empty occurrence stamp" }
    if (($names -contains 'occurrenceWheres') -and (@($row.occurrenceWheres).Count -ne [int]"$($row.occurrences)")) { return "result incidentLifecycle $($row.id) occurrenceWheres disagree with occurrences ($($row.occurrences))" }
    if ("$($row.passStreak)" -notmatch '^\d+$') { return "result incidentLifecycle $($row.id) passStreak '$($row.passStreak)' is not a whole number" }
    if ("$($row.contract)" -ne 'v2') { return "result incidentLifecycle $($row.id) contract '$($row.contract)' unsupported (want v2)" }
    if (("$($row.due)" -ne '') -and ("$($row.due)" -notmatch '^\d{4}-\d{2}-\d{2}$')) { return "result incidentLifecycle $($row.id) due '$($row.due)' is not YYYY-MM-DD" }
    if (("$($row.finding)" -ne '') -and ("$($row.finding)" -notmatch '^(D\d{2} T\d{2} \u00A7\d+|[0-9a-f]{7,40})$')) { return "result incidentLifecycle $($row.id) finding '$($row.finding)' is not a section ref or commit" }
    if (("$($row.state)" -eq 'closed') -and ($names -contains 'closedAt') -and ("$($row.closedAt)" -eq '')) { return "result incidentLifecycle $($row.id) is closed with no closedAt" }
  }
  return ''
}

function Get-LatestLifecycleSnapshot([string[]]$ResultFiles, [string]$Since) {
  # The newest incidentLifecycle block that is the ledger's own state
  # (source `ledger`, section 30 R2-F1): a run whose ledger was missing
  # or unreadable publishes `unavailable` and never counts. The chosen
  # snapshot is validated whole by Test-ResultFile (R4-F1): an invalid
  # one is reported in Error, never silently thinned, because a rebuild
  # from it would drop recoverable history. Returns Stamp, Rows, Error
  # ($null Stamp when no snapshot exists).
  $snap = @()
  $snapStamp = $null
  $snapFile = ''
  $snapBlk = $null
  foreach ($f in @($ResultFiles)) {
    try { $o = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $blk = Read-LifecycleBlock $o
    if (($blk.State -ne 'absent') -and ("$($o.incidentLifecycleSource)" -eq 'ledger') -and ("$($o.stamp)" -ge $Since) -and (($null -eq $snapStamp) -or ("$($o.stamp)" -gt $snapStamp))) { $snap = $blk.Rows; $snapStamp = "$($o.stamp)"; $snapFile = $f; $snapBlk = $blk }
  }
  $err = ''
  if (($snapFile -ne '') -and ($snapBlk.State -eq 'unsupported')) {
    $err = "lifecycle snapshot $snapStamp ($snapFile) is unreadable: $($snapBlk.Error)"
  } elseif ($snapFile -ne '') {
    $v = Test-ResultFile $snapFile
    if (-not $v.Ok) { $err = "lifecycle snapshot $snapStamp ($snapFile) is invalid: $($v.Error)" }
  }
  return [pscustomobject]@{ Stamp = $snapStamp; Rows = $snap; Error = $err; File = $snapFile }
}

function Get-ProtectedSnapshot([string]$NightDir) {
  # The protected lifecycle snapshot (D00 T02 section 45 item 3): the
  # newest ledger-sourced result a rebuild restores from. Each run writes
  # its result through Write-AtomicReport, so the newest snapshot is
  # replaced whole, never in place. Retention counts its bytes against
  # the exempt quota, prune keeps its stamp directory, and a quota
  # refusal names it; it is never offered for release. Returns File,
  # Stamp, and Bytes ($null File when no snapshot exists).
  $files = @(Get-ChildItem -LiteralPath $NightDir -Filter 'morning-*.result.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $files += @(Get-ChildItem -LiteralPath (Join-Path $NightDir 'retained') -Filter 'result.json' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $s = Get-LatestLifecycleSnapshot $files ''
  if (("$($s.File)" -eq '') -or (-not (Test-Path -LiteralPath $s.File))) { return [pscustomobject]@{ File = $null; Stamp = $null; Bytes = [long]0 } }
  return [pscustomobject]@{ File = $s.File; Stamp = $s.Stamp; Bytes = [long](Get-Item -LiteralPath $s.File).Length }
}

function Read-LedgerRecord([string]$Path) {
  # The tracked initialization record (section 38 item 4): `Ledger
  # started: YYYY-MM-DD` once, plus `Reset: YYYY-MM-DD <reason>` lines
  # the operator adds when a ledger loss is intended.
  if (-not (Test-Path $Path)) { return [pscustomobject]@{ Found = $false; Started = ''; Resets = @() } }
  $started = ''
  $resets = @()
  foreach ($ln in (Get-Content $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^Ledger started:\s*(\d{4}-\d{2}-\d{2})')
    if ($m.Success -and ($started -eq '')) { $started = $m.Groups[1].Value }
    $r = [regex]::Match($ln, '^Reset:\s*(\d{4}-\d{2}-\d{2})\s+\S')
    if ($r.Success) { $resets += $r.Groups[1].Value }
  }
  return [pscustomobject]@{ Found = $true; Started = $started; Resets = $resets }
}

function Test-IncidentLedgerPresence([string]$LedgerPath, [string[]]$ResultFiles, [string]$Since, [string]$RecordPath = '', [datetime]$Today = (Get-Date).Date) {
  # A missing ledger reads as empty only when no earlier result carries
  # incidents, either as incident lines or in its published lifecycle
  # snapshot (section 30 item 4, R3-F1: a snapshot outlives the failure
  # results it summarizes); otherwise every failure would re-file as
  # new, so the run reds with the rebuild instruction.
  if (Test-Path -LiteralPath $LedgerPath) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $rows = @(Get-IncidentResultRows $ResultFiles $Since)
  $snap = Get-LatestLifecycleSnapshot $ResultFiles $Since
  # An invalid snapshot is evidence too: it cannot be read as empty.
  if (($rows.Count -eq 0) -and (@($snap.Rows).Count -eq 0) -and ($snap.Error -eq '')) {
    # No evidence left: legitimate only before the ledger ever started,
    # or right after the operator recorded an intended reset (section 38
    # item 4). Otherwise the ledger and every result carrying incidents
    # were deleted together, and history is gone.
    if ($RecordPath -eq '') { return [pscustomobject]@{ Ok = $true; Error = '' } }
    $rec = Read-LedgerRecord $RecordPath
    if ((-not $rec.Found) -or ($rec.Started -eq '')) { return [pscustomobject]@{ Ok = $true; Error = '' } }
    # Today or yesterday only (R2-F1): a future-dated reset authorizes
    # nothing, so it cannot pre-approve later wipes.
    $fresh = @($rec.Resets | Where-Object { $rd = [datetime]::ParseExact($_, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture); ($rd -ge $Today.AddDays(-1)) -and ($rd -le $Today) })
    if ($fresh.Count -gt 0) { return [pscustomobject]@{ Ok = $true; Error = '' } }
    return [pscustomobject]@{ Ok = $false; Error = "incident ledger and every result carrying incidents are gone, but $RecordPath records the ledger started $($rec.Started): incident history was lost; if the loss is intended, add ``Reset: $($Today.ToString('yyyy-MM-dd')) <reason>`` there and re-run" }
  }
  $what = @()
  if ($rows.Count -gt 0) { $what += "$($rows.Count) earlier result(s) carry incidents (latest $($rows[-1].Stamp))" }
  if (@($snap.Rows).Count -gt 0) { $what += "the $($snap.Stamp) lifecycle snapshot holds $(@($snap.Rows).Count) incident(s)" }
  if ($snap.Error -ne '') { $what += $snap.Error }
  return [pscustomobject]@{ Ok = $false; Error = "incident ledger missing while $($what -join ' and '); rebuild: powershell -NoProfile -ExecutionPolicy Bypass -File tools/NightlyLedger.ps1 -Rebuild" }
}

function Get-LedgerCheckpoints([string]$NightDir) {
  # The per-run ledger checkpoints (D00 T02 section 45 item 4): each run
  # writes its ledger state into its own stamp directory right after the
  # ledger itself, so a crash between the ledger write and the result
  # write still leaves that run's state on disk. Returns the checkpoint
  # paths.
  return @(Get-ChildItem -LiteralPath $NightDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$' } | ForEach-Object { Join-Path $_.FullName $script:LedgerCheckpointName } | Where-Object { Test-Path -LiteralPath $_ })
}

function Resolve-LedgerRollForward($LedgerRead, [string[]]$CheckpointFiles) {
  # The checkpoint is written before the ledger (D00 T02 section 45 R1-F5),
  # so a crash between the two leaves the checkpoint as the later state:
  # when the newest readable checkpoint is newer than the ledger's own
  # stamp, the run continues from the checkpoint and says so. Returns
  # Incidents, Stamp, and Line ('' when the ledger is current).
  $best = $null
  foreach ($c in @($CheckpointFiles)) {
    $r = Read-IncidentLedger $c
    if ((-not $r.Ok) -or ("$($r.Stamp)" -eq '')) { continue }
    if (($null -eq $best) -or ($r.Stamp -gt $best.Stamp)) { $best = $r }
  }
  if (($null -ne $best) -and ($best.Stamp -gt "$($LedgerRead.Stamp)")) {
    return [pscustomobject]@{ Incidents = $best.Incidents; Stamp = $best.Stamp; Line = "- ledger rolled forward to checkpoint $($best.Stamp) (the ledger read $(if ("$($LedgerRead.Stamp)" -ne '') { $LedgerRead.Stamp } else { 'no stamp' }); a crash left it behind its checkpoint)" }
  }
  return [pscustomobject]@{ Incidents = $LedgerRead.Incidents; Stamp = "$($LedgerRead.Stamp)"; Line = '' }
}

function Get-ResultChainGaps([string[]]$ResultFiles, [string[]]$KnownStamps, [string]$After) {
  # Missing intermediate results (section 45 item 4): each result names
  # the result before it (previousStamp); a named predecessor after the
  # restore point that no result or checkpoint carries is a gap the
  # rebuild cannot replay. Returns one line per gap, oldest first.
  $known = @{}
  foreach ($s in @($KnownStamps)) { if ("$s" -ne '') { $known["$s"] = $true } }
  $gaps = @()
  foreach ($f in @($ResultFiles)) {
    try { $o = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $prev = "$(if ($null -ne $o.PSObject.Properties['previousStamp']) { $o.previousStamp })"
    if (($prev -eq '') -or ($prev -le $After) -or $known.ContainsKey($prev)) { continue }
    $gaps += [pscustomobject]@{ Stamp = $prev; Line = "result $prev is missing (run $($o.stamp) names it as its predecessor)" }
  }
  return @($gaps | Sort-Object Stamp -Unique | ForEach-Object { $_.Line })
}

function New-IncidentLedgerFromResults([string[]]$ResultFiles, [string]$Since, [hashtable]$Owners, [hashtable]$Links = @{}, [string[]]$CheckpointFiles = @(), [switch]$AcceptGaps) {
  # Rebuild (section 30 item 4, R3-F2): the newest ledger-sourced
  # incidentLifecycle snapshot is the last published state, so it is
  # restored first (identity, state, owner, occurrence stamps, pass
  # streak, due date, finding; incidents whose failure results aged out
  # included), and only results stamped after it replay on top through
  # Update-IncidentLedger. A closed incident that recurred later reopens
  # with its history instead of being overwritten back to closed. With
  # no snapshot, every result replays and recovery restarts from zero.
  $map = @{}
  $snap = Get-LatestLifecycleSnapshot $ResultFiles $Since
  # An invalid newest snapshot stops the rebuild (R4-F1): restoring from
  # it, or skipping to an older one, would persist a ledger missing
  # history the operator can still recover by repairing the result.
  if ($snap.Error -ne '') { throw "rebuild refused: $($snap.Error); repair or move that result aside, then re-run" }
  # A checkpoint newer than the snapshot is the later state (section 45
  # item 4): a crash between the ledger write and the result write left
  # it without its result, so it is restored instead and only results
  # after it replay.
  $base = $snap.Stamp
  $cp = $null
  $cpStamps = @()
  foreach ($c in @($CheckpointFiles)) {
    $r = Read-IncidentLedger $c
    if ((-not $r.Ok) -or ("$($r.Stamp)" -eq '')) { continue }
    $cpStamps += $r.Stamp
    if (("$($r.Stamp)" -ge $Since) -and ((($null -eq $base) -or ($r.Stamp -gt $base)) -and (($null -eq $cp) -or ($r.Stamp -gt $cp.Stamp)))) { $cp = $r }
  }
  $resultStamps = @(foreach ($f in @($ResultFiles)) { try { "$((Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).stamp)" } catch { } })
  $after = if ($null -ne $cp) { $cp.Stamp } elseif ($null -ne $base) { $base } else { '' }
  $script:LedgerRebuildGaps = @(Get-ResultChainGaps $ResultFiles (@($resultStamps) + @($cpStamps)) $after)
  if (($script:LedgerRebuildGaps.Count -gt 0) -and (-not $AcceptGaps)) { throw "rebuild refused: $($script:LedgerRebuildGaps -join '; '); restore the missing result(s), or pass -AcceptGaps to rebuild without them (their occurrences are lost)" }
  # The rebuilt state's own stamp (R3-F3): the latest stamp the rebuild
  # applied, over the restore point and every result replayed, so a
  # later roll-forward never mistakes an older checkpoint for newer.
  $script:LedgerRebuildStamp = "$(if ($null -ne $cp) { $cp.Stamp } elseif ($null -ne $base) { $base })"
  foreach ($rs in @($resultStamps)) { if (("$rs" -ne '') -and ("$rs" -ge $Since) -and ("$rs" -gt $script:LedgerRebuildStamp)) { $script:LedgerRebuildStamp = "$rs" } }
  if ($null -ne $cp) {
    foreach ($k in @($cp.Incidents.Keys)) { $map[$k] = $cp.Incidents[$k] }
    foreach ($r in @(Get-IncidentResultRows $ResultFiles $Since)) {
      if ($r.Stamp -le $cp.Stamp) { continue }
      $map = (Update-IncidentLedger $map $r.Groups $r.Stamp @{} $Owners 3 $Links).Incidents
    }
    $script:LedgerRebuildBase = "checkpoint $($cp.Stamp)"
    return $map
  }
  $script:LedgerRebuildBase = $(if ($null -ne $base) { "snapshot $base" } else { 'no snapshot (full replay)' })
  foreach ($row in @($snap.Rows)) {
    $stamps = @(@($row.occurrenceStamps) | ForEach-Object { "$_" })
    $closed = ("$($row.state)" -eq 'closed')
    $names = @($row.PSObject.Properties.Name)
    # Rows since section 38 carry every ledger field and restore exactly;
    # older rows restore what they carry (the section 30 behavior).
    $full = ($names -contains 'occurrenceWheres') -and ($names -contains 'closedAt')
    $whereList = @($row.occurrenceWheres)
    $occ = @()
    for ($i = 0; $i -lt $stamps.Count; $i++) {
      if ($stamps[$i] -eq '') { continue }
      $w = @()
      if ($full -and ($i -lt $whereList.Count) -and ("$($whereList[$i])" -ne '')) { $w = @("$($whereList[$i])" -split ',') }
      $occ += [pscustomobject]@{ stamp = $stamps[$i]; wheres = $w }
    }
    if (-not $full) { $occ = @($occ | Sort-Object stamp) }
    $map["$($row.id)"] = [pscustomobject]@{ id = "$($row.id)"; test = "$($row.test)"; phase = "$($row.phase)"; key = $(if ($full) { "$($row.key)" } else { '' }); owner = "$($row.owner)"; state = $(if ($closed) { 'closed' } else { 'open' }); firstSeen = "$($row.firstSeen)"; lastSeen = "$($row.lastSeen)"; closedAt = $(if ($full) { "$($row.closedAt)" } elseif ($closed) { $snap.Stamp } else { '' }); closedBy = $(if ($full) { "$($row.closedBy)" } elseif ($closed) { "restored from the $($snap.Stamp) result snapshot" } else { '' }); occurrences = $occ; passStreak = [int]$row.passStreak; streakPopulation = "$(if ($null -ne $row.PSObject.Properties['streakPopulation']) { $row.streakPopulation })"; lastPassStamp = $(if ($full) { "$($row.lastPassStamp)" } else { '' }); due = "$($row.due)"; finding = "$($row.finding)" }
  }
  foreach ($r in @(Get-IncidentResultRows $ResultFiles $Since)) {
    if (($null -ne $snap.Stamp) -and ($r.Stamp -le $snap.Stamp)) { continue }
    $map = (Update-IncidentLedger $map $r.Groups $r.Stamp @{} $Owners 3 $Links).Incidents
  }
  return $map
}

function Get-TrapDisposition([string]$NightDir, [string]$Stamp) {
  # What the cancellation trap may write (D00 T02 section 24 redesign,
  # operator decision 2026-09-25): the run's own result file is the
  # durable publication receipt. Write-AtomicReport lands it by an atomic
  # rename, so it either exists whole or not at all; once it exists for
  # this stamp, the run's evidence is on disk and nothing the trap does
  # may replace it or the report built from it. No in-memory flag and no
  # ordering against the journal decides this. Returns Landed, ResultPath,
  # and Reason. A leftover `.tmp` never counts; a file that exists but no
  # longer parses still counts as landed (the trap never overwrites it:
  # the corruption lifecycle owns it).
  $p = Join-Path $NightDir "morning-$Stamp.result.json"
  if (("$Stamp" -eq '') -or (-not (Test-Path -LiteralPath $p -PathType Leaf))) { return [pscustomobject]@{ Landed = $false; ResultPath = $p; Reason = 'no result landed for this run' } }
  $o = $null
  try { $o = Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return [pscustomobject]@{ Landed = $true; ResultPath = $p; Reason = 'result landed but no longer parses (left for the corruption record)' } }
  if (("$($o.stamp)" -ne '') -and ("$($o.stamp)" -ne $Stamp)) { return [pscustomobject]@{ Landed = $true; ResultPath = $p; Reason = "result file names stamp $($o.stamp) (left untouched)" } }
  return [pscustomobject]@{ Landed = $true; ResultPath = $p; Reason = "result landed (verdict $($o.verdict))" }
}

function Write-PostResultFailure([string]$NightDir, [string]$Stamp, [string]$Day, [string]$Message) {
  # The failure record for a run whose result already landed (section 24
  # redesign): a stamp-scoped note beside the run, never the day report
  # and never the result, so the landed evidence and its acknowledgement
  # checksum stand. Returns the note's path.
  $path = Join-Path $NightDir "morning-$Stamp-failure.md"
  Write-AtomicReport @("# Run failure after its result landed: $Stamp", 'Status: failed-after-result', '', "- Day: $Day", "- Failure: $Message", "- At: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", "- Result: morning-$Stamp.result.json (left untouched; its report may be missing, and next-start recovery records the unfinished run)") $path
  return $path
}

function Write-IncidentLedger([hashtable]$Incidents, [string]$Path, [string]$Stamp = '') {
  # Atomic write plus read-back: a ledger that cannot be read back is a
  # failed write the caller reports, never a silent loss. The optional
  # stamp names the run whose state this is (D00 T02 section 45 item 4),
  # so a checkpoint orders against the results. Returns '' on success,
  # else the error.
  $list = @($Incidents.Keys | Sort-Object | ForEach-Object { $Incidents[$_] })
  $doc = [ordered]@{ version = 1 }
  if ($Stamp -ne '') { $doc['stamp'] = $Stamp }
  $doc['incidents'] = $list
  $json = ConvertTo-Json ([pscustomobject]$doc) -Depth 8
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
  return [pscustomobject]@{ State = 'dirty'; Fingerprint = $fp; Count = $porc.Count; Rows = @($rows) }
}

function Register-TrackedWrite([hashtable]$Writes, [string]$Root, [string]$Path, [string]$Line, [string]$Note, [string]$BeforeText) {
  # The collector's tracked writes (D00 T02 section 45 item 7): the run
  # never commits; each Night-collected or Night-red line it writes into
  # a TODO file is recorded with that file's text before the run's
  # first write, so the tree check can expect exactly those lines and
  # the triage step (tools/NightlyTriage.ps1) commits them. Only a write
  # whose note says it appended registers a line.
  $rel = ($Path.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/'
  if (-not $Writes.ContainsKey($rel)) { $Writes[$rel] = [pscustomobject]@{ File = $rel; Before = $BeforeText; Lines = @() } }
  if ("$Note" -like 'appended*') { $Writes[$rel].Lines = @($Writes[$rel].Lines) + @($Line) }
}

function Test-TrackedWriteOnly([string]$Before, [string]$After, [string[]]$Lines) {
  # True when $After is $Before plus exactly $Lines inserted (each once),
  # line endings aside: removing each recorded line once from $After
  # must give back $Before.
  $a = New-Object System.Collections.Generic.List[string]
  foreach ($l in @("$After" -split "`r?`n")) { $a.Add($l) }
  foreach ($l in @($Lines)) { $i = $a.IndexOf("$l"); if ($i -lt 0) { return $false }; $a.RemoveAt($i) }
  # Case-sensitive (R3-F1): a case-only edit is an edit.
  return ((@($a) -join "`n") -ceq (@("$Before" -split "`r?`n") -join "`n"))
}

function Compare-TreeWithTrackedWrites([string]$Root, $Start, $End, [hashtable]$Writes, $StartTexts = $null) {
  # The tree check expects the collector's writes (section 45 item 7):
  # a file the run wrote counts as expected when its text is its
  # pre-write text plus exactly the registered lines; the start and end
  # fingerprints then compare without those files. Anything else that
  # changed still reads MUTATED. Returns Line, Ok, Expected (files).
  $expected = @()
  $bad = @()
  foreach ($k in @($Writes.Keys | Sort-Object)) {
    $w = $Writes[$k]
    if (@($w.Lines).Count -eq 0) { continue }
    $full = Join-Path $Root $w.File
    $now = if (Test-Path -LiteralPath $full) { [System.IO.File]::ReadAllText($full) } else { '' }
    # The pre-write text must be the file as the run found it (R2-F1):
    # an edit between the start fingerprint and the collector's write
    # would otherwise join the accepted baseline.
    if (($null -ne $StartTexts) -and ((-not $StartTexts.ContainsKey($w.File)) -or ("$($StartTexts[$w.File])" -cne "$($w.Before)"))) { $bad += $w.File; continue }
    if (Test-TrackedWriteOnly $w.Before $now @($w.Lines)) { $expected += $w.File } else { $bad += $w.File }
  }
  $drop = { param($rows) @(@($rows) | Where-Object { $p = ("$_" -split '\|')[1]; $expected -notcontains ($p -replace '\\', '/') }) }
  $sRows = & $drop $Start.Rows
  $eRows = & $drop $End.Rows
  $unknown = ($Start.State -eq 'unknown') -or ($End.State -eq 'unknown')
  $same = (-not $unknown) -and ((@($sRows | Sort-Object) -join "`n") -eq (@($eRows | Sort-Object) -join "`n"))
  $nLines = 0
  foreach ($k in $expected) { $nLines += @($Writes[$k].Lines).Count }
  $exp = if ($expected.Count -gt 0) { "; collector wrote $nLines line(s) to $($expected -join ', '), verified; triage commits them: tools/NightlyTriage.ps1 -Commit" } else { '' }
  if ($bad.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Expected = $expected; Line = "MUTATED ($($bad -join ', ') changed beyond the collector's recorded lines$exp)" } }
  if (-not $same) { return [pscustomobject]@{ Ok = $false; Expected = $expected; Line = "MUTATED (start $($Start.State):$($Start.Count):$($Start.Fingerprint), end $($End.State):$($End.Count):$($End.Fingerprint)$exp)" } }
  $base = if ($sRows.Count -eq 0) { 'clean at start and end' } else { "stable ($($Start.State):$($sRows.Count) path(s) outside the collector's writes)" }
  return [pscustomobject]@{ Ok = $true; Expected = $expected; Line = "$base$exp" }
}

function Write-TrackedWriteManifest([hashtable]$Writes, [string]$Path) {
  # The triage step's input (section 45 item 7): one entry per file with
  # its registered lines, written atomically beside the run.
  # Each entry keeps the file's pre-write text and its SHA-256 (R1-F2),
  # so the record alone shows what the run started from.
  $list = @($Writes.Keys | Sort-Object | ForEach-Object { $w = $Writes[$_]; if (@($w.Lines).Count -gt 0) { [pscustomobject]@{ file = $w.File; beforeSha256 = (Get-BytesSha256 ([System.Text.Encoding]::UTF8.GetBytes("$($w.Before)"))); before = "$($w.Before)"; lines = @($w.Lines) } } })
  Write-AtomicReport @((ConvertTo-Json ([pscustomobject]@{ version = 1; writes = @($list) }) -Depth 5)) $Path
}

function Format-EvidenceSummary([string[]]$Lines, [string]$Stamp = '') {
  # One summary block per run (D00 T02 section 45 item 8): the degraded
  # evidence of the run, each class with its count and next action,
  # scanned from the report lines the run already wrote. Classes:
  # capture refusals, truncation, privacy gates, ledger faults, overdue
  # incidents. A run with none reads one complete line.
  $classes = @(
    @('capture refusals', '(CAPTURE-REFUSED|capture refused|dump refused|\.dmp (not written|refused))', 'review tools/incident-policy.json binaryCaptures and the refusal marker; rerun the leg to capture'),
    @('truncation', '(TRUNCATED|truncated)', 'read the capture budget marker; raise the cap or narrow the leg'),
    @('privacy gates', '(SECRET-SCAN|redacted|PROTECTION REFUSED)', 'inspect the redacted capture; never retain it unredacted'),
    @('ledger faults', '(RED: incident ledger|incident ledger (write|read-back|missing|invalid|unreadable)|ledger checkpoint write failed)', 'repair or rebuild the ledger: tools/NightlyLedger.ps1 -Rebuild'),
    @('overdue incidents', '^- OVERDUE: ', 'triage each overdue incident and link its finding: tools/NightlyLedger.ps1 -Link')
  )
  $out = @()
  foreach ($c in $classes) {
    $hits = @(@($Lines) | Where-Object { "$_" -match $c[1] })
    if ($hits.Count -gt 0) { $out += "- $($c[0]): $($hits.Count) (next: $($c[2]))" }
  }
  if ($out.Count -eq 0) { return @('- Evidence complete: no capture refusals, truncation, privacy gates, ledger faults, or overdue incidents') }
  return @("- Evidence DEGRADED$(if ($Stamp -ne '') { " for $Stamp" }): $($out.Count) class(es)") + $out
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
  # The revision orders a run's copies (D00 T02 section 31 item 5):
  # optional (older results predate it), a positive whole number when present.
  if ((@($o.PSObject.Properties.Name) -contains 'revision') -and ("$($o.revision)" -notmatch '^[1-9]\d*$')) { return [pscustomobject]@{ Ok = $false; Error = "result revision '$($o.revision)' is not a positive whole number" } }
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
  # The block names its source (section 30 R2-F1): `ledger` when it is
  # the ledger's state, `unavailable` when the ledger could not be read,
  # so a rebuild never mistakes a failed run's empty block for state.
  # A block written before the source field existed (between section 30
  # R1 and R2) reads with an unknown source: valid to read, never trusted
  # by a rebuild, and refused on the nightly's own self-check.
  $hasSource = @($o.PSObject.Properties.Name) -contains 'incidentLifecycleSource'
  if ($hasLife -and $RequireLifecycle -and (-not $hasSource)) { return [pscustomobject]@{ Ok = $false; Error = 'result incidentLifecycleSource missing' } }
  if ($hasLife -and $hasSource -and (@('ledger', 'unavailable') -notcontains "$($o.incidentLifecycleSource)")) { return [pscustomobject]@{ Ok = $false; Error = "result incidentLifecycleSource '$($o.incidentLifecycleSource)' unknown (want ledger or unavailable)" } }
  if ($hasLife) {
    # The shared lifecycle row contract (section 38 item 7).
    $rowErr = Test-LifecycleRows @($o.incidentLifecycle)
    if ($rowErr -ne '') { return [pscustomobject]@{ Ok = $false; Error = $rowErr } }
    # The same version rule the readers apply (R2-F2): a version newer
    # than this code is unsupported, never valid.
    $blk = Read-LifecycleBlock $o
    if (@('unsupported', 'invalid') -contains $blk.State) { return [pscustomobject]@{ Ok = $false; Error = "result $($blk.Error)" } }
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

function Get-ScheduledNight([datetime]$LocalStart, [string[]]$TriggerTimes) {
  # A timer launch serves the latest trigger instant at or before its
  # start (section 32 R5-C1): the task's StartWhenAvailable can run a
  # missed 02:30 trigger hours late, and that late run still belongs to
  # the trigger's own night. Falls back to Get-NightKey when no trigger
  # time reads.
  $best = $null
  foreach ($tt in @($TriggerTimes)) {
    $ts = [TimeSpan]::Zero
    if (-not [TimeSpan]::TryParse("$tt", [ref]$ts)) { continue }
    $cand = $LocalStart.Date + $ts
    if ($cand -gt $LocalStart) { $cand = $cand.AddDays(-1) }
    if (($null -eq $best) -or ($cand -gt $best)) { $best = $cand }
  }
  if ($null -eq $best) { return (Get-NightKey $LocalStart) }
  return $best.Date.ToString('yyyy-MM-dd')
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
    $legs[$leg] = [ordered]@{ ran = $(try { [bool]$o.ran } catch { $false }); passed = (& $num $o.passed); failed = (& $num $o.failed); skipped = (& $num $o.skipped); gate = $(try { $g0 = $o.gate; if ($null -eq $g0) { $null } elseif ("$g0" -match '^-?\d{1,9}$') { [int]$g0 } else { Protect-DisclosedText "$g0" } } catch { $null }); killed = $(try { [bool]$o.killed } catch { $false }); cut = $(try { [bool]$o.cut } catch { $false }); testSeconds = $(try { & $num $o.testSeconds } catch { $null }); enforcementRed = $(try { [bool]$o.enforcementRed } catch { $false }) }
  }
  $incs = @()
  # Whole incident lines (disclosed), so phase and failure class survive
  # for the alias map and recurrence (section 32 R3-I1).
  foreach ($ln in @($Result.incidents)) { if ([regex]::IsMatch("$ln", '(INC-[0-9a-f]{8}) `([^`]+)`')) { $incs += (Protect-DisclosedText "$ln") } }
  # Provenance sources and locators pass the disclosure contract before
  # they persist (D00 T02 section 32 item 14).
  $prov = $null
  try { if ($null -ne $Result.provenance) { $prov = [ordered]@{}; foreach ($pp in @($Result.provenance.PSObject.Properties)) { $pv = [ordered]@{}; foreach ($q in @($pp.Value.PSObject.Properties)) { $pv[$q.Name] = Protect-DisclosedText "$($q.Value)" }; $prov[$pp.Name] = [pscustomobject]$pv } } } catch { $prov = $null }
  return [ordered]@{
    schema = 'metrics/1'; identity = "$($Result.identity)"; revision = $(try { $Result.revision } catch { $null }); stamp = "$($Result.stamp)"; day = "$($Result.day)"; night = (Get-ResultNight $Result)
    # Explainable after pruning (section 40 item 13): the row names its
    # source result (identity plus host) and the derivation that built it.
    source = "morning-$($Result.stamp).result.json"; hostKey = (Get-ResultHostKey $Result); derivation = $script:MetricsDerivation; excluded = "$(try { $Result.excluded } catch { '' })"
    verdict = "$($Result.verdict)"; launch = "$($Result.launch)"; simulated = $(try { [bool]$Result.simulated } catch { $false }); backfill = (Test-IsBackfill $Result)
    legs = $legs; soak = [ordered]@{ verdict = $(try { "$($Result.soak.verdict)" } catch { '' }); ran = $(try { [bool]$Result.soak.ran } catch { $false }); failed = $(try { $sf0 = $Result.soak.failed; if ($sf0 -is [array]) { ,@($sf0 | ForEach-Object { Protect-DisclosedText "$_" }) } elseif ($null -eq $sf0) { 0 } else { [int]$sf0 } } catch { 0 }); killed = $(try { $k0 = @(@($Result.soak.killed) | Where-Object { $null -ne $_ } | ForEach-Object { Protect-DisclosedText "$_" }); if ($k0.Count -gt 0) { ,$k0 } else { $null } } catch { $null }); cut = $(try { $c0 = @(@($Result.soak.cut) | Where-Object { $null -ne $_ } | ForEach-Object { Protect-DisclosedText "$_" }); if ($c0.Count -gt 0) { ,$c0 } else { $null } } catch { $null }) }
    incidents = $incs; reserve = $(try { & $num $Result.reserve } catch { $null }); consumed = $(try { & $num $Result.consumed } catch { $null })
    env = $(try { $eo = [ordered]@{}; foreach ($k in $script:EnvFields) { $eo[$k] = Protect-DisclosedText $(try { "$($Result.env.$k)" } catch { 'unknown' }) }; $eo } catch { [ordered]@{ os = 'unknown'; dpi = 'unknown' } })
    quarantine = $(try { [ordered]@{ overdue = @(@($Result.quarantine.overdue) | Where-Object { $null -ne $_ } | ForEach-Object { Protect-DisclosedText "$_" }); dueSoon = @(@($Result.quarantine.dueSoon) | Where-Object { $null -ne $_ } | ForEach-Object { Protect-DisclosedText "$_" }); overdueDetail = @(@($Result.quarantine.overdueDetail) | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ Test = (Protect-DisclosedText "$($_.Test)"); Due = "$($_.Due)"; Owner = (Protect-DisclosedText "$($_.Owner)") } }) } } catch { $null })
    recovered = $(try { Protect-DisclosedText "$($Result.recovered)" } catch { 'none' })
    buildError = $(try { Protect-DisclosedText "$($Result.buildError)" } catch { '' })
    # Absent stays absent (section 32 R4-I1): the classifier reads a
    # missing field differently from a true one, so equivalence needs it.
    omissionOk = $(try { if ($null -eq $Result.omissionOk) { $null } else { [bool]$Result.omissionOk } } catch { $null })
    scheduler = $(try { [ordered]@{ voted = [bool]$Result.scheduler.voted; faults = @(@($Result.scheduler.faults) | ForEach-Object { Protect-DisclosedText "$_" }) } } catch { [ordered]@{ voted = $false; faults = @() } })
    harness = $(try { Protect-DisclosedText "$($Result.harness)" } catch { '' })
    incidentEvidence = $(try { if ($null -eq $Result.incidentEvidence) { $null } else { $ie = [ordered]@{}; foreach ($pp in @($Result.incidentEvidence.PSObject.Properties)) { $ie[$pp.Name] = @(@($pp.Value) | ForEach-Object { Protect-DisclosedText "$_" }) }; [pscustomobject]$ie } } catch { $null })
    populationHash = $(try { Protect-DisclosedText "$($Result.populationHash)" } catch { '' })
    populationState = $(try { "$($Result.populationState)" } catch { '' })
    executedUnique = $(try { $Result.executedUnique } catch { $null })
    provenance = $(if ($null -ne $prov) { [pscustomobject]$prov } else { $null })
    population = $(try { Protect-DisclosedText "$($Result.population)" } catch { '' })
    commit = $(try { Protect-DisclosedText "$($Result.commit)" } catch { '' })
    # Phase timings ride the row so a metrics-only night renders its
    # budget line exactly as the raw result did (section 32 item 12).
    timings = $(try { $tm = $Result.timings; if ($null -eq $tm) { $null } else { $to = [ordered]@{}; $names = if ($tm -is [hashtable]) { @($tm.Keys) } else { @($tm.PSObject.Properties.Name) }; foreach ($k in $names) { $vv = $(try { $tm.$k } catch { $tm[$k] }); $to[(Protect-DisclosedText "$k")] = $(try { [double]$vv } catch { $null }) }; [pscustomobject]$to } } catch { $null })
  }
}

function Invoke-WithMetricsLock([scriptblock]$Body) {
  # One writer at a time on the metrics store (D00 T02 section 32 item
  # 10): a named mutex serializes every read-modify-append, so two
  # renders never interleave half-lines. An abandoned mutex (a writer
  # that died holding it) is taken over, not waited on forever.
  $mtx = New-Object System.Threading.Mutex($false, 'Local\ScratchPad.NightlyMetrics')
  $held = $false
  try {
    try { $held = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw 'metrics store lock timed out after 30 s' }
    return (& $Body)
  } finally {
    if ($held) { $mtx.ReleaseMutex() }
    $mtx.Dispose()
  }
}

function Test-MetricsRowShape($Row) {
  # A row is data only when every consumed value is sound (section 32
  # R1-A2, R2-A1): schema, identity, stamp, a real calendar night, a known
  # verdict, legs as an object whose counts are whole numbers or absent,
  # and seconds that are numbers or absent. Anything else is malformed.
  if ("$($Row.schema)" -ne 'metrics/1') { return $false }
  if (("$($Row.identity)" -eq '') -or ("$($Row.stamp)" -eq '')) { return $false }
  $d = [datetime]::MinValue
  if (-not [datetime]::TryParseExact("$($Row.night)", 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return $false }
  if (@('green', 'red', 'stood-down', 'cancelled') -notcontains "$($Row.verdict)") { return $false }
  if (@($Row.PSObject.Properties.Name) -notcontains 'legs') { return $false }
  $legs = $Row.legs
  if (($null -eq $legs) -or ($legs -is [string]) -or ($legs -is [array]) -or ($legs -is [ValueType])) { return $false }
  foreach ($lp in @($legs.PSObject.Properties)) {
    $o = $lp.Value
    if (($null -eq $o) -or ($o -is [string]) -or ($o -is [ValueType])) { return $false }
    # Whole numbers that fit the Int32 the renderer casts to (section 32
    # R4-A1): a longer digit string would render as zero and look healthy.
    foreach ($k in @('passed', 'failed', 'skipped')) { $v = $o.$k; if (($null -ne $v) -and ("$v" -notmatch '^\d{1,9}$')) { return $false } }
    # Execution flags are booleans or absent (section 32 R5-A1): an array
    # or string would cast to false and hide the leg's failures.
    foreach ($k in @('ran', 'killed', 'cut', 'enforcementRed')) { $v = $o.$k; if (($null -ne $v) -and (-not ($v -is [bool]))) { return $false } }
    $ts = $o.testSeconds
    if (($null -ne $ts) -and ("$ts" -notmatch '^\d+(\.\d+)?$')) { return $false }
  }
  return $true
}

function Get-MetricsKey($Item) {
  # The store key (section 40 R3-F3): a run identity is stamp plus pid,
  # which two hosts can share, so a row with a recorded host keys as
  # identity@host; a legacy row (no host) keeps its bare identity, so
  # stores written before hosts were recorded read unchanged.
  $id = "$($Item.identity)"
  $h = "$(try { $Item.hostKey } catch { '' })"
  if (($id -ne '') -and ($h -ne '') -and ($h -ne 'legacy')) { return "$id@$h" }
  return $id
}

function Read-MetricsStore([string]$Path) {
  # Per-line validation (item 10): a line is a row only when it parses
  # with schema metrics/1 and an identity; supersession records
  # (schema supersession/1) load beside the rows; anything else,
  # including a truncated last line, is reported by line number and
  # never read as data. Returns Rows (last per identity), Raw (identity
  # -> line), Supersessions, Malformed (line numbers), EndsClean.
  $out = [pscustomobject]@{ Rows = [ordered]@{}; Raw = @{}; Supersessions = @(); Malformed = @(); Rejected = 0; EndsClean = $true }
  if (-not (Test-Path $Path)) { return $out }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if (($bytes.Length -gt 0) -and ($bytes[-1] -ne 10)) { $out.EndsClean = $false }
  $i = 0
  foreach ($ln in [System.IO.File]::ReadAllLines($Path)) {
    $i++
    if ($ln.Trim() -eq '') { continue }
    $r = $null
    try { $r = $ln | ConvertFrom-Json -ErrorAction Stop } catch { $out.Malformed += $i; continue }
    if ("$($r.schema)" -eq 'supersession/1') { $out.Supersessions += $r; continue }
    # A compaction backup's marker for a line it could not parse (R4-F1)
    # is a known record, counted, never data and never malformed.
    if ("$($r.schema)" -eq 'rejected/1') { $out.Rejected++; continue }
    # A row is data only with the fields the trend and the archival gate
    # consume (section 32 R1-A2): identity, stamp, night, verdict, legs.
    if (-not (Test-MetricsRowShape $r)) { $out.Malformed += $i; continue }
    $k = Get-MetricsKey $r
    $out.Rows[$k] = $r
    $out.Raw[$k] = $ln.Trim()
  }
  return $out
}

# Long-term storage policy (section 40 item 18): the store keeps every
# night forever (history is never deleted); past this size it compacts, and
# if it is still past the cap after compaction it refuses the append and
# says so, so capacity never silently drops a night.
$script:MetricsMaxBytes = 50MB
$script:MetricsDerivation = 2

function Sync-MetricsStore([string]$Path, $Results, [scriptblock]$Append = $null, [long]$MaxBytes = $script:MetricsMaxBytes) {
  # Keeps one current row per result identity (D00 T02 §25 item 7). The
  # store is append-only JSON lines in ignored scratch beside the runs:
  # a result whose computed row differs from its stored one (a new
  # field such as provenance, R2-F2) appends a revision, and the last
  # row per identity wins; an unchanged result appends nothing.
  # Retention prune never removes a stamp dir whose result has no row
  # (section 32 item 9). Section 32 items 10 and 11: every append runs
  # under the store lock, malformed or truncated lines are skipped and
  # reported ($script:MetricsLastMalformed), an append after a truncated
  # last line starts on a fresh line, and a native row for a night that
  # only a backfill described supersedes it with a recorded supersession
  # line ($script:MetricsSupersessions); superseded backfills leave the
  # returned rows. Returns the current rows.
  return (Invoke-WithMetricsLock {
    $store = Read-MetricsStore $Path
    $script:MetricsLastMalformed = @($store.Malformed)
    $script:MetricsStaleSkipped = @()
    $add = @()
    foreach ($res in @($Results)) {
      if ($null -eq $res) { continue }
      if ("$($res.identity)" -eq '') { continue }
      $json = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $res)) -Depth 6 -Compress
      $id = Get-MetricsKey ($json | ConvertFrom-Json)
      if ($store.Raw.Contains($id) -and ($store.Raw[$id] -eq $json)) { continue }
      # Revision authority (R4-F2): a result older than the stored row
      # (a lower revision) never replaces it.
      if ($store.Rows.Contains($id)) {
        $oldRev = 0; $newRev = 0
        try { $oldRev = [int]$store.Rows[$id].revision } catch { }
        try { $newRev = [int]$res.revision } catch { }
        if ($newRev -lt $oldRev) { $script:MetricsStaleSkipped += @($id); continue }
      }
      $store.Raw[$id] = $json
      $store.Rows[$id] = ($json | ConvertFrom-Json)
      $add += $json
    }
    # Native supersedes backfill for the same night (item 11).
    $byNight = @{}
    foreach ($row in @($store.Rows.Values)) {
      if ("$($row.night)" -eq '') { continue }
      # One host's night (R3-F3): a native row never supersedes another
      # host's backfill.
      $n = "$($row.night)|$(Get-ResultHostKey $row)"
      if (-not $byNight.ContainsKey($n)) { $byNight[$n] = @() }
      $byNight[$n] += $row
    }
    $superseded = @{}
    # A native row supersedes a backfill only when it is evidence for the
    # same run: the same stamp, or a timer-launched native night over a
    # timer-launched backfill. A manual retry later that day is another
    # run, never a replacement (live finding, section 32). Stored records
    # that no longer satisfy the rule are dropped, not trusted.
    # Only an executed native night replaces evidence: a stood-down or
    # cancelled row carries none (R3-A3).
    $replaces = { param($nat, $bf) (@('green', 'red') -contains "$($nat.verdict)") -and (("$($nat.stamp)" -eq "$($bf.stamp)") -or (("$($nat.launch)" -eq 'timer') -and ("$($bf.launch)" -eq 'timer'))) }
    $sups = @($store.Supersessions | Where-Object { $sn = $store.Rows["$($_.native)"]; $sb = $store.Rows["$($_.backfill)"]; ($null -ne $sn) -and ($null -ne $sb) -and (& $replaces $sn $sb) })
    $known = @{}
    foreach ($s0 in $sups) { $known["$($s0.backfill)"] = $true }
    foreach ($n in @($byNight.Keys)) {
      $backs = @($byNight[$n] | Where-Object { [bool]$_.backfill })
      foreach ($b in $backs) {
        $natives = @($byNight[$n] | Where-Object { (-not [bool]$_.backfill) -and (-not [bool]$_.simulated) -and (& $replaces $_ $b) })
        if ($natives.Count -eq 0) { continue }
        $bk = Get-MetricsKey $b
        $superseded[$bk] = $true
        if (-not $known.ContainsKey($bk)) {
          $rec = [pscustomobject]@{ schema = 'supersession/1'; night = "$($b.night)"; native = (Get-MetricsKey $natives[0]); backfill = $bk; recorded = (Get-Date).ToUniversalTime().ToString('o') }
          $add += (ConvertTo-Json $rec -Compress)
          $sups += $rec
          $known[$bk] = $true
        }
      }
    }
    $script:MetricsSupersessions = @($sups)
    $script:MetricsWriteError = ''
    if ($add.Count -gt 0) {
      $lead = if ($store.EndsClean) { '' } else { "`n" }
      $payload = $lead + ($add -join "`n") + "`n"
      $size = if (Test-Path $Path) { (Get-Item $Path).Length } else { 0 }
      # Measured in the bytes written (R3-F1): the payload is UTF-8.
      $payloadBytes = [System.Text.Encoding]::UTF8.GetByteCount($payload)
      if (($size + $payloadBytes) -gt $MaxBytes) { $script:MetricsWriteError = "metrics store over capacity ($size bytes + $payloadBytes > $MaxBytes); run tools/NightlyTrend.ps1 -Compact, then raise the cap if it is still over (history is never deleted)" }
      else {
        # A failed append (a full disk) leaves the store as it was: the
        # write is one call, and a partial line is repaired by the clean-end
        # rule on the next append (section 40 item 10).
        # A write that fails part-way (R1-F1) is cut back to the prior
        # length, so the store's bytes are exactly what they were.
        try { if ($null -ne $Append) { & $Append $Path $payload } else { [System.IO.File]::AppendAllText($Path, $payload, (New-Object System.Text.UTF8Encoding($false))) } }
        catch {
          $script:MetricsWriteError = "metrics append failed: $($_.Exception.Message); the store keeps its prior rows"
          try { if (Test-Path $Path) { $fsx = [System.IO.File]::Open($Path, 'Open', 'ReadWrite'); try { if ($fsx.Length -gt $size) { $fsx.SetLength($size) } } finally { $fsx.Dispose() } } }
          catch { $script:MetricsWriteError += "; truncation back to $size bytes failed ($($_.Exception.Message)), run tools/NightlyTrend.ps1 -Restore" }
        }
      }
    }
    # A native row keeps the backfill's fields it lacks (section 40 item
    # 11): where the native row is null or unknown and the superseded
    # backfill carries a value, the rendered row takes it and names the
    # merge, so partial native evidence never erases stronger evidence.
    $out = @()
    foreach ($row in @($store.Rows.Values)) {
      $rk = Get-MetricsKey $row
      if ($superseded.ContainsKey($rk)) { continue }
      $sup = @($sups | Where-Object { "$($_.native)" -eq $rk }) | Select-Object -First 1
      if ($null -ne $sup) {
        $bf = $store.Rows["$($sup.backfill)"]
        if ($null -ne $bf) {
          $merged = $row | ConvertTo-Json -Depth 8 | ConvertFrom-Json
          $filled = @()
          foreach ($k in @('reserve', 'consumed', 'population', 'populationHash', 'commit', 'harness')) { if ((("$($merged.$k)" -eq '') -or ("$($merged.$k)" -like 'unknown*')) -and ("$($bf.$k)" -ne '') -and ("$($bf.$k)" -notlike 'unknown*')) { $merged | Add-Member -NotePropertyName $k -NotePropertyValue $bf.$k -Force; $filled += $k } }
          foreach ($ek in @($script:EnvFields)) { $nv = "$(try { $merged.env.$ek } catch { '' })"; $bv = "$(try { $bf.env.$ek } catch { '' })"; if ((($nv -eq '') -or ($nv -like 'unknown*')) -and ($bv -ne '') -and ($bv -notlike 'unknown*') -and ($null -ne $merged.env)) { $merged.env | Add-Member -NotePropertyName $ek -NotePropertyValue $bv -Force; $filled += "env.$ek" } }
          if ($filled.Count -gt 0) { $merged | Add-Member -NotePropertyName 'mergedFrom' -NotePropertyValue "$($bf.identity) ($($filled -join ', '))" -Force; $merged | Add-Member -NotePropertyName 'mergedFields' -NotePropertyValue @($filled) -Force; $out += $merged; continue }
        }
      }
      $out += $row
    }
    return $out
  })
}

function Compress-MetricsStore([string]$Path, [scriptblock]$Fault = $null) {
  # The compaction verb (item 10): rewrites the store to its current row
  # per identity plus its supersession records, dropping revisions and
  # malformed lines, after copying the old file to <store>.bak; the
  # rewrite is atomic and read back. Returns a summary line.
  return (Invoke-WithMetricsLock {
    if (-not (Test-Path $Path)) { return 'metrics: nothing to compact' }
    $store = Read-MetricsStore $Path
    $rawLines = @([System.IO.File]::ReadAllLines($Path) | Where-Object { $_.Trim() -ne '' })
    $before = $rawLines.Count
    # The backup carries the disclosure contract too (section 40 item 14):
    # each parsable line is sanitized, each unparsable one is replaced by a
    # marker, so no legacy or rejected value survives in plain text.
    $bakLines = @($rawLines | ForEach-Object { try { $po = $_ | ConvertFrom-Json -ErrorAction Stop; $pc = ConvertTo-Json (Protect-DisclosedObject $po) -Depth 6 -Compress; if ($pc -eq (ConvertTo-Json $po -Depth 6 -Compress)) { $_ } else { $pc } } catch { '{"schema":"rejected/1","note":"malformed line dropped at compaction"}' } })
    Write-AtomicReport $bakLines "$Path.bak"
    # Fault points (R1-F8): fixtures interrupt here, after the backup and
    # after the rewrite's temp file, and the store must stay readable.
    if ($null -ne $Fault) { & $Fault 'after-backup' }
    # A row is rewritten only when sanitizing changes it (a legacy value
    # stored before a rule existed), so clean rows keep their exact bytes
    # and the archive check still matches them.
    foreach ($k in @($store.Rows.Keys)) { $clean = ConvertTo-Json (Protect-DisclosedObject $store.Rows[$k]) -Depth 6 -Compress; if ($clean -ne (ConvertTo-Json $store.Rows[$k] -Depth 6 -Compress)) { $store.Raw[$k] = $clean } }
    $replaces = { param($nat, $bf) (@('green', 'red') -contains "$($nat.verdict)") -and (("$($nat.stamp)" -eq "$($bf.stamp)") -or (("$($nat.launch)" -eq 'timer') -and ("$($bf.launch)" -eq 'timer'))) }
    $valid = @($store.Supersessions | Where-Object { $sn = $store.Rows["$($_.native)"]; $sb = $store.Rows["$($_.backfill)"]; ($null -ne $sn) -and ($null -ne $sb) -and (& $replaces $sn $sb) })
    # Supersession records carry the disclosure contract too (R5-F1).
    $lines = @($store.Rows.Keys | ForEach-Object { $store.Raw[$_] }) + @($valid | ForEach-Object { ConvertTo-Json (Protect-DisclosedObject $_) -Compress })
    $tmp = "$Path.tmp"
    $lines -join "`r`n" | Set-Content -Path $tmp -Encoding UTF8
    if ($null -ne $Fault) { & $Fault 'after-temp' }
    Move-Item -Path $tmp -Destination $Path -Force
    $back = Read-MetricsStore $Path
    if (($back.Rows.Count -ne $store.Rows.Count) -or ($back.Malformed.Count -gt 0)) { throw "metrics compaction read-back mismatch ($($back.Rows.Count) rows vs $($store.Rows.Count))" }
    return "metrics: compacted $before line(s) to $($lines.Count) ($($store.Rows.Count) row(s), $($valid.Count) supersession(s), $($store.Malformed.Count) malformed dropped); backup $Path.bak"
  })
}

function Format-PrunedEvidence($Rows) {
  # Pruned nights explain themselves (section 40 item 13): each night
  # rendered from its metrics row names the result it came from, the
  # derivation that built the row, and that the raw evidence is gone.
  $out = @()
  foreach ($m in @($Rows | Where-Object { [bool]$(try { $_.fromMetrics } catch { $false }) })) {
    $src = "$(try { $m.metricsSource } catch { '' })"
    if ($src -eq '') { $src = 'a metrics row written before sources were recorded' }
    $dv = $(try { $m.derivation } catch { $null })
    $out += "- Pruned night $(Get-ResultNight $m) ($($m.identity)): values from $src, derivation $(if ($null -ne $dv) { $dv } else { '1 (pre-section 40)' }); raw evidence pruned, metrics only"
  }
  return $out
}

function Read-NightlyExclusions([string]$Path) {
  # Operator exclusions (section 40 item 8): rows `| <run identity> |
  # <reason> |` in docs/nightly-exclusions.md. An excluded result is
  # intentional, not unusable: it leaves every series and its night reads
  # excluded, never degraded. Returns identity -> reason.
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  foreach ($ln in (Get-Content $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^\|\s*(\d{4}-\d{2}-\d{2}-\d{6}-pid\d+(?:@[0-9a-f]{8})?)\s*\|\s*([^|]*?)\s*\|')
    if ($m.Success -and ($m.Groups[2].Value -ne '')) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $map
}

function Set-ResultExclusions($Results, $Exclusions) {
  # Marks each excluded result in place and returns how many were marked.
  $n = 0
  foreach ($r in @($Results)) {
    # A row names a bare identity (every host's run with it) or
    # identity@host (that host's run only, section 40 R3-F3).
    $id = "$($r.identity)"
    if ($id -eq '') { continue }
    $hk = Get-MetricsKey ([pscustomobject]@{ identity = $id; hostKey = (Get-ResultHostKey $r) })
    $hit = if ($Exclusions.ContainsKey($hk)) { $hk } elseif ($Exclusions.ContainsKey($id)) { $id } else { '' }
    if ($hit -ne '') { $r | Add-Member -NotePropertyName excluded -NotePropertyValue $Exclusions[$hit] -Force; $n++ }
  }
  return $n
}

function Get-AlertIdentity([string]$Line, [string]$HostKey) {
  # A stable alert identity (section 40 item 15): host plus series, plus
  # the incident for a recurring flake, so one condition keeps one id
  # across nights however its numbers move.
  $m = [regex]::Match($Line, '^-?\s*ALERT ([a-z-]+):\s*(INC-[0-9a-f]{8})?')
  if (-not $m.Success) { return '' }
  $id = "$HostKey|$($m.Groups[1].Value)"
  if ($m.Groups[2].Success) { $id += "|$($m.Groups[2].Value)" }
  return $id
}

function Update-AlertLedger([string[]]$Alerts, [string]$Path, $Evaluation, [string[]]$SupersededIds = @()) {
  # The alert lifecycle (section 40 item 15) in build/nightly/alerts.json:
  # a new id opens; an open id seen again persists; an open id of this
  # host that no longer fires closes as recovered on a later night,
  # corrected when the same night was re-evaluated from a revised result,
  # or superseded when the result it was raised on was superseded.
  # Delivery is tracked per entry (R1-F6): an opening or closing stays
  # pending (notifiedOpen or notifiedClose false) until the morning
  # sender confirms it, so a re-render never drops a transition. Runs
  # under the metrics lock and writes atomically; returns the transitions.
  return (Invoke-WithMetricsLock {
    # An unreadable ledger fails closed (R2-F1): it is never replaced, so
    # pending transitions and delivery history survive for repair.
    $ledger = Read-AlertLedger $Path
    $entries = @(@($ledger.alerts) | Where-Object { $null -ne $_ })
    $night = "$($Evaluation.Night)"; $hk = "$($Evaluation.Host)"; $evalId = "$($Evaluation.Identity)"
    $current = [ordered]@{}
    foreach ($a in @($Alerts)) { $id = Get-AlertIdentity $a $hk; if ($id -ne '') { $current[$id] = $a.TrimStart('-', ' ') } }
    $new = @(); $persist = @(); $closed = @()
    foreach ($id in @($current.Keys)) {
      $e = @($entries | Where-Object { ("$($_.id)" -eq $id) -and ("$($_.state)" -eq 'open') }) | Select-Object -First 1
      if ($null -ne $e) { $e.lastNight = $night; $e.evaluated = $evalId; $e.line = $current[$id]; $persist += $id }
      # Each opening is its own occurrence (R3-F2), so a reopening on the
      # same night never shares a delivery key with the earlier one.
      else { $entries += [pscustomobject]@{ id = $id; occurrence = [guid]::NewGuid().ToString('N').Substring(0, 16); state = 'open'; firstNight = $night; lastNight = $night; evaluated = $evalId; line = $current[$id]; closedNight = ''; notifiedOpen = $false; notifiedClose = $true }; $new += $id }
    }
    foreach ($e in @($entries | Where-Object { ("$($_.state)" -eq 'open') -and ("$($_.id)".StartsWith("$hk|")) -and (-not $current.Contains("$($_.id)")) })) {
      $state = if (@(@($SupersededIds) | ForEach-Object { "$_".Split('@')[0] }) -contains "$($e.evaluated)".Split('#')[0]) { 'superseded' } elseif (("$($e.lastNight)" -eq $night) -and ("$($e.evaluated)" -ne $evalId)) { 'corrected' } elseif ([string]::CompareOrdinal("$($e.lastNight)", $night) -lt 0) { 'recovered' } else { '' }
      if ($state -eq '') { continue }
      $e.state = $state; $e.closedNight = $night
      $e | Add-Member -NotePropertyName notifiedClose -NotePropertyValue $false -Force
      $closed += [pscustomobject]@{ Id = "$($e.id)"; State = $state; Line = "$($e.line)" }
    }
    $out = [pscustomobject]@{ schema = 'alerts/1'; alerts = @($entries) }
    Write-AtomicReport @((ConvertTo-Json $out -Depth 6)) $Path
    return [pscustomobject]@{ New = @($new | ForEach-Object { $current[$_] }); NewIds = @($new); Persisting = @($persist); Closed = @($closed) }
  })
}

function Read-AlertLedger([string]$Path) {
  # The lifecycle ledger, or an empty one when the file does not exist.
  # A file that exists but does not parse as alerts/1 throws, naming the
  # file, so no caller overwrites it or reads it as empty.
  if (-not (Test-Path $Path)) { return [pscustomobject]@{ schema = 'alerts/1'; alerts = @() } }
  $lg = $null
  try { $lg = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { }
  if (($null -eq $lg) -or ("$($lg.schema)" -ne 'alerts/1')) { throw "alert ledger $Path is unreadable; repair it or move it aside (its pending transitions and delivery history are kept, not overwritten)" }
  return $lg
}

function Get-TextHash([string]$Text) {
  # First 8 hex of SHA-256 over a string (the pending-set notify key).
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').Substring(0, 8).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-PendingAlertNotifications([string]$Path) {
  # The transitions not yet delivered (R1-F6): openings with notifiedOpen
  # false and closings with notifiedClose false. Returns Lines to send
  # and Keys to confirm afterwards.
  $lines = @(); $keys = @()
  if (-not (Test-Path $Path)) { return [pscustomobject]@{ Lines = @(); Keys = @(); Persisting = 0 } }
  $lg = Read-AlertLedger $Path
  $persisting = 0
  foreach ($e in @($lg.alerts)) {
    if ($null -eq $e) { continue }
    $occ = if ("$($e.occurrence)" -ne '') { "$($e.occurrence)" } else { "$($e.firstNight)" }
    if ($e.notifiedOpen -eq $false) { $lines += "$($e.line)"; $keys += "open|$($e.id)|$occ" }
    elseif ("$($e.state)" -eq 'open') { $persisting++ }
    if (("$($e.state)" -ne 'open') -and ($e.notifiedClose -eq $false)) { $lines += "closed ($($e.state) on $($e.closedNight)): $($e.id)"; $keys += "close|$($e.id)|$occ" }
  }
  return [pscustomobject]@{ Lines = $lines; Keys = $keys; Persisting = $persisting }
}

function Confirm-AlertNotifications([string]$Path, [string[]]$Keys) {
  # Marks the named transitions delivered, under the metrics lock, after
  # the sender accepted them; a transition opened since stays pending.
  if (@($Keys).Count -eq 0) { return }
  $null = Invoke-WithMetricsLock {
    $lg = Read-AlertLedger $Path
    foreach ($e in @($lg.alerts)) {
      if ($null -eq $e) { continue }
      $occ = if ("$($e.occurrence)" -ne '') { "$($e.occurrence)" } else { "$($e.firstNight)" }
      if (@($Keys) -contains "open|$($e.id)|$occ") { $e.notifiedOpen = $true }
      if (@($Keys) -contains "close|$($e.id)|$occ") { $e | Add-Member -NotePropertyName notifiedClose -NotePropertyValue $true -Force }
    }
    Write-AtomicReport @((ConvertTo-Json $lg -Depth 6)) $Path
  }
}

function Select-AuthoritativeResults($Results, $Rows, [string[]]$Stale = @()) {
  # The render's evidence (section 40 R5-F2): a live result stands for
  # its row unless the store holds a newer revision of it (the sync left
  # it stale), in which case the stored row renders instead; rows with no
  # live result render from metrics. Returns Results and FromMetrics.
  $staleSet = @{}
  foreach ($k in @($Stale)) { if ("$k" -ne '') { $staleSet["$k"] = $true } }
  $keyOf = { param($r) Get-MetricsKey ([pscustomobject]@{ identity = "$($r.identity)"; hostKey = (Get-ResultHostKey $r) }) }
  $kept = @($Results | Where-Object { -not $staleSet.ContainsKey((& $keyOf $_)) })
  $live = @{}
  foreach ($r in $kept) { $live[(& $keyOf $r)] = $true }
  $fromMetrics = @($Rows | Where-Object { -not $live.ContainsKey((Get-MetricsKey $_)) } | ForEach-Object { ConvertFrom-MetricsRow $_ })
  return [pscustomobject]@{ Results = @($kept); FromMetrics = @($fromMetrics) }
}

function Add-MergedEvidence($Results, $Rows) {
  # The live render sees the merge too (R4-F3): each current metrics row
  # that took fields from a superseded backfill copies them onto its live
  # result, so the raw and metrics renders agree before and after the
  # native result is pruned. Returns how many results took fields.
  $n = 0
  $byKey = @{}
  foreach ($r in @($Results)) { $byKey[(Get-MetricsKey ([pscustomobject]@{ identity = "$($r.identity)"; hostKey = (Get-ResultHostKey $r) }))] = $r }
  foreach ($m in @($Rows | Where-Object { ($null -ne $_) -and ($null -ne $(try { $_.mergedFields } catch { $null })) -and (@($_.mergedFields | Where-Object { "$_" -ne '' }).Count -gt 0) })) {
    $r = $byKey[(Get-MetricsKey $m)]
    if ($null -eq $r) { continue }
    foreach ($f in @($m.mergedFields | Where-Object { "$_" -ne '' })) {
      if ($f -like 'env.*') { $ek = $f.Substring(4); if ($null -eq $r.env) { $r | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }; $r.env | Add-Member -NotePropertyName $ek -NotePropertyValue $m.env.$ek -Force }
      else { $r | Add-Member -NotePropertyName $f -NotePropertyValue $m.$f -Force }
    }
    $r | Add-Member -NotePropertyName mergedFrom -NotePropertyValue "$($m.mergedFrom)" -Force
    $n++
  }
  return $n
}

function Remove-ArchivedStamp([string]$NightDir, [string]$Stamp, [string]$StorePath, [scriptblock]$BeforeDelete = $null) {
  # Archival check and deletion under one lock (section 40 item 9): the
  # store is re-read and the stamp re-verified inside the metrics lock
  # immediately before the delete, so a result changed after the first
  # check keeps its stamp. $BeforeDelete lets fixtures interleave a change.
  # Returns Deleted plus Reason.
  return (Invoke-WithMetricsLock {
    $dir = Join-Path $NightDir $Stamp
    if ($null -ne $BeforeDelete) { & $BeforeDelete }
    $chk = Test-StampArchived $NightDir $Stamp (Read-MetricsStore $StorePath)
    if (-not $chk.Ok) { return [pscustomobject]@{ Deleted = $false; Reason = $chk.Reason } }
    Remove-Item -LiteralPath $dir -Recurse -Force
    return [pscustomobject]@{ Deleted = $true; Reason = 'archived and deleted' }
  })
}

function Restore-MetricsStore([string]$Path) {
  # Restore from the compaction backup (section 40 item 10) when the store
  # is unreadable or its lines malformed: the backup is read and validated
  # first, and the restore is atomic. Returns a summary line.
  return (Invoke-WithMetricsLock {
    $bak = "$Path.bak"
    if (-not (Test-Path $bak)) { return 'metrics: no backup to restore from' }
    $b = Read-MetricsStore $bak
    if ($b.Malformed.Count -gt 0) { return "metrics: backup has $($b.Malformed.Count) malformed line(s); not restored" }
    $lines = @($b.Rows.Keys | ForEach-Object { $b.Raw[$_] }) + @($b.Supersessions | ForEach-Object { ConvertTo-Json $_ -Compress })
    Write-AtomicReport $lines $Path
    return "metrics: restored $($b.Rows.Count) row(s) from $bak$(if ($b.Rejected -gt 0) { "; $($b.Rejected) line(s) the compaction had already rejected stay dropped" })"
  })
}

function Protect-DisclosedObject($Value) {
  # The disclosure contract over a whole stored value (section 40 item 14):
  # every string leaf passes Protect-DisclosedText, so a legacy row written
  # before a rule existed is sanitized when compaction rewrites it.
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return (Protect-DisclosedText $Value) }
  if (($Value -is [ValueType])) { return $Value }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Collections.IDictionary])) { return ,@(@($Value) | ForEach-Object { Protect-DisclosedObject $_ }) }
  $o = [ordered]@{}
  foreach ($p in @($Value.PSObject.Properties)) { $o[$p.Name] = Protect-DisclosedObject $p.Value }
  return [pscustomobject]$o
}

function Test-StampArchived([string]$NightDir, [string]$Stamp, $Store) {
  # Archival before prune (item 9): a stamp whose result exists must have
  # its metrics row before the stamp directory may go. A stamp with no
  # result at all (a legacy directory) has nothing to archive.
  $res = @()
  $res += @(Get-ChildItem -LiteralPath $NightDir -Filter "morning-$Stamp.result.json" -File -ErrorAction SilentlyContinue)
  $res += @(Get-ChildItem -LiteralPath (Join-Path $NightDir $Stamp) -Filter 'result.json' -File -ErrorAction SilentlyContinue)
  if ($res.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Reason = 'no result to archive' } }
  foreach ($f in $res) {
    $o = $null
    try { $o = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { return [pscustomobject]@{ Ok = $false; Reason = "result $($f.Name) unreadable" } }
    $id = "$($o.identity)"
    # Section 32 R1-A1: an unidentifiable result cannot be archived, and a
    # stored row must equal the row the current result computes (a result
    # rewritten after its archival is not archived).
    if ($id -eq '') { return [pscustomobject]@{ Ok = $false; Reason = "result $($f.Name) has no identity to archive under" } }
    $key = Get-MetricsKey ([pscustomobject]@{ identity = $id; hostKey = $(try { "$($o.hostKey)" } catch { '' }) })
    if (-not $Store.Rows.Contains($key)) { return [pscustomobject]@{ Ok = $false; Reason = "result $id has no metrics row" } }
    $want = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $o)) -Depth 6 -Compress
    if ("$($Store.Raw[$key])" -ne $want) { return [pscustomobject]@{ Ok = $false; Reason = "result $id changed since its metrics row was written" } }
  }
  return [pscustomobject]@{ Ok = $true; Reason = 'archived' }
}

function ConvertFrom-MetricsRow($Row) {
  # A metrics-only night (its raw result pruned) rendered through the
  # same trend code, flagged so its row reads (metrics).
  $legs = [pscustomobject]@{}
  foreach ($prop in @($Row.legs.PSObject.Properties)) { $legs | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
  return [pscustomobject]@{ version = 1; revision = $(try { $Row.revision } catch { $null }); identity = "$($Row.identity)"; stamp = "$($Row.stamp)"; day = "$($Row.day)"; night = "$($Row.night)"; verdict = "$($Row.verdict)"; launch = "$($Row.launch)"; simulated = [bool]$Row.simulated; legs = $legs; soak = $(if ($null -ne $Row.soak) { $Row.soak } else { [pscustomobject]@{ verdict = '' } }); incidents = @($Row.incidents); reserve = $Row.reserve; consumed = $Row.consumed; env = $(try { $Row.env } catch { [pscustomobject]@{ os = 'unknown'; dpi = 'unknown' } }); fromMetrics = $true; metricsBackfill = [bool]$Row.backfill; provenance = $(try { $Row.provenance } catch { $null }); timings = $(try { $Row.timings } catch { $null }); population = $(try { "$($Row.population)" } catch { '' }); commit = $(try { "$($Row.commit)" } catch { '' }); recovered = $(if ("$($Row.recovered)" -ne '') { "$($Row.recovered)" } else { 'none' }); omissionOk = $(if ($null -ne $Row.omissionOk) { [bool]$Row.omissionOk } else { $null }); buildError = "$($Row.buildError)"; scheduler = $(if ($null -ne $Row.scheduler) { $Row.scheduler } else { [pscustomobject]@{ voted = $false; faults = @() } }); quarantine = $(if ($null -ne $Row.quarantine) { $Row.quarantine } else { [pscustomobject]@{ overdue = @(); dueSoon = @() } }); harness = "$($Row.harness)"; populationHash = "$($Row.populationHash)"; incidentEvidence = $(try { $Row.incidentEvidence } catch { $null }); hostKey = "$($Row.hostKey)"; populationState = "$($Row.populationState)"; executedUnique = $(try { $Row.executedUnique } catch { $null }); excluded = "$($Row.excluded)"; metricsSource = "$($Row.source)"; derivation = $(try { $Row.derivation } catch { $null }); mergedFrom = "$($Row.mergedFrom)" }
}

# Trend window semantics (D00 T02 section 32 items 5 and 6): an alert
# needs this many measured baseline nights, and a percentile over fewer
# than $script:TrendTailMin samples is the maximum and says so.
$script:TrendMinSamples = 5
$script:TrendTailMin = 20

function Get-RunCohort($Result) {
  # The comparison cohort (section 32 item 4): environment (OS, DPI,
  # dotnet), harness version (the build commit's recorded tooling
  # version when present), and the test population. A change between the
  # evaluated night and its baseline makes a comparison cross-cohort.
  $c = [ordered]@{}
  foreach ($k in @('os', 'dpi', 'dotnet')) { $c[$k] = $(try { "$($Result.env.$k)" } catch { '' }) }
  # The host is a cohort dimension too (section 40 item 1).
  $c['host'] = Get-ResultHostKey $Result
  # The harness (the governed scripts' own hash) and the population's
  # identity (the accepted fingerprint's hash, so equal counts over
  # replaced tests still differ). Results written before the hash read
  # unknown rather than falling back to counts (section 40 item 5).
  $c['harness'] = $(try { "$($Result.harness)" } catch { '' })
  $ph = $(try { "$($Result.populationHash)" } catch { '' })
  # A missing population hash never establishes equivalence (section 40
  # item 5): counts alone are not identity, so the dimension reads unknown.
  $c['population'] = $ph
  return $c
}

function Get-CohortChanges($Latest, $Baseline) {
  # The cohort dimensions that differ between the latest night and any
  # baseline night, as 'name old -> new' strings. An unknown (empty,
  # 'unknown', or a legacy host) on either side compares as a change
  # (section 40 item 5): an unknown never establishes equivalence.
  $changes = @()
  $lc = Get-RunCohort $Latest
  $isUnknown = { param($x) ($x -eq '') -or ($x -like 'unknown*') -or ($x -eq 'legacy') }
  foreach ($b in @($Baseline)) {
    $bc = Get-RunCohort $b
    foreach ($k in @($lc.Keys)) {
      $a = "$($bc[$k])"; $z = "$($lc[$k])"
      $aa = if (& $isUnknown $a) { 'unknown' } else { $a }
      $zz = if (& $isUnknown $z) { 'unknown' } else { $z }
      $differs = ($aa -eq 'unknown') -or ($zz -eq 'unknown') -or ($aa -ne $zz)
      $txt = if (($aa -eq 'unknown') -and ($zz -eq 'unknown')) { "$k unknown on both sides" } else { "$k $aa -> $zz" }
      if ($differs -and ($changes -notcontains $txt)) { $changes += $txt }
    }
  }
  return $changes
}

function Select-SameCohort($Latest, $Rows) {
  # The baseline rows sharing the evaluated night's cohort (section 40
  # item 4): a new cohort starts its own baseline instead of alerting
  # against the old one.
  return @(@($Rows) | Where-Object { @(Get-CohortChanges $Latest @($_)).Count -eq 0 })
}

# The ancestry probe (section 40 item 16): returns $true when $A is an
# ancestor of $B, $false when not, $null when the history cannot say.
# Fixtures replace it; the default asks git.
$script:AncestryProbe = {
  param($A, $B)
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & git merge-base --is-ancestor $A $B 2>$null | Out-Null; $code = $LASTEXITCODE } catch { $code = 128 } finally { $ErrorActionPreference = $eap }
  if ($code -eq 0) { return $true }
  if ($code -eq 1) { return $false }
  return $null
}

function Get-CommitRangeShape([string[]]$Commits) {
  # The shape of the revisions between the baseline and the latest night
  # (section 40 item 16): linear when each night's commit descends from
  # the one before, non-linear naming the first rollback or divergence,
  # and unavailable when history cannot answer (a pruned or foreign
  # revision). Consecutive repeats collapse first.
  $seq = @()
  foreach ($c in @($Commits)) { if (($seq.Count -eq 0) -or ($seq[-1] -ne $c)) { $seq += $c } }
  if ($seq.Count -lt 2) { return 'linear' }
  for ($i = 1; $i -lt $seq.Count; $i++) {
    $a = $seq[$i - 1]; $b = $seq[$i]
    $fwd = & $script:AncestryProbe $a $b
    if ($null -eq $fwd) { return "ancestry unavailable ($($a.Substring(0, [math]::Min(7, $a.Length)))..$($b.Substring(0, [math]::Min(7, $b.Length))))" }
    if ($fwd) { continue }
    $back = & $script:AncestryProbe $b $a
    $short = $b.Substring(0, [math]::Min(7, $b.Length))
    if ($back -eq $true) { return "non-linear (rollback to $short)" }
    return "non-linear (divergent at $short)"
  }
  return 'linear'
}

function Format-AlertContext($Latest, $Baseline, [string]$Name) {
  # Attribution and drill-through for one alert (section 32 item 15):
  # the contributing runs, the commit range, environment changes, and
  # whether raw evidence or only metrics remain, on an indented line so
  # the alert line itself stays stable.
  $runs = @(@($Baseline) + @($Latest) | ForEach-Object { "$($_.identity)" } | Where-Object { $_ -ne '' })
  $commits = @(@($Baseline) + @($Latest) | ForEach-Object { "$($_.commit)" } | Where-Object { ($_ -ne '') -and ($_ -ne 'unknown') })
  $range = if ($commits.Count -gt 0) { "$($commits[0].Substring(0, [math]::Min(7, $commits[0].Length)))..$($commits[-1].Substring(0, [math]::Min(7, $commits[-1].Length)))" } else { 'unknown' }
  $changes = @(Get-CohortChanges $Latest $Baseline)
  $env = if ($changes.Count -gt 0) { "CROSS-COHORT ($($changes -join '; '))" } else { 'same cohort' }
  $metricsOnly = @(@($Baseline) + @($Latest) | Where-Object { [bool]$(try { $_.fromMetrics } catch { $false }) }).Count
  $evidence = if ($metricsOnly -gt 0) { "raw results for $(@(@($Baseline) + @($Latest)).Count - $metricsOnly), metrics only for $metricsOnly" } else { 'raw results for every run' }
  # Exact revisions and their shape (section 40 item 16), labeled as
  # correlation: the range says what changed near the alert, not why.
  $exact = if ($commits.Count -gt 0) { "$($commits[0])..$($commits[-1]) ($(Get-CommitRangeShape $commits))" } else { 'unknown' }
  return "  - $Name context: runs $($runs -join ', '); commits $range; revisions $exact; env $env; evidence $evidence; correlation, not cause"
}

function Protect-DisclosedText([string]$Text) {
  # One disclosure contract for every persisted and displayed trend,
  # provenance, incident, toast, and digest channel (section 32 item
  # 14): a secret-shaped value becomes the names of the patterns it hit,
  # and a user-profile path (C:\Users\<name>\...) or UNC path collapses
  # to [path]; repo-relative names pass unchanged.
  $t = "$Text"
  $hits = @(Test-CaptureSecrets $t)
  foreach ($p in $script:SecretPatterns) { $t = [regex]::Replace($t, $p[1], "[redacted: $($p[0])]") }
  # A path runs through its spaces to the next field boundary (a ';',
  # '|', ',', ')', a ' KEY=' token, or the end), so a folder name with a
  # space never leaks its tail (section 32 R3-A2).
  $t = [regex]::Replace($t, '(?i)\b[A-Za-z]:\\Users\\.*?(?=( [A-Z][A-Z0-9_]*=)|[;|,)]|$)', '[path]')
  $t = [regex]::Replace($t, '\\\\(?!\.\\)[^\\;|,)]+\\.*?(?=( [A-Z][A-Z0-9_]*=)|[;|,)]|$)', '[path]')
  return $t
}

function Get-TrendAlerts($Rows, [int]$Baseline = 7) {
  # Regression alerts from the series (D00 T02 §25 item 6), over
  # canonical native nights only (series rule): RunA duration past 125%
  # of the median of the previous nights and at least 60 s over; the
  # executed pass rate 2 points below the baseline median; and an
  # incident id on the latest night that also hit one of the two
  # nights before it. Each alert quotes its baseline and delta.
  # Window semantics (section 32 item 5): the evaluated night is never in
  # its own baseline, missing nights are counted against the window, and
  # fewer than $script:TrendMinSamples measured baseline nights reads
  # insufficient data instead of alerting.
  $alerts = @()
  $r = @(@($Rows) | Where-Object { $null -ne $_ })
  if ($r.Count -lt 2) { return $alerts }
  # One host's series (section 40 item 1): another known host's nights
  # never join this host's window; legacy rows (no host recorded) stay in
  # and read as a cohort change, so the migration names itself.
  $hk = Get-ResultHostKey $r[-1]
  $r = @($r | Where-Object { $h2 = Get-ResultHostKey $_; ($h2 -eq $hk) -or ($h2 -eq 'legacy') })
  if ($r.Count -lt 2) { return $alerts }
  $latest = $r[-1]
  # The evaluated result's identity carries its revision (R1-F3), so a
  # corrected result on the same night reads as a re-evaluation.
  $script:LastTrendEvaluation = [pscustomobject]@{ Night = (Get-ResultNight $latest); Host = $hk; Identity = "$($latest.identity)#r$(try { "$($latest.revision)" } catch { '' })" }
  # The baseline is a calendar window (section 32 R1-I3): the $Baseline
  # nights before the evaluated one, so a missing night consumes its slot
  # and an old measurement past the window never stands in for it.
  $latestNight = [datetime]::MinValue
  $windowed = [datetime]::TryParseExact((Get-ResultNight $latest), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$latestNight)
  if ($windowed) {
    $from = $latestNight.AddDays(-$Baseline).ToString('yyyy-MM-dd')
    $to = $latestNight.AddDays(-1).ToString('yyyy-MM-dd')
    $prev = @($r[0..($r.Count - 2)] | Where-Object { $nk = Get-ResultNight $_; ($nk -ge $from) -and ($nk -le $to) })
    $slotsFilled = @($prev | ForEach-Object { Get-ResultNight $_ } | Sort-Object -Unique).Count
    $missingInWindow = [math]::Max(0, $Baseline - $slotsFilled)
  } else {
    $prev = @($r[0..($r.Count - 2)] | Select-Object -Last $Baseline)
    $missingInWindow = 0
  }
  # Cross-cohort windows rebaseline (section 40 item 4): only nights in
  # the evaluated night's cohort form its baseline, and a cohort change
  # names itself instead of alerting; too few same-cohort nights read as a
  # cold start (insufficient data).
  $allPrev = $prev
  $prev = @(Select-SameCohort $latest $prev)
  if (@($allPrev).Count -gt @($prev).Count) {
    $chg = @(Get-CohortChanges $latest @($allPrev | Where-Object { @(Get-CohortChanges $latest @($_)).Count -gt 0 }))
    $alerts += "- Rebaseline: cohort changed on $(Get-ResultNight $latest) ($($chg -join '; ')); $(@($allPrev).Count - @($prev).Count) earlier night(s) leave the baseline"
  }
  $la = $null
  try { $la = [double]$latest.legs.'run-a'.testSeconds } catch { }
  $pa = @($prev | ForEach-Object { try { if ($null -ne $_.legs.'run-a'.testSeconds) { [double]$_.legs.'run-a'.testSeconds } } catch { } })
  # Each series is gated on its own samples (R1-I2): a duration alert
  # needs $script:TrendMinSamples measured durations, a pass-rate alert
  # as many measured rates; recurrence needs none.
  $gap = if ($missingInWindow -gt 0) { ", $missingInWindow of $Baseline window night(s) missing" } else { '' }
  $insufficient = { param($series, $n) "- Insufficient data: $series ($n measured baseline night(s) of $($script:TrendMinSamples) needed$gap; evaluated night $(Get-ResultNight $latest) excluded from its own baseline); no $series alert is actionable yet" }
  if ($pa.Count -lt $script:TrendMinSamples) { $alerts += (& $insufficient 'runa-duration' $pa.Count) }
  elseif (($null -ne $la) -and ($pa.Count -gt 0)) {
    $med = Get-Percentile $pa 50
    if (($la -gt 1.25 * $med) -and (($la - $med) -ge 60)) {
      # A zero baseline has no percentage (R3-F1): the delta rides alone.
      $pct = if ($med -gt 0) { "+$([int][math]::Round(100 * ($la - $med) / $med))%" } else { "+$([int]($la - $med))s over a zero baseline" }
      $alerts += "- ALERT runa-duration: $([int]$la)s on $(Get-ResultNight $latest) vs baseline $([int]$med)s ($pct, median of $($pa.Count) night(s))"
      $alerts += Format-AlertContext $latest $prev 'runa-duration'
    }
  }
  # An unproven night (a killed or budget-cut leg) contributes no rate,
  # matching the table's denominator rule (R1-F3).
  # Change-point (sustained shift): with at least 10 measured nights,
  # the median of the last 3 against the median of the 7 before them,
  # past 120% and at least 60 s over, so a step that one noisy night
  # would not trip still surfaces (D00 T02 §25 item 6, plan review PR8).
  # Calendar windows (section 32 R3-I2): the last 3 nights (evaluated
  # included) against the 7 nights before them; each window needs its own
  # measured nights (3 recent, 5 prior), so old history never stands in.
  $shiftOk = $false
  if ($windowed) {
    $recentFrom = $latestNight.AddDays(-2).ToString('yyyy-MM-dd')
    $priorFrom = $latestNight.AddDays(-9).ToString('yyyy-MM-dd'); $priorTo = $latestNight.AddDays(-3).ToString('yyyy-MM-dd')
    $recentRows = @(Select-SameCohort $latest @($r | Where-Object { $nk = Get-ResultNight $_; ($nk -ge $recentFrom) } | Where-Object { try { $null -ne $_.legs.'run-a'.testSeconds } catch { $false } }))
    $priorRows = @(Select-SameCohort $latest @($r | Where-Object { $nk = Get-ResultNight $_; ($nk -ge $priorFrom) -and ($nk -le $priorTo) } | Where-Object { try { $null -ne $_.legs.'run-a'.testSeconds } catch { $false } }))
    $shiftOk = ($recentRows.Count -ge 3) -and ($priorRows.Count -ge $script:TrendMinSamples)
  }
  if ($shiftOk) {
    $recentMed = Get-Percentile @($recentRows | ForEach-Object { [double]$_.legs.'run-a'.testSeconds }) 50
    $priorMed = Get-Percentile @($priorRows | ForEach-Object { [double]$_.legs.'run-a'.testSeconds }) 50
    if (($recentMed -gt 1.2 * $priorMed) -and (($recentMed - $priorMed) -ge 60)) {
      $shift = if ($priorMed -gt 0) { "+$([int][math]::Round(100 * ($recentMed - $priorMed) / $priorMed))%" } else { "+$([int]($recentMed - $priorMed))s over a zero baseline" }
      $alerts += "- ALERT runa-shift: last 3 nights median $([int]$recentMed)s vs the prior 7 nights median $([int]$priorMed)s ($shift, sustained)"
      $alerts += Format-AlertContext $latest (@($priorRows) + @($recentRows | Where-Object { $_ -ne $latest })) 'runa-shift'
    }
  }
  $rate = { param($x) $p = 0; $f = 0; $unproven = $false; foreach ($leg in @('run-a', 'run-b', 'interactive')) { try { $o = $x.legs.$leg; if (($null -ne $o) -and (($null -eq $o.ran) -or [bool]$o.ran)) { $p += [int]$o.passed; $f += [int]$o.failed; if ([bool]$o.killed -or [bool]$o.cut) { $unproven = $true } } } catch { } }; if ((-not $unproven) -and (($p + $f) -gt 0)) { 100.0 * $p / ($p + $f) } else { $null } }
  $lr = & $rate $latest
  $pr = @($prev | ForEach-Object { & $rate $_ } | Where-Object { $null -ne $_ })
  if ($pr.Count -lt $script:TrendMinSamples) { $alerts += (& $insufficient 'pass-rate' $pr.Count) }
  elseif (($null -ne $lr) -and ($pr.Count -gt 0)) {
    $med = Get-Percentile $pr 50
    if ($lr -lt ($med - 2)) {
      $alerts += "- ALERT pass-rate: $([math]::Round($lr, 1))% on $(Get-ResultNight $latest) vs baseline $([math]::Round($med, 1))% ($([math]::Round($lr - $med, 1)) points, median of $($pr.Count) night(s))"
      $alerts += Format-AlertContext $latest $prev 'pass-rate'
    }
  }
  $aliasMap = Get-IncidentAliases $Rows
  $ids = { param($x) @(@($x.incidents) | ForEach-Object { $m = [regex]::Match("$_", '(INC-[0-9a-f]{8})'); if ($m.Success) { if ($aliasMap.ContainsKey($m.Groups[1].Value)) { $aliasMap[$m.Groups[1].Value] } else { $m.Groups[1].Value } } }) }
  $li = @(& $ids $latest)
  # The two calendar nights before the evaluated one (section 32 R2-I1):
  # an incident weeks earlier is not a recurrence.
  if ($windowed) {
    $rFrom = $latestNight.AddDays(-2).ToString('yyyy-MM-dd')
    $rTo = $latestNight.AddDays(-1).ToString('yyyy-MM-dd')
    $recent = @($r[0..($r.Count - 2)] | Where-Object { $nk = Get-ResultNight $_; ($nk -ge $rFrom) -and ($nk -le $rTo) })
  } else { $recent = @($r[0..($r.Count - 2)] | Select-Object -Last 2) }
  foreach ($id in ($li | Sort-Object -Unique)) {
    $hits = @($recent | Where-Object { (& $ids $_) -contains $id })
    if ($hits.Count -gt 0) {
      $alerts += "- ALERT recurring-flake: $id on $(Get-ResultNight $latest) and $(($hits | ForEach-Object { Get-ResultNight $_ }) -join ', ')"
      $alerts += Format-AlertContext $latest $hits 'recurring-flake'
    }
  }
  return $alerts
}

function Get-ResultHostKey($Result) {
  # The host a result ran on (section 40 item 1): a short hash of the
  # machine name the nightly records (hostKey), never the name itself;
  # results written before the field read 'legacy'.
  $h = ''
  try { $h = "$($Result.hostKey)" } catch { }
  if ($h -eq '') { return 'legacy' }
  return $h
}

function Get-NightSlotKey($Result) {
  # The composite night identity (section 40 item 1): night plus host, so
  # two hosts' runs on one night never merge. The schedule rides the
  # canonical choice, not the key: one host serves one schedule per night.
  return "$(Get-ResultNight $Result)|$(Get-ResultHostKey $Result)"
}

function Get-HostKey([string]$MachineName = $env:COMPUTERNAME) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$MachineName".ToLowerInvariant()))) -replace '-', '').Substring(0, 8).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Select-CanonicalRuns($Results) {
  # One canonical run per night (item 2): simulations, stood-down
  # losers, and results without a day never count; among the rest the
  # scheduler-launched run wins (latest stamp), then an on-demand task
  # run, then the latest manual run. Every other result of the day is
  # a retry, listed with its reason, so trends count nights, not
  # attempts. Returns a hashtable day -> Canonical (identity) plus
  # Others (identity -> reason).
  # Keyed by night slot (night plus host, section 40 item 1).
  $byDay = @{}
  foreach ($r in @($Results)) {
    if ($null -eq $r) { continue }
    if ((Get-ResultNight $r) -eq '') { continue }
    $day = Get-NightSlotKey $r
    $id = "$($r.identity)"
    if ($id -eq '') { $id = "$($r.stamp)" }
    if (-not $byDay.ContainsKey($day)) { $byDay[$day] = [pscustomobject]@{ Canonical = ''; Others = [ordered]@{}; Pool = @() } }
    $slot = $byDay[$day]
    $sim = $false
    try { $sim = [bool]$r.simulated } catch { }
    if ($sim) { $slot.Others[$id] = 'simulation'; continue }
    $ex = ''
    try { $ex = "$($r.excluded)" } catch { }
    if ($ex -ne '') { $slot.Others[$id] = "excluded ($ex)"; continue }
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
      # Two timer launches serving one night are a repeated trigger (a DST
      # fall-back replays 02:30, or a duplicate fire): the latest is
      # canonical and the other reads as the repeat (section 40 item 2).
      foreach ($p in $slot.Pool) { if ($p.Id -ne $pick.Id) { $slot.Others[$p.Id] = $(if (($p.Launch -eq 'timer') -and ($pick.Launch -eq 'timer')) { "repeated timer trigger (DST fall-back or duplicate fire; canonical $($pick.Id))" } else { "retry ($(if ($p.Launch -eq '') { 'unknown' } else { $p.Launch }) launch; canonical $($pick.Id))" }) } }
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
  # old id rather than guessing), and only when no other v1 id maps
  # to that v2 id (a merge is named, never joined: section 38 R1-F3).
  # Returns old id -> new id.
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
  $targets = @{}
  foreach ($old in $aliases.Keys) { $n = $aliases[$old]; if (-not $targets.ContainsKey($n)) { $targets[$n] = 0 }; $targets[$n]++ }
  foreach ($old in @($aliases.Keys)) { if ($targets[$aliases[$old]] -gt 1) { $aliases.Remove($old) } }
  return $aliases
}

function Move-AliasedIncidents([hashtable]$Ledger, [hashtable]$Aliases, [hashtable]$Links = @{}) {
  # Alias migration moves incident state (D00 T02 section 45 item 5):
  # when a v1 id joins its v2 id (Get-IncidentAliases), the v1 entry's
  # finding link, owner, due date, occurrences, and recovery streak move
  # onto the v2 id, and the v1 entry leaves the ledger, so the join never
  # duplicates or closes work. With both ids present: occurrences union
  # by stamp, first and last seen widen, an open side keeps the result
  # open, a specific owner beats the triage default, the earlier due
  # date and the existing link win, and the streak is the stronger of
  # the two only when both sides are open (a failure on either reset
  # it already). The link map gains the v2 id for a moved link. Returns
  # Incidents, Links, and Lines.
  $map = @{}
  foreach ($k in $Ledger.Keys) { $map[$k] = $Ledger[$k] }
  $lk = @{}
  foreach ($k in $Links.Keys) { $lk[$k] = $Links[$k] }
  $lines = @()
  foreach ($old in @($Aliases.Keys | Sort-Object)) {
    $new = $Aliases[$old]
    if (-not $map.ContainsKey($old)) { continue }
    $o = $map[$old]
    foreach ($field in @('due', 'finding', 'passStreak', 'lastPassStamp', 'closedAt', 'closedBy')) { if (@($o.PSObject.Properties.Name) -notcontains $field) { $o | Add-Member -NotePropertyName $field -NotePropertyValue $(if ($field -eq 'passStreak') { 0 } else { '' }) } }
    if ($lk.ContainsKey($old) -and (-not $lk.ContainsKey($new))) { $lk[$new] = $lk[$old] }
    if (-not $map.ContainsKey($new)) {
      $o.id = $new
      if (("$($o.finding)" -eq '') -and $lk.ContainsKey($new)) { $o.finding = $lk[$new] }
      $map[$new] = $o
      $map.Remove($old)
      $lines += "- $old -> ${new}: alias joined; state moved (state $($o.state), owner $($o.owner), $(@($o.occurrences).Count) occurrences, streak $($o.passStreak)$(if ("$($o.finding)" -ne '') { ", link $($o.finding)" }))"
      continue
    }
    $n = $map[$new]
    # Each side's own last failure, before the merge widens lastSeen (R1-F3).
    $lastBySide = @{ o = "$($o.lastSeen)"; n = "$($n.lastSeen)" }
    foreach ($field in @('due', 'finding', 'passStreak', 'lastPassStamp', 'closedAt', 'closedBy')) { if (@($n.PSObject.Properties.Name) -notcontains $field) { $n | Add-Member -NotePropertyName $field -NotePropertyValue $(if ($field -eq 'passStreak') { 0 } else { '' }) } }
    $byStamp = @{}
    foreach ($x in @($n.occurrences) + @($o.occurrences)) { if (($null -ne $x) -and (-not $byStamp.ContainsKey("$($x.stamp)"))) { $byStamp["$($x.stamp)"] = $x } }
    $n.occurrences = @($byStamp.Keys | Sort-Object | ForEach-Object { $byStamp[$_] })
    if ("$($o.firstSeen)" -lt "$($n.firstSeen)") { $n.firstSeen = $o.firstSeen }
    if ("$($o.lastSeen)" -gt "$($n.lastSeen)") { $n.lastSeen = $o.lastSeen }
    if ((("$($n.owner)" -eq '') -or ($n.owner -eq $script:TriageOwner)) -and ("$($o.owner)" -ne '') -and ($o.owner -ne $script:TriageOwner)) { $n.owner = $o.owner; $n.due = '' }
    elseif (("$($o.due)" -ne '') -and (("$($n.due)" -eq '') -or ("$($o.due)" -lt "$($n.due)")) -and ($n.owner -eq $script:TriageOwner)) { $n.due = $o.due }
    if ("$($n.finding)" -eq '') { $n.finding = $(if ("$($o.finding)" -ne '') { $o.finding } elseif ($lk.ContainsKey($new)) { $lk[$new] } else { '' }) }
    if (($o.state -eq 'open') -or ($n.state -eq 'open')) {
      # A streak survives the merge only from a side whose own last
      # failure is the newest of the two (R1-F3): a side that failed
      # before the other's latest failure may count passes from before
      # that failure, so its streak is void. Equal last failures keep
      # the stronger streak.
      $lf = if ($lastBySide.o -gt $lastBySide.n) { $lastBySide.o } else { $lastBySide.n }
      $cand = @()
      if (("$($o.state)" -eq 'open') -and ($lastBySide.o -eq $lf)) { $cand += $o }
      if (("$($n.state)" -eq 'open') -and ($lastBySide.n -eq $lf)) { $cand += $n }
      $best = $null
      foreach ($c in $cand) { if (($null -eq $best) -or ([int]$c.passStreak -gt [int]$best.passStreak)) { $best = $c } }
      # The streak moves with its population provenance (R2-F2).
      if ($null -ne $best) {
        $n.passStreak = [int]$best.passStreak; $n.lastPassStamp = $best.lastPassStamp
        $pop = if ($null -ne $best.PSObject.Properties['streakPopulation']) { "$($best.streakPopulation)" } else { '' }
        if ($null -eq $n.PSObject.Properties['streakPopulation']) { $n | Add-Member -NotePropertyName streakPopulation -NotePropertyValue $pop } else { $n.streakPopulation = $pop }
      } else { $n.passStreak = 0 }
      $n.state = 'open'; $n.closedAt = ''; $n.closedBy = ''
    }
    $map.Remove($old)
    $lines += "- $old -> ${new}: alias joined; state merged (state $($n.state), owner $($n.owner), $(@($n.occurrences).Count) occurrences, streak $($n.passStreak)$(if ("$($n.finding)" -ne '') { ", link $($n.finding)" }))"
  }
  return [pscustomobject]@{ Incidents = $map; Links = $lk; Lines = $lines }
}

function Get-IncidentAliasReport($Rows, [string]$V2Since = $script:IncidentContractV2Since) {
  # The alias migration cases (section 38 item 6), over the same triple
  # match as Get-IncidentAliases: mapped (one v1 id, one v2 id, joined);
  # merged (several v1 ids share one v2 id: not joined, R1-F3, named with
  # its v1 ids so triage can decide); split (one v1 id matches several v2 ids: not
  # joined, ambiguity keeps the old id); unmapped (no v2 id shares the
  # triple: not joined, the old id stays on its own). Returns Aliases
  # (what the trend joins) plus Merged, Split, and Unmapped for the
  # report lines.
  $aliases = Get-IncidentAliases $Rows $V2Since
  $parse = { param($ln) $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)` x\d+ \(([^)]*)\): ?(.*)$'); if (-not $m.Success) { return $null }; $where = @($m.Groups[3].Value -split ',\s*')[0]; [pscustomobject]@{ Id = $m.Groups[1].Value; Triple = "$($m.Groups[2].Value)|$(Get-IncidentPhase $where)|$(Get-FailureClass $m.Groups[4].Value)" } }
  $v1 = @{}
  $v2 = @{}
  foreach ($r in @($Rows)) {
    foreach ($ln in @($r.incidents)) {
      $p = & $parse $ln
      if ($null -eq $p) { continue }
      if ("$($r.stamp)" -lt $V2Since) { $v1[$p.Id] = $p.Triple }
      else { if (-not $v2.ContainsKey($p.Triple)) { $v2[$p.Triple] = @() }; if ($v2[$p.Triple] -notcontains $p.Id) { $v2[$p.Triple] += $p.Id } }
    }
  }
  $split = @{}
  $unmapped = @()
  foreach ($old in ($v1.Keys | Sort-Object)) {
    $t = $v1[$old]
    if (-not $v2.ContainsKey($t)) { $unmapped += $old }
    elseif (@($v2[$t]).Count -gt 1) { $split[$old] = @($v2[$t] | Sort-Object) }
  }
  $merged = @{}
  foreach ($old in ($v1.Keys | Sort-Object)) {
    $t = $v1[$old]
    if ($v2.ContainsKey($t) -and (@($v2[$t]).Count -eq 1)) {
      $new = $v2[$t][0]
      if (-not $merged.ContainsKey($new)) { $merged[$new] = @() }
      $merged[$new] += $old
    }
  }
  foreach ($k in @($merged.Keys)) { if (@($merged[$k]).Count -lt 2) { $merged.Remove($k) } }
  return [pscustomobject]@{ Aliases = $aliases; Merged = $merged; Split = $split; Unmapped = $unmapped }
}

function Get-NightlySchedule([string]$TaskXml) {
  # The governed task's calendar (section 32 R1-C1): its first night and
  # its day interval from the CalendarTrigger, so the trend knows which
  # nights were due. $null when the definition cannot be read.
  if (-not (Test-Path $TaskXml)) { return $null }
  try {
    [xml]$x = Get-Content -LiteralPath $TaskXml -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace('t', $x.DocumentElement.NamespaceURI)
    $start = $x.SelectSingleNode('//t:CalendarTrigger/t:StartBoundary', $ns).InnerText
    $int = $x.SelectSingleNode('//t:CalendarTrigger/t:ScheduleByDay/t:DaysInterval', $ns)
    $d = [DateTimeOffset]::Parse($start, [System.Globalization.CultureInfo]::InvariantCulture)
    return [pscustomobject]@{ First = $d.Date.ToString('yyyy-MM-dd'); Trigger = $d.ToString('HH:mm'); IntervalDays = $(if ($null -ne $int) { [int]$int.InnerText } else { 1 }) }
  } catch { return $null }
}

function Read-ScheduleHistory([string]$Path) {
  # The schedule's history (section 40 item 3): rows `| From | Trigger |
  # Interval days |` in docs/nightly-schedule-history.md, one per trigger
  # edit, so an edit applies from its date and never rewrites past nights.
  # $null when the file is absent.
  if (-not (Test-Path $Path)) { return $null }
  $entries = @()
  foreach ($ln in (Get-Content $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*(\d{2}:\d{2})\s*\|\s*(\d+)\s*\|')
    if ($m.Success) { $entries += [pscustomobject]@{ First = $m.Groups[1].Value; Trigger = $m.Groups[2].Value; IntervalDays = [int]$m.Groups[3].Value } }
  }
  if ($entries.Count -eq 0) { return $null }
  return [pscustomobject]@{ First = @($entries | Sort-Object First)[0].First; Entries = @($entries | Sort-Object First) }
}

function Get-ScheduleEntry($Schedule, [string]$Night) {
  # The schedule entry in force on $Night: the latest history entry on or
  # before it, else the single-entry schedule itself.
  if ($null -eq $Schedule) { return $null }
  if (@($Schedule.PSObject.Properties.Name) -contains 'Entries') { return (@($Schedule.Entries | Where-Object { [string]::CompareOrdinal($_.First, $Night) -le 0 }) | Select-Object -Last 1) }
  return $Schedule
}

function Test-NightScheduled($Schedule, [string]$Night) {
  # True when the task was due on $Night (on or after its first night,
  # on its interval); with no schedule every night is due. With a
  # history, the entry in force that night decides (section 40 item 3).
  if ($null -eq $Schedule) { return $true }
  if (@($Schedule.PSObject.Properties.Name) -contains 'Entries') {
    $e = Get-ScheduleEntry $Schedule $Night
    if ($null -eq $e) { return $false }
    $e0 = [datetime]::ParseExact($e.First, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $dn = [datetime]::ParseExact($Night, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    return ((([int]($dn - $e0).TotalDays) % [math]::Max(1, $e.IntervalDays)) -eq 0)
  }
  if ([string]::CompareOrdinal($Night, $Schedule.First) -lt 0) { return $false }
  $d0 = [datetime]::ParseExact($Schedule.First, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
  $d = [datetime]::ParseExact($Night, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
  return ((([int]($d - $d0).TotalDays) % [math]::Max(1, $Schedule.IntervalDays)) -eq 0)
}

function Read-NightlyPauses([string]$Path) {
  # Recorded pauses (D00 T02 section 32 item 7): rows `| YYYY-MM-DD |
  # reason |` in docs/nightly-pauses.md name nights the nightly was
  # deliberately not run, so the trend reads them paused, not missing.
  $pauses = @{}
  if (-not (Test-Path $Path)) { return $pauses }
  foreach ($ln in (Get-Content $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*([^|]+?)\s*\|')
    if ($m.Success) { $pauses[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $pauses
}

function Format-TailLine([double[]]$Window) {
  # Honest tails (section 32 item 6): below $script:TrendTailMin samples
  # a nearest-rank p95 is the maximum, and the line says so.
  $n = @($Window).Count
  $max = ($Window | Measure-Object -Maximum).Maximum
  $p95 = Get-Percentile $Window 95
  $p95Text = if ($n -lt $script:TrendTailMin) { "p95 $p95 (= max: n=$n < $($script:TrendTailMin))" } else { "p95 $p95" }
  return "n=$n, p50 $(Get-Percentile $Window 50), p90 $(Get-Percentile $Window 90), $p95Text, max $max"
}

function Format-TrendTable($Results, [hashtable]$Quarantine, [datetime]$Today = (Get-Date), [hashtable]$Pauses = @{}, $Degraded = @(), $Supersessions = @(), $Schedule = $null) {
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
  $aliasReport = Get-IncidentAliasReport $rows
  # Canonical runs (D00 T02 §24 item 2): every result keeps its row, but
  # retries, simulations, and stood-down losers are marked and stay out
  # of the p50, the budget ranks, and flake recurrence, so a retry
  # burst cannot count as extra nights or bias the series.
  $canon = Select-CanonicalRuns $rows
  $isCanon = { param($r) $cid = "$($r.identity)"; if ($cid -eq '') { $cid = "$($r.stamp)" }; $nk = Get-NightSlotKey $r; ($canon.ContainsKey($nk)) -and ($canon[$nk].Canonical -eq $cid) }
  # Series inclusion (D00 T02 §25 item 2): durations, percentiles, and
  # alerts read canonical native nights only (no simulation, stand-down,
  # cancellation, retry, or backfill); pass rate and recurrence read
  # canonical nights, backfills included (their counts are mechanical
  # derivations and say so).
  $isNative = { param($r) (& $isCanon $r) -and (-not (Test-IsBackfill $r)) -and (-not [bool]$(try { $r.metricsBackfill } catch { $false })) }
  $rowEntries = @()
  $nativeNights = @()
  # Degraded data (item 8): a corrupted or skipped result marks its night,
  # so broken evidence never makes a night look healthy.
  $degradedNights = @(@($Degraded) | ForEach-Object { "$($_.Night)" } | Where-Object { $_ -ne '' })
  $lines = @('# Nightly trend', '', '- Pass rate: passed / (passed + failed) over executed tests; skips (quarantine, capability, fenced) are counted apart and never in the denominator; a night with a killed or budget-cut leg reads unproven; stand-downs and cancellations are marks.', '- Series: durations, percentiles, and alerts read canonical native nights (no simulation, stand-down, cancellation, retry, or backfill); pass rate and recurrence read canonical nights with backfills marked; every row renders, retries and extras marked.', '- Series matrix (D00 T02 section 32): [rate] pass rate: canonical nights, backfills marked; [coverage] executed of discovered: every night with a leg run; [native] RunA/RunB seconds, percentiles, alerts: canonical native nights; [recurrence] flake recurrence: canonical nights, aliases joined; [quarantine] quarantine age: each night''s own snapshot plus today''s ledger; [gates] gate verdicts: every night; [budget] budget telemetry and Reserve: every night that is not a mark; [soak] Soak and SoakFail: every night that ran the soak; [env] environment: every night; [excluded] smoke runs: never publish a result.', '- Columns: Pass [rate]; Coverage [coverage]; RunA s, RunB s [native]; Soak, SoakFail [soak]; Gates [gates]; Reserve [budget]; Quar [quarantine]; Env [env].', '', '| Night | Verdict | Class | Pass | RunA s | RunB s | Soak | Gates | Reserve | Quar | SoakFail | Env | Coverage |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
  $allA = @()
  $incNights = @{}
  foreach ($r in $rows) {
    $day = Get-ResultNight $r; $v = "$($r.verdict)"
    if (($v -eq 'stood-down') -or ($v -eq 'cancelled')) {
      $rowEntries += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Line = "| $day | $v (mark) | - | - | - | - | - | - | - | - | - | - | - |" }
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
      if ($fraw -is [array]) { $sfn = @($fraw | Where-Object { $_ -is [string] }); if ($sfn.Count -gt 0) { $soak += ' ' + (Protect-DisclosedText ($sfn -join ',')) } }
      elseif (([int]$fraw) -gt 0) { $soak += " failed=$fraw" }
      $skn = @($r.soak.killed | Where-Object { $null -ne $_ }).Count; $scn = @($r.soak.cut | Where-Object { $null -ne $_ }).Count
      if ($skn -gt 0) { $soak += " killed=$skn" }
      if ($scn -gt 0) { $soak += " cut=$scn" }
    } catch { }
    $gates = '-'
    try {
      $ga = '-'; $gb = '-'
      try { if ($null -ne $r.legs.'run-a') { $la = $r.legs.'run-a'; $ga = if ((($null -ne $la.ran) -and (-not [bool]$la.ran))) { 'skip' } elseif ($null -eq $la.gate) { 'null' } else { Protect-DisclosedText "$($la.gate)" } } } catch { }
      try { if ($null -ne $r.legs.'run-b') { $lb = $r.legs.'run-b'; $gb = if ((($null -ne $lb.ran) -and (-not [bool]$lb.ran))) { 'skip' } elseif ($null -eq $lb.gate) { 'null' } else { Protect-DisclosedText "$($lb.gate)" } } } catch { }
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
    # Intentional exclusion (section 40 item 8): an operator-excluded
    # result renders marked and joins no series; it never reads degraded.
    $exReason = "$(try { $r.excluded } catch { '' })"
    if ($exReason -ne '') { $rowEntries += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Line = "| $day (excluded) | $v | - | excluded: $(Protect-DisclosedText $exReason) | - | - | - | - | - | - | - | - | - |" }; continue }
    if (Test-IsBackfill $r) { $nightCell += ' (backfill)' }
    if ([bool]$(try { $r.fromMetrics } catch { $false })) { $nightCell += ' (metrics)' }
    # Execution coverage (item 2): executed of discovered (executed plus
    # skipped), so a high rate over a shrunken population shows.
    # Discovered is the recorded population's cases for the legs that ran
    # when the result carries it (a killed or cut leg never reports the
    # tests it did not reach), else executed plus skipped (R3-C2).
    $disc = $exec + $s
    $popm = [regex]::Matches("$(try { $r.population } catch { '' })", '(run-a|run-b|interactive)=\d+/(\d+)')
    if ($popm.Count -gt 0) {
      $pd = 0
      foreach ($pm in $popm) { $lg = $pm.Groups[1].Value; try { $lo = $r.legs.$lg; if (($null -ne $lo) -and (($null -eq $lo.ran) -or [bool]$lo.ran)) { $pd += [int]$pm.Groups[2].Value } } catch { } }
      if ($pd -gt 0) { $disc = $pd }
    }
    # Coverage counts unique tests (section 40 item 7): executions past
    # the discovered population are duplicates (retries, shards) and never
    # raise it; a failed discovery reads unknown.
    # The numerator is the count of distinct executed test names the run
    # recorded (executedUnique, from its trx files, R1-F2); a result
    # without it falls back to executions capped at the population and
    # says the identities were not recorded.
    $popState = "$(try { $r.populationState } catch { '' })"
    $eu = $null
    try { if ($null -ne $r.executedUnique) { $eu = [int]$r.executedUnique } } catch { }
    $idNote = ''
    if ($null -ne $eu) { $uniq = [math]::Min($eu, $disc); $dup = [math]::Max(0, $exec - $eu) }
    else { $uniq = [math]::Min($exec, $disc); $dup = [math]::Max(0, $exec - $disc); if ($exec -gt $disc) { $idNote = '; identities not recorded (count capped)' } }
    $cov = if ($popState -eq 'unknown') { 'unknown (discovery failed)' } elseif ($disc -gt 0) { "$uniq/$disc ($([math]::Round((100 * $uniq) / $disc, 1))%)$(if ($dup -gt 0) { "; $dup duplicate execution(s) not counted" })$idNote" } else { '-' }
    if ($degradedNights -contains $day) { $nightCell += ' (degraded)' }
    $rowEntries += [pscustomobject]@{ Night = $day; Stamp = "$($r.stamp)"; Line = "| $nightCell | $v | $c | $pass | $ra | $rb | $soak | $gates | $res | $od/$ds$qage | $sf | $envShort | $cov |" }
  }
  # Missing nights (D00 T02 §25 item 4): every night between the first
  # and last canonical night with no result at all renders as missing.
  $canonNights = @($canon.Keys | Where-Object { $canon[$_].Canonical -ne '' } | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique)
  $allNights = @($rowEntries | ForEach-Object { $_.Night })
  # Enrollment (section 32 R2-C2): the first governed result's night, of
  # any verdict, else the schedule's first night, so a history with no
  # successful publication still lists its missed nights.
  $anyNights = @($rows | ForEach-Object { Get-ResultNight $_ } | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object)
  $enroll = if ($anyNights.Count -gt 0) { $anyNights[0] } elseif ($null -ne $Schedule) { $Schedule.First } else { '' }
  if (($null -ne $Schedule) -and ($enroll -ne '') -and ([string]::CompareOrdinal($enroll, $Schedule.First) -lt 0)) { $enroll = $Schedule.First }
  if ($enroll -ne '') {
    # Schedule-aware calendar (R1-C1): from enrollment through the latest
    # night already due (today's once the quiet window has passed), only
    # nights the task's trigger scheduled; the tail after the last
    # result counts.
    $d0 = [datetime]::ParseExact($enroll, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $lastSeen = if ($anyNights.Count -gt 0) { [datetime]::ParseExact($anyNights[-1], 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } else { $d0 }
    $d1 = $lastSeen
    # Completion grace (section 40 item 3): a night is due-through only
    # once its trigger plus the run's 4 h limit plus 30 min has passed; a
    # night still inside that window reads pending, never missing.
    # Each night's deadline is computed from its own date and the trigger
    # in force that night (R2-F2), so a trigger near midnight keeps the
    # previous night pending past midnight instead of reading missing.
    $dueThrough = $Today.Date.AddDays(-2)
    $pendingNight = ''
    foreach ($cand in @($Today.Date.AddDays(-1), $Today.Date)) {
      $trig = [TimeSpan]::FromHours(2.5)
      try { $te = Get-ScheduleEntry $Schedule $cand.ToString('yyyy-MM-dd'); if (($null -ne $te) -and (@($te.PSObject.Properties.Name) -contains 'Trigger')) { $trig = [TimeSpan]::Parse("$($te.Trigger)") } } catch { }
      $startAt = $cand + $trig
      $deadline = $startAt + [TimeSpan]::FromHours(4.5)
      if ($Today -ge $deadline) { $dueThrough = $cand }
      elseif ($Today -ge $startAt) { $pendingNight = $cand.ToString('yyyy-MM-dd') }
    }
    if ($dueThrough -gt $d1) { $d1 = $dueThrough.AddDays(1) }
    if (($pendingNight -ne '') -and ($allNights -notcontains $pendingNight) -and (Test-NightScheduled $Schedule $pendingNight)) { $rowEntries += [pscustomobject]@{ Night = $pendingNight; Stamp = ''; Line = "| $pendingNight | pending | - | run window open | - | - | - | - | - | - | - | - | - |" } }
    for ($d = $d0; $d -lt $d1; $d = $d.AddDays(1)) {
      $ds = $d.ToString('yyyy-MM-dd')
      if (-not (Test-NightScheduled $Schedule $ds)) { continue }
      if ($allNights -notcontains $ds) {
        # Schedule-aware calendar (item 7): a recorded pause reads paused,
        # a degraded night reads degraded, only the rest read missing.
        if ($Pauses.ContainsKey($ds)) { $rowEntries += [pscustomobject]@{ Night = $ds; Stamp = ''; Line = "| $ds | paused | - | $($Pauses[$ds]) | - | - | - | - | - | - | - | - | - |" } }
        elseif ($degradedNights -contains $ds) { $rowEntries += [pscustomobject]@{ Night = $ds; Stamp = ''; Line = "| $ds | degraded | - | result unreadable | - | - | - | - | - | - | - | - | - |" } }
        else { $rowEntries += [pscustomobject]@{ Night = $ds; Stamp = ''; Line = "| $ds | missing | - | no result | - | - | - | - | - | - | - | - | - |" } }
      }
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
  # The migration cases the join leaves out, named (section 38 item 6).
  if ($null -ne $aliasReport) {
    if ($aliasReport.Merged.Count -gt 0) { $lines += ("- Identity merges (not joined; several v1 ids match one v2 id): " + ((@($aliasReport.Merged.Keys | Sort-Object) | ForEach-Object { "$($aliasReport.Merged[$_] -join ', ') -> $_" }) -join '; ')) }
    if ($aliasReport.Split.Count -gt 0) { $lines += ("- Identity splits (not joined; one v1 id matches several v2 ids): " + ((@($aliasReport.Split.Keys | Sort-Object) | ForEach-Object { "$_ -> $($aliasReport.Split[$_] -join ' | ')" }) -join '; ')) }
    if (@($aliasReport.Unmapped).Count -gt 0) { $lines += ("- Identity unmapped (not joined; no v2 id shares the failure): " + ($aliasReport.Unmapped -join ', ')) }
  }
  # The trend reads the lifecycle through its consumer contract (section
  # 38 item 7, R1-F4): the newest result carrying the block, by contract
  # version, or the reason it cannot be read.
  $lastLife = @($rows | Where-Object { @($_.PSObject.Properties.Name) -contains 'incidentLifecycle' }) | Select-Object -Last 1
  if ($null -ne $lastLife) {
    $blk = Read-LifecycleBlock $lastLife
    if ($blk.State -eq 'ok') { $lines += "- Incident lifecycle ($(Get-ResultNight $lastLife), contract v$($blk.Version)): $(@($blk.Rows | Where-Object { $_.state -eq 'open' }).Count) open, $(@($blk.Rows | Where-Object { $_.state -eq 'closed' }).Count) closed" }
    else { $lines += "- Incident lifecycle ($(Get-ResultNight $lastLife)): unreadable ($($blk.Error))" }
  }
  if ($rec.Count -gt 0) { $lines += ("- Flake recurrence: " + (($rec | ForEach-Object { "$_ ($($incNights[$_] -join ', '))" }) -join '; ') + ' [recurrence]') }
  else { $lines += '- Flake recurrence: none across rendered nights [recurrence]' }
  $canonCount = @($canon.Keys | Where-Object { $canon[$_].Canonical -ne '' }).Count
  $lines += "- Canonical nights: $canonCount of $($rows.Count) results (retries, simulations, and stood-down losers stay out of the p50, the budget ranks, and recurrence)"
  # Launch evidence behind the latest canonical night's incidents
  # (D00 T02 §24 item 14), one click from the trend.
  $latest = @($rows | Where-Object { & $isCanon $_ }) | Select-Object -Last 1
  if ($null -ne $latest) {
    $ev = $null
    try { $ev = $latest.incidentEvidence } catch { }
    if ($null -ne $ev) {
      foreach ($prop in @($ev.PSObject.Properties)) { $lines += (Protect-DisclosedText "- Incident evidence ($($latest.day)): $($prop.Name) $(@($prop.Value) -join '; ')") }
    }
  }
  # Tail percentiles over the last 14 canonical native nights (D00 T02
  # §25 item 5): the sample count plus p50, p90, and p95, so a tail
  # regression and its confidence read at a glance.
  $win = @($nativeNights | Sort-Object Night, Stamp | Select-Object -Last 14 | Where-Object { $null -ne $_.Seconds } | ForEach-Object { $_.Seconds })
  if ($win.Count -gt 0) {
    $lines += "- RunA test-seconds (canonical native nights, last 14): $(Format-TailLine ([double[]]$win)) [native]"
  }
  else { $lines += '- RunA test-seconds: no measurements [native]' }
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
  $lines += "- Quarantine now: $qo overdue$oldest, $qs due within 3 days [quarantine]"
  # Backfill provenance (D00 T02 §25 item 9): every backfilled row quotes
  # where each field came from and how far to trust it.
  foreach ($r in $rows) {
    $pv = $null
    try { $pv = $r.provenance } catch { }
    if ($null -eq $pv) { continue }
    $bits = @($pv.PSObject.Properties | ForEach-Object { $mth = "$($_.Value.method)"; $loc = "$($_.Value.locator)"; "$($_.Name) $($_.Value.confidence)$(if ($mth -ne '') { " by $mth" }) from $($_.Value.source)$(if ($loc -ne '') { " at $loc" })" })
    $lines += (Protect-DisclosedText "- Backfill provenance ($(Get-ResultNight $r) $($r.stamp)): $($bits -join '; ')")
  }
  foreach ($dg in @($Degraded)) { $lines += (Protect-DisclosedText "- Degraded data: night $($dg.Night) ($($dg.Reason))") }
  # Exclusions state their effect (section 40 item 8).
  foreach ($x in @($rows | Where-Object { "$(try { $_.excluded } catch { '' })" -ne '' })) { $lines += (Protect-DisclosedText "- Excluded: $($x.identity) night $(Get-ResultNight $x) ($($x.excluded)): out of [native], [rate], [recurrence], [budget], and [env]; its night reads excluded, not degraded, and its baseline slot counts as missing") }
  foreach ($ss in @($Supersessions)) { $lines += "- Supersession: night $($ss.Night) native $($ss.Native) supersedes backfill $($ss.Backfill)" }
  $lines += ''
  $lines += '## Alerts'
  $lines += ''
  $lines += '(series [native] and [rate] for regressions, [recurrence] for flakes)'
  # Every host's series is evaluated (R1-F4): one group per known host
  # (legacy rows join each, reading as the migration's cohort change),
  # or one group when no host is recorded.
  $nativeRows = @($rows | Where-Object { & $isNative $_ })
  $knownHosts = @($nativeRows | ForEach-Object { Get-ResultHostKey $_ } | Where-Object { $_ -ne 'legacy' } | Sort-Object -Unique)
  $script:TrendAlertGroups = @()
  $alerts = @()
  $groups = if ($knownHosts.Count -le 1) { ,@('') } else { $knownHosts }
  foreach ($gh in @($groups)) {
    $grp = if ($gh -eq '') { $nativeRows } else { @($nativeRows | Where-Object { $h2 = Get-ResultHostKey $_; ($h2 -eq $gh) -or ($h2 -eq 'legacy') }) }
    $script:LastTrendEvaluation = $null
    $ga = @(Get-TrendAlerts $grp)
    if ($null -ne $script:LastTrendEvaluation) { $script:TrendAlertGroups += [pscustomobject]@{ Evaluation = $script:LastTrendEvaluation; Alerts = @($ga | Where-Object { $_ -like '- ALERT *' }) } }
    if ($knownHosts.Count -gt 1) { $alerts += "- Host ${gh}:" }
    $alerts += $ga
  }
  if ($alerts.Count -eq 0) { $lines += '(none)' } else { $lines += $alerts }
  $lines += ''
  $lines += '## Budget'
  $lines += ''
  $lines += '(series [budget])'
  $ranked = @($allA | Sort-Object)
  foreach ($r in $rows) {
    if ((("$($r.verdict)") -eq 'stood-down') -or (("$($r.verdict)") -eq 'cancelled')) { continue }
    if ("$(try { $r.excluded } catch { '' })" -ne '') { continue }
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
      if ($tp.Count -gt 0) { $ph = Protect-DisclosedText ($tp -join ' ') }
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
  $lines += '(series [env])'
  foreach ($r in $rows) {
    if ((("$($r.verdict)") -eq 'stood-down') -or (("$($r.verdict)") -eq 'cancelled')) { continue }
    if ("$(try { $r.excluded } catch { '' })" -ne '') { continue }
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
# D00 T02 §31 carries the lifecycle past the signature: a result's own
# revision orders its copies, proof runs queue apart, deadlines are
# timestamps that §24's SLAs can shorten, each disposition names its
# evidence, a batch covers each incident, the latest commit governs a
# run (withdrawn releases it), unreadable results demand, and a signed
# RED opens a corrective action that closes only on evidence.
$script:AckV1Cutover = '2026-09-21'
$script:AckDueDays = 3
$script:AckDispositions = @('fixed', 'filed', 'quarantined', 'environment', 'expected', 'duplicate', 'withdrawn')
# A cover line (section 39 item 13): `INC-<id> <disposition> <finding>`,
# optionally ending `evidence <e>` so each covered incident carries the
# evidence its own disposition needs in a mixed batch.
$script:AckCoverRe = '^(INC-[0-9a-f]{8})\s+(\S+)\s+(.+?)(?:\s+evidence\s+(\S+))?\s*$'
# Proof provenance (section 39 item 10): the producers allowed to mark a
# result as test activity, and the append-only ledger recording each
# published result's queue at publication.
$script:ProofSources = @('switches', 'simulator', 'backfill')
$script:ResultClassLedger = 'result-classes.jsonl'
# Results stamped at or after this cutover must carry a classification
# entry; one without is operational (section 39 R2-F4).
$script:ResultClassCutover = '2026-09-25-160000'

function Get-FileSha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLower()
  } finally { $sha.Dispose() }
}

function Test-ProofResult($Result) {
  # Deliberate test activity (section 31 item 7): a result marked proof,
  # simulated, or backfilled, or one whose every leg and the soak were
  # skipped (a skip-all proof run from before the flag existed).
  foreach ($flag in @('proof', 'simulated', 'backfill', 'metricsBackfill')) {
    try { if ([bool]$Result.$flag) { return $true } } catch { }
  }
  # Inference is for results written before the flag existed only: a
  # result that says `proof: false` is operational whatever its legs
  # did (an infrastructure failure before execution still escalates).
  if (@($Result.PSObject.Properties.Name) -contains 'proof') { return $false }
  try {
    $legsRan = @(@('run-a', 'run-b', 'interactive') | Where-Object { [bool]$Result.legs.$_.ran }).Count
    $soakRan = [bool]$Result.soak.ran
    if (($null -ne $Result.legs) -and ($legsRan -eq 0) -and (-not $soakRan) -and ("$($Result.buildError)" -eq '')) { return $true }
  } catch { }
  return $false
}

function Test-AckResultShape($Result) {
  # What an acknowledgement binds to must itself be sound (section 31
  # R2-F1): schema version 1, a known verdict whose exit agrees with it,
  # an identity or stamp on a RED, and a positive whole revision when
  # one is recorded. Returns '' when sound, else the reason. The full
  # nightly schema (legs, env, timings) is Test-ResultFile's job; results
  # written before those fields existed still acknowledge.
  if ($null -eq $Result) { return 'unreadable' }
  if ("$($Result.version)" -ne '1') { return "schema version '$($Result.version)' (want 1)" }
  $v = "$($Result.verdict)"
  if (@('green', 'red', 'stood-down', 'cancelled') -notcontains $v) { return "unknown verdict '$v'" }
  $ex = "$($Result.exit)"
  if ($ex -notmatch '^-?\d+$') { return "exit '$ex' is not a number" }
  if ((@('green', 'stood-down') -contains $v) -and ([int]$ex -ne 0)) { return "verdict $v contradicts exit $ex" }
  if ((@('red', 'cancelled') -contains $v) -and ([int]$ex -eq 0)) { return "verdict $v contradicts exit $ex" }
  if ((@('red', 'cancelled') -contains $v) -and ("$($Result.identity)" -eq '') -and ("$($Result.stamp)" -eq '')) { return 'a RED with no identity or stamp' }
  if ((@($Result.PSObject.Properties.Name) -contains 'revision') -and ("$($Result.revision)" -notmatch '^[1-9]\d*$')) { return "revision '$($Result.revision)' is not a positive whole number" }
  return ''
}

function Add-ResultClassification([string]$NightDir, $Result, [string]$Sha, [string]$ForceQueue = '') {
  # Records a published result's queue at publication (section 39 item
  # 10): one JSON line per identity, appended, first write wins. A result
  # edited to proof later cannot move its run out of the operational
  # queue, because the gate reads the queue recorded here. Returns '' or
  # the failure.
  $id = "$($Result.identity)"
  if ($id -eq '') { $id = "$($Result.stamp)" }
  if ($id -eq '') { return 'result has no identity or stamp' }
  $queue = if ($ForceQueue -ne '') { $ForceQueue } elseif (Test-ProofResult $Result) { 'proof' } else { 'operational' }
  # Each line chains to the one before (section 46 item 10): `prev` is the
  # previous line's `h` (the first chained line anchors every legacy line
  # before it), and `h` covers this line's fields plus `prev`, so editing
  # any recorded line breaks the chain from there on.
  $path = Join-Path $NightDir $script:ResultClassLedger
  $prev = Get-ClassChainTail $path
  $body = [ordered]@{ identity = $id; queue = $queue; source = "$($Result.proofSource)"; sha = $Sha; at = (Get-Date).ToUniversalTime().ToString('o'); prev = $prev }
  $h = Get-ClassChainHash (ConvertTo-Json -Compress ([pscustomobject]$body))
  $body['h'] = $h
  $line = ConvertTo-Json -Compress ([pscustomobject]$body)
  try { [System.IO.File]::AppendAllText($path, $line + "`n", (New-Object System.Text.UTF8Encoding($false))); return '' } catch { return "result classification write failed: $($_.Exception.Message)" }
}

function Get-ClassChainHash([string]$Text) {
  return (Get-BytesSha256 ([System.Text.Encoding]::UTF8.GetBytes($Text)))
}

function Get-ClassLegacyAnchor([string[]]$Lines) {
  # The anchor over legacy (unchained) lines: their text, one per line.
  $t = (@($Lines | ForEach-Object { "$_".TrimEnd("`r") }) -join "`n")
  return (Get-ClassChainHash "legacy`n$t")
}

function Get-ClassChainTail([string]$Path) {
  # The `prev` the next appended line must carry.
  if (-not (Test-Path -LiteralPath $Path)) { return (Get-ClassLegacyAnchor @()) }
  $all = @([System.IO.File]::ReadAllLines($Path) | Where-Object { "$_".Trim() -ne '' })
  $legacy = @()
  $last = ''
  foreach ($ln in $all) {
    $o = $null
    try { $o = $ln | ConvertFrom-Json } catch { $o = $null }
    if (($null -ne $o) -and ($null -ne $o.PSObject.Properties['h'])) { $last = "$($o.h)" } elseif ($last -eq '') { $legacy += $ln }
  }
  if ($last -ne '') { return $last }
  return (Get-ClassLegacyAnchor $legacy)
}

function Register-UnclassifiedResults([string]$NightDir, [string[]]$ResultFiles) {
  # First sight (section 39 R2-F4): every result without a classification
  # entry is recorded as it reads now, so a later relabel cannot move it.
  # Returns the count recorded.
  $known = Read-ResultClassifications $NightDir
  $n = 0
  foreach ($f in @($ResultFiles)) {
    $r = $null
    try { $r = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $id = "$($r.identity)"; if ($id -eq '') { $id = "$($r.stamp)" }
    if (($id -eq '') -or $known.ContainsKey($id)) { continue }
    # Past the cutover the nightly classifies at publication, so a result
    # first seen unclassified was not published by it: operational,
    # whatever its fields claim (R3-F3). Before the cutover the fields as
    # first seen are all there is.
    $force = if ("$($r.stamp)" -ge $script:ResultClassCutover) { 'operational' } else { '' }
    if ((Add-ResultClassification $NightDir $r (Get-FileSha256 $f) $force) -eq '') { $known[$id] = $true; $n++ }
  }
  return $n
}

$script:ResultClassTampered = ''

function Read-ResultClassifications([string]$NightDir) {
  # identity -> the first recorded Queue and Source (section 39 item 10).
  # The chain is verified (section 46 item 10): from the first line that
  # breaks it (an edited field, a wrong `prev`, or an unchained line after
  # the chain began), nothing is trusted, so those runs fall back to the
  # operational default, and $script:ResultClassTampered names the line.
  $script:ResultClassTampered = ''
  $map = @{}
  $p = Join-Path $NightDir $script:ResultClassLedger
  if (-not (Test-Path $p)) { return $map }
  $legacy = @()
  # Legacy (pre-chain) entries wait here (section 46 R2-F2): they join the
  # map only once the first chained line verifies their anchor, or when
  # no chained line exists at all (nothing can vouch for them then, as
  # before the chain), so an edited legacy entry never survives a broken
  # anchor.
  $legacyEntries = @()
  $last = ''
  $n = 0
  foreach ($ln in [System.IO.File]::ReadAllLines($p)) {
    $n++
    if ("$ln".Trim() -eq '') { continue }
    $o = $null
    try { $o = $ln | ConvertFrom-Json } catch { $o = $null }
    $chained = ($null -ne $o) -and ($null -ne $o.PSObject.Properties['h'])
    if (-not $chained) {
      if ($last -ne '') { $script:ResultClassTampered = "line $n is unchained after the chain began"; break }
      $legacy += $ln
      if ($null -ne $o) { $legacyEntries += $o }
      continue
    } else {
      $want = if ($last -ne '') { $last } else { Get-ClassLegacyAnchor $legacy }
      $body = [ordered]@{ identity = "$($o.identity)"; queue = "$($o.queue)"; source = "$($o.source)"; sha = "$($o.sha)"; at = "$($o.at)"; prev = "$($o.prev)" }
      $h = Get-ClassChainHash (ConvertTo-Json -Compress ([pscustomobject]$body))
      if ("$($o.prev)" -ne $want) { $script:ResultClassTampered = "line $n does not chain to the line before it (an earlier line was edited, removed, or inserted)"; break }
      if ("$($o.h)" -ne $h) { $script:ResultClassTampered = "line $n was edited after it was recorded"; break }
      if ($last -eq '') { foreach ($le in $legacyEntries) { if (("$($le.identity)" -ne '') -and (-not $map.ContainsKey("$($le.identity)"))) { $map["$($le.identity)"] = [pscustomobject]@{ Queue = "$($le.queue)"; Source = "$($le.source)" } } } }
      $last = "$($o.h)"
    }
    if (("$($o.identity)" -ne '') -and (-not $map.ContainsKey("$($o.identity)"))) { $map["$($o.identity)"] = [pscustomobject]@{ Queue = "$($o.queue)"; Source = "$($o.source)" } }
  }
  if (($last -eq '') -and ("$($script:ResultClassTampered)" -eq '')) { foreach ($le in $legacyEntries) { if (("$($le.identity)" -ne '') -and (-not $map.ContainsKey("$($le.identity)"))) { $map["$($le.identity)"] = [pscustomobject]@{ Queue = "$($le.queue)"; Source = "$($le.source)" } } } }
  return $map
}

function Get-AckDemands($ResultFiles, $Classes = $null) {
  # One demand per RED or cancelled run identity (D00 T02 §23 items 1
  # and 4): retained copies, reruns, and re-emitted results of one run
  # dedupe onto its identity, carrying every checksum seen for it. The
  # checksum covers the result only (notification state lives in
  # §24's own files and never enters it, so a notification version bump
  # leaves every ack valid; section 31 item 4), and the demand records
  # the result's schema version beside it.
  # Section 31 item 5: a copy's `revision` field orders the copies of a
  # run; the highest revision is current, and two copies at the same
  # revision with different checksums are a CONFLICT no ack can resolve.
  # Copies without the field (results written before it) keep the
  # write-time order they always had.
  # Section 31 item 11: an unreadable result raises its own demand
  # (`unreadable:<file>`), never silently dropping out of the gate.
  # Returns identity -> Id, Day, Queue (operational or proof), Shas,
  # Paths, Current, Incidents, AllIncidents, Conflict, Unreadable,
  # SchemaVersion, Result, Revision.
  $demands = @{}
  # Copies that parse but fail the shape check yet name a run (section 46
  # item 6): they never supersede that run's valid copy, and the conflict
  # is attached to its demand once every copy is read.
  $invalidNamed = @()
  foreach ($p in @($ResultFiles)) {
    if (-not (Test-Path $p -PathType Leaf)) { continue }
    $r = $null
    $readErr = ''
    try { $r = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { $readErr = $_.Exception.Message }
    $why = if ($readErr -ne '') { 'unreadable' } else { Test-AckResultShape $r }
    if ($why -ne '') {
      $name = Split-Path -Leaf $p
      $id = "unreadable:$name"
      $dm = [regex]::Match($name, '(\d{4}-\d{2}-\d{2})')
      $day = if ($dm.Success) { $dm.Groups[1].Value } else { '' }
      $sha = Get-FileSha256 $p
      if (-not $demands.ContainsKey($id)) { $demands[$id] = [pscustomobject]@{ Id = $id; Day = $day; Queue = 'operational'; Shas = @($sha); Incidents = @(); Paths = @($p); Current = $sha; CurrentTime = [datetime]::MinValue; AllIncidents = @(); Conflict = @(); Unreadable = $true; Invalid = $why; SchemaVersion = ''; Result = $null; Revision = 0; Regressions = @(); Results = @(); InvalidCopies = @() } }
      if (($readErr -eq '') -and ($null -ne $r)) {
        $named = "$($r.identity)"; if ($named -eq '') { $named = "$($r.stamp)" }
        if ($named -ne '') { $invalidNamed += [pscustomobject]@{ Id = $named; Name = $name; Why = $why; Revision = "$($r.revision)" } }
      }
      continue
    }
    if (@('red', 'cancelled') -notcontains "$($r.verdict)") { continue }
    $id = "$($r.identity)"
    if ($id -eq '') { $id = "$($r.stamp)" }
    if ($id -eq '') { continue }
    $queue = if (Test-ProofResult $r) { 'proof' } else { 'operational' }
    # The queue recorded at publication governs (section 39 item 10): a
    # result relabeled proof after it was published stays operational.
    # With a classification ledger (the nightly and the helper always pass
    # one, empty or not), a result past the cutover with no record is
    # operational (R3-F3); a pure call with no ledger ($null) reads fields.
    if ($null -ne $Classes) {
      if ($Classes.ContainsKey($id)) { $queue = $Classes[$id].Queue }
      elseif ("$($r.stamp)" -ge $script:ResultClassCutover) { $queue = 'operational' }
    }
    # The night key every consumer shares (section 32 item 1): the
    # scheduled night from the run's own start and zone, else its day.
    if (-not $demands.ContainsKey($id)) { $demands[$id] = [pscustomobject]@{ Id = $id; Day = (Get-ResultNight $r); Queue = $queue; Shas = @(); Incidents = @(); Paths = @(); Current = ''; CurrentTime = [datetime]::MinValue; AllIncidents = @(); Conflict = @(); Unreadable = $false; SchemaVersion = "$($r.version)"; Result = $r; Revision = -1; Regressions = @(); Results = @(); InvalidCopies = @() } }
    $d = $demands[$id]
    # Every valid copy stays readable to the deadline rule (section 46
    # item 3): a revision never grants a fresh window.
    $d.Results += $r
    $sha = Get-FileSha256 $p
    if ($d.Shas -notcontains $sha) { $d.Shas += $sha }
    $d.Paths += $p
    $copyInc = @()
    foreach ($ln in @($r.incidents)) {
      $m = [regex]::Match("$ln", '(INC-[0-9a-f]{8})')
      if ($m.Success -and ($copyInc -notcontains $m.Groups[1].Value)) { $copyInc += $m.Groups[1].Value }
    }
    foreach ($i in $copyInc) { if ($d.AllIncidents -notcontains $i) { $d.AllIncidents += $i } }
    $hasRev = @($r.PSObject.Properties.Name) -contains 'revision'
    $rev = 0
    if ($hasRev) { try { $rev = [int]$r.revision } catch { $rev = 0 } }
    $wt = (Get-Item -LiteralPath $p).LastWriteTimeUtc
    if ($hasRev -and ($rev -gt 0)) {
      if ($rev -gt $d.Revision) {
        # A lower revision written after a higher one is a regression
        # (section 39 item 5): flagged, never current.
        if (($d.Revision -gt 0) -and ($d.CurrentTime -gt $wt)) { $d.Regressions += "revision $rev ($p) was written before revision $($d.Revision)" }
        $d.Revision = $rev; $d.Current = $sha; $d.CurrentTime = $wt; $d.Incidents = $copyInc; $d.Result = $r; $d.Conflict = @(); $d.Queue = $queue
      }
      elseif (($rev -lt $d.Revision) -and ($wt -gt $d.CurrentTime)) { $d.Regressions += "revision $rev ($(Split-Path -Leaf $p)) written after revision $($d.Revision)" }
      elseif (($rev -eq $d.Revision) -and ($sha -ne $d.Current)) { if ($d.Conflict -notcontains $sha) { $d.Conflict += $sha } }
    } elseif ($d.Revision -le 0) {
      # Legacy copies: the most recently written is current, so an older
      # retained copy can never keep a changed result acknowledged.
      if ($wt -ge $d.CurrentTime) { $d.Current = $sha; $d.CurrentTime = $wt; $d.Incidents = $copyInc; $d.Result = $r; $d.Revision = 0; $d.Queue = $queue }
    }
  }
  foreach ($iv in $invalidNamed) {
    if (-not $demands.ContainsKey($iv.Id)) { continue }
    $d = $demands[$iv.Id]
    $d.InvalidCopies += "$(if ($iv.Revision -ne '') { "revision $($iv.Revision) " })($($iv.Name)) is invalid ($($iv.Why)) and never supersedes; revision $($d.Revision) stays current"
  }
  return $demands
}

function Read-AckFrontmatter([string]$Text) {
  # The leading `---` block of an ack file: `key: value` lines, with
  # `run:` and `cover:` repeatable. Returns Ok, Fields (last value per
  # key), Runs (each `run:` value), Covers (each `cover:` value), Error.
  $lines = @("$Text" -split "`r?`n")
  if (($lines.Count -lt 3) -or ($lines[0].Trim() -ne '---')) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Covers = @(); Error = 'no frontmatter' } }
  $fields = @{}
  $runs = @()
  $covers = @()
  $closed = $false
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln.Trim() -eq '---') { $closed = $true; break }
    if ($ln.Trim() -eq '') { continue }
    $m = [regex]::Match($ln, '^([a-z][a-z0-9-]*):\s*(.*?)\s*$')
    if (-not $m.Success) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Covers = @(); Error = "frontmatter line malformed: $ln" } }
    switch ($m.Groups[1].Value) {
      'run' { $runs += $m.Groups[2].Value }
      'cover' { $covers += $m.Groups[2].Value }
      default { $fields[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
  }
  if (-not $closed) { return [pscustomobject]@{ Ok = $false; Fields = @{}; Runs = @(); Covers = @(); Error = 'frontmatter not closed' } }
  return [pscustomobject]@{ Ok = $true; Fields = $fields; Runs = $runs; Covers = $covers; Error = '' }
}

function Test-AckV2([string]$Text, [hashtable]$Demands, [hashtable]$Aliases = @{}) {
  # Validates one v2 ack against the live demands (D00 T02 §23 items 1
  # and 2): every named run is a known RED identity whose recorded
  # checksum matches a copy of its result, the incident list equals the
  # run's incident ids, and the disposition is structured (enum,
  # corrective owner, due date on or after signing, linked finding).
  # A `withdrawn` ack names its runs, owner, and signing day only: it
  # releases them (section 31 item 10). A run whose copies conflict at
  # one revision cannot be acked (item 5). An ack naming more than one
  # incident covers each with a `cover:` line or says `covers-all: yes`
  # (item 9). Returns Ok, Acked, Stale, Errors, Disposition.
  $fm = Read-AckFrontmatter $Text
  if (-not $fm.Ok) { return [pscustomobject]@{ Ok = $false; Acked = @(); Stale = @(); Errors = @($fm.Error); Disposition = '' } }
  $f = $fm.Fields
  $errs = @()
  $disp = "$($f['disposition'])"
  $withdrawn = ($disp -eq 'withdrawn')
  if ("$($f['ack-version'])" -ne '2') { $errs += "ack-version must be 2 (got '$($f['ack-version'])')" }
  $required = if ($withdrawn) { @('owner', 'disposition', 'signed') } else { @('owner', 'disposition', 'corrective-owner', 'due', 'finding', 'signed', 'incidents') }
  foreach ($req in $required) {
    if (-not $f.ContainsKey($req) -or ("$($f[$req])" -eq '')) { $errs += "missing $req" }
  }
  $placeholder = '^(TBD|TODO|TBS|XXX|none|n/a|unknown|\?)$'
  foreach ($who in @('owner', 'corrective-owner')) {
    if ($f.ContainsKey($who) -and ("$($f[$who])" -match $placeholder)) { $errs += "$who is a placeholder" }
  }
  if ($f.ContainsKey('disposition') -and ($script:AckDispositions -notcontains $disp)) { $errs += "disposition '$disp' not one of $($script:AckDispositions -join ', ')" }
  $signed = [datetime]::MinValue
  $due = [datetime]::MinValue
  $signedOk = $f.ContainsKey('signed') -and [datetime]::TryParseExact("$($f['signed'])", 'yyyy-MM-dd', $null, 'None', [ref]$signed)
  $dueOk = $f.ContainsKey('due') -and [datetime]::TryParseExact("$($f['due'])", 'yyyy-MM-dd', $null, 'None', [ref]$due)
  if ($f.ContainsKey('signed') -and -not $signedOk) { $errs += "signed is not a YYYY-MM-DD date" }
  if ($f.ContainsKey('due') -and -not $dueOk) { $errs += "due is not a YYYY-MM-DD date" }
  if ($signedOk -and $dueOk -and ($due -lt $signed)) { $errs += 'due precedes signed' }
  $findingRe = '^(D\d{2} T\d{2} \u00A7\d+|INC-[0-9a-f]{8}|[0-9a-f]{7,40})$'
  if ($f.ContainsKey('finding') -and ("$($f['finding'])" -notmatch $findingRe)) { $errs += "finding '$($f['finding'])' is not a section ref, incident id, or commit" }
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
    # A damaged file repaired into another run (section 46 item 7) stays on
    # record: the ack is stale for it (re-ack the restored run), never
    # invalid, so its history and actions survive the repair.
    if ((-not $Demands.ContainsKey($id)) -and $Aliases.ContainsKey($id)) { $stale += $id; continue }
    if (-not $Demands.ContainsKey($id)) { $errs += "run $id is not a known RED"; continue }
    $d = $Demands[$id]
    if (@($d.Conflict).Count -gt 0) { $errs += "run $id has conflicting result copies at revision $($d.Revision) ($(@(@($d.Current) + @($d.Conflict)) | ForEach-Object { $_.Substring(0, 12) }) -join ', '); resolve the copies before acking"; continue }
    if ($d.Current -ne $sha) { $stale += $id; continue }
    $acked += $id
  }
  $covFault = @{}
  if ((-not $withdrawn) -and $f.ContainsKey('incidents') -and ($errs.Count -eq 0)) {
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
    # Per-incident coverage (section 31 item 9). Every cover line is
    # validated whatever the batch shape (section 46 R1-F1): coverage
    # faults are per incident (item 11), each rejecting only the runs that
    # carry the incident, and one incident has exactly one effective
    # disposition, so a second cover for it refuses even with one incident
    # listed or covers-all.
    $covered = @{}
    foreach ($c in @($fm.Covers)) {
      $cm = [regex]::Match("$c", $script:AckCoverRe)
      if (-not $cm.Success) { $errs += "cover line malformed: $c"; continue }
      $ci = $cm.Groups[1].Value
      if ($listed -notcontains $ci) { $errs += "cover names $ci, which the ack does not list"; continue }
      if ($covered.ContainsKey($ci)) { $covFault[$ci] = "cover names $ci twice (one incident has exactly one disposition)"; continue }
      $covered[$ci] = $true
      if (($script:AckDispositions -notcontains $cm.Groups[2].Value) -or ($cm.Groups[2].Value -eq 'withdrawn')) { $covFault[$ci] = "cover $ci disposition '$($cm.Groups[2].Value)' unknown"; continue }
      if ($cm.Groups[3].Value -notmatch $findingRe) { $covFault[$ci] = "cover $ci finding '$($cm.Groups[3].Value)' is not a section ref, incident id, or commit"; continue }
    }
    if (($listed.Count -gt 1) -and ("$($f['covers-all'])" -ne 'yes')) {
      foreach ($u in @($listed | Where-Object { -not $covered.ContainsKey($_) })) { $covFault[$u] = "batch of $($listed.Count) incidents leaves $u uncovered (add a cover line per incident or covers-all: yes)" }
    }
  }
  if ($errs.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Acked = @(); Stale = $stale; Errors = $errs; Disposition = $disp; Rejected = @() } }
  # Runs carrying a faulted incident are rejected alone; the rest stand.
  $rejected = @()
  foreach ($id in @($acked)) {
    $hit = @(@($Demands[$id].Incidents) | Where-Object { $covFault.ContainsKey($_) })
    if ($hit.Count -gt 0) { $rejected += [pscustomobject]@{ Run = $id; Why = (@($hit | ForEach-Object { $covFault[$_] }) -join '; ') } }
  }
  $keep = @($acked | Where-Object { $r = $_; @($rejected | Where-Object { $_.Run -eq $r }).Count -eq 0 })
  if (($covFault.Count -gt 0) -and ($keep.Count -eq 0)) { return [pscustomobject]@{ Ok = $false; Acked = @(); Stale = $stale; Errors = @($covFault.Values | Sort-Object -Unique); Disposition = $disp; Rejected = $rejected } }
  return [pscustomobject]@{ Ok = $true; Acked = $keep; Stale = $stale; Errors = @(); Disposition = $disp; Rejected = $rejected }
}

function Get-AckHistory([string]$Root, [string]$RelPath) {
  # The append-only integrity record (D00 T02 §23 item 5): an ack
  # counts only once committed with the working copy equal to HEAD, and
  # its history is the git log of the file (trunk never amends or
  # force-pushes, so the log only grows). Returns Committed, Dirty,
  # Entries (commit, author, date, newest first), and Error.
  $out = [pscustomobject]@{ Committed = $false; Dirty = $false; Entries = @(); Error = ''; Added = '' }
  $eap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    # Receipt time is the committer date (D00 T02 section 46 item 4): the
    # author date and the declared `signed` are the writer's own claims
    # and can be backdated; the committer date is when the ack landed.
    $log = @(git -C $Root log --follow --format='%H|%an|%cI' -- $RelPath 2>$null)
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
    # When this incarnation of the file was created (section 39 item 3):
    # the most recent add, so a reused file name never borrows an older,
    # deleted file's history as its response time.
    $adds = @(git -C $Root log --diff-filter=A --format=%cI -- $RelPath 2>$null)
    if ($adds.Count -gt 0) { $out.Added = "$($adds[0])" } elseif ($out.Entries.Count -gt 0) { $out.Added = "$($out.Entries[-1].Date)" }
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
    foreach ($f in @(Get-SectionTodoFiles $Root $m.Groups[1].Value $m.Groups[2].Value)) {
      foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName)) { if ($ln -match "^## $($m.Groups[3].Value)\. ") { return $true } }
    }
    return $false
  }
  if ($Finding -match '^INC-[0-9a-f]{8}$') { return (@($KnownIncidents) -contains $Finding) }
  if ($Finding -match '^[0-9a-f]{7,40}$') { return (Test-CommitExists $Root $Finding) }
  return $false
}

function Get-SectionTodoFiles([string]$Root, [string]$Domain, [string]$Todo) {
  return @(Get-ChildItem (Join-Path $Root 'todo') -Directory -Filter "$Domain-*" -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem $_.FullName -File -Filter "TODO-$Todo-*.md" -ErrorAction SilentlyContinue })
}

function Test-CommitExists([string]$Root, [string]$Sha) {
  # Windows PowerShell turns native stderr into a terminating error
  # under Stop even when redirected, so the probe runs with the
  # preference scoped to Continue and reads only the exit code.
  $found = $false
  $eap = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $null = git -C $Root cat-file -e "$Sha^{commit}" 2>&1; $found = ($LASTEXITCODE -eq 0) } catch { $found = $false } finally { $ErrorActionPreference = $eap }
  return $found
}

function Test-SectionStamped([string]$Root, [string]$Ref) {
  # True when the section's Implementation Order row reads [x] (its
  # stamp landed): the evidence that closes a corrective action.
  $m = [regex]::Match($Ref, '^D(\d{2}) T(\d{2}) \u00A7(\d+)$')
  if (-not $m.Success) { return $false }
  foreach ($f in @(Get-SectionTodoFiles $Root $m.Groups[1].Value $m.Groups[2].Value)) {
    foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName)) {
      if ($ln -match "^\|\s*\d+\s*\|\s*\u00A7$($m.Groups[3].Value)\s*\|.*\|\s*\[x\]\s*\|\s*$") { return $true }
    }
  }
  return $false
}

function Get-IncidentTests([string[]]$Runs, [hashtable]$Demands, [string[]]$Only = @()) {
  # Test names the acked runs' incidents name (`- INC-x `<test>` ...`);
  # with $Only, just those incidents' tests (section 39 R2-F1: a cover's
  # evidence answers for its own incident, never another's).
  $tests = @()
  $filter = @($Only | Where-Object { "$_" -match '^INC-[0-9a-f]{8}$' })
  foreach ($id in @($Runs)) {
    if (-not $Demands.ContainsKey($id) -or ($null -eq $Demands[$id].Result)) { continue }
    foreach ($ln in @($Demands[$id].Result.incidents)) {
      $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)`')
      if ((-not $m.Success) -or (($filter.Count -gt 0) -and ($filter -notcontains $m.Groups[1].Value))) { continue }
      if ($tests -notcontains $m.Groups[2].Value) { $tests += $m.Groups[2].Value }
    }
  }
  return $tests
}

function Test-CommitAddresses([string]$Root, [string]$Sha, [string[]]$Tests, [string[]]$Incidents = @()) {
  # A `fixed` commit addresses the failure (section 39 item 7, R1-F1): it
  # touches the failing test's own file, or its message names the failing
  # test or the incident. Any other commit, product code included, is not
  # evidence that this failure was fixed.
  $eap = $ErrorActionPreference
  $files = @()
  $msg = ''
  try {
    $ErrorActionPreference = 'Continue'
    $files = @(git -C $Root show --name-only --format= $Sha 2>$null | Where-Object { "$_" -ne '' })
    $msg = (@(git -C $Root log -1 --format=%B $Sha 2>$null) -join "`n")
  } catch { $files = @() } finally { $ErrorActionPreference = $eap }
  # A RED with no incidents (an infrastructure failure) names no test to
  # address: any existing commit is its fix.
  if ((@($Tests | Where-Object { "$_" -ne '' }).Count -eq 0) -and (@($Incidents | Where-Object { "$_" -ne '' }).Count -eq 0)) { return $true }
  # Namespace.Class.Method names the class second to last; a two-part
  # name (Namespace.Class) names it last.
  $classes = @($Tests | ForEach-Object { $parts = "$_" -split '\.'; if ($parts.Count -ge 3) { $parts[-2] } elseif ($parts.Count -eq 2) { $parts[-1] } })
  foreach ($f in $files) { foreach ($c in $classes) { if (($f -like 'tests/*') -and ((Split-Path -Leaf $f) -like "$c.*")) { return $true } } }
  foreach ($n in @(@($Tests) + @($Incidents))) { if (("$n" -ne '') -and $msg.Contains("$n")) { return $true } }
  return $false
}

function Test-SectionMentions([string]$Root, [string]$Ref, [string[]]$Needles) {
  # A `filed` section names the incident or its test (section 39 item 7)
  # on an executable remediation item (section 46 item 9): a checklist
  # line (`- [ ]` or `- [x]`), never prose alone.
  $m = [regex]::Match($Ref, '^D(\d{2}) T(\d{2}) \u00A7(\d+)$')
  if (-not $m.Success) { return $false }
  foreach ($f in @(Get-SectionTodoFiles $Root $m.Groups[1].Value $m.Groups[2].Value)) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    $h = [regex]::Match($text, "(?m)^## $($m.Groups[3].Value)\. .*$")
    if (-not $h.Success) { continue }
    $end = $text.IndexOf("`n## ", $h.Index + $h.Length)
    $body = if ($end -lt 0) { $text.Substring($h.Index) } else { $text.Substring($h.Index, $end - $h.Index) }
    foreach ($ln in @($body -split "`r?`n")) {
      if ($ln -notmatch '^\s*- \[[ x]\] ') { continue }
      foreach ($n in @($Needles)) { if (("$n" -ne '') -and $ln.Contains("$n")) { return $true } }
    }
  }
  return $false
}

function ConvertTo-LocalStamp([string]$Iso) {
  # An ISO instant as the nightly's local run stamp (yyyy-MM-dd-HHmmss),
  # so a commit time orders against run stamps; '' when it cannot parse.
  $t = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse($Iso, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t)) { return '' }
  return $t.ToLocalTime().ToString('yyyy-MM-dd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-FixVerified([string]$Root, [string]$Sha, [string[]]$Incidents, $Ledger) {
  # A `fixed` action closes only on verification (D00 T02 section 46 item
  # 9): after the fix commit, a run passed the failing test, read from the
  # incident ledger (a pass recorded at a stamp after the commit, or a
  # verified-recovery closure after it). A RED with no incidents (an
  # infrastructure failure) names no test, so its commit suffices.
  # Returns Ok and Why.
  $inc = @(@($Incidents) | Where-Object { "$_" -match '^INC-[0-9a-f]{8}$' })
  if ($inc.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Why = '' } }
  $when = ''
  $eap = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $when = "$(@(git -C $Root show -s --format=%cI $Sha 2>$null) | Select-Object -First 1)" } catch { $when = '' } finally { $ErrorActionPreference = $eap }
  $after = ConvertTo-LocalStamp $when
  if ($after -eq '') { return [pscustomobject]@{ Ok = $false; Why = "the commit time of $Sha cannot be read" } }
  foreach ($i in $inc) {
    $e = $null
    if (($null -ne $Ledger) -and $Ledger.ContainsKey($i)) { $e = $Ledger[$i] }
    $pass = if ($null -ne $e) { "$($e.lastPassStamp)" } else { '' }
    $closedAt = if ($null -ne $e) { "$($e.closedAt)" } else { '' }
    if ((($pass -ne '') -and ($pass -gt $after)) -or (($closedAt -ne '') -and ($closedAt -gt $after))) { continue }
    return [pscustomobject]@{ Ok = $false; Why = "commit $Sha landed; awaiting a passing run of $i's test after it" }
  }
  return [pscustomobject]@{ Ok = $true; Why = '' }
}

function Test-DispositionEvidence($Fields, [string[]]$Runs, [hashtable]$Demands, [string]$Root, [string[]]$Incidents = @()) {
  # Each disposition names its evidence (section 31 item 3), carried by
  # `finding` or an `evidence:` field: fixed a commit, filed a section,
  # quarantined a test on the quarantine list, environment a record
  # that exists in the tree, expected the proof section it served,
  # duplicate the other run it repeats. Returns error strings.
  $disp = "$($Fields['disposition'])"
  $finding = "$($Fields['finding'])"
  $ev = "$($Fields['evidence'])"
  $both = @($finding, $ev) | Where-Object { $_ -ne '' }
  $isCommit = { param($x) ($x -match '^[0-9a-f]{7,40}$') -and (Test-CommitExists $Root $x) }
  $isSection = { param($x) $x -match '^D\d{2} T\d{2} \u00A7\d+$' }
  switch ($disp) {
    'fixed' {
      $commits = @($both | Where-Object { & $isCommit $_ })
      if ($commits.Count -eq 0) { return @('fixed needs a commit that exists (finding or evidence)') }
      $tests = @(Get-IncidentTests $Runs $Demands $Incidents)
      if (@($commits | Where-Object { Test-CommitAddresses $Root $_ $tests $Incidents }).Count -eq 0) { return @("fixed needs a commit that touches the failing test's file or names the test or incident ($($commits -join ', ') does neither)") }
    }
    'filed' {
      $secs = @($both | Where-Object { (& $isSection $_) -and (Test-FindingExists $Root $_ @()) })
      if ($secs.Count -eq 0) { return @('filed needs a section ref that exists (finding or evidence)') }
      $needles = @(@($Incidents) + @(Get-IncidentTests $Runs $Demands $Incidents)) | Where-Object { "$_" -ne '' }
      if (($needles.Count -gt 0) -and (@($secs | Where-Object { Test-SectionMentions $Root $_ $needles }).Count -eq 0)) { return @("filed needs a section that names the incident or its test ($($secs -join ', ') names neither)") }
    }
    'expected' { if (@($both | Where-Object { (& $isSection $_) -and (Test-FindingExists $Root $_ @()) }).Count -eq 0) { return @('expected needs the proof section it served, existing (finding or evidence)') } }
    'quarantined' {
      $qPath = Join-Path $Root 'docs/soak-and-quarantine.md'
      $listed = $false
      if (($ev -ne '') -and (Test-Path $qPath)) { $listed = ((Get-Content $qPath -Raw -Encoding UTF8) -match [regex]::Escape("``$ev``")) }
      if (-not $listed) { return @("quarantined needs evidence naming a test on the quarantine list (got '$ev')") }
    }
    'environment' { if (($ev -eq '') -or (-not (Test-Path (Join-Path $Root $ev)))) { return @("environment needs evidence naming the preflight or block record in the tree (got '$ev')") } }
    'duplicate' { if (($ev -eq '') -or (-not $Demands.ContainsKey($ev)) -or (@($Runs) -contains $ev)) { return @("duplicate needs evidence naming the other known RED it repeats (got '$ev')") } }
  }
  return @()
}

function Test-AckEvidence([string]$Root, $Frontmatter, [string[]]$Acked, [hashtable]$Demands, [string[]]$KnownIncidents) {
  # Everything an ack claims beyond its shape, shared by the gate and
  # tools/NightlyAck.ps1 -Draft (section 31 R2-F3): the linked finding
  # exists, the disposition carries its evidence, and every cover line's
  # finding exists and carries the evidence its own disposition needs.
  # Returns error strings.
  $f = $Frontmatter.Fields
  $errs = @()
  $fnd = "$($f['finding'])"
  if (-not (Test-FindingExists $Root $fnd $KnownIncidents)) { return @("finding $fnd not found") }
  $listedInc = @("$($f['incidents'])" -split '[,\s]+' | Where-Object { ($_ -ne '') -and ($_ -ne 'none') })
  $errs += @(Test-DispositionEvidence $f $Acked $Demands $Root $listedInc)
  foreach ($c in @($Frontmatter.Covers)) {
    $cm = [regex]::Match("$c", $script:AckCoverRe)
    if (-not $cm.Success) { continue }
    if (-not (Test-FindingExists $Root $cm.Groups[3].Value $KnownIncidents)) { $errs += "cover $($cm.Groups[1].Value) finding $($cm.Groups[3].Value) not found"; continue }
    foreach ($e in @(Test-DispositionEvidence @{ disposition = $cm.Groups[2].Value; finding = $cm.Groups[3].Value; evidence = $cm.Groups[4].Value } $Acked $Demands $Root @($cm.Groups[1].Value))) { $errs += "cover $($cm.Groups[1].Value): $e" }
  }
  return $errs
}

function Get-AckDue($Demand, [int]$SlaHours = 0) {
  # The deadline as an explicit timestamp (section 31 item 8): the end
  # of the run's day plus $script:AckDueDays (23:59:59 in the run's own
  # zone, the boundary inclusive), shortened to the run start plus the
  # §24 severity SLA when that comes first. Returns a DateTimeOffset, or
  # $null when the day cannot be read.
  $dayDate = [datetime]::MinValue
  if (-not [datetime]::TryParseExact("$($Demand.Day)", 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$dayDate)) { return $null }
  $offset = [System.TimeZoneInfo]::Local.GetUtcOffset($dayDate)
  $r = $Demand.Result
  try {
    $tzm = [regex]::Match("$($r.tz)", '^([+-])(\d{2}):(\d{2})$')
    if ($tzm.Success) { $offset = New-TimeSpan -Hours ([int]$tzm.Groups[2].Value) -Minutes ([int]$tzm.Groups[3].Value); if ($tzm.Groups[1].Value -eq '-') { $offset = $offset.Negate() } }
  } catch { }
  $due = [DateTimeOffset]::new($dayDate.AddDays($script:AckDueDays).AddHours(23).AddMinutes(59).AddSeconds(59), $offset)
  if ($SlaHours -gt 0) {
    $start = $null
    try { if ($r.startUtc -is [datetime]) { $start = [DateTimeOffset]::new(([datetime]$r.startUtc).ToUniversalTime()) } elseif ("$($r.startUtc)" -ne '') { $start = [DateTimeOffset]::Parse("$($r.startUtc)", [System.Globalization.CultureInfo]::InvariantCulture) } } catch { $start = $null }
    if ($null -eq $start) { $start = [DateTimeOffset]::new($dayDate, $offset) }
    $sla = $start.AddHours($SlaHours).ToOffset($offset)
    if ($sla -lt $due) { $due = $sla }
  }
  return $due
}

function Get-DemandDue($Demand, [scriptblock]$SlaFor = $null, $Inherited = $null) {
  # The demand's deadline inherits (D00 T02 section 46 item 3): the
  # earliest due over every copy of the run ever read (each with its own
  # day, zone, and severity SLA), the demand's own day, and any deadline
  # inherited from a corruption repair, so a revision, a severity change,
  # or a repair never grants a fresh window. Returns a DateTimeOffset, or
  # $null when no day reads.
  $best = $null
  $cands = @($Demand)
  foreach ($c in @($Demand.Results)) { if ($null -ne $c) { $cands += [pscustomobject]@{ Day = (Get-ResultNight $c); Result = $c } } }
  foreach ($c in $cands) {
    $sla = 0
    if (($null -ne $SlaFor) -and ($null -ne $c.Result)) { try { $sla = [int](& $SlaFor $c.Result) } catch { $sla = 0 } }
    $due = Get-AckDue $c $sla
    if (($null -ne $due) -and (($null -eq $best) -or ($due -lt $best))) { $best = $due }
  }
  if (($null -ne $Inherited) -and (($null -eq $best) -or ($Inherited -lt $best))) { $best = $Inherited }
  return $best
}

function Get-RunFirstNamed([string]$Root, [string]$RelPath, [string]$Id, [string]$Since) {
  # The oldest commit of this file incarnation (on or after $Since, its
  # creation) whose change introduced `run: <id> ` (git's pickaxe): when
  # the file first acknowledged that run.
  $eap = $ErrorActionPreference
  $dates = @()
  try { $ErrorActionPreference = 'Continue'; $dates = @(git -C $Root log --format=%cI -S "run: $Id " -- $RelPath 2>$null | Where-Object { ("$_" -ne '') -and (($Since -eq '') -or ("$_" -ge $Since)) }) } catch { $dates = @() } finally { $ErrorActionPreference = $eap }
  if ($dates.Count -gt 0) { return "$($dates[-1])" }
  return $Since
}

function Test-CommitDescends([string]$Root, [string]$Newer, [string]$Older) {
  # True when $Older is an ancestor of (or equal to) $Newer; a pending
  # draft descends from everything committed.
  if (($Newer -eq $Older) -or ($Newer -eq 'PENDING-DRAFT')) { return $true }
  if ($Older -eq 'PENDING-DRAFT') { return $false }
  $eap = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $null = git -C $Root merge-base --is-ancestor $Older $Newer 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false } finally { $ErrorActionPreference = $eap }
}

function Get-AckHistoricalTargets([string]$Root, [string]$RelPath) {
  # Every remediation target any committed version of an ack file named
  # (section 39 R2-F2): the finding and each cover's, with the date it was
  # first named, so an edit that drops a cover never erases its action.
  $targets = [ordered]@{}
  $eap = $ErrorActionPreference
  # git writes UTF-8; Windows PowerShell decodes native output with the
  # console encoding, which would mangle the section sign in findings.
  $enc = [Console]::OutputEncoding
  try {
    $ErrorActionPreference = 'Continue'
    # A session with no console (a scheduled task) may refuse the set;
    # the read still runs.
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    $commits = @(git -C $Root log --format='%H|%cI' -- $RelPath 2>$null)
    [array]::Reverse($commits)
    foreach ($c in $commits) {
      $parts = "$c" -split '\|', 2
      if ($parts.Count -ne 2) { continue }
      $text = (@(git -C $Root show "$($parts[0]):$RelPath" 2>$null) -join "`n")
      if ($LASTEXITCODE -ne 0) { continue }
      $fm = Read-AckFrontmatter $text
      if (-not $fm.Ok) { continue }
      $top = "$($fm.Fields['finding'])"
      # The incidents that version listed ride its targets (section 46
      # R1-C1), so a later edit that drops them never empties what a
      # historical action must verify.
      $verInc = @("$($fm.Fields['incidents'])" -split '[,\s]+' | Where-Object { ($_ -ne '') -and ($_ -ne 'none') })
      # A label named again in a later version adds that version's
      # incidents (section 46 R2-C1).
      if (($top -ne '') -and ("$($fm.Fields['disposition'])" -ne 'withdrawn') -and $targets.Contains($top)) { foreach ($vi in $verInc) { if (@($targets[$top].Incidents) -notcontains $vi) { $targets[$top].Incidents = @(@($targets[$top].Incidents) + @($vi)) } } }
      if (($top -ne '') -and ("$($fm.Fields['disposition'])" -ne 'withdrawn') -and (-not $targets.Contains($top))) { $targets[$top] = [pscustomobject]@{ Label = $top; Finding = $top; Disposition = "$($fm.Fields['disposition'])"; Evidence = "$($fm.Fields['evidence'])"; Since = $parts[1]; Due = "$($fm.Fields['due'])"; Owner = "$($fm.Fields['corrective-owner'])"; Incidents = $verInc } }
      foreach ($cv in @($fm.Covers)) {
        $cm = [regex]::Match("$cv", $script:AckCoverRe)
        if ($cm.Success) { $k = "$($cm.Groups[1].Value) $($cm.Groups[3].Value)"; if (-not $targets.Contains($k)) { $targets[$k] = [pscustomobject]@{ Label = $k; Finding = $cm.Groups[3].Value; Disposition = $cm.Groups[2].Value; Evidence = $cm.Groups[4].Value; Since = $parts[1]; Due = "$($fm.Fields['due'])"; Owner = "$($fm.Fields['corrective-owner'])"; Incidents = @($cm.Groups[1].Value) } } }
      }
    }
  } catch { } finally { $ErrorActionPreference = $eap; try { [Console]::OutputEncoding = $enc } catch { } }
  return $targets
}

function Test-Acknowledgements([string]$Root, [string]$AckDir, [hashtable]$Demands, [datetime]$Today, [scriptblock]$SlaFor = $null, [string]$Assume = '') {
  # The whole gate (D00 T02 §23, §31): v2 acks (committed, clean, valid,
  # evidenced) plus v1 day files for runs on or before the cutover
  # acknowledge demands. Per run the ack with the newest commit governs,
  # and a governing `withdrawn` releases the run (item 10). Everything
  # else stays unacked with its due timestamp; an operational demand
  # past due escalates and stages a filing for tools/NightlyAck.ps1
  # -FileOverdue (item 1), while proof, simulation, and backfill runs
  # queue apart and never stage (item 7). $Today is the instant the gate
  # judges (the run's clock); $SlaFor maps a result to §24's SLA hours.
  # A governing non-withdrawn ack opens a corrective action that closes
  # only on evidence (item 2): its commit finding, its section stamped,
  # or a `closed:` commit; an incident finding closes only on `closed:`,
  # never on the incident's recovery (item 12). Returns Ok (operational
  # queue acked), Unacked, ProofUnacked, Lines, Staged, Overdue,
  # Corrective, CorrectiveOverdue.
  $lines = @()
  $staged = @()
  $knownIncidents = @()
  foreach ($id in @($Demands.Keys)) { $knownIncidents += @($Demands[$id].Incidents) }
  $ledgerRead = Read-IncidentLedger (Join-Path $Root 'build\nightly\incidents.json')
  if ($ledgerRead.Ok) { $knownIncidents += @($ledgerRead.Incidents.Keys) }
  $now = [DateTimeOffset]::new($Today)
  # Corruption lineage (section 46 items 3, 7, 8): a repaired file maps its
  # unreadable demand onto the restored run, which inherits the earlier
  # deadline, and acks naming the damaged file stay on record (stale); a
  # damaged file deleted or renamed before any repair keeps its demand
  # from the record until an ack names it.
  $inheritDue = @{}
  $dues = @{}
  $corrAlias = @{}
  foreach ($e in @(Read-CorruptionRecord (Join-Path $Root 'build\nightly\ack-corruption.json'))) {
    $alias = "unreadable:$($e.file)"
    $dm = [regex]::Match("$($e.file)", '(\d{4}-\d{2}-\d{2})')
    $eday = if ($dm.Success) { $dm.Groups[1].Value } else { '' }
    if ("$($e.restored)" -ne '') {
      $corrAlias[$alias] = "$($e.restored)"
      $ud = Get-AckDue ([pscustomobject]@{ Day = $eday; Result = $null }) 0
      $rid = "$($e.restored)"
      if (($null -ne $ud) -and ((-not $inheritDue.ContainsKey($rid)) -or ($ud -lt $inheritDue[$rid]))) { $inheritDue[$rid] = $ud }
      $lines += "- CORRUPTION merge: $alias restored as $rid; the earlier deadline carries to $rid and acks of $alias stay on record"
      continue
    }
    if (-not $Demands.ContainsKey($alias)) {
      $Demands[$alias] = [pscustomobject]@{ Id = $alias; Day = $eday; Queue = 'operational'; Shas = @("$($e.sha)"); Incidents = @(); Paths = @(); Current = "$($e.sha)"; CurrentTime = [datetime]::MinValue; AllIncidents = @(); Conflict = @(); Unreadable = $true; Invalid = "deleted or renamed while unreadable (first seen $($e.firstSeen): $($e.reason))"; SchemaVersion = ''; Result = $null; Revision = 0; Regressions = @(); Results = @(); InvalidCopies = @() }
    }
  }
  $validFiles = [ordered]@{}
  if ("$($script:ResultClassTampered)" -ne '') { $lines += "- CLASSIFICATION ledger TAMPERED ($($script:ResultClassTampered)); entries from there on are ignored and their runs read operational" }
  $v1Acked = @{}
  $claims = @{}
  $staleGoverning = @{}
  $responded = @{}
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
      foreach ($id in @($Demands.Keys)) { if ($Demands[$id].Day -eq $day) { $v1Acked[$id] = "v1 $($file.Name)"; $n++ } }
      $lines += "- $($file.Name): v1 legacy, acknowledges $n run(s) of $day"
      continue
    }
    $hist = Get-AckHistory $Root $rel
    # A draft judged as if committed now (section 39 R1-F5): what the gate
    # will read once it lands, governance included.
    # With a draft assumed (R3-F4), every uncommitted or edited ack file
    # is judged as landing in the same pending commit, so staged
    # competitors tie as they will once committed together.
    if (($Assume -ne '') -and (($file.Name -eq $Assume) -or ((-not $hist.Committed) -or $hist.Dirty))) { $stamp = [DateTimeOffset]::new($Today).ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture); $hist = [pscustomobject]@{ Committed = $true; Dirty = $false; Entries = @([pscustomobject]@{ Commit = 'PENDING-DRAFT'; Author = 'draft'; Date = $stamp }); Error = ''; Added = $stamp } }
    if ($hist.Error -ne '') { $lines += "- $($file.Name): history unverifiable ($($hist.Error)); ignored"; continue }
    if (-not $hist.Committed) { $lines += "- $($file.Name): uncommitted (ignored until committed: git history is the integrity record)"; continue }
    if ($hist.Dirty) { $lines += "- $($file.Name): edited since its last commit (ignored until committed)"; continue }
    $v = Test-AckV2 $text $Demands $corrAlias
    $histText = (@($hist.Entries | ForEach-Object { "$($_.Commit.Substring(0, 7)) $($_.Author) $($_.Date)" }) -join '; ')
    $fm = Read-AckFrontmatter $text
    if ($v.Ok -and ($v.Disposition -ne 'withdrawn')) {
      # The linked finding must exist, and the disposition must carry its
      # own evidence (section 31 item 3).
      $evErr = @(Test-AckEvidence $Root $fm @($v.Acked) $Demands $knownIncidents)
      if ($evErr.Count -gt 0) { $v = [pscustomobject]@{ Ok = $false; Acked = @(); Stale = $v.Stale; Errors = $evErr; Disposition = $v.Disposition } }
    }
    if (-not $v.Ok) { $lines += "- $($file.Name): INVALID ($($v.Errors -join '; ')); history $histText"; continue }
    foreach ($rj in @($v.Rejected)) { $lines += "- $($file.Name): REJECTS $($rj.Run) ($($rj.Why)); its other runs stand" }
    # Every valid file is remembered (section 46 item 2): one superseded or
    # withdrawn over still owes the remediation it opened.
    $validFiles[$file.Name] = [pscustomobject]@{ File = $file.Name; Fields = $fm.Fields; Covers = @($fm.Covers); Disposition = $v.Disposition; Runs = @(@($v.Acked) + @($v.Stale)) }
    $when = if ($hist.Entries.Count -gt 0) { "$($hist.Entries[0].Date)" } else { '' }
    $commit = if ($hist.Entries.Count -gt 0) { "$($hist.Entries[0].Commit)" } else { '' }
    # The file's first commit is when it responded (section 39 item 3):
    # later edits and replacements never move a response earlier.
    $first = "$($hist.Added)"
    foreach ($id in $v.Acked) {
      if (-not $claims.ContainsKey($id)) { $claims[$id] = @() }
      $claims[$id] += [pscustomobject]@{ File = $file.Name; When = $when; First = $first; Commit = $commit; Disposition = $v.Disposition; Fields = $fm.Fields; Covers = @($fm.Covers); Replaces = "$($fm.Fields['replaces'])" }
    }
    # A signed ack whose run was revised since (stale) keeps the corrective
    # actions it opened (section 39 item 5): the revision does not close
    # the remediation it owed.
    if (($v.Disposition -ne 'withdrawn') -and (@($v.Stale).Count -gt 0)) { $staleGoverning[$file.Name] = [pscustomobject]@{ File = $file.Name; Fields = $fm.Fields; Covers = @($fm.Covers); Disposition = $v.Disposition; Runs = @($v.Stale) } }
    # Per run (R1-F4): when this file's history first named the run, so a
    # run added to an older ack reads its own response time.
    foreach ($id in @(@($v.Stale) + @($v.Acked))) {
      $at = if ($file.Name -eq $Assume) { $first } else { Get-RunFirstNamed $Root $rel $id $first }
      if (($at -ne '') -and ((-not $responded.ContainsKey($id)) -or ($at -lt $responded[$id]))) { $responded[$id] = $at }
    }
    $staleNote = if ($v.Stale.Count -gt 0) { "; STALE for $($v.Stale -join ', ') (result changed after the ack: re-ack with the new checksum)" } else { '' }
    $ackedText = if (@($v.Acked).Count -gt 0) { $v.Acked -join ', ' } else { 'nothing current' }
    $verb = if ($v.Disposition -eq 'withdrawn') { 'withdraws' } else { 'acknowledges' }
    $lines += "- $($file.Name): $verb $ackedText$staleNote; history $histText"
  }
  # The newest commit governs each run (section 31 item 10), ordered by
  # the commit graph (git log is newest first in topological order), not
  # by timestamps, which can tie or run backwards (R1-F4).
  $order = @{}
  $eap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $relDir = ($AckDir.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/'
    $i = 0
    if ($Assume -ne '') { $order['PENDING-DRAFT'] = -1 }
    foreach ($h in @(git -C $Root log --topo-order --format=%H -- $relDir 2>$null)) { if (-not $order.ContainsKey("$h")) { $order["$h"] = $i }; $i++ }
  } catch { } finally { $ErrorActionPreference = $eap }
  $acked = @{}
  $governing = @{}
  foreach ($id in @($claims.Keys)) {
    $ranked = @($claims[$id] | Sort-Object @{ Expression = { if ($order.ContainsKey($_.Commit)) { $order[$_.Commit] } else { [int]::MaxValue } } }, File)
    $g = $ranked[0]
    # Competing acks in one commit (section 39 item 4): the one naming the
    # other in `replaces:` governs; otherwise the tie is undecidable and
    # fails closed, leaving the run demanded until a later commit decides.
    # Competing acks whose commits are not ordered by ancestry (merged
    # branches, R2-F3) compete like a same-commit pair: the newer one must
    # descend from the other, or name it in replaces:.
    $sameCommit = @($ranked | Where-Object { ($_.Commit -eq $g.Commit) -or (-not (Test-CommitDescends $Root $g.Commit $_.Commit)) })
    if ($sameCommit.Count -gt 1) {
      # `replaces:` may list several files (section 46 item 5): a
      # resolution names every competing head it supersedes.
      $winners = @($sameCommit | Where-Object { $w = $_; $rep = @("$($w.Replaces)" -split '[,\s]+' | Where-Object { $_ -ne '' }); @($sameCommit | Where-Object { $_.File -ne $w.File }).Count -eq @($sameCommit | Where-Object { ($_.File -ne $w.File) -and ($rep -contains $_.File) }).Count })
      if ($winners.Count -ne 1) { $lines += "- $id TIE: $(@($sameCommit | ForEach-Object { $_.File }) -join ', ') land in one commit and none replaces the others; name the superseded file in replaces: (the run stays demanded)"; continue }
      $g = $winners[0]
    }
    if (@($claims[$id]).Count -gt 1) { $lines += "- $id governed by $($g.File) (newest of $(@($claims[$id]).Count) acks)" }
    if ($g.Disposition -eq 'withdrawn') { $lines += "- $id released by $($g.File) (withdrawn): demanded again"; continue }
    $acked[$id] = $g.File
    $governing[$g.File] = $g
  }
  foreach ($id in @($v1Acked.Keys)) { if (-not $claims.ContainsKey($id)) { $acked[$id] = $v1Acked[$id] } }
  # Duplicate references cannot cycle (section 39 item 7): a run whose
  # `duplicate` chain returns to itself acknowledges nothing.
  # Top-level and cover-level duplicates both point a run at another
  # (R1-F2), and any cycle through those edges acknowledges nothing.
  $dupOf = @{}
  foreach ($id in @($acked.Keys)) {
    $g = $governing[$acked[$id]]
    if ($null -eq $g) { continue }
    $to = @()
    if (($g.Disposition -eq 'duplicate') -and ("$($g.Fields['evidence'])" -ne '')) { $to += "$($g.Fields['evidence'])" }
    foreach ($c in @($g.Covers)) { $cm = [regex]::Match("$c", $script:AckCoverRe); if ($cm.Success -and ($cm.Groups[2].Value -eq 'duplicate') -and ($cm.Groups[4].Value -ne '')) { $to += $cm.Groups[4].Value } }
    if ($to.Count -gt 0) { $dupOf[$id] = $to }
  }
  $inCycle = @{}
  foreach ($start in @($dupOf.Keys)) {
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($start, @($start)))
    while ($stack.Count -gt 0) {
      $top = $stack.Pop()
      $node = $top[0]; $path = $top[1]
      foreach ($nx in @($dupOf[$node])) {
        if ($nx -eq $start) { foreach ($p in $path) { $inCycle[$p] = ($path + $start) -join ' -> ' }; continue }
        if (($path -notcontains $nx) -and $dupOf.ContainsKey($nx)) { $stack.Push(@($nx, @($path + $nx))) }
      }
    }
  }
  foreach ($id in @($inCycle.Keys | Sort-Object)) { $lines += "- $id duplicate CYCLE ($($inCycle[$id])): acknowledges nothing"; $acked.Remove($id) }
  # The response clock (section 39 item 3): when the run was first
  # answered against its response deadline, whatever later replaced it.
  foreach ($id in @($responded.Keys | Sort-Object)) {
    if (-not $Demands.ContainsKey($id)) { continue }
    $d = $Demands[$id]
    $rdue = Get-DemandDue $d $SlaFor $(if ($inheritDue.ContainsKey($id)) { $inheritDue[$id] } else { $null })
    $at = [DateTimeOffset]::MinValue
    if (($null -ne $rdue) -and [DateTimeOffset]::TryParse($responded[$id], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$at) -and ($at -gt $rdue)) {
      $lines += "- LATE response: $id first acknowledged $($at.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)), due $($rdue.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)) (a replacement never moves the response)"
    }
  }
  foreach ($id in @($Demands.Keys | Sort-Object)) { foreach ($rg in @($Demands[$id].Regressions)) { $lines += "- REVISION regression: $id $rg" } }
  foreach ($id in @($Demands.Keys | Sort-Object)) { foreach ($iv in @($Demands[$id].InvalidCopies)) { $lines += "- REVISION conflict: $id $iv" } }
  # Corrective actions (items 2 and 12).
  $corrective = @()
  $corrOverdue = @()
  $actionSources = @{}
  foreach ($k in $governing.Keys) { $actionSources[$k] = $governing[$k] }
  foreach ($k in $staleGoverning.Keys) { if (-not $actionSources.ContainsKey($k)) { $actionSources[$k] = $staleGoverning[$k] } }
  # A valid ack that no longer governs (superseded, or its run released
  # by a withdrawal) keeps its outstanding remediation until validated
  # closure (section 46 item 2); its own history still supplies dropped
  # covers, and a file now withdrawn keeps what its earlier versions owed.
  $superseded = @{}
  foreach ($k in @($validFiles.Keys)) {
    if ($actionSources.ContainsKey($k)) { continue }
    $actionSources[$k] = $validFiles[$k]
    $superseded[$k] = $true
  }
  # Each target's closure, keyed file|label, for duplicate linkage.
  $targetState = @{}
  $targetsByFile = @{}
  $pendingDup = @()
  foreach ($file in @($actionSources.Keys | Sort-Object)) {
    $f = $actionSources[$file].Fields
    $fileDisp = "$($actionSources[$file].Disposition)"
    $isStale = -not $governing.ContainsKey($file)
    $closedField = "$($f['closed'])"
    $allClosed = ($closedField -ne '') -and ($closedField -match '^[0-9a-f]{7,40}$') -and (Test-CommitExists $Root $closedField)
    # The top-level finding plus each cover line's finding is its own
    # remediation (section 31 R3-F2): a stamped top-level finding never
    # hides an unfinished per-incident one.
    $listedInc = @("$($f['incidents'])" -split '[,\s]+' | Where-Object { ($_ -ne '') -and ($_ -ne 'none') })
    $targets = @()
    if (($fileDisp -ne 'withdrawn') -and ("$($f['finding'])" -ne '')) { $targets += [pscustomobject]@{ Label = "$($f['finding'])"; Finding = "$($f['finding'])"; Disposition = $fileDisp; Evidence = "$($f['evidence'])"; Incidents = $listedInc } }
    foreach ($c in @($actionSources[$file].Covers)) {
      $cm = [regex]::Match("$c", $script:AckCoverRe)
      if ($cm.Success) { $targets += [pscustomobject]@{ Label = "$($cm.Groups[1].Value) $($cm.Groups[3].Value)"; Finding = $cm.Groups[3].Value; Disposition = $cm.Groups[2].Value; Evidence = $cm.Groups[4].Value; Incidents = @($cm.Groups[1].Value) } }
    }
    # Covers an earlier committed version named and this one dropped keep
    # their actions (R2-F2), with the due they were opened under.
    $relAck = (($AckDir.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/') + "/$file"
    $hist = Get-AckHistoricalTargets $Root $relAck
    foreach ($k in $hist.Keys) {
      # A label still current keeps every incident any version listed for
      # it (section 46 R2-C1), so narrowing A+B to A under the same fix
      # never drops B's verification.
      $cur = @($targets | Where-Object { $_.Label -eq $k })
      if ($cur.Count -gt 0) {
        foreach ($ct in $cur) { foreach ($hi in @($hist[$k].Incidents)) { if (("$hi" -ne '') -and (@($ct.Incidents) -notcontains $hi)) { $ct.Incidents = @(@($ct.Incidents) + @($hi)) } } }
        continue
      }
      $h = $hist[$k]
      $hInc = if (($null -ne $h.PSObject.Properties['Incidents']) -and (@($h.Incidents).Count -gt 0)) { @($h.Incidents) } elseif ($k -match '^(INC-[0-9a-f]{8}) ') { @($Matches[1]) } else { @() }
      $targets += [pscustomobject]@{ Label = "$k (dropped from the ack, opened $($h.Since.Substring(0, 10)))"; Finding = $h.Finding; Disposition = $h.Disposition; Evidence = $h.Evidence; Due = $h.Due; Incidents = $hInc }
    }
    $dueDate = [datetime]::MinValue
    $hasDue = [datetime]::TryParseExact("$($f['due'])", 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$dueDate)
    foreach ($tg in $targets) {
      $fnd = $tg.Finding
      # A dropped cover keeps the due it was opened under.
      $tgDue = $dueDate; $tgHasDue = $hasDue; $tgDueText = "$($f['due'])"
      if (($null -ne $tg.PSObject.Properties['Due']) -and ("$($tg.Due)" -ne '')) { $tgHasDue = [datetime]::TryParseExact("$($tg.Due)", 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$tgDue); $tgDueText = "$($tg.Due)" }
      $closedBy = ''
      $ev = "$($tg.Evidence)"
      # Disposition-specific transitions (section 39 item 2): fixed closes
      # on its existing commit, expected on its stamped proof section, and
      # duplicate on the acknowledgement of the run it repeats; only
      # remediation still owed stays open.
      $fixWait = ''
      if ($allClosed) { $closedBy = "closed: $closedField" }
      elseif ($tg.Disposition -eq 'duplicate') {
        # Decided once every other target's state is known (section 46
        # item 1): a duplicate closes only when the repeated run's own
        # actions for the matching incidents are closed.
        $pendingDup += [pscustomobject]@{ File = $file; Target = $tg; Of = $ev; DueOk = $tgHasDue; Due = $tgDue; DueText = $tgDueText; Owner = "$($f['corrective-owner'])"; Stale = $isStale }
        # Registered open now, so a chain A -> B -> C sees B's action
        # (section 46 R1-F2) until B's own resolution closes it.
        if (-not $targetsByFile.ContainsKey($file)) { $targetsByFile[$file] = @() }
        $targetsByFile[$file] += $tg
        $targetState["$file|$($tg.Label)"] = ''
        continue
      }
      elseif ($tg.Disposition -eq 'fixed') {
        foreach ($x in @($fnd, $ev)) {
          if (($closedBy -eq '') -and ($x -match '^[0-9a-f]{7,40}$') -and (Test-CommitExists $Root $x)) {
            # Verification evidence (section 46 item 9): a passing run of
            # the failing test after the fix commit.
            $vf = Test-FixVerified $Root $x @($tg.Incidents) $(if ($ledgerRead.Ok) { $ledgerRead.Incidents } else { $null })
            if ($vf.Ok) { $closedBy = "commit $x, verified by a later pass" } else { $fixWait = $vf.Why }
          }
        }
      }
      elseif ($tg.Disposition -eq 'expected') { foreach ($x in @($fnd, $ev)) { if (($closedBy -eq '') -and ($x -match '^D\d{2} T\d{2} \u00A7\d+$') -and (Test-SectionStamped $Root $x)) { $closedBy = "$x stamped" } } }
      elseif (($fnd -match '^[0-9a-f]{7,40}$') -and (Test-CommitExists $Root $fnd)) { $closedBy = "commit $fnd" }
      elseif (($fnd -match '^D\d{2} T\d{2} \u00A7\d+$') -and (Test-SectionStamped $Root $fnd)) { $closedBy = "$fnd stamped" }
      if (-not $targetsByFile.ContainsKey($file)) { $targetsByFile[$file] = @() }
      $targetsByFile[$file] += $tg
      $targetState["$file|$($tg.Label)"] = $closedBy
      if ($closedBy -ne '') { $corrective += "- CORRECTIVE $file ($($tg.Label)): closed ($closedBy)"; continue }
      $staleNote = if ($isStale) { '; its run was revised after signing, the action stays until closed' } else { '' }
      if ($superseded.ContainsKey($file)) { $staleNote += '; this ack no longer governs its run (superseded or withdrawn over), the action stays until closed' }
      if ($fixWait -ne '') { $staleNote += "; $fixWait" }
      if ($tgHasDue -and ($Today.Date -gt $tgDue.Date)) {
        if ($corrOverdue -notcontains $file) { $corrOverdue += $file }
        $corrective += "- CORRECTIVE $file ($($tg.Label)): OVERDUE since $($tgDueText): escalate $($f['corrective-owner'])$(if ($fnd -match '^INC-') { ' (an incident closes its investigation only on a closed: commit, never on recovery)' })$staleNote"
      } else {
        $corrective += "- CORRECTIVE $file ($($tg.Label)): open, due $tgDueText (owner $($f['corrective-owner'])$staleNote)"
      }
    }
  }
  # Duplicates link the surviving action (section 46 item 1): the target
  # names the repeated run's governing ack and its action for the matching
  # incidents, and closes only when those actions are closed. Chains
  # resolve to a fixpoint (R1-F2): a duplicate closes only once every
  # action it waits on, duplicates included, has closed; a chain that never
  # settles stays open.
  $survFor = {
    param($pd)
    $of = "$($pd.Of)"
    if (($of -eq '') -or (-not $acked.ContainsKey($of))) { return $null }
    # Every ack that claims the repeated run (section 46 R2-F1), not only
    # its governing one: a superseded ack's open action for the matching
    # incident is outstanding remediation too.
    $inc = @($pd.Target.Incidents)
    $out = @()
    foreach ($ff in @($validFiles.Keys)) {
      if (@($validFiles[$ff].Runs) -notcontains $of) { continue }
      foreach ($t in @($targetsByFile[$ff])) {
        if (($inc.Count -eq 0) -or (@($t.Incidents).Count -eq 0) -or (@($t.Incidents | Where-Object { $inc -contains $_ }).Count -gt 0)) { $out += [pscustomobject]@{ File = $ff; Target = $t } }
      }
    }
    return $out
  }
  $changed = $true
  $guard = 0
  while ($changed -and ($guard -lt 64)) {
    $changed = $false
    $guard++
    foreach ($pd in $pendingDup) {
      $key = "$($pd.File)|$($pd.Target.Label)"
      if ("$($targetState[$key])" -ne '') { continue }
      $surv = & $survFor $pd
      if ($null -eq $surv) { continue }
      if ((@($surv).Count -eq 0) -or (@($surv | Where-Object { "$($targetState["$($_.File)|$($_.Target.Label)"])" -eq '' }).Count -eq 0)) { $targetState[$key] = "duplicate of acknowledged $($pd.Of)"; $changed = $true }
    }
  }
  foreach ($pd in $pendingDup) {
    $tg = $pd.Target
    $of = "$($pd.Of)"
    $label = "- CORRECTIVE $($pd.File) ($($tg.Label))"
    if (($of -eq '') -or (-not $acked.ContainsKey($of))) {
      $late = $pd.DueOk -and ($Today.Date -gt $pd.Due.Date)
      if ($late -and ($corrOverdue -notcontains $pd.File)) { $corrOverdue += $pd.File }
      $whoOf = if ($of -ne '') { $of } else { 'an unnamed run' }
      $body = 'duplicate of ' + $whoOf + ", which is not acknowledged; it closes once that run's actions close"
      if ($pd.Stale) { $body += '; its run was revised after signing, the action stays until closed' }
      if ($late) { $corrective += ($label + ': OVERDUE since ' + $pd.DueText + ': ' + $body) } else { $corrective += ($label + ': open (' + $body + ')') }
      continue
    }
    $surv = @(& $survFor $pd)
    if ($surv.Count -eq 0) { $corrective += "$label`: closed (duplicate of acknowledged $of; no ack of it opened an action for these incidents)"; continue }
    $names = (@($surv | ForEach-Object { "$($_.File) ($($_.Target.Label))" }) -join ', ')
    if ("$($targetState["$($pd.File)|$($tg.Label)"])" -ne '') { $corrective += "$label`: closed (duplicate of acknowledged $of; its action $names closed)"; continue }
    $open = @($surv | Where-Object { "$($targetState["$($_.File)|$($_.Target.Label)"])" -eq '' })
    $openNames = (@($open | ForEach-Object { "$($_.File) ($($_.Target.Label))" }) -join ', ')
    $dupNote = ''
    if ($pd.Stale) { $dupNote += '; its run was revised after signing, the action stays until closed' }
    if ($superseded.ContainsKey($pd.File)) { $dupNote += '; this ack no longer governs its run (superseded or withdrawn over), the action stays until closed' }
    if ($pd.DueOk -and ($Today.Date -gt $pd.Due.Date)) {
      if ($corrOverdue -notcontains $pd.File) { $corrOverdue += $pd.File }
      $corrective += "$label`: OVERDUE since $($pd.DueText): duplicate of $of, open while its action $openNames is open: escalate $($pd.Owner)$dupNote"
    } else {
      $corrective += "$label`: open (duplicate of $of; open while its action $openNames is open; due $($pd.DueText), owner $($pd.Owner)$dupNote)"
    }
  }
  $lines += $corrective
  # Every demand's enforced deadline (section 46 R1-I1), for the status view.
  foreach ($id in @($Demands.Keys)) { $dues[$id] = Get-DemandDue $Demands[$id] $SlaFor $(if ($inheritDue.ContainsKey($id)) { $inheritDue[$id] } else { $null }) }
  $unacked = @()
  $proofUnacked = @()
  $overdue = @()
  foreach ($id in @($Demands.Keys | Sort-Object)) {
    if ($acked.ContainsKey($id)) { continue }
    $d = $Demands[$id]
    $isProof = ($d.Queue -eq 'proof')
    if ($isProof) { $proofUnacked += $id } else { $unacked += $id }
    $tag = if ($isProof) { ' (proof queue)' } else { '' }
    $what = if ($d.Unreadable) { "UNREADABLE result $($id.Substring(11)): $($d.Invalid)" } else { "RED $($d.Day)" }
    $due = Get-DemandDue $d $SlaFor $(if ($inheritDue.ContainsKey($id)) { $inheritDue[$id] } else { $null })
    $dues[$id] = $due
    if ($null -eq $due) { $lines += "- UNACKED$tag $id ($what; day unreadable: escalate operator)"; if (-not $isProof) { $overdue += $id }; continue }
    $dueText = $due.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($now -gt $due) {
      $late = [int][math]::Ceiling(($now - $due).TotalDays)
      if ($isProof) { $lines += "- UNACKED$tag $id ($what, due $dueText, past due; proof runs never escalate)"; continue }
      $overdue += $id
      $lines += "- OVERDUE ack: $id ($what, due $dueText, $late day(s) overdue): escalate operator"
      $staged += "- STAGED ack-overdue $id : $what unacknowledged $late day(s) past due; file it with tools/NightlyAck.ps1 -FileOverdue or write docs/nightly-acks/ack-<name>.md naming it (incidents: $(if ($d.Incidents.Count -gt 0) { $d.Incidents -join ', ' } else { 'none' }))"
    } else {
      $lines += "- UNACKED$tag $id ($what, due $dueText)"
    }
  }
  # The status view's inputs (section 46 item 13): the governing ack per
  # run and each demand's deadline.
  return [pscustomobject]@{ Ok = ($unacked.Count -eq 0); Unacked = $unacked; ProofUnacked = $proofUnacked; Lines = $lines; Staged = $staged; Overdue = $overdue; Corrective = $corrective; CorrectiveOverdue = $corrOverdue; Governing = $acked; Dues = $dues; Claims = $claims }
}

function Read-CorruptionRecord([string]$Path) {
  # The corruption record's entries (D00 T02 section 46 items 7 and 8);
  # missing or unreadable reads as none (the nightly reports an
  # unreadable record through Update-CorruptionRecord).
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  try { return @(@((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).entries) | Where-Object { $null -ne $_ }) } catch { return @() }
}

function Update-CorruptionRecord([string]$Path, [hashtable]$Demands, [string]$Today) {
  # The unreadable-result repair lifecycle (section 39 item 6): each
  # unreadable result file is recorded when first seen; once the same
  # file reads again, its entry names the restored run identity, and the
  # entry stays as the record of the corruption. Written atomically to
  # build/nightly/ack-corruption.json (ignored scratch). Returns report
  # lines.
  $rec = @{}
  if (Test-Path $Path) { try { foreach ($e in @((Get-Content $Path -Raw | ConvertFrom-Json).entries)) { if ($null -ne $e) { $rec["$($e.file)"] = $e } } } catch { return @("- ack corruption record unreadable ($Path); left untouched") } }
  $lines = @()
  $changed = $false
  foreach ($id in @($Demands.Keys | Sort-Object)) {
    $d = $Demands[$id]
    if ($d.Unreadable) {
      $name = $id.Substring(11)
      # The damaged bytes' checksum rides the entry (section 46 item 8), so
      # an ack can still name the demand after the file is deleted.
      if (-not $rec.ContainsKey($name)) { $rec[$name] = [pscustomobject]@{ file = $name; firstSeen = $Today; reason = "$($d.Invalid)"; restored = ''; restoredOn = ''; sha = "$($d.Current)" }; $changed = $true }
      continue
    }
    foreach ($p in @($d.Paths)) {
      $leaf = Split-Path -Leaf $p
      if ($rec.ContainsKey($leaf) -and ("$($rec[$leaf].restored)" -eq '')) { $rec[$leaf].restored = $id; $rec[$leaf].restoredOn = $Today; $changed = $true }
    }
  }
  foreach ($k in ($rec.Keys | Sort-Object)) {
    $e = $rec[$k]
    if ("$($e.restored)" -ne '') { $lines += "- CORRUPTION record: $k unreadable since $($e.firstSeen) ($($e.reason)), restored $($e.restoredOn) as $($e.restored); its demand moved to that identity" }
    else { $lines += "- CORRUPTION record: $k unreadable since $($e.firstSeen) ($($e.reason)); demanded as unreadable:$k until repaired" }
  }
  if ($changed) {
    $json = ConvertTo-Json ([pscustomobject]@{ version = 1; entries = @($rec.Keys | Sort-Object | ForEach-Object { $rec[$_] }) }) -Depth 4
    Write-AtomicReport @($json) $Path
  }
  return $lines
}

function Update-OverdueFindings([string[]]$Lines, $Overdue, [string]$Today, [string]$Owner = 'operator', [string[]]$Acked = $null, [string[]]$Pending = @()) {
  # The tracked home for overdue acknowledgements (section 31 item 1):
  # one table row per run in docs/nightly-acks/overdue-findings.md,
  # created once and updated (last overdue day, night count) on later
  # nights, so a staged stub becomes durable, deduped work. $Overdue
  # entries carry Id, What, and Incidents. Returns the new file lines
  # plus Changed.
  $header = @('# Overdue acknowledgements', '', 'Filed by `tools/NightlyAck.ps1 -FileOverdue` (D00 T02 section 31 item 1): one row per RED run whose acknowledgement passed its deadline. The row stays until the run is acknowledged (write `docs/nightly-acks/ack-<name>.md`), then the next filing marks it acked.', '', '| Run | What | Incidents | First overdue | Last overdue | Nights | Owner | State |', '| --- | --- | --- | --- | --- | --- | --- | --- |')
  $rows = [ordered]@{}
  foreach ($ln in @($Lines)) {
    $m = [regex]::Match("$ln", '^\|\s*(\S+)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(.*?)\s*\|\s*(\S+)\s*\|\s*$')
    if ($m.Success -and ($m.Groups[1].Value -ne 'Run') -and ($m.Groups[1].Value -ne '---')) { $rows[$m.Groups[1].Value] = [pscustomobject]@{ Id = $m.Groups[1].Value; What = $m.Groups[2].Value; Incidents = $m.Groups[3].Value; First = $m.Groups[4].Value; Last = $m.Groups[5].Value; Nights = [int]$m.Groups[6].Value; Owner = $m.Groups[7].Value; State = $m.Groups[8].Value } }
  }
  $changed = $false
  $over = @{}
  foreach ($o in @($Overdue)) { $over[$o.Id] = $o }
  foreach ($id in @($over.Keys | Sort-Object)) {
    $o = $over[$id]
    if (-not $rows.Contains($id)) { $rows[$id] = [pscustomobject]@{ Id = $id; What = $o.What; Incidents = $o.Incidents; First = $Today; Last = $Today; Nights = 1; Owner = $Owner; State = 'open' }; $changed = $true }
    elseif ($rows[$id].Last -ne $Today) { $rows[$id].Last = $Today; $rows[$id].Nights += 1; $rows[$id].State = 'open'; $changed = $true }
  }
  foreach ($id in @($rows.Keys)) {
    if ((-not $over.ContainsKey($id)) -and ($rows[$id].State -eq 'open')) {
      # Section 31 R3-C1: `acked` only for a run the gate acknowledged; a
      # run still demanded but not overdue stays open, and one no longer
      # demanded at all (its result gone, or moved to the proof queue)
      # reads `cleared`, never acknowledged.
      if ((@($Pending) -contains $id)) { continue }
      $rows[$id].State = if (($null -eq $Acked) -or (@($Acked) -contains $id)) { 'acked' } else { 'cleared' }
      $changed = $true
    }
  }
  $out = $header + @($rows.Values | ForEach-Object { "| $($_.Id) | $($_.What) | $($_.Incidents) | $($_.First) | $($_.Last) | $($_.Nights) | $($_.Owner) | $($_.State) |" })
  return [pscustomobject]@{ Lines = $out; Changed = $changed }
}
