# Build evidence and UI test population (split out of the nightly tooling on 2026-10-18).
# Dot-sourced by Write-CompileEvidence.ps1 and Write-BuildInputsDigest.ps1 (every
# build), Test-TestPopulation.ps1 (CI) and Update-TestFingerprint.ps1. Pure functions:
# no network, no schedule, nothing written except by the explicit writers.
$ErrorActionPreference = 'Stop'

function Read-TestPopulationFile([string]$Path, [switch]$AllowPrevious) {
  # Strict reader for tests/UI/TestPopulation.fingerprint (D00 T02 §15,
  # D00-T02-S13-PR13): filters, sorted member FQNs, and method plus
  # case counts per leg. Malformed input fails closed (Ok false with
  # the cause); item counts must equal their method counts.
  $bad = { param($why) return [pscustomobject]@{ Ok = $false; Error = $why } }
  if (-not (Test-Path $Path)) { return (& $bad "fingerprint missing: $Path") }
  $filters = @{}
  $counts = @{}
  $runA = @()
  $runB = @()
  $interactive = @()
  $rows = @{ 'run-a' = @(); 'run-b' = @(); 'interactive' = @() }
  $section = ''
  foreach ($raw in (Get-Content $Path)) {
    $ln = $raw.Trim()
    if (($ln -eq '') -or $ln.StartsWith('#')) { continue }
    if ($ln -eq 'run-a:') { $section = 'run-a'; continue }
    if ($ln -eq 'run-b:') { $section = 'run-b'; continue }
    if ($ln -eq 'interactive:') { $section = 'interactive'; continue }
    $rm = [regex]::Match($ln, '^(run-a|run-b|interactive)-case-rows:$')
    if ($rm.Success) { $section = 'rows:' + $rm.Groups[1].Value; continue }
    if ($section.StartsWith('rows:') -and ($raw -match '^  \S')) { $rows[$section.Substring(5)] += $ln; continue }
    $kv = [regex]::Match($ln, '^([a-z-]+):\s*(.+)$')
    if ($kv.Success -and ($raw -notmatch '^\s')) {
      $section = ''
      $filters[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim()
      continue
    }
    if (($section -eq 'run-a') -and ($raw -match '^  \S')) { $runA += $ln; continue }
    if (($section -eq 'run-b') -and ($raw -match '^  \S')) { $runB += $ln; continue }
    if (($section -eq 'interactive') -and ($raw -match '^  \S')) { $interactive += $ln; continue }
    return (& $bad "fingerprint malformed line: $raw")
  }
  # The format version first (D00 T02 §44 item 7).
  $ver = if ($filters.ContainsKey('schema')) { $filters['schema'] } else { 'missing (count-only format)' }
  # Compatibility (D00 T02 section 52 item 10): the checker, the nightly,
  # and the collector read the current version only; a historical proof
  # reader passes -AllowPrevious to read the versions the table lists as
  # readable, and the result names the version it read.
  $readable = ($ver -eq $script:PopulationSchema) -or ($AllowPrevious -and ($script:PopulationSchemaPrevious -contains $ver))
  if (-not $readable) { return (& $bad "fingerprint schema $ver is not $script:PopulationSchema; regenerate: $script:PopulationRegen") }
  foreach ($k in @('run-a-filter', 'run-b-filter', 'interactive-filter')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
  }
  foreach ($k in @('run-a-methods', 'run-a-cases', 'run-b-methods', 'run-b-cases', 'interactive-methods', 'interactive-cases')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
    $n = 0
    if (-not [int]::TryParse($filters[$k], [ref]$n)) { return (& $bad "fingerprint bad count ${k}: $($filters[$k])") }
    $counts[$k] = $n
  }
  if ($runA.Count -ne $counts['run-a-methods']) { return (& $bad "fingerprint run-a items $($runA.Count) != methods $($counts['run-a-methods'])") }
  if ($runB.Count -ne $counts['run-b-methods']) { return (& $bad "fingerprint run-b items $($runB.Count) != methods $($counts['run-b-methods'])") }
  if ($interactive.Count -ne $counts['interactive-methods']) { return (& $bad "fingerprint interactive items $($interactive.Count) != methods $($counts['interactive-methods'])") }
  # Case identity (D00 T02 section 37 item 5): each leg's case rows hash,
  # so a Theory row swapped at an equal total still drifts.
  foreach ($k in @('run-a-case-hash', 'run-b-case-hash', 'interactive-case-hash')) {
    if (-not $filters.ContainsKey($k)) { return (& $bad "fingerprint missing $k") }
  }
  return [pscustomobject]@{ Ok = $true; Error = ''; Schema = $ver; RunA = $runA; RunAFilter = $filters['run-a-filter']; RunBFilter = $filters['run-b-filter']; InteractiveFilter = $filters['interactive-filter']; RunB = $runB; Interactive = $interactive; RunAMethods = $counts['run-a-methods']; RunACases = $counts['run-a-cases']; RunBMethods = $counts['run-b-methods']; RunBCases = $counts['run-b-cases']; InteractiveMethods = $counts['interactive-methods']; InteractiveCases = $counts['interactive-cases']; RunACaseHash = $filters['run-a-case-hash']; RunBCaseHash = $filters['run-b-case-hash']; InteractiveCaseHash = $filters['interactive-case-hash']; RunACaseRows = @($rows['run-a']); RunBCaseRows = @($rows['run-b']); InteractiveCaseRows = @($rows['interactive']) }
}

function Get-CaseIdentityRows($Cases, [string]$Assembly = 'UI') {
  # The case-row representation (D00 T02 §44 item 2): each row is
  # `<assembly>|<display name>` (the display name carries the Theory
  # arguments in xunit's deterministic encoding), rows sort ordinally, and
  # a display name listed twice keeps both rows (the second reads
  # `#2`), so duplicates count and discovery order never matters.
  $list = New-Object 'System.Collections.Generic.List[string]'
  foreach ($c in @($Cases)) { if ($null -ne $c) { $list.Add("$c") } }
  $list.Sort([StringComparer]::Ordinal)
  $rows = @()
  $seen = @{}
  foreach ($c in $list) {
    $k = "$c"
    $n = if ($seen.ContainsKey($k)) { $seen[$k] + 1 } else { 1 }
    $seen[$k] = $n
    $rows += $(if ($n -gt 1) { "$Assembly|$c#$n" } else { "$Assembly|$c" })
  }
  return $rows
}

function Get-CanonicalCaseRows($Cases, [scriptblock]$Runner) {
  # Canonical identity for argument text a display name leaves out (D00
  # T02 section 52 item 3, replacing section 44's args-source digest).
  # xunit cuts a long argument at 50 characters and marks the cut with an
  # ellipsis (U+00B7 x3 or '...'); each method with such a row adds one
  # `case <Type.Method>(<args>)` row per case, read by tools/CaseIdentity
  # from the built assembly's data values (compile-time constants and
  # data-source values, encoded by rule; identical rows numbered), so an
  # argument changed past the cut changes the identity wherever its value
  # comes from. $Runner takes the method names and returns the tool's
  # lines plus its exit code; a `REFUSE` line or a nonzero exit throws by
  # name, so an unencodable argument never reads as an identity.
  # Every parameterized case (section 52 R1-C2), cut or not: identity
  # never depends on how xunit formats a display name, and an argument no
  # rule covers refuses wherever it appears.
  $methods = @(@($Cases) | Where-Object { "$_".Contains('(') } | ForEach-Object { ("$_" -split '\(', 2)[0].Trim() } | Sort-Object -Unique)
  if ($methods.Count -eq 0) { return @() }
  $res = & $Runner $methods
  $lines = @("$($res.Text)" -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
  $refused = @($lines | Where-Object { $_ -like 'REFUSE *' })
  if ($refused.Count -gt 0) { throw "case identity refused: $($refused -join '; ')" }
  if ([int]$res.Code -ne 0) { throw "case identity failed (exit $($res.Code)): $($lines -join ' | ')" }
  $rows = @($lines | ForEach-Object { "case $_" })
  foreach ($m in $methods) {
    if (-not (@($rows) | Where-Object { $_.StartsWith("case $m(", [StringComparison]::Ordinal) })) { throw "case identity refused: $m listed parameterized rows but the tool returned none" }
  }
  return $rows
}

function Get-CaseIdentityRunner([string]$Csproj, [int]$TimeoutSeconds = 120) {
  # The real runner: tools/CaseIdentity (built with the solution into
  # Bin/CaseIdentity/Debug) over the project's built Debug assembly,
  # bounded like every toolchain call. A missing tool or assembly throws
  # with the build instruction.
  $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Csproj))
  $name = [System.IO.Path]::GetFileNameWithoutExtension($Csproj)
  $tool = Join-Path $root 'Bin\CaseIdentity\Debug\CaseIdentity.exe'
  $asm = Join-Path $root "Bin\$name\Debug\$name.dll"
  $cap = $TimeoutSeconds
  return {
    param($methods)
    if (-not (Test-Path -LiteralPath $tool)) { throw "case identity tool missing: $tool; run: dotnet build src/ScratchPad.slnx, then retry" }
    if (-not (Test-Path -LiteralPath $asm)) { throw "case identity assembly missing: $asm; run: dotnet build src/ScratchPad.slnx, then retry" }
    $r = Invoke-BoundedCapture $tool (@($asm) + @($methods)) $root $cap
    if ($r.Killed) { throw "case identity timed out after ${cap}s" }
    return $r
  }.GetNewClosure()
}

