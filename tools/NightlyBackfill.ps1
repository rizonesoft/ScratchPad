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
function Read-TranscriptCounts($runDir, $leg) {
  # Assembly sums beat the report row (D00-T02-S9 S4/FL2): the §9
  # generator wrote UI-only rows (rerun Run A reads 163/1/3; the
  # archive sums 545/1/3 and the §9 stamp quotes 545). Returns $null
  # when no leg log parses to an assembly row.
  $log = @(Get-ChildItem $runDir -Filter "*-$leg.log" -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($log.Count -eq 0) { return $null }
  $rows = @()
  try { $rows = @(Get-TranscriptRows $log[0].FullName) } catch { return $null }
  if ($rows.Count -eq 0) { return $null }
  $p = 0; $f = 0; $s = 0
  foreach ($r in $rows) { try { $p += [int]$r.Passed; $f += [int]$r.Failed; $s += [int]$r.Skipped } catch { } }
  return [pscustomobject]@{ passed = $p; failed = $f; skipped = $s; assemblies = $rows.Count }
}
$countNotes = @()
foreach ($leg in @('default', 'primary')) {
  $tc = Read-TranscriptCounts $RunDir $leg
  if ($null -eq $tc) { continue }
  $nm = if ($leg -eq 'default') { 'run-a' } else { 'run-b' }
  $row = if ($leg -eq 'default') { $rowA } else { $rowB }
  $gate = if ($null -ne $row) { $row.gate } else { $null }
  if (($null -ne $row) -and ($row.passed -eq $tc.passed) -and ($row.failed -eq $tc.failed) -and ($row.skipped -eq $tc.skipped)) { continue }
  if ($null -ne $row) { $countNotes += "$nm counts from transcript ($($tc.passed)/$($tc.failed)/$($tc.skipped) across $($tc.assemblies) assemblies; row reads $($row.passed)/$($row.failed)/$($row.skipped))" }
  else { $countNotes += "$nm counts from transcript ($($tc.passed)/$($tc.failed)/$($tc.skipped) across $($tc.assemblies) assemblies; no row)" }
  $newRow = [pscustomobject]@{ passed = $tc.passed; failed = $tc.failed; skipped = $tc.skipped; gate = $gate }
  if ($leg -eq 'default') { $rowA = $newRow } else { $rowB = $newRow }
}
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
# Enforcement replays the live rule on the retained trx (the stamps
# live in the messages, so no ledger is needed): unclassifiable or
# leaking reads red exactly as the live leg would.
$enfRed = $false
$enfNote = ''
if ($legI.ran) {
  $itrx = @(Get-ChildItem $RunDir -Filter 'interactive.trx' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($itrx.Count -eq 0) { $enfRed = $true; $enfNote = 'enforcement unproven (ran, no interactive trx)' }
  else {
    try {
      $nc = Get-NonQuarantineSkips $itrx[0].FullName
      $enfRed = ((-not [bool]$nc.Ok) -or (@($nc.Names).Count -gt 0))
      if (-not [bool]$nc.Ok) { $enfNote = 'enforcement unproven (interactive trx unclassifiable)' }
    } catch { $enfRed = $true; $enfNote = 'enforcement unproven (interactive trx unreadable)' }
  }
}
$legI | Add-Member -NotePropertyName 'enforcementRed' -NotePropertyValue ([bool]$enfRed) -Force
if ($enfNote -ne '') { $legI | Add-Member -NotePropertyName 'note' -NotePropertyValue $enfNote -Force }

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
# formatter the live path uses, so recurrence sees the old reds. Soak
# iterations pass their trx basename (ui-soak-N), which the identity
# contract folds into its suite phase exactly as the live ledger does.
function Get-TrxIncidentInputs($trxPath, $where) {
  $out = @()
  if (-not (Test-Path $trxPath)) { return $out }
  $sum = $null
  try { $sum = Get-TrxSummary $trxPath } catch { return $out }
  if ($null -eq $sum) { return $out }
  # Structured failures (D00 T02 §22 item 3): message plus stack feed
  # the same incident identity contract the live path uses.
  foreach ($fd in @($sum.FailedDetail)) { $out += [pscustomobject]@{ Test = $fd.Test; Message = $fd.Message; Where = $where; Stack = $fd.Stack } }
  return $out
}
$incidents = @($rep | Where-Object { $_ -match '^- INC-[0-9a-f]{8} `' })
$incidentsDerived = $false
$inputs = @()
if ($incidents.Count -eq 0) {
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'run-a*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Run A' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'run-b*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Run B' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter 'interactive.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName 'Interactive' }
  foreach ($t in @(Get-ChildItem $RunDir -Filter '*-soak-*.trx' -Recurse -ErrorAction SilentlyContinue)) { $inputs += Get-TrxIncidentInputs $t.FullName $t.BaseName }
  if ($inputs.Count -gt 0) { $incidents = @(Format-Incidents $inputs); $incidentsDerived = $true }
}
$soakFailures = @($inputs | Where-Object { "$($_.Where)" -match '^(ui|protocol)-soak-\d+$' })

# Verdict: red on any failure evidence; red without execution
# evidence (no trx, no counts) since a silent run proves nothing; red
# when a ran gated leg has no gate code, since an unproven gate is an
# infrastructure verdict by the classifier's own rule (a failure-free
# legacy run still reds: its foreground proof is unrecoverable).
$trxCount = @(Get-ChildItem $RunDir -Filter '*.trx' -Recurse -ErrorAction SilentlyContinue).Count
$anyCounts = ($null -ne $rowA) -or ($null -ne $rowB) -or ($null -ne $rowI)
$verdict = 'green'
if (-not $anyCounts -and ($trxCount -eq 0)) { $verdict = 'red' }
elseif ((($null -ne $rowA) -and ($rowA.failed -gt 0)) -or (($null -ne $rowB) -and ($rowB.failed -gt 0)) -or (($null -ne $rowI) -and ($rowI.failed -gt 0))) { $verdict = 'red' }
elseif ((($null -ne $rowA) -and ($null -ne $rowA.gate) -and ($rowA.gate -ne 0)) -or (($null -ne $rowB) -and ($null -ne $rowB.gate) -and ($rowB.gate -ne 0))) { $verdict = 'red' }
elseif ((($null -ne $rowA) -and ($null -eq $rowA.gate)) -or (($null -ne $rowB) -and ($null -eq $rowB.gate))) { $verdict = 'red' }
elseif ($soakVerdict -eq 'red') { $verdict = 'red' }

# Scheduler-enabled reads true only on scheduler-parented launches (a
# manual run fires with the task disabled, so enabled is unknowable
# there, never true).
$schedEnabled = $null
if (($launch -eq 'timer') -or ($launch -eq 'demand')) { $schedEnabled = $true }
# Historical environment is unrecoverable, so every dimension reads
# unknown: stamping current-box values onto a September night would
# fabricate cross-night comparability (SDKs update, sessions differ,
# settings drift). The basis line says exactly that; triage compares
# live nights, never backfills, on env.
$envBlock = [pscustomobject]@{ os = 'unknown'; powershell = 'unknown'; dotnet = 'unknown'; session = 'unknown'; topology = 'unknown'; dpi = 'unknown'; adapters = 'unknown'; settings = 'unknown' }
$envBlock | Add-Member -NotePropertyName 'basis' -NotePropertyValue 'backfilled: run-night environment unrecoverable, all dimensions unknown' -Force
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
  soak = [pscustomobject]@{ ran = $soakRan; verdict = $soakVerdict; failed = @($soakFailed); killed = @(); cut = @(); failures = @($soakFailures) }
  quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @(); overdueDetail = @(); note = 'predates result capture; windows unrecoverable' }
  incidents = @($incidents)
  scheduler = [pscustomobject]@{ voted = $false; faults = @(); enabled = $schedEnabled; lastRun = ''; lastResult = '' }
  tree = [pscustomobject]@{ start = 'unknown (predates §16)'; end = 'unknown (predates §16)'; stable = $null }
  recovered = 'none'; omissionOk = $true
  timings = $timings; reserve = $null; consumed = $null
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
foreach ($cn in $countNotes) { $result.note += "; $cn" }
if ($OutFile -eq '') { $OutFile = Join-Path $RunDir 'result.json' }
Write-AtomicReport @((ConvertTo-Json $result -Depth 8)) $OutFile
$chk = Test-ResultFile $OutFile
if (-not $chk.Ok) { Write-Output "backfill: INVALID result ($($chk.Error))"; exit 1 }
Write-Output "backfill: $stamp $verdict -> $OutFile"
