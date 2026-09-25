# Morning notification for the governed nightly (D00 T02 §24): alert
# routing, canonical runs, idempotent final-only delivery with retry,
# fallback, and delivery health, the morning digest plus no-start
# reconciler, multi-label outcomes, the prioritized toast body,
# report/result agreement, recovery notices, and launch-evidence links.
# Pure where it can be: delivery takes a sender scriptblock so fixtures
# (tools/NightlyNotify.Tests.ps1) force failures without a toast. Needs
# tools/NightlyParse.ps1 dot-sourced first (Write-AtomicReport,
# Get-FileSha256, Classify-NightlyOutcome).
$ErrorActionPreference = 'Stop'

# Notification contract version: bump when the payload shape changes.
# It rides the idempotency key beside the run identity and the result
# checksum, and stays separate from the result schema version.
$script:NotifyVersion = 1

# Class -> owner, channel, severity, and response SLA (item 10). The
# channel decides delivery: immediate interrupts, digest waits for the
# morning digest. docs/testing.md "Alert routing" carries the table.
$script:AlertClasses = [ordered]@{
  'scheduler-no-start' = @{ Owner = 'operator'; Channel = 'immediate'; Severity = 'critical'; SlaHours = 4 }
  'infrastructure'     = @{ Owner = 'operator'; Channel = 'immediate'; Severity = 'high'; SlaHours = 8 }
  'recovery'           = @{ Owner = 'operator'; Channel = 'immediate'; Severity = 'high'; SlaHours = 8 }
  'gate'               = @{ Owner = 'triage (D00 T02 s9)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
  'enforcement'        = @{ Owner = 'triage (D00 T02 s9)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
  'test'               = @{ Owner = 'triage (D00 T02 s9)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
  'degraded-soak'      = @{ Owner = 'triage (D00 T02 s5)'; Channel = 'digest'; Severity = 'low'; SlaHours = 72 }
  'green'              = @{ Owner = 'none'; Channel = 'digest'; Severity = 'info'; SlaHours = 0 }
  'stood-down'         = @{ Owner = 'none'; Channel = 'none'; Severity = 'info'; SlaHours = 0 }
  'cancelled'          = @{ Owner = 'operator'; Channel = 'immediate'; Severity = 'high'; SlaHours = 8 }
}

function Get-AlertRoute([string]$Class) {
  # Unknown classes route like infrastructure: an unmapped class goes to
  # a human now, never to silence.
  if ($script:AlertClasses.Contains($Class)) { $r = $script:AlertClasses[$Class] }
  else { $r = $script:AlertClasses['infrastructure'] }
  return [pscustomobject]@{ Class = $Class; Owner = $r.Owner; Channel = $r.Channel; Severity = $r.Severity; SlaHours = $r.SlaHours }
}

function Get-OutcomeLabels($Result) {
  # Every outcome a night carries (item 9), in precedence order, beside
  # the single class Classify-NightlyOutcome picks for the title, so one
  # title never hides simultaneous gate, enforcement, test, soak,
  # quarantine, or infrastructure failures.
  $labels = @()
  $faults = ''
  try { $faults = (@($Result.scheduler.faults) -join ';') } catch { }
  $voted = $false
  try { $voted = [bool]$Result.scheduler.voted } catch { }
  if ($voted -and (($faults -like '*missing start*') -or ($faults -like '*task disabled*'))) { $labels += 'scheduler-no-start' }
  $infra = $false
  try { if ("$($Result.buildError)" -ne '') { $infra = $true } } catch { }
  try { if (($null -ne $Result.omissionOk) -and (-not [bool]$Result.omissionOk)) { $infra = $true } } catch { }
  $gateRed = $false
  foreach ($leg in @('run-a', 'run-b')) {
    $g = $null
    try { $g = $Result.legs.$leg } catch { }
    if ($null -eq $g) { continue }
    try { if (($null -ne $g.ran) -and (-not [bool]$g.ran)) { continue } } catch { }
    try { if ([bool]$g.killed -or [bool]$g.cut) { $infra = $true } } catch { }
    try { if ($null -eq $g.gate) { $infra = $true } elseif ([int]$g.gate -ne 0) { $gateRed = $true } } catch { $infra = $true }
  }
  if ($infra) { $labels += 'infrastructure' }
  try { $rec = "$($Result.recovered)"; if (($rec -ne '') -and ($rec -ne 'none')) { $labels += 'recovery' } } catch { }
  if ($gateRed) { $labels += 'gate' }
  try { if ([bool]$Result.legs.interactive.enforcementRed) { $labels += 'enforcement' } } catch { }
  $failed = 0
  foreach ($leg in @('run-a', 'run-b', 'interactive')) {
    try { $o = $Result.legs.$leg; if (($null -ne $o) -and (($null -eq $o.ran) -or [bool]$o.ran)) { $failed += [int]$o.failed } } catch { }
  }
  if ($failed -gt 0) { $labels += 'test' }
  try { if ("$($Result.soak.verdict)" -eq 'red') { $labels += 'degraded-soak' } } catch { }
  try { if (@($Result.quarantine.overdue).Count -gt 0) { $labels += 'quarantine-overdue' } } catch { }
  return $labels
}

function Format-ToastLines($Items, [string]$ReportPath, [int]$Cap = 7) {
  # The toast body under its cap (item 11): items carry Priority (lower
  # is more urgent) plus Text; the report link always rides last, and a
  # truncated body says how many lines it dropped, so a critical line
  # never falls off behind a routine one. Priority order (docs/testing.md
  # "Alert routing"): 0 fail-closed, 1 escalation, 2 top incident, 3
  # recovery, 4 overdue quarantine, 5 counts, 6 labels, 7 trigger.
  $sorted = @(@($Items) | Where-Object { $null -ne $_ } | Sort-Object @{ Expression = { [int]$_.Priority } }, @{ Expression = { [int]$_.Order } })
  $room = $Cap - 1
  $body = @()
  if ($sorted.Count -le $room) { $body = @($sorted | ForEach-Object { $_.Text }) }
  else {
    $body = @($sorted | Select-Object -First ($room - 1) | ForEach-Object { $_.Text })
    $body += "+$($sorted.Count - ($room - 1)) more in the report"
  }
  $body += "Report: $ReportPath"
  return $body
}

function New-ToastItem([int]$Priority, [string]$Text, [int]$Order = 0) {
  return [pscustomobject]@{ Priority = $Priority; Text = $Text; Order = $Order }
}

function Invoke-WithNotifyLock([scriptblock]$Body, [int]$TimeoutSeconds = 60) {
  # Serializes notify-state read-modify-write (D00 T02 §24 R1-F2): the
  # ledger, the digest queue, and the undelivered set are shared by the
  # nightly, the supervisor, and the morning reconciler, and an atomic
  # file replace alone cannot stop two writers losing each other's
  # entries or both sending one key. A lock that cannot be taken inside
  # the timeout throws, so the caller fails loud instead of racing.
  $m = New-Object System.Threading.Mutex($false, 'Local\ScratchPad.NightlyNotifyState')
  $held = $false
  try {
    try { $held = $m.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw "notify state lock not acquired within ${TimeoutSeconds}s" }
    return (& $Body)
  } finally {
    if ($held) { $m.ReleaseMutex() }
    $m.Dispose()
  }
}

function Read-JsonState([string]$Path, $Default) {
  # Small ignored-scratch state files (ledger, digest queue): missing
  # reads as the default, corrupt throws so the caller reports it.
  if (-not (Test-Path $Path)) { return $Default }
  $v = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  # Windows PowerShell hands back an empty JSON array as one empty
  # array object, so a flushed queue would read as one phantom entry;
  # the elements are flattened here, and nulls drop.
  $items = @()
  foreach ($x in @($v)) {
    if ($x -is [array]) { foreach ($y in $x) { if ($null -ne $y) { $items += $y } } }
    elseif ($null -ne $x) { $items += $x }
  }
  # Unrolled on purpose: every caller collects with @(), which rebuilds
  # the array (a comma-wrapped return would nest it as one element).
  return $items
}

function Invoke-NightlyNotify {
  # Final-only, idempotent delivery (items 3, 5, 6, 8). Only a 'final'
  # publication notifies (core and provisional publications never do).
  # The key is run identity plus result checksum plus notification
  # version, recorded in the notify ledger, so a retried task, a
  # supervisor recovery, or a rerun of the same result sends once. The
  # class route picks the channel: immediate sends now, digest queues
  # for the morning digest. An immediate send retries, and when every
  # attempt fails it falls back to an undelivered file the morning
  # reconciler re-sends and every report escalates until delivered.
  # Returns Status (sent, queued, duplicate, skipped, fallback) plus
  # Attempts and Notes.
  param(
    [string]$Phase, [string]$RunId, [string]$ResultPath, [string]$Class,
    [string]$Title, [string[]]$Lines, [string]$StateDir,
    [scriptblock]$Sender, [int]$Retries = 2, [datetime]$Now = (Get-Date),
    [switch]$NoPersist, [int]$LockTimeoutSeconds = 60
  )
  # -NoPersist (dry runs, R1-F1) decides and reports but writes no
  # ledger, queue, or undelivered state, so a rehearsal can never
  # suppress the real notification as a duplicate.
  $out = [pscustomobject]@{ Status = ''; Attempts = 0; Notes = @(); Key = '' }
  if ($Phase -ne 'final') { $out.Status = 'skipped'; $out.Notes += "not a final publication ($Phase)"; return $out }
  $sha = 'noresult'
  if (($ResultPath -ne '') -and (Test-Path $ResultPath)) { $sha = Get-FileSha256 $ResultPath }
  $key = "$RunId|$sha|v$($script:NotifyVersion)"
  $out.Key = $key
  $null = New-Item -ItemType Directory -Force -Path $StateDir
  return (Invoke-WithNotifyLock -TimeoutSeconds $LockTimeoutSeconds -Body {
  $ledgerPath = Join-Path $StateDir 'notify-ledger.json'
  $ledger = @(Read-JsonState $ledgerPath @())
  if (@($ledger | Where-Object { "$($_.key)" -eq $key }).Count -gt 0) { $out.Status = 'duplicate'; $out.Notes += "already notified for $key"; return $out }
  $route = Get-AlertRoute $Class
  $entry = [pscustomobject]@{ key = $key; run = $RunId; class = $Class; channel = $route.Channel; at = $Now.ToString('o'); status = '' }
  if ($route.Channel -eq 'none') {
    $out.Status = 'skipped'; $out.Notes += "class $Class routes nowhere"
  } elseif ($route.Channel -eq 'digest') {
    $qPath = Join-Path $StateDir 'digest-queue.json'
    $q = @(Read-JsonState $qPath @())
    $q += [pscustomobject]@{ key = $key; run = $RunId; class = $Class; title = $Title; lines = @($Lines); at = $Now.ToString('o') }
    if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json @($q) -Depth 6) $qPath }
    $out.Status = 'queued'; $out.Notes += "queued for the morning digest ($Class, SLA $($route.SlaHours)h, owner $($route.Owner))"
  } else {
    $ok = $false
    for ($i = 0; ($i -le $Retries) -and (-not $ok); $i++) {
      $out.Attempts++
      try { $ok = [bool](& $Sender $Title $Lines) } catch { $ok = $false; $out.Notes += "attempt $($out.Attempts) threw: $($_.Exception.Message)" }
    }
    if ($ok) { $out.Status = 'sent'; $out.Notes += "sent after $($out.Attempts) attempt(s)" }
    else {
      $uDir = Join-Path $StateDir 'undelivered'
      $null = New-Item -ItemType Directory -Force -Path $uDir
      $safe = ($RunId -replace '[^A-Za-z0-9-]', '-')
      $payload = [pscustomobject]@{ key = $key; run = $RunId; class = $Class; title = $Title; lines = @($Lines); failedAt = $Now.ToString('o'); attempts = $out.Attempts }
      if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json $payload -Depth 6) (Join-Path $uDir "$safe.json") }
      $out.Status = 'fallback'; $out.Notes += "delivery failed after $($out.Attempts) attempt(s); fallback undelivered/$safe.json, re-sent by the morning reconciler and escalated in every report until delivered"
    }
  }
  $entry.status = $out.Status
  if ((@('sent', 'queued', 'fallback') -contains $out.Status) -and (-not $NoPersist)) {
    $ledger += $entry
    Write-AtomicReport @(ConvertTo-Json @($ledger) -Depth 6) $ledgerPath
  }
  if ($NoPersist) { $out.Notes += 'dry run: no state written' }
  return $out
  })
}

