#Requires -Version 5.1
# Population fingerprint gate before the night (D00 T02 section 29).
# Runs the governed nightly's own pures (Read-TestPopulationFile,
# Get-UiTestDiscovery, Compare-TestPopulation) against the built UI
# binaries, so a commit that leaves tests/UI/TestPopulation.fingerprint
# stale goes red here (locally or in CI) instead of costing a night.
# Build first. Exit 0 prints the OK line; exit 1 prints each drift line;
# exit 2 means the fingerprint or the build could not be read.
param([string]$Fingerprint = '')
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$Dotnet = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'
if ($Fingerprint -eq '') { $Fingerprint = Join-Path $Root 'tests\UI\TestPopulation.fingerprint' }
$fresh = Get-UiBuildFreshness $Root
if (-not $fresh.Ok) { Write-Output "population UNCHECKED: $($fresh.Error)"; exit 2 }
$fp = Read-TestPopulationFile $Fingerprint
if (-not $fp.Ok) { Write-Output "population UNREADABLE: $($fp.Error)"; exit 2 }
$disc = Get-UiTestDiscovery $Dotnet (Join-Path $Root 'tests\UI\UI.csproj') $fp.RunAFilter $fp.RunBFilter $fp.InteractiveFilter
$pop = Compare-TestPopulation $Fingerprint (Join-Path $PSScriptRoot 'nightly.ps1') $disc
if ($pop.Ok) {
  Write-Output "population OK run-a=$($disc.RunAMethods)/$($disc.RunACases) run-b=$($disc.RunBMethods)/$($disc.RunBCases) interactive=$($disc.InteractiveMethods)/$($disc.InteractiveCases)"
  exit 0
}
Write-Output ("population DRIFT: population drift: " + ($pop.Drifts -join '; '))
Write-Output 'Regenerate after a fresh build with tools/Update-TestFingerprint.ps1 and review the diff.'
exit 1
