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
  'trend-regression'   = @{ Owner = 'triage (D00 T02 s9)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
  'incident-overdue'   = @{ Owner = 'incident owner (tools/incident-policy.json)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
  'quarantine-overdue' = @{ Owner = 'triage (D00 T02 s9)'; Channel = 'digest'; Severity = 'medium'; SlaHours = 24 }
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

function Get-AckSlaHours($Result) {
  # The acknowledgement SLA for a RED (D00 T02 section 31 item 8): the
  # strictest response SLA among the run's outcome labels, 0 when none
  # applies. Shared by the nightly's gate and tools/NightlyAck.ps1, so
  # both judge the same deadline.
  $h = @(@(Get-OutcomeLabels $Result) | ForEach-Object { (Get-AlertRoute $_).SlaHours } | Where-Object { $_ -gt 0 })
  if ($h.Count -eq 0) { return 0 }
  return [int](($h | Measure-Object -Minimum).Minimum)
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
  # Nulls filtered (D00 T02 section 55): a result with no quarantine
  # block once read as one overdue row, a phantom label on every night.
  try { if (@(@($Result.quarantine.overdue) | Where-Object { $null -ne $_ }).Count -gt 0) { $labels += 'quarantine-overdue' } } catch { }
  return $labels
}

function Format-ToastLines($Items, [string]$ReportPath, [int]$Cap = 7) {
  # The toast body under its cap (item 11): items carry Priority (lower
  # is more urgent) plus Text; the report link always rides last, and a
  # truncated body says how many lines it dropped, so a critical line
  # never falls off behind a routine one. Priority order (docs/testing.md
  # "Alert routing"): 0 fail-closed, 1 escalation, 2 top incident then the
  # recovery status, 3 incident recoveries, 4 overdue quarantine, 5 counts,
  # 6 labels, 7 trigger.
  $sorted = @(@($Items) | Where-Object { $null -ne $_ } | Sort-Object @{ Expression = { [int]$_.Priority } }, @{ Expression = { [int]$_.Order } })
  $room = $Cap - 1
  $body = @()
  if ($sorted.Count -le $room) { $body = @($sorted | ForEach-Object { $_.Text }) }
  else {
    $body = @($sorted | Select-Object -First ($room - 1) | ForEach-Object { $_.Text })
    $body += "+$($sorted.Count - ($room - 1)) more in the report"
  }
  $body += "Report: $ReportPath"
  # One disclosure contract on every channel (D00 T02 section 32 item 14).
  return @($body | ForEach-Object { Protect-DisclosedText $_ })
}

function Get-RecoveryToastItems([string[]]$Notices) {
  # Recovery lines under the toast cap (D00 T02 section 33 R3-I1): the
  # recovery status (service recovery, pending acknowledgements, open
  # corrective actions) rides at priority 2 right after the top incident,
  # so the cap drops individual incident recoveries (priority 3) first and
  # never a GREEN's triage status.
  # The three status statements travel as ONE toast line (R4-I1), so the
  # cap keeps or drops them together and a GREEN never shows without its
  # triage status; the report keeps them as separate lines.
  $items = @()
  $status = @(@($Notices) | Where-Object { "$_" -match '^(Service recovered|Service flapping|Service GREEN on a different test population|Partial recovery|Pending acknowledgement|Open corrective actions):' })
  if ($status.Count -gt 0) { $items += New-ToastItem 2 ($status -join '; ') 1 }
  $o3 = 0
  foreach ($n in @(@($Notices) | Where-Object { "$_" -notmatch '^(Service recovered|Service flapping|Service GREEN on a different test population|Partial recovery|Pending acknowledgement|Open corrective actions):' })) { $items += New-ToastItem 3 "$n" $o3; $o3++ }
  return $items
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
    [switch]$NoPersist, [int]$LockTimeoutSeconds = 60,
    [string]$Kind = '', [string[]]$Labels = @(), [string]$Slot = '',
    [scriptblock]$Escalate = { param($t, $l) Send-NightlyEscalation $t $l }
  )
  # Section 55: -Kind gives an operational event its own identity beside
  # the result's (item 2: a failure after the result landed is never a
  # duplicate of the result's own notification, even on a GREEN);
  # -Labels routes over every label (item 7); -Slot records the night
  # slot for supersession and the digest's lifecycle check (items 6 and
  # 10); the title is kept lock-screen safe (item 16).
  $Title = Protect-LockScreenTitle $Title
  # -NoPersist (dry runs, R1-F1) decides and reports but writes no
  # ledger, queue, or undelivered state, so a rehearsal can never
  # suppress the real notification as a duplicate.
  $out = [pscustomobject]@{ Status = ''; Attempts = 0; Notes = @(); Key = '' }
  if ($Phase -ne 'final') { $out.Status = 'skipped'; $out.Notes += "not a final publication ($Phase)"; return $out }
  $sha = 'noresult'
  if (($ResultPath -ne '') -and (Test-Path $ResultPath)) { $sha = Get-FileSha256 $ResultPath }
  $key = "$RunId|$sha|v$($script:NotifyVersion)"
  if ($Kind -ne '') { $key += "|$Kind" }
  $dk = Get-NotifyDedupKey $key
  $out.Key = $key
  $null = New-Item -ItemType Directory -Force -Path $StateDir
  return (Invoke-WithNotifyLock -TimeoutSeconds $LockTimeoutSeconds -Body {
  $ledgerPath = Join-Path $StateDir 'notify-ledger.json'
  $ledger = @(Read-JsonState $ledgerPath @())
  # The send-versus-record crash window (D00 T02 section 33 item 5): an
  # immediate send first records a `sending` intent, then sends, then
  # records the outcome. An intent left behind means a crash between the
  # send and its record (or before the send): the retry sends again,
  # marked as a possible duplicate, so recovery never loses an alert and
  # never claims exactly-once. A recorded fallback that was never sent is
  # the undelivered file the reconciler re-sends.
  # The duplicate check compares keys without the notification version
  # (section 55 item 18), so a version bump never re-notifies a result.
  $intent = @($ledger | Where-Object { ((Get-NotifyDedupKey "$($_.key)") -eq $dk) -and ("$($_.status)" -eq 'sending') })
  if (@($ledger | Where-Object { ((Get-NotifyDedupKey "$($_.key)") -eq $dk) -and ("$($_.status)" -ne 'sending') }).Count -gt 0) { $out.Status = 'duplicate'; $out.Notes += "already notified for $dk"; return $out }
  $possibleDup = $intent.Count -gt 0
  $ledger = @($ledger | Where-Object { -not (((Get-NotifyDedupKey "$($_.key)") -eq $dk) -and ("$($_.status)" -eq 'sending')) })
  $route = if (@($Labels).Count -gt 0) { Get-CombinedRoute $Class $Labels } else { Get-AlertRoute $Class }
  $entry = [pscustomobject]@{ key = $key; run = $RunId; class = $Class; channel = $route.Channel; severity = $route.Severity; at = $Now.ToString('o'); status = ''; slot = $Slot; visibility = '' }
  if ($route.Channel -eq 'none') {
    $out.Status = 'skipped'; $out.Notes += "class $Class routes nowhere"
  } elseif ($route.Channel -eq 'digest') {
    $qPath = Join-Path $StateDir 'digest-queue.json'
    # A corrupt queue is moved aside, never overwritten (section 55 item 9).
    $rq = if ($NoPersist) { [pscustomobject]@{ Items = @(Read-JsonState $qPath @()); Quarantined = '' } } else { Read-NotifyQueue $qPath $Now }
    if ($rq.Quarantined -ne '') { $out.Notes += "digest queue unreadable: moved aside to $(Split-Path -Leaf $rq.Quarantined) (kept for repair)" }
    $q = @($rq.Items)
    # A crash between the queue write and the ledger write left this key
    # queued already (section 33 item 5): it is not queued twice.
    if (@($q | Where-Object { (Get-NotifyDedupKey "$($_.key)") -eq $dk }).Count -eq 0) { $q += [pscustomobject]@{ key = $key; run = $RunId; class = $Class; title = $Title; lines = @($Lines); at = $Now.ToString('o'); slot = $Slot } } else { $out.Notes += 'already queued (a crash before its record); not queued twice' }
    if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json @($q) -Depth 6) $qPath }
    $out.Status = 'queued'; $out.Notes += "queued for the morning digest ($Class, SLA $($route.SlaHours)h, owner $($route.Owner))"
  } else {
    # The intent carries its payload (R1-I1), so the morning reconciler
    # can re-send an alert whose run crashed before or during the send,
    # whatever stamp a later run carries.
    if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json @(@($ledger) + @([pscustomobject]@{ key = $key; run = $RunId; class = $Class; channel = $route.Channel; severity = $route.Severity; at = $Now.ToString('o'); status = 'sending'; title = $Title; lines = @($Lines) })) -Depth 6) $ledgerPath }
    $sendTitle = if ($possibleDup) { "$Title (possible duplicate)" } else { $Title }
    if ($possibleDup) { $out.Notes += 'a send intent was left by an interrupted run: re-sent, marked possible duplicate' }
    $ok = $false
    for ($i = 0; ($i -le $Retries) -and (-not $ok); $i++) {
      $out.Attempts++
      try { $ok = [bool](& $Sender $sendTitle $Lines) } catch { $ok = $false; $out.Notes += "attempt $($out.Attempts) threw: $($_.Exception.Message)" }
    }
    if (-not $NoPersist) { Update-DeliveryRecord $StateDir $Now $ok }
    # Sent means the toast API accepted it (section 55 item 11): operator
    # visibility stays unconfirmed until an acknowledgement is the evidence.
    if ($ok) { $out.Status = 'sent'; $entry.visibility = 'unconfirmed'; $out.Notes += "accepted by the toast API after $($out.Attempts) attempt(s) (operator visibility unconfirmed)" }
    else {
      $uDir = Join-Path $StateDir 'undelivered'
      $null = New-Item -ItemType Directory -Force -Path $uDir
      # Named by run plus a hash of the whole key (R3-F1): two failed
      # notifications for different results of one run keep two files.
      $safe = ($RunId -replace '[^A-Za-z0-9-]', '-') + '-' + (Get-StringHash $key)
      $payload = [pscustomobject]@{ key = $key; run = $RunId; class = $Class; severity = $route.Severity; title = $Title; lines = @($Lines); failedAt = $Now.ToString('o'); attempts = $out.Attempts }
      if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json $payload -Depth 6) (Join-Path $uDir "$safe.json") }
      # Critical and high escalate now (section 55 R1-I1).
      if (-not $NoPersist) { $out.Notes += @(Invoke-UrgentEscalation -StateDir $StateDir -Now $Now -Escalate $Escalate | ForEach-Object { "$_".TrimStart('-', ' ') }) }
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

