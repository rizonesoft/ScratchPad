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
# Run identity (D00 T02 §35 item 3): two red runs on one day are two
# attempts and both land; the same run twice lands once.
$ra = Format-RedLine '2026-09-18' 'D90-T01-S1-N2' 0 1 0 'build/nightly/c/interactive.trx' 'run-c'
$rb = Format-RedLine '2026-09-18' 'D90-T01-S1-N2' 0 1 0 'build/nightly/d/interactive.trx' 'run-d'
Assert ($ra -eq '**Night-red:** 2026-09-18 D90-T01-S1-N2 (0 passed, 1 failed, 0 skipped; log build/nightly/c/interactive.trx; run run-c)') 'red-line-carries-run' $ra
Assert ((Add-RedLine $todo 'D90-T01-S1-N2' '2026-09-18' $ra) -eq 'appended red line') 'red-line-first-run-appends'
Assert ((Add-RedLine $todo 'D90-T01-S1-N2' '2026-09-18' $rb) -eq 'appended red line') 'red-line-second-run-same-day-appends'
Assert ((Add-RedLine $todo 'D90-T01-S1-N2' '2026-09-18' $ra) -like 'skip: D90-T01-S1-N2 already carries a red line for 2026-09-18 run run-c') 'red-line-once-per-run'
# Triage's finding suffix keeps the run identity (D00 T02 §35 R2-F2).
$linked = (Get-Content $todo -Raw) -replace [regex]::Escape($rb), ($rb.Substring(0, $rb.Length - 1) + '; finding D00-T02-S35-F9)')
[System.IO.File]::WriteAllText($todo, $linked)
Assert ((Add-RedLine $todo 'D90-T01-S1-N2' '2026-09-18' $rb) -like 'skip: D90-T01-S1-N2 already carries a red line for 2026-09-18 run run-d') 'red-line-once-per-run-after-finding-link'
# The red entry names owner and next action (D00 T02 §35 R1-F4).
$tn = Format-RedTriageNote 'alice' '2026-09-18'
Assert ($tn -eq 'owner alice; next: file the staged finding, then append `; finding <ref>` to the 2026-09-18 Night-red line') 'red-entry-links-remediation' $tn
Assert ((Format-RedTriageNote '' '2026-09-18') -like 'owner operator;*') 'red-entry-defaults-owner'

