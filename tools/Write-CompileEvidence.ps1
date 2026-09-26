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
  [string]$Assembly = '',
  [string]$Out = '',
  # One consistent snapshot (D00 T02 section 52 R4-A1): the target before
  # CoreCompile writes the inputs digest to -Snapshot (-Phase before); the
  # after phase recomputes it and, when an input changed during the build,
  # writes evidence that names the change instead of an inputs digest, so
  # freshness refuses rather than bind the old assembly to new sources.
  [ValidateSet('before', 'after')][string]$Phase = 'after',
  [string]$Snapshot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$rootFull = [System.IO.Path]::GetFullPath($Root)
$d = Get-ProjectOwnInputsDigest $rootFull ([System.IO.Path]::GetFullPath($ProjectDir))
if ($Phase -eq 'before') {
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Snapshot)
  [System.IO.File]::WriteAllText($Snapshot, $d.Digest, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "compile inputs snapshot $($d.Digest) -> $Snapshot"
  exit 0
}
# A missing or different snapshot fails closed (section 53, from 52 R5-A1).
$snap = Test-CompileSnapshot $Snapshot $d.Digest
$inputsLine = if ($snap.Ok) { "inputs $($d.Digest)" } else { "inputs refused: $($snap.Reason)" }
$asm = Get-FileSha256 ([System.IO.Path]::GetFullPath($Assembly))
$tmp = "$Out.tmp"
[System.IO.File]::WriteAllText($tmp, "$inputsLine`nassembly $asm`n" + (($d.Lines) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmp -Destination $Out -Force
Write-Output "compile evidence $($d.Digest) ($($d.Lines.Count) inputs) -> $Out"
exit 0
