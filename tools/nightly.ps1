#Requires -Version 5.1
<#
.SYNOPSIS
  Nightly governed regression run for ScratchPad (D00 T02 §9).
.DESCRIPTION
  Three legs inside the 02:00-06:50 window, owned by the \ScratchPad\Nightly UI
  scheduled task (daily 02:30 local). Run A: full solution default filter
  (Category!=Interactive&Category!=Primary; the Primary set rests on
  primary by design and rides Run B) with ForegroundLog census proof.
  Run B: Category=Primary with --expect-primary.
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
  -CheckOnly it dry-runs the resolution). A run-level deadline (D00 T02
  §14) gates every leg start: legs whose caps no longer fit are
  budget-cut (unproven, never green) and the report still lands; core
  verdicts publish before soak. SCRATCHPAD_RUN_DEADLINE_SECONDS plus
  SCRATCHPAD_LEG_CAP_SECONDS inject short deadlines for simulation
  only. Uses the repo-local SDK only. Procedure: docs/testing.md
  "Nightly regression run".
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

function Get-InteractiveWindowEnd {
  # Today's window end as a DateTime, from the same spec
  # Get-InInteractiveWindow resolves (D00 T02 §14 R5-F1). Returns $null
  # on a malformed spec; the deadline then falls back to the task limit.
  $spec = $env:SCRATCHPAD_INTERACTIVE_WINDOW
  if ([string]::IsNullOrWhiteSpace($spec)) { $spec = '02:00-06:50' }
  $m = [regex]::Match($spec, '^(\d{2}):(\d{2})-(\d{2}):(\d{2})$')
  if (-not $m.Success) { return $null }
  return (Get-Date -Hour ([int]$m.Groups[3].Value) -Minute ([int]$m.Groups[4].Value) -Second 0)
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
  if ($killed) {
    # Reap first: killing the test processes unblocks stuck job teardown
    # in the common case, and the reap notes land however teardown ends.
    Write-Host "--- $Name killed at the $TimeoutSeconds s cap; reaping its tree ---"
    $script:reapNotes += @(Invoke-OrphanReap ([datetime]::MaxValue))
  }
  # Bounded teardown (D00 T02 §14 R2-F2): a pathologically stuck job
  # object must not hang the run past its deadline. Wait out the stop
  # briefly, drain what the transport still offers (a killed job's
  # receive can throw PSSessionStateBroken, so it never throws), then
  # drop the object; the reap above already got the processes.
  $null = Wait-Job -Job $stepJob -Timeout 60
  try { Receive-Job -Job $stepJob | Write-Host } catch { Write-Host "--- $Name step-job receive failed after kill: $($_.Exception.Message) ---" }
  Remove-Job -Job $stepJob -Force
  $sw.Stop()
  $code = 1
  if (Test-Path $codeFile) { $code = [int](Get-Content $codeFile -Raw).Trim() }
  if ($killed) { $code = 1 }
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
  if ($killed) {
    # Reap first: same unblocking rationale as Invoke-TimedStep.
    Write-Host "--- $Name suite killed at the $GateSeconds s bell; reaping its tree ---"
    $script:reapNotes += @(Invoke-OrphanReap ([datetime]::MaxValue))
  }
  # Bounded teardown, same shape as Invoke-TimedStep (D00 T02 §14 R2-F2).
  $null = Wait-Job -Job $testJob -Timeout 60
  try { Receive-Job -Job $testJob | Write-Host } catch { Write-Host "--- $Name test-job receive failed after kill: $($_.Exception.Message) ---" }
  Remove-Job -Job $testJob -Force
  $sw.Stop()
  $testCode = 1
  if (Test-Path $codeFile) { $testCode = [int](Get-Content $codeFile -Raw).Trim() }
  if ($killed) { $testCode = 1 }
  # Bounded gate wait (D00 T02 §14 R2-F1, R3-F1): the gate legitimately
  # runs to its bell (the window IS the proof), so the wait lasts until
  # bell-plus-grace measured from GATE START, never a fresh cap from here:
  # a fresh cap would let one hung gate cost 2 x cap and strand the report.
  $gateHung = $false
  $gateTimeout = [int](($GateSeconds + 120) - ((Get-Date) - $job.PSBeginTime).TotalSeconds)
  $gateDone = $null
  if ($gateTimeout -gt 0) { $gateDone = Wait-Job -Job $job -Timeout $gateTimeout }
  # A slow teardown can exhaust the grace after a HEALTHY gate already
  # wrote its verdict (D00 T02 §14 R5-F2): only a still-running job at
  # grace expiry is hung; anything else receives normally, verdict kept.
  elseif ($job.State -ne 'Running') { $gateDone = $job }
  if ($null -eq $gateDone) {
    $gateHung = $true
    if ($job.State -eq 'Running') { Stop-Job -Job $job }
    try { Receive-Job -Job $job | Out-Null } catch { }
    Remove-Job -Job $job -Force
  } else {
    $gateCode = Receive-Job -Job $job -Wait -AutoRemoveJob
  }
  $verdict = ''
  if (Test-Path $VerdictFile) { $verdict = (Get-Content $VerdictFile -Raw).Trim() }
  if ($gateHung) { $gateCode = 1; $verdict = 'gate hung past its bell plus grace (unproven)' }
  $overrun = $killed -or ($sw.Elapsed.TotalSeconds -gt $GateSeconds)
  Write-Host "--- $Name gate exit: $gateCode verdict: $verdict overrun: $overrun test-seconds: $([int]$sw.Elapsed.TotalSeconds) ---"
  return [pscustomobject]@{ TestCode = $testCode; GateCode = $gateCode; Verdict = $verdict; Overrun = $overrun }
}