function Get-DeliveryHealth([string]$StateDir, [datetime]$Now = (Get-Date), [int]$StaleQueueHours = 26) {
  # Delivery-health escalation (item 3): every undelivered notification
  # is named in every report until the reconciler delivers it, and a
  # digest queue older than a day means the reconciler is not flushing
  # (R1-F6). Returns Ok, Count, and Lines.
  $uDir = Join-Path $StateDir 'undelivered'
  $files = @(Get-ChildItem $uDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $stale = @()
  try {
    foreach ($e in @(Read-JsonState (Join-Path $StateDir 'digest-queue.json') @())) {
      if ($null -eq $e) { continue }
      $at = [datetime]::MinValue
      if ([datetime]::TryParse("$($e.at)", [ref]$at) -and (($Now - $at).TotalHours -gt $StaleQueueHours)) { $stale += "$($e.run)" }
    }
  } catch { $stale += 'digest queue unreadable' }
  if (($files.Count -eq 0) -and ($stale.Count -eq 0)) { return [pscustomobject]@{ Ok = $true; Count = 0; Lines = @('- Delivery: healthy (no undelivered notifications)') } }
  $lines = @()
  if ($stale.Count -gt 0) { $lines += "- Delivery RED: digest queue stale past ${StaleQueueHours}h ($($stale -join ', ')); escalate operator (the morning reconciler is not flushing)" }
  if ($files.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Count = $stale.Count; Lines = $lines } }
  $lines += "- Delivery RED: $($files.Count) undelivered notification(s); escalate operator (toast channel failing)"
  foreach ($f in $files) {
    $age = ''
    try { $p = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; $age = " (failed $($p.failedAt), $($p.attempts) attempt(s), class $($p.class))" } catch { $age = ' (unreadable payload)' }
    $lines += "  - undelivered/$($f.Name)$age"
  }
  return [pscustomobject]@{ Ok = $false; Count = $files.Count; Lines = $lines }
}

