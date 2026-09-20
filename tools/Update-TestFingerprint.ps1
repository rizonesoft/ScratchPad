#Requires -Version 5.1
# Regenerate tests/UI/TestPopulation.fingerprint (D00 T02 §15,
# D00-T02-S13-PR13). Build first (discovery runs --list-tests against
# the built UI binaries). Membership regenerates from live discovery;
# filters stay as fingerprinted unless the file is missing or
# malformed, in which case they bootstrap from nightly.ps1 by shape
# (the &-conjunction is Run A, Category=Primary is Run B, the
# $collectFilter default is Interactive). Changing a filter is a
# hand-edit to the fingerprint plus this regen: review the diff, since
# every membership change stales prior proofs until re-accepted here.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$Dotnet = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'
$Fingerprint = Join-Path $Root 'tests\UI\TestPopulation.fingerprint'
$Nightly = Join-Path $PSScriptRoot 'nightly.ps1'

$existing = Read-TestPopulationFile $Fingerprint
if ($existing.Ok) {
  $runA = $existing.RunAFilter
  $runB = $existing.RunBFilter
  $interactive = $existing.InteractiveFilter
} else {
  Write-Output "fingerprint $($existing.Error); bootstrapping filters from nightly.ps1"
  $live = Get-NightlyFilterLiterals $Nightly
  $conj = @($live.Literals | Where-Object { $_ -like '*&*' })
  if ($conj.Count -ne 1) { throw "cannot bootstrap run-a filter ($($conj.Count) &-conjunctions)" }
  if (@($live.Literals | Where-Object { $_ -eq 'Category=Primary' }).Count -lt 1) { throw 'cannot bootstrap run-b filter (Category=Primary absent)' }
  if ($live.CollectDefault -eq '') { throw 'cannot bootstrap interactive filter ($collectFilter default absent)' }
  $runA = $conj[0]
  $runB = 'Category=Primary'
  $interactive = $live.CollectDefault
}
$disc = Get-UiTestDiscovery $Dotnet (Join-Path $Root 'tests\UI\UI.csproj') $runA $runB $interactive
Write-TestPopulationFile $Fingerprint $runA $runB $interactive $disc
Write-Output "fingerprint written: run-a=$($disc.RunAMethods)/$($disc.RunACases) run-b=$($disc.RunBMethods)/$($disc.RunBCases) interactive=$($disc.InteractiveMethods)/$($disc.InteractiveCases)"