function Update-DeliveryRecord([string]$StateDir, [datetime]$Now, [bool]$Ok) {
  # Toast delivery outcomes as events (D00 T02 section 33 item 4, R1-C1):
  # each failed send's timestamp and the last successful send's
  # timestamp, in build/nightly/delivery-record.json, under the notify
  # lock (R1-A2; the mutex is re-entrant, so callers already holding it
  # nest safely). Consecutive failing nights are counted from the
  # failures after the last success, so a success early on a night never
  # hides that night's later failures, and the record survives the
  # undelivered files being re-sent and removed.
  $null = Invoke-WithNotifyLock -Body {
    $p = Join-Path $StateDir 'delivery-record.json'
    $rec = Read-JsonState $p ([pscustomobject]@{ failures = @(); lastSuccessAt = ''; escalated = '' })
    # One entry per night holding that night's LATEST failure (R2-A1):
    # any number of failed re-sends on one night can never push an
    # earlier night out of the record, and comparing each night's latest
    # failure with the last success still orders the events.
    $byNight = [ordered]@{}
    foreach ($f in @($(try { $rec.failures } catch { @() }))) {
      $fa = [datetimeoffset]::MinValue
      if (-not [datetimeoffset]::TryParse("$f", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$fa)) { continue }
      $nk = Get-NightKey $fa.DateTime
      if ((-not $byNight.Contains($nk)) -or ($fa -gt [datetimeoffset]::Parse($byNight[$nk], [System.Globalization.CultureInfo]::InvariantCulture))) { $byNight[$nk] = "$f" }
    }
    $last = "$(try { $rec.lastSuccessAt } catch { '' })"
    $stamp = $Now.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Ok) { $last = $stamp } else { $byNight[(Get-NightKey $Now)] = $stamp }
    $kept = @($byNight.Keys | Sort-Object | Select-Object -Last 60 | ForEach-Object { $byNight[$_] })
    $o = [pscustomobject]@{ failures = $kept; lastSuccessAt = $last; escalated = "$(try { $rec.escalated } catch { '' })" }
    Write-AtomicReport @(ConvertTo-Json $o -Depth 4) $p
  }
}

function Invoke-DeliveryEscalation {
  # The independent escalation channel (D00 T02 section 33 item 4). The
  # toast fallback is deferred delivery (the undelivered set the morning
  # reconciler re-sends); when toasts fail on two consecutive nights with
  # no successful send since, the episode escalates once through a
  # channel that does not use the toast API ($Escalate; the default
  # writes a file on the operator's desktop). Recorded default
  # 2026-09-26: a desktop file, because every other local channel either
  # shares the toast stack or needs a credential; the cost of changing is
  # one sender scriptblock. The read, the send, and the record run under
  # the notify lock, so two reconcilers never escalate one episode twice
  # (R1-A2), and a dry run (-NoPersist) plans only: it never calls the
  # channel (R1-A1). Returns Lines.
  param([string]$StateDir, [datetime]$Now = (Get-Date), [scriptblock]$Escalate = { param($t, $l) Send-NightlyEscalation $t $l }, [switch]$NoPersist)
  return @(Invoke-WithNotifyLock -Body {
    $p = Join-Path $StateDir 'delivery-record.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $rec = Read-JsonState $p ([pscustomobject]@{ failures = @(); lastSuccessAt = ''; escalated = '' })
    $lastAt = [datetimeoffset]::MinValue
    $ls = "$(try { $rec.lastSuccessAt } catch { '' })"
    if ($ls -ne '') { $null = [datetimeoffset]::TryParse($ls, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$lastAt) }
    $nights = @()
    foreach ($f in @($(try { $rec.failures } catch { @() }))) {
      $fa = [datetimeoffset]::MinValue
      if (-not [datetimeoffset]::TryParse("$f", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$fa)) { continue }
      if ($fa -gt $lastAt) { $nights += (Get-NightKey $fa.DateTime) }
    }
    $nights = @($nights | Sort-Object -Unique)
    $pair = ''
    for ($i = 1; $i -lt $nights.Count; $i++) {
      $d = [datetime]::ParseExact($nights[$i - 1], 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
      if ($d.AddDays(1).ToString('yyyy-MM-dd') -eq $nights[$i]) { $pair = "$($nights[$i - 1])..$($nights[$i])"; break }
    }
    if ($pair -eq '') { return @() }
    $episode = $nights[0]
    if ("$(try { $rec.escalated } catch { '' })" -eq $episode) { return @("- Delivery escalation: already sent for the episode from $episode (toasts failing since; consecutive nights $pair)") }
    if ($NoPersist) { return @("- Delivery escalation: would escalate the episode from $episode through the independent channel (dry run: not sent; consecutive failing nights $pair)") }
    $title = "ScratchPad nightly: notifications failing since $episode"
    $body = @("Toast notifications failed on consecutive nights ($pair) with no delivered toast since $(if ($ls -ne '') { $ls } else { 'the record began' }).", "Undelivered notifications wait in build/nightly/undelivered and the morning reconciler keeps re-sending them.", "Read build/nightly/morning-reconcile.log and the latest build/nightly/morning-*.md.")
    $ok = $false
    try { $ok = [bool](& $Escalate $title $body) } catch { $ok = $false }
    if ($ok) { $rec | Add-Member -NotePropertyName escalated -NotePropertyValue $episode -Force; Write-AtomicReport @(ConvertTo-Json $rec -Depth 4) $p }
    else { $fb = Add-EscalationFallback $StateDir $title $body $Now; return @("- Delivery escalation: FAILED through the independent channel for the episode from $episode (consecutive failing nights $pair); fallback $fb") }
    return @("- Delivery escalation: sent through the independent channel for the episode from $episode (consecutive failing nights $pair)")
  })
}

function Send-NightlyEscalation([string]$Title, [string[]]$Lines) {
  # The default independent channel: a text file on the operator's
  # desktop, written atomically, which needs neither the toast API nor
  # a credential. Returns $true when written.
  $desk = [Environment]::GetFolderPath('Desktop')
  if ("$desk" -eq '') { return $false }
  Write-AtomicReport (@($Title, '') + @($Lines)) (Join-Path $desk 'ScratchPad nightly - notifications failing.txt')
  return $true
}

function Get-MorningDeliveryLines([string]$StateDir, [datetime]$Now = (Get-Date), [scriptblock]$Escalate = { param($t, $l) Send-NightlyEscalation $t $l }, [switch]$NoPersist) {
  # What the morning reconciler records after its re-send (section 33
  # item 6): the delivery health (every still-undelivered notification by
  # name) and the escalation outcome, so a persistently failing toast is
  # read in build/nightly/morning-reconcile.log without any toast.
  # Elapsed-time escalation by severity joins it (section 55 item 12).
  return @(@((Get-DeliveryHealth $StateDir $Now).Lines) + @(Invoke-DeliveryEscalation -StateDir $StateDir -Now $Now -Escalate $Escalate -NoPersist:$NoPersist) + @(Invoke-UrgentEscalation -StateDir $StateDir -Now $Now -Escalate $Escalate -NoPersist:$NoPersist))
}

function Get-DeliveryHealth([string]$StateDir, [datetime]$Now = (Get-Date), [int]$StaleQueueHours = 26) {
  # Delivery-health escalation (item 3): every undelivered notification
  # is named in every report until the reconciler delivers it, and a
  # digest queue older than a day means the reconciler is not flushing
  # (R1-F6). Returns Ok, Count, and Lines.
  $uDir = Join-Path $StateDir 'undelivered'
  $files = @(Get-ChildItem $uDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $stale = @()
  $extra = @()
  $qn = 0
  try {
    foreach ($e in @(Read-JsonState (Join-Path $StateDir 'digest-queue.json') @())) {
      if ($null -eq $e) { continue }
      $qn++
      $at = [datetime]::MinValue
      if ([datetime]::TryParse("$($e.at)", [ref]$at) -and (($Now - $at).TotalHours -gt $StaleQueueHours)) { $stale += "$($e.run)" }
    }
  } catch { $stale += 'digest queue unreadable' }
  # Section 55 items 9 and 12: a queue moved aside as corrupt, a queue
  # past its capacity, and an escalation the independent channel could
  # not send stay RED in every report until the operator clears them.
  foreach ($cq in @(Get-ChildItem -LiteralPath $StateDir -Filter 'digest-queue.json.corrupt-*' -File -ErrorAction SilentlyContinue | Sort-Object Name)) { $extra += "- Delivery RED: corrupt digest queue kept as $($cq.Name); repair or delete it (its entries were never flushed)" }
  if ($qn -gt $script:DigestQueueCap) { $extra += "- Delivery RED: digest queue over capacity ($qn > $($script:DigestQueueCap)); the reconciler is not flushing" }
  if (Test-Path -LiteralPath (Join-Path $StateDir 'ESCALATION-UNSENT.md')) { $extra += '- Delivery RED: the independent escalation channel failed; read build/nightly/ESCALATION-UNSENT.md, then delete it' }
  # Healthy means the toast API accepted every send (section 55 item
  # 11), never that a human saw it.
  if (($files.Count -eq 0) -and ($stale.Count -eq 0) -and ($extra.Count -eq 0)) { return [pscustomobject]@{ Ok = $true; Count = 0; Lines = @('- Delivery: healthy (no undelivered notifications; every send was accepted by the toast API, operator visibility unconfirmed until acknowledged)') } }
  $lines = @($extra)
  if ($stale.Count -gt 0) { $lines += "- Delivery RED: digest queue stale past ${StaleQueueHours}h ($($stale -join ', ')); escalate operator (the morning reconciler is not flushing)" }
  if ($files.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Count = $stale.Count + $extra.Count; Lines = $lines } }
  $lines += "- Delivery RED: $($files.Count) undelivered notification(s); escalate operator (toast channel failing)"
  foreach ($f in $files) {
    $age = ''
    try { $p = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; $age = " (failed $($p.failedAt), $($p.attempts) attempt(s), class $($p.class))" } catch { $age = ' (unreadable payload)' }
    $lines += "  - undelivered/$($f.Name)$age"
  }
  return [pscustomobject]@{ Ok = $false; Count = $files.Count; Lines = $lines }
}

function Read-NightlyEnrollment([string]$Path) {
  # The recorded enrollment night (D00 T02 §24 redesign review): the
  # `Enrolled: YYYY-MM-DD` line in docs/nightly-schedule-history.md, the
  # night governed results began, written by provisioning when it
  # registers the nightly task. '' when absent.
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  foreach ($ln in (Get-Content -LiteralPath $Path -Encoding UTF8)) { $m = [regex]::Match($ln, '^Enrolled:\s*(\d{4}-\d{2}-\d{2})\s*$'); if ($m.Success) { return $m.Groups[1].Value } }
  return ''
}

function Get-NoStartVerdict($Results, [datetime]$Now, [string]$ExpectBy = '06:50', [int]$LookbackDays = 7, [string]$EnrolledSince = '', $Schedule = $null, $Starts = $null, [scriptblock]$IsAlive = $null) {
  # The independent no-start check (item 4): a night counts as started
  # only by a governed result (timer- or demand-launched, not simulated,
  # not a stood-down loser) or a supervisor tombstone. Every night in
  # the lookback whose window has closed without one is missed (R2-F5:
  # a logon days later still reports the nights it slept through, not
  # only today), so the reconciler alerts each missed date once.
  # Returns NoStart, Missed (dates), and Line.
  # Enrollment (live false alarm 2026-09-25 07:05): nights before the
  # first governed result predate result capture, so they are never
  # reported as missed; only nights from that first result on count.
  $enrolled = $null
  foreach ($r in @($Results)) {
    if ($null -eq $r) { continue }
    $sim0 = $false
    try { $sim0 = [bool]$r.simulated } catch { }
    if ((@('timer', 'demand') -contains "$($r.launch)") -and (-not $sim0)) {
      $d0 = Get-ResultNight $r
      if (($d0 -match '^\d{4}-\d{2}-\d{2}$') -and (($null -eq $enrolled) -or ([string]::CompareOrdinal($d0, $enrolled) -lt 0))) { $enrolled = $d0 }
    }
  }
  # A recorded enrollment counts even with no result at all (the §24
  # redesign review): a task that was provisioned but never started is
  # the no-start this check exists for, so it cannot wait for a first
  # result to enroll.
  if (($EnrolledSince -match '^\d{4}-\d{2}-\d{2}$') -and (($null -eq $enrolled) -or ([string]::CompareOrdinal($EnrolledSince, $enrolled) -lt 0))) { $enrolled = $EnrolledSince }
  $started = @{}
  foreach ($r in @($Results)) {
    if ($null -eq $r) { continue }
    $sim = $false
    try { $sim = [bool]$r.simulated } catch { }
    $gov = (@('timer', 'demand') -contains "$($r.launch)") -and (-not $sim) -and ("$($r.verdict)" -ne 'stood-down')
    $tomb = ("$($r.trigger)" -like 'supervisor tombstone*')
    if ($gov -or $tomb) { $started[(Get-ResultNight $r)] = $true }
  }
  # Section 55 items 3 and 4: a paused or skipped night (the recorded
  # schedule) is owed no run and reads excused, and each missed night
  # names its start state from durable start evidence.
  $missed = @(); $excused = @(); $states = [ordered]@{}
  for ($i = $LookbackDays; $i -ge 0; $i--) {
    $d = $Now.Date.AddDays(-$i)
    $ds = $d.ToString('yyyy-MM-dd')
    $by = [datetime]::ParseExact("$ds $ExpectBy", 'yyyy-MM-dd HH:mm', $null)
    if ($Now -lt $by) { continue }
    if (($null -eq $enrolled) -or ([string]::CompareOrdinal($ds, $enrolled) -lt 0)) { continue }
    if ($started.ContainsKey($ds)) { continue }
    $ex = Get-ExcusedNight $ds $Schedule
    if ($ex -ne '') { $excused += "$ds $ex"; continue }
    $missed += $ds
    $states[$ds] = if ($null -eq $Starts) { 'never-started' } elseif ($null -ne $IsAlive) { Get-NightStartState $ds @($started.Keys) $Starts $Now -IsAlive $IsAlive } else { Get-NightStartState $ds @($started.Keys) $Starts $Now }
  }
  $exTail = if ($excused.Count -gt 0) { "; excused: $($excused -join ', ')" } else { '' }
  if ($missed.Count -eq 0) {
    $today = $Now.ToString('yyyy-MM-dd')
    $todayBy = [datetime]::ParseExact("$today $ExpectBy", 'yyyy-MM-dd HH:mm', $null)
    $tail = if ($Now -lt $todayBy) { "; today waits for $ExpectBy" } else { '' }
    return [pscustomobject]@{ NoStart = $false; Missed = @(); States = $states; Excused = $excused; Line = "every closed night in the last $LookbackDays day(s) started$tail$exTail" }
  }
  return [pscustomobject]@{ NoStart = $true; Missed = $missed; States = $states; Excused = $excused; Line = "NO START: no governed nightly result for $(@($missed | ForEach-Object { "$_ ($($states[$_]))" }) -join ', ') (check the task is enabled and fires; run the manual backup)$exTail" }
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
  # Section 55 item 10: with -Canonical (Select-CanonicalRuns over the
  # current results) each entry reconciles against the lifecycle first
  # (current, recovered since, or stale), and the digest opens with a
  # current-state summary and the triage link. Item 9: a corrupt queue is
  # moved aside, never lost, and entries an interrupted flush may already
  # have sent are marked possible duplicates one by one.
  param([string]$StateDir, [string]$Day, [scriptblock]$Sender, [int]$Retries = 2, [switch]$NoPersist, [datetime]$Now = (Get-Date), $Canonical = $null, $Results = @(), [string]$TriageLink = '')
  return (Invoke-WithNotifyLock -Body {
    $out = [pscustomobject]@{ Status = 'empty'; Count = 0; Attempts = 0; Notes = @(); DigestPath = ''; Duplicates = @(); States = [ordered]@{} }
    $qPath = Join-Path $StateDir 'digest-queue.json'
    $rq = if ($NoPersist) { [pscustomobject]@{ Items = @(@(Read-JsonState $qPath @()) | Where-Object { $null -ne $_ }); Quarantined = '' } } else { Read-NotifyQueue $qPath $Now }
    if ($rq.Quarantined -ne '') { $out.Notes += "digest queue unreadable: moved aside to $(Split-Path -Leaf $rq.Quarantined) (kept for repair)" }
    $queue = @($rq.Items)
    if ($queue.Count -eq 0) { $out.Notes += 'nothing queued'; return $out }
    $out.Count = $queue.Count
    # One file per flush (R2-F4): a later flush the same day never
    # overwrites an earlier digest a delivered toast already points at.
    $flushId = "$Day-$($Now.ToString('HHmmss'))"
    $dPath = Join-Path $StateDir "digest-$flushId.md"
    $k = 1
    while (Test-Path $dPath) { $k++; $flushId = "$Day-$($Now.ToString('HHmmss'))-$k"; $dPath = Join-Path $StateDir "digest-$flushId.md" }
    $out.DigestPath = $dPath
    # The digest's crash window (D00 T02 section 33 R4-A1, section 55
    # item 9): an in-flight record naming the queued keys is written
    # before the send and removed after the queue clears. Every entry a
    # leftover record names may already have been sent, so it is marked a
    # possible duplicate even when the queue only overlaps that flush.
    $inflight = Join-Path $StateDir 'digest-inflight.json'
    $priorKeys = @()
    $prior = $null
    try { $prior = Read-JsonState $inflight $null } catch { $prior = [pscustomobject]@{ keys = '*' } }
    if ($null -ne $prior) { $priorKeys = @("$($prior.keys)" -split "`n" | Where-Object { $_ -ne '' }) }
    $dups = @($queue | Where-Object { ($priorKeys -contains '*') -or ($priorKeys -contains "$($_.key)") } | ForEach-Object { "$($_.key)" })
    $out.Duplicates = $dups
    $counts = [ordered]@{ current = 0; recovered = 0; stale = 0 }
    foreach ($e in $queue) { $s = Get-QueuedEntryState $e $Canonical $Results; $out.States["$($e.key)"] = $s; $counts[$s.State]++ }
    $failing = @($queue | Where-Object { ($out.States["$($_.key)"].State -eq 'current') -and ("$($_.class)" -ne 'green') }).Count
    $summary = "Current state: $failing failing now, $($counts.recovered) recovered since, $($counts.stale) stale$(if ($TriageLink -ne '') { "; triage: $TriageLink" })"
    $md = @("# Nightly digest: $Day", '', "$($queue.Count) routine notification(s), queued by the nightly for the morning digest (D00 T02 s24).", '', "- $summary", '')
    foreach ($e in $queue) {
      $s = $out.States["$($e.key)"]
      $tag = if ($s.State -ne 'current') { " [$($s.State): $($s.Note)]" } else { '' }
      $dtag = if ($dups -contains "$($e.key)") { ' (possible duplicate)' } else { '' }
      $md += "## $($e.title)$tag$dtag"; $md += ''; $md += "- Run: $($e.run) (class $($e.class), queued $($e.at))"; foreach ($l in @($e.lines)) { $md += "- $(Update-EvidenceLinks "$l" $StateDir)" }; $md += ''
    }
    $dg = Format-Digest $queue $Day
    $lines = @($summary) + @($dg.Lines) + @("Digest: build/nightly/digest-$flushId.md")
    if (-not $NoPersist) { Write-AtomicReport $md $dPath }
    $dupTitle = $dg.Title
    if ($dups.Count -gt 0) { $dupTitle = if ($dups.Count -eq $queue.Count) { "$($dg.Title) (possible duplicate)" } else { "$($dg.Title) (possible duplicate: $($dups.Count) of $($queue.Count))" }; $out.Notes += "an earlier flush was interrupted after its send: $($dups.Count) entr(ies) marked possible duplicate" }
    if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json ([pscustomobject]@{ keys = (@($queue | ForEach-Object { "$($_.key)" } | Sort-Object) -join "`n"); at = $Now.ToString('o') })) $inflight }
    $ok = $false
    for ($i = 0; ($i -le $Retries) -and (-not $ok); $i++) {
      $out.Attempts++
      try { $ok = [bool](& $Sender $dupTitle $lines) } catch { $ok = $false; $out.Notes += "attempt $($out.Attempts) threw: $($_.Exception.Message)" }
    }
    if (-not $NoPersist) { Update-DeliveryRecord $StateDir $Now $ok }
    if ($ok) { $out.Status = 'sent'; $out.Notes += "accepted by the toast API: $($queue.Count) queued notification(s) after $($out.Attempts) attempt(s) (operator visibility unconfirmed)" }
    else {
      $out.Status = 'fallback'
      $uDir = Join-Path $StateDir 'undelivered'
      $payload = [pscustomobject]@{ key = "digest-$flushId"; run = "digest-$flushId"; class = 'digest'; title = $dg.Title; lines = $lines; failedAt = $Now.ToString('o'); attempts = $out.Attempts }
      if (-not $NoPersist) { $null = New-Item -ItemType Directory -Force -Path $uDir; Write-AtomicReport @(ConvertTo-Json $payload -Depth 6) (Join-Path $uDir "digest-$flushId.json") }
      $out.Notes += "digest delivery failed after $($out.Attempts) attempt(s); fallback undelivered/digest-$flushId.json, the full digest stays in digest-$flushId.md"
    }
    if (-not $NoPersist) { Write-AtomicReport @('[]') $qPath; Remove-Item -LiteralPath $inflight -Force -ErrorAction SilentlyContinue } else { $out.Notes += 'dry run: no state written' }
    return $out
  })
}

