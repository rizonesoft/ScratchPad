#Requires -Version 5.1
# tools/NightDebt.ps1 -- pure night-debt helpers for the §10 collector (D00 T02 §10).
# No top-level side effects: safe to dot-source from nightly.ps1 and scratch proofs.
# The query line grammar it parses is `query night-debt` output: file, id,
# section, `count N`, `filter F`, `age Nn`, `last-log L`. Filters containing
# ` count `, ` filter `, ` age `, or ` last-log ` with spaces around would
# misparse; real filters are Category values or operator expressions, never
# that shape, so the constraint is documented, not fenced.

function Get-NightDebtDocument {
  param([string]$Root, [string]$Python = 'py')
  # The whole `query night-debt --json` document (schema night-debt/1):
  # debts plus report_block, the exact block the queries print. Fails
  # LOUD on a failed query, non-JSON, or another schema.
  $raw = & $Python (Join-Path $Root 'scripts/todo-graph.py') query night-debt --json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "night-debt: query failed: $raw" }
  $doc = $null
  try { $doc = (@($raw) -join "`n") | ConvertFrom-Json } catch { throw "night-debt: query output is not JSON: $raw" }
  if ("$($doc.schema)" -ne 'night-debt/1') { throw "night-debt: unexpected schema '$($doc.schema)'" }
  return $doc
}

function Format-NightDebtStatus($Doc, [string]$Heading = 'Debt status at run start (`query night-debt`, verbatim):') {
  # The morning report's debt status block (D00 T02 §27 items 6 and 7):
  # the document's report_block verbatim, warnings included, under its
  # heading, so the report and the queries never disagree.
  $block = @($Doc.report_block | Where-Object { $null -ne $_ })
  if ($block.Count -eq 0) { return @() }
  return @($Heading, '') + $block + @('')
}

function Format-NightDebtPostRun($StartDoc, $EndDoc, [string[]]$Greens = @()) {
  # The post-run debt status (D00 T02 §35 item 9): the query re-run after
  # tonight's Night-collected and Night-red lines landed, verbatim, plus one
  # line per debt open at run start that the post-run query no longer lists,
  # so a debt collected green tonight reads collected and never carries the
  # run-start escalation into the morning.
  # A missing or foreign post-run document is a failed re-run, never an
  # empty one (D00 T02 section 50 item 10): reading it as empty would call
  # every run-start debt collected tonight.
  if (($null -eq $EndDoc) -or ("$($EndDoc.schema)" -ne 'night-debt/1')) { throw 'night-debt: the post-run query returned no night-debt/1 document' }
  $endIds = @{}
  foreach ($d in @($EndDoc.debts)) { if ($null -ne $d) { $endIds["$($d.id)"] = $true } }
  $closed = @()
  foreach ($d in @($StartDoc.debts)) {
    if (($null -ne $d) -and -not $endIds.ContainsKey("$($d.id)")) { $closed += "    $($d.id) state collected tonight (was $($d.state))" }
  }
  # A debt collected green tonight that the re-run query still lists open
  # has an unrecorded closure (D00 T02 §42 item 7).
  foreach ($g in @($Greens)) {
    if ($endIds.ContainsKey("$g")) { $closed += "    $g state collected-unrecorded (green tonight; the query still reads it open, closure unrecorded)" }
  }
  $block = @($EndDoc.report_block | Where-Object { $null -ne $_ }) + $closed
  if ($block.Count -eq 0) { return @() }
  return @('Debt status after the run (`query night-debt` re-run, verbatim, plus debts closed tonight):', '') + $block + @('')
}