function Merge-AttemptNames($Attempts) {
  # Executed names over several attempts of one run (D00 T02 section 44
  # R1-F2): a retry re-executes the cases it covers, so each name counts
  # at its highest count in any one attempt, never the sum, and a retried
  # case never discharges an unexecuted twin.
  $best = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  foreach ($attempt in @($Attempts)) {
    $one = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
    foreach ($n in @($attempt)) { if ($null -ne $n) { $k = "$n".Trim(); $one[$k] = $(if ($one.ContainsKey($k)) { $one[$k] } else { 0 }) + 1 } }
    foreach ($k in $one.Keys) { if ((-not $best.ContainsKey($k)) -or ($one[$k] -gt $best[$k])) { $best[$k] = $one[$k] } }
  }
  $out = @()
  foreach ($k in $best.Keys) { for ($i = 0; $i -lt $best[$k]; $i++) { $out += $k } }
  return $out
}

function Get-CaseHash($Cases) {
  # Case-row identity: SHA-256 over the identity rows (Get-CaseIdentityRows:
  # assembly-qualified, ordinal-sorted, duplicates counted), first 16 hex;
  # 'none' when the discovery carries no case list (fixtures built by hand).
  if ($null -eq $Cases) { return 'none' }
  # Ordinal identity (D00 T02 section 37 R2-F1): PowerShell sorting and
  # uniqueness ignore case, which would fold rows differing only by a
  # string argument's casing.
  $text = (@(Get-CaseIdentityRows $Cases) -join "`n")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
  return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 16).ToLowerInvariant()
}

# The fingerprint format (D00 T02 §44 item 7): readers refuse any other
# version with the regen command, so an old count-only file never reads.
# population/3 (D00 T02 section 52 item 3) carries canonical `case` rows
# for display names xunit cut, where population/2 carried an
# args-source digest; its layout is otherwise the same. The migration
# contract (section 52 item 10, docs/testing.md): producers write only
# the current version; the checker, the nightly, and the collector
# accept only it (a previous file refuses with the regen command);
# historical proof readers accept the previous versions listed here,
# and a proof bound under another version reads stale with the schema
# named (Get-ProofBinding records it), never as the same population.
# Owed debt names cases by display name and is schema-independent.
$script:PopulationSchema = 'population/3'
$script:PopulationSchemaPrevious = @('population/2')
$script:PopulationRegen = 'powershell -File tools/Update-TestFingerprint.ps1 (after a fresh build)'

function Get-DiscoveryCaseRows($Discovery, [string]$Leg) {
  $p = $Discovery.PSObject.Properties[$Leg + 'CaseRows']
  if ($null -eq $p -or $null -eq $p.Value) { return @() }
  return @($p.Value)
}

function Get-DiscoveryCaseHash($Discovery, [string]$Leg) {
  $p = $Discovery.PSObject.Properties[$Leg + 'CaseHash']
  if ($null -eq $p -or [string]::IsNullOrEmpty("$($p.Value)")) { return 'none' }
  return "$($p.Value)"
}

