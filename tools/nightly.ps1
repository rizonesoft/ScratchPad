#Requires -Version 5.1
<#
.SYNOPSIS
  Nightly governed regression run for ScratchPad (D00 T02 §9).
.DESCRIPTION
  Three legs inside the 02:00-06:50 window, owned by the \ScratchPad\Nightly UI
  scheduled task (daily 02:30 local). Run A: full solution default filter with
  ForegroundLog census proof. Run B: Category=Primary with --expect-primary.
  Interactive: the fenced collection, owning the foreground. Each invocation
  owns a stamp-scoped directory: leg transcripts land under
  build/nightly/YYYY-MM-DD-HHmmss-{default,primary,full}.log, trx plus gate
  logs under build/nightly/YYYY-MM-DD-HHmmss/; the morning report lands at
  build/nightly/morning-YYYY-MM-DD.md. A red leg never blocks the
  later legs; only the exit code is red. -SkipSoak drops the §5 repeat loop
  that otherwise follows the legs. -SkipDefault, -SkipPrimary, and -SkipFenced
  drop their legs (morning triage re-drives Run A plus Run B with -SkipFenced
  -SkipSoak). -Force runs the Interactive leg outside
  the window for an explicitly accepted interruption. -CollectDebt <id>
  limits the Interactive leg to one night debt's trait filter (with
  -CheckOnly it dry-runs the resolution). Uses the repo-local SDK
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
  [switch]$CheckOnly,
  [string]$CollectDebt = ''
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SdkDir = Join-Path $Root '.tools\dotnet-win-x64'
$Dotnet = Join-Path $SdkDir 'dotnet.exe'
$GateExe = Join-Path $Root 'Bin\ForegroundLog\Debug\ForegroundLog.exe'
. (Join-Path $PSScriptRoot 'NightDebt.ps1')

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
  # Build-time HEAD, captured once after the up-front build: a commit
  # landing mid-run must not misattribute legs (the 04:13 task run's legs
  # read 7ec7495 then 2fd0ea4 while running one build).
  $head = $script:buildHead
  if ([string]::IsNullOrWhiteSpace($head)) {
    $head = 'unknown'
    try { $head = (git -C $Root rev-parse HEAD).Trim() } catch { }
  }
  Write-Output "nightly: scope=$Scope head=$head day=$(Get-Date -Format 'yyyy-MM-dd') leg=$(Split-Path -Leaf $Path)"
}

function Stop-LegLog {
  Stop-Transcript | Out-Null
}

function Invoke-OrphanReap([datetime]$OlderThan) {
  # Reap test apps/hosts under this checkout's Bin. Pre-flight passes the
  # run start so only true orphans (dead-run leftovers) die; a live
  # concurrent run's children are younger and survive. Post-kill passes
  # MaxValue: the mutex guarantees no other governed run, so everything
  # matching is the killed leg's tree. Write-Host, not Write-Output: the
  # caller captures this function's return (note lines for the report).
  $notes = @()
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='ScratchPad.exe' OR Name='testhost.exe'" -ErrorAction SilentlyContinue | Where-Object { ($_.ExecutablePath -like "$Root\Bin\*") -and ($_.CreationDate -lt $OlderThan) })) {
    $note = "$($p.Name) pid=$($p.ProcessId) started=$($p.CreationDate)"
    Write-Host "nightly: reaping orphan $note"
    $notes += $note
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
  return $notes
}

