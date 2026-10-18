#Requires -Version 5.1
# Regenerate tests/UI/TestPopulation.fingerprint (D00 T02 §15,
# D00-T02-S13-PR13). Build first (discovery runs --list-tests against
# the built UI binaries). Membership regenerates from live discovery;
# filters stay as fingerprinted unless the file is missing or
# malformed, in which case they bootstrap to the documented legs
# (docs/testing.md: focus-free, Primary, Interactive). Changing a filter is a
# hand-edit to the fingerprint plus this regen: review the diff, since
# every membership change stales prior proofs until re-accepted here.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'TestBuild.ps1')
$Dotnet = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'
$Fingerprint = Join-Path $Root 'tests\UI\TestPopulation.fingerprint'

$existing = Read-TestPopulationFile $Fingerprint
if ($existing.Ok) {
  $runA = $existing.RunAFilter
  $runB = $existing.RunBFilter
  $interactive = $existing.InteractiveFilter
} else {
  Write-Output "fingerprint $($existing.Error); bootstrapping the documented filters"
  $runA = 'Category!=Interactive&Category!=Primary'
  $runB = 'Category=Primary'
  $interactive = 'Category=Interactive'
}
# A regen against a stale build would record an older tree's counts
# (D00 T02 §29): refuse with the build instruction instead.
$fresh = Get-UiBuildFreshness $Root
if (-not $fresh.Ok) { Write-Output "fingerprint not written: $($fresh.Error)"; exit 2 }
$disc = Get-UiTestDiscovery $Dotnet (Join-Path $Root 'tests\UI\UI.csproj') $runA $runB $interactive
Write-TestPopulationFile $Fingerprint $runA $runB $interactive $disc
Write-Output "fingerprint written: run-a=$($disc.RunAMethods)/$($disc.RunACases) run-b=$($disc.RunBMethods)/$($disc.RunBCases) interactive=$($disc.InteractiveMethods)/$($disc.InteractiveCases)"
