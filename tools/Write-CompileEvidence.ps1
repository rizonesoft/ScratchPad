<# A project's own compile evidence (D00 T02 §52 item 2).

Runs after a build that actually compiled (Directory.Build.targets) and
writes, from one snapshot, the digest of the project's own inputs
(Get-ProjectOwnInputsDigest: its directory's sources, XAML, resources,
and project files) and the SHA-256 of the assembly that compile produced,
beside the assembly:

  inputs <digest>
  assembly <sha256>
  <root-relative path> <sha256>   (one per input)

The UI build binds each reference's evidence into build-binding.txt, and
freshness refuses when a reference's inputs moved past its evidence (a
timestamp-restored edit that never recompiled) or a copied assembly is not
the one the evidence names.
#>
param(
  [Parameter(Mandatory = $true)][string]$Root,
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [Parameter(Mandatory = $true)][string]$Assembly,
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$rootFull = [System.IO.Path]::GetFullPath($Root)
$d = Get-ProjectOwnInputsDigest $rootFull ([System.IO.Path]::GetFullPath($ProjectDir))
$asm = Get-FileSha256 ([System.IO.Path]::GetFullPath($Assembly))
$tmp = "$Out.tmp"
[System.IO.File]::WriteAllText($tmp, "inputs $($d.Digest)`nassembly $asm`n" + (($d.Lines) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmp -Destination $Out -Force
Write-Output "compile evidence $($d.Digest) ($($d.Lines.Count) inputs) -> $Out"
exit 0
