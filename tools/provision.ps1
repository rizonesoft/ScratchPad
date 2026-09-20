#Requires -Version 5.1
<#
.SYNOPSIS
  Self-healing workspace provisioner (D00 T02 §10 item 10).
.DESCRIPTION
  One idempotent command verifies plus repairs the scheduled tasks, git
  hooks, and CI workflows on Windows, and provisions the pinned .NET SDK.
  -Verify runs the verify half only (session-start surface: the
  process-plan audit step invokes it); exit 0 when every leg quotes
  green, exit 1 naming each fault. Without -Verify, repairs run first
  (hooks re-wire on unambiguous breakage only, tasks re-enable plus
  re-register when missing from tools/tasks/, SDK re-provision when its
  verify faults), then a final verify quotes the end state. CI
  workflows are verify-only: content intent lives in git, so drift
  reports as a fault, never auto-edits. Task field drift (a retuned
  trigger or action) likewise reports; only a missing task
  re-registers. A missing or modified hook file reports the exact
  restore instead of running it, and a hooks path pointing at an
  existing other dir is left alone: both may be deliberate user
  intent. Re-export the tools/tasks/ XMLs (UTF-16, matching the
  declaration) after any operator retuning of the live tasks.
  Run from any directory: powershell -ExecutionPolicy Bypass -File tools\provision.ps1 [-Verify]
#>
[CmdletBinding()]
param([switch]$Verify)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rid = 'win-x64'
$Tasks = @(
  @{ Name = 'Nightly UI'; Path = '\ScratchPad\'; Time = '02:30'; ArgMatch = 'nightly.ps1'; Xml = 'tools/tasks/nightly-ui.xml';
     Extra = @{ MultipleInstances = 'IgnoreNew'; ExecutionTimeLimit = 'PT4H'; WakeToRun = 'True' } },
  @{ Name = 'Nightly Foreground Single'; Path = '\ScratchPad\'; Time = '02:05'; ArgMatch = 'OpenInNewWindowModeOpensSecondWindow'; Xml = 'tools/tasks/nightly-foreground-single.xml';
     Extra = @{} }
)

function Test-OneTask($Spec) {
  $label = "task $($Spec.Path)$($Spec.Name)"
  $t = Get-ScheduledTask -TaskPath $Spec.Path -TaskName $Spec.Name -ErrorAction SilentlyContinue
  if ($null -eq $t) { return @{ Name = $label; Ok = $false; Detail = "missing (repair re-registers from $($Spec.Xml))" } }
  $tr = @($t.Triggers)[0]
  $tod = ''
  try { $tod = ([datetime]$tr.StartBoundary).ToString('HH:mm') } catch { }
  $faults = @()
  if ($t.State -eq 'Disabled') { $faults += 'disabled' }
  if ($tr.Enabled -ne $true) { $faults += 'trigger disabled' }
  if ($tod -ne $Spec.Time) { $faults += "trigger $tod, want $($Spec.Time)" }
  if ($tr.DaysInterval -ne 1) { $faults += 'not daily' }
  $act = @($t.Actions)[0]
  if ($act.Execute -ne 'powershell.exe') { $faults += "execute $($act.Execute)" }
  if ($act.Arguments -notlike ('*' + $Spec.ArgMatch + '*')) { $faults += 'action args drifted' }
  # Workdir compares against the exported definition, not this
  # checkout: the tasks serve the canonical checkout, so a second
  # clone verifies the definition, never its own path.
  $xmlWd = ''
  try {
    [xml]$x = Get-Content (Join-Path $Root $Spec.Xml) -Raw
    $xmlWd = (Select-Xml -Xml $x -Namespace @{ t = 'http://schemas.microsoft.com/windows/2004/02/mit/task' } -XPath '//t:Exec/t:WorkingDirectory').Node.'#text'
  } catch { }
  if ($xmlWd -eq '') { $faults += 'definition has no workdir' }
  elseif ($act.WorkingDirectory -ne $xmlWd) { $faults += "workdir $($act.WorkingDirectory)" }
  if ($t.Principal.UserId -ne $env:USERNAME) { $faults += "run-as $($t.Principal.UserId)" }
  if ("$($t.Principal.LogonType)" -ne 'Interactive') { $faults += "logon $($t.Principal.LogonType)" }
  foreach ($k in $Spec.Extra.Keys) {
    if ("$($t.Settings.psobject.Properties[$k].Value)" -ne "$($Spec.Extra[$k])") {
      $faults += "$k $($t.Settings.psobject.Properties[$k].Value)"
    }
  }
  if ($faults.Count -eq 0) { return @{ Name = $label; Ok = $true; Detail = "ready $($Spec.Time) daily $($Spec.ArgMatch)" } }
  return @{ Name = $label; Ok = $false; Detail = ($faults -join '; ') }
}