function Get-NoStartVerdict($Results, [datetime]$Now, [string]$ExpectBy = '06:50') {
  # The independent no-start check (item 4): after the window closes, a
  # night with no scheduler- or demand-launched result for today is a
  # suppressed night, alerted by the morning reconciler without any
  # governed run firing. Manual runs do not count as the night's start.
  $today = $Now.ToString('yyyy-MM-dd')
  $by = [datetime]::ParseExact("$today $ExpectBy", 'yyyy-MM-dd HH:mm', $null)
  if ($Now -lt $by) { return [pscustomobject]@{ NoStart = $false; Line = "no-start check waits for $ExpectBy" } }
  $started = @(@($Results) | Where-Object { ($null -ne $_) -and ("$($_.day)" -eq $today) -and (@('timer', 'demand') -contains "$($_.launch)") })
  $tomb = @(@($Results) | Where-Object { ($null -ne $_) -and ("$($_.day)" -eq $today) -and ("$($_.trigger)" -like 'supervisor tombstone*') })
  if (($started.Count -gt 0) -or ($tomb.Count -gt 0)) { return [pscustomobject]@{ NoStart = $false; Line = "night $today started ($($started.Count + $tomb.Count) scheduled result(s))" } }
  return [pscustomobject]@{ NoStart = $true; Line = "NO START: no scheduled nightly result for $today by $ExpectBy (check the task is enabled and fires; run the manual backup)" }
}