function Get-TrxSummary([string]$TrxPath) {
  if (-not (Test-Path $TrxPath)) { return $null }
  # A killed leg can leave truncated XML; a throw here would kill the
  # report under $ErrorActionPreference = 'Stop', so malformed trx reads
  # as absent (the transcript still carries the counts).
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return $null }
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
  # Same truncated-XML guard as Get-TrxSummary: malformed trx reads as
  # no skips (the transcript skip merge still reports the names).
  try { $t = [xml](Get-Content $TrxPath -Raw) } catch { return $names }
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

function Format-LegRow([string]$Leg, $Sum, $Gate, [string]$LogName, [string]$Note = '') {
  if ($null -eq $Sum) {
    $cell = if ($Note -ne '') { $Note } else { 'no trx (leg skipped or produced none)' }
    return "| $Leg | $cell | -- | $($LogName) |"
  }
  $skips = $Sum.Skipped.Count
  $gate = if ($null -eq $Gate) { 'n/a (owns the foreground)' } else { "exit $($Gate.GateCode) $($Gate.Verdict)" }
  $counts = "$($Sum.Passed) passed, $($Sum.FailedCount) failed, $skips skipped"
  if ($Sum.Assemblies) { $counts += " ($($Sum.Assemblies))" }
  if ($Note -ne '') { $counts += " ($Note)" }
  return "| $Leg | $counts | $gate | $($LogName) |"
}

function Write-AtomicReport([string[]]$Lines, [string]$Path) {
  # Same-volume rename is atomic on NTFS: a kill between the write and
  # the rename leaves the previous report, never a truncation.
  $tmp = "$Path.tmp"
  $Lines -join "`r`n" | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
}

