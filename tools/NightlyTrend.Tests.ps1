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
  return [pscustomobject]@{ version = 1; day = $Night; night = $Night; stamp = $Stamp; identity = "$Stamp-pid1"; verdict = $Verdict; exit = $(if ($Verdict -eq 'green') { 0 } else { 1 }); simulated = $Sim; launch = $Launch; trigger = 't'; buildError = ''; omissionOk = $true; recovered = 'none'; legs = [pscustomobject]@{ 'run-a' = $a; 'run-b' = $b; interactive = $i }; soak = [pscustomobject]@{ verdict = 'green'; failed = 0; killed = @(); cut = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @() }; scheduler = [pscustomobject]@{ voted = $false; faults = @() }; incidents = @($Incidents); reserve = 900; consumed = 600; timings = @{ build = 1 }; env = [pscustomobject]@{ os = '10.0.26200.0'; dpi = 'primary 96x96'; dotnet = '10.0.400' }; harness = 'aaaa1111-bbbb2222'; populationHash = 'pop00001'; hostKey = 'h0st0001' }
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
$ca = @(Get-TrendAlerts (@($cb) + @($cl)))
$ctx = @($ca | Where-Object { $_ -like '  - runa-duration context:*' })
Assert (($ctx.Count -eq 1) -and ($ctx[0] -like '*runs 2026-09-20-023000-pid1,*2026-09-27-023000-pid1;*commits aaaaaaa..bbbbbbb;*same cohort*evidence raw results for every run*')) 'alert-attribution-same-cohort' ($ca -join ' | ')
# Section 40 item 4: across an environment change the window rebaselines:
# the new cohort alerts against nothing and names the change instead.
$cl.env = [pscustomobject]@{ os = '10.0.27000.0'; dpi = 'primary 96x96'; dotnet = '10.0.400' }
$cx = @(Get-TrendAlerts (@($cb) + @($cl)))
Assert ((@($cx | Where-Object { $_ -like '- Rebaseline: cohort changed on 2026-09-27 (os 10.0.26200.0 -> 10.0.27000.0); 7 earlier night(s) leave the baseline' }).Count -eq 1) -and (@($cx | Where-Object { $_ -like '- ALERT *' }).Count -eq 0)) 's40-cross-cohort-rebaselines' ($cx -join ' | ')
# Section 40 item 5: an unknown dimension never establishes equivalence.
$cu = $cl.PSObject.Copy(); $cu.env = [pscustomobject]@{ os = '10.0.26200.0'; dpi = 'primary 96x96'; dotnet = '10.0.400' }; $cu.populationHash = ''
$cux = @(Get-TrendAlerts (@($cb) + @($cu)))
Assert ((@($cux | Where-Object { $_ -like '- Rebaseline:*population pop00001 -> unknown*' }).Count -eq 1) -and (@($cux | Where-Object { $_ -like '- ALERT *' }).Count -eq 0)) 's40-unknown-population-is-not-equivalent' ($cux -join ' | ')
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
Assert (($cur.Count -eq 1) -and ("$($cur[0].identity)" -eq '2026-09-24-023500-pid1') -and ($supLines.Count -eq 1) -and ($supLines[0] -like '*"native":"2026-09-24-023500-pid1@h0st0001","backfill":"backfill-2026-09-24@h0st0001"*')) 'native-supersedes-backfill-once' (($cur | ForEach-Object { $_.identity }) -join ',')
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
Assert (@(Get-TrendAlerts (@($hb) + @($hl)) | Where-Object { $_ -like '- Rebaseline:*(harness aaaa1111-bbbb2222 -> cccc3333-bbbb2222)*' }).Count -eq 1) 'harness-change-rebaselines'
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
Assert (($canonD.Keys.Count -eq 1) -and ($canonD.ContainsKey('2026-10-25|h0st0001')) -and ($canonD['2026-10-25|h0st0001'].Canonical -eq $dA.identity) -and (-not $ns.Missed -or (@($ns.Missed) -notcontains '2026-10-25'))) 'one-scheduled-night-across-dst-for-every-consumer' "$(@($canonD.Keys) -join ',') / $(@($ns.Missed) -join ',')"
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
$norm = { param($f) @(Get-Content $f | Where-Object { ($_ -notlike '- Metrics store:*') -and ($_ -notlike '- Pruned night*') -and ($_ -notlike '- Alert lifecycle:*') } | ForEach-Object { ($_ -replace ' \(metrics\)', '') -replace '; evidence .*$', '' }) }
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
Assert (($zc.Keys.Count -eq 1) -and ($zc.ContainsKey('2026-10-25|legacy')) -and ($zc['2026-10-25|legacy'].Canonical -eq 'z-1') -and ((@('z-1', 'z-2', 'z-3') | ForEach-Object { $zd[$_].Day } | Sort-Object -Unique) -eq '2026-10-25') -and (-not ((Get-NoStartVerdict @($z1, $z2, $z3) (Get-Date '2026-10-25 08:00') '06:50' 0).NoStart))) 'one-night-across-both-dst-offsets-and-zones' "$(@($zc.Keys) -join ',') / $((@('z-1', 'z-2', 'z-3') | ForEach-Object { $zd[$_].Day }) -join ',')"

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

# ---- section 32 round 4 ----
$big = Join-Path $dir 'bigcount.jsonl'
'{"schema":"metrics/1","identity":"g","stamp":"s","night":"2026-09-20","verdict":"green","legs":{"run-a":{"failed":"99999999999999999999999999"}}}' | Set-Content -Path $big -Encoding UTF8
Assert ((Read-MetricsStore $big).Rows.Count -eq 0) 'metrics-overflowing-count-is-malformed'
$gp = New-Night '2026-09-20' '2026-09-20-023000'
$gp.legs.'run-a'.gate = 'C:\Users\someone\Private\gate.log'
$gpj = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $gp)) -Depth 6 -Compress
$gpRaw = @(Format-TrendTable @($gp) $Q $today | Where-Object { $_ -like '| 2026-09-20*' })
Assert (($gpj -notlike '*someone*') -and (($gpRaw -join '') -notlike '*someone*')) 'gate-text-passes-the-disclosure-contract' "$gpj || $($gpRaw -join '')"
$om = New-Night '2026-09-21' '2026-09-21-023000'
$om.PSObject.Properties.Remove('omissionOk')
$omRow = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $om)) -Depth 8 -Compress) | ConvertFrom-Json)
Assert ((Classify-NightlyOutcome $om).Class -eq (Classify-NightlyOutcome $omRow).Class) 'missing-omission-field-classifies-the-same-from-metrics' "$((Classify-NightlyOutcome $om).Class) vs $((Classify-NightlyOutcome $omRow).Class)"

