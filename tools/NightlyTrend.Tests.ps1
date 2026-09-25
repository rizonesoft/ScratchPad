# Trend and telemetry fixture suite (D00 T02 §25). Self-contained:
# builds results under TEMP, drives the real functions plus
# tools/NightlyTrend.ps1 end to end, and exits nonzero on any failure.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
$dir = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-trend-fixtures'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $dir

function New-Night([string]$Night, [string]$Stamp, [int]$RunA = 600, [string]$Launch = 'timer', [int]$Passed = 100, [int]$Failed = 0, [int]$Skipped = 5, [string[]]$Incidents = @(), [bool]$Sim = $false, [string]$Verdict = '') {
  if ($Verdict -eq '') { $Verdict = if ($Failed -gt 0) { 'red' } else { 'green' } }
  $a = [pscustomobject]@{ ran = $true; passed = $Passed; failed = $Failed; skipped = $Skipped; gate = 0; killed = $false; cut = $false; testSeconds = $RunA }
  $b = [pscustomobject]@{ ran = $true; passed = 4; failed = 0; skipped = 0; gate = 0; killed = $false; cut = $false; testSeconds = 20 }
  $i = [pscustomobject]@{ ran = $false; passed = 0; failed = 0; skipped = 0; killed = $false; cut = $false; enforcementRed = $false }
  return [pscustomobject]@{ version = 1; day = $Night; night = $Night; stamp = $Stamp; identity = "$Stamp-pid1"; verdict = $Verdict; exit = $(if ($Verdict -eq 'green') { 0 } else { 1 }); simulated = $Sim; launch = $Launch; trigger = 't'; buildError = ''; omissionOk = $true; recovered = 'none'; legs = [pscustomobject]@{ 'run-a' = $a; 'run-b' = $b; interactive = $i }; soak = [pscustomobject]@{ verdict = 'green'; failed = 0; killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; incidents = @($Incidents); reserve = 900; consumed = 600; timings = @{ build = 1 }; env = [pscustomobject]@{ os = '10.0.26200.0'; dpi = 'primary 96x96' } }
}
$Q = @{ Overdue = @(); DueSoon = @() }
$today = Get-Date '2026-09-30'


# D00 T02 section 30 item 5: identity aliases join a contract v1
# sighting (before 2026-09-25) and a v2 sighting of one failure.
$v1Night = New-Night '2026-09-22' '2026-09-22-023006' 600 'timer' 99 1 5 @('- INC-cd55f7ca `UI.MainWindowTests.FirstRunShowsWhatsNew` x1 (ui-soak-1): Assert.NotNull() Failure: Value is null')
$v2Night = New-Night '2026-09-26' '2026-09-26-023006' 600 'timer' 99 1 5 @('- INC-1a2b3c4d `UI.MainWindowTests.FirstRunShowsWhatsNew` x1 (ui-soak-2): Assert.NotNull() Failure: Value is null')
$aliasMap = Get-IncidentAliases @($v1Night, $v2Night)
Assert (($aliasMap.Count -eq 1) -and ($aliasMap['INC-cd55f7ca'] -eq 'INC-1a2b3c4d')) 'alias-maps-v1-to-v2' (($aliasMap.Keys | ForEach-Object { "$_=$($aliasMap[$_])" }) -join ',')
$tAlias = @(Format-TrendTable @($v1Night, $v2Night) $Q $today)
Assert ((@($tAlias | Where-Object { $_ -like '- Flake recurrence: INC-1a2b3c4d (2026-09-22, 2026-09-26)*' }).Count -eq 1) -and (@($tAlias | Where-Object { $_ -eq '- Identity aliases (contract v1 to v2): INC-cd55f7ca -> INC-1a2b3c4d' }).Count -eq 1)) 'alias-joins-recurrence' (($tAlias | Where-Object { $_ -like '- Flake*' -or $_ -like '- Identity*' }) -join ' | ')
$v2Other = New-Night '2026-09-27' '2026-09-27-023006' 600 'timer' 99 1 5 @('- INC-99999999 `UI.MainWindowTests.FirstRunShowsWhatsNew` x1 (ui-soak-3): Assert.NotNull() Failure: Value is null')
Assert ((Get-IncidentAliases @($v1Night, $v2Night, $v2Other)).Count -eq 0) 'alias-ambiguity-keeps-old-id'

# Item 1: the denominator rule.
$mixed = New-Night '2026-09-20' '2026-09-20-023000' 600 'timer' 90 10 50
$t1 = @(Format-TrendTable @($mixed) $Q $today)
Assert (@($t1 | Where-Object { $_ -like '| 2026-09-20 | red |*| 94/10/50 (90.4% of 104 executed) |*' }).Count -eq 1) 'denominator-excludes-skips' (($t1 | Where-Object { $_ -like '| 2026-09-20*' }) -join '')
Assert (@($t1 | Where-Object { $_ -like '- Pass rate: passed / (passed + failed) over executed tests*' }).Count -eq 1) 'denominator-rule-reads'
$killed = New-Night '2026-09-21' '2026-09-21-023000'
$killed.legs.'run-a'.killed = $true
Assert (@(Format-TrendTable @($killed) $Q $today | Where-Object { $_ -like '*| 104/0/5 unproven (killed or cut leg) |*' }).Count -eq 1) 'denominator-killed-leg-unproven'

# Item 2: series inclusion; a mixed corpus draws no false slope.
$corpus = @(
  (New-Night '2026-09-20' '2026-09-20-023000' 600), (New-Night '2026-09-21' '2026-09-21-023000' 610), (New-Night '2026-09-22' '2026-09-22-023000' 620),
  (New-Night '2026-09-22' '2026-09-22-090000' 3000 'manual'),
  (New-Night '2026-09-23' '2026-09-23-023000' 9999 'timer' 100 0 5 @() $true),
  (New-Night '2026-09-23' '2026-09-23-030000' 615)
)
$bf = New-Night '2026-09-24' '2026-09-24-023000' 5000
$bf | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'leg transcripts'; confidence = 'derived' }; 'env' = [pscustomobject]@{ source = 'none'; confidence = 'unknown' } })
$corpus += $bf
$tc = @(Format-TrendTable $corpus $Q $today)
Assert (@($tc | Where-Object { $_ -eq '- RunA test-seconds (canonical native nights, last 14): n=4, p50 610, p90 620, p95 620 (= max: n=4 < 20), max 620 [native]' }).Count -eq 1) 'series-native-canonical-only' (($tc | Where-Object { $_ -like '*RunA test-seconds*' }) -join '')
$ai = [array]::IndexOf($tc, '## Alerts')
Assert (($tc[$ai + 3] -like '- Insufficient data: runa-duration (3 measured baseline night(s) of 5 needed*') -and (@($tc | Where-Object { $_ -like '- ALERT *' }).Count -eq 0)) 'series-mixed-corpus-no-false-slope' ($tc[$ai + 2])
Assert (@($tc | Where-Object { $_ -like '| 2026-09-24 (backfill) |*' }).Count -eq 1) 'series-backfill-marked'
Assert (@($tc | Where-Object { $_ -like '- Series: durations, percentiles, and alerts read canonical native nights*' }).Count -eq 1) 'series-rule-reads'

