# Proves the Grok campaign hook, liveness script, and review prompt assembly.
# Does not call Claude, Codex, or the test suite.
$ErrorActionPreference = "Stop"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fail = 0

function Assert-Equal($name, $actual, $expected) {
    if ($actual -ne $expected) {
        Write-Output "FAIL $name actual=[$actual] expected=[$expected]"
        $script:fail++
    } else {
        Write-Output "PASS $name"
    }
}

function Invoke-Hook([string]$json, [string]$root) {
    $prev = $env:GROK_WORKSPACE_ROOT
    $env:GROK_WORKSPACE_ROOT = $root
    try {
        $out = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo ".grok\hooks\campaign-stop.ps1")
        return ($out | Out-String).Trim()
    } finally {
        if ($null -eq $prev) { Remove-Item Env:GROK_WORKSPACE_ROOT -ErrorAction SilentlyContinue }
        else { $env:GROK_WORKSPACE_ROOT = $prev }
    }
}

$scratch = Join-Path $env:TEMP ("grok-campaign-selftest-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    python3 -m py_compile (Join-Path $repo ".grok\scripts\assemble-review-prompt.py") (Join-Path $repo ".grok\scripts\run-unchecked.py")
    if ($LASTEXITCODE -ne 0) { throw "py_compile failed" }
    Write-Output "PASS py_compile"

    $unchecked = python3 (Join-Path $repo ".grok\scripts\run-unchecked.py")
    Assert-Equal "unchecked-usage" $LASTEXITCODE 2

    Set-Content -Encoding utf8NoBOM (Join-Path $scratch "section.md") "section body`n"
    Set-Content -Encoding utf8NoBOM (Join-Path $scratch "diff.patch") "diff body`n"
    $fenced = Join-Path $scratch "fenced.md"
    & python3 (Join-Path $repo "scripts\review_prompt.py") fence PANEL "SECTION CONTRACT=$(Join-Path $scratch 'section.md')" "CANDIDATE DIFF=$(Join-Path $scratch 'diff.patch')" | Out-File -Encoding utf8NoBOM $fenced
    $prompt = Join-Path $scratch "prompt.md"
    $tag = (& python3 (Join-Path $repo ".grok\scripts\assemble-review-prompt.py") panel $fenced $prompt).Trim()
    $text = Get-Content -Raw -Encoding utf8 $prompt
    if ($text.StartsWith("You are an independent code reviewer.") -and $text.Contains("[$tag]") -and $text.Contains("section body")) {
        Write-Output "PASS assemble-panel"
    } else {
        Write-Output "FAIL assemble-panel"
        $fail++
    }
    $arch = Join-Path $scratch "arch.md"
    & python3 (Join-Path $repo ".grok\scripts\assemble-review-prompt.py") arch $fenced $arch "editor state" | Out-Null
    $archText = Get-Content -Raw -Encoding utf8 $arch
    if ($archText.Contains("editor state") -and $archText.Contains("**architecture:")) {
        Write-Output "PASS assemble-arch"
    } else {
        Write-Output "FAIL assemble-arch"
        $fail++
    }

    $ws = Join-Path $scratch "ws"
    New-Item -ItemType Directory -Force -Path (Join-Path $ws "docs") | Out-Null
    $run = Join-Path $ws "docs\run.md"
    Set-Content -Encoding utf8 $run "still working`n"
    New-Item -ItemType Directory -Force -Path (Join-Path $ws "build") | Out-Null
    $guard = @{ runner = "grok"; workspace = $ws; phase = "0"; run_file = "docs/run.md"; scheduler_id = "test" } | ConvertTo-Json
    Set-Content -Encoding utf8 (Join-Path $ws "build\grok-campaign-guard.json") $guard

    $open = Invoke-Hook '{"reason":"end_turn","stopHookActive":false}' $ws
    if ($open.Contains('"decision":"block"') -or $open.Contains('"decision": "block"')) { Write-Output "PASS hook-open" } else { Write-Output "FAIL hook-open [$open]"; $fail++ }

    $child = Invoke-Hook '{"reason":"end_turn","subagentType":"general"}' $ws
    Assert-Equal "hook-subagent" $child ""

    $again = Invoke-Hook '{"reason":"end_turn","stopHookActive":true}' $ws
    if ($again.Contains('"decision":"block"') -or $again.Contains('"decision": "block"')) { Write-Output "PASS hook-keeps-blocking" } else { Write-Output "FAIL hook-keeps-blocking [$again]"; $fail++ }

    $other = Invoke-Hook '{"reason":"shutdown"}' $ws
    Assert-Equal "hook-not-end-turn" $other ""

    Set-Content -Encoding utf8 $run "notes mention PARKED in prose`n"
    $mid = Invoke-Hook '{"reason":"end_turn"}' $ws
    if ($mid.Contains("block")) { Write-Output "PASS hook-parked-word-inside" } else { Write-Output "FAIL hook-parked-word-inside [$mid]"; $fail++ }

    Set-Content -Encoding utf8 $run "PARKED`nleftovers`n"
    $parked = Invoke-Hook '{"reason":"end_turn"}' $ws
    Assert-Equal "hook-parked" $parked ""

    Set-Content -Encoding utf8 $run "## Closeout`ndone`n"
    $closed = Invoke-Hook '{"reason":"end_turn"}' $ws
    Assert-Equal "hook-closeout" $closed ""

    $outside = @{ runner = "grok"; run_file = "../outside.md" } | ConvertTo-Json
    Set-Content -Encoding utf8 (Join-Path $ws "build\grok-campaign-guard.json") $outside
    Set-Content -Encoding utf8 (Join-Path $scratch "outside.md") "still working`n"
    $escaped = Invoke-Hook '{"reason":"end_turn"}' $ws
    Assert-Equal "hook-escape" $escaped ""

    $bare = Invoke-Hook '{"reason":"end_turn"}' (Join-Path $scratch "missing-root")
    Assert-Equal "hook-no-guard" $bare ""

    $live = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo ".grok\scripts\campaign-liveness.ps1")
    if ($live -match "^LIVE |^STALE$") { Write-Output "PASS liveness $live" } else { Write-Output "FAIL liveness [$live]"; $fail++ }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) {
    Write-Output "SELFTEST FAILED $fail"
    exit 1
}
Write-Output "SELFTEST PASSED"
exit 0