# ---- section 32 round 5 ----
$flagRows = Join-Path $dir 'flags.jsonl'
'{"schema":"metrics/1","identity":"f","stamp":"s","night":"2026-09-20","verdict":"green","legs":{"run-a":{"ran":[],"passed":100,"failed":5}}}' | Set-Content -Path $flagRows -Encoding UTF8
Assert ((Read-MetricsStore $flagRows).Rows.Count -eq 0) 'metrics-non-boolean-flags-are-malformed'
$sp = New-Night '2026-09-22' '2026-09-22-023000'
$sp.soak = [pscustomobject]@{ ran = $true; verdict = 'red'; failed = @('C:\Users\someone\Private\soak.log'); killed = @(); cut = @() }
$sp.timings = @{ 'C:\Users\someone\Private\phase' = 3 }
$spOut = (Format-TrendTable @($sp) $Q $today) -join "`n"
Assert ($spOut -notlike '*someone*') 'raw-soak-and-timing-text-disclosed'
$late = [datetime]::ParseExact('2026-09-25 13:00', 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$early = [datetime]::ParseExact('2026-09-26 01:10', 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
Assert (((Get-ScheduledNight $late @('02:30')) -eq '2026-09-25') -and ((Get-ScheduledNight $early @('02:30')) -eq '2026-09-25') -and ((Get-NightKey $late) -eq '2026-09-26')) 'late-timer-run-keeps-its-trigger-night' "$(Get-ScheduledNight $late @('02:30')) $(Get-ScheduledNight $early @('02:30'))"

# ---- D00 T02 section 40: trend and telemetry second residuals ----
$s40 = Join-Path $dir 's40'
$null = New-Item -ItemType Directory -Force -Path $s40
# Item 1: two hosts' runs on one night read as two keys, and one host's
# nights never join another's baseline.
$hA = New-Night '2026-10-01' '2026-10-01-023000'
$hB = New-Night '2026-10-01' '2026-10-01-023001'; $hB.identity = '2026-10-01-023001-pid2'; $hB.hostKey = 'h0st0002'
$hc = Select-CanonicalRuns @($hA, $hB)
Assert (($hc.Keys.Count -eq 2) -and $hc.ContainsKey('2026-10-01|h0st0001') -and $hc.ContainsKey('2026-10-01|h0st0002') -and ($hc['2026-10-01|h0st0002'].Canonical -eq $hB.identity)) 's40-two-hosts-key-apart' (@($hc.Keys) -join ',')
$hBase = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$hOther = New-Night '2026-09-27' '2026-09-27-023000' 900; $hOther.hostKey = 'h0st0002'
$hx = @(Get-TrendAlerts (@($hBase) + @($hOther)))
Assert (@($hx | Where-Object { ($_ -like '- ALERT *') -or ($_ -like '- Rebaseline:*') }).Count -eq 0) 's40-other-host-never-joins-the-baseline' ($hx -join ' | ')
# Item 2: a 02:30 trigger repeated by a DST fall-back reads one night.
$rp1 = New-Night '2026-10-25' '2026-10-25-023000'
$rp1 | Add-Member -NotePropertyName startUtc -NotePropertyValue '2026-10-25T00:30:00.0000000Z' -Force
$rp2 = New-Night '2026-10-25' '2026-10-25-023000'; $rp2.identity = '2026-10-25-023000-pid2'
$rp2 | Add-Member -NotePropertyName startUtc -NotePropertyValue '2026-10-25T01:30:00.0000000Z' -Force
$rpc = Select-CanonicalRuns @($rp1, $rp2)
$rpSlot = $rpc['2026-10-25|h0st0001']
Assert (($rpc.Keys.Count -eq 1) -and ($rpSlot.Canonical -ne '') -and (@($rpSlot.Others.Values | Where-Object { "$_" -like 'repeated timer trigger*' }).Count -eq 1)) 's40-repeated-trigger-reads-one-night' "$(@($rpc.Keys) -join ',') / $(@($rpSlot.Others.Values) -join ';')"
# Item 3: a trigger moved mid-history keeps the earlier nights' due state,
# and a night still inside its run window reads pending, never missing.
$shPath = Join-Path $s40 'schedule-history.md'
@('| From | Trigger | Interval days |', '| --- | --- | --- |', '| 2026-09-01 | 02:30 | 1 |', '| 2026-09-10 | 04:00 | 2 |') | Set-Content -Path $shPath -Encoding UTF8
$sh = Read-ScheduleHistory $shPath
Assert (($sh.First -eq '2026-09-01') -and (Test-NightScheduled $sh '2026-09-05') -and (Test-NightScheduled $sh '2026-09-09') -and (-not (Test-NightScheduled $sh '2026-09-11')) -and (Test-NightScheduled $sh '2026-09-12') -and (-not (Test-NightScheduled $sh '2026-08-31'))) 's40-schedule-edit-keeps-history'
$gr = @(20..29 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$grSched = [pscustomobject]@{ First = '2026-09-20'; Trigger = '02:30'; IntervalDays = 1 }
$tRun = @(Format-TrendTable $gr $Q (Get-Date '2026-09-30 04:00') @{} @() @() $grSched)
$tLate = @(Format-TrendTable $gr $Q (Get-Date '2026-09-30 07:30') @{} @() @() $grSched)
Assert ((@($tRun | Where-Object { $_ -like '| 2026-09-30 | pending |*' }).Count -eq 1) -and (@($tRun | Where-Object { $_ -like '| 2026-09-30 | missing |*' }).Count -eq 0) -and (@($tLate | Where-Object { $_ -like '| 2026-09-30 | missing |*' }).Count -eq 1)) 's40-running-night-reads-pending' (($tRun + $tLate | Where-Object { $_ -like '| 2026-09-30*' }) -join ' || ')
# R2-F2: a trigger near midnight keeps the previous night pending past
# midnight, and it reads missing only after its own deadline.
$mnRows = @(20..28 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-230000' -f $_) 600 })
$mnSched = [pscustomobject]@{ First = '2026-09-20'; Trigger = '23:00'; IntervalDays = 1 }
$mnEarly = @(Format-TrendTable $mnRows $Q (Get-Date '2026-09-30 01:00') @{} @() @() $mnSched)
$mnLate = @(Format-TrendTable $mnRows $Q (Get-Date '2026-09-30 03:31') @{} @() @() $mnSched)
Assert ((@($mnEarly | Where-Object { $_ -like '| 2026-09-29 | pending |*' }).Count -eq 1) -and (@($mnEarly | Where-Object { $_ -like '| 2026-09-29 | missing |*' }).Count -eq 0) -and (@($mnLate | Where-Object { $_ -like '| 2026-09-29 | missing |*' }).Count -eq 1)) 's40-late-trigger-grace-crosses-midnight' (($mnEarly + $mnLate | Where-Object { $_ -like '| 2026-09-29*' }) -join ' || ')
# Item 6: each detector's boundary reads its side.
$bBase = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$at125 = @(Get-TrendAlerts (@($bBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 750)))
$past125 = @(Get-TrendAlerts (@($bBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 751)))
Assert ((@($at125 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 0) -and (@($past125 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 1)) 's40-boundary-exactly-125-percent' (($at125 + $past125) -join ' | ')
$lowBase = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 100 })
$at59 = @(Get-TrendAlerts (@($lowBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 159)))
$at60 = @(Get-TrendAlerts (@($lowBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 160)))
Assert ((@($at59 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 0) -and (@($at60 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 1)) 's40-boundary-sixty-second-floor' (($at59 + $at60) -join ' | ')
$five = @(22..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$four = @(23..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$s5 = @(Get-TrendAlerts (@($five) + @(New-Night '2026-09-27' '2026-09-27-023000' 900)))
$s4 = @(Get-TrendAlerts (@($four) + @(New-Night '2026-09-27' '2026-09-27-023000' 900)))
Assert ((@($s5 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 1) -and (@($s4 | Where-Object { $_ -like '- Insufficient data: runa-duration (4 measured*' }).Count -eq 1) -and (@($s4 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 0)) 's40-boundary-exactly-five-samples' (($s5 + $s4) -join ' | ')
$pr2 = @(Get-TrendAlerts (@($bBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 94 2 5)))
$pr3 = @(Get-TrendAlerts (@($bBase) + @(New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 94 3 5)))
Assert ((@($pr2 | Where-Object { $_ -like '- ALERT pass-rate*' }).Count -eq 0) -and (@($pr3 | Where-Object { $_ -like '- ALERT pass-rate*' }).Count -eq 1)) 's40-boundary-exactly-two-points' (($pr2 + $pr3) -join ' | ')
$shiftPrior = @(17..23 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$shAt = @(Get-TrendAlerts (@($shiftPrior) + @(24..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 720 })))
$shPast = @(Get-TrendAlerts (@($shiftPrior) + @(24..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 721 })))
Assert ((@($shAt | Where-Object { $_ -like '- ALERT runa-shift*' }).Count -eq 0) -and (@($shPast | Where-Object { $_ -like '- ALERT runa-shift*' }).Count -eq 1)) 's40-boundary-exactly-120-percent-shift' (($shAt + $shPast) -join ' | ')
# Item 7: a duplicate execution cannot raise coverage; unknown discovery
# reads unknown.
$cvDup = New-Night '2026-09-28' '2026-09-28-023000' 600 'timer' 120 0 0
$cvDup | Add-Member -NotePropertyName population -NotePropertyValue 'run-a=90/100 run-b=4/4 interactive=0/0' -Force
$cvUnk = New-Night '2026-09-29' '2026-09-29-023000'
$cvUnk | Add-Member -NotePropertyName populationState -NotePropertyValue 'unknown' -Force
$cvId = New-Night '2026-09-27' '2026-09-27-023000' 600 'timer' 120 0 0
$cvId | Add-Member -NotePropertyName population -NotePropertyValue 'run-a=90/100 run-b=4/4 interactive=0/0' -Force
$cvId | Add-Member -NotePropertyName executedUnique -NotePropertyValue 95 -Force
$tcv = @(Format-TrendTable @($cvId, $cvDup, $cvUnk) $Q $today)
Assert ((@($tcv | Where-Object { $_ -like '| 2026-09-27 |*| 95/104 (91.3%); 29 duplicate execution(s) not counted |' }).Count -eq 1) -and (@($tcv | Where-Object { $_ -like '| 2026-09-28 |*| 104/104 (100%); 20 duplicate execution(s) not counted; identities not recorded (count capped) |' }).Count -eq 1) -and (@($tcv | Where-Object { $_ -like '| 2026-09-29 |*| unknown (discovery failed) |' }).Count -eq 1)) 's40-coverage-counts-unique-tests'
# R1-F5: the unknown state and the identity count survive the metrics row.
$cvBack = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $cvUnk)) -Depth 6 -Compress) | ConvertFrom-Json)
$cvIdBack = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $cvId)) -Depth 6 -Compress) | ConvertFrom-Json)
$tcvB = @(Format-TrendTable @($cvIdBack, $cvBack) $Q $today)
Assert ((@($tcvB | Where-Object { $_ -like '| 2026-09-29*| unknown (discovery failed) |' }).Count -eq 1) -and (@($tcvB | Where-Object { $_ -like '| 2026-09-27*| 95/104 (91.3%)*' }).Count -eq 1)) 's40-coverage-state-survives-metrics' (($tcvB | Where-Object { $_ -like '| 2026-09-2*' }) -join ' || ') (($tcv | Where-Object { $_ -like '| 2026-09-2*' }) -join ' || ')
# Item 8: an excluded result leaves every series and never degrades.
$exPath = Join-Path $s40 'exclusions.md'
@('| Run identity | Reason |', '| --- | --- |', '| 2026-09-27-023000-pid1 | host rebuilt mid-run |') | Set-Content -Path $exPath -Encoding UTF8
$exRows = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 }) + @(New-Night '2026-09-27' '2026-09-27-023000' 900)
$exN = Set-ResultExclusions $exRows (Read-NightlyExclusions $exPath)
$tex = @(Format-TrendTable $exRows $Q $today)
Assert (($exN -eq 1) -and (@($tex | Where-Object { $_ -like '| 2026-09-27 (excluded) |*excluded: host rebuilt mid-run*' }).Count -eq 1) -and (@($tex | Where-Object { $_ -like '*(degraded)*' }).Count -eq 0) -and (@($tex | Where-Object { $_ -like '- ALERT *' }).Count -eq 0) -and (@($tex | Where-Object { $_ -like '- Excluded: 2026-09-27-023000-pid1 night 2026-09-27 (host rebuilt mid-run): out of *not degraded*' }).Count -eq 1) -and (@($tex | Where-Object { $_ -like '- 2026-09-27 2026-09-27-023000:*' }).Count -eq 0)) 's40-exclusion-never-degrades' (($tex | Where-Object { $_ -like '*2026-09-27*' }) -join ' || ')
# Item 9: archival check and delete share the lock; a result changed in
# between keeps its stamp.
$arDir = Join-Path $s40 'archive'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $arDir '2026-09-20-023000')
$arRes = New-Night '2026-09-20' '2026-09-20-023000'
$arFile = Join-Path $arDir '2026-09-20-023000\result.json'
($arRes | ConvertTo-Json -Depth 8) | Set-Content -Path $arFile -Encoding UTF8
$arStore = Join-Path $arDir 'metrics.jsonl'
$null = Sync-MetricsStore $arStore @(Read-ResultFile $arFile)
$arKeep = Remove-ArchivedStamp $arDir '2026-09-20-023000' $arStore { $o = Get-Content $arFile -Raw | ConvertFrom-Json; $o.verdict = 'red'; $o.exit = 1; ($o | ConvertTo-Json -Depth 8) | Set-Content -Path $arFile -Encoding UTF8 }
$arKept = Test-Path (Join-Path $arDir '2026-09-20-023000')
$null = Sync-MetricsStore $arStore @(Read-ResultFile $arFile)
$arGo = Remove-ArchivedStamp $arDir '2026-09-20-023000' $arStore
Assert ((-not $arKeep.Deleted) -and ($arKeep.Reason -like '*changed since its metrics row*') -and $arKept -and $arGo.Deleted -and (-not (Test-Path (Join-Path $arDir '2026-09-20-023000')))) 's40-archive-and-prune-share-the-lock' "$($arKeep.Reason) / $($arGo.Reason)"
# Item 10 and item 17: disk full, a stale lock, an interrupted
# compaction, a restore, and capacity all end with a readable store.
$fsDir = Join-Path $s40 'store'
$null = New-Item -ItemType Directory -Force -Path $fsDir
$fs = Join-Path $fsDir 'metrics.jsonl'
$null = Sync-MetricsStore $fs @(New-Night '2026-09-20' '2026-09-20-023000')
$fsBefore = [System.IO.File]::ReadAllText($fs)
$null = Sync-MetricsStore $fs @(New-Night '2026-09-21' '2026-09-21-023000') { param($p, $t) throw 'There is not enough space on the disk.' }
$fsErr = "$script:MetricsWriteError"
$fsBack = Read-MetricsStore $fs
Assert (($fsErr -like 'metrics append failed: There is not enough space*') -and ([System.IO.File]::ReadAllText($fs) -eq $fsBefore) -and ($fsBack.Rows.Count -eq 1) -and ($fsBack.Malformed.Count -eq 0)) 's40-disk-full-keeps-the-store' $fsErr
$null = Sync-MetricsStore $fs @(New-Night '2026-09-21' '2026-09-21-023000') { param($p, $t) [System.IO.File]::AppendAllText($p, $t.Substring(0, 40)); throw 'There is not enough space on the disk.' }
$fsPart = Read-MetricsStore $fs
Assert (([System.IO.File]::ReadAllText($fs) -eq $fsBefore) -and ($fsPart.Malformed.Count -eq 0) -and ($fsPart.Rows.Count -eq 1)) 's40-partial-write-is-cut-back' "$script:MetricsWriteError"
$null = Sync-MetricsStore $fs @(New-Night '2026-09-21' '2026-09-21-023000') $null 10
$capErr = "$script:MetricsWriteError"
Assert (($capErr -like 'metrics store over capacity*history is never deleted*') -and ((Read-MetricsStore $fs).Rows.Count -eq 1)) 's40-capacity-refuses-by-policy' $capErr
# R3-F1: capacity counts the UTF-8 bytes written, not characters.
$u8 = New-Night '2026-09-22' '2026-09-22-023000' 600 'timer' 99 1 5 @('- INC-aaaa1111 `UI.A` x1 (Run A): ' + ([string][char]0x00E9 * 200))
$u8Json = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $u8)) -Depth 6 -Compress
$u8Size = (Get-Item $fs).Length
$u8Cap = $u8Size + $u8Json.Length + 50
$null = Sync-MetricsStore $fs @($u8) $null $u8Cap
Assert (("$script:MetricsWriteError" -like 'metrics store over capacity*') -and ((Get-Item $fs).Length -eq $u8Size)) 's40-capacity-counts-utf8-bytes' "$script:MetricsWriteError"

