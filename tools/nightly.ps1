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
$JobCtl = Join-Path $Root 'Bin\JobControl\Debug\JobControl.exe'
. (Join-Path $PSScriptRoot 'NightDebt.ps1')
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
# Run A test projects (D00 T02 §15, D00-T02-S13-R2-F2): the leg runs one
# contained step per project (each keeps its own trx), and the summary
# plus conservation merge the same set. One list feeds both, so the
# steps and the merge cannot drift apart.
$runAProjects = @('Smoke', 'Unit', 'Protocol', 'UI')

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
  $snap = $script:snapshot
  if ([string]::IsNullOrWhiteSpace($snap)) { $snap = 'unknown (pre-build log)' }
  Write-Output "nightly: scope=$Scope head=$head day=$(Get-Date -Format 'yyyy-MM-dd') leg=$(Split-Path -Leaf $Path) snapshot=$snap"
}

function Stop-LegLog {
  Stop-Transcript | Out-Null
}

function Invoke-OrphanReap([datetime]$OlderThan) {
  # Transitional pre-flight reap (D00 T02 §15 PR21): test apps/hosts
  # under this checkout's Bin older than the run start die. Live-leg
  # kills moved to job objects (exact trees, no name matching); this
  # matcher survives only for pre-§15 leftovers, which age out after
  # one governed run. Write-Host, not Write-Output: the caller captures
  # this function's return (note lines for the report).
  $notes = @()
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='ScratchPad.exe' OR Name='testhost.exe'" -ErrorAction SilentlyContinue | Where-Object { ($_.ExecutablePath -like "$Root\Bin\*") -and ($_.CreationDate -lt $OlderThan) })) {
    $note = "$($p.Name) pid=$($p.ProcessId) started=$($p.CreationDate)"
    Write-Host "nightly: reaping orphan $note"
    $notes += $note
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
  return $notes
}

