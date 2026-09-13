#Requires -Version 5.1
<#
.SYNOPSIS
  Provision the pinned .NET SDK into repo-local .tools/ (gitignored).
.DESCRIPTION
  Reads the version from global.json (the single pin), downloads that exact
  build plus its published SHA512, verifies, and extracts. Re-running
  replaces .tools/dotnet with a fresh verified copy.
  Run from any directory: powershell -ExecutionPolicy Bypass -File tools\provision.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Rid = 'win-x64'

$Version = (Get-Content (Join-Path $Root 'global.json') -Raw | ConvertFrom-Json).sdk.version
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
  $Dest = Join-Path $Root '.tools\dotnet'
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
