#Requires -Version 5.1
<#
.SYNOPSIS
  Acknowledgement helper for the governed nightly (D00 T02 section 31).

.DESCRIPTION
  -Draft writes a v2 acknowledgement for one RED run identity: it reads
  the run's current result copy (checksum, incident ids), fills the
  disposition, finding, owners, and a due date, and validates the draft
  with Test-AckV2 plus the disposition-evidence rule before anything is
  written; an invalid draft is refused with its errors and no file.

  -FileOverdue turns the gate's staged ack-overdue stubs into durable
  work: it computes the overdue operational demands exactly as the
  nightly does and updates docs/nightly-acks/overdue-findings.md (one
  row per run, created once, updated on later nights, marked acked when
  the run is acknowledged). With -Commit it commits that file; a failed
  commit writes build/nightly/ack-filing-retry.json and exits 1, and
  the next -FileOverdue retries the commit first.
#>
param(
  [switch]$Draft,
  [switch]$FileOverdue,
  [switch]$Commit,
  [string]$Run = '',
  [string]$Disposition = '',
  [string]$Finding = '',
  [string]$Evidence = '',
  [string]$Owner = '',
  [string]$CorrectiveOwner = '',
  [string]$Due = '',
  [string[]]$Cover = @(),
  [switch]$CoversAll,
  [string]$Out = '',
  [string]$Today = '',
  [string]$WorkspaceRoot = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ($WorkspaceRoot -ne '') { $Root = (Resolve-Path $WorkspaceRoot).Path }
. (Join-Path $PSScriptRoot 'NightlyParse.ps1')
. (Join-Path $PSScriptRoot 'NightlyNotify.ps1')
# The nightly's own SLA rule (R1-I1), so filing and the gate agree.
$ackSla = { param($r) Get-AckSlaHours $r }
$nightDir = Join-Path $Root 'build\nightly'
$ackDir = Join-Path $Root 'docs\nightly-acks'
$now = if ($Today -ne '') { [datetime]::ParseExact($Today, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } else { Get-Date }
$files = @(Get-ChildItem $nightDir -Filter 'morning-*.result.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$files += @(Get-ChildItem (Join-Path $nightDir 'retained') -Filter 'result.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$demands = Get-AckDemands $files

if ($Draft) {
  if (($Run -eq '') -or ($Disposition -eq '') -or ($Owner -eq '')) { Write-Output 'ack: -Draft needs -Run, -Disposition, and -Owner'; exit 2 }
  if (-not $demands.ContainsKey($Run)) { Write-Output "ack: $Run is not a known RED (no red or cancelled result names it)"; exit 1 }
  $d = $demands[$Run]
  $signed = $now.ToString('yyyy-MM-dd')
  if ($Due -eq '') { $Due = $now.AddDays($script:AckDueDays).ToString('yyyy-MM-dd') }
  if ($CorrectiveOwner -eq '') { $CorrectiveOwner = $Owner }
  $incidents = if (@($d.Incidents).Count -gt 0) { @($d.Incidents) -join ', ' } else { 'none' }
  $lines = @('---', 'ack-version: 2', "run: $Run sha256:$($d.Current)", "incidents: $incidents", "owner: $Owner", "disposition: $Disposition")
  if ($Disposition -ne 'withdrawn') { $lines += @("corrective-owner: $CorrectiveOwner", "due: $Due", "finding: $Finding") }
  if ($Evidence -ne '') { $lines += "evidence: $Evidence" }
  # A run with several incidents needs per-incident coverage (R1-I2).
  if ($CoversAll) { $lines += 'covers-all: yes' }
  foreach ($c in @($Cover)) { if ("$c" -ne '') { $lines += "cover: $c" } }
  $lines += @("signed: $signed", '---', '', "# Acknowledgement: $Run", '', "Drafted by tools/NightlyAck.ps1 from the run's current result (checksum $($d.Current.Substring(0, 12))); state the cause and what the finding changes here before committing.")
  $text = ($lines -join "`n") + "`n"
  $v = Test-AckV2 $text $demands
  $errs = @($v.Errors)
  if ($v.Ok -and ($Disposition -ne 'withdrawn')) {
    $fm = Read-AckFrontmatter $text
    $errs += @(Test-DispositionEvidence $fm.Fields @($v.Acked) $demands $Root)
    $known = @()
    foreach ($k in @($demands.Keys)) { $known += @($demands[$k].Incidents) }
    if (-not (Test-FindingExists $Root $Finding $known)) { $errs += "finding $Finding not found" }
  }
  if (@($errs).Count -gt 0) { Write-Output "ack: draft refused ($(@($errs) -join '; ')); nothing written"; exit 1 }
  if ($Out -eq '') { $Out = Join-Path $ackDir ("ack-{0}.md" -f ($Run -replace '[^0-9A-Za-z-]', '-')) }
  if (Test-Path $Out) { Write-Output "ack: $Out exists; choose another -Out"; exit 1 }
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out)
  Write-AtomicReport @($text.TrimEnd("`n") -split "`n") $Out
  Write-Output "ack: drafted $Out (valid against the current result); commit it to count"
  exit 0
}

if ($FileOverdue) {
  $tablePath = Join-Path $ackDir 'overdue-findings.md'
  $retryPath = Join-Path $nightDir 'ack-filing-retry.json'
  $commitIt = {
    $eap = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $rel = $tablePath.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
      $null = git -C $Root add -- $rel 2>&1
      if ($LASTEXITCODE -ne 0) { return "git add failed" }
      $null = git -C $Root diff --cached --quiet -- $rel 2>&1
      if ($LASTEXITCODE -eq 0) { return '' }
      $null = git -C $Root commit -q -m "todo: file overdue acknowledgements ($($now.ToString('yyyy-MM-dd')))" -- $rel 2>&1
      if ($LASTEXITCODE -ne 0) { return "git commit failed (exit $LASTEXITCODE)" }
      return ''
    } finally { $ErrorActionPreference = $eap }
  }
  if ($Commit -and (Test-Path $retryPath)) {
    $err = & $commitIt
    if ($err -ne '') { Write-Output "ack: retry of the pending filing commit failed again ($err); $retryPath kept"; exit 1 }
    Remove-Item $retryPath -Force
    Write-Output 'ack: pending filing commit retried and landed'
  }
  $gate = Test-Acknowledgements $Root $ackDir $demands $now $ackSla
  $over = @($gate.Overdue | ForEach-Object { $d = $demands[$_]; [pscustomobject]@{ Id = $_; What = $(if ($d.Unreadable) { 'unreadable result' } else { "RED $($d.Day)" }); Incidents = $(if (@($d.Incidents).Count -gt 0) { @($d.Incidents) -join ' ' } else { 'none' }) } })
  $existing = if (Test-Path $tablePath) { @(Get-Content $tablePath -Encoding UTF8) } else { @() }
  $upd = Update-OverdueFindings $existing $over $now.ToString('yyyy-MM-dd')
  if (-not $upd.Changed) { Write-Output "ack: overdue findings unchanged ($(@($over).Count) overdue)"; exit 0 }
  $null = New-Item -ItemType Directory -Force -Path $ackDir
  Write-AtomicReport $upd.Lines $tablePath
  Write-Output "ack: overdue findings updated ($(@($over).Count) overdue) in $tablePath"
  if ($Commit) {
    $err = & $commitIt
    if ($err -ne '') {
      [pscustomobject]@{ table = $tablePath; failed = $now.ToString('o'); error = $err } | ConvertTo-Json | Set-Content -Path $retryPath -Encoding UTF8
      Write-Output "ack: filing commit failed ($err); retry recorded in $retryPath"
      exit 1
    }
    Write-Output 'ack: filing committed'
  }
  exit 0
}

Write-Output 'usage: NightlyAck.ps1 -Draft -Run <identity> -Disposition <d> -Owner <o> [-Finding <f>] [-Evidence <e>] [-Cover "INC-<id> <disposition> <finding>", ...] [-CoversAll] [-CorrectiveOwner <c>] [-Due YYYY-MM-DD] [-Out <path>] | -FileOverdue [-Commit] [-Today YYYY-MM-DD] [-WorkspaceRoot <dir>]'
exit 2