function Get-OpenNightDebts {
  param([string]$Root, [string]$Python = 'py', $Doc = $null)
  # One object per open debt from `query night-debt --json` (schema
  # night-debt/1, D00 T02 §27): File, Id, Section, Count, Filter, Age,
  # Due, Owner, State, Overdue, LastLog, plus Line, the exact text the
  # queries print, which the morning report quotes verbatim. JSON
  # replaced the text scrape after §19's due field broke it (the scrape
  # matched no line and the collector ran blind). A failed query or an
  # unexpected schema fails LOUD: the collector never runs blind.
  $doc = if ($null -ne $Doc) { $Doc } else { Get-NightDebtDocument $Root $Python }
  $debts = @()
  foreach ($d in @($doc.debts)) {
    if ($null -eq $d) { continue }
    $debts += [pscustomobject]@{
      File = "$($d.file)"; Id = "$($d.id)"; Section = "$($d.section)"; Count = "$($d.count)"; Filter = "$($d.filter)"
      Age = $(if ($null -eq $d.age) { '?n' } else { "$($d.age)n" }); Due = "$($d.due)"; Owner = "$($d.owner)"; State = "$($d.state)"
      Overdue = [bool]$d.overdue; LastLog = $(if ($null -eq $d.last_log) { 'none' } else { "$($d.last_log)" }); Line = "$($d.line)"
      # The owed tests' digest (D00 T02 §42 item 6), '' when the owed line
      # names none.
      Digest = $(if ($null -eq $d.digest) { '' } else { "$($d.digest)" })
    }
  }
  return $debts
}

function Get-DebtDotnetFilter([string]$Filter) {
  # Bare Category value -> Category=<value>; anything shaped like a
  # --filter expression (operator chars) passes through untouched.
  if ([string]::IsNullOrWhiteSpace($Filter)) { throw 'night-debt: empty filter resolves to nothing' }
  if ($Filter -match '[=|&!~()]') { return $Filter }
  return "Category=$Filter"
}

function Format-CollectedLine([string]$Date, [string]$Id, [int]$Passed, [int]$Failed, [int]$Skipped, [string]$Log, [string]$Digest = '', [string]$Candidate = '', [string]$Run = '', [string]$At = '', [string]$Event = '') {
  # The executed tests' digest rides the line (D00 T02 §42 item 6), so the
  # graph can bind the closure to the owed test identities; the candidate
  # HEAD, run identity, effective time, and event identity ride it too
  # (§50 items 1, 4), each only when known.
  $parts = ''
  foreach ($kv in @(@('digest', $Digest), @('candidate', $Candidate), @('run', $Run), @('at', $At), @('event', $Event))) { if ("$($kv[1])" -ne '') { $parts += "; $($kv[0]) $($kv[1])" } }
  return "**Night-collected:** $Date $Id ($Passed passed, $Failed failed, $Skipped skipped; log $Log$parts)"
}

function Get-TestNamesDigest([string[]]$Names) {
  # The test-identity digest (D00 T02 §42 item 6): the first 16 hex of
  # SHA-256 over the distinct names, ordinal-sorted, newline-joined, so an
  # equally sized but different set never shares it.
  $set = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($n in @($Names)) { if ("$n" -ne '') { $null = $set.Add("$n") } }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes((@($set) -join "`n")))) -replace '-', '').Substring(0, 16).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Test-DebtIdentity([string]$OwedDigest, [string[]]$ExecutedNames) {
  # Closure binds to the owed tests (§42 item 6): with an owed digest,
  # the executed names must hash to it. Returns Ok plus the digest.
  $dg = Get-TestNamesDigest $ExecutedNames
  return [pscustomobject]@{ Ok = (($OwedDigest -eq '') -or ($OwedDigest -eq $dg)); Digest = $dg }
}

function Format-RedLine([string]$Date, [string]$Id, [int]$Passed, [int]$Failed, [int]$Skipped, [string]$Log, [string]$Run = '', [string]$At = '', [string]$Event = '') {
  # A red collection's record (D00 T02 §27 item 3): the first resets the
  # due window once, a second escalates the debt as red-repeat. The run
  # identity (D00 T02 §35 item 3) makes two red runs on one day two
  # attempts.
  $runPart = if ([string]::IsNullOrWhiteSpace($Run)) { '' } else { "; run $Run" }
  if ("$At" -ne '') { $runPart += "; at $At" }
  if ("$Event" -ne '') { $runPart += "; event $Event" }
  return "**Night-red:** $Date $Id ($Passed passed, $Failed failed, $Skipped skipped; log $Log$runPart)"
}

function Format-RedTriageNote([string]$Owner, [string]$Day) {
  # The red entry's remediation linkage (D00 T02 §35 R1-F4): who owns the
  # repair and the next action, which ends with the finding reference
  # recorded on tonight's Night-red line, so the red-repeat line quotes it.
  $who = if ([string]::IsNullOrWhiteSpace($Owner)) { 'operator' } else { $Owner }
  return "owner $who; next: file the staged finding, then append ``; finding <ref>`` to the $Day Night-red line"
}

