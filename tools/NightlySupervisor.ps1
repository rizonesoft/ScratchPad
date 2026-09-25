#Requires -Version 5.1
<#
.SYNOPSIS
  Outer supervisor for the governed nightly run (D00 T02 §15, D00-T02-S14-PR1).
.DESCRIPTION
  Watches a tools/nightly.ps1 run from a separate process and publishes a
  minimal RED tombstone at the fixed morning-report path when the run hangs
  past -TimeoutSeconds or exits without publishing (startup, cleanup,
  checksum, or publication failure the in-process watchdog cannot report
  itself). A fresh report (written after the watch starts, carrying a
  Status line) always stands: the supervisor relays the child exit code
  and writes nothing. Diagnostic flags (-Smoke, -CheckOnly) publish no
  report and are refused here; run them on nightly.ps1 directly.
  Layering: the default 14280 s timeout (PT4H minus 120 s) precedes the
  scheduled task's PT4H kill, so scheduled hangs tombstone instead of
  dying silent; the 120 s covers kill plus atomic write plus scheduler
  slop, and manual runs share the timeout. Next-start recovery
  (D00 T02 §16) stays as the reboot, power-loss, and supervisor-kill
  backstop; fast crash-no-publish tombstones on every path. A supervisor mutex stands
  down second watchers (the scheduled IgnoreNew equivalent), so a
  concurrent supervisor never tombstones a live run's fixed path.