function Write-TestPopulationFile([string]$Path, [string]$RunAFilter, [string]$RunBFilter, [string]$InteractiveFilter, $Discovery) {
  # Canonical writer for the fingerprint (D00 T02 §15, D00-T02-S13-PR13):
  # filters, sorted unique member FQNs, method plus case counts. Atomic
  # via same-volume rename; $Discovery carries RunA/RunB/Interactive
  # method lists plus the six counts. The header § emits by code point:
  # Windows PowerShell reads BOM-less scripts as ANSI, so a literal §
  # double-encodes on write (D00 T02 §15 R2-F7).
  $lines = @(
    "# Nightly UI test population fingerprint (D00 T02 $([char]0xA7)15, D00-T02-S13-PR13).",
    '# One --list-tests discovery per leg filter; member FQNs sorted unique.',
    '# Regen: tools/Update-TestFingerprint.ps1 (build first). Review the diff:',
    '# every membership change stales prior proofs until re-accepted here.',
    "schema: $script:PopulationSchema",
    "run-a-filter: $RunAFilter",
    "run-b-filter: $RunBFilter",
    "interactive-filter: $InteractiveFilter",
    'run-a:'
  )
  foreach ($m in (@($Discovery.RunA) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-a-methods: $($Discovery.RunAMethods)"
  $lines += "run-a-cases: $($Discovery.RunACases)"
  $lines += "run-a-case-hash: $(Get-DiscoveryCaseHash $Discovery 'RunA')"
  $lines += 'run-a-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'RunA')) { $lines += "  $r" }
  $lines += 'run-b:'
  foreach ($m in (@($Discovery.RunB) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "run-b-methods: $($Discovery.RunBMethods)"
  $lines += "run-b-cases: $($Discovery.RunBCases)"
  $lines += "run-b-case-hash: $(Get-DiscoveryCaseHash $Discovery 'RunB')"
  $lines += 'run-b-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'RunB')) { $lines += "  $r" }
  $lines += 'interactive:'
  foreach ($m in (@($Discovery.Interactive) | Sort-Object -Unique)) { $lines += "  $m" }
  $lines += "interactive-methods: $($Discovery.InteractiveMethods)"
  $lines += "interactive-cases: $($Discovery.InteractiveCases)"
  $lines += "interactive-case-hash: $(Get-DiscoveryCaseHash $Discovery 'Interactive')"
  $lines += 'interactive-case-rows:'
  foreach ($r in @(Get-DiscoveryCaseRows $Discovery 'Interactive')) { $lines += "  $r" }
  $tmp = "$Path.tmp"
  $lines -join "`r`n" | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
}

function Compare-TestPopulation([string]$FingerprintPath, $Discovery, [string]$ExclusionLedger = '', $Today = $null) {
  # Fingerprint comparison (D00 T02 §15): live discovery must equal the
  # accepted members plus counts. Any drift reds with names; malformed
  # input fails closed. Returns Ok plus Drifts.
  $drifts = @()
  $fp = Read-TestPopulationFile $FingerprintPath
  if (-not $fp.Ok) { return [pscustomobject]@{ Ok = $false; Drifts = @($fp.Error) } }
  foreach ($leg in @(@('run-a', $fp.RunA, $Discovery.RunA), @('run-b', $fp.RunB, $Discovery.RunB), @('interactive', $fp.Interactive, $Discovery.Interactive))) {
    $added = @(Compare-Object $leg[1] $leg[2] | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
    $removed = @(Compare-Object $leg[1] $leg[2] | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })
    foreach ($a in ($added | Select-Object -First 5)) { $drifts += "$($leg[0]) added: $a" }
    if ($added.Count -gt 5) { $drifts += "$($leg[0]) added: ... ($($added.Count) total)" }
    foreach ($r in ($removed | Select-Object -First 5)) { $drifts += "$($leg[0]) removed: $r" }
    if ($removed.Count -gt 5) { $drifts += "$($leg[0]) removed: ... ($($removed.Count) total)" }
  }
  # Every count pair, methods and cases per leg (D00 T02 §29: run-b and
  # interactive methods were unchecked, so a methods-only drift passed).
  $pairs = @( @('run-a-methods', $fp.RunAMethods, $Discovery.RunAMethods), @('run-a-cases', $fp.RunACases, $Discovery.RunACases), @('run-b-methods', $fp.RunBMethods, $Discovery.RunBMethods), @('run-b-cases', $fp.RunBCases, $Discovery.RunBCases), @('interactive-methods', $fp.InteractiveMethods, $Discovery.InteractiveMethods), @('interactive-cases', $fp.InteractiveCases, $Discovery.InteractiveCases) )
  foreach ($p in $pairs) {
    if ($p[1] -ne $p[2]) { $drifts += "$($p[0]): fingerprinted $($p[1]) vs discovered $($p[2])" }
  }
  foreach ($h in @(@('run-a', $fp.RunACaseHash, 'RunA'), @('run-b', $fp.RunBCaseHash, 'RunB'), @('interactive', $fp.InteractiveCaseHash, 'Interactive'))) {
    $live = Get-DiscoveryCaseHash $Discovery $h[2]
    if ($h[1] -ne $live) {
      $drifts += "$($h[0]) case rows changed: fingerprinted hash $($h[1]) vs discovered $live"
      # The rows themselves (D00 T02 §44 item 8): which cases were added
      # and removed, and the command that re-accepts them.
      $was = @($fp.($h[2] + 'CaseRows'))
      $now = @(Get-DiscoveryCaseRows $Discovery $h[2])
      if (($was.Count -gt 0) -or ($now.Count -gt 0)) {
        $addedRows = @($now | Where-Object { $was -cnotcontains $_ })
        $removedRows = @($was | Where-Object { $now -cnotcontains $_ })
        foreach ($r in ($removedRows | Select-Object -First 5)) { $drifts += "$($h[0]) case removed: $r" }
        if ($removedRows.Count -gt 5) { $drifts += "$($h[0]) case removed: ... ($($removedRows.Count) total)" }
        foreach ($r in ($addedRows | Select-Object -First 5)) { $drifts += "$($h[0]) case added: $r" }
        if ($addedRows.Count -gt 5) { $drifts += "$($h[0]) case added: ... ($($addedRows.Count) total)" }
      }
      $drifts += "$($h[0]) re-accept after review: $script:PopulationRegen"
    }
  }
  if ($Discovery.RunAMethods -ne @($Discovery.RunA).Count) { $drifts += 'discovery run-a method list disagrees with its count (internal error)' }
  if ($Discovery.RunBMethods -ne @($Discovery.RunB).Count) { $drifts += 'discovery run-b method list disagrees with its count (internal error)' }
  if ($Discovery.InteractiveMethods -ne @($Discovery.Interactive).Count) { $drifts += 'discovery interactive method list disagrees with its count (internal error)' }
  # Exclusions (D00 T02 section 52 item 4): a discovery that carries the
  # all-cases listing checks every excluded case against the ledger
  # beside the fingerprint's repo (docs/test-exclusions.md).
  if ($null -ne $Discovery.PSObject.Properties['Excluded']) {
    if ($ExclusionLedger -eq '') { $ExclusionLedger = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent ([System.IO.Path]::GetFullPath($FingerprintPath))))) 'docs\test-exclusions.md' }
    $when = if ($null -ne $Today) { [datetime]$Today } else { Get-Date }
    $drifts += @(Test-ExclusionLedger @($Discovery.Excluded) (Read-ExclusionLedger $ExclusionLedger) $when)
  }
  return [pscustomobject]@{ Ok = ($drifts.Count -eq 0); Drifts = $drifts }
}

function Invoke-BoundedCapture([string]$Exe, [string[]]$ArgList, [string]$WorkDir, [int]$TimeoutSeconds) {
  # Bounded toolchain capture (D00 T02 §15 R3-F3): runs $Exe with a
  # wall cap and returns its stdout plus exit code; a hang kills the
  # job and reports Killed, so no toolchain invocation strands the run
  # past its deadline. Same job shape as Invoke-BootstrapStep, plus
  # captured output and a code file for the exit relay.
  $codeFile = Join-Path ([System.IO.Path]::GetTempPath()) ("bounded-$([Guid]::NewGuid().ToString('N')).code")
  $capJob = Start-Job -ScriptBlock {
    param($exe, $argList, $dir, $codeOut)
    Set-Location $dir
    # Output decodes as UTF-8 whatever the console codepage (D00 T02
    # section 44 R1-F1), so listed names never vary by host.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $out = & $exe @argList 2>&1 | Out-String
    $LASTEXITCODE | Set-Content -Path $codeOut
    $out
  } -ArgumentList @($Exe, $ArgList, $WorkDir, $codeFile)
  $doneSignal = Wait-Job -Job $capJob -Timeout $TimeoutSeconds
  $killed = ($null -eq $doneSignal)
  if ($killed -and ($capJob.State -eq 'Running')) { Stop-Job -Job $capJob }
  $null = Wait-Job -Job $capJob -Timeout 60
  $text = ''
  try { $text = Receive-Job -Job $capJob | Out-String } catch { $text = "bounded capture receive failed: $($_.Exception.Message)" }
  Remove-Job -Job $capJob -Force
  $code = 1
  if (Test-Path $codeFile) {
    $rawCode = Get-Content $codeFile -Raw
    if (($null -eq $rawCode) -or ($rawCode.Trim() -eq '')) { $code = 0 } else { $code = [int]$rawCode.Trim() }
    Remove-Item $codeFile -Force
  }
  if ($killed) { $code = 1 }
  return [pscustomobject]@{ Text = $text; Code = $code; Killed = $killed }
}

function Invoke-WithForcedDiscovery([scriptblock]$Body) {
  # Discovery-time environment (D00 T02 section 29, section 37 items 3
  # and 4): the Interactive force opens the quiet-hours fence and the
  # listing variable lifts every gated Theory's discovery-time skip, so a
  # listing expands the same rows on every host at any hour. Both prior
  # values come back whatever the body does: a prior unset stays unset,
  # and a body that throws still restores before the throw propagates.
  $names = @('SCRATCHPAD_INTERACTIVE_FORCE', 'SCRATCHPAD_DISCOVERY_LISTING')
  $prior = @{}
  foreach ($n in $names) { $prior[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
  try {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, '1', 'Process') }
    return (& $Body)
  } finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $prior[$n], 'Process') }
  }
}