function Repair-OneTask($Spec) {
  $t = Get-ScheduledTask -TaskPath $Spec.Path -TaskName $Spec.Name -ErrorAction SilentlyContinue
  if ($null -eq $t) {
    try {
      $xml = Get-Content (Join-Path $Root $Spec.Xml) -Raw
      Register-ScheduledTask -TaskPath $Spec.Path -TaskName $Spec.Name -Xml $xml -Force | Out-Null
      return "re-registered from $($Spec.Xml)"
    } catch { return "re-register failed: $_" }
  }
  if ($t.State -eq 'Disabled') {
    try { Enable-ScheduledTask -TaskPath $Spec.Path -TaskName $Spec.Name | Out-Null; return 're-enabled' }
    catch { return "re-enable failed: $_" }
  }
  return 'nothing to repair (drift reports as fault)'
}

function Test-HooksLeg {
  $res = @()
  $cfg = ''
  try { $cfg = ((& git -C $Root config core.hooksPath 2>$null) -join "`n").Trim() } catch { }
  if ($cfg -eq 'tools/githooks') { $res += @{ Name = 'hooks path'; Ok = $true; Detail = 'tools/githooks' } }
  else { $res += @{ Name = 'hooks path'; Ok = $false; Detail = "wired to '$cfg'" } }
  if (Test-Path (Join-Path $Root 'tools/githooks/pre-commit')) {
    $res += @{ Name = 'hooks pre-commit'; Ok = $true; Detail = 'present' }
  } else {
    $res += @{ Name = 'hooks pre-commit'; Ok = $false; Detail = 'missing' }
  }
  return $res
}

function Repair-HooksLeg {
  # Split repair (R2-F1): re-wire only unambiguous breakage, and a
  # missing file reports the exact restore instead of running it --
  # a deletion may be deliberate user intent, and no repair
  # overwrites user-owned state without an explicit invocation
  # asking for that exact cleanup.
  $notes = @()
  $cfg = ''
  try { $cfg = ((& git -C $Root config core.hooksPath 2>$null) -join "`n").Trim() } catch { }
  $cfgTarget = if ($cfg -eq '') { '' } elseif ([IO.Path]::IsPathRooted($cfg)) { $cfg } else { Join-Path $Root $cfg }
  if (($cfg -eq '') -or (-not (Test-Path $cfgTarget))) {
    & git -C $Root config core.hooksPath 'tools/githooks'
    if ($LASTEXITCODE -eq 0) { $notes += 'hooks path re-wired' } else { $notes += "hooks path re-wire failed ($LASTEXITCODE)" }
  } else {
    $notes += "hooks path points at existing '$cfg': left alone (verify still faults)"
  }
  $pre = Join-Path $Root 'tools/githooks/pre-commit'
  if (-not (Test-Path $pre)) {
    $notes += "pre-commit missing: restore with git -C $Root checkout -- tools/githooks/pre-commit"
  } else {
    $dirty = ((& git -C $Root status --porcelain -- 'tools/githooks/pre-commit') -join "`n").Trim()
    if ($dirty -ne '') { $notes += 'pre-commit modified in worktree: left alone' }
  }
  return $notes
}

function Test-WorkflowsLeg {
  $res = @()
  foreach ($wf in @('build.yml', 'plan.yml', 'soak.yml')) {
    $p = Join-Path $Root ".github/workflows/$wf"
    if (-not (Test-Path $p)) { $res += @{ Name = "workflow $wf"; Ok = $false; Detail = 'missing' }; continue }
    $linux = Select-String -Path $p -Pattern '^\s*runs-on:\s*.*ubuntu' -CaseSensitive:$false
    if ($linux) { $res += @{ Name = "workflow $wf"; Ok = $false; Detail = 'linux runner (Windows-only repo)' }; continue }
    $res += @{ Name = "workflow $wf"; Ok = $true; Detail = 'present, no linux runner' }
  }
  $plan = Join-Path $Root '.github/workflows/plan.yml'
  if ((Test-Path $plan) -and -not (Select-String -Path $plan -Pattern 'plan-gates' -Quiet)) {
    $res += @{ Name = 'workflow plan-gates'; Ok = $false; Detail = 'plan-gates job absent from plan.yml' }
  } else {
    $res += @{ Name = 'workflow plan-gates'; Ok = $true; Detail = 'present' }
  }
  return $res
}

function Get-PinnedSdkVersion {
  return (Get-Content (Join-Path $Root 'global.json') -Raw | ConvertFrom-Json).sdk.version
}

