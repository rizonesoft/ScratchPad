# Fixture suite for tools/NightlyTriage.ps1 (D00 T02 section 45 item 7).
# Self-contained: builds a throwaway git repository under TEMP with one
# TODO file, plays a run's recorded collector write, and drives the real
# script through -WorkspaceRoot. Exits nonzero on any failure.
# Continue: git's stderr warnings must not stop the fixture (PS 5.1).
$ErrorActionPreference = 'Continue'
$script = Join-Path $PSScriptRoot 'NightlyTriage.ps1'
$failures = 0
function Assert([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { Write-Output "PASS $Name" }
  else { Write-Output "FAIL $Name $Detail"; $script:failures++ }
}
function Invoke-Triage([string[]]$ArgList) {
  $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $script @ArgList 2>&1 | ForEach-Object { "$_" })
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join ' | ') }
}

$ws = Join-Path ([System.IO.Path]::GetTempPath()) 'nightly-triage-fixtures'
if (Test-Path $ws) { Remove-Item $ws -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ws 'todo')
$todo = Join-Path $ws 'todo\T.md'
[System.IO.File]::WriteAllText($todo, "# T`n- Night-owed: a`nend`n")
$null = git -C $ws init -q 2>&1
$null = git -C $ws config user.name fx 2>&1
$null = git -C $ws config user.email fx@example.invalid 2>&1
$null = git -C $ws config commit.gpgsign false 2>&1
$null = git -C $ws config core.autocrlf false 2>&1
$null = git -C $ws add -A 2>&1
$null = git -C $ws commit -q -m base 2>&1
$stamp = '2026-09-25-023001'
$line = '**Night-collected:** 2026-09-25 a (1 passed, 0 failed, 0 skipped; log l)'
[System.IO.File]::WriteAllText($todo, "# T`n- Night-owed: a`n$line`nend`n")
$run = Join-Path $ws "build\nightly\$stamp"
$null = New-Item -ItemType Directory -Force -Path $run
([pscustomobject]@{ version = 1; writes = @([pscustomobject]@{ file = 'todo/T.md'; lines = @($line) }) } | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $run 'tracked-writes.json') -Encoding UTF8

$plan = Invoke-Triage @('-WorkspaceRoot', $ws)
Assert (($plan.Code -eq 0) -and ($plan.Text -like '*todo/T.md ready (1 line(s) from 2026-09-25-023001)*plan only*')) 'triage-plan-names-the-recorded-lines' $plan.Text
# R3-F1: a case-only edit beyond the recorded lines refuses.
[System.IO.File]::WriteAllText($todo, "# t`n- Night-owed: a`n$line`nend`n")
$caseEdit = Invoke-Triage @('-WorkspaceRoot', $ws)
Assert (($caseEdit.Code -eq 1) -and ($caseEdit.Text -like '*REFUSED: todo/T.md differs from HEAD beyond*')) 'triage-refuses-a-case-only-edit' $caseEdit.Text

# Anything beyond the recorded lines refuses and commits nothing.
[System.IO.File]::WriteAllText($todo, "# T edited`n- Night-owed: a`n$line`nend`n")
$bad = Invoke-Triage @('-WorkspaceRoot', $ws, '-Commit')
$head1 = (git -C $ws rev-list --count HEAD 2>$null | Out-String).Trim()
Assert (($bad.Code -eq 1) -and ($bad.Text -like '*REFUSED: todo/T.md differs from HEAD beyond*') -and ($head1 -eq '1')) 'triage-refuses-other-changes' $bad.Text

