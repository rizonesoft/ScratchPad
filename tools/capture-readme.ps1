#Requires -Version 5.1
<#
.SYNOPSIS
  Captures the README screenshots (D00 T03 §1) from a clean checkout.
.DESCRIPTION
  Clones this repository at -Commit into a temporary folder (so its Bin/
  starts empty and the working tree is never touched), builds the app
  there with the repo-local SDK, and launches it once per theme against
  a seeded session holding two realistic sample documents. Each window is
  captured with PrintWindow (PW_RENDERFULLCONTENT) in the suite's
  background mode (SCRATCHPAD_BACKGROUND=1: the window paints off-screen
  and never takes the foreground). Writes docs/assets/readme-hero.png
  (the light shot), readme-hero-light.png, readme-hero-dark.png, and
  prints the provenance lines docs/assets/captures.md records.

  The app's settings and session store (%LOCALAPPDATA%\ScratchPad) is
  backed up before the first launch and restored afterwards, whatever
  happens, so a capture never replaces the operator's own settings.

  A shot fails loud when it is narrower than -MinWidth pixels or its
  pixels do not vary (a black or blank frame).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\capture-readme.ps1
#>
[CmdletBinding()]
param(
  [string]$Commit = 'HEAD',
  [string]$OutDir = '',
  [int]$Width = 1400,
  [int]$Height = 860,
  [int]$MinWidth = 1280,
  [string]$Configuration = 'Debug'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ($OutDir -eq '') { $OutDir = Join-Path $Root 'docs\assets' }
$dotnet = Join-Path $Root '.tools\dotnet-win-x64\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet)) { throw "capture: repo-local SDK missing ($dotnet); run tools\provision.ps1 first" }
$sha = (& git -C $Root rev-parse $Commit).Trim()
if ($LASTEXITCODE -ne 0) { throw "capture: cannot resolve $Commit" }

Add-Type -AssemblyName System.Drawing
Add-Type -Namespace ReadmeShots -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rc);
[DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT rc, int size);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@

# Per-monitor DPI awareness (V2) for this thread: without it Windows
# PowerShell reads window rectangles scaled to 96 DPI, and PrintWindow's
# full-size render lands cropped in a too-small bitmap.
$null = [ReadmeShots.Win]::SetThreadDpiAwarenessContext([IntPtr](-4))

