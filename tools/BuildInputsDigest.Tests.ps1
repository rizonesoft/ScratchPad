# Fixtures for the UI build's content provenance (D00 T02 §44 item 1):
# an edit whose timestamp was restored, a deleted input, and an SDK change
# each refuse; an untouched tree passes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "build-digest-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Force -Path $dir
$a = Join-Path $dir 'A.cs'
$b = Join-Path $dir 'B.csproj'
'class A {}' | Set-Content -Path $a -Encoding UTF8
'<Project />' | Set-Content -Path $b -Encoding UTF8
$inputs = @($a, $b)
$digestFile = Join-Path $dir 'build-inputs.digest'
$d = Get-BuildInputsDigest $dir '10.0.400' $inputs
[System.IO.File]::WriteAllText($digestFile, $d.Digest + "`n" + ($d.Lines -join "`n") + "`n")

Assert ((Test-BuildInputsDigest $dir $digestFile '10.0.400' $inputs).Ok) 's44-untouched-inputs-read-fresh'

$stamp = (Get-Item $a).LastWriteTimeUtc
'class A { int x; }' | Set-Content -Path $a -Encoding UTF8
(Get-Item $a).LastWriteTimeUtc = $stamp
$edited = Test-BuildInputsDigest $dir $digestFile '10.0.400' $inputs
Assert ((-not $edited.Ok) -and ($edited.Error -like '*stale by content*first: A.cs*')) 's44-restored-timestamp-edit-refuses' $edited.Error

'class A {}' | Set-Content -Path $a -Encoding UTF8
Assert ((Test-BuildInputsDigest $dir $digestFile '10.0.400' $inputs).Ok) 's44-reverted-content-reads-fresh'

Remove-Item $b
$deleted = Test-BuildInputsDigest $dir $digestFile '10.0.400' $inputs
Assert ((-not $deleted.Ok) -and ($deleted.Error -like '*B.csproj*')) 's44-deleted-input-refuses' $deleted.Error
'<Project />' | Set-Content -Path $b -Encoding UTF8

$sdk = Test-BuildInputsDigest $dir $digestFile '10.0.500' $inputs
Assert ((-not $sdk.Ok) -and ($sdk.Error -like '*first: sdk*')) 's44-sdk-change-refuses' $sdk.Error

$none = Test-BuildInputsDigest $dir (Join-Path $dir 'absent.digest') '10.0.400' $inputs
Assert ((-not $none.Ok) -and ($none.Error -like '*has no content digest*')) 's44-missing-digest-refuses' $none.Error

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "BuildInputsDigest.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'BuildInputsDigest.Tests: all green'
exit 0