function Invoke-BootstrapStep([string]$Name, [int]$TimeoutSeconds, [string[]]$StepArgs, [string]$CodeFile) {
  # Bounded pre-containment step (D00 T02 §15 PR21): builds the
  # contained runner plus its siblings, so no JobControl exists yet.
  # Plain job plus bound; orphans on timeout are unobserved and age to
  # the next pre-flight. Returns Code plus Killed.
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

$script:legSeq = 0
function Invoke-ContainedSuite([string]$Name, [int]$CapSeconds, [string]$Exe, [string[]]$ExeArgs, [string]$OutLog, [string]$DumpDir, [int]$StubSecs, [string]$StubUnit) {
  # Out-of-process contained leg (D00 T02 §15 PR21/R3-F2): the suite runs
  # under JobControl inside a named job object, so kills reap exactly
  # the leg's tree, pre-kill dumps land per PID, and abandoned handles
  # still kill at close. The supervisor self-bounds at the cap; the PS
  # bound (cap plus kill slack) backstops a stuck supervisor with a
  # named kill (one syscall, no runspace involved) plus abandon-when-hung
  # teardown, so a wedged runspace strands no report. Returns Code,
  # Killed, Dumped. Never throws for a red or killed leg (a missing
  # JobControl binary throws: broken run, not a red leg).
  if (-not (Test-Path $JobCtl)) { throw "nightly: job-control binary missing ($JobCtl); build tools/JobControl first" }
  $script:legSeq++
  $jobName = "Global\ScratchPadLeg-$PID-$script:stamp-$Name-$script:legSeq"
  $runExe = $Exe
  $runArgs = $ExeArgs
  if ($StubSecs -gt 0) {
    $runExe = Join-Path $PSHOME 'powershell.exe'
    $runArgs = @('-NoProfile', '-Command', "Start-Sleep -Seconds $StubSecs")
    Write-Warning "nightly: STUBBED leg $Name (sleeps past its $StubUnit); not a governed proof"
  }
  if (Test-Path $OutLog) { Remove-Item $OutLog -Force }
  $sup = Start-Job -ScriptBlock {
    param($jc, $job, $out, $cap, $dump, $exe, $argList)
    & $jc 'run' '--job' $job '--out' $out '--timeout' "$cap" '--dump' $dump '--' $exe @argList 2>&1
  } -ArgumentList @($JobCtl, $jobName, $OutLog, $CapSeconds, $DumpDir, $runExe, $runArgs)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $doneSignal = Wait-Job -Job $sup -Timeout ($CapSeconds + $script:killSlack)
  $expired = ($null -eq $doneSignal)
  $jobLine = ''
  if (-not $expired) {
    try { $jobLine = @(Receive-Job -Job $sup) -join "`n" } catch { $jobLine = '' }
  }
  $m = [regex]::Match($jobLine, 'JOBCTL code=(\S+) timeout=(\d+) pid=(\d+) dumped=(\d+)')
  $killed = $expired
  $code = 1
  $dumped = 0
  if ($m.Success) {
    $dumped = [int]$m.Groups[4].Value
    if ($m.Groups[2].Value -eq '1') { $killed = $true }
    elseif ($m.Groups[1].Value -ne 'TIMEOUT') { $code = [int]$m.Groups[1].Value }
  } elseif (-not $expired) {
    throw "nightly: $Name leg runner failed (no JOBCTL line: $jobLine)"
  }
  if ($killed) {
    Write-Host "--- $Name killed at the $CapSeconds s cap; job kill is exact, dumped $dumped ---"
    try { & $JobCtl kill --job $jobName | Out-Null } catch { }
  }
  $null = Invoke-BoundedTeardown $sup 60 "$Name supervisor"
  $sw.Stop()
  if ($killed) { $code = 1 }
  Write-Host "--- $Name exit: $code killed: $killed dumped: $dumped test-seconds: $([int]$sw.Elapsed.TotalSeconds) ---"
  return [pscustomobject]@{ Code = $code; Killed = $killed; Dumped = $dumped }
}

function Invoke-TimedStep([string]$Name, [int]$TimeoutSeconds, [string[]]$StepArgs, [string]$OutLog, [string]$DumpDir, [switch]$NoStub) {
  # Bounded step for legs without a gate window (Interactive, soak):
  # contained suite (D00 T02 §15 PR21), killed exactly at the cap.
  # Stub legs (D00 T02 §14 PR4): SCRATCHPAD_STUB_LEGS replaces the suite
  # with a sleeper that always overruns. Simulation-only.
  $stubSecs = 0
  if ((-not $NoStub) -and (-not [string]::IsNullOrWhiteSpace($env:SCRATCHPAD_STUB_LEGS))) {
    $stubSecs = $TimeoutSeconds + 30
  }
  return Invoke-ContainedSuite $Name $TimeoutSeconds $Dotnet $StepArgs $OutLog $DumpDir $stubSecs 'cap'
}

function Invoke-GatedLeg([string]$Name, [int]$GateSeconds, [string]$GateArgs, [string]$GateLog, [string]$VerdictFile, [object[]]$SuiteSteps, [string]$DumpDir) {
  # Gate and suite run together: the gate polls the whole window while the
  # tests drive. The suite must finish inside the window; overrun fails the
  # leg (partial proof is no proof). The gate runs in a background job
  # because the Start-Process object's ExitCode reads back empty in
  # Windows PowerShell 5.1 (measured 2026-09-20 with and without
  # redirection), while the job's $LASTEXITCODE reads back the true
  # verdict; each suite step runs out of process under JobControl (D00 T02
  # §15 PR21), killed exactly at its cap with pre-kill dumps. Multi-step
  # legs (D00 T02 §15, D00-T02-S13-R2-F2) run one step per test project
  # under the same gate window, so each project keeps its own trx; every
  # step's kill cap is the REMAINING leg budget, a killed step ends the
  # loop (its cap was the remainder), and TestCode keeps the first
  # nonzero suite code. Stub legs (D00 T02 §14 PR4): every suite step
  # becomes a sleeper, the gate stays real (it watches an idle box and
  # exits clean at its bell). Each step carries Label, Args, OutLog.
  # Returns a result object, never throws for a red leg (a missing gate
  # or job-control binary throws: broken run, not a red leg).
  if (-not (Test-Path $GateExe)) { throw "nightly: gate binary missing ($GateExe); build tools/ForegroundLog first" }
  $gateArgsArray = @("$GateSeconds", $GateLog)
  if ($GateArgs -ne '') { $gateArgsArray += $GateArgs }
  $job = Start-Job -ScriptBlock {
    param($exe, $argList, $verdict)
    & $exe @argList > $verdict
    $LASTEXITCODE
  } -ArgumentList @($GateExe, $gateArgsArray, $VerdictFile)
  $stubSecs = 0
  if (-not [string]::IsNullOrWhiteSpace($env:SCRATCHPAD_STUB_LEGS)) {
    $stubSecs = $GateSeconds + 30
  }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $testCode = 0
  $killed = $false
  foreach ($step in $SuiteSteps) {
    $remaining = $GateSeconds - [int]$sw.Elapsed.TotalSeconds
    if ($remaining -le 0) {
      $killed = $true
      Write-Host "--- $Name-$($step.Label) stood down (leg budget exhausted: unproven) ---"
      break
    }
    $suite = Invoke-ContainedSuite "$Name-$($step.Label)" $remaining $Dotnet $step.Args $step.OutLog $DumpDir $stubSecs 'bell'
    if ($suite.Killed) { $killed = $true }
    if (($testCode -eq 0) -and ($suite.Code -ne 0)) { $testCode = $suite.Code }
    if ($suite.Killed) { break }
  }
  $sw.Stop()
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
  return [pscustomobject]@{ TestCode = $testCode; GateCode = $gateCode; Verdict = $verdict; Overrun = $overrun; Killed = $killed }
}

# Result parsing plus report formatting live in tools/NightlyParse.ps1
# (D00 T02 §15: shared with the parser fixture suite); dot-sourced below.

function Publish-NightlyReport([string[]]$Lines, [string]$ArchiveSuffix) {
  # Fixed path plus stamp-scoped archive plus latest pointer (D00 T02
  # §15 PR5): every publication lands all three atomically, so same-day
  # runs never overwrite each other's reports and triage resolves the
  # current stamp from latest.txt instead of globbing stamp dirs.
  Write-AtomicReport $Lines (Join-Path $script:nightDir "morning-$($script:day).md")
  Write-AtomicReport $Lines (Join-Path $script:nightDir "morning-$($script:stamp)$ArchiveSuffix.md")
  Write-AtomicReport @($script:stamp) (Join-Path $script:nightDir 'latest.txt')
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
# Monotonic run clock starts with the run itself (D00 T02 §14 PR18), so
# elapsed budgets never see time-sync or timezone jumps.
$runClock = [System.Diagnostics.Stopwatch]::StartNew()
$mutex = New-Object System.Threading.Mutex($false, 'Global\ScratchPadNightlyRun')
$lockHeld = $false
try { $lockHeld = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $lockHeld = $true }
if (-not $lockHeld) {
  # Explicit loser report (D00 T02 §15 PR20): the stand-down lands a
  # uniquely-named record instead of console-only silence, without
  # touching the holder's evidence (only the shared night dir, which
  # must exist anyway, plus the loser's own file). Same-second
  # sequential stamp reuse is unreachable (every invocation outlives
  # its second), so the mutex plus the unique loser name close the
  # overlap class.
  $loserStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
  $loserId = "$loserStamp-pid$PID"
  $loserDir = Join-Path $Root 'build\nightly'
  New-Item -ItemType Directory -Path $loserDir -Force | Out-Null
  $kindBits = @()
  if ($Force) { $kindBits += '-Force' }
  if ($SkipDefault) { $kindBits += '-SkipDefault' }
  if ($SkipPrimary) { $kindBits += '-SkipPrimary' }
  if ($SkipFenced) { $kindBits += '-SkipFenced' }
  if ($SkipSoak) { $kindBits += '-SkipSoak' }
  if ($Smoke) { $kindBits += '-Smoke' }
  if ($CollectDebt -ne '') { $kindBits += "-CollectDebt $CollectDebt" }
  $kind = if ($kindBits.Count -eq 0) { 'full (scheduled/manual shape)' } else { ($kindBits -join ' ') }
  Write-AtomicReport @("# Stood-down run: $loserId", 'Status: stood-down', '', "- At: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", "- Kind: $kind", '- Holder: another governed run holds Global\ScratchPadNightlyRun', '- Verdict: STOOD DOWN (not run; the holder owns the proof)') (Join-Path $loserDir "loser-$loserId.md")
  Write-Output 'nightly: another governed run holds the lock; standing down (exit 0, nothing failed)'
  exit 0
}

trap {
  # Cancellation record (D00 T02 §14 PR23): Ctrl+C, operator cancel, and
  # service shutdown land an atomic RED cancelled record instead of
  # silence, distinguishable from a crash by its Status line. The guard
  # only fires once the evidence dir exists; helper functions are
  # defined by then (they live above the leg block).
  if ((-not [string]::IsNullOrWhiteSpace($nightDir)) -and (-not [string]::IsNullOrWhiteSpace($day)) -and (Test-Path $nightDir)) {
    Write-AtomicReport @("# Morning report: $day", 'Status: cancelled', '', "- Cancelled: $($_.Exception.Message)", "- At: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", '- Verdict: RED (cancelled; partial evidence in the stamp dir, if any)') (Join-Path $nightDir "morning-$day.md")
    Write-Output 'nightly: RED (cancelled; record landed)'
  }
  if ($lockHeld -and ($null -ne $mutex)) { $mutex.ReleaseMutex() }
  exit 1
}

# Run-level deadline (D00 T02 §14): the catastrophe bound. Every leg
# starts only when its full cap fits inside the remaining budget, so the
# run lands its report before the scheduler kills it. Deadline is the
# earlier of the task PT4H limit and the resolved window end (in-window
# runs only: a manual daytime backup has no window boundary), minus a
# 300 s reserve for reaping plus the atomic report. The builds ride 600 s
# timed steps; only the smoke path runs outside the budget (a manual
# diagnostic, never proof). SCRATCHPAD_RUN_DEADLINE_SECONDS overrides
# the budget for simulation (the budget-exhaustion proof),
# SCRATCHPAD_LEG_CAP_SECONDS overrides every leg cap, and
# SCRATCHPAD_STUB_LEGS replaces suites with overrunning sleepers; all
# three are simulation-only and warn loudly whenever set. Elapsed
# budgets tick on the monotonic run clock; civil time serves only the
# window-end boundary plus display. Legs that never start are
# budget-cut (unproven, never green); §14 abort rules in docs/testing.md
# carry the deadline math.
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
if (-not [string]::IsNullOrWhiteSpace($env:SCRATCHPAD_STUB_LEGS)) { $simMode = $true }
if ($reserveBypassed) { Write-Output "nightly: run deadline $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) (simulation: reserve bypassed)" }
else { Write-Output "nightly: run deadline $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) (reserve ${deadlineReserve}s)" }
# Elapsed budgets tick on the monotonic run clock; civil time serves
# only the window-end boundary plus display (D00 T02 §14 PR18).
$budgetTotalSeconds = ($deadline - $runStart).TotalSeconds
function Test-LegBudget([int]$CapSeconds) {
  return (($budgetTotalSeconds - $runClock.Elapsed.TotalSeconds) -ge ($CapSeconds + $killSlack))
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
$captureNotes = @()
$failed = $false
# Suite-wide Primary guard (D00 T02 §15, D00-T02-S13-R3-F1): a Primary
# trait outside tests/UI runs in no governed leg, so the run reds
# before building with the strays named. Same shape as the red-build
# path: nothing runs, the report still lands.
$placement = Test-PrimaryPlacement (Join-Path $Root 'tests')
$placementError = ''
if (-not $placement.Ok) {
  $placementError = "Primary trait outside tests/UI: $($placement.Strays -join ', ')"
  $failed = $true
  $SkipDefault = $true
  $SkipPrimary = $true
  $SkipFenced = $true
  $SkipSoak = $true
  Write-Output "nightly: $placementError; no leg runs on a misplaced trait, report still lands"
}
$placementLine = if ($placementError -eq '') { "OK ($($placement.UiCount) Primary traits in tests/UI, none elsewhere)" } else { "VIOLATION: $placementError" }
$populationLine = 'not verified (check skipped)'
$buildError = ''
$gateA = $null
$gateB = $null
$interactiveRan = $false
$interactiveKilled = $false
$interactiveLeaked = @()
$interactiveSkipReason = ''
$nightOwedRows = @()
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
  $budgetAtStart = $budgetTotalSeconds - $runClock.Elapsed.TotalSeconds
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
    # nothing, so the builds ride a bounded bootstrap step (600 s against
    # ~10 s normal); the contained runner cannot build itself. A killed
    # build reds exactly like a red one: no leg runs, the report lands.
    $r = Invoke-BootstrapStep 'build' 600 @('build', 'src/ScratchPad.slnx', '--nologo') (Join-Path $trxDir 'build.testcode')
    if (($r.Code -ne 0) -or $r.Killed) { throw "solution build failed (code $($r.Code), killed $($r.Killed))" }
    $r = Invoke-BootstrapStep 'build-gate' 600 @('build', 'tools/ForegroundLog/ForegroundLog.csproj', '--nologo') (Join-Path $trxDir 'build-gate.testcode')
    if (($r.Code -ne 0) -or $r.Killed -or (-not (Test-Path $GateExe))) { throw "gate build failed (code $($r.Code), killed $($r.Killed))" }
    $r = Invoke-BootstrapStep 'build-jobcontrol' 600 @('build', 'tools/JobControl/JobControl.csproj', '--nologo') (Join-Path $trxDir 'build-jobcontrol.testcode')
    if (($r.Code -ne 0) -or $r.Killed -or (-not (Test-Path $JobCtl))) { throw "job-control build failed (code $($r.Code), killed $($r.Killed))" }
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
  # Build-once snapshot identity (D00 T02 §15 PR9): commit, dirty
  # state, binaries, config, and tool versions, captured once so every
  # leg header quotes the identical line.
  $dirtyState = 'clean'
  try { $dirtyCount = @((git -C $Root status --porcelain)).Count; if ($dirtyCount -gt 0) { $dirtyState = "dirty:$dirtyCount" } } catch { $dirtyState = 'unknown' }
  $sdkVersion = 'unknown'
  try { $sdkVersion = (& $Dotnet --version).Trim() } catch { }
  $script:snapshot = "HEAD $($script:buildHead) $dirtyState; config Debug; dotnet $sdkVersion; UI $(Get-ShortHash (Join-Path $Root 'Bin\UI\Debug\UI.dll')); Protocol $(Get-ShortHash (Join-Path $Root 'Bin\Protocol\Debug\Protocol.dll')); gate $(Get-ShortHash $GateExe); jobctl $(Get-ShortHash $JobCtl)"
  # Population fingerprint (D00 T02 §15, D00-T02-S13-PR13): the tree's
  # leg populations must match the accepted fingerprint, or prior
  # proofs stand stale. Discovery runs against the just-built UI
  # binaries. Same shape as the red-build path: nothing runs, the
  # report still lands with the drift named.
  if ($buildError -eq '') {
    try {
      $fpPath = Join-Path $Root 'tests\UI\TestPopulation.fingerprint'
      $fpRead = Read-TestPopulationFile $fpPath
      if (-not $fpRead.Ok) { throw $fpRead.Error }
      $disc = Get-UiTestDiscovery $Dotnet (Join-Path $Root 'tests\UI\UI.csproj') $fpRead.RunAFilter $fpRead.RunBFilter $fpRead.InteractiveFilter
      $pop = Compare-TestPopulation $fpPath (Join-Path $PSScriptRoot 'nightly.ps1') $disc
      if (-not $pop.Ok) { throw ("population drift: " + ($pop.Drifts -join '; ')) }
      $populationLine = "OK (run-a=$($disc.RunAMethods)/$($disc.RunACases) run-b=$($disc.RunBMethods)/$($disc.RunBCases) interactive=$($disc.InteractiveMethods)/$($disc.InteractiveCases))"
      Write-Output "nightly: population fingerprint matches ($populationLine)"
    } catch {
      $populationLine = "DRIFT: $_"
      $failed = $true
      $SkipDefault = $true
      $SkipPrimary = $true
      $SkipFenced = $true
      $SkipSoak = $true
      Write-Output "nightly: $populationLine; no leg runs on a drifted population, report still lands"
    }
  } else {
    $populationLine = 'not verified (build failed)'
  }

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
      $gateLog = Join-Path $trxDir 'gate-default.log'
      $verdictFile = Join-Path $trxDir 'gate-default.out'
      # One step per test project (D00 T02 §15, D00-T02-S13-R2-F2): a
      # single solution run shares one LogFileName across projects, so
      # each project overwrote the last one's trx. Per-project runs
      # keep per-project trx files under the same gate window.
      # -e is load-bearing: shell exports do not reach the app through
      # the test host (measured 2026-09-17); see docs/testing.md.
      $stepsA = @()
      foreach ($proj in $runAProjects) {
        $stepsA += [pscustomobject]@{ Label = $proj; Args = @('test', "tests/$proj/$proj.csproj", '--no-build', '--nologo', '--filter', 'Category!=Interactive&Category!=Primary', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=run-a-$proj.trx", '--results-directory', $trxDir); OutLog = (Join-Path $nightDir "$stamp-default-$proj.out.log") }
      }
      $r = Invoke-GatedLeg 'run-a' $capA '' $gateLog $verdictFile $stepsA (Join-Path $trxDir 'captures-run-a')
      $gateA = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
      if (($r.TestCode -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture 'run-a' (Join-Path $trxDir 'captures-run-a') $r.Killed) }
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
      $stepsB = @([pscustomobject]@{ Label = 'UI'; Args = $testArgsB; OutLog = ([System.IO.Path]::ChangeExtension($log, '.out.log')) })
      $r = Invoke-GatedLeg 'run-b' $capB '--expect-primary' $gateLog $verdictFile $stepsB (Join-Path $trxDir 'captures-run-b')
      $gateB = $r
      if (($r.TestCode -ne 0) -or ($r.GateCode -ne 0) -or $r.Overrun) { $failed = $true }
      if (($r.TestCode -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture 'run-b' (Join-Path $trxDir 'captures-run-b') $r.Killed) }
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
    # Cut-work handoff (D00 T02 §15, D00-T02-S14-PR10): every unexecuted
    # case becomes a staged Night-owed row for triage to file via
    # add-todo, so the cut never silently reduces coverage. Runs stage
    # text; triage files. Discovery failure re-owes the whole
    # collection filter instead of dropping the debt.
    try {
      $owed = Get-ListTestsCases $Dotnet (Join-Path $Root 'tests\UI\UI.csproj') $collectFilter 'cut-interactive'
      $nightOwedRows += "- $($owed.MethodCount) methods, $($owed.CaseCount) cases unexecuted (interactive budget-cut $stamp; collector runs each method filter)"
      foreach ($fq in $owed.Methods) { $nightOwedRows += "- Night-owed: $fq | collector filter: FullyQualifiedName=$fq" }
      Write-Output "nightly: interactive cut stages $($owed.MethodCount) Night-owed rows"
    } catch {
      $nightOwedRows += "- Night-owed: collection unverifiable ($_) | collector filter: $collectFilter (full collection re-owed)"
      Write-Output 'nightly: interactive cut discovery failed; full collection re-owed'
    }
  }
  if (-not $SkipFenced) {
    $log = Join-Path $nightDir "$stamp-full.log"
    if ($Force) {
      Start-LegLog $log ($interactiveScope + ', forced')
      try {
        $trx = Join-Path $trxDir 'interactive.trx'
        $stepArgs = @('test', 'tests/UI/UI.csproj', '--no-build', '--nologo', '--filter', $collectFilter, '-e', 'SCRATCHPAD_INTERACTIVE_FORCE=1', '--logger', 'trx;LogFileName=interactive.trx', '--results-directory', $trxDir)
        $r = Invoke-TimedStep 'interactive' $capI $stepArgs ([System.IO.Path]::ChangeExtension($log, '.out.log')) (Join-Path $trxDir 'captures-interactive')
        $interactiveRan = $true
        $interactiveKilled = $r.Killed
        if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
        if (($r.Code -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture 'interactive' (Join-Path $trxDir 'captures-interactive') $r.Killed) }
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
        $r = Invoke-TimedStep 'interactive' $capI $stepArgs ([System.IO.Path]::ChangeExtension($log, '.out.log')) (Join-Path $trxDir 'captures-interactive')
        $interactiveRan = $true
        $interactiveKilled = $r.Killed
        if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
        if (($r.Code -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture 'interactive' (Join-Path $trxDir 'captures-interactive') $r.Killed) }
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
  $runATrx = @()
  $runALogs = @((Join-Path $nightDir "$stamp-default.log"))
  foreach ($proj in $runAProjects) {
    $runATrx += (Join-Path $trxDir "run-a-$proj.trx")
    $runALogs += (Join-Path $nightDir "$stamp-default-$proj.out.log")
  }
  $sumA = Get-LegSummary $runATrx $runALogs
  $sumB = Get-LegSummary @((Join-Path $trxDir 'run-b.trx')) @((Join-Path $nightDir "$stamp-primary.log"))
  $sumI = Get-LegSummary @((Join-Path $trxDir 'interactive.trx')) @((Join-Path $nightDir "$stamp-full.log"))
  # Count conservation (D00 T02 §15 PR23): any break reds the run with
  # the numbers named; a silent new outcome class fails closed. The
  # expected-assembly set enforces only on completed legs (a null gate
  # covers skip plus cut; killed legs are already unproven).
  $conservationNotes = @()
  $completedA = ($null -ne $gateA) -and (-not $gateA.Killed)
  $completedB = ($null -ne $gateB) -and (-not $gateB.Killed)
  $completedI = $interactiveRan -and (-not $interactiveKilled)
  $conLegs = @(
    [pscustomobject]@{ Leg = 'Run A'; Trx = $runATrx; Logs = $runALogs; Enforce = $completedA },
    [pscustomobject]@{ Leg = 'Run B'; Trx = @((Join-Path $trxDir 'run-b.trx')); Logs = @((Join-Path $nightDir "$stamp-primary.log")); Enforce = $completedB },
    [pscustomobject]@{ Leg = 'Interactive'; Trx = @((Join-Path $trxDir 'interactive.trx')); Logs = @((Join-Path $nightDir "$stamp-full.log")); Enforce = $completedI }
  )
  foreach ($leg in $conLegs) {
    $con = Test-CountConservation $leg.Leg $leg.Trx $leg.Logs $leg.Enforce
    if (-not $con.Ok) {
      $failed = $true
      $conservationNotes += @($con.Breaks | ForEach-Object { "- Conservation RED: $_" })
    }
  }
  # Quarantine windows (D00 T02 §15 PR30): an overdue window auto-fails
  # the run with notification (this section, until §17 carries it).
  $quar = Test-QuarantineWindows (Join-Path $Root 'docs/soak-and-quarantine.md') (Get-Date)
  $quarantineNotes = @()
  if ($quar.Overdue.Count -gt 0) {
    $failed = $true
    foreach ($o in $quar.Overdue) {
      if ($o.Malformed) { $quarantineNotes += "- OVERDUE (malformed due '$($o.Due)'): $($o.Test) (owner $($o.Owner))" }
      else { $quarantineNotes += "- OVERDUE: $($o.Test) (due $($o.Due), owner $($o.Owner))" }
    }
  } else {
    $quarantineNotes += "- Windows current ($($quar.Open) open, earliest due $($quar.EarliestDue))"
  }
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
  $coreReport += "- Run identity: $stamp-pid$PID"
  $coreReport += "- Placement: $placementLine"
  $coreReport += "- Population: $populationLine"
  $coreReport += "- Core verdicts published before soak; the final report overwrites after soak (or budget-cut)"
  $coreReport += ''
  $coreReport += '| Leg | Counts | Gate | Infra | Log |'
  $coreReport += '| --- | ------ | ---- | ----- | --- |'
  $coreReport += (Format-LegRow 'Run A (default)' $sumA $gateA "$stamp-default.log" (Get-LegNote 'Run A (default)' $gateA $false))
  $coreReport += (Format-LegRow 'Run B (primary)' $sumB $gateB "$stamp-primary.log" (Get-LegNote 'Run B (primary)' $gateB $false))
  $coreReport += (Format-LegRow 'Interactive (collection)' $sumI $null "$stamp-full.log" (Get-LegNote 'Interactive (collection)' $null $interactiveKilled))
  if ($conservationNotes.Count -gt 0) { $coreReport += ''; $coreReport += $conservationNotes }
  $coreReport += ''
  $coreReport += '## Quarantine'
  $coreReport += ''
  $coreReport += $quarantineNotes
  Publish-NightlyReport $coreReport '-core'
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
      $r = Invoke-TimedStep "soak-ui-$i" $capSoak $soakArgs (Join-Path $trxDir "soak-ui-$i.out.log") (Join-Path $trxDir "captures-soak-ui-$i")
      if ($r.Killed) { $soakKilled += "ui-soak-$i" }
      if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
      if (($r.Code -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture "soak-ui-$i" (Join-Path $trxDir "captures-soak-ui-$i") $r.Killed) }
    }
    for ($i = 1; $i -le 5; $i++) {
      if (-not (Test-LegBudget $capSoak)) {
        $budgetCut += "protocol-soak-$i..5"
        $failed = $true
        Write-Output "nightly: soak protocol iterations $i..5 budget-cut (unproven)"
        break
      }
      $soakArgs = @('test', 'tests/Protocol/Protocol.csproj', '--no-build', '--nologo', '-e', 'SCRATCHPAD_BACKGROUND=1', '--logger', "trx;LogFileName=protocol-soak-$i.trx", '--results-directory', $trxDir)
      $r = Invoke-TimedStep "soak-protocol-$i" $capSoak $soakArgs (Join-Path $trxDir "soak-protocol-$i.out.log") (Join-Path $trxDir "captures-soak-protocol-$i")
      if ($r.Killed) { $soakKilled += "protocol-soak-$i" }
      if (($r.Code -ne 0) -or $r.Killed) { $failed = $true }
      if (($r.Code -ne 0) -or $r.Killed) { $captureNotes += @(Invoke-FailureCapture "soak-protocol-$i" (Join-Path $trxDir "captures-soak-protocol-$i") $r.Killed) }
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
  # The supervisor (D00 T02 §15 PR1) interposes one powershell level on
  # the scheduled path, so scheduler labels match the grandparent when
  # the parent is a plain shell; parent-first order keeps the direct
  # (unsupervised) readings identical.
  $gpname = ''
  if ($pname -eq 'powershell.exe') {
    $grandparent = (Get-CimInstance Win32_Process -Filter "ProcessId=$parent").ParentProcessId
    $gpname = (Get-CimInstance Win32_Process -Filter "ProcessId=$grandparent").Name
  }
  $sched = if (($pname -eq 'taskeng.exe') -or ($pname -eq 'svchost.exe')) { $pname } else { $gpname }
  if ($sched -eq 'taskeng.exe') { $trigger = 'cron \ScratchPad\Nightly UI (daily 02:30)' }
  elseif ($sched -eq 'svchost.exe') { $trigger = 'task \ScratchPad\Nightly UI (timer or demand; svchost.exe hosts the scheduler on Win8+, an interactive shell never parents to it)' }
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
$report += "- Run identity: $stamp-pid$PID"
$report += "- Trigger: $trigger"
$report += "- Window: 02:00-06:50 local (or SCRATCHPAD_INTERACTIVE_WINDOW)"
$reserveNote = if ($reserveBypassed) { 'simulation: reserve bypassed' } else { "reserve ${deadlineReserve}s" }
$report += "- Deadline: $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) ($reserveNote)"
$cutLine = if ($budgetCut.Count -eq 0) { 'none' } else { ($budgetCut -join '; ') }
$report += "- Budget-cut: $cutLine"
$reapLine = if ($reapNotes.Count -eq 0) { 'none' } else { ($reapNotes -join '; ') }
$buildLine = if ($buildError -eq '') { 'OK' } else { "FAILED: $buildError" }
$report += "- Build: $buildLine"
$report += "- Placement: $placementLine"
$report += "- Population: $populationLine"
$report += "- Pre-flight reaped: $reapLine"
$report += ''
$report += '| Leg | Counts | Gate | Infra | Log |'
$report += '| --- | ------ | ---- | ----- | --- |'
$report += (Format-LegRow 'Run A (default)' $sumA $gateA "$stamp-default.log" (Get-LegNote 'Run A (default)' $gateA $false))
$report += (Format-LegRow 'Run B (primary)' $sumB $gateB "$stamp-primary.log" (Get-LegNote 'Run B (primary)' $gateB $false))
$report += (Format-LegRow 'Interactive (collection)' $sumI $null "$stamp-full.log" (Get-LegNote 'Interactive (collection)' $null $interactiveKilled))
if ($conservationNotes.Count -gt 0) { $report += ''; $report += $conservationNotes }
$report += ''
$report += '## Quarantine'
$report += ''
$report += $quarantineNotes
$report += ''
$report += '## Enforcement'
$report += ''
$report += (Format-EnforcementVerdict $interactiveRan $interactiveLeaked)
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
$report += '## Captures'
$report += ''
if ($captureNotes.Count -eq 0) { $report += '(none: green night)' } else { $report += $captureNotes }
$report += ''
# Soak fourth phase (D00 T02 §15 PR7): the ledger gains a FAILED mark
# plus an aggregate verdict, so a red soak cannot hide behind green
# legs; the phase verdict fails the run like a leg. Suite output lands
# in per-iteration `.out.log` files; the trx files stay the count
# record.
$report += '## Soak'
$report += ''
$soakLedger = Format-SoakLedger $trxDir $soakKilled $budgetCut
if ($soakLedger.Failed) { $failed = $true }
$report += $soakLedger.Rows
$report += ''
$report += '## Incidents'
$report += ''
$incidentInputs = @()
foreach ($pair in @( @('Run A', $sumA), @('Run B', $sumB), @('Interactive', $sumI) )) {
  if (($null -ne $pair[1]) -and ($pair[1].FailedCount -gt 0)) {
    foreach ($fl in $pair[1].Failed) {
      $fm = [regex]::Match($fl, '^\s*-\s*([^:]+):\s*(.*)$')
      if ($fm.Success) { $incidentInputs += [pscustomobject]@{ Test = $fm.Groups[1].Value.Trim(); Message = $fm.Groups[2].Value.Trim(); Where = $pair[0] } }
    }
  }
}
$incidentInputs += @($soakLedger.Failures)
$incidentLines = @(Format-Incidents $incidentInputs)
if ($incidentLines.Count -eq 0) { $report += '(none)' } else { $report += $incidentLines }
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
if ($nightOwedRows.Count -gt 0) {
  $report += '### Night-owed (staged; triage files via add-todo)'
  $report += $nightOwedRows
  $report += ''
}
$reportPath = Join-Path $nightDir "morning-$day.md"
Publish-NightlyReport $report ''
Write-Output "nightly: report at $reportPath"

# A simulation run never exits 0 (D00 T02 §14 R2-F3): short deadlines
# prove the watchdog, never the suite, so no sim report reads as
# governed green proof however its legs land.
if ($simMode -and (-not $failed)) { Write-Output 'nightly: simulation run forced RED (not a governed proof)'; $failed = $true }
if ($failed) { Write-Output 'nightly: RED (see above)'; exit 1 }
Write-Output 'nightly: GREEN'
exit 0