function Get-ListTestsCases([string]$Dotnet, [string]$Csproj, [string]$Filter, [string]$What, [int]$TimeoutSeconds = 180, [scriptblock]$CaseRunner = $null) {
  # One --list-tests run against built binaries, parsed to sorted
  # unique method FQNs (theory case suffixes cut at the first paren)
  # with method plus case counts. Shared by population discovery
  # (PR13) and cut-work handoff (PR10). Bounded (D00 T02 §15 R3-F3): a
  # hang throws like a failure, so hung discovery cannot strand the run
  # past its deadline. Failure throws with $What naming the caller;
  # callers report on their red path.
  # Time-independent discovery (D00 T02 §29): outside the quiet window a
  # fenced Theory lists as one skipped case instead of its rows, so a
  # daytime regen undercounted what the 02:30 night discovers. The force
  # variable makes the fence attributes expand everywhere; the prior
  # value is restored whatever happens.
  $cap = Invoke-WithForcedDiscovery { Invoke-BoundedCapture $Dotnet @('test', $Csproj, '--no-build', '--nologo', '--filter', $Filter, '--list-tests') (Split-Path -Parent $Csproj) $TimeoutSeconds }
  if ($cap.Killed) { throw "discovery timed out for $What filter '$Filter' after ${TimeoutSeconds}s" }
  $text = $cap.Text
  if ($cap.Code -ne 0) { throw "discovery failed for $What filter '$Filter': $text" }
  $methods = @()
  $caseNames = @()
  $cases = 0
  foreach ($ln in ($text -split "`r?`n")) {
    $m = [regex]::Match($ln, '^    (\S[^(]*?)(?: \(|\(|$)')
    if (-not $m.Success) { continue }
    $cases++
    $caseNames += $ln.Trim()
    $fq = $m.Groups[1].Value.Trim()
    if ($methods -notcontains $fq) { $methods += $fq }
  }
  $methods = @($methods | Sort-Object -Unique)
  # A display name cut short hides the rest of its arguments (section 44
  # R1-F1): each method with a truncated row adds its canonical case rows
  # (section 52 item 3), so changing an argument past the cut changes the
  # identity.
  $identity = @($caseNames) + @(Get-CanonicalCaseRows $caseNames $(if ($null -ne $CaseRunner) { $CaseRunner } else { Get-CaseIdentityRunner $Csproj }))
  return [pscustomobject]@{ Methods = $methods; MethodCount = $methods.Count; CaseCount = $cases; Cases = $caseNames; CaseHash = (Get-CaseHash $identity); CaseRows = @(Get-CaseIdentityRows $identity) }
}

