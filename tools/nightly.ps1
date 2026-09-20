#Requires -Version 5.1
<#
.SYNOPSIS
  Nightly governed regression run for ScratchPad (D00 T02 §9).
.DESCRIPTION
  Three legs inside the 02:00-06:50 window, owned by the \ScratchPad\Nightly UI
  scheduled task (daily 02:30 local). Run A: full solution default filter with
  ForegroundLog census proof. Run B: Category=Primary with --expect-primary.
  Interactive: the fenced collection, owning the foreground. Each leg gets its
  own transcript under build/nightly/YYYY-MM-DD-{default,primary,full}.log;
  trx plus gate logs land under build/nightly/YYYY-MM-DD/; the morning report
  lands at build/nightly/morning-YYYY-MM-DD.md. A red leg never blocks the
  later legs; only the exit code is red. -SkipSoak drops the §5 repeat loop
  that otherwise follows the legs. -Force runs the Interactive leg outside
  the window for an explicitly accepted interruption. Uses the repo-local SDK
  only. Procedure: docs/testing.md "Nightly regression run".
#>
[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$SkipDefault,
  [switch]$SkipPrimary,
  [switch]$SkipFenced,
  [switch]$SkipSoak,
  [switch]$Smoke,
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SdkDir = Join-Path $Root '.tools\dotnet-win-x64'
$Dotnet = Join-Path $SdkDir 'dotnet.exe'
$GateExe = Join-Path $Root 'Bin\ForegroundLog\Debug\ForegroundLog.exe'

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

function Start-LegLog([string]$Path, [string]$Scope) {
  if (Test-Path $Path) { Remove-Item $Path -Force }
  Start-Transcript -Path $Path | Out-Null
  $head = 'unknown'
  try { $head = (git -C $Root rev-parse HEAD).Trim() } catch { }
  Write-Output "nightly: scope=$Scope head=$head day=$(Get-Date -Format 'yyyy-MM-dd') leg=$(Split-Path -Leaf $Path)"
}

function Stop-LegLog {
  Stop-Transcript | Out-Null
}

function Invoke-GatedLeg([string]$Name, [int]$GateSeconds, [string]$GateArgs, [string]$GateLog, [string]$VerdictFile, [scriptblock]$TestCmd) {
  # Gate and suite run together: the gate polls the whole window while the
  # tests drive. The suite must finish inside the window; overrun fails the
  # leg (partial proof is no proof). Returns a result object, never throws
  # for a red leg (missing gate binary throws: that is a broken run, not a
  # red leg).
  if (-not (Test-Path $GateExe)) { throw "nightly: gate binary missing ($GateExe); build tools/ForegroundLog first" }
  $gate = Start-Process -FilePath $GateExe -ArgumentList "$GateSeconds $GateLog $GateArgs" -NoNewWindow -PassThru -RedirectStandardOutput $VerdictFile
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $TestCmd | Write-Host
  $testCode = $LASTEXITCODE
  $sw.Stop()
  $gate.WaitForExit()
  $gateCode = $gate.ExitCode
  $verdict = ''
  if (Test-Path $VerdictFile) { $verdict = (Get-Content $VerdictFile -Raw).Trim() }
  $overrun = $sw.Elapsed.TotalSeconds -gt $GateSeconds
  Write-Host "--- $Name gate exit: $gateCode verdict: $verdict overrun: $overrun test-seconds: $([int]$sw.Elapsed.TotalSeconds) ---"
  return [pscustomobject]@{ TestCode = $testCode; GateCode = $gateCode; Verdict = $verdict; Overrun = $overrun }
}

function Get-TrxSummary([string]$TrxPath) {
  if (-not (Test-Path $TrxPath)) { return $null }
  $t = [xml](Get-Content $TrxPath -Raw)
  $results = @($t.TestRun.Results.UnitTestResult)
  $passed = @($results | Where-Object { $_.outcome -eq 'Passed' }).Count
  $failed = @($results | Where-Object { $_.outcome -eq 'Failed' })
  $skipped = @($results | Where-Object { $_.outcome -eq 'NotExecuted' })
  $failLines = @($failed | ForEach-Object {
    $msg = ''
    if ($_.Output -and $_.Output.ErrorInfo -and $_.Output.ErrorInfo.Message) { $msg = $_.Output.ErrorInfo.Message }
    $msg = ($msg -split "`r?`n")[0]
    if ($msg.Length -gt 160) { $msg = $msg.Substring(0, 160) }
    '  - ' + $_.testName + ': ' + $msg
  })
  $skipLines = @($skipped | ForEach-Object {
    $reason = 'triage annotates'
    if ($_.Output -and $_.Output.ErrorInfo -and $_.Output.ErrorInfo.Message) { $reason = (($_.Output.ErrorInfo.Message -split "`r?`n")[0]) }
    '  - ' + $_.testName + ': ' + $reason
  })
  return [pscustomobject]@{ Passed = $passed; FailedCount = $failed.Count; Failed = $failLines; Skipped = $skipLines }
}

function Get-TranscriptRows([string]$LogPath) {
  # VSTest assembly summary lines. A solution-level trx keeps only the last
  # assembly (each project overwrites LogFileName), so the transcript is the
  # authoritative per-leg count; the trx carries failure messages.
  $rows = @()
  if (-not (Test-Path $LogPath)) { return $rows }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '(Passed!|Failed!)\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),.*-\s*(\S+)\s*\(net')
    if ($m.Success) {
      $rows += [pscustomobject]@{ Assembly = $m.Groups[5].Value; Passed = [int]$m.Groups[3].Value; Failed = [int]$m.Groups[2].Value; Skipped = [int]$m.Groups[4].Value }
    }
  }
  return $rows
}

