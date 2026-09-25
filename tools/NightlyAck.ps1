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

  Section 39: -Commit runs only in the Claude writer session (AGENTS.md:
  Claude Code is the only writer; CLAUDECODE=1) and commits the overdue
  table alone, refusing when anything else is staged. A filing holds
  build/nightly/ack-filing.lock for its whole run, so a concurrent filing
  refuses, and a table written but never committed (a crash between the
  write and the commit) is committed by the next -FileOverdue -Commit.
  -Draft reports the draft pending until committed, and -Status -Run
  <id> reads whether a run is acknowledged now (effective), drafted but
  uncommitted (pending), or unacknowledged.
#>
param(
  [switch]$Draft,
  [switch]$FileOverdue,
  [switch]$Commit,
  [switch]$Status,
  [string]$Run = '',
  [string]$Disposition = '',
  [string]$Finding = '',
  [string]$Evidence = '',
  [string]$Owner = '',
  [string]$CorrectiveOwner = '',
  [string]$Due = '',
  [string]$Cover = '',
  [switch]$CoversAll,
  [string]$Out = '',
  [string]$Today = '',
  [int]$LockWaitSeconds = 60,
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
$demands = Get-AckDemands $files (Read-ResultClassifications $nightDir)

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
  # -Cover takes `INC-<id> <disposition> <finding>` entries separated by ';'.
  foreach ($c in @($Cover -split ';')) { if ("$c".Trim() -ne '') { $lines += "cover: $("$c".Trim())" } }
  $lines += @("signed: $signed", '---', '', "# Acknowledgement: $Run", '', "Drafted by tools/NightlyAck.ps1 from the run's current result (checksum $($d.Current.Substring(0, 12))); state the cause and what the finding changes here before committing.")
  $text = ($lines -join "`n") + "`n"
  $v = Test-AckV2 $text $demands
  $errs = @($v.Errors)
  # A draft whose coverage rejects the run it names is refused (section 46
  # item 11), even though the gate would still honor the file's other runs.
  foreach ($rj in @($v.Rejected)) { $errs += "rejects $($rj.Run): $($rj.Why)" }
  if ($v.Ok -and ($Disposition -ne 'withdrawn')) {
    # The gate's own evidence check (R2-F3), so a draft the helper
    # accepts is one the gate accepts once committed.
    $known = @()
    foreach ($k in @($demands.Keys)) { $known += @($demands[$k].Incidents) }
    $ledger = Read-IncidentLedger (Join-Path $nightDir 'incidents.json')
    if ($ledger.Ok) { $known += @($ledger.Incidents.Keys) }
    $errs += @(Test-AckEvidence $Root (Read-AckFrontmatter $text) @($v.Acked) $demands $known)
  }
  if (@($errs).Count -gt 0) { Write-Output "ack: draft refused ($(@($errs) -join '; ')); nothing written"; exit 1 }
  if ($Out -eq '') { $Out = Join-Path $ackDir ("ack-{0}.md" -f ($Run -replace '[^0-9A-Za-z-]', '-')) }
  if (Test-Path $Out) { Write-Output "ack: $Out exists; choose another -Out"; exit 1 }
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out)
  Write-AtomicReport @($text.TrimEnd("`n") -split "`n") $Out
  # Pending versus effective (section 39 item 12): recheck the checksum
  # against the result as it is now, and say what the gate will read
  # once the file is committed.
  $fresh = Get-AckDemands $files (Read-ResultClassifications $nightDir)
  if ($fresh[$Run].Current -ne $d.Current) { Write-Output "ack: drafted $Out, but $Run's result changed while drafting (now $($fresh[$Run].Current.Substring(0, 12))); redraft before committing"; exit 1 }
  # The whole gate with this draft assumed committed (R1-F5): ties,
  # duplicate cycles, and governance decide, not the checksum alone.
  $would = Test-Acknowledgements $Root $ackDir $fresh $now $ackSla (Split-Path -Leaf $Out)
  if ((@($would.Unacked) -contains $Run) -or (@($would.ProofUnacked) -contains $Run)) {
    $why = @($would.Lines | Where-Object { ($_ -like "*$Run*") -and (($_ -like '*TIE*') -or ($_ -like '*CYCLE*') -or ($_ -like '*INVALID*') -or ($_ -like '*released*')) })
    Write-Output "ack: drafted $Out, but the gate would NOT acknowledge $Run once committed ($(if ($why.Count) { $why -join '; ' } else { 'governed elsewhere' })); fix the draft before committing"
    exit 1
  }
  Write-Output "ack: drafted $Out; PENDING: the gate acknowledges $Run once this file is committed (checksum $($d.Current.Substring(0, 12)) still current)"
  exit 0
}