function Test-UiBuildFresh([datetime]$BinaryTimeUtc, [datetime]$NewestSourceTimeUtc, [string]$BinaryPath) {
  # Stale-build refusal (D00 T02 §29): discovery reads the built UI
  # binaries, so a test source newer than the binary means the counts
  # would describe an older tree. Returns Ok plus the instruction.
  if ($BinaryTimeUtc -lt $NewestSourceTimeUtc) {
    return [pscustomobject]@{ Ok = $false; Error = "UI build is stale: $BinaryPath ($($BinaryTimeUtc.ToString('u'))) is older than the newest tests/UI source ($($NewestSourceTimeUtc.ToString('u'))); run: dotnet build src/ScratchPad.slnx, then retry" }
  }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

function Get-UiBuildInputs([string]$Root, [string]$Start = '', [switch]$NoReferences) {
  # Every build input of the UI binaries (D00 T02 section 37 item 2):
  # tests/UI plus each project it references, transitively (sources,
  # XAML, project files), plus the shared build inputs at the root
  # (Directory.Build.*, Directory.Packages.props, global.json,
  # NuGet.config, .editorconfig). Configuration identity: discovery reads
  # Bin/UI/Debug, the configuration the nightly builds (its snapshot line
  # says config Debug), so a Release-only build reads as missing or stale.
  # R1-F2: besides each project directory, every ancestor
  # Directory.Build.* between a project and the root, every file an
  # MSBuild file imports (<Import Project>), and every linked item outside
  # the project directory (Compile, None, Content, Page, EmbeddedResource,
  # Manifest, and the other file item types) count, followed transitively.
  # Paths built from MSBuild properties resolve against the built-in
  # directory properties and every literal property the visited files
  # define (R2-F2); a path that still names an unresolved property lands
  # in $script:UiBuildUnresolved, and freshness refuses rather than skip it.
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $dirs = @()
  $extra = @{}
  $props = @{}
  $pending = New-Object System.Collections.Generic.List[object]
  $queue = New-Object System.Collections.Generic.Queue[string]
  # One project's own inputs (section 52 R1-A1): -Start names the
  # project and -NoReferences stays inside it (its imports, linked items,
  # and the shared root inputs still count).
  $queue.Enqueue($(if ($Start -ne '') { $Start } else { (Join-Path $Root 'tests\UI\UI.csproj') }))
  $seen = @{}
  do {
  while ($queue.Count -gt 0) {
    $file = [System.IO.Path]::GetFullPath($queue.Dequeue())
    if ($seen.ContainsKey($file) -or -not (Test-Path $file)) { continue }
    $seen[$file] = $true
    $extra[$file] = $true
    $here = Split-Path -Parent $file
    $text = Get-Content $file -Raw
    # A property's own $(MSBuildThisFileDirectory) is its defining file's
    # directory, fixed where it is defined (R3-F2); two different
    # definitions of one name make it ambiguous, and a path using it
    # stays unresolved instead of guessing evaluation order.
    foreach ($pm in [regex]::Matches($text, '<([A-Za-z_][\w.]*)>([^<]*)</\1>')) {
      $pn = $pm.Groups[1].Value
      $pv = $pm.Groups[2].Value.Trim().Replace('$(MSBuildThisFileDirectory)', ($here.TrimEnd('\') + '\'))
      if (-not $props.ContainsKey($pn)) { $props[$pn] = $pv }
      elseif ($props[$pn] -ne $pv) { $props[$pn] = '$(__ambiguous__' + $pn + ')' }
    }
    if ($file -like '*proj') {
      $dirs += $here
      foreach ($m in [regex]::Matches($text, '<ProjectReference\s+Include="([^"]+)"')) { if ($NoReferences) { continue }; $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'queue'; From = $file }) }
      $d = $here
      while ($d.Length -ge $rootFull.Length) {
        foreach ($n in @('Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props')) {
          $f = Join-Path $d $n
          if (Test-Path $f) { $queue.Enqueue($f) }
        }
        $parent = Split-Path -Parent $d
        if ([string]::IsNullOrEmpty($parent) -or ($parent -eq $d)) { break }
        $d = $parent
      }
    }
    foreach ($m in [regex]::Matches($text, '<Import\s+Project="([^"]+)"')) { $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'queue'; From = $file }) }
    foreach ($m in [regex]::Matches($text, '<(?:Compile|None|Content|Page|EmbeddedResource|ApplicationDefinition|Manifest|Resource|AdditionalFiles|PRIResource)\s+Include="([^"]+)"')) {
      $pending.Add(@{ Dir = $here; Raw = $m.Groups[1].Value; Kind = 'file'; From = $file })
    }
  }
  # The queue drained: resolve what the files seen so far reference, now
  # that their literal properties are known; newly queued files may
  # define more, so drain and resolve again until nothing new arrives.
  $later = New-Object System.Collections.Generic.List[object]
  foreach ($p in $pending) {
    $path = Resolve-MsBuildPath $p.Raw $p.Dir $p.From $props
    if ($null -eq $path) { $later.Add($p); continue }
    if ($path.Contains('*')) {
      # A wildcard item (R3-F3): every file it matches is an input.
      foreach ($hit in @(Expand-MsBuildWildcard $path)) { $extra[$hit] = $true }
    } elseif ($p.Kind -eq 'queue') { if (-not $seen.ContainsKey($path)) { $queue.Enqueue($path) } }
    elseif (Test-Path $path -PathType Leaf) { $extra[$path] = $true }
    elseif ($p.Kind -eq 'file') {
      # A resolved item that names no file cannot be proved older than the
      # binary (R3-F2): report it instead of dropping it.
      $later.Add(@{ Dir = $p.Dir; Raw = "$($p.Raw) (resolves to missing $path)"; Kind = 'missing'; From = $p.From })
    }
  }
  $pending = $later
  } while ($queue.Count -gt 0)
  $script:UiBuildUnresolved = @($pending | ForEach-Object { "$($_.Raw) in $($_.From.Substring($rootFull.Length).TrimStart('\\'))" })
  # The projects visited (section 52 item 2): the UI project and each
  # reference, transitively, for the compile-evidence binding.
  $script:UiBuildProjects = @($seen.Keys | Where-Object { $_ -like '*.csproj' } | Sort-Object)
  $files = @()
  foreach ($d in ($dirs | Sort-Object -Unique)) {
    $files += @(Get-ChildItem -Path $d -Recurse -Include '*.cs', '*.csproj', '*.xaml', '*.props', '*.targets', '*.resw', '*.json' -File |
      Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' })
  }
  foreach ($n in @('Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props', 'global.json', 'NuGet.config', '.editorconfig')) {
    $f = Join-Path $Root $n
    if (Test-Path $f) { $extra[[System.IO.Path]::GetFullPath($f)] = $true }
  }
  foreach ($k in $extra.Keys) { $files += Get-Item $k }
  return $files
}

function Expand-MsBuildWildcard([string]$Pattern) {
  # MSBuild item wildcards: `*` within a segment, `**` across segments.
  # The walk starts at the longest wildcard-free prefix directory.
  $segments = $Pattern -split '\\'
  $fixed = @()
  foreach ($seg in $segments) { if ($seg.Contains('*')) { break } ; $fixed += $seg }
  $base = $fixed -join '\'
  if (-not (Test-Path $base -PathType Container)) { return @() }
  $rx = '^' + (([regex]::Escape($Pattern)) -replace '\\\*\\\*\\\\', '(?:.*\\)?' -replace '\\\*', '[^\\]*') + '$'
  return @(Get-ChildItem -Path $base -Recurse -File | Where-Object { $_.FullName -match $rx -and $_.FullName -notmatch '\\(obj|bin)\\' } | ForEach-Object { $_.FullName })
}

function Resolve-MsBuildPath([string]$Raw, [string]$Dir, [string]$From, $Props) {
  # One MSBuild path: built-in directory properties, then literal
  # properties, repeated until nothing changes; null while any $(...)
  # stays unresolved.
  $v = $Raw
  $builtin = @{ MSBuildThisFileDirectory = ($Dir.TrimEnd('\') + '\'); MSBuildProjectDirectory = $Dir; MSBuildThisFileFullPath = $From }
  for ($i = 0; $i -lt 8 -and $v -match '\$\(([\w.]+)\)'; $i++) {
    $v = [regex]::Replace($v, '\$\(([\w.]+)\)', {
      param($m)
      $n = $m.Groups[1].Value
      if ($builtin.ContainsKey($n)) { return $builtin[$n] }
      if ($Props.ContainsKey($n)) { return $Props[$n] }
      return $m.Value
    })
  }
  if ($v -match '\$\(') { return $null }
  if (-not [System.IO.Path]::IsPathRooted($v)) { $v = Join-Path $Dir $v }
  if ($v.Contains('*')) {
    # Windows PowerShell's GetFullPath rejects wildcards: normalize the
    # wildcard-free prefix and keep the pattern segments as written.
    $segs = $v -split '\\'
    $cut = 0
    while (($cut -lt $segs.Count) -and (-not $segs[$cut].Contains('*'))) { $cut++ }
    return ([System.IO.Path]::GetFullPath(($segs[0..($cut - 1)] -join '\')).TrimEnd('\') + '\' + ($segs[$cut..($segs.Count - 1)] -join '\'))
  }
  return [System.IO.Path]::GetFullPath($v)
}

# Content provenance for the UI build (D00 T02 section 44 item 1).

function Get-FileSha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
}

function Get-BuildInputsDigest([string]$Root, [string]$Sdk, $Inputs = $null) {
  # One line per input (`<root-relative path> <sha256>`, ordinal-sorted),
  # the restore result, and the SDK version; the digest is SHA-256 over
  # the lines. $Inputs overrides the discovered set (fixtures).
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $files = if ($null -ne $Inputs) { @($Inputs) } else { @(Get-UiBuildInputs $Root | ForEach-Object { $_.FullName }) }
  $assets = Join-Path $rootFull 'tests\UI\obj\project.assets.json'
  if ((Test-Path $assets) -and ($null -eq $Inputs)) { $files += $assets }
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($f in $files) {
    $full = [System.IO.Path]::GetFullPath("$f")
    $rel = if ($full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $full.Substring($rootFull.Length + 1) } else { $full }
    $hash = if (Test-Path -LiteralPath $full) { Get-FileSha256 $full } else { 'missing' }
    $lines.Add("$($rel.Replace('\', '/')) $hash")
  }
  $lines.Sort([StringComparer]::Ordinal)
  $lines.Add("sdk $Sdk")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $digest = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))) -replace '-', '').Substring(0, 16).ToLowerInvariant() } finally { $sha.Dispose() }
  return [pscustomobject]@{ Digest = $digest; Lines = @($lines) }
}

function Get-ProjectOwnInputsDigest([string]$Root, [string]$ProjectDir) {
  # One project's own compile inputs (D00 T02 section 52 item 2, R1-A1):
  # the build-input walk from its project file without following project
  # references (its sources, XAML, resources, project and settings files,
  # every file it imports, its linked items outside its directory, and
  # the shared root inputs), plus its restore result (obj/project.assets
  # .json), one `<root-relative path> <sha256>` line each, ordinal-sorted,
  # digest over the lines. An unresolved path is a line too, so its
  # change is visible. The UI walk's own results are kept intact.
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $proj = @(Get-ChildItem -LiteralPath $ProjectDir -Filter '*.csproj' -File | Sort-Object Name)
  $savedU = $script:UiBuildUnresolved; $savedP = $script:UiBuildProjects
  try {
    $files = @(if ($proj.Count -gt 0) { Get-UiBuildInputs $Root -Start $proj[0].FullName -NoReferences | ForEach-Object { $_.FullName } })
    $unres = @($script:UiBuildUnresolved)
  } finally { $script:UiBuildUnresolved = $savedU; $script:UiBuildProjects = $savedP }
  $assets = Join-Path $ProjectDir 'obj\project.assets.json'
  if (Test-Path -LiteralPath $assets) { $files += [System.IO.Path]::GetFullPath($assets) }
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($full in @($files | Sort-Object -Unique)) {
    $rel = if ($full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $full.Substring($rootFull.Length + 1) } else { $full }
    $hash = if (Test-Path -LiteralPath $full) { Get-FileSha256 $full } else { 'missing' }
    $lines.Add("$($rel.Replace('\', '/')) $hash")
  }
  foreach ($u in $unres) { $lines.Add("unresolved $u") }
  $lines.Sort([StringComparer]::Ordinal)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $digest = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))) -replace '-', '').Substring(0, 16).ToLowerInvariant() } finally { $sha.Dispose() }
  return [pscustomobject]@{ Digest = $digest; Lines = @($lines) }
}

