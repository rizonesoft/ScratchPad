# Exit 0 when a ScratchPad campaign writer looks live, exit 1 when it looks stalled.
# Prints one token line: LIVE tree, LIVE session, LIVE process, or STALE.
$ErrorActionPreference = "Stop"
$root = $env:GROK_WORKSPACE_ROOT
if (-not $root) { $root = (Get-Location).Path }
$cutoff = (Get-Date).AddMinutes(-25)
$skip = [regex]'\\(bin|obj|Bin|build)\\'

$trees = @("src", "tests", "todo", "resources", "docs")
foreach ($tree in $trees) {
    $dir = Join-Path $root $tree
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $hit = Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff -and $_.FullName -notmatch $skip } |
        Select-Object -First 1
    if ($hit) {
        Write-Output "LIVE tree"
        exit 0
    }
}

$encoded = [Uri]::EscapeDataString($root)
$sessionRoot = Join-Path $env:USERPROFILE ".grok\sessions"
if (Test-Path -LiteralPath $sessionRoot) {
    $sessionHit = Get-ChildItem -LiteralPath $sessionRoot -Recurse -File -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*$encoded*" -and $_.LastWriteTime -gt $cutoff } |
        Select-Object -First 1
    if ($sessionHit) {
        Write-Output "LIVE session"
        exit 0
    }
}

$names = @("dotnet", "testhost")
$procs = Get-Process -Name $names -ErrorAction SilentlyContinue
foreach ($proc in $procs) {
    $path = $proc.Path
    if (-not $path) { continue }
    if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output "LIVE process"
        exit 0
    }
}

Write-Output "STALE"
exit 1