# Item 3: nights group by run identity plus timezone.
Assert ((Get-NightKey ([datetime]'2026-09-24 23:50')) -eq '2026-09-25') 'night-overnight-run-groups-forward'
Assert ((Get-NightKey ([datetime]'2026-09-25 02:30')) -eq '2026-09-25') 'night-timer-run-keeps-its-date'
$tzA = [pscustomobject]@{ day = '2026-09-25'; startUtc = '2026-09-25T00:30:00Z'; tz = '+02:00' }
$tzB = [pscustomobject]@{ day = '2026-09-24'; startUtc = '2026-09-25T00:30:00Z'; tz = '-05:00' }
Assert (((Get-ResultNight $tzA) -eq '2026-09-25') -and ((Get-ResultNight $tzB) -eq '2026-09-25')) 'night-timezone-move-groups-correctly' "$(Get-ResultNight $tzA) / $(Get-ResultNight $tzB)"
Assert ((Get-ResultNight ([pscustomobject]@{ day = '2026-09-19' })) -eq '2026-09-19') 'night-legacy-result-uses-day'
$jsonRound = ('{"day":"2026-09-24","startUtc":"2026-09-24T22:45:00.0000000Z","tz":"+02:00"}' | ConvertFrom-Json)
Assert ((Get-ResultNight $jsonRound) -eq '2026-09-25') 'night-json-roundtrip-datetime' "$(Get-ResultNight $jsonRound) ($($jsonRound.startUtc.GetType().Name))"
$ci = [System.Threading.Thread]::CurrentThread.CurrentCulture
try { [System.Threading.Thread]::CurrentThread.CurrentCulture = 'en-GB'; Assert ((Get-ResultNight $jsonRound) -eq '2026-09-25') 'night-day-first-culture' (Get-ResultNight $jsonRound) } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci }

# Item 4: the seven correctness fixtures.
$gap = @((New-Night '2026-09-22' '2026-09-22-023000'), (New-Night '2026-09-20' '2026-09-20-023000'))
$tg = @(Format-TrendTable $gap $Q $today)
Assert (@($tg | Where-Object { $_ -like '| 2026-09-21 | missing |*' }).Count -eq 1) 'fixture-missing-night'
$rowsOnly = @($tg | Where-Object { $_ -like '| 2026-09-2*' })
Assert ((($rowsOnly | ForEach-Object { $_.Substring(2, 10) }) -join ',') -eq '2026-09-20,2026-09-21,2026-09-22,2026-09-23,2026-09-24,2026-09-25,2026-09-26,2026-09-27,2026-09-28,2026-09-29') 'fixture-out-of-order-sorted' (($rowsOnly | ForEach-Object { $_.Substring(2, 10) }) -join ',')
$dup = @((New-Night '2026-09-20' '2026-09-20-023000' 600), (New-Night '2026-09-20' '2026-09-20-023000' 600))
$dup[1].identity = '2026-09-20-023000-pid2'
Assert (@(Format-TrendTable $dup $Q $today | Where-Object { $_ -like '| 2026-09-20 (retry) |*' }).Count -eq 1) 'fixture-duplicate-night-one-canonical'
Assert (@($tc | Where-Object { $_ -like '| 2026-09-22 (retry) |*' }).Count -eq 1) 'fixture-retry-marked'
$tzNight = New-Night '2026-09-25' '2026-09-25-023000'
$tzNight.night = $null
$tzNight | Add-Member -NotePropertyName startUtc -NotePropertyValue '2026-09-24T22:45:00Z'
$tzNight | Add-Member -NotePropertyName tz -NotePropertyValue '+02:00'
Assert ((Get-ResultNight $tzNight) -eq '2026-09-25') 'fixture-clock-change-uses-recorded-offset' (Get-ResultNight $tzNight)

# Items 4 and 7 end to end: a corrupted result is skipped with a note,
# and a pruned night renders from the metrics store.
$nd = Join-Path $dir 'night'
$null = New-Item -ItemType Directory -Force -Path $nd
$full = New-Night '2026-09-20' '2026-09-20-023000'
$full.env = [pscustomobject]@{ os = '10.0.26200.0'; powershell = '5.1.26100.9444'; dotnet = '10.0.400'; session = 'op/Console'; topology = '\\.\DISPLAY1 2560x1440+0+0 primary'; dpi = 'primary 96x96'; adapters = 'GPU'; settings = 'BACKGROUND= WINDOW= SPEC=' }
foreach ($n in @('2026-09-20', '2026-09-21')) {
  $x = $full.PSObject.Copy(); $x.day = $n; $x.night = $n; $x.stamp = "$n-023000"; $x.identity = "$n-023000-pid1"
  (ConvertTo-Json $x -Depth 6) | Set-Content -Path (Join-Path $nd "morning-$n-023000.result.json") -Encoding UTF8
}
'{ corrupt' | Set-Content -Path (Join-Path $nd 'morning-2026-09-22-023000.result.json') -Encoding UTF8
$qdoc = Join-Path $dir 'q.md'
@('# q', '', '## Quarantine list', '', '| Test | Failure signature | First seen | Owner | Quarantined | Due |', '| --- | --- | --- | --- | --- | --- |') | Set-Content -Path $qdoc -Encoding UTF8
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyTrend.ps1') -NightDir $nd -OutFile (Join-Path $nd 'trend.md') -LedgerPath $qdoc 2>&1
Remove-Item (Join-Path $nd 'morning-2026-09-20-023000.result.json') -Force
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyTrend.ps1') -NightDir $nd -OutFile (Join-Path $nd 'trend.md') -LedgerPath $qdoc 2>&1
$tr = @(Get-Content (Join-Path $nd 'trend.md') -Encoding UTF8)
Assert (@($tr | Where-Object { $_ -like '- Skipped invalid results:*morning-2026-09-22-023000.result.json*' }).Count -eq 1) 'fixture-corrupted-result-skipped' (($tr | Where-Object { $_ -like '*Skipped*' }) -join '')
Assert (@($tr | Where-Object { $_ -like '| 2026-09-20 (metrics) |*' }).Count -eq 1) 'fixture-retention-boundary-metrics-row' (($tr | Where-Object { $_ -like '| 2026-09-2*' }) -join ' || ')
Assert (@($tr | Where-Object { $_ -eq '- Metrics store: 2 row(s), 1 night(s) rendered from metrics after pruning' }).Count -eq 1) 'metrics-store-outlives-retention' (($tr | Where-Object { $_ -like '*Metrics store*' }) -join '')
$mrows = @(Sync-MetricsStore (Join-Path $nd 'metrics.jsonl') @($full))
Assert ((@(Get-Content (Join-Path $nd 'metrics.jsonl') | Where-Object { $_.Trim() -ne '' }).Count -eq 2) -and ($mrows.Count -eq 2)) 'metrics-store-idempotent-per-identity'

# Item 5: count plus tail percentiles.
$tail = @(10..24 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) (500 + 10 * ($_ - 10)) })
$tt = @(Format-TrendTable $tail $Q $today)
Assert (@($tt | Where-Object { $_ -eq '- RunA test-seconds (canonical native nights, last 14): n=14, p50 570, p90 630, p95 640 (= max: n=14 < 20), max 640 [native]' }).Count -eq 1) 'percentiles-count-and-tails' (($tt | Where-Object { $_ -like '*RunA test-seconds*' }) -join '')

# Item 6: planted regressions alert with their baseline delta.
$base = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 'timer' 100 0 5 @() })
$slow = @($base) + @(New-Night '2026-09-27' '2026-09-27-023000' 900 'timer' 90 10 5 @('- INC-aaaa1111 `UI.A` x1 (Run A): boom'))
$slow[-2].incidents = @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
$al = @(Get-TrendAlerts $slow)
Assert (@($al | Where-Object { $_ -eq '- ALERT runa-duration: 900s on 2026-09-27 vs baseline 600s (+50%, median of 7 night(s))' }).Count -eq 1) 'alert-duration-regression' ($al -join ' | ')
Assert (@($al | Where-Object { $_ -eq '- ALERT pass-rate: 90.4% on 2026-09-27 vs baseline 100% (-9.6 points, median of 7 night(s))' }).Count -eq 1) 'alert-pass-rate-regression' ($al -join ' | ')
Assert (@($al | Where-Object { $_ -eq '- ALERT recurring-flake: INC-aaaa1111 on 2026-09-27 and 2026-09-26' }).Count -eq 1) 'alert-recurring-flake' ($al -join ' | ')
Assert (@(Get-TrendAlerts $base).Count -eq 0) 'alert-steady-series-quiet'