function Find-CompileEvidence([string]$Root, [string]$Name) {
  # A reference's compile-evidence file under Bin/<Name>/Debug (any RID
  # folder). Two or more read as ambiguous rather than picking one.
  $base = Join-Path $Root "Bin\$Name\Debug"
  $hits = @(if (Test-Path -LiteralPath $base) { Get-ChildItem -Path $base -Recurse -Filter 'compile-evidence.txt' -File })
  if ($hits.Count -eq 1) { return $hits[0].FullName }
  if ($hits.Count -gt 1) { return "ambiguous: $(@($hits | ForEach-Object { $_.FullName.Substring($Root.TrimEnd('\').Length + 1) }) -join ', ')" }
  return ''
}

function Get-BuildBindingLines([string]$Root, [string]$OutDir, $Projects) {
  # The binaries the UI digest describes (D00 T02 section 52 item 2),
  # from one snapshot: the UI assembly's hash, and for each referenced
  # project its compile evidence (inputs digest and assembly hash) plus
  # the hash of the copy the UI output carries. A reference with no
  # evidence, or ambiguous evidence, records so, and the check refuses.
  $lines = @("out UI.dll $(Get-FileSha256 (Join-Path $OutDir 'UI.dll'))")
  foreach ($p in @($Projects | Sort-Object)) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension("$p")
    if ($name -eq 'UI') { continue }
    $ev = Find-CompileEvidence $Root $name
    $copy = Join-Path $OutDir "$name.dll"
    $copyHash = if (Test-Path -LiteralPath $copy) { Get-FileSha256 $copy } else { 'missing' }
    if (($ev -eq '') -or $ev.StartsWith('ambiguous')) { $lines += "ref $name evidence $(if ($ev -eq '') { 'missing' } else { $ev.Replace(' ', '_') }) copy $copyHash"; continue }
    $evLines = @(Get-Content -LiteralPath $ev -TotalCount 2)
    $inputs = if (($evLines.Count -gt 0) -and ($evLines[0] -match '^inputs ([0-9a-f]{16})$')) { $Matches[1] } else { 'unreadable' }
    $asm = if (($evLines.Count -gt 1) -and ($evLines[1] -match '^assembly ([0-9a-f]{64})$')) { $Matches[1] } else { 'unreadable' }
    $rel = [System.IO.Path]::GetFullPath("$p").Substring([System.IO.Path]::GetFullPath($Root).TrimEnd('\').Length + 1).Replace('\', '/')
    $lines += "ref $name project $rel inputs $inputs assembly $asm copy $copyHash"
  }
  return $lines
}

function Test-CompileSnapshot([string]$Snapshot, [string]$Digest) {
  # The pre-compile snapshot check (D00 T02 section 53, from section 52
  # R5-A1): provenance publishes only when the snapshot the
  # before-CoreCompile target owes exists and equals the inputs now. A
  # missing snapshot fails closed, never falls back to post-compile inputs.
  if ("$Snapshot" -eq '') { return [pscustomobject]@{ Ok = $false; Reason = 'no pre-compile snapshot path was given' } }
  if (-not (Test-Path -LiteralPath $Snapshot)) { return [pscustomobject]@{ Ok = $false; Reason = "the pre-compile snapshot $Snapshot is missing" } }
  $before = ([System.IO.File]::ReadAllText($Snapshot)).Trim()
  if ($before -ne $Digest) { return [pscustomobject]@{ Ok = $false; Reason = "inputs changed during the build (before $before, after $Digest)" } }
  return [pscustomobject]@{ Ok = $true; Reason = '' }
}

function Test-BuildBinding([string]$Root, [string]$BindingFile, $ExpectedProjects = $null) {
  # Refuses a UI build whose recorded binaries no longer answer to their
  # sources (D00 T02 section 52 item 2): the UI assembly changed since the
  # binding, a reference has no readable evidence, a reference's own
  # inputs moved past its evidence (its project never recompiled, as a
  # timestamp-restored edit leaves it), or the copy the UI output carries
  # is not the assembly the evidence names. Names the first problem.
  $rebuild = 'rebuild without incremental skips: dotnet build src/ScratchPad.slnx --no-incremental'
  if (-not (Test-Path -LiteralPath $BindingFile)) { return [pscustomobject]@{ Ok = $false; Error = "UI build has no binary binding ($BindingFile); $rebuild" } }
  $outDir = Split-Path -Parent $BindingFile
  $problems = @()
  # Completeness (section 52 R1-A2): the UI row and one row per current
  # reference must be present, so an empty or truncated binding refuses.
  $all = @(Get-Content -LiteralPath $BindingFile | Where-Object { "$_".Trim() -ne '' })
  if (@($all | Where-Object { $_ -match '^out UI\.dll ' }).Count -ne 1) { $problems += 'the binding has no single UI.dll row' }
  foreach ($p in @($ExpectedProjects | Where-Object { $null -ne $_ })) {
    $pn = [System.IO.Path]::GetFileNameWithoutExtension("$p")
    if ($pn -eq 'UI') { continue }
    if (@($all | Where-Object { $_ -match ('^ref ' + [regex]::Escape($pn) + ' ') }).Count -ne 1) { $problems += "the binding has no single row for reference $pn" }
  }
  foreach ($ln in @(Get-Content -LiteralPath $BindingFile | Where-Object { "$_".Trim() -ne '' })) {
    if ($ln -match '^out UI\.dll (\S+)$') {
      $now = Get-FileSha256 (Join-Path $outDir 'UI.dll')
      if ($now -ne $Matches[1]) { $problems += "UI.dll changed since its binding was recorded" }
      continue
    }
    if ($ln -match '^ref (\S+) evidence (\S+) copy (\S+)$') { $problems += "reference $($Matches[1]) has no usable compile evidence ($($Matches[2]))"; continue }
    if ($ln -match '^ref (\S+) project (\S+) inputs (\S+) assembly (\S+) copy (\S+)$') {
      $name = $Matches[1]; $proj = $Matches[2]; $inputs = $Matches[3]; $asm = $Matches[4]; $copy = $Matches[5]
      if ($inputs -notmatch '^[0-9a-f]{16}$') { $problems += "reference $name has no consistent compile evidence (its inputs changed during the build or the evidence is unreadable)"; continue }
      $now = Get-ProjectOwnInputsDigest $Root (Split-Path -Parent (Join-Path $Root $proj))
      if ($inputs -ne $now.Digest) { $problems += "reference $name did not recompile after its sources changed (evidence inputs $inputs, now $($now.Digest))"; continue }
      if ($asm -ne $copy) { $problems += "the UI output's $name.dll is not the assembly $name's compile produced"; continue }
      $copyNow = Join-Path $outDir "$name.dll"
      $copyNowHash = if (Test-Path -LiteralPath $copyNow) { Get-FileSha256 $copyNow } else { 'missing' }
      if ($copyNowHash -ne $copy) { $problems += "the UI output's $name.dll changed since its binding was recorded" }
      continue
    }
    $problems += "unreadable binding line: $ln"
  }
  if ($problems.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Error = "UI build binding is stale: $($problems[0])$(if ($problems.Count -gt 1) { " (+$($problems.Count - 1) more)" }); $rebuild" } }
  return [pscustomobject]@{ Ok = $true; Error = '' }
}

