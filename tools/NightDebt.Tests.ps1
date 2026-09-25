# Night-debt collector fixture suite (D00 T02 §27): the Night-red
# writer and the JSON reader the morning report quotes. Self-contained
# under TEMP except the parity check, which reads the live tree.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NightDebt.ps1')
$Root = Split-Path -Parent $PSScriptRoot

$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
$dir = Join-Path ([System.IO.Path]::GetTempPath()) 'night-debt-fixtures'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $dir

$todo = Join-Path $dir 'TODO-01-x.md'
$body = @('## 1. Work', '', '**Night-owed:** D90-T01-S1-N1 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-14)', '**Night-owed:** D90-T01-S1-N2 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-14)', '', '## Verification') -join "`n"
[System.IO.File]::WriteAllText($todo, $body)
$r1 = Format-RedLine '2026-09-16' 'D90-T01-S1-N1' 0 1 0 'build/nightly/a/interactive.trx'
Assert ($r1 -eq '**Night-red:** 2026-09-16 D90-T01-S1-N1 (0 passed, 1 failed, 0 skipped; log build/nightly/a/interactive.trx)') 'red-line-shape' $r1
Assert ((Add-RedLine $todo 'D90-T01-S1-N1' '2026-09-16' $r1) -eq 'appended red line') 'red-line-appends'
Assert ((Add-RedLine $todo 'D90-T01-S1-N1' '2026-09-16' $r1) -like 'skip: D90-T01-S1-N1 already carries a red line for 2026-09-16') 'red-line-once-per-date'
$r2 = Format-RedLine '2026-09-19' 'D90-T01-S1-N1' 0 1 0 'build/nightly/b/interactive.trx'
$null = Add-RedLine $todo 'D90-T01-S1-N1' '2026-09-19' $r2
$lines = @((Get-Content $todo -Raw) -split "`r?`n")
$i1 = [array]::IndexOf($lines, $r1); $i2 = [array]::IndexOf($lines, $r2); $iOwed2 = [array]::IndexOf($lines, '**Night-owed:** D90-T01-S1-N2 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-14)')
Assert (($i1 -eq 3) -and ($i2 -eq 4) -and ($iOwed2 -eq 5)) 'red-lines-follow-their-owed-line' "red1 $i1 red2 $i2 owed2 $iOwed2"
Assert ((Add-RedLine $todo 'D90-T01-S1-N9' '2026-09-16' $r1) -eq 'skip: no Night-owed line for D90-T01-S1-N9') 'red-line-without-owed-skips-loud'

# Parity with the live queries: every debt's JSON line equals the text
# line `query night-debt` prints, and the reader fails loud on non-JSON.
$py = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'py' }
$debts = @(Get-OpenNightDebts $Root $py)
$text = @(& $py (Join-Path $Root 'scripts/todo-graph.py') query night-debt 2>&1 | Where-Object { ("$_" -match '^\s{4}\S') -and ("$_" -notmatch '^\s+WARN ') } | ForEach-Object { "$_".Trim() })
Assert (($debts.Count -eq $text.Count) -and ((@($debts | ForEach-Object { $_.Line }) -join "`n") -eq ($text -join "`n"))) 'json-lines-match-query-text' "json $($debts.Count) text $($text.Count)"
Assert (@($debts | Where-Object { ($_.Owner -eq '') -or ($_.State -eq '') }).Count -eq 0) 'json-carries-owner-and-state'
$fake = Join-Path $dir 'fakepy.cmd'
'@echo not json' | Set-Content -Path $fake -Encoding ASCII
$threw = ''
try { $null = Get-OpenNightDebts $Root $fake } catch { $threw = "$_" }
Assert ($threw -like 'night-debt: query output is not JSON*') 'reader-fails-loud-on-non-json' $threw

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightDebt.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightDebt.Tests: all green'
exit 0