# Item 8: every consumed env field validates, unknowns read unknown.
$goodEnv = [pscustomobject]@{ os = '10.0.26200.0'; powershell = '5.1.26100.9444'; dotnet = '10.0.400'; session = 'DerickPayne/Console'; topology = '\\.\DISPLAY1 2560x1440+0+0 primary; \\.\DISPLAY2 1920x1080+-1920+1080'; dpi = 'primary 96x96'; adapters = 'NVIDIA GeForce RTX 2060'; settings = 'BACKGROUND= WINDOW= SPEC=' }
Assert ((Test-EnvironmentFields $goodEnv).Ok) 'env-real-block-validates' ((Test-EnvironmentFields $goodEnv).Error)
$unk = [pscustomobject]@{ os = 'unknown'; powershell = 'unknown'; dotnet = 'unknown'; session = 'unknown'; topology = 'unknown (forms unavailable)'; dpi = 'unknown'; adapters = 'unknown'; settings = 'unknown'; basis = 'backfilled' }
Assert ((Test-EnvironmentFields $unk).Ok) 'env-unknown-state-validates' ((Test-EnvironmentFields $unk).Error)
Assert ((Test-EnvironmentFields ([pscustomobject]@{ os = '10.0' })).Ok) 'env-missing-fields-read-unknown'
foreach ($bad in @(@('dpi', '96'), @('os', 'Windows'), @('topology', 'C:\secret'), @('settings', 'BACKGROUND=1'), @('session', 'a/b/c'))) {
  $e = $goodEnv.PSObject.Copy(); $e.($bad[0]) = $bad[1]
  Assert (-not (Test-EnvironmentFields $e).Ok) "env-$($bad[0])-malformed-fails" ((Test-EnvironmentFields $e).Error)
}
$extra = $goodEnv.PSObject.Copy(); $extra | Add-Member -NotePropertyName harness -NotePropertyValue 'x'
Assert ((Test-EnvironmentFields $extra).Error -eq 'env field not allowlisted: harness') 'env-unlisted-field-fails'

# Item 9: a backfilled row quotes its provenance per field.
Assert (@($tc | Where-Object { $_ -eq '- Backfill provenance (2026-09-24 2026-09-24-023000): legs.counts derived from leg transcripts; env unknown from none' }).Count -eq 1) 'backfill-provenance-per-field' (($tc | Where-Object { $_ -like '*provenance*' }) -join '')

# Item 10: the allowlist drops unknown keys, secrets and paths redact.
$planted = [pscustomobject]@{ os = '10.0.26200.0'; powershell = '5.1'; dotnet = '10.0.400'; session = 'op/Console'; topology = '\\.\DISPLAY1 2560x1440+0+0 primary'; dpi = 'primary 96x96'; adapters = 'GPU'; settings = ('BACKGROUND=1 WINDOW=token=' + 'ghp_' + ('A1b2C3d4E5' * 4) + ' SPEC=C:\Users\op\private.txt'); harness = 'secret-harness' }
$pe = Protect-EnvironmentBlock $planted
Assert ((@($pe.PSObject.Properties.Name) -join ',') -eq 'os,powershell,dotnet,session,topology,dpi,adapters,settings') 'env-allowlist-drops-unknown-keys' (@($pe.PSObject.Properties.Name) -join ',')
Assert (($pe.settings -like '`[redacted: *github-token*`]') -and ($pe.settings -notlike '*ghp_*')) 'env-planted-secret-redacted' $pe.settings
Assert ($pe.topology -eq '\\.\DISPLAY1 2560x1440+0+0 primary') 'env-display-names-are-not-paths' $pe.topology
$pathOnly = Protect-EnvironmentBlock ([pscustomobject]@{ settings = 'BACKGROUND= WINDOW= SPEC=C:\Users\op\private.txt' })
Assert ($pathOnly.settings -eq 'BACKGROUND= WINDOW= SPEC=[path]') 'env-path-redacted' $pathOnly.settings
$leak = $goodEnv.PSObject.Copy(); $leak.adapters = 'GPU ' + 'ghp_' + ('A1b2C3d4E5' * 4)
Assert ((Test-EnvironmentFields $leak).Error -eq 'env adapters carries a secret-shaped value') 'env-secret-fails-validation' ((Test-EnvironmentFields $leak).Error)