# Parity with the live queries: every debt's JSON line equals the text
# line `query night-debt` prints, and the reader fails loud on non-JSON.
$py = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'py' }
$debts = @(Get-OpenNightDebts $Root $py)
$text = @(& $py (Join-Path $Root 'scripts/todo-graph.py') query night-debt 2>&1 | Where-Object { ("$_" -match '^\s{4}\S') -and ("$_" -notmatch '^\s+WARN ') } | ForEach-Object { "$_".Trim() })
Assert (($debts.Count -eq $text.Count) -and ((@($debts | ForEach-Object { $_.Line }) -join "`n") -eq ($text -join "`n"))) 'json-lines-match-query-text' "json $($debts.Count) text $($text.Count)"
Assert (@($debts | Where-Object { ($_.Owner -eq '') -or ($_.State -eq '') }).Count -eq 0) 'json-carries-owner-and-state'
# The report writes the document's report_block verbatim, warnings
# included, under its heading (D00 T02 §27 R1-F5, R1-F6).
$synthetic = [pscustomobject]@{ schema = 'night-debt/1'; report_block = @('    todo/x.md D90-T01-S1-N1 D90 T01 s1 count 1 filter Interactive age 5n due 2026-09-18 owner operator state open last-log none OVERDUE escalate operator by 2026-09-20: rerun', '    WARN D90-T01-S1-N1: due token ''x'' malformed; fallback 2026-09-18') }
$blockOut = @(Format-NightDebtStatus $synthetic)
Assert (($blockOut.Count -eq 5) -and ($blockOut[0] -eq 'Debt status at run start (`query night-debt`, verbatim):') -and ($blockOut[2] -eq $synthetic.report_block[0]) -and ($blockOut[3] -eq $synthetic.report_block[1])) 'report-block-verbatim-with-warnings' ($blockOut -join ' | ')
Assert (@(Format-NightDebtStatus ([pscustomobject]@{ schema = 'night-debt/1'; report_block = @() })).Count -eq 0) 'report-block-empty-when-no-debt'
# The post-run block (D00 T02 §35 item 9): a debt open at run start and
# collected green tonight reads collected; one still open reads its
# post-run line verbatim.
$startDoc = [pscustomobject]@{ debts = @([pscustomobject]@{ id = 'D90-T01-S1-N1'; state = 'open' }, [pscustomobject]@{ id = 'D90-T01-S1-N2'; state = 'red' }); report_block = @('    a', '    b') }
$endDoc = [pscustomobject]@{ debts = @([pscustomobject]@{ id = 'D90-T01-S1-N2'; state = 'red-repeat' }); report_block = @('    todo/x.md D90-T01-S1-N2 state red-repeat') }
$post = @(Format-NightDebtPostRun $startDoc $endDoc)
Assert (($post[0] -like 'Debt status after the run*') -and ($post -contains '    todo/x.md D90-T01-S1-N2 state red-repeat') -and ($post -contains '    D90-T01-S1-N1 state collected tonight (was open)')) 'post-run-reads-collected-tonight' ($post -join ' | ')
Assert (@(Format-NightDebtPostRun ([pscustomobject]@{ debts = @(); report_block = @() }) ([pscustomobject]@{ debts = @(); report_block = @() })).Count -eq 0) 'post-run-empty-when-no-debt'
# D00 T02 §42 item 7: a green collection whose write or re-query failed
# reads collected-unrecorded.
$postU = @(Format-NightDebtPostRun $startDoc $endDoc @('D90-T01-S1-N2'))
Assert (($postU -contains '    D90-T01-S1-N2 state collected-unrecorded (green tonight; the query still reads it open, closure unrecorded)')) 's42-green-still-open-reads-collected-unrecorded' ($postU -join ' | ')
$postQ = @(Format-UnrecordedGreens @('D90-T01-S1-N1') 'boom')
Assert (($postQ[0] -eq 'Debt status after the run: query failed: boom') -and ($postQ -contains '    D90-T01-S1-N1 state collected-unrecorded (green tonight; the re-run query failed, closure unrecorded)')) 's42-failed-requery-reads-collected-unrecorded' ($postQ -join ' | ')
$gU = Format-DebtGreenEntry 'D90-T01-S1-N1' 's' 1 0 0 'log' 'skipped: write failed'
Assert (($gU[0] -like '*collected-unrecorded*closure unrecorded') -and ($gU[1] -eq $true)) 's42-failed-write-entry-reds' "$($gU[0])"
# D00 T02 §42 item 6: closure binds to the owed test identities.
$dA = Get-TestNamesDigest @('UI.A.One', 'UI.A.Two')
$dB = Get-TestNamesDigest @('UI.A.Two', 'UI.A.One', 'UI.A.One')
$dC = Get-TestNamesDigest @('UI.A.One', 'UI.A.Three')
Assert (($dA -eq $dB) -and ($dA -ne $dC) -and ($dA -match '^[0-9a-f]{16}$')) 's42-digest-is-order-free-and-set-exact' "$dA $dC"
$idSwap = Test-DebtIdentity $dA @('UI.A.One', 'UI.A.Three')
$idOk = Test-DebtIdentity $dA @('UI.A.Two', 'UI.A.One')
$idLegacy = Test-DebtIdentity '' @('UI.A.One')
Assert ((-not $idSwap.Ok) -and $idOk.Ok -and $idLegacy.Ok) 's42-swapped-test-at-same-count-keeps-debt-open'
# D00 T02 §42 R1-F4: a failed write becomes a note, never a stop.
$wf = Invoke-CollectedLine (Join-Path $env:TEMP "no-such-dir-$([guid]::NewGuid().ToString('N'))\x.md") 'D90-T01-S1-N1' '**Night-collected:** x'
$gW = Format-DebtGreenEntry 'D90-T01-S1-N1' 's' 1 0 0 'log' $wf
Assert (($wf -like 'write failed:*') -and ($gW[0] -like '*collected-unrecorded*') -and $gW[1]) 's42-failed-write-reads-collected-unrecorded' "$wf"
# D00 T02 §42 R1-F5: a new record with an unrecorded digest appends; the
# same digest again is skipped.
$cdir = Join-Path $env:TEMP "s42-collect-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Force -Path $cdir
$ctodo = Join-Path $cdir 'TODO.md'
@('## 1. W', '', '**Night-owed:** D90-T01-S1-N1 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-12, digest aaaa1111bbbb2222)', '**Night-collected:** 2026-09-18 D90-T01-S1-N1 (1 passed, 0 failed, 0 skipped; log a.trx; digest cccc3333dddd4444)', '') | Set-Content -Path $ctodo -Encoding UTF8
$c1 = Invoke-CollectedLine $ctodo 'D90-T01-S1-N1' '**Night-collected:** 2026-09-20 D90-T01-S1-N1 (1 passed, 0 failed, 0 skipped; log b.trx; digest aaaa1111bbbb2222)'
$c2 = Invoke-CollectedLine $ctodo 'D90-T01-S1-N1' '**Night-collected:** 2026-09-21 D90-T01-S1-N1 (1 passed, 0 failed, 0 skipped; log c.trx; digest aaaa1111bbbb2222)'
Remove-Item $cdir -Recurse -Force
Assert (($c1 -eq 'appended: D90-T01-S1-N1') -and ($c2 -like 'skip:*already carries*')) 's42-new-digest-appends-past-a-stale-record' "$c1 / $c2"
# D00 T02 §42 R3-F1: a quarantine-skipped owed test counts in the
# collector's identity, so the digest matches Get-DebtDigest's.
$tq = Join-Path $env:TEMP "s42-census-$([guid]::NewGuid().ToString('N')).trx"
'<TestRun><Results><UnitTestResult testName="UI.A.One" outcome="Passed" /><UnitTestResult testName="UI.A.Two" outcome="NotExecuted" /></Results></TestRun>' | Set-Content -Path $tq -Encoding UTF8
$cn = @(Get-TrxCensusNames $tq)
Remove-Item $tq
Assert (($cn.Count -eq 2) -and ((Get-TestNamesDigest $cn) -eq (Get-TestNamesDigest @('UI.A.One', 'UI.A.Two'))) -and (Test-DebtIdentity (Get-TestNamesDigest @('UI.A.One', 'UI.A.Two')) $cn).Ok) 's42-quarantine-skip-keeps-the-identity' ($cn -join ';')
# D00 T02 §42 R1-F1: the listing parser reads the available tests.
$ln = Get-ListedTestNames @('Test run for x.dll', 'The following Tests are available:', '    UI.A.One', '    UI.A.Two(x: 1)')
Assert (($ln.Count -eq 2) -and ($ln[1] -eq 'UI.A.Two(x: 1)')) 's42-listing-parser-reads-names' ($ln -join ';')
Assert ((Format-CollectedLine '2026-09-20' 'D90-T01-S1-N1' 2 0 0 'build/x.trx' $dA) -eq "**Night-collected:** 2026-09-20 D90-T01-S1-N1 (2 passed, 0 failed, 0 skipped; log build/x.trx; digest $dA)") 's42-collected-line-carries-the-digest'
$liveDoc = Get-NightDebtDocument $Root $py
$liveText = @(& $py (Join-Path $Root 'scripts/todo-graph.py') query night-debt 2>&1 | Where-Object { "$_" -match '^\s{4}\S' } | ForEach-Object { "$_" })
Assert ((@($liveDoc.report_block) -join "`n") -eq ($liveText -join "`n")) 'live-report-block-equals-query-text' "block $(@($liveDoc.report_block).Count) text $($liveText.Count)"
$fake = Join-Path $dir 'fakepy.cmd'
'@echo not json' | Set-Content -Path $fake -Encoding ASCII
$threw = ''
try { $null = Get-OpenNightDebts $Root $fake } catch { $threw = "$_" }
Assert ($threw -like 'night-debt: query output is not JSON*') 'reader-fails-loud-on-non-json' $threw

Remove-Item $dir -Recurse -Force
if ($failures -gt 0) { Write-Output "NightDebt.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightDebt.Tests: all green'
exit 0