function Invoke-TimedStep([string]$Name, [int]$TimeoutSeconds, [string[]]$StepArgs, [string]$CodeFile) {
  # Bounded step for legs without a gate window (Interactive, soak): the
  # command runs in a job, killed at the cap so a hung drive cannot eat
  # the window and strand the report. Same sidecar discipline as
  # Invoke-GatedLeg (Receive-Job mixes output with the code, and a killed
  # job never emits its code). Returns Code plus Killed.
  if (Test-Path $CodeFile) { Remove-Item $CodeFile -Force }
  $stepJob = Start-Job -ScriptBlock {
    param($exe, $argList, $dir, $codeOut)
    Set-Location $dir
    & $exe @argList
    $LASTEXITCODE | Set-Content -Path $codeOut
  } -ArgumentList @($Dotnet, $StepArgs, $Root, $CodeFile)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $doneSignal = Wait-Job -Job $stepJob -Timeout $TimeoutSeconds
  $killed = ($null -eq $doneSignal)
  if ($killed -and ($stepJob.State -eq 'Running')) { Stop-Job -Job $stepJob }
  Receive-Job -Job $stepJob | Write-Host
  Remove-Job -Job $stepJob -Force
  $sw.Stop()
  $code = 1
  if (Test-Path $codeFile) { $code = [int](Get-Content $codeFile -Raw).Trim() }
  if ($killed) {
    $code = 1
    Write-Host "--- $Name killed at the $TimeoutSeconds s cap; reaping its tree ---"
    $script:reapNotes += @(Invoke-OrphanReap ([datetime]::MaxValue))
  }
  Write-Host "--- $Name exit: $code killed: $killed test-seconds: $([int]$sw.Elapsed.TotalSeconds) ---"
  return [pscustomobject]@{ Code = $code; Killed = $killed }
}