if ($Status) {
  if ($Run -eq '') { Write-Output 'ack: -Status needs -Run'; exit 2 }
  if (-not $demands.ContainsKey($Run)) { Write-Output "ack: $Run is not a demanded RED"; exit 1 }
  $gate = Test-Acknowledgements $Root $ackDir $demands $now $ackSla
  # The status view (section 46 item 13): the governing ack, each incident
  # with its pending state, the owners, the deadline, and every gate line
  # that blocks the run or its ack's actions.
  $d = $demands[$Run]
  $gov = if ($gate.Governing.ContainsKey($Run)) { "$($gate.Governing[$Run])" } else { '' }
  # The deadline the gate enforces (section 46 R1-I1), inheritance included.
  $dueNow = if ($gate.Dues.ContainsKey($Run)) { $gate.Dues[$Run] } else { Get-DemandDue $d $ackSla }
  Write-Output "status: $Run"
  Write-Output "  governing: $(if ($gov -ne '') { $gov } else { 'none' })"
  Write-Output "  deadline: $(if ($null -ne $dueNow) { $dueNow.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture) } else { 'unreadable (escalate operator)' })"
  $govClaim = $null
  if (($gov -ne '') -and $gate.Claims.ContainsKey($Run)) { $govClaim = @($gate.Claims[$Run] | Where-Object { $_.File -eq $gov }) | Select-Object -First 1 }
  if ($null -ne $govClaim) { Write-Output "  owners: owner $($govClaim.Fields['owner']), corrective-owner $($govClaim.Fields['corrective-owner'])" } else { Write-Output '  owners: none (no governing ack)' }
  # Every ack that ever claimed the run counts (section 46 R1-I2): a
  # superseded ack's open action still holds its incidents open.
  $files = @()
  if ($gate.Claims.ContainsKey($Run)) { $files = @($gate.Claims[$Run] | ForEach-Object { $_.File } | Sort-Object -Unique) }
  if (($gov -ne '') -and ($files -notcontains $gov)) { $files += $gov }
  # And every ack whose history ever named the run (section 46 R2-I1): an
  # ack edited to name another run still owes what it opened for this one.
  $eap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $relAcks = ($ackDir.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/'
    foreach ($nm in @(git -C $Root log --format= --name-only -S "run: $Run " -- $relAcks 2>$null)) { $leaf = Split-Path -Leaf "$nm"; if (($leaf -like 'ack-*.md') -and ($files -notcontains $leaf) -and (Test-Path (Join-Path $ackDir $leaf))) { $files += $leaf } }
  } catch { } finally { $ErrorActionPreference = $eap }
  $onFiles = { param($ln) @($files | Where-Object { $ln -like "*CORRECTIVE $_ (*" }).Count -gt 0 }
  foreach ($inc in @($d.Incidents)) {
    # A cover line answers for its own incident; otherwise each ack's
    # top-level action does.
    $mine = @($gate.Corrective | Where-Object { (& $onFiles $_) -and ($_ -like "* ($inc *") })
    $top = @($gate.Corrective | Where-Object { (& $onFiles $_) -and ($_ -notmatch 'CORRECTIVE \S+ \(INC-') })
    $all = @($mine) + @($top)
    $st = if ($files.Count -eq 0) { 'pending (no ack)' } elseif ($all.Count -eq 0) { 'closed (no action opened)' } elseif (@($all | Where-Object { $_ -like '*: closed (*' }).Count -eq $all.Count) { 'closed' } else { 'pending' }
    Write-Output "  incident $inc`: $st"
  }
  # A plain acknowledgement line blocks nothing; a stale, invalid, tie, or
  # open-action line does, from any ack that claimed the run.
  $block = @($gate.Lines | Where-Object { (($_ -like "*$Run*") -and (($_ -notmatch ': acknowledges ') -or ($_ -like '*STALE*'))) -or ((& $onFiles $_) -and ($_ -notlike '*: closed (*')) })
  if ($block.Count -eq 0) { Write-Output '  blocking: none' } else { foreach ($b in $block) { Write-Output "  blocking: $("$b".TrimStart('-', ' '))" } }
  if ((@($gate.Unacked) -notcontains $Run) -and (@($gate.ProofUnacked) -notcontains $Run)) { Write-Output "ack: $Run EFFECTIVE (acknowledged now)"; exit 0 }
  $pending = @($gate.Lines | Where-Object { ($_ -like '*: uncommitted*') -or ($_ -like '*edited since its last commit*') } | Where-Object { $ln = $_; $f = [regex]::Match($ln, '^- (\S+?):').Groups[1].Value; ($f -ne '') -and (Test-Path (Join-Path $ackDir $f)) -and ((Get-Content (Join-Path $ackDir $f) -Raw) -match [regex]::Escape("run: $Run ")) })
  if ($pending.Count -gt 0) { Write-Output "ack: $Run PENDING (a draft names it but is not committed: $($pending -join '; '))"; exit 1 }
  Write-Output "ack: $Run UNACKNOWLEDGED"
  exit 1
}