function Add-RedLine([string]$TodoPath, [string]$DebtId, [string]$Date, [string]$Line) {
  # Appends a Night-red line after the id's owed line (and any lines
  # already following it for the id), once per id and run identity (once
  # per id and date for a line with no run, D00 T02 §35 item 3), atomic
  # with readback. Triage commits it like a Night-collected line.
  $text = Get-Content $TodoPath -Raw -Encoding UTF8
  $runM = [regex]::Match($Line, '; run (\S+?)\)$')
  $dupPattern = '\*\*Night-red:\*\*\s+' + [regex]::Escape($Date) + '\s+' + [regex]::Escape($DebtId) + '\b'
  # The run chunk may be followed by triage's `; finding <ref>` (§35 R2-F2).
  if ($runM.Success) { $dupPattern += '[^\n]*; run ' + [regex]::Escape($runM.Groups[1].Value) + '[;)]' }
  if ($text -match $dupPattern) { return "skip: $DebtId already carries a red line for $Date$(if ($runM.Success) { " run $($runM.Groups[1].Value)" })" }
  $lines = @($text -split "`r?`n")
  $idx = Find-OwedLineIndex $lines $DebtId
  if ($idx -lt 0) { return "skip: no Night-owed line for $DebtId" }
  $at = $idx
  while ((($at + 1) -lt $lines.Count) -and ($lines[$at + 1] -match ('\*\*Night-(red|collected|ack|accepted|owner|extend|revoked):\*\*\s+(\S+\s+)?' + [regex]::Escape($DebtId) + '\b'))) { $at++ }
  $new = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $lines.Count; $i++) { $new.Add($lines[$i]); if ($i -eq $at) { $new.Add($Line) } }
  $tmp = "$TodoPath.tmp"
  [System.IO.File]::WriteAllText($tmp, ($new -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -Path $tmp -Destination $TodoPath -Force
  $back = Get-Content $TodoPath -Raw -Encoding UTF8
  $n = ([regex]::Matches($back, [regex]::Escape($Line))).Count
  if ($n -ne 1) { return "FAULT: $DebtId red line reads back $n times" }
  return "appended red line"
}

function Invoke-CollectedLine([string]$TodoPath, [string]$DebtId, [string]$Line) {
  # The collector's write (D00 T02 §42 R1-F4): any failure of the append,
  # the replacement, or the readback becomes a `write failed` note, so the
  # green entry reads collected-unrecorded and the run reds instead of
  # the collector stopping.
  try { return (Add-CollectedLine $TodoPath $DebtId $Line) }
  catch { return "write failed: $($_.Exception.Message)" }
}

function Get-TrxCensusNames([string]$TrxPath) {
  # Every test row the collection's census counts (D00 T02 §42 R3-F1):
  # passed, failed, and skipped. At the identity check the census has
  # already refused capability and other skips, so the skips left are
  # quarantine-declared and belong to the owed set, as they do in the
  # digest Get-DebtDigest.ps1 prints. Missing or unreadable trx reads
  # as none.
  if (-not (Test-Path $TrxPath)) { return @() }
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return @() }
  return @(@($t.TestRun.Results.UnitTestResult) | Where-Object { $null -ne $_ } | ForEach-Object { "$($_.testName)" })
}

function Get-ListedTestNames([string[]]$Output) {
  # Test names from `dotnet test --list-tests` output: the indented lines
  # after "The following Tests are available:".
  $names = @()
  $on = $false
  foreach ($l in @($Output)) {
    if ("$l" -match 'The following Tests are available:') { $on = $true; continue }
    if ($on -and ("$l" -match '^\s{4}(\S.*)$')) { $names += $Matches[1].Trim() }
  }
  return $names
}

function Find-OwedLineIndex([string[]]$Lines, [string]$DebtId) {
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match ('\*\*Night-owed:\*\*\s+' + [regex]::Escape($DebtId) + '\b')) { return $i }
  }
  return -1
}

