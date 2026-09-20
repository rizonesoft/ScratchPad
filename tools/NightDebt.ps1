#Requires -Version 5.1
# tools/NightDebt.ps1 -- pure night-debt helpers for the §10 collector (D00 T02 §10).
# No top-level side effects: safe to dot-source from nightly.ps1 and scratch proofs.
# The query line grammar it parses is `query night-debt` output: file, id,
# section, `count N`, `filter F`, `age Nn`, `last-log L`. Filters containing
# ` count `, ` filter `, ` age `, or ` last-log ` with spaces around would
# misparse; real filters are Category values or operator expressions, never
# that shape, so the constraint is documented, not fenced.

function Get-OpenNightDebts {
  param([string]$Root, [string]$Python = 'py')
  # One object per open debt: File, Id, Section, Count, Filter, Age,
  # LastLog. A failed query fails LOUD: the collector never runs blind.
  $raw = & $Python (Join-Path $Root 'scripts/todo-graph.py') query night-debt 2>&1
  if ($LASTEXITCODE -ne 0) { throw "night-debt: query failed: $raw" }
  $debts = @()
  foreach ($ln in ($raw -split "`r?`n")) {
    $m = [regex]::Match(
      $ln,
      '^\s*(?<file>\S+)\s+(?<id>\S+)\s+(?<section>.+?)\s+count\s+(?<count>\S+)\s+filter\s+(?<filter>.+?)\s+age\s+(?<age>\S+)\s+last-log\s+(?<lastlog>\S+)\s*$'
    )
    if (-not $m.Success) { continue }
    $debts += [pscustomobject]@{
      File = $m.Groups['file'].Value
      Id = $m.Groups['id'].Value
      Section = $m.Groups['section'].Value
      Count = $m.Groups['count'].Value
      Filter = $m.Groups['filter'].Value
      Age = $m.Groups['age'].Value
      LastLog = $m.Groups['lastlog'].Value
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

function Format-CollectedLine([string]$Date, [string]$Id, [int]$Passed, [int]$Failed, [int]$Skipped, [string]$Log) {
  return "**Night-collected:** $Date $Id ($Passed passed, $Failed failed, $Skipped skipped; log $Log)"
}

function Find-OwedLineIndex([string[]]$Lines, [string]$DebtId) {
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match ('\*\*Night-owed:\*\*\s+' + [regex]::Escape($DebtId) + '\b')) { return $i }
  }
  return -1
}

function Add-CollectedLine([string]$TodoPath, [string]$DebtId, [string]$Line) {
  # Atomic append after the Night-owed line naming this id, with
  # readback verifying exactly one copy. An existing collected line
  # for the id, or a missing owed line: skip with a report line --
  # never duplicate, never drop silently. The write re-reads before
  # replacing (R1 A2): a concurrent edit retries once from current
  # content, then skips loud for triage to append.
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    $text = Get-Content $TodoPath -Raw -Encoding UTF8
    if ($text -match ('\*\*Night-collected:\*\*\s+\S+\s+' + [regex]::Escape($DebtId) + '\b')) {
      return "skip: $DebtId already carries a collected line"
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
      Move-Item -Path $tmp -Destination $TodoPath -Force
      $back = Get-Content $TodoPath -Raw -Encoding UTF8
      $hits = ([regex]::Matches($back, [regex]::Escape($Line))).Count
      if ($hits -ne 1) { throw "night-debt: readback found $hits copies, want exactly 1" }
      return "appended: $DebtId"
    }
  }
  return "skip: file changed under write, triage appends"
}

function Test-DebtCoverage([string]$DebtFilter, [string]$CollectFilter, [string]$CollectId) {
  # exact: this run's filter is the debt's own (closeable with the
  # leg's counts). superset (R1 I2): an un-narrowed full-Interactive
  # run covering an Interactive-scoped &-only debt -- the leg's
  # totals are superset counts, so triage closes with subset counts.
  # uncovered: anything else. `|`/`!` filters are exact-only:
  # subsumption is undecidable for strings.
  if (($DebtFilter -ne '') -and ($DebtFilter -eq $CollectFilter)) { return 'exact' }
  if (($CollectId -eq '') -and ($CollectFilter -eq 'Category=Interactive') -and ($DebtFilter -ne '') -and ($DebtFilter -match '(?i)^Interactive$|Category\s*=\s*Interactive') -and ($DebtFilter -notmatch '[|!]')) { return 'superset' }
  return 'uncovered'
}

function Test-DebtCensus([string]$OwedCount, [int]$Passed, [int]$Failed, [int]$Skipped) {
  # Collected totals must equal the owed count (R1 I3); anything
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