if ($FileOverdue) {
  $tablePath = Join-Path $ackDir 'overdue-findings.md'
  $retryPath = Join-Path $nightDir 'ack-filing-retry.json'
  $lockPath = Join-Path $nightDir 'ack-filing.lock'
  # Authority (section 39 item 9): only the Claude writer commits.
  if ($Commit -and ($env:CLAUDECODE -ne '1')) { Write-Output 'ack: -Commit runs only in the Claude writer session (AGENTS.md: Claude Code is the only writer); file without -Commit or run it from Claude Code'; exit 1 }
  # One filing at a time (section 39 item 8): the lock is held for the
  # whole filing and released at exit.
  $null = New-Item -ItemType Directory -Force -Path $nightDir
  $lock = $null
  # Concurrent filings both land (section 46 item 12): a filing waits for
  # the lock (bounded by -LockWaitSeconds) and then files against the
  # state as it is after the other one, instead of refusing.
  $waitUntil = (Get-Date).AddSeconds([math]::Max(0, $LockWaitSeconds))
  while ($null -eq $lock) {
    try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
      if ((Get-Date) -ge $waitUntil) { Write-Output "ack: another filing held $lockPath for $LockWaitSeconds s; retry when it finishes"; exit 1 }
      Start-Sleep -Milliseconds 250
    }
  }
  $rel = $tablePath.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
  $commitIt = {
    $eap = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      # Scope (section 39 item 9): nothing but the table may be staged.
      $others = @(git -C $Root diff --cached --name-only 2>$null | Where-Object { ("$_" -ne '') -and ("$_" -ne $rel) })
      if ($others.Count -gt 0) { return "refused: other files are staged ($($others -join ', ')); the filing commits $rel alone" }
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
    # A lost receipt (section 46 item 12): the commit landed but the retry
    # record survived (a crash after the commit, or a reported failure that
    # still committed). The table at HEAD already equals the filed table,
    # so the retry commits nothing and says which case it was.
    $eap = $ErrorActionPreference
    $atHead = ''
    try { $ErrorActionPreference = 'Continue'; $atHead = ((git -C $Root show "HEAD:$rel" 2>$null) | Out-String) } finally { $ErrorActionPreference = $eap }
    $onDisk = if (Test-Path $tablePath) { [System.IO.File]::ReadAllText($tablePath) } else { '' }
    if (($atHead -ne '') -and ((@($atHead -split "`r?`n" | Where-Object { $_ -ne '' }) -join "`n") -ceq (@($onDisk -split "`r?`n" | Where-Object { $_ -ne '' }) -join "`n"))) {
      Remove-Item $retryPath -Force
      Write-Output 'ack: lost commit receipt: the pending filing had already landed; nothing recommitted'
    }
  }
  if ($Commit -and (Test-Path $retryPath)) {
    $err = & $commitIt
    if ($err -ne '') { Write-Output "ack: retry of the pending filing commit failed again ($err); $retryPath kept"; $lock.Dispose(); exit 1 }
    Remove-Item $retryPath -Force
    Write-Output 'ack: pending filing commit retried and landed'
  }
  # A table written but never committed (section 39 item 8: a crash
  # between the write and the commit) is committed now.
  if ($Commit -and (Test-Path $tablePath)) {
    $eap = $ErrorActionPreference
    $dirty = @()
    try { $ErrorActionPreference = 'Continue'; $dirty = @(git -C $Root status --porcelain -- $rel 2>$null) } finally { $ErrorActionPreference = $eap }
    if ($dirty.Count -gt 0) {
      $err = & $commitIt
      if ($err -ne '') { Write-Output "ack: an uncommitted filing is pending and its commit failed ($err)"; $lock.Dispose(); exit 1 }
      Write-Output 'ack: an uncommitted filing from an interrupted run was committed'
    }
  }
  $gate = Test-Acknowledgements $Root $ackDir $demands $now $ackSla
  $over = @($gate.Overdue | ForEach-Object { $d = $demands[$_]; [pscustomobject]@{ Id = $_; What = $(if ($d.Unreadable) { 'unreadable result' } else { "RED $($d.Day)" }); Incidents = $(if (@($d.Incidents).Count -gt 0) { @($d.Incidents) -join ' ' } else { 'none' }) } })
  $existing = if (Test-Path $tablePath) { @(Get-Content $tablePath -Encoding UTF8) } else { @() }
  $ackedIds = @($demands.Keys | Where-Object { (@($gate.Unacked) -notcontains $_) -and (@($gate.ProofUnacked) -notcontains $_) })
  $upd = Update-OverdueFindings $existing $over $now.ToString('yyyy-MM-dd') 'operator' $ackedIds @($gate.Unacked)
  if (-not $upd.Changed) { Write-Output "ack: overdue findings unchanged ($(@($over).Count) overdue)"; $lock.Dispose(); exit 0 }
  $null = New-Item -ItemType Directory -Force -Path $ackDir
  Write-AtomicReport $upd.Lines $tablePath
  Write-Output "ack: overdue findings updated ($(@($over).Count) overdue) in $tablePath"
  if ($Commit) {
    $err = & $commitIt
    if ($err -ne '') {
      [pscustomobject]@{ table = $tablePath; failed = $now.ToString('o'); error = $err } | ConvertTo-Json | Set-Content -Path $retryPath -Encoding UTF8
      Write-Output "ack: filing commit failed ($err); retry recorded in $retryPath"
      $lock.Dispose()
      exit 1
    }
    Write-Output 'ack: filing committed'
  }
  $lock.Dispose()
  exit 0
}

Write-Output 'usage: NightlyAck.ps1 -Status -Run <identity> | -Draft -Run <identity> -Disposition <d> -Owner <o> [-Finding <f>] [-Evidence <e>] [-Cover "INC-<id> <disposition> <finding>; ..."] [-CoversAll] [-CorrectiveOwner <c>] [-Due YYYY-MM-DD] [-Out <path>] | -FileOverdue [-Commit] [-Today YYYY-MM-DD] [-WorkspaceRoot <dir>]'
exit 2
