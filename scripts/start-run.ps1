# Starts a ScratchPad campaign run: an interactive agent session in this checkout, in this window, with every
# permission prompt off and its goal set. The run starts only when the operator starts it, and ends when its window
# closes, it crashes or the machine restarts: nothing here, or anywhere in this repository, starts or resumes it.
#
#   pwsh scripts/start-run.ps1                    start the run in Claude Code (the latest Opus)
#   pwsh scripts/start-run.ps1 -Runner agy        start it in Google Antigravity on Orchestrator (the Carbon runner)
#   pwsh scripts/start-run.ps1 -InstallShortcut   put "ScratchPad Claude campaign" and "ScratchPad Carbon campaign" on
#                                                 the desktop, each running the line above for its runner
#   pwsh scripts/start-run.ps1 -DryRun            print what would run or be written, and change nothing
#   pwsh scripts/start-run.ps1 -Model sonnet      start on another model
#   pwsh scripts/start-run.ps1 -Effort high       start the Claude runner at another effort (default medium)
#   pwsh scripts/start-run.ps1 -TakeOver          end a held run guard without being asked, then start
#
# Adapted from the Conclave-SDK's own scripts/start-run.ps1 (the Windows launcher its Windows projects share; the
# unattended kit's launcher needs tmux and WSL, where a WinUI app cannot be built or tested). Each shortcut's icon is
# the app icon (resources/notepad.ico) with its runner's badge, rendered on this machine into
# %LOCALAPPDATA%\ScratchPad.Campaign by the unattended kit's renderer (scripts/campaign-icon.py), never into the
# repository.
#
# The goal is checked after every turn: the plan finished through the process-phase skill. That skill acquires the run
# guard itself (scripts/claude_campaign.py or scripts/agy_campaign.py) and arms the heartbeat inside the session, as
# docs/writer-campaigns.md describes, so this file acquires nothing.
#
# Two sessions must never write to one tree. When either writer's guard is active, this file names its session and
# waits for Enter (or takes -TakeOver as the answer). Only then does it end that guard with reason `handoff`, so the
# new session can acquire a fresh one. When no guard is active the new session is told so: a guard it then finds
# belongs to another live run, and it must start nothing.
#
# The Claude runner signs in with the long-lived token (`claude setup-token`) kept in the user variable
# CLAUDE_CODE_OAUTH_TOKEN, read from the user's own variables when this window does not have it yet. With none stored
# the session uses the claude.ai sign-in. The token is never printed, and this file never creates or changes one.
param(
  [ValidateSet('claude', 'agy')]
  [string]$Runner = 'claude',
  [switch]$InstallShortcut,
  [switch]$DryRun,
  [switch]$TakeOver,
  [string]$ShortcutDir = [Environment]::GetFolderPath('Desktop'),
  [string]$Model = '',
  [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
  [string]$Effort = 'medium',
  [string]$IconDir = (Join-Path $env:LOCALAPPDATA 'ScratchPad.Campaign'),
  [string]$UserEnvKey = 'HKCU:\Environment',
  [string]$Goal = '',
  # The three below exist for the tests: stand-ins for claude and agy, and a state folder outside the real build folder.
  [string]$ClaudePath = '',
  [string]$AgyPath = '',
  [string]$StateRoot = ''
)
$ErrorActionPreference = 'Stop'
# The automations kit marks every process a scheduled task runs: a run starts only when its operator starts it.
if ($env:CONCLAVE_AUTOMATION -and -not $InstallShortcut) {
  "start refused: it came from the scheduled task $env:CONCLAVE_AUTOMATION, and a run starts only when its operator starts it"
  exit 2
}
$repo = Split-Path $PSScriptRoot
$tokenName = 'CLAUDE_CODE_OAUTH_TOKEN'
if (-not $Model) { $Model = if ($Runner -eq 'agy') { 'gemini-pro-orchestrator' } else { 'opus' } }
if (-not $StateRoot) { $StateRoot = Join-Path $repo 'build' }

# Each runner's shortcut: its name is also the window title, so the operator can tell the campaigns apart.
$shortcuts = @(
  @{ Runner = 'claude'; Name = 'ScratchPad Claude campaign'; Icon = 'scratchpad-campaign-claude.ico'
     Description = 'Start the ScratchPad campaign in Claude Code (the latest Opus)' },
  @{ Runner = 'agy'; Name = 'ScratchPad Carbon campaign'; Icon = 'scratchpad-campaign-carbon.ico'
     Description = 'Start the ScratchPad campaign in Google Antigravity on Orchestrator (Carbon)' }
)
$title = ($shortcuts | Where-Object { $_.Runner -eq $Runner }).Name

if ($InstallShortcut) {
  $pwsh = (Get-Process -Id $PID).Path
  $brand = Join-Path $repo 'resources\notepad.ico'
  $renderer = Join-Path $PSScriptRoot 'campaign-icon.py'
  # Codex only reviews here since 2026-11-17, so a Codex campaign shortcut from an earlier setup is removed.
  $retired = @((Join-Path $ShortcutDir 'ScratchPad Codex campaign.lnk'))
  if ($DryRun) {
    foreach ($s in $shortcuts) {
      "would write: $(Join-Path $ShortcutDir "$($s.Name).lnk")"
      "  target: $pwsh -NoLogo -NoExit -NoProfile -File `"$PSCommandPath`" -Runner $($s.Runner)"
      "  icon: $(Join-Path $IconDir $s.Icon)"
    }
    foreach ($link in $retired) { if (Test-Path -LiteralPath $link) { "would remove: $link" } }
    exit 0
  }
  $python = (Get-Command python -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
  if (-not $python) { 'python is not on PATH: install Python 3, then write the shortcuts again'; exit 1 }
  New-Item -ItemType Directory -Force $IconDir | Out-Null
  foreach ($s in $shortcuts) {
    $icon = Join-Path $IconDir $s.Icon
    & $python $renderer badge $brand $s.Runner $icon
    if ($LASTEXITCODE -ne 0) { "the icon for $($s.Name) could not be rendered"; exit 1 }
    $link = Join-Path $ShortcutDir "$($s.Name).lnk"
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = "-NoLogo -NoExit -NoProfile -File `"$PSCommandPath`" -Runner $($s.Runner)"
    $shortcut.WorkingDirectory = $repo
    $shortcut.Description = $s.Description
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Save()
    "shortcut written: $link"
  }
  foreach ($link in $retired) {
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link; "shortcut removed: $link" }
  }
  exit 0
}

if (-not $Goal) {
  $Goal = (@'
Finish the ScratchPad implementation plan (todo/implementation-plan.md) 100% complete and aim for excellence: a Windows 11 Notepad replacement that works fully, end to end, and is a pleasure to use, with Claude Code and Codex inside. Work the whole plan with the process-phase skill, as the prompt `process plan` does, without stopping between sections or phases. Follow AGENTS.md and docs/design-contract.md. Never ask the operator a question: take the industry-standard option and record the decision, and what reversing it would cost, in the run file. Fix what breaks at its owning layer. The goal is met only when `python scripts/todo-graph.py query ready` lists nothing this session can run and the run file carries its Closeout heading or its PARKED line for this run id.
'@).Trim()
}

# Who holds the tree, read before anything starts: each writer keeps its own state, and `active` means a live run.
$held = $null
foreach ($harness in 'claude', 'agy') {
  $stateFile = Join-Path $StateRoot "$harness-campaign\state.json"
  if (-not (Test-Path -LiteralPath $stateFile)) { continue }
  $state = try { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { $null }
  if ($null -eq $state) { "the run guard file $stateFile cannot be read: inspect it before starting a run"; exit 1 }
  $paused = Test-Path -LiteralPath (Join-Path (Split-Path $stateFile) "paused-$($state.generation)")
  if ($state.status -eq 'active' -and -not $paused) {
    $held = @{ Harness = $harness; Session = [string]$state.session }
    break
  }
}
if ($held -and $held.Session -notmatch '^[0-9A-Za-z-]{8,64}$') {
  "the $($held.Harness) run guard is active but names no usable session: inspect build\$($held.Harness)-campaign\state.json"
  exit 1
}
if ($held) {
  $Goal += " The operator ended the earlier $($held.Harness) run guard (session $($held.Session)) at launch with reason handoff: inspect git status and that run's file before acquiring a fresh guard."
} else {
  $Goal += ' No run guard was active when this session was launched: if acquire is refused, another run is live, so start nothing and end the turn.'
}
# One line with no double quote: it is passed to the agent as a single argument. Claude Code allows 4,000 characters.
if ($Goal.Contains('"') -or $Goal.Contains("`n")) { 'the goal must be one line with no double quote'; exit 1 }
if ($Goal.Length -gt 4000) { "the goal is $($Goal.Length) characters; Claude Code allows 4,000"; exit 1 }

if ($Runner -eq 'agy') {
  # Antigravity takes its flags as --name=value; --prompt-interactive runs the goal and keeps the session open.
  $agent = 'agy'
  $arguments = @("--model=$Model", '--dangerously-skip-permissions', "--prompt-interactive=$Goal")
} else {
  $agent = 'claude'
  $session = [guid]::NewGuid().ToString()
  $arguments = @('--session-id', $session, '--dangerously-skip-permissions', '--model', $Model, '--effort', $Effort, '--name', $title, "/goal $Goal")
}
if ($DryRun) {
  "in $repo"
  if ($held) { "the $($held.Harness) run guard is active for session $($held.Session): a real start asks before ending it" }
  "$agent $($arguments[0..($arguments.Count - 2)] -join ' ') `"$($arguments[-1])`""
  exit 0
}

# Looked up, not assumed: a missing tool is named with its fix instead of failing as a bare "not recognized".
$python = (Get-Command python -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
$standIn = if ($agent -eq 'agy') { $AgyPath } else { $ClaudePath }
$program = if ($standIn) { $standIn } else { (Get-Command $agent -ErrorAction Ignore | Select-Object -First 1).Source }
if (-not $python) { 'python is not on PATH: install Python 3, then start again'; exit 1 }
if (-not $program) {
  if ($agent -eq 'agy') { 'agy is not on PATH: install Google Antigravity, then start again' } else { 'claude is not on PATH: install Claude Code, then start again' }
  exit 1
}

if ($held) {
  "the $($held.Harness) run guard is active for session $($held.Session)"
  'If that session is still working in another window, close this one now.'
  if (-not $TakeOver) { [void](Read-Host 'Press Enter to end that guard and start a new session') }
  & $python (Join-Path $PSScriptRoot "$($held.Harness)_campaign.py") --root (Split-Path $StateRoot) end --session $held.Session --reason handoff | Out-Null
  if ($LASTEXITCODE -ne 0) { 'the held run guard could not be ended: nothing was started'; exit 1 }
  'the earlier run guard was ended with reason handoff'
}

# The sign-in (Claude Code's; Antigravity signs in itself). Each line says where it came from, never the token itself.
if ($agent -eq 'agy') {
  'sign-in: Antigravity uses its own Google sign-in'
} elseif ([Environment]::GetEnvironmentVariable($tokenName)) {
  'sign-in: the long-lived token this window already has'
} else {
  $token = if (Test-Path -LiteralPath $UserEnvKey) { (Get-Item -LiteralPath $UserEnvKey).GetValue($tokenName, $null) }
  if ($token) {
    [Environment]::SetEnvironmentVariable($tokenName, $token)
    $token = $null
    'sign-in: the long-lived token from your user variables'
  } else {
    'sign-in: no long-lived token is stored, so the session uses the claude.ai sign-in'
    "          to store one: run ``claude setup-token`` and keep its output as the user variable $tokenName"
  }
}

# claude.exe shows --name in its title; Antigravity never rewrites the host title, so the one set here persists.
try { $Host.UI.RawUI.WindowTitle = $title } catch { Write-Verbose "window title not set: $($_.Exception.Message)" }
Set-Location -LiteralPath $repo
& $program @arguments