# R1-F1: a path with spaces redacts whole, and the next field survives.
$sp = Protect-EnvironmentBlock ([pscustomobject]@{ settings = 'BACKGROUND= WINDOW=C:\Users\Private Person\confidential.txt SPEC=x' })
Assert ($sp.settings -eq 'BACKGROUND= WINDOW=[path] SPEC=x') 'env-path-with-spaces-redacted-whole' $sp.settings
$unc = Protect-EnvironmentBlock ([pscustomobject]@{ adapters = 'GPU \\fileserver\Share Name\doc.txt' })
Assert ($unc.adapters -eq 'GPU [path]') 'env-unc-path-redacted' $unc.adapters
# R1-F2: the basis note is secret-scanned too.
$bs = [pscustomobject]@{ os = 'unknown'; basis = ('note ' + 'ghp_' + ('A1b2C3d4E5' * 4)) }
Assert ((Test-EnvironmentFields $bs).Error -eq 'env basis carries a secret-shaped value') 'env-basis-secret-fails' ((Test-EnvironmentFields $bs).Error)
# R1-F3: an unproven night neither sets nor breaks the pass-rate baseline.
$pr = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$uk = New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 10 50 5
$uk.legs.'run-a'.cut = $true
Assert (@(Get-TrendAlerts (@($pr) + @($uk)) | Where-Object { $_ -like '- ALERT pass-rate*' }).Count -eq 0) 'alert-unproven-night-has-no-rate'
# R1-F4: a pruned backfill keeps its marker and provenance.
$bfr = New-Night '2026-09-24' '2026-09-24-023000' 5000
$bfr | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'rows in morning-x.md'; confidence = 'derived' } })
$mrow = (ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $bfr)) -Depth 6 -Compress) | ConvertFrom-Json
$back = ConvertFrom-MetricsRow $mrow
$tb = @(Format-TrendTable @($back) $Q $today)
Assert ((@($tb | Where-Object { $_ -like '| 2026-09-24 (backfill) (metrics) |*' }).Count -eq 1) -and (@($tb | Where-Object { $_ -like '- Backfill provenance (2026-09-24 2026-09-24-023000): legs.counts derived from rows in morning-x.md' }).Count -eq 1)) 'metrics-backfill-keeps-marker-and-provenance' (($tb | Where-Object { ($_ -like '| 2026*') -or ($_ -like '*provenance*') }) -join ' || ')
# R1-F6 plus R2-F3: a backfill over a synthesized run directory (inside
# this fixture, no historical artifact needed) names its artifacts.
$run = Join-Path $dir 'bfrun'
$null = New-Item -ItemType Directory -Force -Path $run
@('# Morning report: 2026-09-20', 'Status: final', '', '- HEAD: 0000000', '- Run identity: 2026-09-20-023000-pid7', '- Trigger: task \ScratchPad\Nightly UI (timer)', '', '| Leg | Counts | Gate | Infra | Log |', '| --- | --- | --- | --- | --- |', '| Run A (default) | 10 passed, 0 failed, 1 skipped | exit 0 | - | 2026-09-20-023000-default.log |', '| Run B (primary) | 4 passed, 0 failed, 0 skipped | exit 0 | - | 2026-09-20-023000-primary.log |', '| Interactive (collection) | 3 passed, 0 failed, 0 skipped | n/a | - | 2026-09-20-023000-full.log |') | Set-Content -Path (Join-Path $run 'morning-2026-09-20-023000.md') -Encoding UTF8
'Passed!  - Failed:     0, Passed:    10, Skipped:     1, Total:    11, Duration: 1 s - UI.dll (net10.0)' | Set-Content -Path (Join-Path $run '2026-09-20-023000-default.log') -Encoding UTF8
@('Passed!  - Failed:     0, Passed:     4, Skipped:     0, Total:     4, Duration: 1 s - UI.dll (net10.0)', 'test-seconds: 12') | Set-Content -Path (Join-Path $run '2026-09-20-023000-primary.log') -Encoding UTF8
$null = New-Item -ItemType Directory -Force -Path (Join-Path $run '2026-09-20-023000')
'<TestRun><Results><UnitTestResult testName="UI.X" outcome="Passed" /></Results></TestRun>' | Set-Content -Path (Join-Path $run '2026-09-20-023000\ui-soak-1.trx') -Encoding UTF8
$bfOut = Join-Path $dir 'backfill.result.json'
$bfLog = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyBackfill.ps1') -RunDir $run -OutFile $bfOut 2>&1 | ForEach-Object { "$_" })
if (Test-Path $bfOut) {
  $bfj = Get-Content $bfOut -Raw | ConvertFrom-Json
  Assert (("$($bfj.provenance.'legs.gates'.source)" -eq 'gate cells in morning-2026-09-20-023000.md') -and ("$($bfj.provenance.soak.source)" -eq 'soak trx 2026-09-20-023000\ui-soak-1.trx') -and ("$($bfj.provenance.'timings.run-a'.source)" -like 'test-seconds in 2026-09-20-023000-default.log*' -or "$($bfj.provenance.'timings.run-a'.source)" -like 'test-seconds in 2026-09-20-023000-primary.log, (none matching *-full*.log)')) 'backfill-provenance-names-artifacts' ("gates: $($bfj.provenance.'legs.gates'.source) | soak: $($bfj.provenance.soak.source) | timings: $($bfj.provenance.timings.source)")
} else { Assert $false 'backfill-provenance-names-artifacts' ($bfLog -join ' | ') }
# R2-F2: a stored row revises when its result gains a field; the last
# row per identity wins and an unchanged result appends nothing.
$rv = Join-Path $dir 'revise.jsonl'
$plain = New-Night '2026-09-24' '2026-09-24-023000' 5000
$null = Sync-MetricsStore $rv @($plain)
$withProv = New-Night '2026-09-24' '2026-09-24-023000' 5000
$withProv | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'rows in r.md'; confidence = 'derived' } })
$cur = @(Sync-MetricsStore $rv @($withProv))
$null = Sync-MetricsStore $rv @($withProv)
Assert (($cur.Count -eq 1) -and ($null -ne $cur[0].provenance) -and (@(Get-Content $rv | Where-Object { $_.Trim() -ne '' }).Count -eq 2)) 'metrics-row-revises-last-wins' "rows=$($cur.Count) lines=$(@(Get-Content $rv | Where-Object { $_.Trim() -ne '' }).Count)"

# R3-F1: a zero baseline alerts without dividing.
$zero = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 0 }) + @(New-Night '2026-09-27' '2026-09-27-023000' 90)
$za = @(Get-TrendAlerts $zero)
Assert (@($za | Where-Object { $_ -eq '- ALERT runa-duration: 90s on 2026-09-27 vs baseline 0s (+90s over a zero baseline, median of 7 night(s))' }).Count -eq 1) 'alert-zero-baseline-no-divide' ($za -join ' | ')
# R3-F2: nights without a measurement still occupy the window.
$win16 = @(1..16 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) (500 + $_) })
$win16[14].legs.'run-a'.testSeconds = $null
$win16[15].legs.'run-a'.testSeconds = $null
$tw = @(Format-TrendTable $win16 $Q $today)
Assert (@($tw | Where-Object { $_ -like '- RunA test-seconds (canonical native nights, last 14): n=12,*max 514 `[native`]' }).Count -eq 1) 'percentile-window-counts-unmeasured-nights' (($tw | Where-Object { $_ -like '*RunA test-seconds*' }) -join '')

# Change-point: a sustained step (three nights at 800 after seven at 600)
# alerts as a shift even when the latest night alone stays under the
# single-night threshold; a steady series stays quiet.
$stepNights = @(11..17 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 }) + @(18..20 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 740 })
$sa = @(Get-TrendAlerts $stepNights)
Assert ((@($sa | Where-Object { $_ -eq '- ALERT runa-shift: last 3 nights median 740s vs the prior 7 nights median 600s (+23%, sustained)' }).Count -eq 1) -and (@($sa | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 0)) 'alert-change-point-sustained-shift' ($sa -join ' | ')
Assert (@(Get-TrendAlerts @(11..22 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 }) | Where-Object { $_ -like '*runa-shift*' }).Count -eq 0) 'alert-change-point-quiet-when-steady'

