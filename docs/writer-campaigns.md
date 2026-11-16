# Writer campaigns

Claude Code and Google Antigravity (the Carbon runner) may each own ScratchPad; Codex only reviews (operator decision 2026-11-17). Pick one active lead, finish or pause its run, then hand over. Start this machinery only for an explicitly requested phase or plan, never for a question or a review.

## Starting a run

The operator starts a run, in a window that stays open: nothing in this repository starts or resumes one on its own, and closing the window, a crash or a reboot ends it.

```powershell
pwsh scripts/start-run.ps1                    # Claude Code, the latest Opus at medium effort
pwsh scripts/start-run.ps1 -Runner agy        # Antigravity on Orchestrator (Carbon)
pwsh scripts/start-run.ps1 -DryRun            # print the command and goal, change nothing
pwsh scripts/start-run.ps1 -InstallShortcut   # write the two desktop shortcuts
```

The desktop shortcuts "ScratchPad Claude campaign" and "ScratchPad Carbon campaign" run the first two lines. Their icons are the app icon with the runner's badge, rendered by `scripts/campaign-icon.py` into `%LOCALAPPDATA%\ScratchPad.Campaign`, never into the repository. The launcher turns every permission prompt off and sets the goal: the whole plan through `process-phase`, with no questions to the operator. It refuses a start that comes from a scheduled task. When a run guard is still active it names that session and waits for Enter before ending the guard with reason `handoff`.

## Ownership and switching

Inspect `git status --short` and every existing diff before taking over. Runtime state lives separately in `build/claude-campaign/` and `build/agy-campaign/`. `scripts/agy_campaign.py` reuses the lifecycle in `scripts/claude_campaign.py` with its own state folder; the only shared runtime primitive is `build/writer-ownership.lock`, used to reject simultaneous acquisition. Preserve unfinished work and run evidence.

Create a run file under `docs/phase-runs/`, then acquire the active harness guard:

```powershell
python scripts/claude_campaign.py acquire --session $env:CLAUDE_CODE_SESSION_ID --run-file docs/phase-runs/<date>-phase-<N>.md --scope phase --phase <N>
python scripts/claude_campaign.py status
```

For Antigravity substitute `scripts/agy_campaign.py` and `$env:ANTIGRAVITY_CONVERSATION_ID`. If the host does not expose its session id, use the exact id from its session details; never guess or use another session's id. For the whole plan use `--scope plan`. Preserve the returned generation and run id. Reacquiring an active guard is refused, even in the same session, and so is acquiring while the other writer's guard is active.

To switch, the old owner runs `end --session <its-id> --reason handoff`, cancels its heartbeat, and records the current candidate, remaining work and evidence. The next writer inspects that record and acquires a fresh guard and generation. There is no automatic takeover of an active guard. Interrupted or stalled runs require an explicit operator resume before acquisition.

## Claude heartbeat

Use Claude's own `CronCreate` with a five-minute recurring schedule. Its prompt begins `SCRATCHPAD_HEARTBEAT <generation>` and says: read `scripts/claude_campaign.py status`; continue only if this exact session and generation remain active; otherwise delete this Cron job and stop. Resume only the recorded scope and run file. Never restart a paused or stalled run. Store the returned job id in the run file as `- bookkeeping: heartbeat job <id>`. Check `CronList` at each section boundary and recreate a missing or expiring job only for the same active run.

On operator stop, run `python scripts/claude_campaign.py end --session <id> --reason operator-stop`, then `CronDelete` the exact job. Do not depend on expiry for cancellation.

## Antigravity heartbeat

Use Antigravity's own `schedule` tool in the owning conversation, cron `*/5 * * * *`, with the same prompt shape: `SCRATCHPAD_HEARTBEAT <generation>`, read `python scripts/agy_campaign.py status`, continue only if this exact conversation and generation remain active, otherwise cancel this timer and stop. Store the timer id in the run file as `- bookkeeping: heartbeat timer <id>` and check `/tasks` at each section boundary. When the `schedule` tool is not offered or the timer cannot be made, the run is held by the Stop hook alone: say so in the run file. On operator stop, end the guard with `--reason operator-stop` and cancel the timer.

The heartbeat nudges an idle session that is still open. It never starts a session, and a session that has ended stays ended until the operator starts a new run.

## Stop behavior and closeout

The hook acts only on the owning session. Reviewers and unrelated sessions stop normally. While runnable work remains, Stop asks the owner to continue (Claude Code is held with `block`, Antigravity with `continue`). Three unchanged continuations trip the breaker on the next Stop. Source changes or substantive run evidence reset it; `- bookkeeping:` lines do not count as progress. A live review owned by this session suppresses the breaker until its deadline. End or pause takes precedence over heartbeat continuation. Claude's Interrupt and SessionEnd, and Antigravity's operator cancel (`terminationReason: USER_CANCELED`), pause the run.

Write `## Closeout run=<run_id>` after the requested scope is complete, or `PARKED <UTC> run=<run_id> <reason>` when nothing is runnable here. The id prevents an old marker closing a new run. End the guard with `--reason closeout` or `--reason park`, then cancel the heartbeat. A whole-plan run uses a new guard and run id for its next phase. A named phase never chains.

## Activation and checks

Claude loads `.claude/settings.json` in its own runtime; Antigravity loads `.agents/hooks.json` (one named hook, `campaign-guard`, with a Stop handler that runs from `.agents/`). Reload the relevant session after changing hook wiring.

```powershell
python -m unittest discover -s scripts/tests -p test_campaign_runtime.py
python -m unittest discover -s scripts/tests -p test_start_run.py
python -m unittest discover -s scripts/tests -p 'test_review*.py'
python -m unittest discover -s scripts/tests -p 'test_three*.py'
python scripts/review-dispatch.py --check-pin
```

Unit tests prove lifecycle logic, the payload shapes and the launcher's commands, not delivery of a hook into a real idle session. The Antigravity Stop hook and `schedule` heartbeat have not yet been observed in a live ScratchPad run: the first Carbon campaign is their proof, and its run file records what happened. Installation and tests do not arm a live campaign.