$lockJob = Start-Job -ScriptBlock { $m = New-Object System.Threading.Mutex($false, 'Local\ScratchPad.NightlyMetrics'); $null = $m.WaitOne(); 'held' }
$null = Wait-Job $lockJob -Timeout 60; $null = Receive-Job $lockJob; Remove-Job $lockJob -Force
$staleRows = @(Sync-MetricsStore $fs @(New-Night '2026-09-21' '2026-09-21-023000'))
Assert ($staleRows.Count -eq 2) 's40-stale-lock-is-taken-over' "$($staleRows.Count)"
$fsPre = [System.IO.File]::ReadAllText($fs)
$faultOk = $true
foreach ($fp in @('after-backup', 'after-temp')) {
  try { $null = Compress-MetricsStore $fs { param($pt) if ($pt -eq $fp) { throw "killed at $pt" } }; $faultOk = $false } catch { if ("$($_.Exception.Message)" -notlike "*killed at $fp*") { $faultOk = $false } }
  $fsMid = Read-MetricsStore $fs
  if (([System.IO.File]::ReadAllText($fs) -ne $fsPre) -or ($fsMid.Malformed.Count -gt 0) -or ($fsMid.Rows.Count -ne 2)) { $faultOk = $false }
}
$fsResume = Compress-MetricsStore $fs
Assert ($faultOk -and ($fsResume -like 'metrics: compacted*') -and (-not (Test-Path "$fs.tmp")) -and ((Read-MetricsStore $fs).Rows.Count -eq 2)) 's40-interrupted-compaction-keeps-the-store' "$fsResume"
[System.IO.File]::AppendAllText($fs, '{"schema":"metrics/1","identity":"half')
'{"partial":' | Set-Content -Path "$fs.tmp" -Encoding UTF8
$fsTorn = Read-MetricsStore $fs
$fsRestore = Restore-MetricsStore $fs
$fsFixed = Read-MetricsStore $fs
# R4-F1: a backup carrying a rejected-line marker still restores.
$rjStore = Join-Path $fsDir 'rejected.jsonl'
Copy-Item $fs $rjStore -Force
[System.IO.File]::AppendAllText($rjStore, "{broken`n")
$null = Compress-MetricsStore $rjStore
[System.IO.File]::AppendAllText($rjStore, '{"schema":"metrics/1","identity":"torn')
$rjOut = Restore-MetricsStore $rjStore
$rjBack = Read-MetricsStore $rjStore
Assert (($rjOut -like 'metrics: restored *row(s)*1 line(s) the compaction had already rejected stay dropped*') -and ($rjBack.Malformed.Count -eq 0) -and ($rjBack.Rows.Count -ge 1)) 's40-backup-with-rejected-marker-restores' $rjOut
# R4-F2: a lower revision never replaces the stored row.
$rvStore = Join-Path $fsDir 'revision.jsonl'
$rv2 = New-Night '2026-09-23' '2026-09-23-023000' 700; $rv2 | Add-Member -NotePropertyName revision -NotePropertyValue 2 -Force
$rv1 = New-Night '2026-09-23' '2026-09-23-023000' 600; $rv1 | Add-Member -NotePropertyName revision -NotePropertyValue 1 -Force
$null = Sync-MetricsStore $rvStore @($rv2)
$rvRows = @(Sync-MetricsStore $rvStore @($rv1))
$rvAuth = Select-AuthoritativeResults @($rv1) $rvRows @($script:MetricsStaleSkipped)
Assert ((@($rvAuth.Results).Count -eq 0) -and (@($rvAuth.FromMetrics).Count -eq 1) -and ("$($rvAuth.FromMetrics[0].revision)" -eq '2') -and ([int]$rvAuth.FromMetrics[0].legs.'run-a'.testSeconds -eq 700)) 's40-stale-live-result-renders-the-stored-revision' "$(@($rvAuth.Results).Count) $(@($rvAuth.FromMetrics).Count)"
Assert ((@($rvRows).Count -eq 1) -and ("$($rvRows[0].revision)" -eq '2') -and ([int]$rvRows[0].legs.'run-a'.testSeconds -eq 700) -and (@($script:MetricsStaleSkipped).Count -eq 1)) 's40-lower-revision-never-replaces' "$($rvRows[0].revision)"
Assert (($fsTorn.Malformed.Count -eq 1) -and ($fsRestore -like 'metrics: restored 2 row(s)*') -and ($fsFixed.Rows.Count -eq 2) -and ($fsFixed.Malformed.Count -eq 0)) 's40-torn-store-restores-from-backup' "$fsRestore"
# Item 11: a partial native row keeps the backfill's fields it lacks.
$mgStore = Join-Path $s40 'merge.jsonl'
$mgBf = New-Night '2026-09-22' '2026-09-22-023000'; $mgBf.identity = 'bf-2026-09-22'
$mgBf | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ reserve = [pscustomobject]@{ confidence = 'high'; source = 'log' } }) -Force
$mgBf.populationHash = 'popBF001'
$mgNat = New-Night '2026-09-22' '2026-09-22-023000'; $mgNat.populationHash = ''; $mgNat.harness = ''
$null = Sync-MetricsStore $mgStore @($mgBf)
$mgRows = @(Sync-MetricsStore $mgStore @($mgNat))
$mgRow = @($mgRows | Where-Object { "$($_.identity)" -eq $mgNat.identity }) | Select-Object -First 1
# R4-F3: the live native result takes the merged fields too.
$mgLive = New-Night '2026-09-22' '2026-09-22-023000'; $mgLive.populationHash = ''; $mgLive.harness = ''
$mgN = Add-MergedEvidence @($mgLive) $mgRows
# Section 47 item 6 narrows the merge: a native row with its own counts
# keeps its own population (never the backfill's), while unit-free fields
# such as the harness still fill.
Assert (($mgN -eq 1) -and ("$($mgLive.populationHash)" -eq '') -and ("$($mgLive.harness)" -eq 'aaaa1111-bbbb2222') -and ("$($mgLive.mergedFrom)" -like 'bf-2026-09-22*')) 's40-live-render-takes-merged-evidence' "$mgN $($mgLive.populationHash)"
Assert ((@($mgRows).Count -eq 1) -and ("$($mgRow.populationHash)" -ne 'popBF001') -and ("$($mgRow.harness)" -eq 'aaaa1111-bbbb2222') -and ("$($mgRow.mergedFrom)" -like 'bf-2026-09-22 (*harness*)') -and ("$($mgRow.mergedFrom)" -notlike '*populationHash*')) 's40-partial-native-keeps-backfill-evidence' (($mgRows | ConvertTo-Json -Depth 4 -Compress))
# Item 12: a mixed corpus compares structured metrics and alerts, not
# only text: corrections, two cohorts, a malformed row, a schedule edit.
$mxStore = Join-Path $s40 'mixed.jsonl'
$mx = @(10..16 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$mx += New-Night '2026-09-17' '2026-09-17-023000' 610
$mx[-1].env = [pscustomobject]@{ os = '10.0.27000.0'; dpi = 'primary 96x96'; dotnet = '10.0.400' }
$null = Sync-MetricsStore $mxStore @($mx)
$mx[3].legs.'run-a'.testSeconds = 640
[System.IO.File]::AppendAllText($mxStore, "{not json`n")
$mxRows = @(Sync-MetricsStore $mxStore @($mx))
$mxBack = @($mxRows | Sort-Object { "$($_.night)" } | ForEach-Object { ConvertFrom-MetricsRow $_ })
$mxRawJ = @($mx | ForEach-Object { ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $_)) -Depth 6 -Compress })
$mxBackJ = @($mxBack | ForEach-Object { ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $_)) -Depth 6 -Compress })
$mxAlertsRaw = @(Get-TrendAlerts $mx) -join "`n"
$mxAlertsBack = @(Get-TrendAlerts $mxBack) -join "`n"
$mxSched = [pscustomobject]@{ First = '2026-09-10'; Entries = @([pscustomobject]@{ First = '2026-09-10'; Trigger = '02:30'; IntervalDays = 1 }, [pscustomobject]@{ First = '2026-09-14'; Trigger = '03:00'; IntervalDays = 2 }) }
$mxNorm = { param($l) @($l | Where-Object { ($_ -notlike '- Metrics store:*') -and ($_ -notlike '- Pruned night*') } | ForEach-Object { ($_ -replace ' \(metrics\)', '') -replace '; evidence .*$', '' }) }
$mxTextRaw = & $mxNorm @(Format-TrendTable $mx $Q $today @{} @() @() $mxSched)
$mxTextBack = & $mxNorm @(Format-TrendTable $mxBack $Q $today @{} @() @() $mxSched)
$mxTextDiff = @(Compare-Object $mxTextRaw $mxTextBack | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
Assert ((($mxRawJ -join "`n") -eq ($mxBackJ -join "`n")) -and ($mxAlertsRaw -eq $mxAlertsBack) -and ($mxAlertsRaw -like '*Rebaseline: cohort changed on 2026-09-17*') -and (@($script:MetricsLastMalformed).Count -eq 1) -and ($mxTextDiff.Count -eq 0) -and (@($mxTextRaw | Where-Object { $_ -like '| 2026-09-18 | missing |*' }).Count -eq 1) -and (@($mxTextRaw | Where-Object { $_ -like '| 2026-09-19 *' }).Count -eq 0)) 's40-mixed-corpus-structured-equivalence' "$mxAlertsRaw || $mxAlertsBack || $($mxTextDiff -join ' / ')"
# Item 13: a pruned night names its source, derivation, and lost evidence.
$pe = @(Format-PrunedEvidence @($mxBack[0]))
Assert (($pe.Count -eq 1) -and ($pe[0] -eq '- Pruned night 2026-09-10 (2026-09-10-023000-pid1): values from morning-2026-09-10-023000.result.json, derivation 2; raw evidence pruned, metrics only')) 's40-pruned-value-explains-itself' ($pe -join ' | ')
# R5-F1: a valid supersession record naming a planted path is sanitized.
$lgSup = Join-Path $s40 'legacy-sup.jsonl'
$lgNat = New-Night '2026-09-18' '2026-09-18-023000'
$lgBf = New-Night '2026-09-18' '2026-09-18-023000'; $lgBf.identity = 'C:\Users\op\bf'
$lgBf | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ reserve = [pscustomobject]@{ confidence = 'high'; source = 'log' } }) -Force
$lgNatRow = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $lgNat)) -Depth 6 -Compress
$lgBfRow = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $lgBf)) -Depth 6 -Compress
$lgRec = ConvertTo-Json ([pscustomobject]@{ schema = 'supersession/1'; night = '2026-09-18'; native = '2026-09-18-023000-pid1@h0st0001'; backfill = 'C:\Users\op\bf@h0st0001'; recorded = '2026-09-18T00:00:00Z' }) -Compress
[System.IO.File]::WriteAllText($lgSup, "$lgNatRow`n$lgBfRow`n$lgRec`n")
$lgPre = Read-MetricsStore $lgSup
$null = Compress-MetricsStore $lgSup
$lgSupAfter = [System.IO.File]::ReadAllText($lgSup)
Assert ((@($lgPre.Supersessions).Count -eq 1) -and ($lgSupAfter -like '*supersession/1*') -and ($lgSupAfter -notlike '*Users\op*')) 's40-supersession-records-sanitized-on-compaction' $lgSupAfter
# Item 14: a planted path in a legacy row is redacted on compaction, in
# the store and in its backup.
$lgStore = Join-Path $s40 'legacy.jsonl'
$lgRow = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow (New-Night '2026-09-18' '2026-09-18-023000'))) -Depth 6 -Compress
$lgRow = $lgRow -replace '"incidents":\[\]', '"incidents":["- INC-aaaa1111 `UI.A` x1 (Run A): C:\\Users\\op\\secret\\notes.txt missing"]'
[System.IO.File]::WriteAllText($lgStore, "$lgRow`n")
$null = Compress-MetricsStore $lgStore
$lgAll = [System.IO.File]::ReadAllText($lgStore) + [System.IO.File]::ReadAllText("$lgStore.bak")
Assert (($lgRow -like '*Users\\op*') -and ($lgAll -notlike '*Users\\op*') -and ($lgAll -notlike '*secret*') -and ($lgAll -like '*`[path`]*')) 's40-legacy-row-redacted-on-compaction' $lgAll
# Item 15: a persisting alert raises once; a recovered one closes; a
# re-evaluated night closes as corrected.
$alPath = Join-Path $s40 'alerts.json'
$al1 = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-27 vs baseline 600s (+50%, median of 7 night(s))') $alPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'n27' })
$al2 = Update-AlertLedger @('- ALERT runa-duration: 950s on 2026-09-28 vs baseline 600s (+58%, median of 7 night(s))') $alPath ([pscustomobject]@{ Night = '2026-09-28'; Host = 'h0st0001'; Identity = 'n28' })
$al3 = Update-AlertLedger @() $alPath ([pscustomobject]@{ Night = '2026-09-29'; Host = 'h0st0001'; Identity = 'n29' })
Assert ((@($al1.New).Count -eq 1) -and (@($al2.New).Count -eq 0) -and (@($al2.Persisting).Count -eq 1) -and (@($al3.Closed).Count -eq 1) -and ($al3.Closed[0].State -eq 'recovered') -and ($al3.Closed[0].Id -eq 'h0st0001|runa-duration')) 's40-alert-raises-once-and-closes'
$al4 = Update-AlertLedger @('- ALERT recurring-flake: INC-aaaa1111 on 2026-09-30 and 2026-09-29') $alPath ([pscustomobject]@{ Night = '2026-09-30'; Host = 'h0st0001'; Identity = 'n30#r1' })
$al5 = Update-AlertLedger @() $alPath ([pscustomobject]@{ Night = '2026-09-30'; Host = 'h0st0001'; Identity = 'n30#r2' })
$al6 = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-10-01 vs baseline 600s (+50%, median of 7 night(s))') $alPath ([pscustomobject]@{ Night = '2026-10-01'; Host = 'h0st0002'; Identity = 'm01' })
Assert ((@($al4.New).Count -eq 1) -and ($al5.Closed[0].State -eq 'corrected') -and ($al5.Closed[0].Id -eq 'h0st0001|recurring-flake|INC-aaaa1111') -and (@($al6.New).Count -eq 1) -and (@($al6.Closed).Count -eq 0)) 's40-alert-corrected-and-host-scoped'
# R1-F3: the evaluation identity carries the revision.
$rvBase = @(20..26 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$rvLate = New-Night '2026-09-27' '2026-09-27-023000' 900; $rvLate | Add-Member -NotePropertyName revision -NotePropertyValue 2 -Force
$script:LastTrendEvaluation = $null
$null = Get-TrendAlerts (@($rvBase) + @($rvLate))
Assert ("$($script:LastTrendEvaluation.Identity)" -eq '2026-09-27-023000-pid1#r2') 's40-evaluation-identity-carries-revision' "$($script:LastTrendEvaluation.Identity)"
# R1-F6: transitions stay pending until delivery is confirmed, across
# re-renders.
$dvPath = Join-Path $s40 'delivery.json'
$null = Update-AlertLedger @('- ALERT pass-rate: 90% on 2026-09-27 vs baseline 100% (-10 points, median of 7 night(s))') $dvPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'a#r1' })
$null = Update-AlertLedger @('- ALERT pass-rate: 90% on 2026-09-27 vs baseline 100% (-10 points, median of 7 night(s))') $dvPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'a#r1' })
$dv1 = Get-PendingAlertNotifications $dvPath
Confirm-AlertNotifications $dvPath @($dv1.Keys)
$dv2 = Get-PendingAlertNotifications $dvPath
$null = Update-AlertLedger @() $dvPath ([pscustomobject]@{ Night = '2026-09-28'; Host = 'h0st0001'; Identity = 'b#r1' })
$null = Update-AlertLedger @() $dvPath ([pscustomobject]@{ Night = '2026-09-28'; Host = 'h0st0001'; Identity = 'b#r1' })
$dv3 = Get-PendingAlertNotifications $dvPath
Assert ((@($dv1.Lines).Count -eq 1) -and ($dv1.Lines[0] -like 'ALERT pass-rate*') -and (@($dv2.Lines).Count -eq 0) -and ($dv2.Persisting -eq 1) -and (@($dv3.Lines).Count -eq 1) -and ($dv3.Lines[0] -eq 'closed (recovered on 2026-09-28): h0st0001|pass-rate')) 's40-alert-delivery-survives-rerender' "$($dv1.Lines -join ';') / $($dv3.Lines -join ';')"
# R2-F1: an unreadable ledger fails closed and is never overwritten.
$bdPath = Join-Path $s40 'bad-ledger.json'
'{"schema":"alerts/1","alerts":[{"id":' | Set-Content -Path $bdPath -Encoding UTF8
$bdBefore = [System.IO.File]::ReadAllText($bdPath)
$bdThrew = $false
try { $null = Update-AlertLedger @('- ALERT pass-rate: 90% on 2026-09-27 vs baseline 100%') $bdPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'a#r1' }) } catch { $bdThrew = ("$($_.Exception.Message)" -like '*alert ledger*unreadable*') }
$bdPendThrew = $false
try { $null = Get-PendingAlertNotifications $bdPath } catch { $bdPendThrew = $true }
Assert ($bdThrew -and $bdPendThrew -and ([System.IO.File]::ReadAllText($bdPath) -eq $bdBefore)) 's40-corrupt-ledger-fails-closed'
# R2-F3: the revision survives the metrics row, so a metrics-only
# evaluation still tells a corrected result apart.
$rvRow = ConvertFrom-MetricsRow ((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $rvLate)) -Depth 6 -Compress) | ConvertFrom-Json)
$script:LastTrendEvaluation = $null
$null = Get-TrendAlerts (@($rvBase) + @($rvRow))
Assert ("$($script:LastTrendEvaluation.Identity)" -eq '2026-09-27-023000-pid1#r2') 's40-revision-survives-metrics' "$($script:LastTrendEvaluation.Identity)"
# R3-F2: a reopening on the same night is its own occurrence and stays
# pending after the first opening was delivered.
$ocPath = Join-Path $s40 'occurrence.json'
$ocAlert = '- ALERT runa-duration: 900s on 2026-09-27 vs baseline 600s (+50%, median of 7 night(s))'
$null = Update-AlertLedger @($ocAlert) $ocPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'o#r1' })
Confirm-AlertNotifications $ocPath @((Get-PendingAlertNotifications $ocPath).Keys)
$null = Update-AlertLedger @() $ocPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'o#r2' })
$null = Update-AlertLedger @($ocAlert) $ocPath ([pscustomobject]@{ Night = '2026-09-27'; Host = 'h0st0001'; Identity = 'o#r3' })
$ocPend = Get-PendingAlertNotifications $ocPath
Assert ((@($ocPend.Lines | Where-Object { $_ -like 'ALERT runa-duration*' }).Count -eq 1) -and (@($ocPend.Lines | Where-Object { $_ -like 'closed (corrected on 2026-09-27)*' }).Count -eq 1) -and (@($ocPend.Keys | Sort-Object -Unique).Count -eq 2)) 's40-reopening-is-its-own-occurrence' ($ocPend.Lines -join ' | ')
# R3-F3: two hosts' runs sharing stamp and pid keep separate rows, and an
# identity@host exclusion reaches only that host.
$twStore = Join-Path $s40 'twohosts.jsonl'
$twA = New-Night '2026-09-25' '2026-09-25-023000'
$twB = New-Night '2026-09-25' '2026-09-25-023000' 700; $twB.hostKey = 'h0st0002'
$twRows = @(Sync-MetricsStore $twStore @($twA, $twB))
$twBack = Read-MetricsStore $twStore
$twEx = @{ '2026-09-25-023000-pid1@h0st0002' = 'rebuilt' }
$twA2 = New-Night '2026-09-25' '2026-09-25-023000'; $twB2 = New-Night '2026-09-25' '2026-09-25-023000'; $twB2.hostKey = 'h0st0002'
$twN = Set-ResultExclusions @($twA2, $twB2) $twEx
Assert (($twRows.Count -eq 2) -and ($twBack.Rows.Count -eq 2) -and $twBack.Rows.Contains('2026-09-25-023000-pid1@h0st0001') -and $twBack.Rows.Contains('2026-09-25-023000-pid1@h0st0002') -and ($twN -eq 1) -and ("$($twB2.excluded)" -eq 'rebuilt') -and ("$(try { $twA2.excluded } catch { '' })" -eq '')) 's40-hosts-sharing-an-identity-keep-their-rows' (@($twBack.Rows.Keys) -join ',')
# R1-F4: every host's series is evaluated in the table.
$mhA = @(20..27 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600 })
$mhB = @(20..27 | ForEach-Object { $n = New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023500' -f $_) $(if ($_ -eq 27) { 900 } else { 600 }); $n.identity = ('2026-09-{0:d2}-023500-pid2' -f $_); $n.hostKey = 'h0st0002'; $n })
$tmh = @(Format-TrendTable (@($mhA) + @($mhB)) $Q $today)
$mhGroups = @($script:TrendAlertGroups)
$mhIdx = [array]::IndexOf($tmh, '- Host h0st0002:')
Assert (($mhGroups.Count -eq 2) -and (@($mhGroups | Where-Object { ($_.Evaluation.Host -eq 'h0st0002') -and (@($_.Alerts).Count -eq 1) }).Count -eq 1) -and (@($mhGroups | Where-Object { ($_.Evaluation.Host -eq 'h0st0001') -and (@($_.Alerts).Count -eq 0) }).Count -eq 1) -and ($mhIdx -ge 0) -and ($tmh[$mhIdx + 1] -like '- ALERT runa-duration: 900s*')) 's40-every-host-is-evaluated' (($tmh | Where-Object { ($_ -like '- Host*') -or ($_ -like '- ALERT*') }) -join ' | ')
# Item 16: a rollback between baseline and latest reads non-linear, and
# the context labels itself correlation, not cause.
$savedProbe = $script:AncestryProbe
$anc = @{ 'c1|c2' = $true; 'c2|c3' = $false; 'c3|c2' = $true; 'c1|c4' = $false; 'c4|c1' = $false }
$script:AncestryProbe = { param($A, $B) if ($anc.ContainsKey("$A|$B")) { return $anc["$A|$B"] }; return $null }
$shRoll = Get-CommitRangeShape @('c1', 'c1', 'c2', 'c3')
$shDiv = Get-CommitRangeShape @('c1', 'c4')
$shUnk = Get-CommitRangeShape @('c1', 'c9')
$shLin = Get-CommitRangeShape @('c1', 'c2')
$rbBase = @(20..26 | ForEach-Object { $n = New-Night ('2026-09-{0:d2}' -f $_) ('2026-09-{0:d2}-023000' -f $_) 600; $n | Add-Member -NotePropertyName commit -NotePropertyValue $(if ($_ -lt 24) { 'c1' } else { 'c2' }) -Force; $n })
$rbLate = New-Night '2026-09-27' '2026-09-27-023000' 900; $rbLate | Add-Member -NotePropertyName commit -NotePropertyValue 'c3' -Force
$rbCtx = @(Get-TrendAlerts (@($rbBase) + @($rbLate)) | Where-Object { $_ -like '  - runa-duration context:*' })
$script:AncestryProbe = $savedProbe
Assert (($shRoll -eq 'non-linear (rollback to c3)') -and ($shDiv -eq 'non-linear (divergent at c4)') -and ($shUnk -like 'ancestry unavailable*') -and ($shLin -eq 'linear') -and ($rbCtx.Count -eq 1) -and ($rbCtx[0] -like '*revisions c1..c3 (non-linear (rollback to c3))*correlation, not cause')) 's40-attribution-reads-rollback-as-correlation' "$shRoll / $shDiv / $shUnk / $shLin / $($rbCtx -join '')"

# ---- Section 47: trend and telemetry third residuals -----------------
$d47 = Join-Path $dir 's47'
$null = New-Item -ItemType Directory -Force -Path $d47
# Item 1: two governed schedules on one host read as a named conflict.
$sc1 = New-Night '2026-09-20' '2026-09-20-023000'; $sc1.trigger = 'task \ScratchPad\Nightly UI'
$sc2 = New-Night '2026-09-20' '2026-09-20-033000'; $sc2.trigger = 'task \ScratchPad\Nightly UI Copy'
$c1 = Select-CanonicalRuns @($sc1, $sc2)
$t1 = @(Format-TrendTable @($sc1, $sc2) $Q $today)
Assert (($c1['2026-09-20|h0st0001'].Canonical -eq '') -and ("$($c1['2026-09-20|h0st0001'].Conflict)" -like 'governed runs from 2 schedules*') -and (@($t1 | Where-Object { $_ -like '- SCHEDULE CONFLICT: night 2026-09-20 on host h0st0001 has governed runs from 2 schedules*never one merged night*' }).Count -eq 1)) 's47-two-schedules-conflict-by-name' ($t1 -join ' | ')
# Item 2: pre-host results with conflicting environments read unresolved.
$lg1 = New-Night '2026-09-21' '2026-09-21-023000'; $lg1.hostKey = ''; $lg1.env | Add-Member -NotePropertyName topology -NotePropertyValue 'DISPLAY1 2560x1440' -Force
$lg2 = New-Night '2026-09-21' '2026-09-21-120000' 600 'manual'; $lg2.hostKey = ''; $lg2.env | Add-Member -NotePropertyName topology -NotePropertyValue 'DISPLAY1 1920x1080' -Force
$lg3 = New-Night '2026-09-21' '2026-09-21-130000' 600 'manual'; $lg3.hostKey = ''; $lg3.env | Add-Member -NotePropertyName topology -NotePropertyValue 'DISPLAY1 2560x1440' -Force; $lg3.env | Add-Member -NotePropertyName session -NotePropertyValue 'op/Console' -Force
$lg1.env | Add-Member -NotePropertyName session -NotePropertyValue 'op/' -Force
$c2 = Select-CanonicalRuns @($lg1, $lg2)
$c2b = Select-CanonicalRuns @($lg1, $lg3)
Assert (($c2['2026-09-21|legacy'].Canonical -eq '') -and ("$($c2['2026-09-21|legacy'].Unresolved)" -like '*2 conflicting environments*') -and ($c2b['2026-09-21|legacy'].Canonical -ne '')) 's47-legacy-conflicting-environments-unresolved' "$($c2['2026-09-21|legacy'].Unresolved)"
# Item 3: a renamed host's old key maps to its new key.
'| Old | New | Reason |', '| --- | --- | --- |', '| 0a0a0a0a | 0b0b0b0b | renamed host |' | Set-Content -Path (Join-Path $d47 'aliases.md') -Encoding UTF8
$script:HostAliases = Read-HostAliases (Join-Path $d47 'aliases.md')
$old = New-Night '2026-09-22' '2026-09-22-023000'; $old.hostKey = '0a0a0a0a'
$new = New-Night '2026-09-23' '2026-09-23-023000'; $new.hostKey = '0b0b0b0b'
$k3 = @((Get-ResultHostKey $old), (Get-ResultHostKey $new))
$script:HostAliases = @{}
Assert (($k3[0] -eq '0b0b0b0b') -and ($k3[1] -eq '0b0b0b0b')) 's47-host-alias-maps-old-to-new' ($k3 -join ',')
# Item 4: a persisting alert on green runs is acknowledged.
$alPath = Join-Path $d47 'alerts.json'
$ev = [pscustomobject]@{ Night = '2026-09-24'; Host = 'h0st0001'; Identity = 'e1' }
$null = Update-AlertLedger @('- ALERT runa-duration: 900s on 2026-09-24 vs baseline 600s') $alPath $ev
'| Alert | Owner | Date | Reason |', '| --- | --- | --- | --- |', '| h0st0001|runa-duration | operator | 2026-09-25 | new UI suite is slower by design |' | Set-Content -Path (Join-Path $d47 'alert-acks.md') -Encoding UTF8
$ev2 = [pscustomobject]@{ Night = '2026-09-25'; Host = 'h0st0001'; Identity = 'e2' }
$null = Update-AlertLedger @('- ALERT runa-duration: 910s on 2026-09-25 vs baseline 600s') $alPath $ev2 @() (Read-AlertAcks (Join-Path $d47 'alert-acks.md'))
$lg4 = Read-AlertLedger $alPath
$pend4 = Get-PendingAlertNotifications $alPath
$e4 = @($lg4.alerts | Where-Object { $_.id -eq 'h0st0001|runa-duration' })[0]
Assert (("$($e4.acknowledged)" -like 'operator on 2026-09-25: new UI suite*') -and ($e4.state -eq 'open')) 's47-green-run-alert-acknowledged' "$($e4.acknowledged) state=$($e4.state) persisting=$($pend4.Persisting) acked=$($pend4.Acknowledged)"
# Item 5: a returning cohort reuses its baseline; a long cold start says so.
$retRows = @()
foreach ($i in 1..6) { $n = New-Night ('2026-08-{0:d2}' -f (10 + $i)) ('2026-08-{0:d2}-023000' -f (10 + $i)) 600; $retRows += $n }
foreach ($i in 1..3) { $n = New-Night ('2026-08-{0:d2}' -f (20 + $i)) ('2026-08-{0:d2}-023000' -f (20 + $i)) 600; $n.harness = 'cccc3333-dddd4444'; $retRows += $n }
$retLate = New-Night '2026-09-10' '2026-09-10-023000' 5000
$g5 = @(Get-TrendAlerts (@($retRows) + @($retLate)))
$coldRows = @()
foreach ($i in 1..11) { $n = New-Night ('2026-09-{0:d2}' -f $i) ('2026-09-{0:d2}-023000' -f $i) 600; $n.harness = 'eeee5555-ffff6666'; $n.legs.'run-a'.testSeconds = $null; $coldRows += $n }
$g5b = @(Get-TrendAlerts $coldRows)
Assert ((@($g5 | Where-Object { $_ -like '- Rebaseline: cohort returned; reusing *earlier same-cohort night(s)*' }).Count -eq 1) -and (@($g5 | Where-Object { $_ -like '- ALERT runa-duration*' }).Count -eq 1) -and (@($g5b | Where-Object { $_ -like '*PROLONGED INSUFFICIENCY: runa-duration has had no actionable baseline for 11 night(s)*' }).Count -eq 1)) 's47-returning-cohort-reuses-and-cold-start-escalates' (($g5 + @('||') + $g5b) -join ' | ')
# Item 6: a native row with counts never takes the backfill's population;
# a tombstone blocks a refill.
$mgS = Join-Path $d47 'merge.jsonl'
$bf6 = New-Night '2026-09-26' '2026-09-26-023000'; $bf6.identity = 'bf-2026-09-26-pid1'; $bf6 | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{ passed = [pscustomobject]@{ confidence = 'high'; source = 'trx' } }) -Force; $bf6.populationHash = 'popBF006'; $bf6 | Add-Member -NotePropertyName commit -NotePropertyValue 'abc1234' -Force
$nat6 = New-Night '2026-09-26' '2026-09-26-023000'; $nat6.populationHash = ''; $nat6 | Add-Member -NotePropertyName commit -NotePropertyValue '' -Force; $nat6 | Add-Member -NotePropertyName tombstone -NotePropertyValue @('commit') -Force
$null = Sync-MetricsStore $mgS @($bf6)
$r6 = @(Sync-MetricsStore $mgS @($nat6)) | Where-Object { "$($_.identity)" -eq $nat6.identity } | Select-Object -First 1
Assert (("$($r6.populationHash)" -ne 'popBF006') -and ("$($r6.commit)" -ne 'abc1234')) 's47-merge-keeps-units-and-tombstones' (($r6 | ConvertTo-Json -Depth 4 -Compress))
# Item 7: an all-excluded run reads excluded with zero executions; a green
# run that executed nothing reads unproven.
$ex7 = New-Night '2026-09-27' '2026-09-27-023000'; $ex7 | Add-Member -NotePropertyName excluded -NotePropertyValue 'harness experiment' -Force
$z7 = New-Night '2026-09-28' '2026-09-28-023000' 600 'timer' 0 0 0; $z7.legs.'run-b'.passed = 0
$t7 = @(Format-TrendTable @($ex7, $z7) $Q $today)
Assert ((@($t7 | Where-Object { $_ -like '| 2026-09-27 (excluded) | excluded (0 executed counted; recorded green) |*' }).Count -eq 1) -and (@($t7 | Where-Object { $_ -like '| 2026-09-28 | green (0 executed: unproven) |*' }).Count -eq 1)) 's47-excluded-and-empty-runs-never-read-healthy' ($t7 -join ' | ')
# Item 8: a missing shard manifest reads coverage partial.
$sh8 = New-Night '2026-09-29' '2026-09-29-023000'; $sh8 | Add-Member -NotePropertyName discovery -NotePropertyValue ([pscustomobject]@{ shards = 3; manifests = 2 }) -Force
$t8 = @(Format-TrendTable @($sh8) $Q $today)
Assert (@($t8 | Where-Object { $_ -like '| 2026-09-29 |*| partial (2 of 3 shard manifest(s) read;*' }).Count -eq 1) 's47-missing-shard-reads-partial' ($t8 -join ' | ')
# Item 9: a run still going past its grace reads overrun; a disabled
# schedule reads disabled.
$shPath = Join-Path $d47 'schedule.md'
'| From | Trigger | Interval days |', '| --- | --- | --- |', '| 2026-09-20 | 02:30 | 1 |', '| 2026-09-25 | 02:30 | 0 |' | Set-Content -Path $shPath -Encoding UTF8
$sched9 = Read-ScheduleHistory $shPath
$n9 = New-Night '2026-09-24' '2026-09-24-023000'
$t9 = @(Format-TrendTable @($n9) $Q (Get-Date '2026-09-27 10:00') @{} @() @() $sched9)
$sched9b = Read-ScheduleHistory (Join-Path $d47 'none.md')
$t9b = @(Format-TrendTable @($n9) $Q (Get-Date '2026-09-26 09:00') @{} @() @() $null ([pscustomobject]@{ Night = '2026-09-26'; Started = '2026-09-26 02:30' }))
Assert ((@($t9 | Where-Object { $_ -like '| 2026-09-25 | disabled | - | schedule disabled from 2026-09-25 |*' }).Count -eq 1) -and (@($t9b | Where-Object { $_ -like '| 2026-09-26 | overrun | - | run still going past its grace (started 2026-09-26 02:30) |*' }).Count -eq 1)) 's47-calendar-names-overrun-and-disabled' (($t9 + @('||') + $t9b) -join ' | ')
# Item 10: a restore from a stale backup lists the rows lost since it.
$rs = Join-Path $d47 'restore.jsonl'
$null = Sync-MetricsStore $rs @((New-Night '2026-09-10' '2026-09-10-023000'))
$null = Compress-MetricsStore $rs
$null = Sync-MetricsStore $rs @((New-Night '2026-09-11' '2026-09-11-023000'))
[System.IO.File]::AppendAllText($rs, "{torn`n")
$rsOut = Restore-MetricsStore $rs
Assert ($rsOut -like '*LOST since the backup: 2026-09-11-023000-pid1@h0st0001 (not in the backup)*') 's47-stale-restore-lists-lost-rows' $rsOut
# Item 11: a restore from a pre-rule backup yields sanitized rows, and the
# migration rewrites the retained copy once.
$ds = Join-Path $d47 'disc.jsonl'
$leak = New-Night '2026-09-12' '2026-09-12-023000'; $leak.trigger = 'token=ghp_' + ('a' * 36)
$leakRow = ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $leak)) -Depth 6 -Compress
$leakRow = $leakRow.Replace('"launch":"timer"', '"launch":"timer","note":"api_key=' + ('z' * 12) + '"')
[System.IO.File]::WriteAllText("$ds.bak", $leakRow + "`n")
$mig = @(Update-DisclosureMigration $ds)
$bakText = [System.IO.File]::ReadAllText("$ds.bak")
[System.IO.File]::WriteAllText("$ds.bak", $leakRow + "`n")
$null = Restore-MetricsStore $ds
$restText = [System.IO.File]::ReadAllText($ds)
Assert ((@($mig).Count -eq 1) -and ($bakText -notlike ('*api_key=' + ('z' * 12) + '*')) -and ($restText -notlike ('*api_key=' + ('z' * 12) + '*')) -and (@(Update-DisclosureMigration $ds).Count -eq 0)) 's47-pre-rule-backup-restores-sanitized' (($mig -join ' | ') + ' || ' + $restText.Substring(0, [math]::Min(200, $restText.Length)))
# Item 12: capacity warns at 90 percent, and pruning of archived stamps
# runs while writes are refused.
$cap = Join-Path $d47 'cap.jsonl'
$c12 = New-Night '2026-09-13' '2026-09-13-023000'
$len = [System.Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json ([pscustomobject](ConvertTo-MetricsRow $c12)) -Depth 6 -Compress) + "`n")
$null = Sync-MetricsStore $cap @($c12) $null ([long]($len / 0.95))
$warn12 = "$script:MetricsCapacityWarning"
$pn = Join-Path $d47 'prune'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $pn '2026-09-13-023000')
ConvertTo-Json $c12 -Depth 6 | Set-Content -Path (Join-Path $pn 'morning-2026-09-13-023000.result.json') -Encoding UTF8
$pstore = Join-Path $pn 'metrics.jsonl'
$null = Sync-MetricsStore $pstore @($c12)
$null = Sync-MetricsStore $pstore @((New-Night '2026-09-14' '2026-09-14-023000')) $null 10
$refused12 = "$script:MetricsWriteError"
$del12 = Remove-ArchivedStamp $pn '2026-09-13-023000' $pstore
Assert (($warn12 -like 'metrics store at 9*% of its *-byte cap*') -and ($refused12 -like '*over capacity*pruning of archived stamps still runs*') -and $del12.Deleted) 's47-capacity-warns-and-pruning-still-runs' "$warn12 || $refused12 || $($del12.Reason)"
# Item 13: a derivation-1 row beside derivation-2 rows reads its version
# where coverage depends on the change.
$d1 = ConvertFrom-MetricsRow ([pscustomobject](ConvertTo-MetricsRow (New-Night '2026-09-15' '2026-09-15-023000')))
$d1.PSObject.Properties.Remove('derivation')
$d1 | Add-Member -NotePropertyName derivation -NotePropertyValue 1 -Force
$d2 = New-Night '2026-09-16' '2026-09-16-023000'
$t13 = @(Format-TrendTable @($d1, $d2) $Q $today)
Assert ((@($t13 | Where-Object { ($_ -like '| 2026-09-15 (metrics) |*') -and $_.Contains('[derivation 1; not comparable with derivation 2] |') }).Count -eq 1) -and (@($t13 | Where-Object { ($_ -like '| 2026-09-16 |*') -and ($_ -like '*derivation*') }).Count -eq 0)) 's47-derivation-reads-its-version' ($t13 -join ' | ')
# Item 14: an alert's context names baseline values, samples, exclusions,
# and what recovers it.
$b14 = @(1..7 | ForEach-Object { New-Night ('2026-09-{0:d2}' -f (19 + $_)) ('2026-09-{0:d2}-023000' -f (19 + $_)) 600 })
$b14[0].harness = 'other000-harness'
$l14 = New-Night '2026-09-27' '2026-09-27-023000' 5000
$g14 = @(Get-TrendAlerts (@($b14) + @($l14)))
$ctx14 = @($g14 | Where-Object { $_ -like '  - runa-duration context:*' })
Assert (($ctx14.Count -eq 1) -and $ctx14[0].Contains('baseline values [600, 600, 600, 600, 600, 600]; samples 6') -and ($ctx14[0] -like '*excluded nights: 2026-09-20 (cohort: harness*') -and ($ctx14[0] -like '*recovers when RunA is back under 125% of the 600s baseline median*')) 's47-alert-context-explains-the-calculation' ($ctx14 -join ' | ')

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyTrend.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyTrend.Tests: all green'
exit 0