function Add-CollectedLine([string]$TodoPath, [string]$DebtId, [string]$Line, [scriptblock]$Fault = $null) {
  # Atomic append after the Night-owed line naming this id, with
  # readback verifying exactly one copy. An existing collected line
  # for the id, or a missing owed line: skip with a report line --
  # never duplicate, never drop silently. The write re-reads before
  # replacing (R1-F2): a concurrent edit retries once from current
  # content, then skips loud for triage to append. Residual (R2-F2):
  # a microsecond check-act window no user-space scheme closes
  # (repo precedent: plan --sync); single-writer plus the run mutex
  # bound it, and the readback still guards the copy count.
  # Distinct outcomes with idempotent reconciliation (D00 T02 section 50
  # item 8): `appended` (written and read back once), `reconciled` (this
  # exact line is already on disk: an earlier write landed, so nothing is
  # written again), `failed` (the replace did not land; the line is
  # absent), and `unknown` (the replace ran but the readback could not
  # confirm it; the caller treats the line as possibly written and the
  # next run reconciles it). $Fault is a test seam called with the stage
  # name ('move' or 'readback').
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    $text = Get-Content $TodoPath -Raw -Encoding UTF8
    if (([regex]::Matches($text, [regex]::Escape($Line))).Count -ge 1) { return "reconciled: $DebtId has this exact collected line on disk (an earlier write landed); nothing written" }
    # An existing record blocks a new one unless the new one carries a
    # digest no existing record for the id carries (D00 T02 §42 R1-F5):
    # a record the graph rejects for the wrong tests never blocks the
    # valid evidence a later green run brings.
    $existing = @([regex]::Matches($text, '\*\*Night-collected:\*\*\s+\S+\s+' + [regex]::Escape($DebtId) + '\b[^\r\n]*') | ForEach-Object { $_.Value })
    $newDigest = [regex]::Match($Line, '\bdigest\s+([0-9a-f]+)')
    if ($existing.Count -gt 0) {
      # A same-digest record blocks only when it also names this line's
      # candidate (D00 T02 section 50 R1-A2): a record the graph rejected for
      # an older candidate never blocks the valid collection that follows.
      $newCand = [regex]::Match($Line, '\bcandidate\s+([0-9a-f]+)')
      $recorded = $newDigest.Success -and (@($existing | Where-Object { ($_ -match ('\bdigest\s+' + $newDigest.Groups[1].Value + '\b')) -and ((-not $newCand.Success) -or ($_ -match ('\bcandidate\s+' + $newCand.Groups[1].Value + '\b'))) }).Count -gt 0)
      if ((-not $newDigest.Success) -or $recorded) { return "skip: $DebtId already carries a collected line" }
    }
    $lines = @($text -split "`r?`n")
    $idx = Find-OwedLineIndex $lines $DebtId
    if ($idx -lt 0) { return "skip: no Night-owed line for $DebtId" }
    $new = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $idx; $i++) { $new.Add($lines[$i]) }
    $new.Add($Line)
    for ($i = $idx + 1; $i -lt $lines.Count; $i++) { $new.Add($lines[$i]) }
    $now = Get-Content $TodoPath -Raw -Encoding UTF8
    if ($now -ceq $text) {
      $tmp = "$TodoPath.tmp-$PID"
      $nl = "`n"
      if ($text.Contains("`r`n")) { $nl = "`r`n" }
      $new -join $nl | Set-Content -Path $tmp -Encoding UTF8 -NoNewline
      try {
        if ($null -ne $Fault) { & $Fault 'move' }
        Move-Item -Path $tmp -Destination $TodoPath -Force
      } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return "failed: $DebtId not written ($($_.Exception.Message)); the line is absent"
      }
      $back = $null
      for ($r = 0; ($r -lt 2) -and ($null -eq $back); $r++) {
        try { if ($null -ne $Fault) { & $Fault 'readback' }; $back = [System.IO.File]::ReadAllText($TodoPath) } catch { $back = $null }
      }
      if ($null -eq $back) { return "unknown: $DebtId written but the readback failed twice; the line may be on disk and the next run reconciles it" }
      $hits = ([regex]::Matches($back, [regex]::Escape($Line))).Count
      if ($hits -ne 1) { throw "night-debt: readback found $hits copies, want exactly 1" }
      return "appended: $DebtId"
    }
  }
  return "skip: file changed under write, triage appends"
}

