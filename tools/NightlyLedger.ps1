#Requires -Version 5.1
# Incident ledger maintenance (D00 T02 section 30 item 4). The governed
# nightly reds when build/nightly/incidents.json is missing while
# earlier results carry incidents; -Rebuild replays every result file
# (build/nightly/morning-*.result.json and retained/*/result.json)
# stamped under identity contract v2 through the same lifecycle the
# nightly runs, restoring each incident with its occurrences, owner,
# and finding link. Pass streaks are not stored in results, so
# recovery counting restarts from zero. Refuses to overwrite an
# existing ledger unless -Force is given.
param(
  [switch]$Rebuild,
  [switch]$Force,
  [string]$WorkspaceRoot = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ($WorkspaceRoot -ne '') { $Root = (Resolve-Path $WorkspaceRoot).Path }
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$nightDir = Join-Path $Root 'build\nightly'
$ledgerPath = Join-Path $nightDir 'incidents.json'
if (-not $Rebuild) { Write-Output 'usage: NightlyLedger.ps1 -Rebuild [-Force] [-WorkspaceRoot <dir>]'; exit 2 }
if ((Test-Path $ledgerPath) -and (-not $Force)) { Write-Output "ledger: $ledgerPath exists; pass -Force to replace it"; exit 1 }
$files = @(Get-ChildItem $nightDir -Filter 'morning-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$files += @(Get-ChildItem (Join-Path $nightDir 'retained') -Filter 'result.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
try {
  $map = New-IncidentLedgerFromResults $files $script:IncidentContractV2Since (Get-QuarantineOwners (Join-Path $Root 'docs/soak-and-quarantine.md')) (Read-IncidentLinks (Join-Path $Root 'docs/incident-links.md'))
} catch {
  Write-Output "ledger: $($_.Exception.Message)"
  exit 1
}
$err = Write-IncidentLedger $map $ledgerPath
if ($err -ne '') { Write-Output "ledger: rebuild FAILED: $err"; exit 1 }
Write-Output "ledger: rebuilt $($map.Count) incident(s) from $($files.Count) result file(s) into $ledgerPath"
exit 0