# ---- D00 T02 section 32 ----
# Item 1: the scheduled night survives DST and a timezone move, and the
# ack gate keys the same night.
$dst1 = [pscustomobject]@{ startUtc = '2026-10-24T00:30:00.0000000Z'; tz = '+02:00'; day = '2026-10-24' }
$dst2 = [pscustomobject]@{ startUtc = '2026-10-25T01:30:00.0000000Z'; tz = '+01:00'; day = '2026-10-25' }
$move = [pscustomobject]@{ startUtc = '2026-09-30T07:30:00.0000000Z'; tz = '-05:00'; day = '2026-09-30' }
Assert (((Get-ResultNight $dst1) -eq '2026-10-24') -and ((Get-ResultNight $dst2) -eq '2026-10-25') -and ((Get-ResultNight $move) -eq '2026-09-30')) 'night-survives-dst-and-timezone-move' "$(Get-ResultNight $dst1) $(Get-ResultNight $dst2) $(Get-ResultNight $move)"
$lateRun = Join-Path $dir 'late.result.json'
[pscustomobject]@{ version = 1; stamp = '2026-09-29-235000'; day = '2026-09-29'; night = '2026-09-30'; identity = '2026-09-29-235000-pid1'; verdict = 'red'; exit = 1; incidents = @() } | ConvertTo-Json | Set-Content -Path $lateRun -Encoding UTF8
Assert ((Get-AckDemands @($lateRun))['2026-09-29-235000-pid1'].Day -eq '2026-09-30') 'ack-gate-keys-the-same-night'
# Item 2: coverage beside the rate.
$halfQ = New-Night '2026-09-28' '2026-09-28-023000' 600 'timer' 50 0 50
$tq = @(Format-TrendTable @($halfQ) $Q $today)
Assert (@($tq | Where-Object { $_ -like '| 2026-09-28 |*| 54/0/50 (100% of 54 executed) |*| 54/104 (51.9%) |' }).Count -eq 1) 'coverage-reads-beside-the-rate' (($tq | Where-Object { $_ -like '| 2026-09-28*' }) -join '')
# Item 3: the matrix reads and each series cites its row.
Assert ((@($tq | Where-Object { $_ -like '- Series matrix (D00 T02 section 32): `[rate`]*`[native`]*`[recurrence`]*`[quarantine`]*' }).Count -eq 1) -and (@($tq | Where-Object { $_ -like '- Flake recurrence:*`[recurrence`]' }).Count -eq 1) -and (@($tq | Where-Object { $_ -like '- RunA test-seconds*`[native`]' }).Count -eq 1) -and (@($tq | Where-Object { $_ -like '- Quarantine now:*`[quarantine`]' }).Count -eq 1)) 'series-matrix-reads-and-series-cite-it'
# Items 4 and 15: a regression across an environment change reads
# cross-cohort, and the alert carries its runs and commit range.
$cb = @(20..26 | ForEach-Object { $n = New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600; $n | Add-Member -NotePropertyName commit -NotePropertyValue ('aaaaaaa{0:d2}' -f $_) -Force; $n })
$cl = New-Night '2026-09-27' '2026-09-27-023000' 900
$cl | Add-Member -NotePropertyName commit -NotePropertyValue 'bbbbbbb27' -Force
$cl.env = [pscustomobject]@{ os = '10.0.27000.0'; dpi = 'primary 96x96' }
$ca = @(Get-TrendAlerts (@($cb) + @($cl)))
$ctx = @($ca | Where-Object { $_ -like '  - runa-duration context:*' })
Assert (($ctx.Count -eq 1) -and ($ctx[0] -like '*runs 2026-09-20-023000-pid1,*2026-09-27-023000-pid1;*commits aaaaaaa..bbbbbbb;*CROSS-COHORT (os 10.0.26200.0 -> 10.0.27000.0)*evidence raw results for every run')) 'alert-attribution-and-cross-cohort' ($ca -join ' | ')
# Item 5: a short history reads insufficient data instead of alerting.
$three = @(20..22 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$three += New-Night '2026-09-23' '2026-09-23-023000' 5000
$ia = @(Get-TrendAlerts $three)
Assert (($ia.Count -eq 2) -and ($ia[0] -like '- Insufficient data: runa-duration (3 measured baseline night(s) of 5 needed, 4 of 7 window night(s) missing; evaluated night 2026-09-23 excluded from its own baseline)*') -and ($ia[1] -like '- Insufficient data: pass-rate (3 measured*') -and (@($ia | Where-Object { $_ -like '- ALERT *' }).Count -eq 0)) 'window-insufficient-data' ($ia -join ' | ')
# Items 7 and 8: a recorded pause reads paused; a degraded night marks.
$gapA = New-Night '2026-09-20' '2026-09-20-023000'
$gapB = New-Night '2026-09-24' '2026-09-24-023000'
$tp = @(Format-TrendTable @($gapA, $gapB) $Q $today @{ '2026-09-21' = 'operator travel' } @([pscustomobject]@{ Night = '2026-09-22'; Reason = 'morning-2026-09-22.result.json: result unreadable' }, [pscustomobject]@{ Night = '2026-09-24'; Reason = 'retained copy invalid' }))
Assert ((@($tp | Where-Object { $_ -like '| 2026-09-21 | paused | - | operator travel |*' }).Count -eq 1) -and (@($tp | Where-Object { $_ -like '| 2026-09-22 | degraded |*' }).Count -eq 1) -and (@($tp | Where-Object { $_ -like '| 2026-09-23 | missing |*' }).Count -eq 1) -and (@($tp | Where-Object { $_ -like '| 2026-09-24 (degraded) |*' }).Count -eq 1) -and (@($tp | Where-Object { $_ -like '- Degraded data: night 2026-09-22 (*' }).Count -eq 1)) 'pause-and-degraded-read-honestly' (($tp | Where-Object { $_ -like '| 2026-09-2*' }) -join ' / ')
# Item 10: a truncated last line and a concurrent writer both recover.
$st = Join-Path $dir 'durable.jsonl'
$null = Sync-MetricsStore $st @(New-Night '2026-09-20' '2026-09-20-023000')
[System.IO.File]::AppendAllText($st, '{"schema":"metrics/1","identity":"2026-09-21-0230', (New-Object System.Text.UTF8Encoding($false)))
$afterTrunc = @(Sync-MetricsStore $st @(New-Night '2026-09-22' '2026-09-22-023000'))
$readBack = Read-MetricsStore $st
Assert (($afterTrunc.Count -eq 2) -and (@($script:MetricsLastMalformed).Count -eq 1) -and ($readBack.Rows.Count -eq 2) -and (@($readBack.Malformed).Count -eq 1)) 'store-truncated-line-recovers' "rows $($readBack.Rows.Count) malformed $(@($readBack.Malformed) -join ',')"
$cmp = Compress-MetricsStore $st
$readCmp = Read-MetricsStore $st
Assert (($readCmp.Rows.Count -eq 2) -and (@($readCmp.Malformed).Count -eq 0) -and (Test-Path "$st.bak") -and ($cmp -like 'metrics: compacted 3 line(s) to 2*1 malformed dropped*')) 'store-compaction-drops-malformed-with-backup' $cmp
$cc = Join-Path $dir 'concurrent.jsonl'
$writer = {
  param($parse, $path, $prefix)
  . $parse
  foreach ($k in 1..15) { $null = Sync-MetricsStore $path @([pscustomobject]@{ version = 1; identity = "$prefix-$k"; stamp = "2026-09-20-0230$('{0:d2}' -f $k)"; day = '2026-09-20'; verdict = 'green'; legs = [pscustomobject]@{}; soak = [pscustomobject]@{ verdict = 'green' }; incidents = @(); env = [pscustomobject]@{ os = 'x'; dpi = 'y' } }) }
}
$j1 = Start-Job -ScriptBlock $writer -ArgumentList (Join-Path $PSScriptRoot 'NightlyParse.ps1'), $cc, 'a'
$j2 = Start-Job -ScriptBlock $writer -ArgumentList (Join-Path $PSScriptRoot 'NightlyParse.ps1'), $cc, 'b'
$null = Wait-Job $j1, $j2 -Timeout 300
Receive-Job $j1, $j2 -ErrorAction SilentlyContinue | Out-Null
Remove-Job $j1, $j2 -Force
$readCc = Read-MetricsStore $cc
Assert (($readCc.Rows.Count -eq 30) -and (@($readCc.Malformed).Count -eq 0)) 'store-concurrent-writers-interleave-cleanly' "rows $($readCc.Rows.Count) malformed $(@($readCc.Malformed).Count)"
# Item 11: a native row supersedes the backfill for its night, once.
$ss = Join-Path $dir 'supersede.jsonl'
$bfN = New-Night '2026-09-24' '2026-09-24-023000'
$bfN.identity = 'backfill-2026-09-24'
$bfN | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'rows'; confidence = 'derived' } }) -Force
$null = Sync-MetricsStore $ss @($bfN)
$nat = New-Night '2026-09-24' '2026-09-24-023500'
$cur = @(Sync-MetricsStore $ss @($nat))
$null = Sync-MetricsStore $ss @($nat)
$supLines = @([System.IO.File]::ReadAllLines($ss) | Where-Object { $_ -like '*supersession/1*' })
Assert (($cur.Count -eq 1) -and ("$($cur[0].identity)" -eq '2026-09-24-023500-pid1') -and ($supLines.Count -eq 1) -and ($supLines[0] -like '*"native":"2026-09-24-023500-pid1","backfill":"backfill-2026-09-24"*')) 'native-supersedes-backfill-once' (($cur | ForEach-Object { $_.identity }) -join ',')
# A manual retry later that night never supersedes the timer backfill.
$ss2 = Join-Path $dir 'supersede-manual.jsonl'
$bf2 = New-Night '2026-09-21' '2026-09-21-023003'
$bf2.identity = 'backfill-2026-09-21'
$bf2 | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'rows'; confidence = 'derived' } }) -Force
$null = Sync-MetricsStore $ss2 @($bf2)
$man = New-Night '2026-09-21' '2026-09-21-120835' 600 'manual'
$cur2 = @(Sync-MetricsStore $ss2 @($man))
Assert (($cur2.Count -eq 2) -and (@([System.IO.File]::ReadAllLines($ss2) | Where-Object { $_ -like '*supersession/1*' }).Count -eq 0)) 'manual-retry-never-supersedes-backfill' (($cur2 | ForEach-Object { $_.identity }) -join ',')
# A lifecycle block without its source (pre-section-30 R2) reads, but the
# nightly's own self-check refuses it.
$noSrc = Join-Path $dir 'nosrc.result.json'
[pscustomobject]@{ version = 1; stamp = 's'; day = 'd'; identity = 'i'; verdict = 'stood-down'; exit = 0; incidentLifecycle = @() } | ConvertTo-Json | Set-Content -Path $noSrc -Encoding UTF8
Assert (((Test-ResultFile $noSrc).Ok -eq $true) -and ((Test-ResultFile $noSrc -RequireLifecycle).Error -eq 'result incidentLifecycleSource missing')) 'lifecycle-without-source-reads-but-self-check-refuses'
# Item 12: every series and alert renders the same from metrics alone.
$eq = @(20..27 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) (580 + $_) })
$eqStore = Join-Path $dir 'equiv.jsonl'
$rowsEq = @(Sync-MetricsStore $eqStore $eq)
$rawRender = @(Format-TrendTable $eq $Q $today)
$metRender = @(Format-TrendTable @($rowsEq | ForEach-Object { ConvertFrom-MetricsRow $_ }) $Q $today | ForEach-Object { $_.Replace(' (metrics)', '') })
$diff = @(Compare-Object $rawRender $metRender | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
Assert ($diff.Count -eq 0) 'metrics-only-render-matches-raw' ($diff -join ' || ')
# Item 14: the disclosure contract on the trend and metrics channels.
$leak = New-Night '2026-09-25' '2026-09-25-023000'
$leak | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'C:\Users\someone\secret\run.log'; method = 'transcript-parse'; locator = ('token=' + 'ghp_' + ('A1b2C3d4E5' * 4)); confidence = 'derived' } }) -Force
$tl = @(Format-TrendTable @($leak) $Q $today)
$provLine = @($tl | Where-Object { $_ -like '- Backfill provenance*' })
$mrow = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $leak)) -Depth 6 -Compress
Assert (($provLine.Count -eq 1) -and ($provLine[0] -notlike '*Users\someone*') -and ($provLine[0] -notlike '*ghp_*') -and ($provLine[0] -like '*`[path`]*') -and ($mrow -notlike '*ghp_*') -and ($mrow -notlike '*Users\\someone*')) 'disclosure-trend-and-metrics-channels' ("$($provLine[0]) || $mrow")
Assert (((Protect-DisclosedText 'evidence \\host\share\user\dump.dmp; next') -eq 'evidence [path]; next') -and ((Protect-DisclosedText 'keep build/nightly/x.log') -eq 'keep build/nightly/x.log')) 'disclosure-unc-and-repo-paths'
# Item 13: a backfilled count quotes its locator and method.
if (Test-Path $bfOut) {
  $bfj2 = Get-Content $bfOut -Raw | ConvertFrom-Json
  Assert (("$($bfj2.provenance.'legs.run-a.counts'.method)" -eq 'report-row') -and ("$($bfj2.provenance.'legs.run-a.counts'.locator)" -like 'morning-2026-09-20-023000.md:*') -and ("$($bfj2.provenance.'legs.run-b.counts'.locator)" -like 'morning-2026-09-20-023000.md:*') -and ("$($bfj2.provenance.'timings.run-b'.locator)" -like '2026-09-20-023000-primary.log:*') -and ("$($bfj2.report)" -eq 'morning-2026-09-20-023000.md')) 'backfill-count-quotes-locator-and-method' "$($bfj2.provenance.'legs.run-a.counts'.method) $($bfj2.provenance.'legs.run-a.counts'.locator) $($bfj2.provenance.'timings.run-b'.locator)"
} else { Assert $false 'backfill-count-quotes-locator-and-method' 'no backfill output' }

