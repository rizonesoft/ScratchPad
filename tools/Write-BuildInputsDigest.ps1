<# The UI build's content provenance (D00 T02 §44 item 1).

Writes the digest of every UI build input (Get-UiBuildInputs: sources,
XAML, project files, imports, linked items, shared build files), the
restore result (tests/UI/obj/project.assets.json), and the SDK version
beside the built binary, so the freshness check can compare content
instead of timestamps: an edit whose timestamp was restored, a deleted
input, or a changed property all change the digest.

tests/UI/UI.csproj runs this after every build:
  powershell -File tools/Write-BuildInputsDigest.ps1 -Root <repo> -Out <OutDir>build-inputs.digest -Sdk <NETCoreSdkVersion>
#>
param(
  [Parameter(Mandatory = $true)][string]$Root,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$Sdk = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$d = Get-BuildInputsDigest ([System.IO.Path]::GetFullPath($Root)) $Sdk
$tmp = "$Out.tmp"
[System.IO.File]::WriteAllText($tmp, $d.Digest + "`n" + (($d.Lines) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmp -Destination $Out -Force
Write-Output "build-inputs digest $($d.Digest) ($($d.Lines.Count) entries) -> $Out"
exit 0