function Invoke-DigestFlush {
  # The morning digest flush (D00 T02 §24 items 3 and 8, R1-F5, R1-F6).
  # Under the notify lock it claims the whole queue, writes every
  # queued payload whole (title plus every line, each with its own
  # report link) to build/nightly/digest-<day>.md so nothing is lost to
  # the toast cap, and sends one summary toast naming that file. The
  # send retries; when every attempt fails the summary joins the
  # undelivered set (re-sent by the next reconcile and escalated by
  # Get-DeliveryHealth), so a failing digest channel is never silent.
  param([string]$StateDir, [string]$Day, [scriptblock]$Sender, [int]$Retries = 2, [switch]$NoPersist, [datetime]$Now = (Get-Date))
  return (Invoke-WithNotifyLock -Body {
    $out = [pscustomobject]@{ Status = 'empty'; Count = 0; Attempts = 0; Notes = @(); DigestPath = '' }
    $qPath = Join-Path $StateDir 'digest-queue.json'
    $queue = @(@(Read-JsonState $qPath @()) | Where-Object { $null -ne $_ })
    if ($queue.Count -eq 0) { $out.Notes += 'nothing queued'; return $out }
    $out.Count = $queue.Count
    $dPath = Join-Path $StateDir "digest-$Day.md"
    $out.DigestPath = $dPath
    $md = @("# Nightly digest: $Day", '', "$($queue.Count) routine notification(s), queued by the nightly for the morning digest (D00 T02 s24).", '')
    foreach ($e in $queue) { $md += "## $($e.title)"; $md += ''; $md += "- Run: $($e.run) (class $($e.class), queued $($e.at))"; foreach ($l in @($e.lines)) { $md += "- $l" }; $md += '' }
    $dg = Format-Digest $queue $Day
    $lines = @($dg.Lines) + @("Digest: build/nightly/digest-$Day.md")
    if (-not $NoPersist) { Write-AtomicReport $md $dPath }
    $ok = $false
    for ($i = 0; ($i -le $Retries) -and (-not $ok); $i++) {
      $out.Attempts++
      try { $ok = [bool](& $Sender $dg.Title $lines) } catch { $ok = $false; $out.Notes += "attempt $($out.Attempts) threw: $($_.Exception.Message)" }
    }
    if ($ok) { $out.Status = 'sent'; $out.Notes += "sent $($queue.Count) queued notification(s) after $($out.Attempts) attempt(s)" }
    else {
      $out.Status = 'fallback'
      $uDir = Join-Path $StateDir 'undelivered'
      $payload = [pscustomobject]@{ key = "digest-$Day"; run = "digest-$Day"; class = 'digest'; title = $dg.Title; lines = $lines; failedAt = $Now.ToString('o'); attempts = $out.Attempts }
      if (-not $NoPersist) { $null = New-Item -ItemType Directory -Force -Path $uDir; Write-AtomicReport @(ConvertTo-Json $payload -Depth 6) (Join-Path $uDir "digest-$Day.json") }
      $out.Notes += "digest delivery failed after $($out.Attempts) attempt(s); fallback undelivered/digest-$Day.json, the full digest stays in digest-$Day.md"
    }
    if (-not $NoPersist) { Write-AtomicReport @('[]') $qPath } else { $out.Notes += 'dry run: no state written' }
    return $out
  })
}