$work = Join-Path ([IO.Path]::GetTempPath()) ("readme-capture-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$clone = Join-Path $work 'repo'
$docs = Join-Path $work 'docs'
$null = New-Item -ItemType Directory -Force -Path $docs

# 1. A clean checkout: a fresh clone has no Bin/ at all.
& git clone --quiet --no-hardlinks $Root $clone
& git -C $clone checkout --quiet $sha
if ($LASTEXITCODE -ne 0) { throw "capture: checkout of $sha failed" }
if (Test-Path -LiteralPath (Join-Path $clone 'Bin')) { throw 'capture: the clean checkout already has a Bin/ folder' }
$env:DOTNET_ROOT = Split-Path -Parent $dotnet
$env:DOTNET_MULTILEVEL_LOOKUP = '0'
& $dotnet build (Join-Path $clone 'src\ScratchPad\ScratchPad.csproj') -c $Configuration --nologo -v q | Out-Host
if ($LASTEXITCODE -ne 0) { throw "capture: build failed ($LASTEXITCODE)" }
$exe = Get-ChildItem -LiteralPath (Join-Path $clone 'Bin\ScratchPad') -Recurse -Filter 'ScratchPad.exe' | Select-Object -First 1
if ($null -eq $exe) { throw 'capture: ScratchPad.exe not found under the clean build' }

# 2. Realistic sample documents (never lorem ipsum).
$notes = Join-Path $docs 'release-notes.md'
[IO.File]::WriteAllText($notes, (@(
  '# ScratchPad 0.4 release notes',
  '',
  '## Highlights',
  '- Tabs restore exactly where you left them, unsaved edits included.',
  '- Find and Replace keeps its options per window.',
  '- Word wrap and the status bar follow your last choice.',
  '',
  '## Fixes',
  '- Saving a file with mixed line endings keeps the ending you chose.',
  '- Closing a window with unsaved tabs never loses a change.',
  '',
  '## Next',
  '- Agents in the editor: ask Claude Code or Codex about the open file,',
  '  review the proposed diff, and apply it with one undo step.'
) -join "`r`n"))
$todo = Join-Path $docs 'groceries.txt'
[IO.File]::WriteAllText($todo, (@('Saturday market', '', 'apples (6)', 'sourdough loaf', 'coffee beans, medium roast', 'basil', 'lemons') -join "`r`n"))

# 3. The store is backed up before any launch and restored after. The
# store is shared by every instance, so the capture needs it exclusively:
# it refuses while any other ScratchPad runs, re-checks before each
# launch, and never restores over state a concurrent instance may have
# written (the backup is then kept beside the store and named).
function Get-OtherInstances([int[]]$Except = @()) { return @(Get-Process -Name 'ScratchPad' -ErrorAction SilentlyContinue | Where-Object { $Except -notcontains $_.Id }) }
$running = Get-OtherInstances
if ($running.Count -gt 0) { throw "capture: ScratchPad is running (pid $(@($running | ForEach-Object { $_.Id }) -join ', ')); close it first: the capture seeds the shared settings store" }
$store = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ScratchPad'
$null = New-Item -ItemType Directory -Force -Path $store
$backup = Join-Path $work 'store-backup'
$null = New-Item -ItemType Directory -Force -Path $backup
$saved = @{}
foreach ($n in @('settings.json', 'session.json')) {
  $p = Join-Path $store $n
  $saved[$n] = Test-Path -LiteralPath $p
  if ($saved[$n]) { Copy-Item -LiteralPath $p -Destination (Join-Path $backup $n) -Force }
}

function Test-FrameVaries([System.Drawing.Bitmap]$Bmp) {
  # Luminance spread over a sample grid; a black or blank frame reads ~0.
  $vals = New-Object System.Collections.Generic.List[double]
  for ($y = 5; $y -lt $Bmp.Height; $y += [math]::Max(1, [int]($Bmp.Height / 40))) {
    for ($x = 5; $x -lt $Bmp.Width; $x += [math]::Max(1, [int]($Bmp.Width / 40))) {
      $c = $Bmp.GetPixel($x, $y); $vals.Add(0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
    }
  }
  $mean = ($vals | Measure-Object -Average).Average
  $var = ($vals | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Average).Average
  return [math]::Sqrt($var)
}

$shots = @()
try {
  foreach ($theme in @('light', 'dark')) {
    $settings = [ordered]@{ Version = 1; X = 40; Y = 40; Width = $Width; Height = $Height; Theme = $theme; WordWrap = $true; ShowStatusBar = $true; WhenStarts = 'continue'; WhatsNewSeen = $true; RecentFiles = @(); PinnedFiles = @() }
    [IO.File]::WriteAllText((Join-Path $store 'settings.json'), (ConvertTo-Json ([pscustomobject]$settings) -Depth 4))
    $session = [pscustomobject]@{ Windows = @([pscustomobject]@{ Tabs = @([pscustomobject]@{ Path = $notes; Caret = 0 }, [pscustomobject]@{ Path = $todo; Caret = 0 }); Active = 0 }); ActiveWindow = 0 }
    [IO.File]::WriteAllText((Join-Path $store 'session.json'), (ConvertTo-Json $session -Depth 6))
    $running = Get-OtherInstances
    if ($running.Count -gt 0) { throw "capture: another ScratchPad started during the capture (pid $(@($running | ForEach-Object { $_.Id }) -join ', ')); stopping before it reads the seeded store" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe.FullName
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['SCRATCHPAD_BACKGROUND'] = '1'
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
      $deadline = (Get-Date).AddSeconds(30)
      while (((Get-Date) -lt $deadline) -and ($proc.MainWindowHandle -eq [IntPtr]::Zero)) { Start-Sleep -Milliseconds 250; $proc.Refresh() }
      if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { throw "capture: no main window within 30 s ($theme)" }
      $hwnd = $proc.MainWindowHandle
      # The seeded Width and Height are DIPs; the layout settles first.
      Start-Sleep -Milliseconds 3000
      $rc = New-Object ReadmeShots.Win+RECT
      $null = [ReadmeShots.Win]::GetWindowRect($hwnd, [ref]$rc)
      $w = $rc.Right - $rc.Left; $h = $rc.Bottom - $rc.Top
      $bmp = New-Object System.Drawing.Bitmap($w, $h)
      try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $hdc = $g.GetHdc(); try { $null = [ReadmeShots.Win]::PrintWindow($hwnd, $hdc, 2) } finally { $g.ReleaseHdc($hdc) } } finally { $g.Dispose() }
        # Crop to the visible frame (DWMWA_EXTENDED_FRAME_BOUNDS): the
        # window rectangle includes invisible resize borders that
        # PrintWindow paints black.
        $fr = New-Object ReadmeShots.Win+RECT
        if ([ReadmeShots.Win]::DwmGetWindowAttribute($hwnd, 9, [ref]$fr, 16) -eq 0) {
          $crop = New-Object System.Drawing.Rectangle(($fr.Left - $rc.Left), ($fr.Top - $rc.Top), ($fr.Right - $fr.Left), ($fr.Bottom - $fr.Top))
          if (($crop.Width -gt 0) -and ($crop.Height -gt 0) -and ($crop.Right -le $w) -and ($crop.Bottom -le $h)) {
            $cut = $bmp.Clone($crop, $bmp.PixelFormat); $bmp.Dispose(); $bmp = $cut; $w = $crop.Width; $h = $crop.Height
          }
        }
        $spread = Test-FrameVaries $bmp
        if ($w -lt $MinWidth) { throw "capture: $theme shot is $w px wide (< $MinWidth)" }
        if ($spread -lt 8) { throw "capture: $theme shot does not vary (luminance spread $([math]::Round($spread, 1))): a black or blank frame" }
        $out = Join-Path $OutDir "readme-hero-$theme.png"
        $null = New-Item -ItemType Directory -Force -Path $OutDir
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $shots += [pscustomobject]@{ Theme = $theme; Path = $out; Width = $w; Height = $h; Spread = [math]::Round($spread, 1) }
      } finally { $bmp.Dispose() }
    } finally {
      if (-not $proc.HasExited) { $null = $proc.CloseMainWindow(); if (-not $proc.WaitForExit(10000)) { $proc.Kill() } }
    }
  }
} finally {
  $running = Get-OtherInstances
  if ($running.Count -gt 0) {
    # Another instance may own the store now: nothing is overwritten, and
    # the operator's backup is kept beside the store for them to restore.
    $kept = Join-Path $store ("capture-backup-" + (Get-Date).ToString('yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $backup -Destination $kept -Recurse -Force
    Write-Output "capture: another ScratchPad is running (pid $(@($running | ForEach-Object { $_.Id }) -join ', ')); the store was NOT restored; your settings and session are kept in $kept"
  } else {
    foreach ($n in @('settings.json', 'session.json')) {
      $p = Join-Path $store $n
      if ($saved[$n]) { Copy-Item -LiteralPath (Join-Path $backup $n) -Destination $p -Force }
      elseif (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
  }
}
Copy-Item -LiteralPath (Join-Path $OutDir 'readme-hero-light.png') -Destination (Join-Path $OutDir 'readme-hero.png') -Force
$os = [Environment]::OSVersion.Version.ToString()
foreach ($s in $shots) { Write-Output "shot $($s.Theme): $(Split-Path -Leaf $s.Path) $($s.Width)x$($s.Height) luminance-spread $($s.Spread)" }
Write-Output "provenance: commit $sha; configuration $Configuration; OS $os; captured $((Get-Date).ToString('yyyy-MM-dd HH:mm zzz')); command powershell -ExecutionPolicy Bypass -File tools\capture-readme.ps1 -Commit $sha"
try { Remove-Item -LiteralPath $work -Recurse -Force } catch { Write-Output "capture: temp folder left at $work ($($_.Exception.Message))" }
