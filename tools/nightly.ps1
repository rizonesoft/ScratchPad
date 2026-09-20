#Requires -Version 5.1
<#
.SYNOPSIS
  Nightly unattended UI plus soak run for ScratchPad.
.DESCRIPTION
  Phase 1 (fenced): tests/UI Category=Interactive in the foreground. Runs
  only inside the quiet-hours window (02:00-06:50 local, or
  SCRATCHPAD_INTERACTIVE_WINDOW) on an UNLOCKED workstation; a locked
  session cannot drive UI, so outside those conditions the phase logs
  its skip and the run continues. -Force runs it regardless for an
  explicitly accepted interruption.
  Phase 2 (soak): full solution minus Interactive with
  SCRATCHPAD_BACKGROUND=1, then UI (non-interactive) and Protocol x5,
  all trx-logged. Soak repeats exclude Interactive: the fenced phase
  owns those, so the soak never grabs the foreground mid-run.
  Logs land under TestResults/nightly-<stamp>/. Exit code is nonzero
  when any executed phase fails. Run by the \ScratchPad\Nightly UI
  scheduled task; also runnable by hand. Uses the repo-local SDK only.
#>
[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$SkipFenced,
  [switch]$SkipSoak,
  [switch]$Smoke,
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SdkDir = Join-Path $Root '.tools\dotnet-win-x64'
$Dotnet = Join-Path $SdkDir 'dotnet.exe'

function Get-InInteractiveWindow {
  $spec = $env:SCRATCHPAD_INTERACTIVE_WINDOW
  if ([string]::IsNullOrWhiteSpace($spec)) { $spec = '02:00-06:50' }
  $m = [regex]::Match($spec, '^(\d{2}):(\d{2})-(\d{2}):(\d{2})$')
  if (-not $m.Success) { return $false }
  try {
    $start = New-TimeSpan -Hours ([int]$m.Groups[1].Value) -Minutes ([int]$m.Groups[2].Value)
    $end = New-TimeSpan -Hours ([int]$m.Groups[3].Value) -Minutes ([int]$m.Groups[4].Value)
  } catch { return $false }
  $now = (Get-Date).TimeOfDay
  if ($end -le $start) { return ($now -ge $start) -or ($now -lt $end) }
  return ($now -ge $start) -and ($now -lt $end)
}

function Get-WorkstationLocked {
  return $null -ne (Get-Process logonui -ErrorAction SilentlyContinue)
}

function Invoke-Step([string]$Name, [scriptblock]$Cmd) {
  # Write-Host, not Write-Output: the caller captures this function's
  # return, which would swallow Write-Output into $code and print
  # nothing. Host lines still land in the transcript.
  Write-Host "--- $Name ---"
  & $Cmd | Write-Host
  $code = $LASTEXITCODE
  Write-Host "--- $Name exit: $code ---"
  return $code
}

if (-not (Test-Path $Dotnet)) { throw "nightly: repo-local SDK missing ($Dotnet); provision first: powershell -ExecutionPolicy Bypass -File tools\provision.ps1" }
$env:DOTNET_ROOT = $SdkDir
$env:PATH = "$SdkDir;" + $env:PATH
$env:DOTNET_MULTILEVEL_LOOKUP = '0'

$waruntime = @(Get-AppxPackage -Name '*WindowsAppRuntime*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Microsoft.WindowsAppRuntime.2*' })
if ($waruntime.Count -eq 0) { throw 'nightly: WindowsAppRuntime 2.x missing; install it before UI runs (see docs/build.md)' }
$theme = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme
$ext = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction SilentlyContinue).HideFileExt
if ($theme -ne 0) { Write-Warning 'nightly: dark app theme not set (AppsUseLightTheme should be 0); goldens will mismatch' }
if ($ext -ne 0) { Write-Warning 'nightly: file extensions hidden (HideFileExt should be 0); dialog tests will fail' }

$inWindow = Get-InInteractiveWindow
$locked = Get-WorkstationLocked
Write-Output "nightly: window=$inWindow locked=$locked force=$($Force.IsPresent)"

if ($CheckOnly) { Write-Output 'nightly: environment OK'; exit 0 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $Root ("TestResults\nightly-" + $stamp)
New-Item -ItemType Directory -Path $runDir | Out-Null
$log = Join-Path $runDir 'nightly.log'
Start-Transcript -Path $log | Out-Null
$failed = $false
try {
  Push-Location $Root
  try {
    if ($Smoke) {
      $code = Invoke-Step 'smoke' { & $Dotnet test tests/Smoke/Smoke.csproj --nologo --logger "trx;LogFileName=smoke.trx" --results-directory $runDir }
      if ($code -ne 0) { $failed = $true }
    } else {
      if (-not $SkipFenced) {
        if ($Force) {
          $code = Invoke-Step 'fenced-interactive' { & $Dotnet test tests/UI/UI.csproj --nologo --filter 'Category=Interactive' -e SCRATCHPAD_INTERACTIVE_FORCE=1 --logger 'trx;LogFileName=ui-interactive.trx' --results-directory $runDir }
          if ($code -ne 0) { $failed = $true }
        } elseif (-not $inWindow) {
          Write-Output 'nightly: fenced phase skipped (outside the quiet-hours window)'
        } elseif ($locked) {
          Write-Output 'nightly: fenced phase skipped (workstation locked; UI cannot be driven)'
        } else {
          $code = Invoke-Step 'fenced-interactive' { & $Dotnet test tests/UI/UI.csproj --nologo --filter 'Category=Interactive' --logger 'trx;LogFileName=ui-interactive.trx' --results-directory $runDir }
          if ($code -ne 0) { $failed = $true }
        }
      }
      if (-not $SkipSoak) {
        # -e is load-bearing: shell exports do not reach the app through
        # the test host (measured 2026-09-17); see docs/testing.md.
        $code = Invoke-Step 'soak-solution' { & $Dotnet test src/ScratchPad.slnx --nologo --filter 'Category!=Interactive' -e SCRATCHPAD_BACKGROUND=1 --logger 'trx;LogFileName=soak-solution.trx' --results-directory $runDir }
        if ($code -ne 0) { $failed = $true }
        for ($i = 1; $i -le 5; $i++) {
          $code = Invoke-Step "soak-ui-$i" { & $Dotnet test tests/UI/UI.csproj --no-build --nologo --filter 'Category!=Interactive' -e SCRATCHPAD_BACKGROUND=1 --logger "trx;LogFileName=ui-soak-$i.trx" --results-directory $runDir }
          if ($code -ne 0) { $failed = $true }
        }
        for ($i = 1; $i -le 5; $i++) {
          $code = Invoke-Step "soak-protocol-$i" { & $Dotnet test tests/Protocol/Protocol.csproj --no-build --nologo -e SCRATCHPAD_BACKGROUND=1 --logger "trx;LogFileName=protocol-soak-$i.trx" --results-directory $runDir }
          if ($code -ne 0) { $failed = $true }
        }
      }
    }
  } finally {
    Pop-Location
  }
} finally {
  Stop-Transcript | Out-Null
}
if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
Write-Output 'nightly: GREEN'
exit 0