function Format-Digest($Queue, [string]$Day) {
  # The morning digest (item 8): every queued routine notification in
  # one toast, worst class first, with the count per class.
  $q = @(@($Queue) | Where-Object { $null -ne $_ })
  if ($q.Count -eq 0) { return $null }
  $order = @($script:AlertClasses.Keys)
  $byClass = $q | Group-Object { "$($_.class)" } | Sort-Object { $i = $order.IndexOf($_.Name); if ($i -lt 0) { 99 } else { $i } }
  $title = "Nightly digest $Day : $($q.Count) run(s)"
  $lines = @()
  foreach ($g in $byClass) { $lines += "$($g.Count) x $($g.Name): $((@($g.Group | ForEach-Object { $_.run }) | Select-Object -First 3) -join ', ')" }
  return [pscustomobject]@{ Title = $title; Lines = $lines }
}

function Test-ReportResultAgreement([string[]]$ReportLines, $Result) {
  # Field-level agreement between the Markdown report and the JSON
  # result (item 12): leg counts plus gate codes, the incident id set,
  # the reserve, the environment line, and the exit code. The run reds
  # on any contradiction, so the two surfaces can never disagree
  # silently. Returns Ok plus Breaks.
  $breaks = @()
  $legMap = @{ 'Run A (default)' = 'run-a'; 'Run B (primary)' = 'run-b'; 'Interactive (collection)' = 'interactive' }
  $seenLegs = @()
  foreach ($ln in $ReportLines) {
    $m = [regex]::Match("$ln", '^\| (Run A \(default\)|Run B \(primary\)|Interactive \(collection\)) \| (\d+) passed, (\d+) failed, (\d+) skipped[^|]*\| ([^|]*)\|')
    if (-not $m.Success) { continue }
    $key = $legMap[$m.Groups[1].Value]
    $seenLegs += $key
    $leg = $null
    try { $leg = $Result.legs.$key } catch { }
    if ($null -eq $leg) { $breaks += "${key}: report has counts, result has no leg"; continue }
    foreach ($pair in @(@('passed', 2), @('failed', 3), @('skipped', 4))) {
      $rv = $null
      try { $rv = [int]$leg.($pair[0]) } catch { }
      if ($rv -ne [int]$m.Groups[$pair[1]].Value) { $breaks += "$key $($pair[0]): report $($m.Groups[$pair[1]].Value) vs result $rv" }
    }
    $gm = [regex]::Match($m.Groups[5].Value, '^\s*exit (\d+)')
    if ($gm.Success) {
      $rg = $null
      try { $rg = $leg.gate } catch { }
      if (($null -eq $rg) -or ([int]$rg -ne [int]$gm.Groups[1].Value)) { $breaks += "$key gate: report exit $($gm.Groups[1].Value) vs result $rg" }
    }
  }
  # A leg the result says ran must have its counts row (R1-F3).
  foreach ($key in @('run-a', 'run-b', 'interactive')) {
    $leg = $null
    try { $leg = $Result.legs.$key } catch { }
    if ($null -eq $leg) { continue }
    $ran = $true
    try { if ($null -ne $leg.ran) { $ran = [bool]$leg.ran } } catch { }
    if ($ran -and ($seenLegs -notcontains $key)) { $breaks += "${key}: result ran the leg, report has no counts row" }
  }
  $inSec = $false
  $repInc = @()
  foreach ($ln in $ReportLines) {
    if ("$ln" -eq '## Incidents') { $inSec = $true; continue }
    if ($inSec -and ("$ln" -like '## *')) { break }
    if ($inSec) { $im = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) '); if ($im.Success) { $repInc += $im.Groups[1].Value } }
  }
  $resInc = @()
  foreach ($ln in @($Result.incidents)) { $im = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) '); if ($im.Success) { $resInc += $im.Groups[1].Value } }
  if ((@($repInc | Sort-Object) -join ',') -ne (@($resInc | Sort-Object) -join ',')) { $breaks += "incidents: report [$(@($repInc | Sort-Object) -join ',')] vs result [$(@($resInc | Sort-Object) -join ',')]" }
  # Budget (R1-F3): the report's Budget line must exist and carry both
  # fields the result carries.
  $bm = @($ReportLines | ForEach-Object { [regex]::Match("$_", '^- Budget: consumed=(-?\d+)s reserve=(-?\d+)s$') } | Where-Object { $_.Success }) | Select-Object -First 1
  if ($null -eq $bm) { $breaks += 'budget: report carries no Budget line' }
  else {
    $rc = $null; $rr = $null
    try { $rc = [int]$Result.consumed } catch { }
    try { $rr = [int]$Result.reserve } catch { }
    if ($rc -ne [int]$bm.Groups[1].Value) { $breaks += "budget consumed: report $($bm.Groups[1].Value)s vs result $rc" }
    if ($rr -ne [int]$bm.Groups[2].Value) { $breaks += "budget reserve: report $($bm.Groups[2].Value)s vs result $rr" }
  }
  # Soak (R1-F3): the report's soak verdict line matches the result's.
  $soakSec = $false
  $repSoak = ''
  foreach ($ln in $ReportLines) {
    if ("$ln" -eq '## Soak') { $soakSec = $true; continue }
    if ($soakSec -and ("$ln" -like '## *')) { break }
    if (-not $soakSec) { continue }
    if ("$ln" -like '- Verdict: GREEN*') { $repSoak = 'green'; break }
    if ("$ln" -like '- Verdict: RED*') { $repSoak = 'red'; break }
    if ("$ln" -like '(no soak iterations ran*') { $repSoak = 'skipped'; break }
  }
  $resSoak = ''
  try { $resSoak = "$($Result.soak.verdict)" } catch { }
  if (($repSoak -ne '') -or ($resSoak -ne '')) {
    if ($repSoak -ne $resSoak) { $breaks += "soak: report $(if ($repSoak -eq '') { 'no verdict' } else { $repSoak }) vs result $resSoak" }
  }
  # Environment (R1-F3): every field, from one line the run prints off
  # the same object it writes to the JSON.
  $envKeys = @('os', 'powershell', 'dotnet', 'session', 'topology', 'dpi', 'adapters', 'settings')
  $envLine = @($ReportLines | Where-Object { "$_" -like '- Environment: *' }) | Select-Object -First 1
  if ($null -eq $envLine) { $breaks += 'environment: report carries no Environment line' }
  else {
    foreach ($k in $envKeys) {
      $want = ''
      try { $want = "$($Result.env.$k)" } catch { }
      $got = $null
      foreach ($part in ("$envLine".Substring(15) -split '; ')) { if ($part.StartsWith("$k ")) { $got = $part.Substring($k.Length + 1) } elseif ($part -eq $k) { $got = '' } }
      if ($null -eq $got) { $breaks += "environment ${k}: report omits it" }
      elseif ($got -ne $want) { $breaks += "environment ${k}: report '$got' vs result '$want'" }
    }
  }
  $xm = @($ReportLines | ForEach-Object { [regex]::Match("$_", '^- Exit: (\d+)$') } | Where-Object { $_.Success }) | Select-Object -First 1
  if ($null -eq $xm) { $breaks += 'exit: report carries no Exit line' }
  else {
    $rx = $null
    try { $rx = [int]$Result.exit } catch { }
    if ($rx -ne [int]$xm.Groups[1].Value) { $breaks += "exit: report $($xm.Groups[1].Value) vs result $rx" }
  }
  return [pscustomobject]@{ Ok = ($breaks.Count -eq 0); Breaks = $breaks }
}