# ---- section 32 round 1 ----
# R1-A1: the archival gate refuses a stale row and an unidentifiable result.
$gnd = Join-Path $dir 'gate-night'
$null = New-Item -ItemType Directory -Force -Path $gnd
$gres = New-Night '2026-07-02' '2026-07-02-023001'
($gres | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $gnd 'morning-2026-07-02-023001.result.json') -Encoding UTF8
$null = Sync-MetricsStore (Join-Path $gnd 'metrics.jsonl') @($gres)
$gOk = Test-StampArchived $gnd '2026-07-02-023001' (Read-MetricsStore (Join-Path $gnd 'metrics.jsonl'))
$gres.verdict = 'red'; $gres.exit = 1
($gres | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $gnd 'morning-2026-07-02-023001.result.json') -Encoding UTF8
$gStale = Test-StampArchived $gnd '2026-07-02-023001' (Read-MetricsStore (Join-Path $gnd 'metrics.jsonl'))
'{"version":1,"stamp":"2026-07-03-023001","verdict":"green","exit":0}' | Set-Content -Path (Join-Path $gnd 'morning-2026-07-03-023001.result.json') -Encoding UTF8
$gNoId = Test-StampArchived $gnd '2026-07-03-023001' (Read-MetricsStore (Join-Path $gnd 'metrics.jsonl'))
Assert ($gOk.Ok -and (-not $gStale.Ok) -and ($gStale.Reason -like '*changed since its metrics row was written') -and (-not $gNoId.Ok) -and ($gNoId.Reason -like '*has no identity*')) 'archival-gate-refuses-stale-and-unidentified' "$($gStale.Reason) / $($gNoId.Reason)"
# R1-A2: an incomplete row is malformed, never data.
$inc = Join-Path $dir 'incomplete.jsonl'
'{"schema":"metrics/1","identity":"x-1"}' | Set-Content -Path $inc -Encoding UTF8
$rinc = Read-MetricsStore $inc
Assert (($rinc.Rows.Count -eq 0) -and (@($rinc.Malformed).Count -eq 1)) 'metrics-incomplete-row-is-malformed'
# R1-A3: every persisted metrics string passes the disclosure contract.
$pl = New-Night '2026-09-26' '2026-09-26-023000'
$pl | Add-Member -NotePropertyName population -NotePropertyValue ('C:\Users\someone\p ' + 'ghp_' + ('A1b2C3d4E5' * 4)) -Force
$pl | Add-Member -NotePropertyName commit -NotePropertyValue 'C:\Users\someone\repo' -Force
$plj = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $pl)) -Depth 6 -Compress
Assert (($plj -notlike '*ghp_*') -and ($plj -notlike '*someone*')) 'metrics-population-and-commit-disclosed' $plj
# R1-C1: an every-other-day schedule skips undue nights, and nights after
# the last result through today read missing.
$sch = [pscustomobject]@{ First = '2026-09-20'; IntervalDays = 2 }
$tsch = @(Format-TrendTable @((New-Night '2026-09-20' '2026-09-20-023000'), (New-Night '2026-09-24' '2026-09-24-023000')) $Q (Get-Date '2026-09-28 08:00') @{} @() @() $sch)
$nightsSch = @($tsch | Where-Object { $_ -like '| 2026-09-*' } | ForEach-Object { $_.Substring(2, 10) })
Assert ((($nightsSch -join ',') -eq '2026-09-20,2026-09-22,2026-09-24,2026-09-26,2026-09-28') -and (@($tsch | Where-Object { $_ -like '| 2026-09-28 | missing |*' }).Count -eq 1)) 'schedule-aware-calendar' ($nightsSch -join ',')
# R1-C2: a harness change reads cross-cohort.
$hb = @(20..26 | ForEach-Object { $n = New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600; $n | Add-Member -NotePropertyName harness -NotePropertyValue 'aaaa1111-bbbb2222' -Force; $n })
$hl = New-Night '2026-09-27' '2026-09-27-023000' 900
$hl | Add-Member -NotePropertyName harness -NotePropertyValue 'cccc3333-bbbb2222' -Force
Assert (@(Get-TrendAlerts (@($hb) + @($hl)) | Where-Object { $_ -like '*CROSS-COHORT (harness aaaa1111-bbbb2222 -> cccc3333-bbbb2222)*' }).Count -eq 1) 'harness-change-reads-cross-cohort'
# R1-I2: series gate on their own samples: durations missing, rates present.
$nd7 = @(20..26 | ForEach-Object { $n = New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600; $n.legs.'run-a'.testSeconds = $null; $n })
$nl7 = New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 80 20 5
$gs = @(Get-TrendAlerts (@($nd7) + @($nl7)))
Assert ((@($gs | Where-Object { $_ -like '- Insufficient data: runa-duration (0 measured*' }).Count -eq 1) -and (@($gs | Where-Object { $_ -like '- ALERT pass-rate:*' }).Count -eq 1)) 'series-gate-on-their-own-samples' ($gs -join ' | ')
# R1-I3: missing nights consume window slots; old measurements do not
# stand in for them.
$old7 = @(1..7 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$late = New-Night '2026-09-27' '2026-09-27-023000' 5000
$gw = @(Get-TrendAlerts (@($old7) + @($late)))
Assert ((@($gw | Where-Object { $_ -like '- Insufficient data: runa-duration (0 measured baseline night(s) of 5 needed, 7 of 7 window night(s) missing*' }).Count -eq 1) -and (@($gw | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 0)) 'missing-nights-consume-window-slots' ($gw -join ' | ')
# Record 1: a timer run and a retry of one scheduled night keep one night
# across the DST change, in the trend, the ack gate, and notify.
$dA = New-Night '2026-10-25' '2026-10-25-023000'
$dA | Add-Member -NotePropertyName startUtc -NotePropertyValue '2026-10-25T01:30:00.0000000Z' -Force
$dA | Add-Member -NotePropertyName tz -NotePropertyValue '+01:00' -Force
$dA.PSObject.Properties.Remove('night')
$dB = New-Night '2026-10-25' '2026-10-25-031000' 600 'manual'
$dB | Add-Member -NotePropertyName startUtc -NotePropertyValue '2026-10-25T02:10:00.0000000Z' -Force
$dB | Add-Member -NotePropertyName tz -NotePropertyValue '+01:00' -Force
$dB.PSObject.Properties.Remove('night')
$canonD = Select-CanonicalRuns @($dA, $dB)
. (Join-Path $PSScriptRoot 'NightlyNotify.ps1')
$ns = Get-NoStartVerdict @($dA, $dB) (Get-Date '2026-10-25 08:00') '06:50' 1
Assert (($canonD.Keys.Count -eq 1) -and ($canonD.ContainsKey('2026-10-25')) -and ($canonD['2026-10-25'].Canonical -eq $dA.identity) -and (-not $ns.Missed -or (@($ns.Missed) -notcontains '2026-10-25'))) 'one-scheduled-night-across-dst-for-every-consumer' "$(@($canonD.Keys) -join ',') / $(@($ns.Missed) -join ',')"
# Record 2: the renderer's own loading path, before and after the raw
# results are deleted, renders the same series and alerts.
$eqDir = Join-Path $dir 'equiv-night'
$null = New-Item -ItemType Directory -Force -Path $eqDir
$eqRes = @(10..16 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$eqRes += New-Night '2026-09-17' '2026-09-17-023000' 900 'timer' 90 10 5
foreach ($er in $eqRes) { ($er | ConvertTo-Json -Depth 8) | Set-Content -Path (Join-Path $eqDir "morning-$($er.stamp).result.json") -Encoding UTF8 }
$trendScript = Join-Path $PSScriptRoot 'NightlyTrend.ps1'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $trendScript -NightDir $eqDir -OutFile (Join-Path $eqDir 'a.md') 2>&1
Get-ChildItem $eqDir -Filter 'morning-*.result.json' | Remove-Item
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $trendScript -NightDir $eqDir -OutFile (Join-Path $eqDir 'b.md') 2>&1
$norm = { param($f) @(Get-Content $f | Where-Object { $_ -notlike '- Metrics store:*' } | ForEach-Object { ($_ -replace ' \(metrics\)', '') -replace '; evidence .*$', '' }) }
$ea = & $norm (Join-Path $eqDir 'a.md')
$eb = & $norm (Join-Path $eqDir 'b.md')
$ediff = @(Compare-Object $ea $eb | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
Assert (($ediff.Count -eq 0) -and (@($ea | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 1) -and (@(Get-Content (Join-Path $eqDir 'b.md') | Where-Object { $_ -like '*(metrics)*' }).Count -ge 8)) 'render-matches-after-raw-deletion-with-alerts' ($ediff -join ' || ')

# ---- section 32 round 2 ----
# R2-A1: wrong-typed values are malformed, row by row.
$bad = Join-Path $dir 'badrows.jsonl'
@('{"schema":"metrics/1","identity":"a","stamp":"s","night":"2026-02-30","verdict":"green","legs":{}}', '{"schema":"metrics/1","identity":"b","stamp":"s","night":"2026-09-20","verdict":"maybe","legs":{}}', '{"schema":"metrics/1","identity":"c","stamp":"s","night":"2026-09-20","verdict":"green","legs":null}', '{"schema":"metrics/1","identity":"d","stamp":"s","night":"2026-09-20","verdict":"green","legs":{"run-a":{"passed":"lots"}}}', '{"schema":"metrics/1","identity":"e","stamp":"s","night":"2026-09-20","verdict":"green","legs":{"run-a":{"passed":3,"testSeconds":600}}}') | Set-Content -Path $bad -Encoding UTF8
$rb = Read-MetricsStore $bad
Assert (($rb.Rows.Count -eq 1) -and ($rb.Rows.Contains('e')) -and ((@($rb.Malformed) -join ',') -eq '1,2,3,4')) 'metrics-wrong-typed-rows-are-malformed' ((@($rb.Malformed) -join ',') + ' rows ' + (@($rb.Rows.Keys) -join ','))
# R2-C2: with no result at all, scheduled nights since enrollment list missing.
$tnone = @(Format-TrendTable @() $Q (Get-Date '2026-09-23 08:00') @{} @() @() ([pscustomobject]@{ First = '2026-09-20'; IntervalDays = 1 }))
Assert ((@($tnone | Where-Object { $_ -like '| 2026-09-2* | missing |*' } | ForEach-Object { $_.Substring(2, 10) }) -join ',') -eq '2026-09-20,2026-09-21,2026-09-22,2026-09-23') 'calendar-lists-missing-before-any-result' (($tnone | Where-Object { $_ -like '| 2026-*' }) -join ' / ')
# R2-I1: an incident weeks earlier is not a recurrence.
$recOld = @(1..3 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 'timer' 100 0 5 @('- INC-aaaa1111 `UI.A` x1 (Run A): boom') })
$recNow = New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 100 0 5 @('- INC-aaaa1111 `UI.A` x1 (Run A): boom')
Assert (@(Get-TrendAlerts (@($recOld) + @($recNow)) | Where-Object { $_ -like '- ALERT recurring-flake*' }).Count -eq 0) 'recurrence-needs-the-two-calendar-nights-before'
# R2-I2: incident evidence renders the same from metrics.
$ev = New-Night '2026-09-28' '2026-09-28-023000'
$ev | Add-Member -NotePropertyName incidentEvidence -NotePropertyValue ([pscustomobject]@{ 'INC-aaaa1111' = @('Bin/UI/Debug/launch-diagnostics/leak-1.json') }) -Force
$evRow = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $ev)) -Depth 6 -Compress) | ConvertFrom-Json)
$evA = @(Format-TrendTable @($ev) $Q $today | Where-Object { $_ -like '- Incident evidence*' })
$evB = @(Format-TrendTable @($evRow) $Q $today | Where-Object { $_ -like '- Incident evidence*' })
Assert (($evA.Count -eq 1) -and (($evA -join '') -eq ($evB -join ''))) 'incident-evidence-survives-metrics' (($evA + $evB) -join ' || ')
# Record: one scheduled night moves across both DST offsets and across
# zones, and every consumer keys it once.
$z1 = [pscustomobject]@{ version = 1; identity = 'z-1'; stamp = '2026-10-25-023000'; day = '2026-10-25'; launch = 'timer'; verdict = 'red'; exit = 1; startUtc = '2026-10-25T00:30:00.0000000Z'; tz = '+02:00'; incidents = @() }
$z2 = [pscustomobject]@{ version = 1; identity = 'z-2'; stamp = '2026-10-25-024000'; day = '2026-10-25'; launch = 'manual'; verdict = 'red'; exit = 1; startUtc = '2026-10-25T01:40:00.0000000Z'; tz = '+01:00'; incidents = @() }
$z3 = [pscustomobject]@{ version = 1; identity = 'z-3'; stamp = '2026-10-24-214000'; day = '2026-10-24'; launch = 'manual'; verdict = 'red'; exit = 1; startUtc = '2026-10-25T02:40:00.0000000Z'; tz = '-05:00'; incidents = @() }
$zc = Select-CanonicalRuns @($z1, $z2, $z3)
$zf = @($z1, $z2, $z3) | ForEach-Object { $zp = Join-Path $dir "$($_.identity).result.json"; ($_ | ConvertTo-Json) | Set-Content -Path $zp -Encoding UTF8; $zp }
$zd = Get-AckDemands $zf
Assert (($zc.Keys.Count -eq 1) -and ($zc.ContainsKey('2026-10-25')) -and ($zc['2026-10-25'].Canonical -eq 'z-1') -and ((@('z-1', 'z-2', 'z-3') | ForEach-Object { $zd[$_].Day } | Sort-Object -Unique) -eq '2026-10-25') -and (-not ((Get-NoStartVerdict @($z1, $z2, $z3) (Get-Date '2026-10-25 08:00') '06:50' 0).NoStart))) 'one-night-across-both-dst-offsets-and-zones' "$(@($zc.Keys) -join ',') / $((@('z-1', 'z-2', 'z-3') | ForEach-Object { $zd[$_].Day }) -join ',')"

