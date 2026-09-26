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
  [string]$Out = '',
  [string]$Sdk = '',
  # One consistent snapshot (D00 T02 section 52 R4-A1): -Phase before
  # (before CoreCompile) records the inputs digest to -Snapshot; the
  # after phase writes nothing, and removes a stale digest and binding,
  # when an input changed during the build, so freshness refuses.
  [ValidateSet('before', 'after')][string]$Phase = 'after',
  [string]$Snapshot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$rootFull = [System.IO.Path]::GetFullPath($Root)
$d = Get-BuildInputsDigest $rootFull $Sdk
if ($Phase -eq 'before') {
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Snapshot)
  [System.IO.File]::WriteAllText($Snapshot, $d.Digest, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "build-inputs snapshot $($d.Digest) -> $Snapshot"
  exit 0
}
# A missing or different snapshot fails closed (section 53, from 52 R5-A1).
$snap = Test-CompileSnapshot $Snapshot $d.Digest
if (-not $snap.Ok) {
  foreach ($f in @($Out, (Join-Path (Split-Path -Parent $Out) 'build-binding.txt'))) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
  Write-Output "build-inputs digest not written: $($snap.Reason) (rebuild): dotnet build src/ScratchPad.slnx --no-incremental"
  exit 0
}
# The binaries this digest describes (D00 T02 section 52 item 2), taken in
# the same run: UI.dll plus each reference's compile evidence and copy.
$bindingOut = Join-Path (Split-Path -Parent $Out) 'build-binding.txt'
$binding = @(Get-BuildBindingLines $rootFull (Split-Path -Parent ([System.IO.Path]::GetFullPath($Out))) $script:UiBuildProjects)
$tmpB = "$bindingOut.tmp"
[System.IO.File]::WriteAllText($tmpB, (($binding) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmpB -Destination $bindingOut -Force
$tmp = "$Out.tmp"
[System.IO.File]::WriteAllText($tmp, $d.Digest + "`n" + (($d.Lines) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmp -Destination $Out -Force
Write-Output "build-inputs digest $($d.Digest) ($($d.Lines.Count) entries) -> $Out"
exit 0