function Get-LegNote([string]$Leg, $Gate, [bool]$Killed) {
  if ($script:budgetCut -contains $Leg) { return 'budget-cut (unproven)' }
  if ($Killed) { return 'killed at cap: unproven' }
  if (($null -ne $Gate) -and $Gate.Overrun) { return 'killed at cap: unproven' }
  return ''
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

# Run-level deadline (D00 T02 §14): the catastrophe bound. Every leg
# starts only when its full cap fits inside the remaining budget, so the
# run lands its report before the scheduler kills it. Deadline is the
# earlier of the task PT4H limit and the 06:50 window end (in-window runs
# only: a manual daytime backup has no window boundary), minus a 300 s
# reserve for reaping plus the atomic report. The build and the smoke
# path run outside the budget: nothing proves without a build, both fail
# fast, and neither can strand the report. SCRATCHPAD_RUN_DEADLINE_SECONDS
# overrides the budget for simulation (the all-hang proof) and
# SCRATCHPAD_LEG_CAP_SECONDS overrides every leg cap; both are
# simulation-only and warn loudly whenever set. Legs that never start
# are budget-cut (unproven, never green); §14 abort rules in
# docs/testing.md carry the deadline math.
$deadlineReserve = 300
# Kill slack: a killed leg costs its cap plus job-teardown latency
# (measured ~120 s per kill on the 2026-09-20 simulation: Stop-Job plus
# broken-transport teardown), so the budget gate holds 180 s per leg
# beyond the cap. Without it, teardown leaks past the deadline.
$killSlack = 180
$taskLimit = $runStart.AddHours(4)
# Window end follows the resolved window (D00 T02 §14 R5-F1), never a
# hardcoded 06:50: Force plus SCRATCHPAD_INTERACTIVE_WINDOW move the
# window, and a stale 06:50 would fail healthy daytime runs fast. An
# in-window run whose end already passed today sits in a
# crossing-midnight window, so the end rolls to tomorrow.
$windowEndToday = Get-InteractiveWindowEnd
$deadline = $taskLimit
if ($inWindow -and ($null -ne $windowEndToday)) {
  if ($windowEndToday -le $runStart) { $windowEndToday = $windowEndToday.AddDays(1) }
  if ($windowEndToday -lt $taskLimit) { $deadline = $windowEndToday }
}
$deadline = $deadline.AddSeconds(-$deadlineReserve)
$simDeadline = $env:SCRATCHPAD_RUN_DEADLINE_SECONDS
$simMode = $false
$reserveBypassed = $false
if (-not [string]::IsNullOrWhiteSpace($simDeadline)) {
  $deadline = $runStart.AddSeconds([int]$simDeadline)
  $simMode = $true
  $reserveBypassed = $true
  Write-Warning "nightly: SIMULATION run deadline ${simDeadline}s from start (ends $($deadline.ToString('HH:mm:ss'))); not a governed proof"
}
$simCap = $env:SCRATCHPAD_LEG_CAP_SECONDS
$capA = 1800; $capB = 300; $capI = 1800; $capSoak = 1800
if (-not [string]::IsNullOrWhiteSpace($simCap)) {
  $capA = $capB = $capI = $capSoak = [int]$simCap
  $simMode = $true
  Write-Warning "nightly: SIMULATION leg caps ${simCap}s; not a governed proof"
}
if ($reserveBypassed) { Write-Output "nightly: run deadline $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) (simulation: reserve bypassed)" }
else { Write-Output "nightly: run deadline $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) (reserve ${deadlineReserve}s)" }
function Test-LegBudget([int]$CapSeconds) {
  return (($deadline - (Get-Date)).TotalSeconds -ge ($CapSeconds + $killSlack))
}
$budgetCut = @()
$soakKilled = @()

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
  # Resolution failure skips the leg with the cause instead of
  # throwing: report-always outranks fail-fast on a real run (the
  # dry run still exits 2 above, where no report is owed).
  $hit = @($debtSnapshot | Where-Object { $_.Id -eq $CollectDebt })
  if ($hit.Count -ne 1) {
    $SkipFenced = $true
    $interactiveSkipReason = "unknown debt id '$CollectDebt'"
    $failed = $true
  } else {
    try { $collectFilter = Get-DebtDotnetFilter $hit[0].Filter; $collectId = $CollectDebt }
    catch {
      $SkipFenced = $true
      $interactiveSkipReason = "unresolvable filter for '$CollectDebt'"
      $failed = $true
    }
  }
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
  # Fail fast past the deadline (D00 T02 §14 R4-F2): a late in-window
  # start (or a recovered miss) can arrive with zero budget left; running
  # the builds anyway would land the report past the boundary for no
  # provable leg. Reuse the red-build path: nothing runs, the report
  # still lands. Threshold is zero, not the reserve: a small positive
  # remainder still fits the fast builds, and short-budget simulations
  # need their legs to exercise kills plus cuts.
  $budgetAtStart = ($deadline - (Get-Date)).TotalSeconds
  if ($budgetAtStart -le 0) {
    $buildError = 'run started past its deadline: nothing fits inside the remaining budget (unproven)'
    $failed = $true
    $SkipDefault = $true; $SkipPrimary = $true; $SkipFenced = $true; $SkipSoak = $true
    $budgetCut += 'entire run (deadline passed at start)'
    Write-Output 'nightly: deadline already passed at start; skipping builds and legs, landing the report'
  }
  try {
    if ($buildError -ne '') { throw $buildError }
    # Bounded builds (D00 T02 §14 R2-F1): a hung toolchain must strand
    # nothing, so the builds ride the same timed step as the legs (600 s
    # against ~10 s normal). A killed build reds exactly like a red one:
    # no leg runs, the report still lands.
    $r = Invoke-TimedStep 'build' 600 @('build', 'src/ScratchPad.slnx', '--nologo') (Join-Path $trxDir 'build.testcode')
    if (($r.Code -ne 0) -or $r.Killed) { throw "solution build failed (code $($r.Code), killed $($r.Killed))" }
    $r = Invoke-TimedStep 'build-gate' 600 @('build', 'tools/ForegroundLog/ForegroundLog.csproj', '--nologo') (Join-Path $trxDir 'build-gate.testcode')
    if (($r.Code -ne 0) -or $r.Killed -or (-not (Test-Path $GateExe))) { throw "gate build failed (code $($r.Code), killed $($r.Killed))" }
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

  if ((-not $SkipDefault) -and (-not (Test-LegBudget $capA))) {
    $SkipDefault = $true
    $budgetCut += 'Run A (default)'
    $failed = $true
    Write-Output 'nightly: Run A budget-cut (unproven): its cap no longer fits inside the run deadline'
  }
  if (-not $SkipDefault) {
    $log = Join-Path $nightDir "$stamp-default.log"
    Start-LegLog $log 'full tree, Category!=Interactive&Category!=Primary, backgrounded'
    try {
      $trx = Join-Path $trxDir 'run-a.trx'
      $gateLog = Join-Path $trxDir 'gate-default.log'
      $verdictFile = Join-Path $trxDir 'gate-default.out'
      # -e is load-bearing: shell exports do not reach the app through
      # the test host (measured 2026-09-17); see docs/testing.md.
      $testArgsA = @('test', 'src/ScratchPad.slnx', '--no-build', '--nologo', '--filter', 'Category!=Interactive&Category!=Primary', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', 'trx;LogFileName=run-a.trx', '--results-directory', $trxDir)
      $r = Invoke-GatedLeg 'run-a' $capA '' $gateLog $verdictFile $testArgsA
      $gateA = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if ((-not $SkipPrimary) -and (-not (Test-LegBudget $capB))) {
    $SkipPrimary = $true
    $budgetCut += 'Run B (primary)'
    $failed = $true
    Write-Output 'nightly: Run B budget-cut (unproven): its cap no longer fits inside the run deadline'
  }
  if (-not $SkipPrimary) {
    $log = Join-Path $nightDir "$stamp-primary.log"
    Start-LegLog $log 'tests/UI, Category=Primary, backgrounded, expect-primary'
    try {
      $gateLog = Join-Path $trxDir 'gate-primary.log'
      $verdictFile = Join-Path $trxDir 'gate-primary.out'
      $testArgsB = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', 'Category=Primary', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', 'trx;LogFileName=run-b.trx', '--results-directory', $trxDir)
      $r = Invoke-GatedLeg 'run-b' $capB '--expect-primary' $gateLog $verdictFile $testArgsB
      $gateB = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
    } finally {
      Stop-LegLog
    }
  }

  if ((-not $SkipFenced) -and (-not (Test-LegBudget $capI))) {
    $SkipFenced = $true
    $interactiveSkipReason = 'budget-cut (run deadline)'
    $budgetCut += 'Interactive (collection)'
    $failed = $true
    Write-Output 'nightly: Interactive budget-cut (unproven): its cap no longer fits inside the run deadline'
  }
  if (-not $SkipFenced) {
    $log = Join-Path $nightDir "$stamp-full.log"
    if ($Force) {
      Start-LegLog $log ($interactiveScope + ', forced')
      try {
        $trx = Join-Path $trxDir 'interactive.trx'
        $stepArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', $collectFilter, '-e', 'SCRATCHPAD_INTERACTIVE_FORCE=1', '--logger', 'trx;LogFileName=interactive.trx', '--results-directory', $trxDir)
        $r = Invoke-TimedStep 'interactive' $capI $stepArgs "$trx.testcode"
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
        $r = Invoke-TimedStep 'interactive' $capI $stepArgs "$trx.testcode"
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
    if ($interactiveSkipReason -eq '') { $interactiveSkipReason = '-SkipFenced' }
  }

  # Core verdicts publish before soak (D00 T02 §14 item 3): the three
  # regression legs land on the fixed report path now, so a long night
  # keeps its core proof even if soak eats the remaining budget.
  $sumA = Get-LegSummary (Join-Path $trxDir 'run-a.trx') (Join-Path $nightDir "$stamp-default.log")
  $sumB = Get-LegSummary (Join-Path $trxDir 'run-b.trx') (Join-Path $nightDir "$stamp-primary.log")
  $sumI = Get-LegSummary (Join-Path $trxDir 'interactive.trx') (Join-Path $nightDir "$stamp-full.log")
  $coreReport = @()
  $coreTitle = "# Morning report: $day (core verdicts, pre-soak)"
  if ($simMode) { $coreTitle += ' (SIMULATION: not a governed proof)' }
  $coreReport += $coreTitle
  # Machine-checkable publication marker (D00 T02 §14 R5-F4): the guard
  # plus triage distinguish the pre-soak core from the final report by
  # this Status line, never by presence alone.
  $coreReport += 'Status: pre-soak core verdicts (final report overwrites after soak)'
  $coreReport += ''
  $coreReport += "- HEAD: $script:buildHead"
  $coreReport += "- Core verdicts published before soak; the final report overwrites after soak (or budget-cut)"
  $coreReport += ''
  $coreReport += '| Leg | Counts | Gate | Log |'
  $coreReport += '| --- | ------ | ---- | --- |'
  $coreReport += (Format-LegRow 'Run A (default)' $sumA $gateA "$stamp-default.log" (Get-LegNote 'Run A (default)' $gateA $false))
  $coreReport += (Format-LegRow 'Run B (primary)' $sumB $gateB "$stamp-primary.log" (Get-LegNote 'Run B (primary)' $gateB $false))
  $coreReport += (Format-LegRow 'Interactive (collection)' $sumI $null "$stamp-full.log" (Get-LegNote 'Interactive (collection)' $null $interactiveKilled))
  Write-AtomicReport $coreReport (Join-Path $nightDir "morning-$day.md")
  Write-Output "nightly: core verdicts published before soak"
  if (-not $SkipSoak) {
    for ($i = 1; $i -le 5; $i++) {
      if (-not (Test-LegBudget $capSoak)) {
        $budgetCut += "ui-soak-$i..5"
        $failed = $true
        Write-Output "nightly: soak UI iterations $i..5 budget-cut (unproven)"
        break
      }
      $soakArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', 'Category!=Interactive', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=ui-soak-$i.trx", '--results-directory', $trxDir)
      $r = Invoke-TimedStep "soak-ui-$i" $capSoak $soakArgs (Join-Path $trxDir "ui-soak-$i.testcode")
      if ($r.Killed) { $soakKilled += "ui-soak-$i" }
      if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
    }
    for ($i = 1; $i -le 5; $i++) {
      if (-not (Test-LegBudget $capSoak)) {
        $budgetCut += "protocol-soak-$i..5"
        $failed = $true
        Write-Output "nightly: soak protocol iterations $i..5 budget-cut (unproven)"
        break
      }
      $soakArgs = @('test', 'tests/Protocol/Protocol.csproj', '--no-build', '--nologo', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=protocol-soak-$i.trx", '--results-directory', $trxDir)
      $r = Invoke-TimedStep "soak-protocol-$i" $capSoak $soakArgs (Join-Path $trxDir "protocol-soak-$i.testcode")
      if ($r.Killed) { $soakKilled += "protocol-soak-$i" }
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
# (Format-LegRow plus Get-LegNote live with the helpers above: the core
# publish calls them before the final report block runs.)
$report = @()
$reportTitle = "# Morning report: $day"
if ($simMode) { $reportTitle += ' (SIMULATION: not a governed proof)' }
$report += $reportTitle
$report += 'Status: final'
$report += ''
$report += "- HEAD: $head"
$report += "- Trigger: $trigger"
$report += "- Window: 02:00-06:50 local (or SCRATCHPAD_INTERACTIVE_WINDOW)"
$reserveNote = if ($reserveBypassed) { 'simulation: reserve bypassed' } else { "reserve ${deadlineReserve}s" }
$report += "- Deadline: $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) ($reserveNote)"
$cutLine = if ($budgetCut.Count -eq 0) { 'none' } else { ($budgetCut -join '; ') }
$report += "- Budget-cut: $cutLine"
$reapLine = if ($reapNotes.Count -eq 0) { 'none' } else { ($reapNotes -join '; ') }
$buildLine = if ($buildError -eq '') { 'OK' } else { "FAILED: $buildError" }
$report += "- Build: $buildLine"
$report += "- Pre-flight reaped: $reapLine"
$report += ''
$report += '| Leg | Counts | Gate | Log |'
$report += '| --- | ------ | ---- | --- |'
$report += (Format-LegRow 'Run A (default)' $sumA $gateA "$stamp-default.log" (Get-LegNote 'Run A (default)' $gateA $false))
$report += (Format-LegRow 'Run B (primary)' $sumB $gateB "$stamp-primary.log" (Get-LegNote 'Run B (primary)' $gateB $false))
$report += (Format-LegRow 'Interactive (collection)' $sumI $null "$stamp-full.log" (Get-LegNote 'Interactive (collection)' $null $interactiveKilled))
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
# Soak ledger (D00 T02 §14 item 3): per-iteration counts plus kills plus
# budget-cuts. Soak runs uncaptured (Invoke-TimedStep output lands on the
# console only), so the trx files are the record; §15 PR7 owns the full
# fourth-phase reporting this ledger anticipates.
$report += '## Soak'
$report += ''
$soakNames = @()
foreach ($i in 1..5) { $soakNames += "ui-soak-$i" }
foreach ($i in 1..5) { $soakNames += "protocol-soak-$i" }
$soakAny = $false
foreach ($n in $soakNames) {
  $st = Get-TrxSummary (Join-Path $trxDir "$n.trx")
  if ($null -eq $st) {
    if ($soakKilled -contains $n) { $soakAny = $true; $report += "- $n : no trx (killed at cap: unproven)" }
    continue
  }
  $soakAny = $true
  $tag = if ($soakKilled -contains $n) { 'killed at cap: unproven' } else { 'proved' }
  $report += "- $n : $($st.Passed) passed, $($st.FailedCount) failed, $($st.Skipped.Count) skipped ($tag)"
}
foreach ($cut in @($budgetCut | Where-Object { $_ -like '*soak-*' })) {
  $soakAny = $true
  $report += "- $cut : budget-cut (unproven)"
}
if (-not $soakAny) { $report += '(no soak iterations ran: -SkipSoak or budget-cut before the first)' }
$report += ''
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
    $coverage = Test-DebtCoverage $debtFilter $collectFilter $collectId
    $covered = $interactiveRan -and ($coverage -ne 'uncovered')
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
      $stageNote = if ($sumI.FailedCount -gt 0) { 'findings staged below' } else { 'non-quarantine skips, no failures' }
      $debtEntries += "- $($debt.Id) ($($debt.Section)): collection red ($($sumI.Passed)/$($sumI.FailedCount)/$($sumI.Skipped.Count)); $stageNote; debt stays open"
      continue
    }
    $logRel = "build/nightly/$stamp/interactive.trx"
    if ($coverage -eq 'superset') {
      $sub = Get-TrxSubsetCounts (Join-Path $trxDir 'interactive.trx') $debtFilter
      $decision = Test-SubsetClose $sub $debt.Count
      if ($decision -eq 'close') {
        $line = Format-CollectedLine $day $debt.Id $sub.Passed $sub.Failed $sub.Skipped $logRel
        $note = Add-CollectedLine (Join-Path $Root $debt.File) $debt.Id $line
        Write-Output "nightly: night-debt $($debt.Id): $note (subset)"
        $pair = Format-DebtGreenEntry $debt.Id $debt.Section $sub.Passed $sub.Failed $sub.Skipped $logRel $note
        $debtEntries += $pair[0]
        if ($pair[1]) { $failed = $true }
      } elseif ($decision -eq 'red') {
        $debtEntries += "- $($debt.Id) ($($debt.Section)): subset red ($($sub.Passed)/$($sub.Failed)/$($sub.Skipped)); findings staged; debt stays open"
      } elseif ($decision -eq 'skipped-stage') {
        $debtEntries += "- $($debt.Id) ($($debt.Section)): subset has $($sub.Skipped) skips without reasons; triage closes with attribution; log $logRel"
      } elseif ($decision -eq 'mismatch') {
        $got = $sub.Passed + $sub.Failed + $sub.Skipped
        $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: subset census mismatch (owed $($debt.Count), collected $got): debt stays open"
        $failed = $true
      } else {
        $debtEntries += "- $($debt.Id) ($($debt.Section)): covered by superset collection ($($sumI.Passed)/$($sumI.FailedCount)/$($sumI.Skipped.Count)); not FQN-attributable, triage appends Night-collected with subset counts; log $logRel"
      }
      continue
    }
    $split = Split-DebtSkips $sumI.Skipped
    if (($split.Capability -gt 0) -or ($split.Other -gt 0)) {
      $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: $($split.Capability) capability plus $($split.Other) other skips never executed: debt stays open"
      continue
    }
    $got = $sumI.Passed + $sumI.FailedCount + $split.Quarantine
    if (-not (Test-DebtCensus $debt.Count $sumI.Passed $sumI.FailedCount $split.Quarantine)) {
      $debtEntries += "- $($debt.Id) ($($debt.Section)): uncollected: census mismatch (owed $($debt.Count), collected $got): debt stays open"
      $failed = $true
      continue
    }
    $line = Format-CollectedLine $day $debt.Id $sumI.Passed $sumI.FailedCount $sumI.Skipped.Count $logRel
    $note = Add-CollectedLine (Join-Path $Root $debt.File) $debt.Id $line
    Write-Output "nightly: night-debt $($debt.Id): $note"
    $pair = Format-DebtGreenEntry $debt.Id $debt.Section $sumI.Passed $sumI.FailedCount $sumI.Skipped.Count $logRel $note
    $debtEntries += $pair[0]
    if ($pair[1]) { $failed = $true }
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
Write-AtomicReport $report $reportPath
Write-Output "nightly: report at $reportPath"

# A simulation run never exits 0 (D00 T02 §14 R2-F3): short deadlines
# prove the watchdog, never the suite, so no sim report reads as
# governed green proof however its legs land.
if ($simMode -and (-not $failed)) { Write-Output 'nightly: simulation run forced RED (not a governed proof)'; $failed = $true }
if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
Write-Output 'nightly: GREEN'
exit 0
