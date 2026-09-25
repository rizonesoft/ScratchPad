#Requires -Version 5.1
<#
.SYNOPSIS
  The named triage step that commits the nightly collector's tracked lines (D00 T02 section 45 item 7).
.DESCRIPTION
  The unattended nightly never commits. Its only tracked writes are the
  night-debt collector's `Night-collected:` and `Night-red:` lines in
  TODO files, which it records in build/nightly/<stamp>/tracked-writes.json
  and which its tree check expects. This step reads every run's
  manifest together, verifies that each named file differs from HEAD by
  exactly the recorded lines not yet committed across those runs
  (anything else refuses, naming the file), and with -Commit commits only
  those files. Without -Commit it
  prints the plan. Exit 0 ok, 1 refused, 2 usage.
#>
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$WorkspaceRoot = ''
)
# Continue, not Stop: Windows PowerShell 5.1 turns a native command's
# stderr (git's warnings) into a terminating error under Stop; every git
# call below checks its exit code instead.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
if ($WorkspaceRoot -ne '') { $Root = (Resolve-Path $WorkspaceRoot).Path }
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
$nightDir = Join-Path $Root 'build\nightly'
# git output decodes as UTF-8 (TODO text carries non-ASCII signs).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# Every run's manifest counts together (D00 T02 section 45 R3-F2): two
# nights waiting for triage may both have written the same TODO file, and
# a newer run that wrote nothing must not hide an older run's lines. Each
# file must differ from HEAD by exactly the pending lines of all runs.
$manifests = @(Get-ChildItem -LiteralPath $nightDir -Directory -ErrorAction SilentlyContinue | Where-Object { ($_.Name -match '^\d{4}-\d{2}-\d{2}-\d{6}$') -and (Test-Path (Join-Path $_.FullName 'tracked-writes.json')) } | Sort-Object Name)
if ($manifests.Count -eq 0) { Write-Output 'triage: no run recorded tracked writes; nothing to commit'; exit 0 }
$byFile = [ordered]@{}
$refused = 0
foreach ($m in $manifests) {
  try { $doc = Get-Content -LiteralPath (Join-Path $m.FullName 'tracked-writes.json') -Raw | ConvertFrom-Json } catch { Write-Output "triage: REFUSED: $($m.Name) manifest unreadable ($($_.Exception.Message))"; $refused++; continue }
  foreach ($w in @($doc.writes)) {
    $file = "$($w.file)"
    if (($file -eq '') -or ($file -match '\.\.') -or ([System.IO.Path]::IsPathRooted($file)) -or ($file -notlike 'todo/*')) { Write-Output "triage: REFUSED: $file is not a TODO file the collector writes"; $refused++; continue }
    if (-not $byFile.Contains($file)) { $byFile[$file] = @() }
    foreach ($l in @($w.lines)) { $byFile[$file] = @($byFile[$file]) + @([pscustomobject]@{ Line = "$l"; Stamp = $m.Name }) }
  }
}
$ready = @()
$stampsReady = @()
foreach ($file in @($byFile.Keys)) {
  $full = Join-Path $Root $file
  $head = ((git -C $Root show "HEAD:$file" 2>$null) | Out-String)
  if ($LASTEXITCODE -ne 0) { Write-Output "triage: REFUSED: $file is not tracked at HEAD"; $refused++; continue }
  $work = [System.IO.File]::ReadAllText($full)
  $pendingRows = @(@($byFile[$file]) | Where-Object { -not $head.Contains($_.Line) })
  if ($pendingRows.Count -eq 0) { Write-Output "triage: $file already carries every recorded line"; continue }
  $pending = @($pendingRows | ForEach-Object { $_.Line })
  $from = @($pendingRows | ForEach-Object { $_.Stamp } | Sort-Object -Unique)
  if (-not (Test-TrackedWriteOnly $head $work $pending)) { Write-Output "triage: REFUSED: $file differs from HEAD beyond the $($pending.Count) recorded line(s) of $($from -join ', '); commit or revert the other change first"; $refused++; continue }
  $ready += $file
  foreach ($st in $from) { if ($stampsReady -notcontains $st) { $stampsReady += $st } }
  Write-Output "triage: $file ready ($($pending.Count) line(s) from $($from -join ', '))"
}
if ($refused -gt 0) { Write-Output "triage: $refused file(s) REFUSED; nothing committed"; exit 1 }
if ($ready.Count -eq 0) { Write-Output 'triage: nothing to commit'; exit 0 }
if (-not $Commit) { Write-Output "triage: plan only; re-run with -Commit to commit $($ready.Count) file(s)"; exit 0 }
# Claude Code is the only writer (AGENTS.md, operator decision
# 2026-09-23; section 45 R1-F1): the commit runs only inside a Claude
# Code session, whose id rides the commit message.
if ("$env:CLAUDE_CODE_SESSION_ID" -eq '') { Write-Output 'triage: REFUSED: -Commit runs only inside a Claude Code session (CLAUDE_CODE_SESSION_ID unset); the plan above stands; nothing committed'; exit 1 }
$msg = "nightly: record the collector lines of $(@($stampsReady | Sort-Object) -join ', ')"
$out = @(git -C $Root commit --only -m $msg -m "Claude-Session: $env:CLAUDE_CODE_SESSION_ID" -- @ready 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { Write-Output "triage: commit FAILED: $(($out | Select-Object -Last 2) -join '; ')"; exit 1 }
Write-Output "triage: committed $($ready.Count) file(s): $msg"
exit 0
