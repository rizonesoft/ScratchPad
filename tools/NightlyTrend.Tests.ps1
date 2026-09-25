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
Assert (@($tc | Where-Object { $_ -eq '- RunA test-seconds (canonical native nights, last 14): n=4, p50 610, p90 620, p95 620, max 620' }).Count -eq 1) 'series-native-canonical-only' (($tc | Where-Object { $_ -like '*RunA test-seconds*' }) -join '')
$ai = [array]::IndexOf($tc, '## Alerts')
Assert ($tc[$ai + 2] -eq '(none)') 'series-mixed-corpus-no-false-slope' ($tc[$ai + 2])
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
Assert ((($rowsOnly | ForEach-Object { $_.Substring(2, 10) }) -join ',') -eq '2026-09-20,2026-09-21,2026-09-22') 'fixture-out-of-order-sorted' (($rowsOnly | ForEach-Object { $_.Substring(2, 10) }) -join ',')
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
Assert (@($tt | Where-Object { $_ -eq '- RunA test-seconds (canonical native nights, last 14): n=14, p50 570, p90 630, p95 640, max 640' }).Count -eq 1) 'percentiles-count-and-tails' (($tt | Where-Object { $_ -like '*RunA test-seconds*' }) -join '')

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

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyTrend.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyTrend.Tests: all green'
exit 0