function Test-SdkLeg {
  $Version = Get-PinnedSdkVersion
  if (-not $Version) { return @(@{ Name = 'sdk'; Ok = $false; Detail = 'no sdk.version in global.json' }) }
  $exe = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'
  if (-not (Test-Path $exe)) { return @(@{ Name = 'sdk'; Ok = $false; Detail = 'not provisioned' }) }
  $sdks = & $exe --list-sdks 2>$null
  if ($sdks -match ('^' + [regex]::Escape($Version) + ' ')) {
    return @(@{ Name = 'sdk'; Ok = $true; Detail = "$Version ready" })
  }
  return @(@{ Name = 'sdk'; Ok = $false; Detail = 'installed SDK is not ' + $Version }) 
}

function Install-Sdk {
  $Version = Get-PinnedSdkVersion
  if (-not $Version) { throw "provision.ps1: no sdk.version in $Root\global.json" }
  $Base = "https://builds.dotnet.microsoft.com/dotnet/Sdk/$Version/dotnet-sdk-$Version-$Rid"
  $Work = Join-Path ([IO.Path]::GetTempPath()) ('notepad-sdk-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $Work | Out-Null
  try {
    $Zip = Join-Path $Work 'sdk.zip'
    $Sidecar = Join-Path $Work 'sdk.sha512'
    Invoke-WebRequest -Uri "$Base.zip" -OutFile $Zip
    Invoke-WebRequest -Uri "$Base.zip.sha512" -OutFile $Sidecar
    $Expected = ((Get-Content $Sidecar -Raw) -split '\s+')[0].ToUpperInvariant()
    $Actual = (Get-FileHash -Path $Zip -Algorithm SHA512).Hash
    if ($Actual -ne $Expected) { throw "provision.ps1: SHA512 mismatch for $Base.zip" }
    $Dest = Join-Path $Root ".tools\dotnet-$Rid"
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    New-Item -ItemType Directory -Path $Dest | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $Dest
    $env:DOTNET_ROOT = $Dest
    $env:DOTNET_MULTILEVEL_LOOKUP = '0'
    $env:PATH = "$Dest;$env:PATH"
    Push-Location $Root
    try {
      & dotnet --info
      $Sdks = & dotnet --list-sdks
    } finally { Pop-Location }
    if (-not ($Sdks -match ('^' + [regex]::Escape($Version) + ' '))) { throw "provision.ps1: installed SDK is not $Version" }
    Write-Output "provision.ps1: .NET SDK $Version ready in $Dest"
  } finally {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
  }
}

function Test-All {
  $res = @()
  # Scheduled tasks are dev-box-only (dev SID plus dev workdir baked
  # into the definitions): ephemeral CI runners can never satisfy
  # them, so a cache-miss provision failed deterministically there.
  # GitHub sets CI=true on every runner; skip the legs (verify and
  # repair alike) instead of failing what cannot pass.
  if ($env:CI -ne 'true') {
    foreach ($spec in $Tasks) { $res += Test-OneTask $spec }
  } else {
    Write-Host 'provision: tasks skipped on CI (dev-box only)'
  }
  $res += Test-HooksLeg
  $res += Test-WorkflowsLeg
  $res += Test-SdkLeg
  return $res
}

function Show-Verify($Results) {
  # Write-Host, not Write-Output: callers capture this function's
  # return, which would swallow Write-Output into $green.
  foreach ($r in $Results) {
    $verdict = if ($r.Ok) { 'OK' } else { 'FAULT' }
    Write-Host "provision: verify $($r.Name): $verdict ($($r.Detail))"
  }
  $ok = @($Results | Where-Object { $_.Ok }).Count
  Write-Host "provision: verify $ok/$($Results.Count) green"
  return ($ok -eq $Results.Count)
}

$results = @(Test-All)
if ($Verify) {
  $green = Show-Verify $results
  if ($green) { exit 0 } else { exit 1 }
}
if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) {
  $hookNotes = try { Repair-HooksLeg } catch { @("repair crashed: $_") }
  foreach ($n in $hookNotes) { Write-Output "provision: repair hooks: $n" }
  if ($env:CI -ne 'true') {
    foreach ($spec in $Tasks) {
      $tnote = try { Repair-OneTask $spec } catch { "repair crashed: $_" }
      Write-Output "provision: repair task $($spec.Name): $tnote"
    }
  }
  Write-Output 'provision: repair workflows: verify-only, nothing repaired'
  if (@($results | Where-Object { (-not $_.Ok) -and ($_.Name -eq 'sdk') }).Count -gt 0) { Install-Sdk }
  $results = @(Test-All)
}
$green = Show-Verify $results
if ($green) { exit 0 } else { exit 1 }