function Test-BuildInputsDigest([string]$Root, [string]$DigestFile, [string]$Sdk, $Inputs = $null) {
  # The content freshness check: the digest recorded beside the binary at
  # build time must equal the inputs' digest now. Names the first
  # differing entry so the refusal says what changed.
  if (-not (Test-Path $DigestFile)) { return [pscustomobject]@{ Ok = $false; Error = "UI build has no content digest ($DigestFile); an incremental build that compiles nothing writes none, so rebuild: dotnet build src/ScratchPad.slnx --no-incremental" } }
  $recorded = @(Get-Content -LiteralPath $DigestFile)
  $now = Get-BuildInputsDigest $Root $Sdk $Inputs
  if (($recorded.Count -gt 0) -and ($recorded[0].Trim() -eq $now.Digest)) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $was = @($recorded | Select-Object -Skip 1 | Where-Object { $_ -ne '' })
  $changed = @($now.Lines | Where-Object { $was -cnotcontains $_ }) + @($was | Where-Object { $now.Lines -cnotcontains $_ })
  $first = if ($changed.Count -gt 0) { ($changed[0] -split ' ', 2)[0] } else { '?' }
  return [pscustomobject]@{ Ok = $false; Error = "UI build is stale by content: its build inputs changed since the build (first: $first; $($changed.Count) differing entries, timestamps notwithstanding); rebuild without incremental skips (a timestamp-restored input would not recompile): dotnet build src/ScratchPad.slnx --no-incremental" }
}