function Test-DebtCoverage([string]$DebtFilter, [string]$CollectFilter, [string]$CollectId) {
  # exact: this run's filter is the debt's own (closeable with the
  # leg's counts). superset (R1-F4): an un-narrowed full-Interactive
  # run covering an Interactive-scoped &-only debt. uncovered:
  # anything else. `|`/`!` filters are exact-only, and the
  # Interactive clause matches per &-clause, never substring (R2-F5):
  # `FullyQualifiedName~Category=Interactive` is not a subset.
  if (($DebtFilter -ne '') -and ($DebtFilter -eq $CollectFilter)) { return 'exact' }
  if (($CollectId -eq '') -and ($CollectFilter -eq 'Category=Interactive') -and ($DebtFilter -ne '') -and ($DebtFilter -notmatch '[|!]')) {
    foreach ($cl in @($DebtFilter -split '&')) {
      $t = $cl.Trim().Trim('(', ')', ' ', "`t").Trim()
      if ($t -match '^(?i)Category\s*=\s*Interactive$') { return 'superset' }
    }
  }
  return 'uncovered'
}

function Format-UnrecordedGreens([string[]]$Greens, [string]$Why) {
  # The post-run block when the re-run query itself failed (§42 item 7):
  # every debt collected green tonight reads collected-unrecorded.
  $out = @("Debt status after the run: query failed: $Why", '')
  foreach ($g in @($Greens)) { $out += "    $g state collected-unrecorded (green tonight; the re-run query failed, closure unrecorded)" }
  return $out + @('')
}