function Invoke-UndeliveredResend {
  # Re-sends every undelivered notification (item 3, R2-F1) with the
  # read, the send, and the delete all under the notify lock, so two
  # reconcilers never send one payload twice and a producer never has a
  # newer payload deleted between the read and the delete. Returns
  # Lines (one per payload).
  param([string]$StateDir, [scriptblock]$Sender, [switch]$NoPersist)
  return (Invoke-WithNotifyLock -Body {
    $lines = @()
    foreach ($u in @(Get-ChildItem (Join-Path $StateDir 'undelivered') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
      try {
        $raw = [System.IO.File]::ReadAllText($u.FullName)
        $p = $raw | ConvertFrom-Json
        # The re-send's crash window (section 33 R4-A1): the payload is
        # stamped before the send, so a crash after the send and before the
        # delete makes the next re-send say it may be a duplicate.
        $wasResending = "$(try { $p.resendingAt } catch { '' })" -ne ''
        if (-not $NoPersist) { $p | Add-Member -NotePropertyName resendingAt -NotePropertyValue ((Get-Date).ToString('o')) -Force; Write-AtomicReport @(ConvertTo-Json $p -Depth 6) $u.FullName }
        $ok = [bool](& $Sender "$($p.title) (re-sent$(if ($wasResending) { ', possible duplicate' }))" @($p.lines))
        if (-not $NoPersist) { Update-DeliveryRecord $StateDir (Get-Date) $ok }
        if ($ok) {
          if (-not $NoPersist) { Remove-Item -LiteralPath $u.FullName -Force }
          $lines += "undelivered $($u.Name): re-sent$(if ($NoPersist) { ' (dry run: kept)' })"
        } else { $lines += "undelivered $($u.Name): still failing" }
      } catch { $lines += "undelivered $($u.Name): unreadable or failed: $($_.Exception.Message)" }
    }
    # A send intent left in the ledger (D00 T02 section 33 R1-I1) is a run
    # that crashed before or during its send: every send holds this lock,
    # so an intent seen here is never in flight. It is re-sent marked as
    # a possible duplicate and recorded sent, or it joins the undelivered
    # set as a fallback.
    $lp = Join-Path $StateDir 'notify-ledger.json'
    $ledger = @(@(Read-JsonState $lp @()) | Where-Object { $null -ne $_ })
    $changed = $false
    foreach ($e in @($ledger | Where-Object { "$($_.status)" -eq 'sending' })) {
      if ("$($e.title)" -eq '') { $lines += "intent $($e.key): no payload recorded (written before intents carried one); cannot re-send, escalate operator"; continue }
      $ok = $false
      try { $ok = [bool](& $Sender "$($e.title) (possible duplicate)" @($e.lines)) } catch { $ok = $false }
      if ($NoPersist) { $lines += "intent $($e.key): $(if ($ok) { 're-sent' } else { 'still failing' }) (dry run: kept)"; continue }
      Update-DeliveryRecord $StateDir (Get-Date) $ok
      if ($ok) { $e.status = 'sent'; $lines += "intent $($e.key): re-sent, marked possible duplicate" }
      else {
        $uDir = Join-Path $StateDir 'undelivered'
        $null = New-Item -ItemType Directory -Force -Path $uDir
        $safe = ("$($e.run)" -replace '[^A-Za-z0-9-]', '-') + '-' + (Get-StringHash "$($e.key)")
        Write-AtomicReport @(ConvertTo-Json ([pscustomobject]@{ key = "$($e.key)"; run = "$($e.run)"; class = "$($e.class)"; severity = "$(try { $e.severity } catch { '' })"; title = "$($e.title) (possible duplicate)"; lines = @($e.lines); failedAt = (Get-Date).ToString('o'); attempts = 1 }) -Depth 6) (Join-Path $uDir "$safe.json")
        $e.status = 'fallback'; $lines += "intent $($e.key): still failing; fallback undelivered/$safe.json"
      }
      $changed = $true
    }
    if ($changed) { Write-AtomicReport @(ConvertTo-Json @($ledger) -Depth 6) $lp }
    return $lines
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
  return [pscustomobject]@{ Title = $title; Lines = @($lines | ForEach-Object { Protect-DisclosedText $_ }) }
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
    $rg = $null
    try { $rg = $leg.gate } catch { }
    if ($gm.Success) {
      if (($null -eq $rg) -or ([int]$rg -ne [int]$gm.Groups[1].Value)) { $breaks += "$key gate: report exit $($gm.Groups[1].Value) vs result $rg" }
    } elseif ($null -ne $rg) {
      # A gate the result recorded must read as its exit code (R2-F3).
      $breaks += "$key gate: report '$($m.Groups[5].Value.Trim())' vs result $rg"
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
  # Soak names reconcile both ways (R2-F3): every FAILED, killed, or
  # budget-cut row the report prints is backed by the result's lists,
  # and every name the result lists appears in the report's soak rows.
  $soakRows = @()
  $inSoak = $false
  foreach ($ln in $ReportLines) {
    if ("$ln" -eq '## Soak') { $inSoak = $true; continue }
    if ($inSoak -and ("$ln" -like '## *')) { break }
    if ($inSoak) { $sm = [regex]::Match("$ln", '^- ((?:ui|protocol)-soak-[\d.]+) : (.*)$'); if ($sm.Success) { $soakRows += [pscustomobject]@{ Name = $sm.Groups[1].Value; Text = $sm.Groups[2].Value } } }
  }
  $rf = @(); $rk = @(); $rc = @()
  try { $rf = @($Result.soak.failed | Where-Object { $_ -is [string] }) } catch { }
  try { $rk = @($Result.soak.killed | Where-Object { $_ -is [string] }) } catch { }
  try { $rc = @($Result.soak.cut | Where-Object { $_ -is [string] }) } catch { }
  foreach ($row in $soakRows) {
    # Every failure form the ledger prints, not only FAILED (R4-F1).
    if (($row.Text -match '\(FAILED\)|nonzero exit|failed without trx') -and ($rf -notcontains $row.Name)) { $breaks += "soak $($row.Name): report failed ('$($row.Text)'), result failed list lacks it" }
    if (($row.Text -like '*killed at cap*') -and ($rk -notcontains $row.Name)) { $breaks += "soak $($row.Name): report killed, result killed list lacks it" }
    if (($row.Text -like 'budget-cut*') -and ($rc -notcontains $row.Name)) { $breaks += "soak $($row.Name): report budget-cut, result cut list lacks it" }
  }
  $rowNames = @($soakRows | ForEach-Object { $_.Name })
  foreach ($nm in @($rf + $rk + $rc)) { if ($rowNames -notcontains $nm) { $breaks += "soak ${nm}: result lists it, report soak rows omit it" } }
  # The row must say what the result says (R3-F2): a failed iteration
  # reads FAILED, nonzero exit, or failed without trx; a killed one
  # reads killed at cap; a cut one reads budget-cut.
  foreach ($row in $soakRows) {
    if (($rf -contains $row.Name) -and ($row.Text -notmatch '\(FAILED\)|nonzero exit|failed without trx')) { $breaks += "soak $($row.Name): result failed, report row reads '$($row.Text)'" }
    if (($rk -contains $row.Name) -and ($row.Text -notlike '*killed at cap*')) { $breaks += "soak $($row.Name): result killed, report row reads '$($row.Text)'" }
    if (($rc -contains $row.Name) -and ($row.Text -notlike 'budget-cut*')) { $breaks += "soak $($row.Name): result cut, report row reads '$($row.Text)'" }
  }
  $tm = @($ReportLines | ForEach-Object { [regex]::Match("$_", '^- Timings: .*reserve=(-?\d+)s') } | Where-Object { $_.Success }) | Select-Object -First 1
  if ($null -ne $tm) {
    $tr = $null
    try { $tr = [int]$Result.reserve } catch { }
    if ($tr -ne [int]$tm.Groups[1].Value) { $breaks += "timings reserve: report $($tm.Groups[1].Value)s vs result $tr" }
  }
  # Environment (R1-F3): every field, from one line the run prints off
  # the same object it writes to the JSON.
  $envKeys = @('os', 'powershell', 'dotnet', 'session', 'topology', 'dpi', 'adapters', 'settings')
  $envLine = @($ReportLines | Where-Object { "$_" -like '- Environment: *' }) | Select-Object -First 1
  if ($null -eq $envLine) { $breaks += 'environment: report carries no Environment line' }
  else {
    # Fields ride ' | ' in a fixed key order: values such as topology
    # carry '; ' themselves, so the separator is not ';', and a value
    # that ever carried ' | ' changes the field count and breaks loud.
    $parts = @("$envLine".Substring(15) -split ' \| ')
    if ($parts.Count -ne $envKeys.Count) { $breaks += "environment: report has $($parts.Count) fields, want $($envKeys.Count) ($($envKeys -join ', '))" }
    else {
      for ($i = 0; $i -lt $envKeys.Count; $i++) {
        $k = $envKeys[$i]
        $want = ''
        try { $want = "$($Result.env.$k)" } catch { }
        $part = $parts[$i]
        if (($part -ne $k) -and (-not $part.StartsWith("$k "))) { $breaks += "environment ${k}: report field $($i + 1) reads '$part'"; continue }
        $got = if ($part -eq $k) { '' } else { $part.Substring($k.Length + 1) }
        if ($got -ne $want) { $breaks += "environment ${k}: report '$got' vs result '$want'" }
      }
    }
  }
  $xm = @($ReportLines | ForEach-Object { [regex]::Match("$_", '^- Exit: (\d+)$') } | Where-Object { $_.Success }) | Select-Object -First 1
  if ($null -eq $xm) { $breaks += 'exit: report carries no Exit line' }
  else {
    $rx = $null
    try { $rx = [int]$Result.exit } catch { }
    if ($rx -ne [int]$xm.Groups[1].Value) { $breaks += "exit: report $($xm.Groups[1].Value) vs result $rx" }
  }
  # Section 55 item 14: every result field is covered, so schema growth
  # cannot bypass the check.
  $breaks += @(Test-AgreementCoverage $Result)
  return [pscustomobject]@{ Ok = ($breaks.Count -eq 0); Breaks = $breaks }
}

function Get-NightVoice($Canonical, $Current) {
  # One night identity for the notification and the trend (D00 T02
  # section 33 item 1): the night slot key and the canonical run come
  # from Select-CanonicalRuns, the same selection the trend renders, so a
  # retry, a cancellation, or a second scheduled run can never make the
  # two surfaces speak for different runs. Returns Slot, Canonical (the
  # id that speaks for the night), and IsVoice.
  $slot = Get-NightSlotKey $Current
  $curId = "$($Current.identity)"
  if ($curId -eq '') { $curId = "$($Current.stamp)" }
  $can = if ($Canonical.ContainsKey($slot)) { "$($Canonical[$slot].Canonical)" } else { '' }
  return [pscustomobject]@{ Slot = $slot; Canonical = $can; IsVoice = ($can -eq $curId) }
}

function Get-RecoveryNotices($Canonical, $Results, $Current, [string[]]$LedgerLines, $AckGate = $null) {
  # Recovery notices (item 13): a canonical night that turns GREEN after
  # a RED canonical night says so, and every incident the §22 ledger
  # closed on verified recovery rides the notification by id.
  $notices = @()
  # The shared night key (D00 T02 section 32 item 1): the canonical map
  # is keyed by night slot (night plus host, section 40 item 1), so the
  # lookup is too, and the previous night is the same host's.
  $day = Get-NightSlotKey $Current
  $hostSuffix = '|' + (Get-ResultHostKey $Current)
  $curId = "$($Current.identity)"
  if ($curId -eq '') { $curId = "$($Current.stamp)" }
  # Only the night's canonical run speaks for the night (R1-F4): a GREEN
  # manual retry after a RED timer run is not a recovered night.
  $isCanonicalNow = $Canonical.ContainsKey($day) -and ($Canonical[$day].Canonical -eq $curId)
  $prev = @($Canonical.Keys | Where-Object { ($_.EndsWith($hostSuffix)) -and ([string]::CompareOrdinal($_, $day) -lt 0) } | Sort-Object -Descending) | Select-Object -First 1
  if ($isCanonicalNow -and ($null -ne $prev) -and ("$($Current.verdict)" -eq 'green')) {
    $pid0 = $Canonical[$prev].Canonical
    # The previous night's run is this host's (section 40 R4-F4):
    # an identity two hosts share resolves to the one on this host.
    $pr = @(@($Results) | Where-Object { (("$($_.identity)" -eq $pid0) -or ("$($_.stamp)" -eq $pid0)) -and ((Get-ResultHostKey $_) -eq (Get-ResultHostKey $Current)) }) | Select-Object -First 1
    if (($null -ne $pr) -and (@('red', 'cancelled') -contains "$($pr.verdict)")) {
      # Recovery reads comparable evidence and names flapping (section 55
      # item 15): a GREEN on a different test population is no recovery,
      # and a service that keeps changing verdict reads flapping.
      $pp = "$(try { $pr.populationIdentity } catch { '' })"; $cp = "$(try { $Current.populationIdentity } catch { '' })"
      $flap = Get-FlapState $Canonical $Results $Current
      if (($pp -ne '') -and ($cp -ne '') -and ($pp -ne $cp)) { $notices += "Service GREEN on a different test population: night $($prev.Split('|')[0]) was $($pr.verdict.ToString().ToUpper()) on another population (not comparable; not a recovery)" }
      elseif ($flap.Flapping) { $notices += "Service flapping: $($day.Split('|')[0]) is GREEN after $($prev.Split('|')[0]) was $($pr.verdict.ToString().ToUpper()), $($flap.Changes) verdict changes in the last $($flap.Nights) nights (not recovered)" }
      else { $notices += "Service recovered: night $($prev.Split('|')[0]) was $($pr.verdict.ToString().ToUpper()), $($day.Split('|')[0]) is GREEN" }
    }
  }
  # Partial recovery (section 55 item 15): a RED night after a RED night
  # names the previous incidents that no longer fail and those that still do.
  if ($isCanonicalNow -and ($null -ne $prev) -and ("$($Current.verdict)" -eq 'red')) {
    $pid1 = $Canonical[$prev].Canonical
    $pr1 = @(@($Results) | Where-Object { (("$($_.identity)" -eq $pid1) -or ("$($_.stamp)" -eq $pid1)) -and ((Get-ResultHostKey $_) -eq (Get-ResultHostKey $Current)) }) | Select-Object -First 1
    $pp1 = "$(try { $pr1.populationIdentity } catch { '' })"; $cp1 = "$(try { $Current.populationIdentity } catch { '' })"
    if (($null -ne $pr1) -and ("$($pr1.verdict)" -eq 'red') -and ($pp1 -ne '') -and ($cp1 -ne '') -and ($pp1 -ne $cp1)) { $notices += "Partial recovery: not comparable: night $($prev.Split('|')[0]) ran another test population, so no incident reads recovered from it" }
    elseif (($null -ne $pr1) -and ("$($pr1.verdict)" -eq 'red')) {
      $was = @(Get-ResultIncidentIds $pr1); $now1 = @(Get-ResultIncidentIds $Current)
      $gone = @($was | Where-Object { $now1 -notcontains $_ }); $still = @($was | Where-Object { $now1 -contains $_ })
      if (($gone.Count -gt 0) -and ($now1.Count -gt 0)) { $notices += "Partial recovery: $($gone.Count) of $($was.Count) incident(s) from night $($prev.Split('|')[0]) no longer fail ($($gone -join ', ')); still failing: $(if ($still.Count -gt 0) { $still -join ', ' } else { 'none of the earlier ones' })" }
    }
  }
  # An incident closed while the service flaps says so (section 55
  # R1-C2): its recovery is verified for its own test, not a stable night.
  $flapNow = $false
  try { $flapNow = (Get-FlapState $Canonical $Results $Current).Flapping } catch { }
  foreach ($ln in @($LedgerLines)) {
    $m = [regex]::Match("$ln", '^- (INC-[0-9a-f]{8}) `([^`]+)`: CLOSED')
    if ($m.Success) { $notices += "Recovered: $($m.Groups[1].Value) $($m.Groups[2].Value) (closed on verified recovery$(if ($flapNow) { '; the service is flapping, so this is not a stable recovery' }))" }
  }
  # A GREEN never implies completed triage (D00 T02 section 33 item 7):
  # a recovery notice states the acknowledgements still pending and the
  # corrective actions still open, each on its own line.
  if (($notices.Count -gt 0) -and ($null -ne $AckGate)) {
    $un = @(@($AckGate.Unacked) | Where-Object { "$_" -ne '' })
    $notices += $(if ($un.Count -gt 0) { "Pending acknowledgement: $($un.Count) RED run(s) still unacknowledged ($($un -join ', '))" } else { 'Pending acknowledgement: none' })
    $open = @(@($AckGate.Corrective) | Where-Object { ("$_" -match ': open') -or ("$_" -match ': OVERDUE') })
    $notices += $(if ($open.Count -gt 0) { "Open corrective actions: $($open.Count) ($(@($open | ForEach-Object { ("$_" -replace '^- CORRECTIVE ', '') -replace ':.*$', '' }) -join '; '))" } else { 'Open corrective actions: none' })
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

# ---------------------------------------------------------------------
# D00 T02 section 55: the notify redesign residuals. Pure where it can
# be; every mechanism below has its own fixture in
# tools/NightlyNotify.Tests.ps1 (the s55-* cases).
# ---------------------------------------------------------------------

# Stamps from this one on publish a generation manifest (item 1); older
# runs predate it and are never "repaired" into a recovered report.
$script:GenerationSince = '2026-09-27'
# Severity order for combined routing (item 7) and the elapsed-time
# escalation bounds in hours (item 12): a critical alert escalates at
# its first failed delivery; info never escalates. No scheduler checks
# more often than the nightly and the 07:05 reconciler, so critical and
# high escalate at their first failed delivery wherever it happens
# (section 55 R1-I1); medium and low wait for a later reconcile.
$script:SeverityRank = @{ 'critical' = 4; 'high' = 3; 'medium' = 2; 'low' = 1; 'info' = 0 }
$script:EscalateAfterHours = @{ 'critical' = 0; 'high' = 0; 'medium' = 24; 'low' = 72 }
# Notify-state retention and capacity (item 9). Dedup records outlive
# every retry path (the reconciler looks back 7 days), so a pruned key is
# never re-sent by a retry; undelivered payloads are never pruned.
$script:NotifyLedgerRetentionDays = 90
$script:NotifyLedgerCap = 5000
# Records this recent are never pruned for capacity (section 55 R3-I1):
# twice the reconciler's 7-day lookback, so no eligible result's record
# can go and replay its alert.
$script:NotifyLedgerProtectDays = 14
$script:DigestFileRetentionDays = 60
$script:DigestQueueCap = 500
# A flapping service (item 15): this many verdict changes inside the
# window of canonical nights reads flapping, not recovered.
$script:FlapWindowNights = 6
$script:FlapChanges = 3

function Get-NotifyDedupKey([string]$Key) {
  # The notification version rides the key (the payload shape) but never
  # decides a duplicate (section 55 item 18): a version bump re-notifies
  # nothing a run already delivered for the same result.
  return ($Key -replace '\|v\d+(?=\||$)', '')
}

function Get-CombinedRoute([string]$Class, [string[]]$Labels = @()) {
  # One route over every label a night carries (section 55 item 7): the
  # channel is immediate when any label routes immediately, the severity
  # and the accountable owner come from the strictest label (severity,
  # then the shortest SLA, then precedence order), and the SLA is the
  # shortest positive one, so a secondary critical failure never inherits
  # the title class's slower route. Owners lists every owner; one
  # acknowledgement by any listed owner closes the alert for every
  # recipient, and the accountable owner answers for the deadline.
  $names = @(@(@($Class) + @($Labels)) | Where-Object { "$_" -ne '' } | Select-Object -Unique)
  $routes = @($names | ForEach-Object { Get-AlertRoute $_ })
  $live = @($routes | Where-Object { $_.Channel -ne 'none' })
  $ackRule = 'one acknowledgement by any listed owner closes it for every recipient; the accountable owner answers for the deadline'
  if ($live.Count -eq 0) {
    $r = Get-AlertRoute $Class
    return [pscustomobject]@{ Class = $Class; Lead = $Class; Owner = $r.Owner; Owners = @($r.Owner); Channel = $r.Channel; Severity = $r.Severity; SlaHours = $r.SlaHours; Ack = $ackRule }
  }
  $lead = @($live | Sort-Object @{ Expression = { -1 * [int]$script:SeverityRank["$($_.Severity)"] } }, @{ Expression = { if ([int]$_.SlaHours -gt 0) { [int]$_.SlaHours } else { 99999 } } }, @{ Expression = { [array]::IndexOf($names, "$($_.Class)") } })[0]
  $channel = if (@($live | Where-Object { $_.Channel -eq 'immediate' }).Count -gt 0) { 'immediate' } else { 'digest' }
  $slas = @($live | ForEach-Object { [int]$_.SlaHours } | Where-Object { $_ -gt 0 })
  $sla = if ($slas.Count -gt 0) { [int](($slas | Measure-Object -Minimum).Minimum) } else { 0 }
  $owners = @($live | ForEach-Object { "$($_.Owner)" } | Where-Object { $_ -ne 'none' } | Select-Object -Unique)
  return [pscustomobject]@{ Class = $Class; Lead = "$($lead.Class)"; Owner = "$($lead.Owner)"; Owners = $owners; Channel = $channel; Severity = "$($lead.Severity)"; SlaHours = $sla; Ack = $ackRule }
}

function Get-AlertTaxonomy {
  # The current class taxonomy (section 55 item 17), derived from the
  # routing table itself: every class and the distinct routes (owner,
  # channel, severity, SLA) they share. §24 and §33 name this function
  # instead of a hand count, so the plan and the code read one taxonomy.
  $routes = [ordered]@{}
  foreach ($c in @($script:AlertClasses.Keys)) {
    $r = $script:AlertClasses[$c]
    $k = "$($r.Owner) | $($r.Channel) | $($r.Severity) | $($r.SlaHours)h"
    if (-not $routes.Contains($k)) { $routes[$k] = @() }
    $routes[$k] += $c
  }
  return [pscustomobject]@{ Classes = @($script:AlertClasses.Keys); Routes = $routes }
}

function Test-LockScreenSafe([string]$Title) {
  # A toast title shows on the lock screen (section 55 item 16), so it
  # never names test content: no test class, source file, qualified
  # method, or local path. Incident ids are opaque hashes and stay.
  return (-not ($Title -match '\b[A-Z]\w*Tests\b|\.cs\b|\b\w+\.\w+\.\w+\(|[A-Za-z]:\\|\\\\'))
}

function Protect-LockScreenTitle([string]$Title) {
  # An unsafe title is replaced by its safe prefix plus "details on
  # unlock"; the body keeps the detail.
  if (Test-LockScreenSafe $Title) { return $Title }
  $m = [regex]::Match($Title, '^(Nightly(?: trend)? \S+ :)')
  $head = if ($m.Success) { $m.Groups[1].Value } else { 'Nightly :' }
  return "$head details on unlock"
}

function Write-NightlyGeneration([string]$NightDir, [string]$Stamp) {
  # One committed generation (section 55 item 1): once the run's result
  # and its stamp-scoped report have both landed, a manifest names the
  # pair by checksum. It is written last and atomically, so its presence
  # proves both files, and a republished report rewrites it. Returns the
  # manifest path, or '' when either file is missing.
  $res = Join-Path $NightDir "morning-$Stamp.result.json"
  $rep = Join-Path $NightDir "morning-$Stamp.md"
  if (-not ((Test-Path -LiteralPath $res -PathType Leaf) -and (Test-Path -LiteralPath $rep -PathType Leaf))) { return '' }
  $m = [pscustomobject]@{ schema = 'generation/1'; stamp = $Stamp; result = (Get-FileSha256 $res); report = (Get-FileSha256 $rep); at = (Get-Date).ToString('o') }
  $p = Join-Path $NightDir "morning-$Stamp.generation.json"
  Write-AtomicReport @(ConvertTo-Json $m) $p
  return $p
}

function Test-NightlyGeneration([string]$NightDir, [string]$Stamp) {
  # The generation's state: committed, no-result, missing-report,
  # no-manifest (a crash between the report and its manifest), stale
  # (the result was revised after the manifest), or report-changed (the
  # report differs from the one the manifest names; the nightly rewrites
  # the manifest after each republish, so a difference is a crash in that
  # window or a damaged report, and it is never linked: section 55 R1-A1).
  $res = Join-Path $NightDir "morning-$Stamp.result.json"
  $rep = Join-Path $NightDir "morning-$Stamp.md"
  $man = Join-Path $NightDir "morning-$Stamp.generation.json"
  if (-not (Test-Path -LiteralPath $res -PathType Leaf)) { return 'no-result' }
  if (-not (Test-Path -LiteralPath $rep -PathType Leaf)) { return 'missing-report' }
  if (-not (Test-Path -LiteralPath $man -PathType Leaf)) { return 'no-manifest' }
  $m = $null
  # An unreadable manifest proves nothing (section 55 R2-A1): it reads
  # manifest-unreadable, alerts link the result, and repair leaves it.
  try { $m = Get-Content -LiteralPath $man -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { return 'manifest-unreadable' }
  if ("$($m.schema)" -ne 'generation/1') { return 'manifest-unreadable' }
  if ("$($m.result)" -ne (Get-FileSha256 $res)) { return 'stale' }
  if ("$($m.report)" -ne (Get-FileSha256 $rep)) { return 'report-changed' }
  return 'committed'
}

function Resolve-NotifyReportLink([string]$NightDir, [string]$Stamp, [string]$Since = $script:GenerationSince) {
  # The report link an alert may carry (section 55 item 1): the
  # stamp-scoped report only when its generation is committed (or the run
  # predates manifests); otherwise the result itself, which always
  # exists for a notified run, so an alert never links a missing or
  # mismatched report. Returns Link, State, and Note.
  $st = Test-NightlyGeneration $NightDir $Stamp
  $rep = "build/nightly/morning-$Stamp.md"
  $res = "build/nightly/morning-$Stamp.result.json"
  if ($st -eq 'committed') { return [pscustomobject]@{ Link = $rep; State = $st; Note = '' } }
  if (($st -eq 'no-manifest') -and ([string]::CompareOrdinal($Stamp, $Since) -lt 0)) { return [pscustomobject]@{ Link = $rep; State = 'legacy'; Note = '' } }
  if ($st -eq 'no-result') { return [pscustomobject]@{ Link = $rep; State = $st; Note = 'no result landed' } }
  return [pscustomobject]@{ Link = $res; State = $st; Note = "report generation $st; linking the result" }
}

function Format-RecoveredReport($Result, [string]$Stamp, [string]$State) {
  # A report rebuilt from a landed result whose report never landed
  # (section 55 item 1). It says it is recovered and carries only what the
  # result records.
  $v = "$($Result.verdict)".ToUpper()
  $md = @("# Morning report (recovered): $Stamp", 'Status: recovered-from-result', '', "- Recovered: the run's report did not land ($State); rebuilt from morning-$Stamp.result.json by the morning reconciler (D00 T02 section 55 item 1)", "- Verdict: $v", "- Exit: $($Result.exit)")
  foreach ($leg in @('run-a', 'run-b', 'interactive')) {
    $g = $null
    try { $g = $Result.legs.$leg } catch { }
    if ($null -ne $g) { $md += "- ${leg}: $($g.passed) passed, $($g.failed) failed, $($g.skipped) skipped" }
  }
  $inc = @(@($(try { $Result.incidents } catch { @() })) | Where-Object { "$_" -ne '' })
  if ($inc.Count -gt 0) { $md += @('', '## Incidents', '') + @($inc | ForEach-Object { "$_" }) }
  return $md
}

function Repair-NightlyGenerations([string]$NightDir, [datetime]$Now, [string]$Since = $script:GenerationSince, [int]$SettleMinutes = 30, [switch]$NoPersist) {
  # Interrupted publications are recovered, never stranded (section 55
  # item 1, D00-T02-S33-PR5): for every result from $Since on that has
  # settled, a missing report is rebuilt from the result and its manifest
  # written; a report left without its manifest is committed (the run
  # wrote both from one result); a result revised after its manifest
  # keeps its report untouched and links the result instead. A
  # stamp-scoped report with no result is an orphan, moved to orphans/.
  # Returns Lines and Recovered (the stamps whose report was rebuilt).
  # Notification eligibility is decided apart from repair
  # (Get-UnnotifiedResults, R1-A2), so a crash after a repair never
  # strands a result.
  $lines = @(); $recovered = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $NightDir -Filter 'morning-*.result.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $m = [regex]::Match($f.Name, '^morning-(\d{4}-\d{2}-\d{2}-\d{6})\.result\.json$')
    if (-not $m.Success) { continue }
    $stamp = $m.Groups[1].Value
    if ([string]::CompareOrdinal($stamp, $Since) -lt 0) { continue }
    if (($Now - $f.LastWriteTime).TotalMinutes -lt $SettleMinutes) { continue }
    $st = Test-NightlyGeneration $NightDir $stamp
    if ($st -eq 'committed') { continue }
    if ($st -eq 'report-changed') { $lines += "generation ${stamp}: report differs from its generation; alerts link the result, the report is kept for inspection"; continue }
    if ($st -eq 'missing-report') {
      $r = $null
      try { $r = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { $lines += "generation ${stamp}: report missing and the result is unreadable; left for the corruption record"; continue }
      if (-not $NoPersist) { Write-AtomicReport (Format-RecoveredReport $r $stamp $st) (Join-Path $NightDir "morning-$stamp.md"); $null = Write-NightlyGeneration $NightDir $stamp }
      $recovered += $stamp
      $lines += "generation ${stamp}: report missing; rebuilt from the result$(if ($NoPersist) { ' (dry run: not written)' })"
    } elseif ($st -eq 'no-manifest') {
      # The pair commits only when the report agrees with the result
      # field by field (section 55 R3-A1), the same check the run itself
      # applies, so a mismatched report never gains a manifest.
      $ag = $null
      try { $ag = Test-ReportResultAgreement @(Get-Content -LiteralPath (Join-Path $NightDir "morning-$stamp.md") -Encoding UTF8) (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch { $ag = $null }
      if (($null -ne $ag) -and $ag.Ok) {
        if (-not $NoPersist) { $null = Write-NightlyGeneration $NightDir $stamp }
        $lines += "generation ${stamp}: manifest missing after both files landed; report agrees with the result; committed"
      } else {
        $lines += "generation ${stamp}: manifest missing and the report does not agree with the result$(if ($null -ne $ag) { " ($(@($ag.Breaks)[0]))" }); alerts link the result, nothing committed"
      }
    } elseif ($st -eq 'manifest-unreadable') {
      $lines += "generation ${stamp}: manifest unreadable; alerts link the result and the files are left for inspection"
    } elseif ($st -eq 'stale') {
      $lines += "generation ${stamp}: result revised after its report; alerts link the result, the report is kept as it was"
    }
  }
  foreach ($f in @(Get-ChildItem -LiteralPath $NightDir -Filter 'morning-*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $m = [regex]::Match($f.Name, '^morning-(\d{4}-\d{2}-\d{2}-\d{6})\.md$')
    if (-not $m.Success) { continue }
    $stamp = $m.Groups[1].Value
    if ([string]::CompareOrdinal($stamp, $Since) -lt 0) { continue }
    if (($Now - $f.LastWriteTime).TotalMinutes -lt $SettleMinutes) { continue }
    if (Test-Path -LiteralPath (Join-Path $NightDir "morning-$stamp.result.json")) { continue }
    if (-not $NoPersist) {
      $od = Join-Path $NightDir 'orphans'
      $null = New-Item -ItemType Directory -Force -Path $od
      Move-Item -LiteralPath $f.FullName -Destination (Join-Path $od $f.Name) -Force
    }
    $lines += "generation ${stamp}: report without a result moved to orphans/$($f.Name) (no alert links it)"
  }
  return [pscustomobject]@{ Lines = $lines; Recovered = $recovered }
}

function Get-UnnotifiedResults([string]$NightDir, $Results, [datetime]$Now, [string]$Since = $script:GenerationSince, [int]$SettleMinutes = 30, [int]$LookbackDays = 7, $Starts = $null, [scriptblock]$IsAlive = { param($p, $s) Test-JournalProcessAlive $p $s }) {
  # Every settled, non-simulated result from $Since on whose run the
  # notify ledger never recorded (section 55 R1-A2): a run that crashed
  # before its notification, whatever state its report generation is in,
  # stays eligible until the ledger records it, so neither a repair nor a
  # crash after one strands an urgent result. Only the final publication
  # writes morning-<stamp>.result.json (the pre-soak core publication
  # writes -core reports only), so a landed result is final; a run whose
  # start evidence shows it still alive is still publishing and waits
  # (R2-I1). Only results inside the reconciler's lookback count, far
  # inside the ledger's 90-day retention, so a pruned record never
  # replays an old alert (R2-I2). Returns the results.
  $out = @()
  foreach ($r in @($Results)) {
    if ($null -eq $r) { continue }
    $stamp = "$($r.stamp)"
    if (($stamp -notmatch '^\d{4}-\d{2}-\d{2}-\d{6}$') -or ([string]::CompareOrdinal($stamp, $Since) -lt 0)) { continue }
    if ([bool]$(try { $r.simulated } catch { $false })) { continue }
    $f = Join-Path $NightDir "morning-$stamp.result.json"
    if (-not (Test-Path -LiteralPath $f)) { continue }
    if (($Now - (Get-Item -LiteralPath $f).LastWriteTime).TotalMinutes -lt $SettleMinutes) { continue }
    $sd = [datetime]::ParseExact($stamp.Substring(0, 10), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($sd -lt $Now.Date.AddDays(-$LookbackDays)) { continue }
    $live = $false
    foreach ($se in @(@($Starts) | Where-Object { ($null -ne $_) -and ("$($_.stamp)" -eq $stamp) })) {
      $sst = [datetime]::MinValue
      if ($se.started -is [datetime]) { $sst = $se.started } else { $null = [datetime]::TryParse("$($se.started)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$sst) }
      try { if ([bool](& $IsAlive ([int]$se.pid) $sst)) { $live = $true } } catch { }
    }
    if ($live) { continue }
    $id = "$($r.identity)"; if ($id -eq '') { $id = $stamp }
    if (-not (Test-RunNotified $NightDir $id)) { $out += $r }
  }
  return $out
}

function Test-RunNotified([string]$StateDir, [string]$RunId) {
  # True when the notify ledger holds any settled entry for the run.
  $lp = Join-Path $StateDir 'notify-ledger.json'
  $l = @()
  try { $l = @(Read-JsonState $lp @()) } catch { return $true }
  return (@($l | Where-Object { ("$($_.run)" -eq $RunId) -and ("$($_.status)" -ne 'sending') }).Count -gt 0)
}

function Add-StartEvidence([string]$NightDir, [string]$Stamp, [int]$ProcId, [datetime]$Started, [bool]$Scheduled, [bool]$Simulated) {
  # Durable start evidence (section 55 item 3): one JSON line per run in
  # build/nightly/starts.jsonl, appended at launch before any leg runs,
  # so the no-start check can tell a run that never started from one
  # that started and died, hangs, or is still running.
  $o = [pscustomobject]@{ stamp = $Stamp; pid = $ProcId; started = $Started.ToString('o'); night = (Get-NightKey $Started); scheduled = $Scheduled; simulated = $Simulated }
  Add-Content -LiteralPath (Join-Path $NightDir 'starts.jsonl') -Value (ConvertTo-Json $o -Compress) -Encoding UTF8
}

function Read-StartEvidence([string]$NightDir) {
  # The start records; an unreadable line is skipped and counted.
  $p = Join-Path $NightDir 'starts.jsonl'
  $rows = @(); $bad = 0
  if (Test-Path -LiteralPath $p) {
    foreach ($ln in [System.IO.File]::ReadAllLines($p)) {
      if ("$ln".Trim() -eq '') { continue }
      try { $rows += ($ln | ConvertFrom-Json -ErrorAction Stop) } catch { $bad++ }
    }
  }
  return [pscustomobject]@{ Rows = $rows; Unreadable = $bad }
}

function Get-NightStartState([string]$Night, [string[]]$StartedNights, $Starts, [datetime]$Now, [int]$HangHours = 6, [scriptblock]$IsAlive = { param($p, $s) Test-JournalProcessAlive $p $s }) {
  # A night's start state (section 55 item 3): completed (a governed
  # result or tombstone), still-running (a live start within the hang
  # bound), hung (a live start past it), started-without-result (a dead
  # start with no result), or never-started (no start evidence at all).
  # Simulated starts are not evidence.
  if (@($StartedNights) -contains $Night) { return 'completed' }
  # A manual start is no evidence the schedule fired (section 55 R1-C1):
  # only scheduler-launched starts count, so a manual run on a night the
  # task never started keeps it never-started (the scheduler's route).
  $mine = @(@($Starts) | Where-Object { ($null -ne $_) -and ("$($_.night)" -eq $Night) -and (-not [bool]$_.simulated) -and ("$($_.scheduled)" -ne 'False') })
  if ($mine.Count -eq 0) { return 'never-started' }
  $last = @($mine | Sort-Object { "$($_.started)" })[-1]
  $st = [datetime]::MinValue
  $sv = $last.started
  if ($sv -is [datetime]) { $st = $sv } else { $null = [datetime]::TryParse("$sv", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$st) }
  $alive = $false
  try { $alive = [bool](& $IsAlive ([int]$last.pid) $st) } catch { $alive = $false }
  if ($alive) { if (($Now - $st).TotalHours -lt $HangHours) { return 'still-running' } else { return 'hung' } }
  return 'started-without-result'
}

function Read-NightlySchedule([string]$Path) {
  # The recorded schedule (section 55 item 4) in
  # docs/nightly-schedule-history.md: `Enrolled: D`, `Paused: D1..D2
  # <reason>` (inclusive), and `Skipped: D <reason>`. A paused or skipped
  # night is owed no run, so the no-start check never invents a miss for
  # it. The operator writes these lines (and D00 T09's Pause and Skip
  # controls will when they land). Returns Enrolled, Pauses, Skips.
  $out = [pscustomobject]@{ Enrolled = ''; Pauses = @(); Skips = @() }
  if (-not (Test-Path -LiteralPath $Path)) { return $out }
  foreach ($ln in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^Enrolled:\s*(\d{4}-\d{2}-\d{2})\s*$'); if ($m.Success -and ($out.Enrolled -eq '')) { $out.Enrolled = $m.Groups[1].Value; continue }
    $m = [regex]::Match($ln, '^Paused:\s*(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})\s*(.*)$'); if ($m.Success) { $out.Pauses += [pscustomobject]@{ From = $m.Groups[1].Value; To = $m.Groups[2].Value; Reason = $m.Groups[3].Value.Trim() }; continue }
    $m = [regex]::Match($ln, '^Skipped:\s*(\d{4}-\d{2}-\d{2})\s*(.*)$'); if ($m.Success) { $out.Skips += [pscustomobject]@{ Night = $m.Groups[1].Value; Reason = $m.Groups[2].Value.Trim() } }
  }
  return $out
}

function Get-ExcusedNight([string]$Night, $Schedule) {
  # 'paused (<reason>)', 'skipped (<reason>)', or '' for an owed night.
  if ($null -eq $Schedule) { return '' }
  foreach ($p in @($Schedule.Pauses)) { if (([string]::CompareOrdinal($Night, $p.From) -ge 0) -and ([string]::CompareOrdinal($Night, $p.To) -le 0)) { return "paused ($($p.Reason))" } }
  foreach ($s in @($Schedule.Skips)) { if ($s.Night -eq $Night) { return "skipped ($($s.Reason))" } }
  return ''
}

function Get-SupersessionCorrection($Canonical, $Results, $Current, $LedgerEntries) {
  # Supersession (section 55 item 6, D00-T02-S33-PR7): when this run
  # speaks for its night and another run of the same night slot was
  # already notified, the notice names the superseding verdict. The rules
  # it states: the earlier run's acknowledgement demand, its deadline,
  # and its incidents stand (a correction never erases owed triage); this
  # run's own RED demands its own acknowledgement as any RED does; the
  # correction itself demands none (acknowledgements are per RED run,
  # never per notice). Returns the lines ('' entries never).
  $voice = Get-NightVoice $Canonical $Current
  if (-not $voice.IsVoice) { return @() }
  $curId = "$($Current.identity)"; if ($curId -eq '') { $curId = "$($Current.stamp)" }
  $prior = @()
  foreach ($e in @($LedgerEntries)) {
    if (($null -eq $e) -or ("$($e.status)" -eq 'sending')) { continue }
    $run = "$($e.run)"
    if (($run -eq '') -or ($run -eq $curId) -or ($prior -contains $run)) { continue }
    # Scoped to this run's host (section 55 R3-C1): hosts may share an id.
    $curHost = Get-ResultHostKey $Current
    $r = @(@($Results) | Where-Object { (("$($_.identity)" -eq $run) -or ("$($_.stamp)" -eq $run)) -and ((Get-ResultHostKey $_) -eq $curHost) }) | Select-Object -First 1
    $eSlot = "$(try { $e.slot } catch { '' })"
    if (($eSlot -eq '') -and ($null -ne $r)) { $eSlot = Get-NightSlotKey $r }
    if ($eSlot -eq $voice.Slot) { $prior += $run }
  }
  if ($prior.Count -eq 0) { return @() }
  $night = $voice.Slot.Split('|')[0]
  $cv = "$($Current.verdict)".ToUpper()
  $lines = @()
  foreach ($p in $prior) {
    $r = @(@($Results) | Where-Object { (("$($_.identity)" -eq $p) -or ("$($_.stamp)" -eq $p)) -and ((Get-ResultHostKey $_) -eq (Get-ResultHostKey $Current)) }) | Select-Object -First 1
    $pv = if ($null -ne $r) { "$($r.verdict)".ToUpper() } else { 'UNKNOWN' }
    $lines += "Correction: $curId ($cv) supersedes $p ($pv) as the verdict for night $night"
    if (@('RED', 'CANCELLED') -contains $pv) { $lines += "Earlier $p stays owed: its acknowledgement, deadline, and incidents stand (a correction never erases triage)" }
  }
  if (@('RED', 'CANCELLED') -contains $cv) { $lines += "This run's $cv demands its own acknowledgement; the correction itself demands none" } else { $lines += 'The correction itself demands no acknowledgement' }
  return $lines
}

function Read-NotifyQueue([string]$Path, [datetime]$Now) {
  # The digest queue's corruption contract (section 55 item 9): a queue
  # that does not parse is moved aside whole as <name>.corrupt-<stamp>
  # (never overwritten, so nothing is lost) and an empty queue continues;
  # Get-DeliveryHealth names the moved file in every report until the
  # operator repairs it. Returns Items and Quarantined (the moved path).
  try { return [pscustomobject]@{ Items = @(@(Read-JsonState $Path @()) | Where-Object { $null -ne $_ }); Quarantined = '' } }
  catch {
    $aside = "$Path.corrupt-$($Now.ToString('yyyyMMddHHmmss'))"
    Move-Item -LiteralPath $Path -Destination $aside -Force
    return [pscustomobject]@{ Items = @(); Quarantined = $aside }
  }
}

function Invoke-NotifyStateRetention([string]$StateDir, [datetime]$Now, [switch]$NoPersist) {
  # Retention, capacity, and cleanup coordination (section 55 item 9,
  # D00-T02-S33-PR9), under the notify lock: ledger entries older than
  # the retention drop (a `sending` intent never does), then the oldest
  # settled ones past the cap; digest files past their retention drop
  # unless an undelivered payload still names them; undelivered payloads
  # are never pruned (they escalate instead). Returns Lines.
  return @(Invoke-WithNotifyLock -Body {
    $lines = @()
    $lp = Join-Path $StateDir 'notify-ledger.json'
    if (Test-Path -LiteralPath $lp) {
      $l = @(@(Read-JsonState $lp @()) | Where-Object { $null -ne $_ })
      $cut = $Now.AddDays(-$script:NotifyLedgerRetentionDays)
      $keep = @($l | Where-Object { $at = [datetime]::MinValue; ("$($_.status)" -eq 'sending') -or (-not [datetime]::TryParse("$($_.at)", [ref]$at)) -or ($at -ge $cut) })
      if ($keep.Count -gt $script:NotifyLedgerCap) {
        $protect = $Now.AddDays(-$script:NotifyLedgerProtectDays)
        $settled = @($keep | Where-Object { $at = [datetime]::MinValue; ("$($_.status)" -ne 'sending') -and [datetime]::TryParse("$($_.at)", [ref]$at) -and ($at -lt $protect) } | Sort-Object { "$($_.at)" })
        $drop = @($settled | Select-Object -First ($keep.Count - $script:NotifyLedgerCap))
        $keep = @($keep | Where-Object { $drop -notcontains $_ })
        if ($keep.Count -gt $script:NotifyLedgerCap) { $lines += "retention: notify ledger over its cap ($($keep.Count) > $($script:NotifyLedgerCap)); records from the last $($script:NotifyLedgerProtectDays) days are kept" }
      }
      if ($keep.Count -lt $l.Count) {
        $lines += "retention: notify ledger $($l.Count) -> $($keep.Count) entries (older than $($script:NotifyLedgerRetentionDays) days or past the cap of $($script:NotifyLedgerCap))"
        if (-not $NoPersist) { Write-AtomicReport @(ConvertTo-Json @($keep) -Depth 6) $lp }
      }
    }
    $named = ''
    foreach ($u in @(Get-ChildItem (Join-Path $StateDir 'undelivered') -Filter '*.json' -File -ErrorAction SilentlyContinue)) { try { $named += [System.IO.File]::ReadAllText($u.FullName) } catch { } }
    foreach ($d in @(Get-ChildItem -LiteralPath $StateDir -Filter 'digest-*.md' -File -ErrorAction SilentlyContinue)) {
      if (($Now - $d.LastWriteTime).TotalDays -le $script:DigestFileRetentionDays) { continue }
      if ($named -like "*$($d.Name)*") { $lines += "retention: kept $($d.Name) (an undelivered payload still links it)"; continue }
      if (-not $NoPersist) { Remove-Item -LiteralPath $d.FullName -Force }
      $lines += "retention: removed $($d.Name) (older than $($script:DigestFileRetentionDays) days)"
    }
    return $lines
  })
}

function Get-QueuedEntryState($Entry, $Canonical, $Results) {
  # A queued alert against the current lifecycle (section 55 item 10):
  # stale when another run now speaks for its night slot, recovered when
  # a later night of the same host is canonical GREEN, else current. An
  # entry queued before slots were recorded reads current.
  $slot = "$(try { $Entry.slot } catch { '' })"
  if (($slot -eq '') -or ($null -eq $Canonical)) { return [pscustomobject]@{ State = 'current'; Note = '' } }
  $can = if ($Canonical.ContainsKey($slot)) { "$($Canonical[$slot].Canonical)" } else { '' }
  if (($can -ne '') -and ($can -ne "$($Entry.run)")) { return [pscustomobject]@{ State = 'stale'; Note = "superseded by $can" } }
  if ("$($Entry.class)" -eq 'green') { return [pscustomobject]@{ State = 'current'; Note = '' } }
  $hostSuffix = '|' + $slot.Split('|')[1]
  $later = @($Canonical.Keys | Where-Object { $_.EndsWith($hostSuffix) -and ([string]::CompareOrdinal($_, $slot) -gt 0) -and ("$($Canonical[$_].Canonical)" -ne '') } | Sort-Object -Descending) | Select-Object -First 1
  if ($null -ne $later) {
    $lid = "$($Canonical[$later].Canonical)"
    $slotHost = $slot.Split('|')[1]
    $lr = @(@($Results) | Where-Object { (("$($_.identity)" -eq $lid) -or ("$($_.stamp)" -eq $lid)) -and ((Get-ResultHostKey $_) -eq $slotHost) }) | Select-Object -First 1
    if (($null -ne $lr) -and ("$($lr.verdict)" -eq 'green')) {
      # The same comparability and flapping rules as Get-RecoveryNotices
      # (section 55 R2-C1): another population or a flapping service is
      # never a recovery in the digest either.
      $er = @(@($Results) | Where-Object { (("$($_.identity)" -eq "$($Entry.run)") -or ("$($_.stamp)" -eq "$($Entry.run)")) -and ((Get-ResultHostKey $_) -eq $slotHost) }) | Select-Object -First 1
      $ep = if ($null -ne $er) { "$(try { $er.populationIdentity } catch { '' })" } else { '' }
      $lp = "$(try { $lr.populationIdentity } catch { '' })"
      if (($ep -ne '') -and ($lp -ne '') -and ($ep -ne $lp)) { return [pscustomobject]@{ State = 'current'; Note = "night $($later.Split('|')[0]) is GREEN on another test population (not comparable)" } }
      $fs = $null
      try { $fs = Get-FlapState $Canonical $Results $lr } catch { }
      if (($null -ne $fs) -and $fs.Flapping) { return [pscustomobject]@{ State = 'current'; Note = "night $($later.Split('|')[0]) is GREEN but the service is flapping ($($fs.Changes) changes)" } }
      return [pscustomobject]@{ State = 'recovered'; Note = "night $($later.Split('|')[0]) is GREEN ($lid)" }
    }
  }
  return [pscustomobject]@{ State = 'current'; Note = '' }
}

function Invoke-UrgentEscalation {
  # Elapsed-time escalation by severity (section 55 item 12): an
  # undelivered notification whose delivery has failed for its severity's
  # bound (critical and high at once, medium 24 h, low 72 h) escalates
  # once through the independent channel, and the payload records it. A
  # failed escalation channel writes build/nightly/ESCALATION-UNSENT.md,
  # the fallback destination every report names (Get-DeliveryHealth), so
  # it is discoverable without the failing notification path. Returns
  # Lines.
  param([string]$StateDir, [datetime]$Now = (Get-Date), [scriptblock]$Escalate = { param($t, $l) Send-NightlyEscalation $t $l }, [switch]$NoPersist)
  return @(Invoke-WithNotifyLock -Body {
    $lines = @()
    foreach ($u in @(Get-ChildItem (Join-Path $StateDir 'undelivered') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
      $p = $null
      try { $p = [System.IO.File]::ReadAllText($u.FullName) | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ("$(try { $p.escalatedAt } catch { '' })" -ne '') { continue }
      # The effective severity the payload carries (section 55 R1-I2), so a
      # secondary critical label keeps its bound; else the class's.
      $sev = "$(try { $p.severity } catch { '' })"
      if ($sev -eq '') { $sev = (Get-AlertRoute "$($p.class)").Severity }
      if (-not $script:EscalateAfterHours.ContainsKey($sev)) { continue }
      $fa = [datetime]::MinValue
      $fv = $p.failedAt
      if ($fv -is [datetime]) { $fa = $fv } elseif (-not [datetime]::TryParse("$fv", [ref]$fa)) { continue }
      $age = ($Now - $fa).TotalHours
      if ($age -lt $script:EscalateAfterHours[$sev]) { continue }
      if ($NoPersist) { $lines += "- Urgent escalation: would escalate $($u.Name) ($sev, undelivered $([int]$age) h; dry run)"; continue }
      $title = "ScratchPad nightly: $sev notification undelivered"
      $body = @("$($p.title)", "Undelivered for $([int]$age) h (bound $($script:EscalateAfterHours[$sev]) h for $sev).", "Payload: build/nightly/undelivered/$($u.Name)")
      $ok = $false
      try { $ok = [bool](& $Escalate $title $body) } catch { $ok = $false }
      if ($ok) {
        $p | Add-Member -NotePropertyName escalatedAt -NotePropertyValue ($Now.ToString('o')) -Force
        Write-AtomicReport @(ConvertTo-Json $p -Depth 6) $u.FullName
        $lines += "- Urgent escalation: sent for $($u.Name) ($sev, undelivered $([int]$age) h)"
      } else {
        $fb = Add-EscalationFallback $StateDir $title $body $Now
        $lines += "- Urgent escalation: FAILED for $($u.Name) ($sev); fallback $fb"
      }
    }
    return $lines
  })
}

function Add-EscalationFallback([string]$StateDir, [string]$Title, [string[]]$Body, [datetime]$Now) {
  # The escalation channel's own fallback (section 55 item 12): an entry
  # appended to build/nightly/ESCALATION-UNSENT.md (atomic rewrite), which
  # Get-DeliveryHealth names in every report until the operator clears it.
  $p = Join-Path $StateDir 'ESCALATION-UNSENT.md'
  $old = @()
  if (Test-Path -LiteralPath $p) { $old = @(Get-Content -LiteralPath $p -Encoding UTF8) }
  if ($old.Count -eq 0) { $old = @('# Unsent escalations', '', 'The independent escalation channel failed for these; read each, then delete this file (D00 T02 section 55 item 12).', '') }
  Write-AtomicReport (@($old) + @("## $($Now.ToString('yyyy-MM-dd HH:mm')) $Title", '') + @($Body | ForEach-Object { "- $_" }) + @('')) $p
  return 'build/nightly/ESCALATION-UNSENT.md'
}

# Every top-level result field and how the agreement check covers it
# (section 55 item 14): `agreement` (Test-ReportResultAgreement compares
# it with the report), `routing` (Get-OutcomeLabels or the class reads
# it), `link` (the notification links it), or `exempt: <reason>`. A
# field the table does not name fails the agreement, so schema growth
# cannot bypass the check.
$script:ResultFieldCoverage = [ordered]@{
  legs = 'agreement'; incidents = 'agreement'; consumed = 'agreement'; reserve = 'agreement'; soak = 'agreement'; env = 'agreement'; exit = 'agreement'; timings = 'agreement'
  scheduler = 'routing'; buildError = 'routing'; omissionOk = 'routing'; recovered = 'routing'; quarantine = 'routing'; verdict = 'routing'; simulated = 'routing'; launch = 'routing'
  report = 'link'; incidentEvidence = 'link'
  version = 'exempt: schema version'; revision = 'exempt: copy ordering (section 31 item 5)'; identity = 'exempt: run identity keys the notification'; stamp = 'exempt: run identity'; day = 'exempt: night identity'; night = 'exempt: night identity'; startUtc = 'exempt: night identity'; tz = 'exempt: night identity'; hostKey = 'exempt: night identity'; previousStamp = 'exempt: run chain'
  commit = 'exempt: provenance'; harness = 'exempt: provenance'; trigger = 'exempt: provenance'; tree = 'exempt: provenance'; note = 'exempt: free text'
  population = 'exempt: population gate (section 52)'; populationHash = 'exempt: population gate (section 52)'; populationIdentity = 'exempt: population gate (section 52)'; populationState = 'exempt: population gate (section 52)'; executedUnique = 'exempt: population gate (section 52)'; owedCases = 'exempt: population gate (section 52)'; owedIdentities = 'exempt: population gate (section 52)'; eligible = 'exempt: proof binding (section 52)'; proof = 'exempt: proof binding (section 52)'; proofBinding = 'exempt: proof binding (section 52)'; proofSource = 'exempt: proof binding (section 52)'; ciOverride = 'exempt: proof binding (section 52)'
  incidentLifecycle = 'exempt: lifecycle consumer contract (section 38 item 7)'; incidentLifecycleSource = 'exempt: lifecycle consumer contract (section 38 item 7)'; incidentLifecycleVersion = 'exempt: lifecycle consumer contract (section 38 item 7)'
  evidenceCompleteness = 'exempt: rendered from the result itself (section 53 item 12)'
  discovery = 'exempt: shard inventory the trend reads (section 54 item 8)'
}

function Test-AgreementCoverage($Result) {
  # Section 55 item 14: every top-level field of the result is named in
  # $script:ResultFieldCoverage. Returns the breaks (empty when covered).
  $breaks = @()
  if ($null -eq $Result) { return $breaks }
  foreach ($n in @($Result.PSObject.Properties | ForEach-Object { $_.Name })) {
    if (-not $script:ResultFieldCoverage.Contains($n)) { $breaks += "coverage: result field '$n' has no agreement coverage (name it in `$script:ResultFieldCoverage: agreement, routing, link, or exempt with a reason)" }
  }
  return $breaks
}

function Get-FlapState($Canonical, $Results, $Current) {
  # Night-level flapping (section 55 item 15): the canonical verdicts of
  # this host's last $script:FlapWindowNights nights up to the current
  # one; $script:FlapChanges or more green/red changes read flapping.
  # Returns Flapping, Changes, and Nights.
  $slot = Get-NightSlotKey $Current
  $hostSuffix = '|' + (Get-ResultHostKey $Current)
  $keys = @(@($Canonical.Keys | Where-Object { $_.EndsWith($hostSuffix) -and ([string]::CompareOrdinal($_, $slot) -le 0) -and ("$($Canonical[$_].Canonical)" -ne '') } | Sort-Object) | Select-Object -Last $script:FlapWindowNights)
  $vs = @()
  foreach ($k in $keys) {
    $id = "$($Canonical[$k].Canonical)"
    $r = @(@($Results) | Where-Object { ((("$($_.identity)" -eq $id) -or ("$($_.stamp)" -eq $id)) -and ((Get-ResultHostKey $_) -eq (Get-ResultHostKey $Current))) }) | Select-Object -First 1
    if ($null -ne $r) { $vs += $(if ("$($r.verdict)" -eq 'green') { 'g' } else { 'r' }) }
  }
  $changes = 0
  for ($i = 1; $i -lt $vs.Count; $i++) { if ($vs[$i] -ne $vs[$i - 1]) { $changes++ } }
  return [pscustomobject]@{ Flapping = ($changes -ge $script:FlapChanges); Changes = $changes; Nights = $vs.Count }
}

function Get-ResultIncidentIds($Result) {
  $ids = @()
  foreach ($ln in @($(try { $Result.incidents } catch { @() }))) { $m = [regex]::Match("$ln", '(INC-[0-9a-f]{8})'); if ($m.Success -and ($ids -notcontains $m.Groups[1].Value)) { $ids += $m.Groups[1].Value } }
  return $ids
}

function Update-EvidenceLinks([string]$Line, [string]$NightDir) {
  # Every `[evidence: <link>]` in a queued line resolves at flush time
  # (section 55 item 16), so a digest read after relocation still opens.
  return [regex]::Replace($Line, '\[evidence: ([^\]]+)\]', { param($m) "[evidence: $((Resolve-EvidenceLink $m.Groups[1].Value $NightDir).Link)]" })
}

function Resolve-EvidenceLink([string]$Link, [string]$NightDir) {
  # A diagnostic link that survives relocation within retention (section
  # 55 item 16): `<kind> <path>[:<line>]` resolves to the path when it
  # exists, else to the same file under a retained copy
  # (build/nightly/retained/<run>/...), else reads expired. Returns
  # Link and State (present, relocated, expired).
  $m = [regex]::Match($Link, '^(\S+) (.+?)(:\d+)?$')
  if (-not $m.Success) { return [pscustomobject]@{ Link = $Link; State = 'expired' } }
  $kind = $m.Groups[1].Value; $path = $m.Groups[2].Value; $ln = $m.Groups[3].Value
  if (Test-Path -LiteralPath $path) { return [pscustomobject]@{ Link = $Link; State = 'present' } }
  $parts = @($path -split '[\\/]' | Where-Object { $_ -ne '' })
  $tail = if ($parts.Count -ge 2) { Join-Path $parts[-2] $parts[-1] } else { $parts[-1] }
  $ret = Join-Path $NightDir 'retained'
  foreach ($c in @(Get-ChildItem -LiteralPath $ret -Recurse -File -Filter $parts[-1] -ErrorAction SilentlyContinue)) {
    if ($c.FullName.EndsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)) { return [pscustomobject]@{ Link = "$kind $($c.FullName)$ln"; State = 'relocated' } }
  }
  return [pscustomobject]@{ Link = "$kind $path$ln (expired: past retention)"; State = 'expired' }
}
