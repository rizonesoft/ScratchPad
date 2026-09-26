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
$startDoc = [pscustomobject]@{ schema = 'night-debt/1'; debts = @([pscustomobject]@{ id = 'D90-T01-S1-N1'; state = 'open' }, [pscustomobject]@{ id = 'D90-T01-S1-N2'; state = 'red' }); report_block = @('    a', '    b') }
$endDoc = [pscustomobject]@{ schema = 'night-debt/1'; debts = @([pscustomobject]@{ id = 'D90-T01-S1-N2'; state = 'red-repeat' }); report_block = @('    todo/x.md D90-T01-S1-N2 state red-repeat') }
$post = @(Format-NightDebtPostRun $startDoc $endDoc)
Assert (($post[0] -like 'Debt status after the run*') -and ($post -contains '    todo/x.md D90-T01-S1-N2 state red-repeat') -and ($post -contains '    D90-T01-S1-N1 state collected tonight (was open)')) 'post-run-reads-collected-tonight' ($post -join ' | ')
Assert (@(Format-NightDebtPostRun ([pscustomobject]@{ schema = 'night-debt/1'; debts = @(); report_block = @() }) ([pscustomobject]@{ schema = 'night-debt/1'; debts = @(); report_block = @() })).Count -eq 0) 'post-run-empty-when-no-debt'
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
# D00 T02 section 50 item 8: a failed write and an unknown readback are
# distinct, and a landed write reconciles to collected once.
$w50 = Join-Path $env:TEMP "nd50-$([guid]::NewGuid().ToString('N')).md"
'# x', '', '**Night-owed:** D90-T01-S1-N1 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-20)', '' | Set-Content -Path $w50 -Encoding UTF8
$l50 = '**Night-collected:** 2026-09-21 D90-T01-S1-N1 (1 passed, 0 failed, 0 skipped; log b.trx; digest aaaa1111bbbb2222)'
$f50 = Add-CollectedLine $w50 'D90-T01-S1-N1' $l50 { param($stage) if ($stage -eq 'move') { throw 'disk full' } }
$afterFail = ([regex]::Matches((Get-Content $w50 -Raw), [regex]::Escape($l50))).Count
$u50 = Add-CollectedLine $w50 'D90-T01-S1-N1' $l50 { param($stage) if ($stage -eq 'readback') { throw 'io error' } }
$r50 = Add-CollectedLine $w50 'D90-T01-S1-N1' $l50
$n50 = ([regex]::Matches((Get-Content $w50 -Raw), [regex]::Escape($l50))).Count
$g50 = Format-DebtGreenEntry 'D90-T01-S1-N1' 'D90 T01 §1' 1 0 0 'b.trx' $r50
Assert (($f50 -like 'failed: D90-T01-S1-N1 not written (disk full)*') -and ($afterFail -eq 0) -and ($u50 -like 'unknown:*') -and ($r50 -like 'reconciled:*') -and ($n50 -eq 1) -and ($g50[0] -like '*collected 1 passed*reconciled*') -and (-not $g50[1])) 's50-write-outcomes-and-once-reconciliation' "$f50 | $u50 | $r50 | copies $n50"
Remove-Item $w50 -Force

# Section 50 item 10: a failed post-run query reads as a failure, never as
# every debt collected tonight.
$qf = $null
try { $null = Get-NightDebtDocument (Split-Path -Parent $PSScriptRoot) 'no-such-python-50' } catch { $qf = "$_" }
$pf = $null
try { $null = Format-NightDebtPostRun ([pscustomobject]@{ schema = 'night-debt/1'; debts = @([pscustomobject]@{ id = 'D90-T01-S1-N1'; state = 'open' }); report_block = @() }) $null @() } catch { $pf = "$_" }
$ug = @(Format-UnrecordedGreens @('D90-T01-S1-N1') "$qf")
Assert (($null -ne $qf) -and ($pf -like '*returned no night-debt/1 document*') -and (@($ug | Where-Object { $_ -like '*D90-T01-S1-N1*' }).Count -ge 1)) 's50-post-run-query-failure-never-reads-collected' "$qf | $pf | $($ug -join ' / ')"

