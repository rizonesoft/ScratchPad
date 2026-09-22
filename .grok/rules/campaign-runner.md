# Grok campaign runner

You are the Grok runner for this repo's process-plan campaign. The Muse runner is `.claude/skills/` and `CLAUDE.md`. Do not read those skills, do not edit them, and do not follow their procedures. When a name collides, the skill under `.grok/skills/` is the one you run.

Shared, and safe to call: `scripts/todo-graph.py`, `scripts/review_prompt.py`, `docs/testing.md`, `tools/nightly.ps1`, `tools/NightlySupervisor.ps1`, and the test suites. Those are the product and the graph. They are not model prompts. Everything that tells you how to behave lives under `.grok/`.

## Skills

| Skill | Run it when |
| --- | --- |
| `add-todo` | New work needs a home in `todo/` |
| `create-todo` | `add-todo` routes to a new file |
| `groom-plan` | Harden the tree before a long run. Never starts a campaign |
| `process-plan` | Process the plan, with no phase named. Chains phases |
| `process-phase` | One named phase, to closeout or park |
| `process-todo-section` | One section: validate, build, gate, commit |
| `review-todo-section` | Stamp and flip the row, or audit a shipped row |
| `process-todo-file` | Every row in one file is `[x]` |

Read the skill before acting. `AGENTS.md` names `.claude/skills/` because that sentence is the Muse path. Ignore that path.

## Host

Windows, PowerShell. Graph commands are `python3 scripts/todo-graph.py ...`. If `python3` is missing, use `py -3`. Do not use `grep`, `head`, `tail`, `sed`, `awk`, or `find` in the shell. Use the `grep` tool, `Select-Object -First` or `-Last`, and the scripts in `.grok/scripts/`. Bound every command. Full logs stay under `build/`.

UTC stamps: `[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")`. Run ids use `yyyyMMdd` from that same clock.

## Run guard

A campaign run creates one Grok scheduled task, interval `10m`, `durable` true, `fire_immediately` false. The task expires after 7 days; recreate it if the run is still open. The schedule is an interval, not a cron expression. The prompt stands alone: each fire is a detached subagent with no view of this conversation. That subagent is a reminder, never a writer, and never a turn boundary. It does not audit, edit, commit, or resume the campaign. Its message lands in this session only if this session has gone idle. The campaign loop lives in `.grok/skills/process-plan`: finish the open section's items, stamp it with the review panel, take the next section, then the next phase. Stop only when `todo/implementation-plan.md` has no runnable work left, or the operator says stop. A commit, a green suite, or a status report is not a stop. Every future campaign copies the canonical reminder prompt in `.grok/skills/process-plan`. Adopting an older heartbeat replaces its prompt with that reminder. A heartbeat that resumes the campaign itself is stale. Write `build/grok-campaign-guard.json` when the run starts and delete that file, then the scheduled task, before a stop, a pause, a park, or a closeout. One guard per workspace. Adopt an existing heartbeat whose prompt contains `Grok run-guard heartbeat for ScratchPad` and this workspace. Do not create a second.

The Stop hook `.grok/hooks/campaign-stop.ps1` blocks every main-session `end_turn` while that state file names a run file that has neither a `## Closeout` heading nor a column-0 `PARKED` line. It does not give up because a previous block already continued the turn. It does not block subagents. The harness itself stops asking after 8 blocks in one turn. Deleting the state file is how an operator stop sticks.

## Tests

Daytime gates are focus-free. Read `.grok/skills/process-todo-section/gates.md`, then `docs/testing.md` when the card and the doc disagree: the doc wins. Interactive tests run only in the 02:00-06:50 local window. Outside it, record `Night-owed` and stamp. Quiet time never parks a flip. Do not set `SCRATCHPAD_INTERACTIVE_FORCE` unless the operator accepted that interruption in this turn. Do not create a second nightly scheduled task. `\ScratchPad\Nightly UI` already collects the debt.

## Reviews

`gpt-5.6-terra` at high effort runs panel rounds 1 and 2. `claude-sonnet-5` at high effort runs round 3 and signs off. A failed round falls back once to the other family: terra when Sonnet fails, Sonnet when terra fails. You implement. You do not sign your own stamp. Panel headings stay `Opus panel` for the Claude family and `GPT panel` for the Codex family, because the validator matches those words. The Telemetry line names the real model.
