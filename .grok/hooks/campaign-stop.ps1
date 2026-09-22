# Block the main session's end_turn while a campaign run is open.
# The harness stops asking after 8 blocks in one turn. This script
# does not give up earlier. Fail open: a bad payload, a missing
# guard, or a thrown error allows the stop.
$ErrorActionPreference = "Stop"
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $event = $raw | ConvertFrom-Json
    $reason = [string]$event.reason
    if ($reason -and $reason -ne "end_turn") { exit 0 }
    if ([string]$event.subagentType) { exit 0 }

    $root = $env:GROK_WORKSPACE_ROOT
    if (-not $root) { $root = [string]$event.workspaceRoot }
    if (-not $root) { $root = [string]$event.cwd }
    if (-not $root) { exit 0 }

    $guardPath = Join-Path $root "build\grok-campaign-guard.json"
    if (-not (Test-Path -LiteralPath $guardPath)) { exit 0 }
    $guard = Get-Content -LiteralPath $guardPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $relative = [string]$guard.run_file
    if (-not $relative) { exit 0 }
    if ([System.IO.Path]::IsPathRooted($relative)) { exit 0 }
    $runPath = Join-Path $root $relative
    $fullRun = [System.IO.Path]::GetFullPath($runPath)
    $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
    $underRoot = $fullRun.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $underRoot) { exit 0 }
    if (-not (Test-Path -LiteralPath $fullRun)) { exit 0 }

    $text = Get-Content -LiteralPath $fullRun -Raw -Encoding UTF8
    if ($text -match "(?m)^## Closeout\b") { exit 0 }
    if ($text -match "(?m)^PARKED\b") { exit 0 }

    $message = "Campaign run is still open ($relative). Do not end the turn. Finish the open section's checklist, run the review panel and stamp it, then the next section, then the next phase. Stop only when the plan has no runnable work, or the operator said stop. A commit is not a stop."
    $payload = @{ decision = "block"; reason = $message } | ConvertTo-Json -Compress
    [Console]::Out.WriteLine($payload)
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 0
}
