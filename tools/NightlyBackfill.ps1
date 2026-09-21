<# Backfills versioned result files for retained runs that predate the
emitter (D00 T02 §17 item 6): a one-time migration INTO the
machine-readable format, so notification, trend, retention, and
recovery stop parsing prose. Every derived field is mechanical
(transcript lines, trx summaries, gate verdicts, report rows);
anything unrecoverable reads unknown with a note, never a guess.
#>
param(
  [string]$RunDir = '',
  [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
if ($RunDir -eq '') { Write-Output 'backfill: -RunDir required'; exit 2 }

$reportFile = @(Get-ChildItem $RunDir -Filter 'morning-2*.md' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*-core.md' } | Select-Object -First 1)
if ($reportFile.Count -eq 0) { Write-Output "backfill: no morning report in $RunDir"; exit 2 }
# Raw strings only: Read-RawLines strips the PSPath/PSDrive/PSProvider/
# ReadCount decoration Get-Content hangs on every line (unstripped file
# lines into ConvertTo-Json expand the provider graph to the depth
# limit and never return). Never feed file lines to JSON raw.
$rep = @(Read-RawLines $reportFile[0].FullName)
$repText = $rep -join "`n"

function Find-ReportLine($lines, $prefix) {
  $hit = @($lines | Where-Object { $_ -like "$prefix*" } | Select-Object -First 1)
  if ($hit.Count -eq 0) { return '' }
  return $hit[0]
}

# Identity: the report's run-identity line, else the stamp with a
# pid0 marker (pids went unrecorded pre-§16).
$stamp = ''
$day = ''
$idLine = Find-ReportLine $rep '- Run identity:'
if ($idLine -match '^- Run identity: (\d{4}-\d{2}-\d{2}-\d{6})-pid(\d+)') { $stamp = $Matches[1] }
if ($stamp -eq '') {
  $defLog = @(Get-ChildItem $RunDir -Filter '*-default.log' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($defLog.Count -gt 0) {
    $st = Select-String -Path $defLog[0].FullName -Pattern '^Start time: (\d{14})' | Select-Object -First 1
    if ($null -ne $st) { $s = $st.Matches[0].Groups[1].Value; $stamp = $s.Substring(0, 4) + '-' + $s.Substring(4, 2) + '-' + $s.Substring(6, 2) + '-' + $s.Substring(8, 6) }
  }
}
if ($stamp -eq '') { Write-Output "backfill: no stamp derivable in $RunDir"; exit 2 }
$day = $stamp.Substring(0, 10)
$identity = "$stamp-pid0"
if ($idLine -match '^- Run identity: (\S+)') { $identity = $Matches[1] }

# Trigger plus launch: mechanical map from the trigger line and the
# stamp time against the 02:30 daily fire.
$triggerLine = Find-ReportLine $rep '- Trigger:'
$trigger = 'unknown (no trigger line)'
if ($triggerLine -match '^- Trigger: (.*)$') { $trigger = $Matches[1] }
$launch = 'unknown'
if ($trigger -like '*cron *') { $launch = 'timer' }
elseif (($trigger -like 'manual (parent taskeng.exe)*') -or ($trigger -like 'manual (parent svchost.exe)*')) { $launch = 'demand' }
elseif ($trigger -like 'manual*') { $launch = 'manual' }
elseif ($trigger -like 'task \ScratchPad*') {
  $tod = $stamp.Substring(11, 2) + ':' + $stamp.Substring(13, 2)
  $diffMin = [math]::Abs(((([int]$tod.Substring(0, 2)) * 60) + ([int]$tod.Substring(3, 2))) - 150)
  if ($diffMin -gt 720) { $diffMin = 1440 - $diffMin }
  $launch = if ($diffMin -le 5) { 'timer' } else { 'demand' }
}
$commit = 'unknown (no HEAD line)'
$headLine = Find-ReportLine $rep '- HEAD:'
if ($headLine -match '^- HEAD: (\S+)') { $commit = $Matches[1] }

# Legs: report rows carry full counts (the shared run-a.trx keeps
# the final project only, so trx undercounts Run A pre-§15).
function Read-LegRow($lines, $name) {
  # Legacy gate cells (§9-era: `exit  changes logged; ...`) carry no
  # numeric code, so the third alternative matches them with gate $null
  # (unrecoverable, never guessed); current rows match the first two.
  $pat = '^\| ' + [regex]::Escape($name) + ' \| (\d+) passed, (\d+) failed, (\d+) skipped.*\| (exit (\d+|null)|n/a|exit\s[^|]*)[^|]*\|'
  $hit = @($lines | Where-Object { $_ -match $pat } | Select-Object -First 1)
  if ($hit.Count -eq 0) { return $null }
  $m = [regex]::Match($hit[0], $pat)
  $gate = $null
  if ($m.Groups[5].Value -match '^\d+$') { $gate = [int]$m.Groups[5].Value }
  return [pscustomobject]@{ passed = [int]$m.Groups[1].Value; failed = [int]$m.Groups[2].Value; skipped = [int]$m.Groups[3].Value; gate = $gate }
}
$rowA = Read-LegRow $rep 'Run A (default)'
$rowB = Read-LegRow $rep 'Run B (primary)'
$rowI = Read-LegRow $rep 'Interactive (collection)'
function Read-TestSeconds($runDir, $leg) {
  $log = @(Get-ChildItem $runDir -Filter "*-$leg.log" -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($log.Count -eq 0) { return $null }
  $hit = Select-String -Path $log[0].FullName -Pattern 'test-seconds: (\d+)' | Select-Object -First 1
  if ($null -eq $hit) { return $null }
  return [int]$hit.Matches[0].Groups[1].Value
}
function Read-TranscriptWall($runDir, $leg) {
  $log = @(Get-ChildItem $runDir -Filter "*-$leg.log" -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($log.Count -eq 0) { return $null }
  $s = Select-String -Path $log[0].FullName -Pattern '^Start time: (\d{14})' | Select-Object -First 1
  $e = Select-String -Path $log[0].FullName -Pattern '^End time: (\d{14})' | Select-Object -First 1
  if (($null -eq $s) -or ($null -eq $e)) { return $null }
  try {
    $a = [datetime]::ParseExact($s.Matches[0].Groups[1].Value, 'yyyyMMddHHmmss', $null)
    $b = [datetime]::ParseExact($e.Matches[0].Groups[1].Value, 'yyyyMMddHHmmss', $null)
    return [int](($b - $a).TotalSeconds)
  } catch { return $null }
}
function New-BackLeg($row, $seconds, $started) {
  # A leg with no row but a transcript started yet proved nothing (the
  # fl5f1 shape): ran reads true with zero counts plus a note, never
  # false (nothing started) and never guessed counts.
  if ($null -eq $row) {
    $leg = [pscustomobject]@{ ran = [bool]$started; passed = 0; failed = 0; skipped = 0; gate = $null; killed = $false; cut = $false; testSeconds = $null }
    if ($started) { $leg | Add-Member -NotePropertyName 'note' -NotePropertyValue 'leg started (transcript present) but produced no trx: unproven' -Force }
    return $leg
  }
  return [pscustomobject]@{ ran = $true; passed = $row.passed; failed = $row.failed; skipped = $row.skipped; gate = $row.gate; killed = $false; cut = $false; testSeconds = $seconds }
}
function Test-LegTranscript($runDir, $leg) {
  return (@(Get-ChildItem $runDir -Filter "*-$leg*.log" -ErrorAction SilentlyContinue).Count -gt 0)
}
$legA = New-BackLeg $rowA (Read-TestSeconds $RunDir 'default') (Test-LegTranscript $RunDir 'default')
$legB = New-BackLeg $rowB (Read-TestSeconds $RunDir 'primary') (Test-LegTranscript $RunDir 'primary')
$legI = New-BackLeg $rowI (Read-TranscriptWall $RunDir 'full') (Test-LegTranscript $RunDir 'full')
$legI | Add-Member -NotePropertyName 'enforcementRed' -NotePropertyValue $false -Force
if ($null -ne $rowA) { $legA | Add-Member -NotePropertyName 'note' -NotePropertyValue 'run-a counts cover UI only (shared trx name pre-§15)' -Force }

# Soak: per-iteration trx summaries (mechanical, no prose).
$soakFailed = @()
$soakFound = $false
foreach ($i in 1..5) {
  foreach ($s in @("ui-soak-$i", "protocol-soak-$i")) {
    $trx = @(Get-ChildItem $RunDir -Filter "$s.trx" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($trx.Count -eq 0) { continue }
    $soakFound = $true
    $st = $null
    try { $st = Get-TrxSummary $trx[0].FullName } catch { }
    if (($null -ne $st) -and ([int]$st.FailedCount -gt 0)) { $soakFailed += $s }
  }
}
$soakRan = $soakFound
$soakVerdict = 'skipped'
if ($soakRan) { $soakVerdict = if ($soakFailed.Count -gt 0) { 'red' } else { 'green' } }

# Incidents: verbatim INC lines when the report carries them (machine
# ids, none pre-§15); else derived from trx failures through the same
# formatter the live path uses, so recurrence sees the old reds. The
# parse mirrors Format-SoakLedger (first message line, 160ch).
function Get-TrxIncidentInputs($trxPath, $where) {
  $out = @()
  if (-not (Test-Path $trxPath)) { return $out }
  $sum = $null
  try { $sum = Get-TrxSummary $trxPath } catch { return $out }
  if ($null -eq $sum) { return $out }
  foreach ($fl in @($sum.Failed)) {
    $m = [regex]::Match($fl, '^\s*-\s*([^:]+):\s*(.*)$')
    if ($m.Success) { $out += [pscustomobject]@{ Test = $m.Groups[1].Value.Trim(); Message = $m.Groups[2].Value.Trim(); Where = $where } }
  }
  return $out
}
$incidents = @($rep | Where-Object { $_ -match '^- INC-[0-9a-f]{8} `' })
$incidentsDerived = $false
if ($incidents.Count -eq 0) {
  $inputs = @()
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'run-a*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Run A' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'run-b*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Run B' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'interactive.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Interactive' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter '*-soak-*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Soak' }
  if ($inputs.Count -gt 0) { $incidents = @(Format-Incidents $inputs); $incidentsDerived = $true }
}

# Verdict: red on any failure evidence; red without execution
# evidence (no trx, no counts) since a silent run proves nothing.
$trxCount = @(Get-ChildItem $RunDir -Filter '*.trx' -Recurse -ErrorAction SilentlyContinue).Count
$anyCounts = ($null -ne $rowA) -or ($null -ne $rowB) -or ($null -ne $rowI)
$verdict = 'green'
if (-not $anyCounts -and ($trxCount -eq 0)) { $verdict = 'red' }
elseif ((($null -ne $rowA) -and ($rowA.failed -gt 0)) -or (($null -ne $rowB) -and ($rowB.failed -gt 0)) -or (($null -ne $rowI) -and ($rowI.failed -gt 0))) { $verdict = 'red' }
elseif ((($null -ne $rowA) -and ($null -ne $rowA.gate) -and ($rowA.gate -ne 0)) -or (($null -ne $rowB) -and ($null -ne $rowB.gate) -and ($rowB.gate -ne 0))) { $verdict = 'red' }
elseif ($soakVerdict -eq 'red') { $verdict = 'red' }

$envBlock = Get-EnvironmentBlock ''
$envBlock | Add-Member -NotePropertyName 'basis' -NotePropertyValue 'backfill: live capture on the same box (topology/DPI/session corroborated by the §13 09-20 manifest); settings are current, not historical' -Force
$timings = @{}
if ($null -ne $legA.testSeconds) { $timings['run-a'] = $legA.testSeconds }
if ($null -ne $legB.testSeconds) { $timings['run-b'] = $legB.testSeconds }
if ($null -ne $legI.testSeconds) { $timings['interactive'] = $legI.testSeconds }
$result = [pscustomobject]@{
  version = 1; stamp = $stamp; day = $day; identity = $identity
  verdict = $verdict; exit = if ($verdict -eq 'red') { 1 } else { 0 }
  simulated = $false; trigger = $trigger; launch = $launch; commit = $commit
  buildError = ''
  legs = [pscustomobject]@{ 'run-a' = $legA; 'run-b' = $legB; interactive = $legI }
  soak = [pscustomobject]@{ ran = $soakRan; verdict = $soakVerdict; failed = @($soakFailed); killed = @(); cut = @(); failures = @() }
  quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @(); note = 'predates result capture; windows unrecoverable' }
  incidents = @($incidents)
  scheduler = [pscustomobject]@{ voted = $false; faults = @(); enabled = $true; lastRun = ''; lastResult = '' }
  tree = [pscustomobject]@{ start = 'unknown (predates §16)'; end = 'unknown (predates §16)'; stable = $true }
  recovered = 'none'; omissionOk = $true
  timings = $timings; reserve = $null
  env = $envBlock
  report = $reportFile[0].FullName
  note = "backfilled $(Get-Date -Format 'yyyy-MM-dd'): mechanical derivation (report rows, transcripts, trx); unknowns noted, never guessed"
}
$legacyGates = @()
if ($legA.ran -and ($null -eq $legA.gate)) { $legacyGates += 'run-a' }
if ($legB.ran -and ($null -eq $legB.gate)) { $legacyGates += 'run-b' }
if ($legacyGates.Count -gt 0) { $result.note += "; legacy gate prose on $($legacyGates -join ', ') (numeric exit unrecoverable)" }
# The classifier reads recovered <> 'none' as a dead-run event, so the
# field stays the bare 'none' and the predates-journal caveat rides the
# note (a backfill can neither recover nor rule out an older death).
$result.note += '; recovery unknowable (predates the run journal)'
if ($incidentsDerived) { $result.note += '; incidents derived from trx failures (no INC lines pre-§15)' }
if ($OutFile -eq '') { $OutFile = Join-Path $RunDir 'result.json' }
Write-AtomicReport @((ConvertTo-Json $result -Depth 8)) $OutFile
$chk = Test-ResultFile $OutFile
if (-not $chk.Ok) { Write-Output "backfill: INVALID result ($($chk.Error))"; exit 1 }
Write-Output "backfill: $stamp $verdict -> $OutFile"
