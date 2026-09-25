<# The owed tests' digest for a Night-owed line (D00 T02 §42 R1-F1).

Lists the UI tests the debt's filter selects under the forced-discovery
environment (the quiet-hours fence open and gated theories expanded, so
the listing matches any host at any hour) and prints the digest the
owed line records as `digest <hex>`:

  powershell -File tools/Get-DebtDigest.ps1 -Filter "Category=Interactive&FullyQualifiedName~Menu"

Prints `digest <hex> (<n> tests)`; exits 1 when the filter selects no
test (a digest over nothing proves nothing).
#>
param(
  [Parameter(Mandatory = $true)][string]$Filter,
  [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty in parameter defaults on Windows PowerShell 5.1.
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
. (Join-Path $PSScriptRoot 'NightDebt.ps1')
$dotnet = Join-Path $Root '.tools/dotnet-win-x64/dotnet.exe'
if (-not (Test-Path $dotnet)) { $dotnet = 'dotnet' }
# The owed line's filter as the collector expands it (R2-F2): a bare
# category (Interactive) reads Category=Interactive, so the digest covers
# the population the collection will run.
$dotnetFilter = Get-DebtDotnetFilter $Filter
$out = Invoke-WithForcedDiscovery { & $dotnet test (Join-Path $Root 'tests/UI/UI.csproj') --no-build --nologo --list-tests --filter $dotnetFilter 2>&1 | ForEach-Object { "$_" } }
$names = Get-ListedTestNames @($out)
if ($names.Count -eq 0) { Write-Output "no test matches $Filter"; exit 1 }
Write-Output "digest $(Get-TestNamesDigest $names) ($($names.Count) tests)"
exit 0