# Outside a Claude Code session the commit refuses (R1-F1).
$savedSession = $env:CLAUDE_CODE_SESSION_ID
$env:CLAUDE_CODE_SESSION_ID = ''
[System.IO.File]::WriteAllText($todo, "# T`n- Night-owed: a`n$line`nend`n")
$noSession = Invoke-Triage @('-WorkspaceRoot', $ws, '-Commit')
Assert (($noSession.Code -eq 1) -and ($noSession.Text -like '*REFUSED: -Commit runs only inside a Claude Code session*')) 'triage-commit-needs-the-writer-session' $noSession.Text
$env:CLAUDE_CODE_SESSION_ID = 'fixture-session'
# The recorded lines alone commit, only that file, with the fixed message.
[System.IO.File]::WriteAllText($todo, "# T`n- Night-owed: a`n$line`nend`n")
'untracked' | Set-Content -Path (Join-Path $ws 'todo\other.md') -Encoding UTF8
$ok = Invoke-Triage @('-WorkspaceRoot', $ws, '-Commit')
$msg = (git -C $ws log -1 --format=%s 2>$null | Out-String).Trim()
$files = @(git -C $ws show --name-only --format= HEAD 2>$null | Where-Object { $_ -ne '' })
Assert (($ok.Code -eq 0) -and ($msg -eq "nightly: record the collector lines of $stamp") -and ($files.Count -eq 1) -and ($files[0] -eq 'todo/T.md')) 'triage-commits-only-the-recorded-file' "$($ok.Text) || $msg || $($files -join ',')"

# R3-F2: two runs awaiting triage that wrote the same file, plus a newer
# run that wrote nothing, commit together.
$stamp2 = '2026-09-26-023001'
$line2 = '**Night-collected:** 2026-09-26 b (1 passed, 0 failed, 0 skipped; log m)'
$stamp3 = '2026-09-27-023001'
$line3 = '**Night-red:** 2026-09-27 a (0 passed, 1 failed, 0 skipped; log n)'
[System.IO.File]::WriteAllText($todo, "# T`n- Night-owed: a`n$line`n$line3`nend`n$line2`n")
foreach ($pair in @(@($stamp2, $line2), @($stamp3, $line3))) {
  $rd = Join-Path $ws "build\nightly\$($pair[0])"
  $null = New-Item -ItemType Directory -Force -Path $rd
  ([pscustomobject]@{ version = 1; writes = @([pscustomobject]@{ file = 'todo/T.md'; lines = @($pair[1]) }) } | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $rd 'tracked-writes.json') -Encoding UTF8
}
$rd4 = Join-Path $ws 'build\nightly\2026-09-28-023001'
$null = New-Item -ItemType Directory -Force -Path $rd4
([pscustomobject]@{ version = 1; writes = @() } | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $rd4 'tracked-writes.json') -Encoding UTF8
$multi = Invoke-Triage @('-WorkspaceRoot', $ws, '-Commit')
$msg2 = (git -C $ws log -1 --format=%s 2>$null | Out-String).Trim()
Assert (($multi.Code -eq 0) -and ($msg2 -eq "nightly: record the collector lines of $stamp2, $stamp3")) 'triage-commits-every-pending-run-together' "$($multi.Text) || $msg2"
# A second pass finds the lines committed and does nothing.
$again = Invoke-Triage @('-WorkspaceRoot', $ws, '-Commit')
Assert (($again.Code -eq 0) -and ($again.Text -like '*already carries*nothing to commit*')) 'triage-is-idempotent' $again.Text

# A manifest naming a file outside todo/ refuses.
([pscustomobject]@{ version = 1; writes = @([pscustomobject]@{ file = '../x.md'; lines = @('x') }) } | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $run 'tracked-writes.json') -Encoding UTF8
$esc = Invoke-Triage @('-WorkspaceRoot', $ws)
Assert (($esc.Code -eq 1) -and ($esc.Text -like '*REFUSED: ../x.md is not a TODO file*')) 'triage-refuses-paths-outside-todo' $esc.Text

$env:CLAUDE_CODE_SESSION_ID = $savedSession
Remove-Item $ws -Recurse -Force
if ($failures -gt 0) { Write-Output "NightlyTriage.Tests: $failures FAILURE(S)"; exit 1 }
Write-Output 'NightlyTriage.Tests: all green'
exit 0
