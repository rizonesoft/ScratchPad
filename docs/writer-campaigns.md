# Writer campaigns

Claude Code and Codex may each own ScratchPad. Pick one active lead, finish or pause its run, then hand over. Reviewers remain read-only. Start this machinery only for an explicitly requested phase or plan, never for a question or a review.

## Ownership and switching

Inspect `git status --short` and every existing diff before taking over. Runtime state lives separately in `build/claude-campaign/` and `build/codex-campaign/`. Each script is independently executable and imports nothing from the other. The only shared runtime primitive is `build/writer-ownership.lock`, used to reject simultaneous acquisition. Preserve unfinished work and run evidence.

Create a run file under `docs/phase-runs/`, then acquire the active harness guard:

```powershell
python scripts/codex_campaign.py acquire --session $env:CODEX_THREAD_ID --run-file docs/phase-runs/<date>-phase-<N>.md --scope phase --phase <N>
python scripts/codex_campaign.py status
```

For Claude substitute `scripts/claude_campaign.py` and `$env:CLAUDE_CODE_SESSION_ID`. If the host does not expose its session id, use the exact id from its session details; never guess or use another thread's id. For the whole plan use `--scope plan`. Preserve the returned generation and run id. Reacquiring an active guard is refused, even in the same session.

To switch, the old owner runs `end --session <its-id> --reason handoff`, cancels its heartbeat, and records the current candidate, remaining work and evidence. The next writer inspects that record and acquires a fresh guard and generation. There is no automatic takeover of an active guard. Interrupted or stalled runs require an explicit operator resume before acquisition.

## Codex heartbeat

The installed CLI must support `codex queue --thread <id> --message <text> --resume`. Start the hidden watchdog after acquisition:

```powershell
python scripts/codex_campaign.py start-worker --session $env:CODEX_THREAD_ID --generation <generation> --interval 300 --owner-pid <native-session-process-id>
```

The watchdog queues one generation-bound message after five minutes without a hook event, then waits for consumption. It never launches a second writer. PostToolUse refreshes activity. UserPromptSubmit rejects stale heartbeat generations. Stop continues an active run; Interrupt and SessionEnd pause it. A queue failure or resume warning degrades the run and stops the watchdog. Check `status` at each section boundary: `error`, `worker_pid`, `pending` and `last_heartbeat`. Restart a dead worker with `start-worker` only for the same active generation. The owner PID must identify the native session process, not the temporary shell running this command. The watchdog records its creation identity and stops if that process exits or its PID is reused. An unconsumed heartbeat degrades the run after ten minutes. Ending the guard stops the watchdog within ten seconds, or within forty seconds if a queue call is already in flight.

This recovers a local idle session, not a dead machine. If the session ends, resume is an operator action.

## Claude heartbeat

Use Claude's own `CronCreate` with a five-minute recurring schedule. Its prompt begins `SCRATCHPAD_HEARTBEAT <generation>` and says: read `scripts/claude_campaign.py status`; continue only if this exact session and generation remain active; otherwise delete this Cron job and stop. Resume only the recorded scope and run file. Never restart a paused or stalled run. Store the returned job id in the run file as `- bookkeeping: heartbeat job <id>`. Check `CronList` at each section boundary and recreate a missing or expiring job only for the same active run. Claude jobs and Codex workers never call each other's runtime.

On operator stop, run `python scripts/claude_campaign.py end --session <id> --reason operator-stop`, then `CronDelete` the exact job. Do not depend on expiry for cancellation.

## Stop behavior and closeout

The hook acts only on the owning session. Reviewers and unrelated sessions stop normally. While runnable work remains, Stop asks the owner to continue. Three unchanged continuations trip the breaker on the next Stop. Source changes or substantive run evidence reset it; `- bookkeeping:` lines do not count as progress. A live review owned by this session suppresses the breaker until its deadline. End or pause takes precedence over heartbeat continuation.

Write `## Closeout run=<run_id>` after the requested scope is complete, or `PARKED <UTC> run=<run_id> <reason>` when nothing is runnable here. The id prevents an old marker closing a new run. End the guard with `--reason closeout` or `--reason park`, then cancel the Claude Cron job or let the Codex worker observe the ended state. A whole-plan run uses a new guard and run id for its next phase. A named phase never chains.

## Activation and checks

Codex loads `.codex/hooks.json` only in a trusted project and skips new or changed non-managed hook definitions until reviewed and trusted in `/hooks` (or Settings > Hooks). This is required by the native [Codex hook trust model](https://learn.chatgpt.com/docs/hooks). Do not edit trust hashes to claim activation. Claude loads `.claude/settings.json` in its own runtime. Reload the relevant session after changing hook wiring.

```powershell
python -m unittest discover -s scripts/tests -p test_campaign_runtime.py
python -m unittest discover -s scripts/tests -p 'test_review*.py'
python scripts/review-dispatch.py --check-pin
```

Unit tests prove lifecycle logic and subprocess contracts, not native hook trust or delivery into a real idle thread. Report these separately. Installation and tests do not arm a live campaign.
