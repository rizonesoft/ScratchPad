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
if ($NightlyPath -eq '') { $NightlyPath = Join-Path $PSScriptRoot 'nightly.ps1' }
if ($NightlyArgs -match '(^|\s)-(Smoke|CheckOnly)\b') { throw 'supervisor refuses diagnostic flags (they publish no report; run nightly.ps1 directly)' }
if ($TimeoutSeconds -le 0) { throw 'supervisor needs a positive -TimeoutSeconds' }

$supMutex = New-Object System.Threading.Mutex($false, 'Global\ScratchPadNightlySupervisor')
$supHeld = $false
try { $supHeld = $supMutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $supHeld = $true }
if (-not $supHeld) {
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
  Write-Output "supervisor: tombstone landed ($cause)"
  exit 1
} finally {
  try { $supMutex.ReleaseMutex() } catch { }
  $supMutex.Dispose()
}