function Get-UiSdkVersion([string]$Root) {
  # The SDK the build records (NETCoreSdkVersion): the repo-local
  # toolchain's version, else the PATH one, else '' when neither answers.
  try { $dn = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'; if (-not (Test-Path $dn)) { $dn = 'dotnet' }; return "$(& $dn --version)".Trim() } catch { return '' }
}

function Get-UiBuildFreshness([string]$Root) {
  $dll = Join-Path $Root 'Bin\UI\Debug\UI.dll'
  if (-not (Test-Path $dll)) { return [pscustomobject]@{ Ok = $false; Error = "UI build missing: $dll; run: dotnet build src/ScratchPad.slnx, then retry" } }
  $inputs = @(Get-UiBuildInputs $Root)
  if (@($script:UiBuildUnresolved).Count -gt 0) {
    # An input the check cannot locate cannot be proved older than the
    # binary (R2-F2): refuse, naming each.
    return [pscustomobject]@{ Ok = $false; Error = "UI build freshness unprovable: unresolved build input path(s): $($script:UiBuildUnresolved -join '; ')" }
  }
  $newest = $inputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($null -eq $newest) { return [pscustomobject]@{ Ok = $true; Error = '' } }
  $r = Test-UiBuildFresh (Get-Item $dll).LastWriteTimeUtc $newest.LastWriteTimeUtc $dll
  if (-not $r.Ok) { $r.Error = $r.Error -replace 'the newest tests/UI source', "its newest build input ($($newest.FullName.Substring($Root.Length).TrimStart('\')))"; return $r }
  # Content freshness (D00 T02 section 44 item 1): the digest the build
  # recorded beside the binary must equal the inputs' digest now, so an
  # edit whose timestamp was restored, a deletion, or a property or SDK
  # change is caught where timestamps say fresh.
  $content = Test-BuildInputsDigest $Root (Join-Path $Root 'Bin\UI\Debug\build-inputs.digest') (Get-UiSdkVersion $Root)
  if (-not $content.Ok) { return $content }
  # Binary binding (section 52 item 2): the digest answers for the
  # binaries only when each reference's own compile evidence still
  # matches its sources and the copies the UI output carries.
  return (Test-BuildBinding $Root (Join-Path $Root 'Bin\UI\Debug\build-binding.txt') @($script:UiBuildProjects))
}

function Get-UiTestDiscovery([string]$Dotnet, [string]$UiCsproj, [string]$RunAFilter, [string]$RunBFilter, [string]$InteractiveFilter) {
  # Live discovery (D00 T02 §15, D00-T02-S13-PR13): one --list-tests run
  # per leg filter against the built UI binaries. Discovery failure
  # throws: an unverifiable population is a broken run, and the caller
  # reports it on the red path (never as governed green).
  $out = [pscustomobject]@{ RunA = @(); RunB = @(); Interactive = @(); RunAMethods = 0; RunACases = 0; RunBMethods = 0; RunBCases = 0; InteractiveMethods = 0; InteractiveCases = 0 }
  $legs = @(@('RunA', $RunAFilter), @('RunB', $RunBFilter), @('Interactive', $InteractiveFilter))
  foreach ($leg in $legs) {
    $one = Get-ListTestsCases $Dotnet $UiCsproj $leg[1] $leg[0]
    $out.($leg[0]) = $one.Methods
    $out.($leg[0] + 'Methods') = $one.MethodCount
    $out.($leg[0] + 'Cases') = $one.CaseCount
    $out | Add-Member -NotePropertyName ($leg[0] + 'CaseHash') -NotePropertyValue $one.CaseHash -Force
    $out | Add-Member -NotePropertyName ($leg[0] + 'CaseRows') -NotePropertyValue @($one.CaseRows) -Force
    $out | Add-Member -NotePropertyName ($leg[0] + 'CaseNames') -NotePropertyValue @($one.Cases) -Force
  }
  # Every case the binaries list, whatever its traits (D00 T02 section 52
  # item 4): a case no governed leg selects is an exclusion, and the
  # exclusion ledger must account for it.
  $all = Get-ListTestsCases $Dotnet $UiCsproj $script:AllCasesFilter 'AllCases'
  $out | Add-Member -NotePropertyName Excluded -NotePropertyValue @(Get-ExcludedCases @($all.Cases) @(@($out.RunACaseNames) + @($out.RunBCaseNames) + @($out.InteractiveCaseNames))) -Force
  return $out
}

# A filter every test matches (no test is named `__none__`), for the
# all-cases listing: vstest refuses an empty filter.
$script:AllCasesFilter = 'FullyQualifiedName!=__none__'

function Get-ExcludedCases($All, $Selected) {
  # The cases the binaries list that no governed leg selects (D00 T02
  # section 52 item 4), by display name with multiplicity: a name listed
  # twice and selected once leaves one excluded copy.
  $left = @{}
  foreach ($c in @($Selected)) { $k = "$c"; $left[$k] = 1 + $(if ($left.ContainsKey($k)) { $left[$k] } else { 0 }) }
  $out = @()
  foreach ($c in @($All)) {
    $k = "$c"
    if ($left.ContainsKey($k) -and ($left[$k] -gt 0)) { $left[$k]--; continue }
    $out += $k
  }
  return @($out | Sort-Object)
}

function Read-ExclusionLedger([string]$Path) {
  # docs/test-exclusions.md (D00 T02 section 52 item 4): one table row per
  # excluded case, `| <case> | <reason> | <owner> | <review-by
  # YYYY-MM-DD> |`. The header and separator rows are skipped; a missing
  # file reads as no rows (every exclusion then refuses).
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $rows = @()
  $n = 0
  foreach ($ln in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $n++
    $t = "$ln".Trim()
    if (-not ($t.StartsWith('|') -and $t.EndsWith('|'))) { continue }
    $cells = @($t.Substring(1, $t.Length - 2) -split '\|' | ForEach-Object { $_.Trim() })
    if (($cells.Count -ge 1) -and (($cells[0] -eq 'Case') -or ($cells[0] -match '^:?-{3,}'))) { continue }
    $rows += [pscustomobject]@{ Line = $n; Case = $cells[0].Trim('`'); Reason = $(if ($cells.Count -gt 1) { $cells[1] } else { '' }); Owner = $(if ($cells.Count -gt 2) { $cells[2] } else { '' }); ReviewBy = $(if ($cells.Count -gt 3) { $cells[3] } else { '' }); Cells = $cells.Count }
  }
  return $rows
}

function Test-ExclusionLedger($Excluded, $Rows, [datetime]$Today) {
  # Exclusion accountability (D00 T02 section 52 item 4): every excluded
  # case needs its own ledger row with a reason, an owner, and a review
  # date not yet past; a row for a case that is no longer excluded is
  # stale. Returns the problems, one line each (empty is green).
  $problems = @()
  # A function returning no rows hands back $null, which @() wraps as one
  # null element; neither list counts nulls.
  $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
  $Excluded = @(@($Excluded) | Where-Object { $null -ne $_ })
  $byCase = @{}
  foreach ($r in @($Rows)) {
    if ($byCase.ContainsKey($r.Case)) { $problems += "exclusion ledger line $($r.Line): duplicate row for $($r.Case)"; continue }
    $byCase[$r.Case] = $r
  }
  $today = $Today.Date
  foreach ($c in @($Excluded | Sort-Object -Unique)) {
    if (-not $byCase.ContainsKey($c)) { $problems += "excluded case without a ledger row: $c (add it to docs/test-exclusions.md with a reason, an owner, and a review date, or select it in a governed leg)"; continue }
    $r = $byCase[$c]
    if ($r.Cells -ne 4) { $problems += "exclusion ledger line $($r.Line): $c needs exactly 4 cells (case, reason, owner, review-by)"; continue }
    if ($r.Reason -eq '') { $problems += "exclusion ledger line $($r.Line): $c has no reason" }
    if ($r.Owner -eq '') { $problems += "exclusion ledger line $($r.Line): $c has no owner" }
    $due = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($r.ReviewBy, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$due)) { $problems += "exclusion ledger line $($r.Line): $c review date '$($r.ReviewBy)' is not YYYY-MM-DD" }
    elseif ($due.Date -lt $today) { $problems += "exclusion ledger line $($r.Line): $c review expired $($r.ReviewBy) (re-review it and move the date, or select the case)" }
  }
  $excludedSet = @{}
  foreach ($c in @($Excluded)) { $excludedSet["$c"] = $true }
  foreach ($r in @($Rows)) {
    if (-not $excludedSet.ContainsKey($r.Case)) { $problems += "exclusion ledger line $($r.Line): stale row, $($r.Case) is not excluded (remove the row)" }
  }
  return $problems
}
