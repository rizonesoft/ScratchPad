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
  return [pscustomobject]@{ version = 1; day = $Day; stamp = $Stamp; identity = "$Stamp-pid1"; verdict = $Verdict; exit = $(if ($Verdict -eq 'green') { 0 } else { 1 }); simulated = $Sim; launch = $Launch; trigger = 'x'; buildError = ''; omissionOk = $true; recovered = 'none'; legs = [pscustomobject]@{ 'run-a' = $leg; 'run-b' = $legB; interactive = $legI }; soak = [pscustomobject]@{ verdict = 'green'; failed = 0; killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; incidents = @(); reserve = 900; env = [pscustomobject]@{ os = '10.0.26200.0'; dpi = 'primary 96x96' } }
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
Assert ($canon['2026-09-23'].Canonical -eq '2026-09-23-023011-pid1') 'canonical-timer-wins' $canon['2026-09-23'].Canonical
Assert ($canon['2026-09-24'].Canonical -eq '2026-09-24-121212-pid1') 'canonical-demand-beats-manual' $canon['2026-09-24'].Canonical
Assert (($canon['2026-09-23'].Others['2026-09-23-050000-pid1'] -eq 'simulation') -and ($canon['2026-09-23'].Others['2026-09-23-060000-pid1'] -eq 'stood-down loser') -and ($canon['2026-09-23'].Others['2026-09-23-040435-pid1'] -like 'retry (manual launch*')) 'canonical-others-carry-reasons' (($canon['2026-09-23'].Others.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')
$trend = @(Format-TrendTable $heavy @{ Overdue = @(); DueSoon = @() } (Get-Date '2026-09-25'))
Assert (@($trend | Where-Object { $_ -like '| 2026-09-23 (retry) |*' }).Count -eq 3) 'canonical-trend-marks-retries' (($trend | Where-Object { $_ -like '| 2026-09-23*' }) -join ' || ')
Assert (@($trend | Where-Object { $_ -eq '- RunA test-seconds p50/median: 800 (n=2, max=800)' }).Count -eq 1) 'canonical-p50-counts-nights-not-attempts' (($trend | Where-Object { $_ -like '*p50*' }) -join '')
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
Assert (($n3.Status -eq 'fallback') -and ($n3.Attempts -eq 3) -and ($script:sent -eq 3) -and (Test-Path (Join-Path $state 'undelivered\r2.json'))) 'notify-failure-retries-then-falls-back' "$($n3.Status) attempts=$($n3.Attempts) $($n3.Notes -join '; ')"
$dh = Get-DeliveryHealth $state
Assert ((-not $dh.Ok) -and ($dh.Count -eq 1) -and ($dh.Lines[0] -like '- Delivery RED: 1 undelivered notification(s); escalate operator*')) 'notify-delivery-health-escalates' ($dh.Lines -join ' | ')
$script:sent = 0
$n4 = Invoke-NightlyNotify -Phase 'final' -RunId 'r3' -ResultPath $resPath -Class 'test' -Title 'routine' -Lines @('a') -StateDir $state -Sender $okSender
$q = @(Get-Content (Join-Path $state 'digest-queue.json') -Raw | ConvertFrom-Json)
Assert (($n4.Status -eq 'queued') -and ($script:sent -eq 0) -and ($q.Count -eq 1) -and ($q[0].run -eq 'r3')) 'notify-routine-night-digests' "$($n4.Status) sent=$($script:sent) q=$($q.Count)"
Assert ($n1.Status -eq 'sent') 'notify-urgent-night-interrupts'
$dg = Format-Digest @($q + @([pscustomobject]@{ run = 'r9'; class = 'infrastructure' })) '2026-09-25'
Assert (($dg.Title -eq 'Nightly digest 2026-09-25 : 2 run(s)') -and ($dg.Lines[0] -like '1 x infrastructure*')) 'notify-digest-worst-class-first' ($dg.Lines -join ' | ')
Assert ($null -eq (Format-Digest @() 'd')) 'notify-empty-digest-sends-nothing'

# Item 4: the no-start check alerts without any governed run firing.
$ns = Get-NoStartVerdict @((New-Result '2026-09-24' '2026-09-24-023000' 'green' 'timer')) (Get-Date '2026-09-25 07:05') '06:50'
Assert ($ns.NoStart -and ($ns.Line -like 'NO START: no scheduled nightly result for 2026-09-25 by 06:50*')) 'nostart-suppressed-night-alerts' $ns.Line
Assert (-not (Get-NoStartVerdict @() (Get-Date '2026-09-25 05:00') '06:50').NoStart) 'nostart-waits-for-the-window'
Assert (-not (Get-NoStartVerdict @((New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer')) (Get-Date '2026-09-25 07:05') '06:50').NoStart) 'nostart-started-night-passes'
Assert ((Get-NoStartVerdict @((New-Result '2026-09-25' '2026-09-25-043000' 'red' 'manual')) (Get-Date '2026-09-25 07:05') '06:50').NoStart) 'nostart-manual-run-is-not-a-start'
$mDir = Join-Path $dir 'morning'
$null = New-Item -ItemType Directory -Force -Path $mDir
$mOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyMorning.ps1') -DryRun -NightDir $mDir -ExpectBy '00:00' 2>&1 | ForEach-Object { "$_" })
Assert ((@($mOut | Where-Object { $_ -like 'morning: no-start: NO START*' }).Count -eq 1) -and (@($mOut | Where-Object { $_ -like 'morning: no-start notify: sent*' }).Count -eq 1)) 'nostart-reconciler-alerts-with-no-run' ($mOut -join ' | ')

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
$rep = @('| Run A (default) | 10 passed, 0 failed, 1 skipped (UI.dll 10/0/1) | exit 0 changes logged | - | log |', '| Run B (primary) | 4 passed, 0 failed, 0 skipped (UI.dll 4/0/0) | exit 0 x | - | log |', '| Interactive (collection) | 3 passed, 0 failed, 0 skipped (UI.dll 3/0/0) | n/a (owns the foreground) | - | log |', '', '## Incidents', '', '- INC-aaaa1111 `UI.A` x1 (Run A): boom', '', '## Run integrity', '- Timings: build=1s reserve=900s', '- Environment: os 10.0.26200.0; dpi primary 96x96', '- Exit: 1')
Assert ((Test-ReportResultAgreement $rep $agreeRes).Ok) 'agree-consistent-report-passes' ((Test-ReportResultAgreement $rep $agreeRes).Breaks -join '; ')
$bad = @($rep | ForEach-Object { $_ -replace '^\| Run B \(primary\) \| 4 passed', '| Run B (primary) | 5 passed' })
Assert (@((Test-ReportResultAgreement $bad $agreeRes).Breaks | Where-Object { $_ -eq 'run-b passed: report 5 vs result 4' }).Count -eq 1) 'agree-count-contradiction-fails' ((Test-ReportResultAgreement $bad $agreeRes).Breaks -join '; ')
$bad2 = @($rep | Where-Object { $_ -notlike '- INC-*' })
Assert (@((Test-ReportResultAgreement $bad2 $agreeRes).Breaks | Where-Object { $_ -eq 'incidents: report [] vs result [INC-aaaa1111]' }).Count -eq 1) 'agree-incident-contradiction-fails' ((Test-ReportResultAgreement $bad2 $agreeRes).Breaks -join '; ')
$bad3 = @($rep | ForEach-Object { $_ -replace 'reserve=900s', 'reserve=901s' } | ForEach-Object { $_ -replace 'exit 0 changes', 'exit 1 changes' })
$b3 = @((Test-ReportResultAgreement $bad3 $agreeRes).Breaks)
Assert ((@($b3 | Where-Object { $_ -eq 'reserve: report 901s vs result 900' }).Count -eq 1) -and (@($b3 | Where-Object { $_ -eq 'run-a gate: report exit 1 vs result 0' }).Count -eq 1)) 'agree-reserve-and-gate-contradictions-fail' ($b3 -join '; ')
$bad4 = @($rep | Where-Object { $_ -notlike '- Environment:*' })
Assert (@((Test-ReportResultAgreement $bad4 $agreeRes).Breaks | Where-Object { $_ -eq 'environment: report carries no Environment line' }).Count -eq 1) 'agree-missing-environment-fails'

# Item 13: recovery notices, night-level and incident-level.
$hist = @((New-Result '2026-09-24' '2026-09-24-023000' 'red' 'timer'), (New-Result '2026-09-25' '2026-09-25-023000' 'green' 'timer'))
$rn = @(Get-RecoveryNotices (Select-CanonicalRuns $hist) $hist $hist[1] @('- INC-aaaa1111 `UI.A`: CLOSED (verified recovery: passed in run-a on 3 runs through s)'))
Assert ((($rn -join ' | ') -eq 'Recovered: night 2026-09-24 was RED, 2026-09-25 is GREEN | Recovered: INC-aaaa1111 UI.A (closed on verified recovery)')) 'recovery-notice-night-and-incident' ($rn -join ' | ')
$still = @(Get-RecoveryNotices (Select-CanonicalRuns $hist) $hist (New-Result '2026-09-25' '2026-09-25-023000' 'red' 'timer') @())
Assert ($still.Count -eq 0) 'recovery-none-while-red'

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
Assert (@($evTrend | Where-Object { $_ -like '- Incident evidence (2026-09-25): INC-aaaa1111 bundle *bundle.json; screenshot *leak.png; launch-record *' }).Count -eq 1) 'evidence-rides-the-trend' (($evTrend | Where-Object { $_ -like '*evidence*' }) -join '')

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyNotify.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyNotify.Tests: all green'
exit 0