#>
[CmdletBinding()]
param(
  [int]$TimeoutSeconds = 14280,
  [string]$NightlyArgs = '',
  [string]$NightlyPath = ''
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
. (Join-Path $PSScriptRoot 'NightlyNotify.ps1')
if ($NightlyPath -eq '') { $NightlyPath = Join-Path $PSScriptRoot 'nightly.ps1' }
if ($NightlyArgs -match '(^|\s)-(Smoke|CheckOnly)\b') { throw 'supervisor refuses diagnostic flags (they publish no report; run nightly.ps1 directly)' }
if ($TimeoutSeconds -le 0) { throw 'supervisor needs a positive -TimeoutSeconds' }

$supMutex = New-Object System.Threading.Mutex($false, 'Global\ScratchPadNightlySupervisor')
$supHeld = $false
try { $supHeld = $supMutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $supHeld = $true }
if (-not $supHeld) {
  $supNightDir = Join-Path $Root 'build\nightly'
  New-Item -ItemType Directory -Path $supNightDir -Force | Out-Null
  $supStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
  $supId = "$supStamp-pid$PID"
  Write-AtomicReport @("# Stood-down run: $supId", 'Status: stood-down', '', "- At: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", '- Kind: supervisor', '- Holder: another watcher holds Global\ScratchPadNightlySupervisor', '- Verdict: STOOD DOWN (not run; the holder owns the watch)') (Join-Path $supNightDir "loser-$supId.md")
  $supState = Get-SchedulerState (Join-Path $PSScriptRoot 'tasks\nightly-ui.xml')
  $supResult = [pscustomobject]@{ version = 1; stamp = $supStamp; day = (Get-Date -Format 'yyyy-MM-dd'); identity = $supId; verdict = 'stood-down'; exit = 0; reason = 'supervisor mutex held by another watcher'; kind = 'supervisor'; scheduler = [pscustomobject]@{ ok = $supState.Ok; enabled = $supState.Enabled; lastRun = "$($supState.LastRunTime)"; lastResult = $supState.LastResult } }
  Write-AtomicReport @((ConvertTo-Json $supResult -Depth 5)) (Join-Path $supNightDir "loser-$supId.result.json")
  try { & (Join-Path $PSScriptRoot 'NightlyTrend.ps1') -NightDir $supNightDir -OutFile (Join-Path $supNightDir 'trend.md') -LedgerPath (Join-Path $Root 'docs/soak-and-quarantine.md') | Out-Null } catch { }
  Write-Output 'supervisor: another watcher holds the lock; standing down (exit 0, nothing failed)'
  exit 0
}
try {
  $watchStart = Get-Date
  $day = Get-Date -Format 'yyyy-MM-dd'
  $nightDir = Join-Path $Root 'build\nightly'
  New-Item -ItemType Directory -Path $nightDir -Force | Out-Null
  $fixedReport = Join-Path $nightDir "morning-$day.md"
  $childArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$NightlyPath`" $NightlyArgs".Trim()
  Write-Output "supervisor: watching $NightlyPath ($childArgs) for ${TimeoutSeconds}s"
  # Raw .NET launch: Start-Process -PassThru reads ExitCode back empty
  # in Windows PowerShell 5.1 (measured 2026-09-20, same quirk the
  # gated legs route around via jobs), while Process.Start tracks it.
  $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $PSHOME 'powershell.exe'), $childArgs)
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $child = [System.Diagnostics.Process]::Start($psi)
  $exited = $false
  try { $exited = $child.WaitForExit($TimeoutSeconds * 1000) } catch { $exited = $false }
  $timedOut = -not $exited
  if ($timedOut) {
    Write-Output "supervisor: child hung past ${TimeoutSeconds}s; killing pid $($child.Id)"
    try { $child.Kill() } catch { }
  }
  $code = 1
  try { $code = $child.ExitCode } catch { $code = 1 }
  # Freshness decides: a report written after the watch starts with a
  # Status line stands, however the child ended (a post-publication
  # hang still exits 1, but the tombstone must not cover real proof).
  $fresh = $false
  if ((Test-Path $fixedReport) -and ((Get-Item $fixedReport).LastWriteTime -gt $watchStart)) {
    $head = @(Get-Content $fixedReport -TotalCount 8)
    if ((($head -join "`n") -like '*Status:*') -and ($head[0] -like '# Morning report:*')) { $fresh = $true }
  }
  if ($fresh) {
    if ($timedOut) { Write-Output 'supervisor: child hung after publishing; report stands (exit 1)'; exit 1 }
    Write-Output "supervisor: fresh report stands; relaying child exit $code"
    exit $code
  }
  $cause = if ($timedOut) { "child hung past ${TimeoutSeconds}s (pid $($child.Id) killed)" } else { "child exited $code without publishing" }
  Write-AtomicReport @("# Morning report: $day", 'Status: supervisor tombstone', '', "- Supervisor: NightlySupervisor pid $PID (timeout ${TimeoutSeconds}s)", "- Cause: $cause", "- At: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", '- Verdict: RED (supervised run produced no report; investigate the stamp dir, if any)') $fixedReport
  $tombStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
  $tombId = "$tombStamp-pid$PID"
  $tombHead = ''
  try { $tombHead = (git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1).Trim() } catch { }
  $tombLeg = [pscustomobject]@{ ran = $false; passed = 0; failed = 0; skipped = 0; gate = $null; killed = $false; cut = $false; testSeconds = $null }
  $tombI = [pscustomobject]@{ ran = $false; passed = 0; failed = 0; skipped = 0; gate = $null; killed = $false; cut = $false; testSeconds = $null; enforcementRed = $false }
  $tombResult = [pscustomobject]@{ version = 1; stamp = $tombStamp; day = $day; identity = $tombId; verdict = 'red'; exit = 1; trigger = 'supervisor tombstone (hang/no-publish)'; launch = 'unknown'; commit = "$tombHead"; buildError = ''; legs = [pscustomobject]@{ 'run-a' = $tombLeg; 'run-b' = $tombLeg; interactive = $tombI }; soak = [pscustomobject]@{ ran = $false; verdict = 'skipped'; failed = @(); killed = @(); cut = @(); failures = @() }; quarantine = [pscustomobject]@{ overdue = @(); dueSoon = @(); overdueDetail = @() }; incidents = @(); scheduler = [pscustomobject]@{ voted = $false; faults = @(); enabled = $null; lastRun = ''; lastResult = '' }; tree = [pscustomobject]@{ start = 'unknown (tombstone)'; end = 'unknown (tombstone)'; stable = $null }; recovered = 'none'; omissionOk = $false; timings = @{}; reserve = $null; consumed = $null; env = Get-EnvironmentBlock ''; report = "build/nightly/morning-$day.md"; note = "tombstone: $cause; legs unproven by construction" }
  Write-AtomicReport @((ConvertTo-Json $tombResult -Depth 8)) (Join-Path $nightDir "morning-$tombStamp.result.json")
  $tombClass = 'infrastructure'
  try { $tombClass = (Classify-NightlyOutcome $tombResult).Class } catch { }
  try { $null = Invoke-NightlyNotify -Phase 'final' -RunId $tombId -ResultPath (Join-Path $nightDir "morning-$tombStamp.result.json") -Class $tombClass -Title "Nightly $day : RED ($tombClass)" -Lines @("Supervised run produced no report: $cause", "Result: build/nightly/morning-$tombStamp.result.json") -StateDir $nightDir -Sender { param($tt, $ll) Send-NightlyToast $tt $ll } } catch { }
  try { & (Join-Path $PSScriptRoot 'NightlyTrend.ps1') -NightDir $nightDir -OutFile (Join-Path $nightDir 'trend.md') -LedgerPath (Join-Path $Root 'docs/soak-and-quarantine.md') | Out-Null } catch { }
  Write-Output "supervisor: tombstone landed ($cause)"
  exit 1
} finally {
  try { $supMutex.ReleaseMutex() } catch { }
  $supMutex.Dispose()
}