function Get-RecoveryNotices($Canonical, $Results, $Current, [string[]]$LedgerLines) {
  # Recovery notices (item 13): a canonical night that turns GREEN after
  # a RED canonical night says so, and every incident the §22 ledger
  # closed on verified recovery rides the notification by id.
  $notices = @()
  $day = "$($Current.day)"
  $curId = "$($Current.identity)"
  if ($curId -eq '') { $curId = "$($Current.stamp)" }
  # Only the night's canonical run speaks for the night (R1-F4): a GREEN
  # manual retry after a RED timer run is not a recovered night.
  $isCanonicalNow = $Canonical.ContainsKey($day) -and ($Canonical[$day].Canonical -eq $curId)
  $prev = @($Canonical.Keys | Where-Object { [string]::CompareOrdinal($_, $day) -lt 0 } | Sort-Object -Descending) | Select-Object -First 1
  if ($isCanonicalNow -and ($null -ne $prev) -and ("$($Current.verdict)" -eq 'green')) {
    $pid0 = $Canonical[$prev].Canonical
    $pr = @(@($Results) | Where-Object { ("$($_.identity)" -eq $pid0) -or ("$($_.stamp)" -eq $pid0) }) | Select-Object -First 1
    if (($null -ne $pr) -and (@('red', 'cancelled') -contains "$($pr.verdict)")) { $notices += "Recovered: night $prev was $($pr.verdict.ToString().ToUpper()), $day is GREEN" }
  }
  foreach ($ln in @($LedgerLines)) {
    $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)`: CLOSED')
    if ($m.Success) { $notices += "Recovered: $($m.Groups[1].Value) $($m.Groups[2].Value) (closed on verified recovery)" }
  }
  return $notices
}

function Find-IncidentEvidence([string]$DiagRoot, [string]$Test, [string[]]$Days) {
  # Launch evidence behind an incident (item 14): the §18 foreground-leak
  # bundles (bundles/<yyyyMMdd>/<Class-cs-Method>-<HHmmss>/bundle.json
  # plus leak.png) and failed launch records (launches-<yyyyMMdd>.jsonl
  # rows for Class.cs:Method with an error). A test that owns neither is
  # not launch-related and links nothing. Returns Links (strings).
  $links = @()
  $m = [regex]::Match("$Test", '^(?:[\w]+\.)*?(\w+)\.(\w+)(?:\(.*)?$')
  if (-not $m.Success) { return $links }
  $cls = $m.Groups[1].Value; $meth = $m.Groups[2].Value
  $recTest = "$cls.cs:$meth"
  $san = { param($t) (-join ($t.ToCharArray() | ForEach-Object { if ([char]::IsLetterOrDigit($_)) { $_ } else { '-' } })) }
  $prefixes = @((& $san "$cls.cs:$meth"), (& $san "${cls}:$meth"))
  foreach ($d in @($Days)) {
    $bd = Join-Path $DiagRoot (Join-Path 'bundles' $d)
    foreach ($dir in @(Get-ChildItem $bd -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
      $hit = $false
      foreach ($p in $prefixes) { if ($dir.Name -like "$p-*") { $hit = $true } }
      if (-not $hit) { continue }
      $bj = Join-Path $dir.FullName 'bundle.json'
      if (Test-Path $bj) { $links += "bundle $bj" }
      $png = Join-Path $dir.FullName 'leak.png'
      if (Test-Path $png) { $links += "screenshot $png" }
    }
    $lf = Join-Path $DiagRoot "launches-$d.jsonl"
    if (Test-Path $lf) {
      $n = 0
      foreach ($ln in [System.IO.File]::ReadAllLines($lf)) {
        $n++
        if (($ln -like "*`"test`":`"$recTest`"*") -and ($ln -notlike '*"error":null*')) { $links += "launch-record ${lf}:$n" }
      }
    }
  }
  return $links
}