function Get-TranscriptFailures([string]$LogPath) {
  $names = @()
  if (-not (Test-Path $LogPath)) { return $names }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '^\s*Failed (\S+) \[')
    if ($m.Success -and ($names -notcontains $m.Groups[1].Value)) { $names += $m.Groups[1].Value }
  }
  return $names
}

function Get-LegSummary([string]$TrxPath, [string]$LogPath) {
  $trx = Get-TrxSummary $TrxPath
  $rows = Get-TranscriptRows $LogPath
  if ($rows.Count -eq 0) { return $trx }
  $p = ($rows | Measure-Object Passed -Sum).Sum
  $f = ($rows | Measure-Object Failed -Sum).Sum
  $s = ($rows | Measure-Object Skipped -Sum).Sum
  $failLines = @()
  $trxNames = @()
  if ($null -ne $trx) {
    $failLines += $trx.Failed
    $trxNames = @($trx.Failed | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  }
  foreach ($n in (Get-TranscriptFailures $LogPath)) {
    if ($trxNames -notcontains $n) { $failLines += "  - $n : see transcript" }
  }
  $skipLines = @()
  if ($null -ne $trx) { $skipLines = $trx.Skipped }
  $asm = ($rows | ForEach-Object { "$($_.Assembly) $($_.Passed)/$($_.Failed)/$($_.Skipped)" }) -join ', '
  return [pscustomobject]@{ Passed = $p; FailedCount = $f; Failed = $failLines; Skipped = $skipLines; Assemblies = $asm }
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

$day = Get-Date -Format 'yyyy-MM-dd'
$nightDir = Join-Path $Root 'build\nightly'
New-Item -ItemType Directory -Path $nightDir -Force | Out-Null
$trxDir = Join-Path $nightDir $day
New-Item -ItemType Directory -Path $trxDir -Force | Out-Null
# Pre-flight: reap orphaned test apps from a dead run. Path-scoped to this
# checkout's Bin, so a released ScratchPad anywhere else is never touched.
# The 02:30 run's parent died mid-loop and left three holding Bin locks,
# which reds the build (MSB3027) until reaped; stale windows also
# contaminate window-enumerating tests, so the reap precedes every leg.
$reapNotes = @()
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='ScratchPad.exe' OR Name='testhost.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -like "$Root\Bin\*" })) {
  $note = "$($p.Name) pid=$($p.ProcessId) started=$($p.CreationDate)"
  Write-Output "nightly: reaping orphan $note"
  $reapNotes += $note
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
$failed = $false
$gateA = $null
$gateB = $null

if ($Smoke) {
  $log = Join-Path $nightDir "$day-smoke.log"
  if (Test-Path $log) { Remove-Item $log -Force }
  Start-Transcript -Path $log | Out-Null
  try {
    Push-Location $Root
    try {
      $code = Invoke-Step 'smoke' { & $Dotnet test tests/Smoke/Smoke.csproj --nologo --logger "trx;LogFileName=smoke.trx" --results-directory $trxDir }
      if ($code -ne 0) { $failed = $true }
    } finally {
      Pop-Location
    }
  } finally {
    Stop-Transcript | Out-Null
  }
  if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
  Write-Output 'nightly: GREEN'
  exit 0
}

Push-Location $Root
try {
  # One build up front: every leg then runs --no-build, so a leg never
  # rebuilds mid-proof. ForegroundLog rides no solution; build it here.
  $code = Invoke-Step 'build' { & $Dotnet build src/ScratchPad.slnx --nologo }
  if ($code -ne 0) { throw "nightly: solution build failed ($code); no leg runs on a broken build" }
  $code = Invoke-Step 'build-gate' { & $Dotnet build tools/ForegroundLog/ForegroundLog.csproj --nologo }
  if (($code -ne 0) -or (-not (Test-Path $GateExe))) { throw "nightly: gate build failed ($code); Run A and B need the gate binary" }

  if (-not $SkipDefault) {
    $log = Join-Path $nightDir "$day-default.log"
    Start-LegLog $log 'full tree, Category!=Interactive, backgrounded'
    try {
      $trx = Join-Path $trxDir 'run-a.trx'
      $gateLog = Join-Path $trxDir 'gate-default.log'
      $verdictFile = Join-Path $trxDir 'gate-default.out'
      # -e is load-bearing: shell exports do not reach the app through
      # the test host (measured 2026-09-17); see docs/testing.md.
      $r = Invoke-GatedLeg 'run-a' 1800 '' $gateLog $verdictFile { & $Dotnet test src/ScratchPad.slnx --no-build --nologo --filter 'Category!=Interactive' -e SCRATCHPAD_BACKGROUND=1 --logger 'trx;LogFileName=run-a.trx' --results-directory $trxDir }
      $gateA = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if (-not $SkipPrimary) {
    $log = Join-Path $nightDir "$day-primary.log"
    Start-LegLog $log 'tests/UI, Category=Primary, backgrounded, expect-primary'
    try {
      $gateLog = Join-Path $trxDir 'gate-primary.log'
      $verdictFile = Join-Path $trxDir 'gate-primary.out'
      $r = Invoke-GatedLeg 'run-b' 300 '--expect-primary' $gateLog $verdictFile { & $Dotnet test tests/UI/UI.csproj --no-build --nologo --filter 'Category=Primary' -e SCRATCHPAD_BACKGROUND=1 --logger 'trx;LogFileName=run-b.trx' --results-directory $trxDir }
      $gateB = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if (-not $SkipFenced) {
    $log = Join-Path $nightDir "$day-full.log"
    if ($Force) {
      Start-LegLog $log 'tests/UI, Category=Interactive, foreground, forced'
      try {
        $code = Invoke-Step 'interactive' { & $Dotnet test tests/UI/UI.csproj --no-build --nologo --filter 'Category=Interactive' -e SCRATCHPAD_INTERACTIVE_FORCE=1 --logger 'trx;LogFileName=interactive.trx' --results-directory $trxDir }
        if ($code -ne 0) { $failed = $true }
      } finally {
        Stop-LegLog
      }
    } elseif (-not $inWindow) {
      Write-Output 'nightly: interactive leg skipped (outside the quiet-hours window)'
    } elseif ($locked) {
      Write-Output 'nightly: interactive leg skipped (workstation locked; UI cannot be driven)'
    } else {
      Start-LegLog $log 'tests/UI, Category=Interactive, foreground'
      try {
        $code = Invoke-Step 'interactive' { & $Dotnet test tests/UI/UI.csproj --no-build --nologo --filter 'Category=Interactive' --logger 'trx;LogFileName=interactive.trx' --results-directory $trxDir }
        if ($code -ne 0) { $failed = $true }
      } finally {
        Stop-LegLog
      }
    }
  }

  if (-not $SkipSoak) {
    for ($i = 1; $i -le 5; $i++) {
      $code = Invoke-Step "soak-ui-$i" { & $Dotnet test tests/UI/UI.csproj --no-build --nologo --filter 'Category!=Interactive' -e SCRATCHPAD_BACKGROUND=1 --logger "trx;LogFileName=ui-soak-$i.trx" --results-directory $trxDir }
      if ($code -ne 0) { $failed = $true }
    }
    for ($i = 1; $i -le 5; $i++) {
      $code = Invoke-Step "soak-protocol-$i" { & $Dotnet test tests/Protocol/Protocol.csproj --no-build --nologo -e SCRATCHPAD_BACKGROUND=1 --logger "trx;LogFileName=protocol-soak-$i.trx" --results-directory $trxDir }
      if ($code -ne 0) { $failed = $true }
    }
  }
} finally {
  Pop-Location
}

# Morning report (D00 T02 §9 item 3): per-leg counts plus failures with
# filing refs appended at triage. Always written, green or red.
$head = 'unknown'
try { $head = (git -C $Root rev-parse HEAD).Trim() } catch { }
$trigger = 'manual (see transcript head)'
try {
  $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
  $pname = (Get-CimInstance Win32_Process -Filter "ProcessId=$parent").Name
  if ($pname -eq 'taskeng.exe') { $trigger = 'cron \ScratchPad\Nightly UI (daily 02:30)' }
  else { $trigger = "manual (parent $pname)" }
} catch { }
$sumA = Get-LegSummary (Join-Path $trxDir 'run-a.trx') (Join-Path $nightDir "$day-default.log")
$sumB = Get-LegSummary (Join-Path $trxDir 'run-b.trx') (Join-Path $nightDir "$day-primary.log")
$sumI = Get-LegSummary (Join-Path $trxDir 'interactive.trx') (Join-Path $nightDir "$day-full.log")
function Format-LegRow([string]$Leg, $Sum, $Gate, [string]$LogName) {
  if ($null -eq $Sum) { return "| $Leg | no trx (leg skipped or produced none) | -- | $($LogName) |" }
  $skips = $Sum.Skipped.Count
  $gate = if ($null -eq $Gate) { 'n/a (owns the foreground)' } else { "exit $($Gate.GateCode) $($Gate.Verdict)" }
  $counts = "$($Sum.Passed) passed, $($Sum.FailedCount) failed, $skips skipped"
  if ($Sum.Assemblies) { $counts += " ($($Sum.Assemblies))" }
  return "| $Leg | $counts | $gate | $($LogName) |"
}
$report = @()
$report += "# Morning report: $day"
$report += ''
$report += "- HEAD: $head"
$report += "- Trigger: $trigger"
$report += "- Window: 02:00-06:50 local (or SCRATCHPAD_INTERACTIVE_WINDOW)"
$reapLine = if ($reapNotes.Count -eq 0) { 'none' } else { ($reapNotes -join '; ') }
$report += "- Pre-flight reaped: $reapLine"
$report += ''
$report += '| Leg | Counts | Gate | Log |'
$report += '| --- | ------ | ---- | --- |'
$report += (Format-LegRow 'Run A (default)' $sumA $gateA "$day-default.log")
$report += (Format-LegRow 'Run B (primary)' $sumB $gateB "$day-primary.log")
$report += (Format-LegRow 'Interactive (collection)' $sumI $null "$day-full.log")
$report += ''
$report += '## Failures (triage appends finding refs)'
$report += ''
$anyFail = $false
foreach ($pair in @( @('Run A', $sumA), @('Run B', $sumB), @('Interactive', $sumI) )) {
  if (($null -ne $pair[1]) -and ($pair[1].FailedCount -gt 0)) {
    $anyFail = $true
    $report += "### $($pair[0])"
    $report += $pair[1].Failed
    $report += ''
  }
}
if (-not $anyFail) { $report += '(none)' ; $report += '' }
$report += '## Skips (triage annotates reasons)'
$report += ''
$anySkip = $false
foreach ($pair in @( @('Run A', $sumA), @('Run B', $sumB), @('Interactive', $sumI) )) {
  if (($null -ne $pair[1]) -and ($pair[1].Skipped.Count -gt 0)) {
    $anySkip = $true
    $report += "### $($pair[0])"
    $report += $pair[1].Skipped
    $report += ''
  }
}
if (-not $anySkip) { $report += '(none)' ; $report += '' }
$report += '## Filings'
$report += ''
$report += '(triage appends one line per failure: test name, finding ref or quarantine row)'
$report += ''
$reportPath = Join-Path $nightDir "morning-$day.md"
$report -join "`r`n" | Set-Content -Path $reportPath -Encoding UTF8
Write-Output "nightly: report at $reportPath"

if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
Write-Output 'nightly: GREEN'
exit 0