# ---- section 32 sign-off ----
# R3-A2: a private path with spaces redacts whole.
Assert (((Protect-DisclosedText 'dump C:\Users\Jane Doe\Private Data\dump.dmp; next') -eq 'dump [path]; next') -and ((Protect-DisclosedText 'at \\host\share\Jane Doe\x.dmp') -eq 'at [path]')) 'disclosure-paths-with-spaces'
# R3-A3: a stood-down night never supersedes a timer backfill.
$ss3 = Join-Path $dir 'supersede-standdown.jsonl'
$bf3 = New-Night '2026-09-22' '2026-09-22-023003'
$bf3.identity = 'backfill-2026-09-22'
$bf3 | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ 'legs.counts' = [pscustomobject]@{ source = 'rows'; confidence = 'derived' } }) -Force
$null = Sync-MetricsStore $ss3 @($bf3)
$sd3 = New-Night '2026-09-22' '2026-09-22-023500' 600 'timer' 100 0 5 @() $false 'stood-down'
$cur3 = @(Sync-MetricsStore $ss3 @($sd3))
Assert (($cur3.Count -eq 2) -and (@([System.IO.File]::ReadAllLines($ss3) | Where-Object { $_ -like '*supersession/1*' }).Count -eq 0)) 'stood-down-never-supersedes'
# R3-C2: coverage counts the recorded population for a killed leg.
$kl = New-Night '2026-09-29' '2026-09-29-023000' 600 'timer' 54 0 0
$kl.legs.'run-a'.killed = $true
$kl | Add-Member -NotePropertyName population -NotePropertyValue 'run-a=100/100 run-b=4/4 interactive=39/44' -Force
Assert (@(Format-TrendTable @($kl) $Q $today | Where-Object { $_ -like '| 2026-09-29 |*| 58/104 (55.8%) |' }).Count -eq 1) 'coverage-counts-the-population-for-a-killed-leg' ((Format-TrendTable @($kl) $Q $today | Where-Object { $_ -like '| 2026-09-29*' }) -join '')
# R3-I1: enforcement, soak failures, and incident class survive metrics.
$en = New-Night '2026-09-30' '2026-09-30-023000' 600 'timer' 100 0 5 @('- INC-aaaa1111 `UI.A` x1 (ui-soak-1): Assert.NotNull() Failure')
$en.legs.interactive = [pscustomobject]@{ ran = $true; passed = 1; failed = 0; skipped = 0; killed = $false; cut = $false; enforcementRed = $true }
$en.soak = [pscustomobject]@{ ran = $true; verdict = 'red'; failed = @('UI.Soak.T'); killed = @(); cut = @() }
$enRow = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $en)) -Depth 8 -Compress) | ConvertFrom-Json)
$enA = @(Format-TrendTable @($en) $Q $today | Where-Object { $_ -like '| 2026-09-30*' })
$enB = @(Format-TrendTable @($enRow) $Q $today | Where-Object { $_ -like '| 2026-09-30*' } | ForEach-Object { $_.Replace(' (metrics)', '') })
Assert ((($enA -join '') -eq ($enB -join '')) -and (($enA -join '') -like '*| enforcement |*') -and (($enA -join '') -like '*red UI.Soak.T*') -and ("$(@($enRow.incidents)[0])" -like '*(ui-soak-1): Assert.NotNull() Failure')) 'metrics-keep-enforcement-soak-and-incident-class' (($enA + $enB) -join ' || ')
# R3-I2: August history cannot make a September shift.
$aug = @(1..7 | ForEach-Object { New-Night ('2026-08-{0:d2}' -f $_) ('2026-08-{0:d2}-023000' -f $_) 600 })
$sep = @(25..27 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 800 })
Assert (@(Get-TrendAlerts (@($aug) + @($sep)) | Where-Object { $_ -like '- ALERT runa-shift*' }).Count -eq 0) 'shift-needs-its-own-calendar-windows'
# R3-I3: a corrupt retained copy marks its night through the path's date.
$rtd = Join-Path $dir 'retained-night'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $rtd 'retained\2026-09-21-023001-run')
'{ truncated' | Set-Content -Path (Join-Path $rtd 'retained\2026-09-21-023001-run\result.json') -Encoding UTF8
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'NightlyTrend.ps1') -NightDir $rtd -OutFile (Join-Path $rtd 'trend.md') 2>&1
Assert (@(Get-Content (Join-Path $rtd 'trend.md') | Where-Object { $_ -like '- Degraded data: night 2026-09-21 (*' }).Count -eq 1) 'corrupt-retained-copy-marks-its-night' ((Get-Content (Join-Path $rtd 'trend.md') | Where-Object { $_ -like '*Degraded*' }) -join '')

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyTrend.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyTrend.Tests: all green'
exit 0