function Get-TrxSubsetCounts([string]$TrxPath, [string]$DebtFilter) {
  # Subset counts for a superset run (R2-F4): AND-only
  # FullyQualifiedName/Name constraints matched against trx test
  # names. Returns $null when the filter is not FQN-attributable
  # (Category-only refinements, `|`, `!`, parens) or the trx is
  # unreadable -- the caller stages those for triage. Sound within
  # a superset run's trx: every row already matched
  # Category=Interactive, so FQN constraints alone pick the subset.
  # `=` compares against the full name and, for Name=, the last
  # dotted segment (vstest Name is the method name).
  if ($DebtFilter -match '[|!()]') { return $null }
  $clauses = @($DebtFilter -split '&' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $constraints = @()
  foreach ($c in $clauses) {
    if ($c -match '^(?i)Category\s*=\s*Interactive$') { continue }
    $m = [regex]::Match($c, '^(?i)(FullyQualifiedName|Name)\s*(~|=)\s*(.+)$')
    if (-not $m.Success) { return $null }
    $constraints += @{ Field = $m.Groups[1].Value; Op = $m.Groups[2].Value; Value = $m.Groups[3].Value.Trim() }
  }
  if ($constraints.Count -eq 0) { return $null }
  try { [xml]$x = Get-Content $TrxPath -Raw } catch { return $null }
  $rows = @(Select-Xml -Xml $x -XPath '//*[local-name()="UnitTestResult"]' | ForEach-Object { $_.Node })
  $p = 0; $f = 0; $s = 0
  $names = @()
  foreach ($r in $rows) {
    $name = "$($r.testName)"
    $hit = $true
    foreach ($k in $constraints) {
      if ($k.Op -eq '~') {
        if ($name -notlike ('*' + $k.Value + '*')) { $hit = $false; break }
      } elseif ($k.Field -match '^(?i)Name$') {
        $last = ($name -split '\.')[-1]
        if (($name -cne $k.Value) -and ($last -cne $k.Value)) { $hit = $false; break }
      } else {
        if ($name -cne $k.Value) { $hit = $false; break }
      }
    }
    if (-not $hit) { continue }
    switch ("$($r.outcome)") {
      'Passed' { $p++; $names += $name }
      'Failed' { $f++; $names += $name }
      default { $s++ }
    }
  }
  return @{ Passed = $p; Failed = $f; Skipped = $s; Names = $names }
}

function Format-DebtGreenEntry([string]$Id, [string]$Section, [int]$P, [int]$F, [int]$S, [string]$LogRel, [string]$Note) {
  # Green-leg entry honors the close-loop outcome (R2-F2): only an
  # `appended` note claims collected; an already-closed debt says
  # so; any other skip reds for triage. Returns @(entry, red).
  $counts = "$P/$F/$S"
  if ($Note -like 'appended*') {
    return @("- $Id ($Section): collected $P passed, $F failed, $S skipped; log $LogRel", $false)
  }
  if ($Note -like '*already carries*') {
    return @("- $Id ($Section): collection green ($counts); already closed (Night-collected present)", $false)
  }
  # A write that landed earlier reconciles to collected once (D00 T02
  # section 50 item 8); an unknown outcome is its own line and reds so
  # triage looks, while the next run reconciles it.
  if ($Note -like 'reconciled*') {
    return @("- $Id ($Section): collected $P passed, $F failed, $S skipped; log $LogRel (reconciled: the line had landed)", $false)
  }
  if ($Note -like 'unknown*') {
    return @("- $Id ($Section): collection green ($counts); Night-collected write outcome unknown ($Note)", $true)
  }
  # A green collection whose Night-collected write failed is closed in
  # fact and unrecorded on disk (D00 T02 §42 item 7): the run reds.
  return @("- $Id ($Section): collected-unrecorded: collection green ($counts) but the Night-collected write failed ($Note); closure unrecorded", $true)
}

function Split-DebtSkips([string[]]$SkipLines) {
  # Closure-safe split (plan PR4): quarantine-declared skips
  # transfer their proof to the quarantine window and may close
  # with the collection; capability and other skips never executed,
  # so they hold the debt open. Returns
  # @{Quarantine; Capability; Other}.
  $q = 0; $c = 0; $o = 0
  foreach ($ln in $SkipLines) {
    if ($ln -match 'QUARANTINED') { $q++ }
    elseif ($ln -match 'unavailable on this host') { $c++ }
    else { $o++ }
  }
  return @{ Quarantine = $q; Capability = $c; Other = $o }
}

function Test-SubsetClose($Sub, [string]$OwedCount) {
  # Subset close decision (plan PR4): close only fully executed
  # with matching census (trx skips carry no reason, so any skip
  # stages); red, mismatch, and unattributable route triage-side.
  # $Sub is $null when the filter is not FQN-attributable or the
  # trx is unreadable.
  if ($null -eq $Sub) { return 'unattributable' }
  if ($Sub.Failed -gt 0) { return 'red' }
  if ($Sub.Skipped -gt 0) { return 'skipped-stage' }
  $total = $Sub.Passed + $Sub.Failed + $Sub.Skipped
  if (($total -le 0) -or (-not (Test-DebtCensus $OwedCount $Sub.Passed $Sub.Failed $Sub.Skipped))) { return 'mismatch' }
  return 'close'
}

function Test-DebtCensus([string]$OwedCount, [int]$Passed, [int]$Failed, [int]$Skipped) {
  # Collected totals must equal the owed count (R1-F5); anything
  # else (drift, partial run, unparseable count) fails closed.
  $n = 0
  return ([int]::TryParse($OwedCount, [ref]$n) -and (($Passed + $Failed + $Skipped) -eq $n))
}

function Format-FindingStubs([string[]]$FailedLines, [string]$Root) {
  # Finding stubs for the report Filings: test name, first message
  # line, test-file hint. Safety or data-integrity shaped failures
  # carry REOPEN-CANDIDATE for the agent (triage reopens through
  # audit stance); the marker is a triage hint, never a decision.
  $stubs = @()
  foreach ($fl in $FailedLines) {
    $m = [regex]::Match($fl, '^\s*-\s*([^:]+):\s*(.*)$')
    if (-not $m.Success) { continue }
    $name = $m.Groups[1].Value.Trim()
    $msg = $m.Groups[2].Value.Trim()
    if ($msg.Length -gt 160) { $msg = $msg.Substring(0, 160) }
    $hint = 'unknown'
    $parts = $name -split '\.'
    if ($parts.Count -ge 3) {
      $cand = Join-Path $Root (Join-Path 'tests' (Join-Path $parts[0] ($parts[1] + '.cs')))
      if (Test-Path $cand) { $hint = 'tests/' + $parts[0] + '/' + $parts[1] + '.cs' }
    }
    $stub = "  - $name`: $msg [test $hint]"
    if ($msg -match '(?i)\bdata loss\b|\bdata corrupt|\bcorrupt\b|integrity|\bdisk\b|unauthorized|access denied|\bIO error\b') {
      $stub += ' [REOPEN-CANDIDATE: safety/data-integrity, agent reopens through audit stance]'
    }
    $stubs += $stub
  }
  return $stubs
}