function Invoke-GatedLeg([string]$Name, [int]$GateSeconds, [string]$GateArgs, [string]$GateLog, [string]$VerdictFile, [string[]]$TestArgs) {
  # Gate and suite run together: the gate polls the whole window while the
  # tests drive. The suite must finish inside the window; overrun fails the
  # leg (partial proof is no proof). Both sides run in background jobs: the
  # gate job because the Start-Process object's ExitCode reads back empty in
  # Windows PowerShell 5.1 (measured 2026-09-20 with and without
  # redirection), while the job's $LASTEXITCODE reads back the true verdict;
  # the test job because the window is an enforced timeout, not a
  # stopwatch: a hung suite is killed at the bell so the later legs still
  # run (pre-fix the run hung until the task's 4-hour limit). The test
  # command arrives as an exe-plus-args array (a scriptblock would lose its
  # variables across the job boundary); its output lands in the transcript
  # at completion, not live. The job's exit code lands in a sidecar file:
  # Receive-Job returns output plus code as one flat array, and a killed
  # job never emits its code. Returns a result object, never throws for a
  # red leg (missing gate binary throws: that is a broken run, not a red
  # leg).
  if (-not (Test-Path $GateExe)) { throw "nightly: gate binary missing ($GateExe); build tools/ForegroundLog first" }
  $gateArgsArray = @("$GateSeconds", $GateLog)
  if ($GateArgs -ne '') { $gateArgsArray += $GateArgs }
  $job = Start-Job -ScriptBlock {
    param($exe, $argList, $verdict)
    & $exe @argList > $verdict
    $LASTEXITCODE
  } -ArgumentList @($GateExe, $gateArgsArray, $VerdictFile)
  $codeFile = "$VerdictFile.testcode"
  if (Test-Path $codeFile) { Remove-Item $codeFile -Force }
  $testJob = Start-Job -ScriptBlock {
    param($exe, $argList, $dir, $codeOut)
    Set-Location $dir
    & $exe @argList
    $LASTEXITCODE | Set-Content -Path $codeOut
  } -ArgumentList @($Dotnet, $TestArgs, $Root, $codeFile)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $doneSignal = Wait-Job -Job $testJob -Timeout $GateSeconds
  $killed = ($null -eq $doneSignal)
  if ($killed -and ($testJob.State -eq 'Running')) { Stop-Job -Job $testJob }
  Receive-Job -Job $testJob | Write-Host
  Remove-Job -Job $testJob -Force
  $sw.Stop()
  $testCode = 1
  if (Test-Path $codeFile) { $testCode = [int](Get-Content $codeFile -Raw).Trim() }
  if ($killed) {
    $testCode = 1
    Write-Host "--- $Name suite killed at the $GateSeconds s bell; reaping its tree ---"
    $script:reapNotes += @(Invoke-OrphanReap ([datetime]::MaxValue))
  }
  $gateCode = Receive-Job -Job $job -Wait -AutoRemoveJob
  $verdict = ''
  if (Test-Path $VerdictFile) { $verdict = (Get-Content $VerdictFile -Raw).Trim() }
  $overrun = $killed -or ($sw.Elapsed.TotalSeconds -gt $GateSeconds)
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

function Get-NonQuarantineSkips([string]$TrxPath) {
  # The Interactive bar excuses quarantine skips only (docs/testing.md):
  # any skip without a QUARANTINED stamp reds the leg. xUnit's exit code
  # stays zero under skips, so the trx is the enforcement point.
  $names = @()
  if (-not (Test-Path $TrxPath)) { return $names }
  $t = [xml](Get-Content $TrxPath -Raw)
  foreach ($r in @($t.TestRun.Results.UnitTestResult | Where-Object { $_.outcome -eq 'NotExecuted' })) {
    $msg = ''
    if ($r.Output -and $r.Output.ErrorInfo -and $r.Output.ErrorInfo.Message) { $msg = $r.Output.ErrorInfo.Message }
    if ($msg -notlike '*QUARANTINED*') { $names += $r.testName }
  }
  return $names
}

function Get-TranscriptSkips([string]$LogPath) {
  $names = @()
  if (-not (Test-Path $LogPath)) { return $names }
  foreach ($ln in (Get-Content $LogPath)) {
    $m = [regex]::Match($ln, '^\s*Skipped (\S+) \[')
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
  if ($null -ne $trx) { $skipLines += $trx.Skipped }
  $trxSkipNames = @($skipLines | ForEach-Object { ($_ -replace '^  - ([^:]+):.*$', '$1') })
  foreach ($n in (Get-TranscriptSkips $LogPath)) {
    if ($trxSkipNames -notcontains $n) { $skipLines += "  - $n : see transcript" }
  }
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

if ($CheckOnly -and ($CollectDebt -ne '')) {
  # Collector dry run (D00 T02 §10 item 4): resolve one debt id, quote
  # its filter, owed count, and the log path it would write. No dirs,
  # no tests, no side effects.
  $debts = @(Get-OpenNightDebts $Root)
  $debt = @($debts | Where-Object { $_.Id -eq $CollectDebt })
  if ($debt.Count -ne 1) { Write-Output "nightly: unknown debt id '$CollectDebt'"; exit 2 }
  $dryStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
  $dryFilter = Get-DebtDotnetFilter $debt[0].Filter
  Write-Output "nightly: collect-debt $($debt[0].Id) section $($debt[0].Section) filter $dryFilter owed $($debt[0].Count)"
  Write-Output "nightly: collect-debt log build/nightly/$dryStamp-full.log trx build/nightly/$dryStamp/interactive.trx"
  exit 0
}
if ($CheckOnly) { Write-Output 'nightly: environment OK'; exit 0 }

# Single-writer: the mutex serializes governed runs, so a manual backup
# never overlaps the scheduled fire (overlap used to mean mutual
# orphan-reaping). A stood-down invocation exits 0: nothing failed, the
# holder owns the proof. The OS releases the mutex at process exit; an
# abandoned hold from a dead run reads as acquired.
$runStart = Get-Date
$mutex = New-Object System.Threading.Mutex($false, 'Global\ScratchPadNightlyRun')
$lockHeld = $false
try { $lockHeld = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $lockHeld = $true }
if (-not $lockHeld) { Write-Output 'nightly: another governed run holds the lock; standing down (exit 0, nothing failed)'; exit 0 }

$day = Get-Date -Format 'yyyy-MM-dd'
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$nightDir = Join-Path $Root 'build\nightly'
New-Item -ItemType Directory -Path $nightDir -Force | Out-Null
# Invocation-scoped: every run owns its stamp directory plus its stamped
# transcripts, so a second same-day run never overwrites (or gets merged
# into) the first run's evidence. The morning report keeps its day-scoped
# name: the guard plus the operator check one fixed path.
$trxDir = Join-Path $nightDir $stamp
New-Item -ItemType Directory -Path $trxDir -Force | Out-Null
# Pre-flight: reap orphaned test apps from a dead run. Path-scoped to this
# checkout's Bin, so a released ScratchPad anywhere else is never touched;
# age-scoped to before this run's start, so a concurrent run's children
# survive. The 02:30 run's parent died mid-loop and left three holding Bin
# locks, which reds the build (MSB3027) until reaped; stale windows also
# contaminate window-enumerating tests, so the reap precedes every leg.
$reapNotes = @(Invoke-OrphanReap $runStart)
$failed = $false
$buildError = ''
$gateA = $null
$gateB = $null
$interactiveRan = $false
$interactiveKilled = $false
$interactiveLeaked = @()
$interactiveSkipReason = ''
# Collector snapshot (D00 T02 §10 items 4-6): open debts before the
# legs, so the report attributes per-debt entries against this run's
# start state, never a mid-run re-read. A failed query reds the run
# but the report still lands (report-always outranks attribution).
$debtSnapshot = @()
$debtQueryError = ''
try { $debtSnapshot = @(Get-OpenNightDebts $Root) } catch { $debtQueryError = "$_"; $failed = $true }
$collectFilter = 'Category=Interactive'
$collectId = ''
if ($CollectDebt -ne '') {
  $hit = @($debtSnapshot | Where-Object { $_.Id -eq $CollectDebt })
  if ($hit.Count -ne 1) { throw "nightly: unknown debt id '$CollectDebt'" }
  $collectId = $CollectDebt
  $collectFilter = Get-DebtDotnetFilter $hit[0].Filter
}
$interactiveScope = "tests/UI, $collectFilter, foreground"
if ($collectId -ne '') { $interactiveScope += ", debt $collectId" }

if ($Smoke) {
  $log = Join-Path $nightDir "$stamp-smoke.log"
  Start-LegLog $log 'tests/Smoke, launch smoke'
  try {
    Push-Location $Root
    try {
      $code = Invoke-Step 'smoke' { & $Dotnet test tests/Smoke/Smoke.csproj --nologo --logger "trx;LogFileName=smoke.trx" --results-directory $trxDir }
      if ($code -ne 0) { $failed = $true }
    } finally {
      Pop-Location
    }
  } finally {
    Stop-LegLog
  }
  if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
  Write-Output 'nightly: GREEN'
  exit 0
}

Push-Location $Root
try {
  # One build up front: every leg then runs --no-build, so a leg never
  # rebuilds mid-proof. ForegroundLog rides no solution; build it here.
  # A red build skips every leg but still writes the report: a scheduled
  # run with no fixed-path record reads as completed to the guard.
  try {
    $code = Invoke-Step 'build' { & $Dotnet build src/ScratchPad.slnx --nologo }
    if ($code -ne 0) { throw "solution build failed ($code)" }
    $code = Invoke-Step 'build-gate' { & $Dotnet build tools/ForegroundLog/ForegroundLog.csproj --nologo }
    if (($code -ne 0) -or (-not (Test-Path $GateExe))) { throw "gate build failed ($code)" }
  } catch {
    $buildError = "$_"
    $failed = $true
    Write-Output "nightly: $buildError; no leg runs on a broken build, report still lands"
    $SkipDefault = $true
    $SkipPrimary = $true
    $SkipFenced = $true
    $SkipSoak = $true
  }
  $script:buildHead = 'unknown'
  try { $script:buildHead = (git -C $Root rev-parse HEAD).Trim() } catch { }

  if (-not $SkipDefault) {
    $log = Join-Path $nightDir "$stamp-default.log"
    Start-LegLog $log 'full tree, Category!=Interactive, backgrounded'
    try {
      $trx = Join-Path $trxDir 'run-a.trx'
      $gateLog = Join-Path $trxDir 'gate-default.log'
      $verdictFile = Join-Path $trxDir 'gate-default.out'
      # -e is load-bearing: shell exports do not reach the app through
      # the test host (measured 2026-09-17); see docs/testing.md.
      $testArgsA = @('test', 'src/ScratchPad.slnx', '--no-build', '--nologo', '--filter', 'Category!=Interactive', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', 'trx;LogFileName=run-a.trx', '--results-directory', $trxDir)
      $r = Invoke-GatedLeg 'run-a' 1800 '' $gateLog $verdictFile $testArgsA
      $gateA = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if (-not $SkipPrimary) {
    $log = Join-Path $nightDir "$stamp-primary.log"
    Start-LegLog $log 'tests/UI, Category=Primary, backgrounded, expect-primary'
    try {
      $gateLog = Join-Path $trxDir 'gate-primary.log'
      $verdictFile = Join-Path $trxDir 'gate-primary.out'
      $testArgsB = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', 'Category=Primary', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', 'trx;LogFileName=run-b.trx', '--results-directory', $trxDir)
      $r = Invoke-GatedLeg 'run-b' 300 '--expect-primary' $gateLog $verdictFile $testArgsB
      $gateB = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if (-not $SkipFenced) {
    $log = Join-Path $nightDir "$stamp-full.log"
    if ($Force) {
      Start-LegLog $log ($interactiveScope + ', forced')
      try {
        $trx = Join-Path $trxDir 'interactive.trx'
        $stepArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', $collectFilter, '-e', 'SCRATCHPAD_INTERACTIVE_FORCE=1', '--logger', 'trx;LogFileName=interactive.trx', '--results-directory', $trxDir)
        $r = Invoke-TimedStep 'interactive' 1800 $stepArgs "$trx.testcode"
        $interactiveRan = $true
        $interactiveKilled = $r.Killed
        if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
        $leaked = @(Get-NonQuarantineSkips $trx)
        $interactiveLeaked = $leaked
        if ($leaked.Count -gt 0) { Write-Host "nightly: interactive non-quarantine skips: $($leaked -join ', ')"; $failed = $true }
      } finally {
        Stop-LegLog
      }
    } elseif (-not $inWindow) {
      Write-Output 'nightly: interactive leg skipped (outside the quiet-hours window); the bar fails the run (see docs/testing.md)'
      $interactiveSkipReason = 'outside the quiet-hours window'
      $failed = $true
    } elseif ($locked) {
      Write-Output 'nightly: interactive leg skipped (workstation locked; UI cannot be driven); the bar fails the run (see docs/testing.md)'
      $interactiveSkipReason = 'workstation locked'
      $failed = $true
    } else {
      Start-LegLog $log $interactiveScope
      try {
        $trx = Join-Path $trxDir 'interactive.trx'
        $stepArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', $collectFilter, '--logger', 'trx;LogFileName=interactive.trx', '--results-directory', $trxDir)
        $r = Invoke-TimedStep 'interactive' 1800 $stepArgs "$trx.testcode"
        $interactiveRan = $true
        $interactiveKilled = $r.Killed
        if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
        $leaked = @(Get-NonQuarantineSkips $trx)
        $interactiveLeaked = $leaked
        if ($leaked.Count -gt 0) { Write-Host "nightly: interactive non-quarantine skips: $($leaked -join ', ')"; $failed = $true }
      } finally {
        Stop-LegLog
      }
    }
  } else {
    $interactiveSkipReason = '-SkipFenced'
  }

  if (-not $SkipSoak) {
    for ($i = 1; $i -le 5; $i++) {
      $soakArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', 'Category!=Interactive', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=ui-soak-$i.trx", '--results-directory', $trxDir)
      $r = Invoke-TimedStep "soak-ui-$i" 1800 $soakArgs (Join-Path $trxDir "ui-soak-$i.testcode")
      if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
    }
    for ($i = 1; $i -le 5; $i++) {
      $soakArgs = @('test', 'tests/Protocol/Protocol.csproj', '--no-build', '--nologo', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=protocol-soak-$i.trx", '--results-directory', $trxDir)
      $r = Invoke-TimedStep "soak-protocol-$i" 1800 $soakArgs (Join-Path $trxDir "protocol-soak-$i.testcode")
      if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
    }
  }
} finally {
  Pop-Location
}

# Morning report (D00 T02 §9 item 3): per-leg counts plus failures with
# filing refs appended at triage. Always written, green or red.
$head = $script:buildHead
if ([string]::IsNullOrWhiteSpace($head)) {
  $head = 'unknown'
  try { $head = (git -C $Root rev-parse HEAD).Trim() } catch { }
}
$trigger = 'manual (see transcript head)'
try {
  $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
  $pname = (Get-CimInstance Win32_Process -Filter "ProcessId=$parent").Name
  if ($pname -eq 'taskeng.exe') { $trigger = 'cron \ScratchPad\Nightly UI (daily 02:30)' }
  elseif ($pname -eq 'svchost.exe') { $trigger = 'task \ScratchPad\Nightly UI (timer or demand; svchost.exe hosts the scheduler on Win8+, an interactive shell never parents to it)' }
  else { $trigger = "manual (parent $pname)" }
} catch { }
$sumA = Get-LegSummary (Join-Path $trxDir 'run-a.trx') (Join-Path $nightDir "$stamp-default.log")
$sumB = Get-LegSummary (Join-Path $trxDir 'run-b.trx') (Join-Path $nightDir "$stamp-primary.log")
$sumI = Get-LegSummary (Join-Path $trxDir 'interactive.trx') (Join-Path $nightDir "$stamp-full.log")
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
$buildLine = if ($buildError -eq '') { 'OK' } else { "FAILED: $buildError" }
$report += "- Build: $buildLine"
$report += "- Pre-flight reaped: $reapLine"
$report += ''
$report += '| Leg | Counts | Gate | Log |'
$report += '| --- | ------ | ---- | --- |'
$report += (Format-LegRow 'Run A (default)' $sumA $gateA "$stamp-default.log")
$report += (Format-LegRow 'Run B (primary)' $sumB $gateB "$stamp-primary.log")
$report += (Format-LegRow 'Interactive (collection)' $sumI $null "$stamp-full.log")
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
# Night-debt close-loop (D00 T02 §10 items 5-6): attribute the
# Interactive collection per open debt, append Night-collected on
# green, stage finding stubs on red. Triage commits the appends;
# runs never commit. A zero-executed collection never closes debt
# (vacuous proof); it reds as a collector bug.
$debtEntries = @()
$stagedStubs = @()
if ($debtQueryError -ne '') {
  $debtEntries += "- debt query failed: $debtQueryError (debts neither attributed nor closed)"
} else {
  foreach ($debt in $debtSnapshot) {
    $debtFilter = ''
    try { $debtFilter = Get-DebtDotnetFilter $debt.Filter } catch { $debtFilter = '' }
    $covered = $interactiveRan -and ($debtFilter -ne '') -and ($debtFilter -eq $collectFilter)
    if (-not $covered) {
      if ($interactiveSkipReason -ne '') { $cause = "interactive leg skipped ($interactiveSkipReason)" }
      else { $cause = "filter $debtFilter not covered this run (leg ran $collectFilter)" }
      $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: $cause"
      continue
    }
    if (($null -eq $sumI) -or $interactiveKilled) {
      $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: collector bug (leg killed or no summary)"
      $failed = $true
      continue
    }
    $executed = $sumI.Passed + $sumI.FailedCount
    if ($executed -le 0) {
      $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: collector bug (filter matched no tests)"
      $failed = $true
      continue
    }
    if (($sumI.FailedCount -gt 0) -or ($interactiveLeaked.Count -gt 0)) {
      $debtEntries += "- $($debt.Id) ($($debt.Section)): collection red ($($sumI.Passed)/$($sumI.FailedCount)/$($sumI.Skipped.Count)); findings staged below; debt stays open"
      continue
    }
    $logRel = "build/nightly/$stamp/interactive.trx"
    $line = Format-CollectedLine $day $debt.Id $sumI.Passed $sumI.FailedCount $sumI.Skipped.Count $logRel
    $note = Add-CollectedLine (Join-Path $Root $debt.File) $debt.Id $line
    Write-Output "nightly: night-debt $($debt.Id): $note"
    $debtEntries += "- $($debt.Id) ($($debt.Section)): collected $($sumI.Passed) passed, $($sumI.FailedCount) failed, $($sumI.Skipped.Count) skipped; log $logRel"
  }
}
if ($interactiveRan -and ($null -ne $sumI) -and ($sumI.FailedCount -gt 0)) {
  $stagedStubs = @(Format-FindingStubs $sumI.Failed $Root)
}
$report += '## Night debt'
$report += ''
if ($debtEntries.Count -eq 0) { $report += '(no open debt at run start)'; $report += '' }
else { $report += $debtEntries; $report += '' }
$report += '## Filings'
$report += ''
$report += '(triage appends one line per failure: test name, finding ref or quarantine row)'
$report += ''
if ($stagedStubs.Count -gt 0) {
  $report += '### Nightly collector (staged; triage files via add-todo)'
  $report += $stagedStubs
  $report += ''
}
$reportPath = Join-Path $nightDir "morning-$day.md"
$report -join "`r`n" | Set-Content -Path $reportPath -Encoding UTF8
Write-Output "nightly: report at $reportPath"

if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
Write-Output 'nightly: GREEN'
exit 0
