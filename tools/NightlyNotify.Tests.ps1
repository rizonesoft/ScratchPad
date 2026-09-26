# Notification fixture suite for tools/NightlyNotify.ps1 (D00 T02 §24).
# Self-contained: builds state under TEMP, drives the real functions
# with a stub sender (no toast ever fires), and exits nonzero on any
# failure. One or more cases per item of the section.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
. (Join-Path $PSScriptRoot 'NightlyNotify.ps1')

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
$dir = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-notify-fixtures'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $dir

function New-Result([string]$Day, [string]$Stamp, [string]$Verdict, [string]$Launch, [bool]$Sim = $false, [int]$RunASeconds = 600) {
  $leg = [pscustomobject]@{ ran = $true; passed = 10; failed = 0; skipped = 1; gate = 0; killed = $false; cut = $false; testSeconds = $RunASeconds }
  $legB = [pscustomobject]@{ ran = $true; passed = 4; failed = 0; skipped = 0; gate = 0; killed = $false; cut = $false; testSeconds = 20 }
  $legI = [pscustomobject]@{ ran = $true; passed = 3; failed = 0; skipped = 0; killed = $false; cut = $false; enforcementRed = $false; testSeconds = 100 }
  return [pscustomobject]@{ version = 1; day = $Day; stamp = $Stamp; identity = "$Stamp-pid1"; verdict = $Verdict; exit = $(if ($Verdict -eq 'green') { 0 } else { 1 }); simulated = $Sim; launch = $Launch; trigger = 'x'; buildError = ''; omissionOk = $true; recovered = 'none'; legs = [pscustomobject]@{ 'run-a' = $leg; 'run-b' = $legB; interactive = $legI }; soak = [pscustomobject]@{ verdict = 'green'; failed = 0; killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; incidents = @(); reserve = 900; consumed = 600; env = [pscustomobject]@{ os = '10.0.26200.0'; powershell = '5.1'; dotnet = '10.0.400'; session = 'op/'; topology = 'D1 primary'; dpi = 'primary 96x96'; adapters = 'GPU'; settings = 'BACKGROUND=' } }
}

# Item 2: one canonical run per night on a duplicate-heavy day.
$heavy = @(
  (New-Result '2026-09-23' '2026-09-23-015108' 'red' 'manual' $false 500),
  (New-Result '2026-09-23' '2026-09-23-023011' 'red' 'timer' $false 600),
  (New-Result '2026-09-23' '2026-09-23-040435' 'red' 'manual' $false 3000),
  (New-Result '2026-09-23' '2026-09-23-050000' 'red' 'manual' $true 9999),
  (New-Result '2026-09-23' '2026-09-23-060000' 'stood-down' 'timer'),
  (New-Result '2026-09-24' '2026-09-24-101010' 'green' 'manual' $false 700),
  (New-Result '2026-09-24' '2026-09-24-121212' 'green' 'demand' $false 800)
)
$canon = Select-CanonicalRuns $heavy
Assert ($canon['2026-09-23|legacy'].Canonical -eq '2026-09-23-023011-pid1') 'canonical-timer-wins' $canon['2026-09-23|legacy'].Canonical
Assert ($canon['2026-09-24|legacy'].Canonical -eq '2026-09-24-121212-pid1') 'canonical-demand-beats-manual' $canon['2026-09-24|legacy'].Canonical
Assert (($canon['2026-09-23|legacy'].Others['2026-09-23-050000-pid1'] -eq 'simulation') -and ($canon['2026-09-23|legacy'].Others['2026-09-23-060000-pid1'] -eq 'stood-down loser') -and ($canon['2026-09-23|legacy'].Others['2026-09-23-040435-pid1'] -like 'retry (manual launch*')) 'canonical-others-carry-reasons' (($canon['2026-09-23|legacy'].Others.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')
$trend = @(Format-TrendTable $heavy @{ Overdue = @(); DueSoon = @() } (Get-Date '2026-09-25'))
Assert (@($trend | Where-Object { $_ -like '| 2026-09-23 (retry) |*' }).Count -eq 3) 'canonical-trend-marks-retries' (($trend | Where-Object { $_ -like '| 2026-09-23*' }) -join ' || ')
Assert (@($trend | Where-Object { $_ -eq '- RunA test-seconds (canonical native nights, last 14): n=2, p50 600, p90 800, p95 800 (= max: n=2 < 20), max 800 [native]' }).Count -eq 1) 'canonical-p50-counts-nights-not-attempts' (($trend | Where-Object { $_ -like '*p50*' }) -join '')
Assert (@($trend | Where-Object { $_ -like '- Canonical nights: 2 of 7 results*' }).Count -eq 1) 'canonical-count-line' (($trend | Where-Object { $_ -like '*Canonical*' }) -join '')

# Items 3, 5, 6, 8: final-only, idempotent, routed, retried, fallback.
$state = Join-Path $dir 'state'
$resPath = Join-Path $dir 'r1.result.json'
(ConvertTo-Json (New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer') -Depth 6) | Set-Content -Path $resPath -Encoding UTF8
$script:sent = 0
$okSender = { param($t, $l) $script:sent++; return $true }
$badSender = { param($t, $l) $script:sent++; return $false }
$n0 = Invoke-NightlyNotify -Phase 'core' -RunId 'r1' -ResultPath $resPath -Class 'infrastructure' -Title 't' -Lines @('a') -StateDir $state -Sender $okSender
Assert (($n0.Status -eq 'skipped') -and ($script:sent -eq 0)) 'notify-core-publication-sends-nothing' "$($n0.Status) sent=$($script:sent)"
$n1 = Invoke-NightlyNotify -Phase 'final' -RunId 'r1' -ResultPath $resPath -Class 'infrastructure' -Title 't' -Lines @('a') -StateDir $state -Sender $okSender
Assert (($n1.Status -eq 'sent') -and ($script:sent -eq 1)) 'notify-final-sends-once' "$($n1.Status) sent=$($script:sent)"
$n2 = Invoke-NightlyNotify -Phase 'final' -RunId 'r1' -ResultPath $resPath -Class 'infrastructure' -Title 't' -Lines @('a') -StateDir $state -Sender $okSender
Assert (($n2.Status -eq 'duplicate') -and ($script:sent -eq 1)) 'notify-retried-run-sends-once' "$($n2.Status) sent=$($script:sent)"
Assert ($n1.Key -like "r1|*|v$($script:NotifyVersion)") 'notify-key-has-run-checksum-version' $n1.Key
$script:sent = 0
$n3 = Invoke-NightlyNotify -Phase 'final' -RunId 'r2' -ResultPath $resPath -Class 'infrastructure' -Title 'urgent' -Lines @('a') -StateDir $state -Sender $badSender -Retries 2
Assert (($n3.Status -eq 'fallback') -and ($n3.Attempts -eq 3) -and ($script:sent -eq 3) -and (@(Get-ChildItem (Join-Path $state 'undelivered') -Filter 'r2-*.json').Count -eq 1)) 'notify-failure-retries-then-falls-back' "$($n3.Status) attempts=$($n3.Attempts) $($n3.Notes -join '; ')"
# R3-F1: a second failed notification for another result of the same run
# keeps its own fallback file.
$res2 = Join-Path $dir 'r2b.result.json'
(ConvertTo-Json (New-Result '2026-09-25' '2026-09-25-023006' 'red' 'timer') -Depth 6) | Set-Content -Path $res2 -Encoding UTF8
$null = Invoke-NightlyNotify -Phase 'final' -RunId 'r2' -ResultPath $res2 -Class 'infrastructure' -Title 'urgent2' -Lines @('b') -StateDir $state -Sender $badSender -Retries 0
Assert (@(Get-ChildItem (Join-Path $state 'undelivered') -Filter 'r2-*.json').Count -eq 2) 'notify-fallbacks-never-overwrite' "$(@(Get-ChildItem (Join-Path $state 'undelivered') -Filter 'r2-*.json').Count)"
$dh = Get-DeliveryHealth $state
Assert ((-not $dh.Ok) -and ($dh.Count -eq 2) -and ($dh.Lines[0] -like '- Delivery RED: 2 undelivered notification(s); escalate operator*')) 'notify-delivery-health-escalates' ($dh.Lines -join ' | ')
$script:sent = 0
$n4 = Invoke-NightlyNotify -Phase 'final' -RunId 'r3' -ResultPath $resPath -Class 'test' -Title 'routine' -Lines @('a') -StateDir $state -Sender $okSender
$q = @(Get-Content (Join-Path $state 'digest-queue.json') -Raw | ConvertFrom-Json)
Assert (($n4.Status -eq 'queued') -and ($script:sent -eq 0) -and ($q.Count -eq 1) -and ($q[0].run -eq 'r3')) 'notify-routine-night-digests' "$($n4.Status) sent=$($script:sent) q=$($q.Count)"
Assert ($n1.Status -eq 'sent') 'notify-urgent-night-interrupts'
$dg = Format-Digest @($q + @([pscustomobject]@{ run = 'r9'; class = 'infrastructure' })) '2026-09-25'
Assert (($dg.Title -eq 'Nightly digest 2026-09-25 : 2 run(s)') -and ($dg.Lines[0] -like '1 x infrastructure*')) 'notify-digest-worst-class-first' ($dg.Lines -join ' | ')
Assert ($null -eq (Format-Digest @() 'd')) 'notify-empty-digest-sends-nothing'

# R1-F1: a dry run decides but persists nothing, so the real send is
# never suppressed as a duplicate.
$dryState = Join-Path $dir 'dry'
$script:sent = 0
$d1 = Invoke-NightlyNotify -Phase 'final' -RunId 'nostart-x' -ResultPath '' -Class 'scheduler-no-start' -Title 't' -Lines @('a') -StateDir $dryState -Sender $okSender -NoPersist
$d2 = Invoke-NightlyNotify -Phase 'final' -RunId 'nostart-x' -ResultPath '' -Class 'scheduler-no-start' -Title 't' -Lines @('a') -StateDir $dryState -Sender $okSender
Assert (($d1.Status -eq 'sent') -and ($d2.Status -eq 'sent') -and (-not (Test-Path (Join-Path $dryState 'notify-ledger.json')) -or (@(Get-Content (Join-Path $dryState 'notify-ledger.json') -Raw | ConvertFrom-Json).Count -eq 1))) 'notify-dry-run-never-suppresses-the-real-send' "$($d1.Status)/$($d2.Status)"
# R1-F2: the state lock serializes writers and fails loud when held.
$holder = Start-Job -ScriptBlock { $m = New-Object System.Threading.Mutex($false, 'Local\ScratchPad.NightlyNotifyState'); $null = $m.WaitOne(); Start-Sleep -Seconds 12; $m.ReleaseMutex() }
Start-Sleep -Seconds 4
$lockErr = ''
try { $null = Invoke-NightlyNotify -Phase 'final' -RunId 'locked' -ResultPath '' -Class 'infrastructure' -Title 't' -Lines @('a') -StateDir $state -Sender $okSender -LockTimeoutSeconds 1 } catch { $lockErr = $_.Exception.Message }
Stop-Job $holder -ErrorAction SilentlyContinue; Remove-Job $holder -Force -ErrorAction SilentlyContinue
Assert ($lockErr -like 'notify state lock not acquired within 1s*') 'notify-held-lock-fails-loud' $lockErr
# R1-F5, R1-F6: the digest keeps every payload whole and fails over.
$dgState = Join-Path $dir 'digest'
$null = New-Item -ItemType Directory -Force -Path $dgState
@([pscustomobject]@{ key = 'k1'; run = 'r10'; class = 'test'; title = 'Nightly 2026-09-24 : RED (test)'; lines = @('INC-1 top incident [evidence: bundle x]', 'Also: degraded-soak', 'Report: build/nightly/morning-2026-09-24.md'); at = (Get-Date).AddHours(-2).ToString('o') },
  [pscustomobject]@{ key = 'k2'; run = 'r11'; class = 'green'; title = 'Nightly 2026-09-25 : GREEN (green)'; lines = @('Recovered: night 2026-09-24 was RED', 'Report: build/nightly/morning-2026-09-25.md'); at = (Get-Date).AddHours(-1).ToString('o') }) | ForEach-Object { $_ } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dgState 'digest-queue.json') -Encoding UTF8
$script:sent = 0
$f1Now = Get-Date
$f1 = Invoke-DigestFlush -StateDir $dgState -Day '2026-09-25' -Sender $okSender -Now $f1Now
$dmd = Get-Content $f1.DigestPath -Raw
Assert (($f1.Status -eq 'sent') -and ($f1.Count -eq 2) -and ($dmd -like '*INC-1 top incident `[evidence: bundle x`]*') -and ($dmd -like '*Report: build/nightly/morning-2026-09-24.md*') -and ($dmd -like '*Recovered: night 2026-09-24 was RED*')) 'digest-keeps-every-payload-whole' $f1.Status
Assert ((@(Read-JsonState (Join-Path $dgState 'digest-queue.json') @()).Count -eq 0) -and ((Get-Content (Join-Path $dgState 'digest-queue.json') -Raw).Trim() -eq '[]')) 'digest-flush-clears-the-queue'
@([pscustomobject]@{ key = 'k3'; run = 'r12'; class = 'test'; title = 't'; lines = @('x'); at = (Get-Date).ToString('o') }) | ForEach-Object { $_ } | ConvertTo-Json -Depth 5 | ForEach-Object { "[$_]" } | Set-Content -Path (Join-Path $dgState 'digest-queue.json') -Encoding UTF8
$script:sent = 0
$f2 = Invoke-DigestFlush -StateDir $dgState -Day '2026-09-26' -Sender $badSender
$h2 = Get-DeliveryHealth $dgState
Assert (($f2.Status -eq 'fallback') -and ($f2.Attempts -eq 3) -and (@(Get-ChildItem (Join-Path $dgState 'undelivered') -Filter 'digest-2026-09-26-*.json').Count -eq 1) -and (-not $h2.Ok)) 'digest-failure-retries-falls-back-escalates' "$($f2.Status) attempts=$($f2.Attempts) health=$($h2.Ok)"
# R2-F4: a second flush the same day writes its own file.
@([pscustomobject]@{ key = 'k5'; run = 'r14'; class = 'test'; title = 'late'; lines = @('late line'); at = (Get-Date).ToString('o') }) | ForEach-Object { $_ } | ConvertTo-Json -Depth 5 | ForEach-Object { "[$_]" } | Set-Content -Path (Join-Path $dgState 'digest-queue.json') -Encoding UTF8
$f3 = Invoke-DigestFlush -StateDir $dgState -Day '2026-09-25' -Sender $okSender -Now $f1Now
Assert (($f3.DigestPath -ne $f1.DigestPath) -and ((Get-Content $f1.DigestPath -Raw) -like '*INC-1 top incident*') -and ((Get-Content $f3.DigestPath -Raw) -like '*late line*')) 'digest-second-flush-never-overwrites' "$($f1.DigestPath) vs $($f3.DigestPath)"
# R2-F1: undelivered re-sends run under the lock and delete only on success.
$uState = Join-Path $dir 'resend'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $uState 'undelivered')
'{"title":"T","lines":["x"]}' | Set-Content -Path (Join-Path $uState 'undelivered\a.json') -Encoding UTF8
$rs1 = @(Invoke-UndeliveredResend -StateDir $uState -Sender $badSender)
$rs2 = @(Invoke-UndeliveredResend -StateDir $uState -Sender $okSender)
Assert (($rs1 -join '') -eq 'undelivered a.json: still failing') 'resend-failure-keeps-payload' ($rs1 -join ' | ')
Assert ((($rs2 -join '') -eq 'undelivered a.json: re-sent') -and (-not (Test-Path (Join-Path $uState 'undelivered\a.json')))) 'resend-success-deletes-payload' ($rs2 -join ' | ')
$staleState = Join-Path $dir 'stale'
$null = New-Item -ItemType Directory -Force -Path $staleState
@([pscustomobject]@{ key = 'k4'; run = 'r13'; class = 'test'; title = 't'; lines = @('x'); at = (Get-Date).AddHours(-30).ToString('o') }) | ForEach-Object { $_ } | ConvertTo-Json -Depth 5 | ForEach-Object { "[$_]" } | Set-Content -Path (Join-Path $staleState 'digest-queue.json') -Encoding UTF8
$h3 = Get-DeliveryHealth $staleState
Assert ((-not $h3.Ok) -and ($h3.Lines[0] -like '- Delivery RED: digest queue stale past 26h (r13)*')) 'delivery-stale-digest-queue-escalates' ($h3.Lines -join ' | ')

# Item 4: the no-start check alerts without any governed run firing.
$ns = Get-NoStartVerdict @((New-Result '2026-09-24' '2026-09-24-023000' 'green' 'timer')) (Get-Date '2026-09-25 07:05') '06:50' 0
Assert ($ns.NoStart -and ((@($ns.Missed) -join ',') -eq '2026-09-25') -and ($ns.Line -like 'NO START: no governed nightly result for 2026-09-25*')) 'nostart-suppressed-night-alerts' $ns.Line
Assert (-not (Get-NoStartVerdict @() (Get-Date '2026-09-25 05:00') '06:50' 0).NoStart) 'nostart-waits-for-the-window'
Assert (-not (Get-NoStartVerdict @((New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer')) (Get-Date '2026-09-25 07:05') '06:50' 0).NoStart) 'nostart-started-night-passes'
$enrolledNight = New-Result '2026-09-20' '2026-09-20-023000' 'green' 'timer'
Assert ((Get-NoStartVerdict @($enrolledNight, (New-Result '2026-09-25' '2026-09-25-043000' 'red' 'manual')) (Get-Date '2026-09-25 07:05') '06:50' 0).NoStart) 'nostart-manual-run-is-not-a-start'
# R2-F2: simulated and stood-down results are not governed starts.
Assert ((Get-NoStartVerdict @($enrolledNight, (New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer' $true)) (Get-Date '2026-09-25 07:05') '06:50' 0).NoStart) 'nostart-simulation-is-not-a-start'
Assert ((Get-NoStartVerdict @($enrolledNight, (New-Result '2026-09-25' '2026-09-25-023000' 'stood-down' 'timer')) (Get-Date '2026-09-25 07:05') '06:50' 0).NoStart) 'nostart-stood-down-is-not-a-start'
# R2-F5: a logon before today's deadline still reports the nights missed.
$lb = Get-NoStartVerdict @((New-Result '2026-09-22' '2026-09-22-023000' 'red' 'timer')) (Get-Date '2026-09-25 05:00') '06:50' 3
Assert ((@($lb.Missed) -join ',') -eq '2026-09-23,2026-09-24') 'nostart-lookback-reports-missed-nights' ((@($lb.Missed) -join ','))
# Enrollment: nights before the first governed result predate result
# capture and are never reported (live false alarm 2026-09-25 07:05).
$enr = Get-NoStartVerdict @((New-Result '2026-09-22' '2026-09-22-023000' 'red' 'timer'), (New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer')) (Get-Date '2026-09-25 07:05') '06:50' 7
Assert ((@($enr.Missed) -join ',') -eq '2026-09-23,2026-09-25') 'nostart-skips-nights-before-enrollment' ((@($enr.Missed) -join ','))
Assert (-not (Get-NoStartVerdict @() (Get-Date '2026-09-25 07:05') '06:50' 7).NoStart) 'nostart-no-governed-history-reports-nothing'
# D00 T02 §24 redesign review: a provisioned task that never produced a
# result still alerts from its recorded enrollment night.
$never = Get-NoStartVerdict @() (Get-Date '2026-09-25 07:05') '06:50' 3 '2026-09-23'
$hs = Join-Path $dir 'history-enrolled.md'
'# history', '', 'Enrolled: 2026-09-23', '', '| From | Trigger | Interval days |' | Set-Content -Path $hs -Encoding UTF8
# §24 R7: enrollment is the first trigger after registration, so a task
# provisioned at 00:30 before its 02:30 trigger owes that same night.
Assert (((Get-EnrollmentNight $null (Get-Date '2026-09-25 00:30') '02:30') -eq '2026-09-25') -and ((Get-EnrollmentNight $null (Get-Date '2026-09-25 03:00') '02:30') -eq '2026-09-26') -and ((Get-EnrollmentNight (Get-Date '2026-09-25 02:30') (Get-Date '2026-09-25 00:30')) -eq '2026-09-25')) 'enrollment-is-the-first-trigger-after-registration'
Assert ($never.NoStart -and ((@($never.Missed) -join ',') -eq '2026-09-23,2026-09-24,2026-09-25') -and ((Read-NightlyEnrollment $hs) -eq '2026-09-23') -and ((Read-NightlyEnrollment (Join-Path $dir 'none.md')) -eq '')) 'nostart-enrolled-task-that-never-ran-alerts' ((@($never.Missed) -join ','))
$mDir = Join-Path $dir 'morning'
$null = New-Item -ItemType Directory -Force -Path $mDir
$enrolledMorning = New-Result ((Get-Date).AddDays(-3).ToString('yyyy-MM-dd')) ((Get-Date).AddDays(-3).ToString('yyyy-MM-dd') + '-023000') 'green' 'timer'
(ConvertTo-Json $enrolledMorning -Depth 6) | Set-Content -Path (Join-Path $mDir ('morning-' + $enrolledMorning.stamp + '.result.json')) -Encoding UTF8
$mOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyMorning.ps1') -DryRun -NightDir $mDir -ExpectBy '00:00' -LookbackDays 1 2>&1 | ForEach-Object { "$_" })
Assert ((@($mOut | Where-Object { $_ -like 'morning: no-start: NO START*' }).Count -eq 1) -and (@($mOut | Where-Object { $_ -like 'morning: no-start notify *: sent*dry run*' }).Count -eq 2) -and (-not (Test-Path (Join-Path $mDir 'notify-ledger.json')))) 'nostart-reconciler-alerts-with-no-run' ($mOut -join ' | ')

# D00 T02 section 40 R1-F6: the morning step reads pending alert
# transitions from the lifecycle ledger, and a dry run confirms nothing.
'## Alerts' | Set-Content -Path (Join-Path $mDir 'trend.md') -Encoding UTF8
$null = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-27 vs baseline 600s (+50%, median of 7 night(s))') (Join-Path $mDir 'alerts.json') ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'x#r1' })
$mAl = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyMorning.ps1') -DryRun -NightDir $mDir -ExpectBy '00:00' -LookbackDays 1 2>&1 | ForEach-Object { "$_" })
$mPend = Get-PendingAlertNotifications (Join-Path $mDir 'alerts.json')
Assert ((@($mAl | Where-Object { $_ -like 'morning: trend alerts: 1 (*' }).Count -eq 1) -and (@($mPend.Lines).Count -eq 1)) 's40-morning-sends-pending-and-dry-run-keeps-it' (($mAl | Where-Object { $_ -like '*trend*' }) -join ' | ')

# Item 9: every outcome beside the precedence class.
$multi = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$multi.legs.'run-a'.gate = 1
$multi.legs.'run-a'.failed = 2
$multi.legs.interactive.enforcementRed = $true
$multi.soak.verdict = 'red'
$multi.quarantine = [pscustomobject]@{ overdue = @('UI.X'); dueSoon = @() }
$labels = @(Get-OutcomeLabels $multi)
Assert ((($labels -join ',') -eq 'gate,enforcement,test,degraded-soak,quarantine-overdue') -and ((Classify-NightlyOutcome $multi).Class -eq 'gate')) 'labels-multi-failure-lists-every-outcome' ($labels -join ',')

# Item 10: every class routes with an owner, channel, severity, and SLA.
foreach ($c in @('scheduler-no-start', 'infrastructure', 'recovery', 'gate', 'enforcement', 'test', 'degraded-soak', 'green', 'cancelled')) {
  $r = Get-AlertRoute $c
  Assert (($r.Owner -ne '') -and (@('immediate', 'digest') -contains $r.Channel) -and ($r.Severity -ne '') -and ($null -ne $r.SlaHours)) "route-$c" "$($r.Owner) $($r.Channel) $($r.Severity) $($r.SlaHours)"
}
Assert ((Get-AlertRoute 'mystery').Channel -eq 'immediate') 'route-unknown-class-goes-to-a-human'

# Item 11: priority plus truncation under the cap, report link last.
$items = @(
  (New-ToastItem 7 'Trigger: timer'), (New-ToastItem 5 'counts'), (New-ToastItem 6 'Also: soak'),
  (New-ToastItem 4 'Overdue quarantine: x'), (New-ToastItem 3 'Recovered: y'), (New-ToastItem 2 'INC-1 top incident'),
  (New-ToastItem 1 'Unacked REDs: 3'), (New-ToastItem 0 'Result invalid: z'), (New-ToastItem 5 'more counts' 1)
)
$tl = @(Format-ToastLines $items 'build/nightly/morning-2026-09-25.md')
Assert (($tl.Count -eq 7) -and ($tl[0] -eq 'Result invalid: z') -and ($tl[1] -eq 'Unacked REDs: 3') -and ($tl[2] -eq 'INC-1 top incident') -and ($tl[5] -eq '+4 more in the report') -and ($tl[6] -eq 'Report: build/nightly/morning-2026-09-25.md')) 'cap-keeps-priority-and-links-report' ($tl -join ' | ')
$short = @(Format-ToastLines @((New-ToastItem 5 'counts')) 'r.md')
Assert ((($short -join '|') -eq 'counts|Report: r.md')) 'cap-short-body-untruncated' ($short -join '|')

# Item 12: report and result agree field by field.
$agreeRes = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$agreeRes.incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
$rep = @('| Run A (default) | 10 passed, 0 failed, 1 skipped (UI.dll 10/0/1) | exit 0 changes logged | - | log |', '| Run B (primary) | 4 passed, 0 failed, 0 skipped (UI.dll 4/0/0) | exit 0 x | - | log |', '| Interactive (collection) | 3 passed, 0 failed, 0 skipped (UI.dll 3/0/0) | n/a (owns the foreground) | - | log |', '', '## Incidents', '', '- INC-aaaa1111 `UI.A` x1 (Run A): boom', '', '## Soak', '', '- Verdict: GREEN (10/10 iterations proved)', '', '## Run integrity', '- Timings: build=1s reserve=900s', '- Budget: consumed=600s reserve=900s', '- Environment: os 10.0.26200.0 | powershell 5.1 | dotnet 10.0.400 | session op/ | topology D1 primary | dpi primary 96x96 | adapters GPU | settings BACKGROUND=', '- Exit: 1')
Assert ((Test-ReportResultAgreement $rep $agreeRes).Ok) 'agree-consistent-report-passes' ((Test-ReportResultAgreement $rep $agreeRes).Breaks -join '; ')
$bad = @($rep | ForEach-Object { $_ -replace '^\| Run B \(primary\) \| 4 passed', '| Run B (primary) | 5 passed' })
Assert (@((Test-ReportResultAgreement $bad $agreeRes).Breaks | Where-Object { $_ -eq 'run-b passed: report 5 vs result 4' }).Count -eq 1) 'agree-count-contradiction-fails' ((Test-ReportResultAgreement $bad $agreeRes).Breaks -join '; ')
$bad2 = @($rep | Where-Object { $_ -notlike '- INC-*' })
Assert (@((Test-ReportResultAgreement $bad2 $agreeRes).Breaks | Where-Object { $_ -eq 'incidents: report [] vs result [INC-aaaa1111]' }).Count -eq 1) 'agree-incident-contradiction-fails' ((Test-ReportResultAgreement $bad2 $agreeRes).Breaks -join '; ')
$bad3 = @($rep | ForEach-Object { $_ -replace '- Budget: consumed=600s reserve=900s', '- Budget: consumed=600s reserve=901s' } | ForEach-Object { $_ -replace 'exit 0 changes', 'exit 1 changes' })
$b3 = @((Test-ReportResultAgreement $bad3 $agreeRes).Breaks)
Assert ((@($b3 | Where-Object { $_ -eq 'budget reserve: report 901s vs result 900' }).Count -eq 1) -and (@($b3 | Where-Object { $_ -eq 'run-a gate: report exit 1 vs result 0' }).Count -eq 1)) 'agree-reserve-and-gate-contradictions-fail' ($b3 -join '; ')
$b5 = @((Test-ReportResultAgreement @($rep | Where-Object { $_ -notlike '| Run B (primary)*' }) $agreeRes).Breaks)
Assert (@($b5 | Where-Object { $_ -eq 'run-b: result ran the leg, report has no counts row' }).Count -eq 1) 'agree-missing-leg-row-fails' ($b5 -join '; ')
$b6 = @((Test-ReportResultAgreement @($rep | Where-Object { ($_ -notlike '- Budget:*') -and ($_ -notlike '- Exit:*') }) $agreeRes).Breaks)
Assert ((@($b6 | Where-Object { $_ -eq 'budget: report carries no Budget line' }).Count -eq 1) -and (@($b6 | Where-Object { $_ -eq 'exit: report carries no Exit line' }).Count -eq 1)) 'agree-missing-budget-and-exit-fail' ($b6 -join '; ')
$b7 = @((Test-ReportResultAgreement @($rep | ForEach-Object { $_ -replace '- Verdict: GREEN', '- Verdict: RED' }) $agreeRes).Breaks)
Assert (@($b7 | Where-Object { $_ -eq 'soak: report red vs result green' }).Count -eq 1) 'agree-soak-contradiction-fails' ($b7 -join '; ')
$b8 = @((Test-ReportResultAgreement @($rep | ForEach-Object { $_ -replace 'topology D1 primary', 'topology D2 primary' }) $agreeRes).Breaks)
Assert (@($b8 | Where-Object { $_ -eq "environment topology: report 'D2 primary' vs result 'D1 primary'" }).Count -eq 1) 'agree-environment-field-contradiction-fails' ($b8 -join '; ')
$bad4 = @($rep | Where-Object { $_ -notlike '- Environment:*' })
Assert (@((Test-ReportResultAgreement $bad4 $agreeRes).Breaks | Where-Object { $_ -eq 'environment: report carries no Environment line' }).Count -eq 1) 'agree-missing-environment-fails'

# A real topology carries '; ' (two monitors); the Environment line
# must still agree field by field.
$multiMon = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$multiMon.incidents = $agreeRes.incidents
$multiMon.env.topology = '\.\DISPLAY1 2560x1440+0+0 primary; \.\DISPLAY2 1920x1080+-1920+1080'
$repMM = @($rep | ForEach-Object { $_ -replace 'topology D1 primary', ('topology ' + $multiMon.env.topology.Replace('$', '$$')) })
$bMM = @((Test-ReportResultAgreement $repMM $multiMon).Breaks)
Assert ($bMM.Count -eq 0) 'agree-multi-monitor-topology-passes' ($bMM -join '; ')
$repPipe = @($repMM | ForEach-Object { $_ -replace 'adapters GPU', 'adapters GPU | extra' })
Assert (@((Test-ReportResultAgreement $repPipe $multiMon).Breaks | Where-Object { $_ -like 'environment: report has 9 fields, want 8*' }).Count -eq 1) 'agree-environment-field-count-fails-loud'

# R2-F3: a numeric gate replaced by n/a, soak names out of step either
# way, and a Timings reserve that disagrees all break.
$b9 = @((Test-ReportResultAgreement @($rep | ForEach-Object { $_ -replace '\| exit 0 changes logged \|', '| n/a |' }) $agreeRes).Breaks)
Assert (@($b9 | Where-Object { $_ -eq "run-a gate: report 'n/a' vs result 0" }).Count -eq 1) 'agree-gate-cell-must-be-numeric' ($b9 -join '; ')
$soakRes = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$soakRes.incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
$soakRes.soak = [pscustomobject]@{ verdict = 'green'; failed = @('ui-soak-2'); killed = @(); cut = @() }
$b10 = @((Test-ReportResultAgreement $rep $soakRes).Breaks)
Assert (@($b10 | Where-Object { $_ -eq 'soak ui-soak-2: result lists it, report soak rows omit it' }).Count -eq 1) 'agree-soak-result-name-must-appear' ($b10 -join '; ')
$repFail = @($rep | ForEach-Object { if ($_ -like '- Verdict: GREEN*') { $_; '- ui-soak-3 : 9 passed, 1 failed, 0 skipped (FAILED)' } else { $_ } })
$b11 = @((Test-ReportResultAgreement $repFail $agreeRes).Breaks)
Assert (@($b11 | Where-Object { $_ -like "soak ui-soak-3: report failed ('9 passed, 1 failed, 0 skipped (FAILED)'), result failed list lacks it" }).Count -eq 1) 'agree-soak-report-claim-must-be-backed' ($b11 -join '; ')
$repNz = @($rep | ForEach-Object { if ($_ -like '- Verdict: GREEN*') { $_; '- protocol-soak-2 : nonzero exit, trx carries no Failed outcomes (aborted host suspected: unproven; owes triage: re-drive or carry)' } else { $_ } })
$b14 = @((Test-ReportResultAgreement $repNz $agreeRes).Breaks)
Assert (@($b14 | Where-Object { $_ -like 'soak protocol-soak-2: report failed (*nonzero exit*), result failed list lacks it' }).Count -eq 1) 'agree-soak-every-failure-form-backed' ($b14 -join '; ')
$b12 = @((Test-ReportResultAgreement @($rep | ForEach-Object { $_ -replace 'build=1s reserve=900s', 'build=1s reserve=5s' }) $agreeRes).Breaks)
Assert (@($b12 | Where-Object { $_ -eq 'timings reserve: report 5s vs result 900' }).Count -eq 1) 'agree-timings-reserve-still-checked' ($b12 -join '; ')

# R3-F2: a result-failed iteration whose row reads passed breaks.
$soakRes2 = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$soakRes2.incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
$soakRes2.soak = [pscustomobject]@{ verdict = 'green'; failed = @('ui-soak-4'); killed = @(); cut = @() }
$repPassed = @($rep | ForEach-Object { if ($_ -like '- Verdict: GREEN*') { $_; '- ui-soak-4 : 10 passed, 0 failed, 0 skipped (proved)' } else { $_ } })
$b13 = @((Test-ReportResultAgreement $repPassed $soakRes2).Breaks)
Assert (@($b13 | Where-Object { $_ -like "soak ui-soak-4: result failed, report row reads '10 passed*" }).Count -eq 1) 'agree-soak-row-status-must-match' ($b13 -join '; ')

# Item 13: recovery notices, night-level and incident-level.
$hist = @((New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer'), (New-Result '2026-09-25' '2026-09-25-023000' 'green' 'timer'))
$rn = @(Get-RecoveryNotices (Select-CanonicalRuns $hist) $hist $hist[1] @('- INC-aaaa1111 `UI.A`: CLOSED (verified recovery: passed in run-a on 3 runs through s)'))
Assert ((($rn -join ' | ') -eq 'Service recovered: night 2026-09-24 was RED, 2026-09-25 is GREEN | Recovered: INC-aaaa1111 UI.A (closed on verified recovery)')) 'recovery-notice-night-and-incident' ($rn -join ' | ')
$still = @(Get-RecoveryNotices (Select-CanonicalRuns $hist) $hist (New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer') @())
Assert ($still.Count -eq 0) 'recovery-none-while-red'
$retryDay = @((New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer'), (New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer'), (New-Result '2026-09-25' '2026-09-25-093000' 'green' 'manual'))
$rr = @(Get-RecoveryNotices (Select-CanonicalRuns $retryDay) $retryDay $retryDay[2] @())
Assert ($rr.Count -eq 0) 'recovery-green-retry-is-not-a-recovered-night' ($rr -join ' | ')
# D00 T02 section 40 item 1: another host's GREEN never recovers this
# host's RED night; the previous night is the same host's.
$hostRed = New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer'; $hostRed | Add-Member -NotePropertyName hostKey -NotePropertyValue 'h0st0001' -Force
$hostGreen = New-Result '2026-09-25' '2026-09-25-023000' 'green' 'timer'; $hostGreen | Add-Member -NotePropertyName hostKey -NotePropertyValue 'h0st0002' -Force
$hx = @(Get-RecoveryNotices (Select-CanonicalRuns @($hostRed, $hostGreen)) @($hostRed, $hostGreen) $hostGreen @())
Assert ($hx.Count -eq 0) 's40-recovery-is-host-scoped' ($hx -join ' | ')
# R4-F4: an identity two hosts share resolves to this host's run.
$shB = New-Result '2026-09-24' '2026-09-24-023000' 'green' 'timer'; $shB | Add-Member -NotePropertyName hostKey -NotePropertyValue 'h0st0002' -Force
$shA = New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer'; $shA | Add-Member -NotePropertyName hostKey -NotePropertyValue 'h0st0001' -Force
$shNow = New-Result '2026-09-25' '2026-09-25-023000' 'green' 'timer'; $shNow | Add-Member -NotePropertyName hostKey -NotePropertyValue 'h0st0001' -Force
$shRes = @($shB, $shA, $shNow)
$shN = @(Get-RecoveryNotices (Select-CanonicalRuns $shRes) $shRes $shNow @())
Assert (($shN -join ' | ') -eq 'Service recovered: night 2026-09-24 was RED, 2026-09-25 is GREEN') 's40-shared-identity-resolves-to-this-host' ($shN -join ' | ')

# Item 14: launch evidence links end to end.
$diag = Join-Path $dir 'launch-diagnostics'
$bdir = Join-Path $diag 'bundles\20260925\LaunchTests-cs-LargeFileOpensResponsively-010203'
$null = New-Item -ItemType Directory -Force -Path $bdir
'{}' | Set-Content -Path (Join-Path $bdir 'bundle.json') -Encoding UTF8
[System.IO.File]::WriteAllBytes((Join-Path $bdir 'leak.png'), (New-Object byte[] 16))
@('{"schema":"launch-diagnostics/1","test":"LaunchTests.cs:LargeFileOpensResponsively","pid":null,"error":"TimeoutException: UIA Timeout"}', '{"schema":"launch-diagnostics/1","test":"LaunchTests.cs:LargeFileOpensResponsively","pid":5,"error":null}') | Set-Content -Path (Join-Path $diag 'launches-20260925.jsonl') -Encoding UTF8
$links = @(Find-IncidentEvidence $diag 'UI.LaunchTests.LargeFileOpensResponsively' @('20260925'))
Assert (($links.Count -eq 3) -and ($links[0] -like 'bundle *bundle.json') -and ($links[1] -like 'screenshot *leak.png') -and ($links[2] -like 'launch-record *launches-20260925.jsonl:1')) 'evidence-links-bundle-screenshot-record' ($links -join ' | ')
Assert (@(Find-IncidentEvidence $diag 'UI.TabBarTests.Other' @('20260925')).Count -eq 0) 'evidence-unrelated-test-links-nothing'
$evRes = New-Result '2026-09-25' '2026-09-25-023005' 'red' 'timer'
$evRes | Add-Member -NotePropertyName incidentEvidence -NotePropertyValue ([pscustomobject]@{ 'INC-aaaa1111' = $links })
$evTrend = @(Format-TrendTable @($evRes) @{ Overdue = @(); DueSoon = @() } (Get-Date '2026-09-25'))
# The fixture's evidence lives under the user's temp folder, so the
# disclosure contract (D00 T02 section 32) shows it as [path].
Assert (@($evTrend | Where-Object { ($_ -like '- Incident evidence (2026-09-25): INC-aaaa1111 bundle *; screenshot *; launch-record *') -and (($_ -like '*bundle.json*') -or ($_ -like '*`[path`]*')) }).Count -eq 1) 'evidence-rides-the-trend' (($evTrend | Where-Object { $_ -like '*evidence*' }) -join '')

# D00 T02 section 32 item 14: toasts and digests pass the disclosure
# contract (a planted token and a user-profile path never render).
$tok = 'ghp_' + ('A1b2C3d4E5' * 4)
$dToast = @(Format-ToastLines @((New-ToastItem 1 "leak $tok at C:\Users\someone\AppData\x.log")) 'build/nightly/morning-x.md')
$dDig = Format-Digest @([pscustomobject]@{ run = "C:\Users\someone\run $tok"; class = 'test' }) '2026-09-25'
Assert ((($dToast -join ' ') -notlike '*ghp_*') -and (($dToast -join ' ') -notlike '*Users\someone*') -and (($dToast -join ' ') -like '*`[redacted: github-token`]*') -and ((@($dDig.Lines) -join ' ') -notlike '*ghp_*') -and ((@($dDig.Lines) -join ' ') -notlike '*Users\someone*')) 'notify-channels-disclose-nothing' (($dToast -join ' | ') + ' || ' + (@($dDig.Lines) -join ' | '))

# D00 T02 section 33 item 1: one night identity. A night with a RED timer
# run, a cancelled run, and a GREEN manual retry: the trend's selection
# and the notification's voice name the same run, and a run that does not
# speak for its night knows which one does.
$n33 = @((New-Result '2026-09-26' '2026-09-26-023000' 'red' 'timer'), (New-Result '2026-09-26' '2026-09-26-031500' 'cancelled' 'timer'), (New-Result '2026-09-26' '2026-09-26-093000' 'green' 'manual'))
$c33 = Select-CanonicalRuns $n33
$trendPick = $c33[(Get-NightSlotKey $n33[0])].Canonical
$voices = @($n33 | ForEach-Object { Get-NightVoice $c33 $_ })
Assert ((@($voices | ForEach-Object { $_.Canonical } | Sort-Object -Unique).Count -eq 1) -and ($voices[0].Canonical -eq $trendPick) -and (@($voices | Where-Object { $_.IsVoice }).Count -eq 1)) 's33-notify-and-trend-pick-one-run' "trend $trendPick; voices $(@($voices | ForEach-Object { "$($_.Canonical)/$($_.IsVoice)" }) -join ',')"

# Item 2: a worsening alert re-notifies, an unchanged one does not.
$al33 = Join-Path $dir 'alerts33.json'
$ev1 = [pscustomobject]@{ Night = '2026-09-24'; Host = 'h0st0001'; Identity = 'a1' }
$null = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-24 vs baseline 600s (+50%, median of 5 night(s))') $al33 $ev1
$p1 = Get-PendingAlertNotifications $al33; Confirm-AlertNotifications $al33 @($p1.Keys)
$null = Update-AlertLedger @('- ALERT runa-duration: 910s on 2026-09-25 vs baseline 600s (+52%, median of 5 night(s))') $al33 ([pscustomobject]@{ Night = '2026-09-25'; Host = 'h0st0001'; Identity = 'a2' })
$p2 = Get-PendingAlertNotifications $al33
$w3 = Update-AlertLedger @('- ALERT runa-duration: 1200s on 2026-09-26 vs baseline 600s (+100%, median of 5 night(s))') $al33 ([pscustomobject]@{ Night = '2026-09-26'; Host = 'h0st0001'; Identity = 'a3' })
$p3 = Get-PendingAlertNotifications $al33
Assert ((@($p2.Lines).Count -eq 0) -and (@($w3.Worsened) -contains 'h0st0001|runa-duration') -and (@($p3.Lines).Count -eq 1) -and ($p3.Lines[0] -like 'WORSENING (from 50 to 100): ALERT runa-duration: 1200s*')) 's33-worsening-renotifies-unchanged-does-not' "p2=$(@($p2.Lines) -join '|') p3=$(@($p3.Lines) -join '|')"

# Item 3: every enumerated agreement field has a contradiction fixture;
# the result is changed one field at a time and the named break reads.
$fields33 = @(
  @('run-a passed', { param($r) $r.legs.'run-a'.passed = 99 }, 'run-a passed: report 10 vs result 99'),
  @('run-a failed', { param($r) $r.legs.'run-a'.failed = 99 }, 'run-a failed: report 0 vs result 99'),
  @('run-a skipped', { param($r) $r.legs.'run-a'.skipped = 99 }, 'run-a skipped: report 1 vs result 99'),
  @('run-a gate', { param($r) $r.legs.'run-a'.gate = 5 }, 'run-a gate: report exit 0 vs result 5'),
  @('run-b passed', { param($r) $r.legs.'run-b'.passed = 99 }, 'run-b passed: report 4 vs result 99'),
  @('run-b failed', { param($r) $r.legs.'run-b'.failed = 99 }, 'run-b failed: report 0 vs result 99'),
  @('run-b skipped', { param($r) $r.legs.'run-b'.skipped = 99 }, 'run-b skipped: report 0 vs result 99'),
  @('run-b gate', { param($r) $r.legs.'run-b'.gate = 5 }, 'run-b gate: report exit 0 vs result 5'),
  @('interactive passed', { param($r) $r.legs.interactive.passed = 99 }, 'interactive passed: report 3 vs result 99'),
  @('interactive failed', { param($r) $r.legs.interactive.failed = 99 }, 'interactive failed: report 0 vs result 99'),
  @('interactive skipped', { param($r) $r.legs.interactive.skipped = 99 }, 'interactive skipped: report 0 vs result 99'),
  @('incidents', { param($r) $r.incidents = @() }, 'incidents: report [INC-aaaa1111] vs result []'),
  @('budget consumed', { param($r) $r.consumed = 1 }, 'budget consumed: report 600s vs result 1'),
  @('budget reserve', { param($r) $r.reserve = 1 }, 'budget reserve: report 900s vs result 1'),
  @('timings reserve', { param($r) $r.reserve = 1 }, 'timings reserve: report 900s vs result 1'),
  @('soak verdict', { param($r) $r.soak.verdict = 'red' }, 'soak: report green vs result red'),
  @('soak failed list', { param($r) $r.soak | Add-Member -NotePropertyName failed -NotePropertyValue @('ui-soak-9') -Force }, 'soak ui-soak-9: result lists it, report soak rows omit it'),
  @('soak killed list', { param($r) $r.soak | Add-Member -NotePropertyName killed -NotePropertyValue @('ui-soak-9') -Force }, 'soak ui-soak-9: result lists it, report soak rows omit it'),
  @('soak cut list', { param($r) $r.soak | Add-Member -NotePropertyName cut -NotePropertyValue @('ui-soak-9') -Force }, 'soak ui-soak-9: result lists it, report soak rows omit it'),
  @('exit', { param($r) $r.exit = 7 }, 'exit: report 1 vs result 7')
)
foreach ($k in @('os', 'powershell', 'dotnet', 'session', 'topology', 'dpi', 'adapters', 'settings')) { $fields33 += , @("environment $k", [scriptblock]::Create("param(`$r) `$r.env.$k = 'zz'"), "environment ${k}: report ") }
$miss33 = @()
foreach ($f in $fields33) {
  $r33 = $agreeRes | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  & $f[1] $r33
  $br = @((Test-ReportResultAgreement $rep $r33).Breaks)
  if (@($br | Where-Object { "$_".StartsWith($f[2]) }).Count -eq 0) { $miss33 += "$($f[0]) (got: $($br -join '; '))" }
}
$doc33 = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/testing.md') -Raw -Encoding UTF8
$undoc33 = @($fields33 | Where-Object { -not $doc33.Contains('`' + $_[0] + '`') } | ForEach-Object { $_[0] })
Assert (($miss33.Count -eq 0) -and ($undoc33.Count -eq 0) -and ($fields33.Count -eq 28)) 's33-every-agreement-field-has-a-contradiction-fixture' "missing: $($miss33 -join ' | '); undocumented: $($undoc33 -join ', ')"

# Item 4: two consecutive failing nights escalate once through the
# independent channel; a success ends the episode.
$st33 = Join-Path $dir 'state33'
$null = New-Item -ItemType Directory -Force -Path $st33
$fail = { param($t, $l) $false }
$null = Invoke-NightlyNotify -Phase 'final' -RunId 'r33a' -ResultPath '' -Class 'test-failure' -Title 'n1' -Lines @('x') -StateDir $st33 -Sender $fail -Now (Get-Date '2026-09-24 03:00')
$esc1 = @(Invoke-DeliveryEscalation -StateDir $st33 -Now (Get-Date '2026-09-24 07:05') -Escalate { param($t, $l) $script:esc33 += $t; $true })
$null = Invoke-NightlyNotify -Phase 'final' -RunId 'r33b' -ResultPath '' -Class 'test-failure' -Title 'n2' -Lines @('x') -StateDir $st33 -Sender $fail -Now (Get-Date '2026-09-25 03:00')
$script:esc33 = @()
$esc2 = @(Invoke-DeliveryEscalation -StateDir $st33 -Now (Get-Date '2026-09-25 07:05') -Escalate { param($t, $l) $script:esc33 += $t; $true })
$esc3 = @(Invoke-DeliveryEscalation -StateDir $st33 -Now (Get-Date '2026-09-25 08:00') -Escalate { param($t, $l) $script:esc33 += $t; $true })
Assert (($esc1.Count -eq 0) -and ($esc2[0] -like '- Delivery escalation: sent through the independent channel for the episode from 2026-09-24*') -and ($script:esc33.Count -eq 1) -and ($esc3[0] -like '*already sent for the episode from 2026-09-24*')) 's33-two-failed-nights-escalate-once' "$($esc1 -join '|') / $($esc2 -join '|') / $($esc3 -join '|') / $($script:esc33 -join '|')"

# Item 5: the crash window. A send intent left behind re-sends marked as a
# possible duplicate; a recorded fallback never sent is re-sent by the
# reconciler; a digest key already queued is not queued twice.
$st33b = Join-Path $dir 'state33b'
$null = New-Item -ItemType Directory -Force -Path $st33b
$k33 = "r33c|noresult|v$($script:NotifyVersion)"
ConvertTo-Json @([pscustomobject]@{ key = $k33; run = 'r33c'; class = 'test-failure'; channel = 'immediate'; at = '2026-09-25T03:00:00+02:00'; status = 'sending' }) -Depth 4 | Set-Content -Path (Join-Path $st33b 'notify-ledger.json') -Encoding UTF8
$script:sent33 = @()
$cw = Invoke-NightlyNotify -Phase 'final' -RunId 'r33c' -ResultPath '' -Class 'test-failure' -Title 'crash' -Lines @('x') -StateDir $st33b -Sender { param($t, $l) $script:sent33 += $t; $true }
$cw2 = Invoke-NightlyNotify -Phase 'final' -RunId 'r33c' -ResultPath '' -Class 'test-failure' -Title 'crash' -Lines @('x') -StateDir $st33b -Sender { param($t, $l) $script:sent33 += $t; $true }
$null = Invoke-NightlyNotify -Phase 'final' -RunId 'r33d' -ResultPath '' -Class 'test-failure' -Title 'lost' -Lines @('x') -StateDir $st33b -Sender $fail
$rs33 = @(Invoke-UndeliveredResend -StateDir $st33b -Sender { param($t, $l) $script:sent33 += $t; $true })
$qk = "r33e|noresult|v$($script:NotifyVersion)"
ConvertTo-Json @([pscustomobject]@{ key = $qk; run = 'r33e'; class = 'green'; title = 'q'; lines = @('x'); at = '2026-09-25T03:00:00+02:00' }) -Depth 4 | Set-Content -Path (Join-Path $st33b 'digest-queue.json') -Encoding UTF8
$qd = Invoke-NightlyNotify -Phase 'final' -RunId 'r33e' -ResultPath '' -Class 'green' -Title 'q' -Lines @('x') -StateDir $st33b -Sender $fail
$q33 = @(Get-Content (Join-Path $st33b 'digest-queue.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
Assert (($cw.Status -eq 'sent') -and ($script:sent33[0] -eq 'crash (possible duplicate)') -and ($cw2.Status -eq 'duplicate') -and (@($rs33 | Where-Object { $_ -like '*re-sent*' }).Count -eq 1) -and ($script:sent33 -contains 'lost (re-sent)') -and ($qd.Status -eq 'queued') -and (@($q33 | Where-Object { $_.key -eq $qk }).Count -eq 1)) 's33-crash-window-resends-marked-and-queues-once' "sent=$($script:sent33 -join '|') cw2=$($cw2.Status) q=$(@($q33).Count)"

# Item 6: a toast failing every morning still reads in the reconciler's
# log lines, with no toast involved.
$ml33 = @(Get-MorningDeliveryLines -StateDir $st33 -Now (Get-Date '2026-09-25 07:10') -Escalate { param($t, $l) $true })
Assert ((@($ml33 | Where-Object { $_ -like '- Delivery RED: 2 undelivered notification(s)*' }).Count -eq 1) -and (@($ml33 | Where-Object { $_ -like '*undelivered/r33a-*' }).Count -eq 1)) 's33-failing-toast-reads-in-the-morning-log' ($ml33 -join ' | ')

# Item 7: a recovery after an unacknowledged RED names the pending ack
# and the open corrective action on their own lines.
$gate33 = [pscustomobject]@{ Unacked = @('2026-09-24-023000-pid1'); Corrective = @('- CORRECTIVE ack-x.md (D00 T02 §9): open, due 2026-10-01 (owner operator)', '- CORRECTIVE ack-y.md (D00 T02 §9): closed (abc)') }
$rn33 = @(Get-RecoveryNotices (Select-CanonicalRuns $hist) $hist $hist[1] @() $gate33)
Assert (($rn33[0] -like 'Service recovered: night 2026-09-24 was RED*') -and ($rn33 -contains 'Pending acknowledgement: 1 RED run(s) still unacknowledged (2026-09-24-023000-pid1)') -and ($rn33 -contains 'Open corrective actions: 1 (ack-x.md (D00 T02 §9))')) 's33-recovery-names-pending-ack-and-open-actions' ($rn33 -join ' | ')

# Section 33 R1-A1: a dry run plans the escalation and never calls the
# channel. R1-C1: a success early on night D does not hide D's later
# failures. R1-I2: a successful digest send ends the episode.
$st33c = Join-Path $dir 'state33c'
$null = New-Item -ItemType Directory -Force -Path $st33c
Update-DeliveryRecord $st33c (Get-Date '2026-09-24 01:00') $true
Update-DeliveryRecord $st33c (Get-Date '2026-09-24 03:00') $false
Update-DeliveryRecord $st33c (Get-Date '2026-09-25 03:00') $false
$script:called33 = 0
$dry33 = @(Invoke-DeliveryEscalation -StateDir $st33c -Now (Get-Date '2026-09-25 07:05') -Escalate { param($t, $l) $script:called33++; $true } -NoPersist)
$real33 = @(Invoke-DeliveryEscalation -StateDir $st33c -Now (Get-Date '2026-09-25 07:05') -Escalate { param($t, $l) $script:called33++; $true })
$st33d = Join-Path $dir 'state33d'
$null = New-Item -ItemType Directory -Force -Path $st33d
Update-DeliveryRecord $st33d (Get-Date '2026-09-24 03:00') $false
@([pscustomobject]@{ key = 'g1'; run = 'r'; class = 'green'; title = 't'; lines = @('x'); at = '2026-09-25T03:00:00+02:00' }) | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $st33d 'digest-queue.json') -Encoding UTF8
$null = Invoke-DigestFlush -StateDir $st33d -Day '2026-09-25' -Sender { param($t, $l) $true } -Now (Get-Date '2026-09-25 07:05')
Update-DeliveryRecord $st33d (Get-Date '2026-09-26 03:00') $false
$dg33 = @(Invoke-DeliveryEscalation -StateDir $st33d -Now (Get-Date '2026-09-26 07:05') -Escalate { param($t, $l) $script:called33++; $true })
Assert (($dry33[0] -like '*would escalate the episode from 2026-09-24*dry run: not sent*') -and ($real33[0] -like '- Delivery escalation: sent*episode from 2026-09-24*') -and ($script:called33 -eq 1) -and ($dg33.Count -eq 0)) 's33-escalation-dry-run-event-order-and-digest-success' "$($dry33 -join '|') / $($real33 -join '|') / called $script:called33 / $($dg33 -join '|')"

# R1-I1: an intent a crashed run left behind carries its payload, and the
# morning reconciler re-sends it marked as a possible duplicate.
$st33e = Join-Path $dir 'state33e'
$null = New-Item -ItemType Directory -Force -Path $st33e
ConvertTo-Json @([pscustomobject]@{ key = 'crash|noresult|v1'; run = 'crashed-run'; class = 'infrastructure'; channel = 'immediate'; at = '2026-09-25T03:00:00+02:00'; status = 'sending'; title = 'Nightly 2026-09-25 : RED (infrastructure)'; lines = @('boom') }) -Depth 4 | Set-Content -Path (Join-Path $st33e 'notify-ledger.json') -Encoding UTF8
$script:sent33e = @()
$ri33 = @(Invoke-UndeliveredResend -StateDir $st33e -Sender { param($t, $l) $script:sent33e += $t; $true })
$led33e = @(Get-Content (Join-Path $st33e 'notify-ledger.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
Assert (($script:sent33e -contains 'Nightly 2026-09-25 : RED (infrastructure) (possible duplicate)') -and ($led33e[0].status -eq 'sent') -and (@($ri33 | Where-Object { $_ -like 'intent crash|noresult|v1: re-sent*' }).Count -eq 1)) 's33-reconciler-resends-a-crashed-intent' "$($script:sent33e -join '|') / $($led33e[0].status) / $($ri33 -join '|')"

# Section 33 R2-A1: sixty failures on D+1 never push D's failure out, so
# the consecutive nights still escalate.
$st33f = Join-Path $dir 'state33f'
$null = New-Item -ItemType Directory -Force -Path $st33f
Update-DeliveryRecord $st33f (Get-Date '2026-09-24 03:00') $false
for ($i = 0; $i -lt 60; $i++) { Update-DeliveryRecord $st33f ((Get-Date '2026-09-25 03:00').AddSeconds($i)) $false }
$esc33f = @(Invoke-DeliveryEscalation -StateDir $st33f -Now (Get-Date '2026-09-25 07:05') -Escalate { param($t, $l) $true })
Assert ($esc33f[0] -like '- Delivery escalation: sent*episode from 2026-09-24*') 's33-many-failures-never-erase-the-earlier-night' ($esc33f -join '|')

# R2-C1: worsening compares to the magnitude actually delivered. +50 opens,
# +70 arrives before delivery, the delivery confirms +70; then +80 is
# not worsening (under 95) and +95 is, from 70.
$al33g = Join-Path $dir 'alerts33g.json'
$null = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-24 vs baseline 600s (+50%, median of 5 night(s))') $al33g ([pscustomobject]@{ Night = '2026-09-24'; Host = 'h0st0001'; Identity = 'g1' })
$null = Update-AlertLedger @('- ALERT runa-duration: 1020s on 2026-09-25 vs baseline 600s (+70%, median of 5 night(s))') $al33g ([pscustomobject]@{ Night = '2026-09-25'; Host = 'h0st0001'; Identity = 'g2' })
$pg = Get-PendingAlertNotifications $al33g; Confirm-AlertNotifications $al33g @($pg.Keys)
$null = Update-AlertLedger @('- ALERT runa-duration: 1080s on 2026-09-26 vs baseline 600s (+80%, median of 5 night(s))') $al33g ([pscustomobject]@{ Night = '2026-09-26'; Host = 'h0st0001'; Identity = 'g3' })
$pg2 = Get-PendingAlertNotifications $al33g
$null = Update-AlertLedger @('- ALERT runa-duration: 1170s on 2026-09-27 vs baseline 600s (+95%, median of 5 night(s))') $al33g ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'g4' })
$pg3 = Get-PendingAlertNotifications $al33g
Assert (($pg.Lines[0] -like 'ALERT runa-duration: 1020s*') -and (@($pg2.Lines).Count -eq 0) -and ($pg3.Lines[0] -like 'WORSENING (from 70 to 95): ALERT runa-duration: 1170s*')) 's33-worsening-compares-to-the-delivered-magnitude' "$($pg.Lines -join '|') / $($pg2.Lines -join '|') / $($pg3.Lines -join '|')"

# R2-I1: the notification selects from the trend's validated inputs. An
# invalid later timer result (GREEN with exit 1) derails the raw-JSON
# selection (it never names the valid run); the shared loader skips it, so the notification and the trend both
# speak for the valid run.
$nd33 = Join-Path $dir 'night33'
$null = New-Item -ItemType Directory -Force -Path $nd33
$v33 = New-Result '2026-09-26' '2026-09-26-023000' 'red' 'timer'
$v33 | Add-Member -NotePropertyName timings -NotePropertyValue ([pscustomobject]@{ build = 1 }) -Force
$v33.env.topology = '\\.\DISPLAY1 1920x1080+0+0 primary'; $v33.env.settings = 'BACKGROUND=1 WINDOW=x SPEC=y'
$bad33 = New-Result '2026-09-26' '2026-09-26-030000' 'green' 'timer'; $bad33.exit = 1
ConvertTo-Json $v33 -Depth 8 | Set-Content -Path (Join-Path $nd33 'morning-2026-09-26-023000.result.json') -Encoding UTF8
ConvertTo-Json $bad33 -Depth 8 | Set-Content -Path (Join-Path $nd33 'morning-2026-09-26-030000.result.json') -Encoding UTF8
$raw33 = @(Get-ChildItem $nd33 -Filter 'morning-*.result.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
$in33 = Get-TrendInputResults $nd33 (Join-Path $nd33 'metrics.jsonl')
$rawPick = (Select-CanonicalRuns $raw33)[(Get-NightSlotKey $v33)].Canonical
$vo33 = Get-NightVoice (Select-CanonicalRuns @($in33.Results)) $v33
Assert (($rawPick -ne '2026-09-26-023000-pid1') -and ($vo33.Canonical -eq '2026-09-26-023000-pid1') -and $vo33.IsVoice -and (@($in33.Skipped).Count -eq 1)) 's33-notify-selects-from-the-trend-inputs' "raw $rawPick; shared $($vo33.Canonical); skipped $(@($in33.Skipped) -join ',')"

# Section 33 R3-C1: a confirmation records the magnitude that was sent,
# not a later one; R3-I1: the recovery status survives the toast cap.
$al33h = Join-Path $dir 'alerts33h.json'
$null = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-24 vs baseline 600s (+50%, median of 5 night(s))') $al33h ([pscustomobject]@{ Night = '2026-09-24'; Host = 'h0st0001'; Identity = 'h1' })
$snap = Get-PendingAlertNotifications $al33h
$null = Update-AlertLedger @('- ALERT runa-duration: 1200s on 2026-09-25 vs baseline 600s (+100%, median of 5 night(s))') $al33h ([pscustomobject]@{ Night = '2026-09-25'; Host = 'h0st0001'; Identity = 'h2' })
Confirm-AlertNotifications $al33h @($snap.Keys)
$eh = @((Read-AlertLedger $al33h).alerts)[0]
$null = Update-AlertLedger @('- ALERT runa-duration: 1200s on 2026-09-26 vs baseline 600s (+100%, median of 5 night(s))') $al33h ([pscustomobject]@{ Night = '2026-09-26'; Host = 'h0st0001'; Identity = 'h3' })
$ph = Get-PendingAlertNotifications $al33h
Assert (("$($eh.notifiedMagnitude)" -eq '50') -and ($ph.Lines[0] -like 'WORSENING (from 50 to 100)*')) 's33-confirm-records-the-sent-magnitude' "notified $($eh.notifiedMagnitude); $($ph.Lines -join '|')"
$recN = @('Recovered: INC-00000001 UI.A (closed on verified recovery)', 'Recovered: INC-00000002 UI.B (closed on verified recovery)', 'Recovered: INC-00000003 UI.C (closed on verified recovery)', 'Recovered: INC-00000004 UI.D (closed on verified recovery)', 'Service recovered: night 2026-09-24 was RED, 2026-09-25 is GREEN', 'Pending acknowledgement: none', 'Open corrective actions: 1 (ack-x.md (D00 T02 §9))')
$toast33 = @(Format-ToastLines (@(New-ToastItem 2 'top incident') + @(Get-RecoveryToastItems $recN) + @(New-ToastItem 5 'counts')) 'build/nightly/morning-x.md')
Assert ((@($toast33 | Where-Object { $_ -like 'Service recovered:*' }).Count -eq 1) -and (@($toast33 | Where-Object { $_ -like 'Pending acknowledgement:*' }).Count -eq 1) -and (@($toast33 | Where-Object { $_ -like 'Open corrective actions: 1*' }).Count -eq 1)) 's33-recovery-status-survives-the-toast-cap' ($toast33 -join ' | ')

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyNotify.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyNotify.Tests: all green'
exit 0