# Section 50 R1-R1, R2-R1: the chain end to end against the real graph.
# A temporary repository carries a copy of scripts/todo-graph.py, a
# one-debt TODO tree, and a commit the owed candidate names. Night one:
# the collector's write lands but its readback fails (unknown), the write
# is registered as possibly landed, and the post-run query fails, so the
# green reads unrecorded, never collected. Night two: the real query reads
# the debt closed by the landed line, so the collector has nothing to
# collect and the file keeps exactly one collected line. R1-A2, R2-A1: a
# record of another event never blocks the valid one.
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$e50 = Join-Path $env:TEMP "nd50e-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Force -Path (Join-Path $e50 'scripts'), (Join-Path $e50 'todo\90-night')
Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\*.py') (Join-Path $e50 'scripts')
$eap50 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$null = & git -C $e50 init -q 2>&1
'x' | Set-Content -Path (Join-Path $e50 'seed.txt')
$null = & git -C $e50 add seed.txt 2>&1
$null = & git -C $e50 -c user.name=t -c user.email=t@t commit -q -m seed 2>&1
$c50 = ((& git -C $e50 rev-parse HEAD) | Out-String).Trim()
$ErrorActionPreference = $eap50
@('# 90 Night', '', '## TODOs', '', '| TODO | Title | Status |', '| ---- | ----- | :----: |', '| [TODO-01](./TODO-01-night.md) | Night | active |') | Set-Content -Path (Join-Path $e50 'todo\90-night\INDEX.md') -Encoding UTF8
$t50 = Join-Path $e50 'todo\90-night\TODO-01-night.md'
@('---', 'schema_version: 1', 'id: night', 'domain: 90-night', 'status: active', 'title: "TODO-01 -- Night"', 'track: Z9', '---', '', '# TODO-01 -- Night', '', '> **Goal:** Fixture.', '', '## Outcome', '', '- Fixture.', '', '**Adjacency:** all=not-applicable (fixture)', '', '## Implementation Order', '', '| Order | Section | Deliverable | Depends On | Status |', '| :---: | :-----: | ----------- | ---------- | :----: |', '|   1   |   §1    | Owned work | -- |  [ ]   |', '', '---', '', '## 1. Owned work', '', '- [ ] Did the thing', '- [ ] Commit: `"selftest: night"`', '', '**Test checkpoint:** `true`', '', "**Night-owed:** D90-T01-S1-N1 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-20, candidate $c50, digest aaaa1111bbbb2222)", '', '## Verification', '', '- [ ] Fixture file validates') | Set-Content -Path $t50 -Encoding UTF8
$docStart = Get-NightDebtDocument $e50
$before50 = [System.IO.File]::ReadAllText($t50)
$line1 = Format-CollectedLine '2026-09-21' 'D90-T01-S1-N1' 1 0 0 'seed.txt' 'aaaa1111bbbb2222' $c50 's1-pid1' '02:40' 'collect-s1-D90-T01-S1-N1'
$note1 = Add-CollectedLine $t50 'D90-T01-S1-N1' $line1 { param($stage) if ($stage -eq 'readback') { throw 'io error' } }
$tw = @{}
Register-TrackedWrite $tw $e50 $t50 $line1 $note1 $before50
$qfail = $null
try { $null = Get-NightDebtDocument $e50 'no-such-python-50' } catch { $qfail = "$_" }
$night1 = @(Format-UnrecordedGreens @('D90-T01-S1-N1') $qfail)
$g1 = Format-DebtGreenEntry 'D90-T01-S1-N1' 'D90 T01 §1' 1 0 0 'seed.txt' $note1
$docNext = Get-NightDebtDocument $e50
$openNext = @(@($docNext.debts) | Where-Object { "$($_.id)" -eq 'D90-T01-S1-N1' })
$copies = ([regex]::Matches([System.IO.File]::ReadAllText($t50), '\*\*Night-collected:\*\*')).Count
$reg = @($tw.Values | ForEach-Object { @($_.Lines) }) -contains $line1
Assert ((@($docStart.debts | Where-Object { "$($_.id)" -eq 'D90-T01-S1-N1' }).Count -eq 1) -and ($note1 -like 'unknown:*') -and $reg -and ($null -ne $qfail) -and (@($night1 | Where-Object { $_ -like '*D90-T01-S1-N1*' }).Count -ge 1) -and $g1[1] -and ($openNext.Count -eq 0) -and ($copies -eq 1)) 's50-landed-write-failed-query-then-reconciled' "start $(@($docStart.debts).Count) | $note1 | reg $reg | $($night1 -join ' / ') | next open $($openNext.Count) | copies $copies"
$old50 = Format-CollectedLine '2026-09-23' 'D90-T01-S1-N2' 1 0 0 'l' 'aaaa1111bbbb2222' 'aaaa' 'r' '02:40' 'e1'
'# x', '', '**Night-owed:** D90-T01-S1-N2 (1 Interactive, collector Nightly UI 02:30, owed 2026-09-20, candidate bbbb, digest aaaa1111bbbb2222)', $old50, '' | Set-Content -Path $t50 -Encoding UTF8
$new50 = Format-CollectedLine '2026-09-24' 'D90-T01-S1-N2' 1 0 0 'l' 'aaaa1111bbbb2222' 'bbbb' 'r2' '02:41' 'e2'
$n50b = Add-CollectedLine $t50 'D90-T01-S1-N2' $new50
Assert ($n50b -like 'appended*') 's50-older-candidate-record-never-blocks-the-valid-one' $n50b
Remove-Item $e50 -Recurse -Force

if ($failures -gt 0) { Write-Output "NightDebt.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightDebt.Tests: all green'
exit 0
