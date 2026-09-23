---
name: process-plan
description: Front door for todo/implementation-plan.md. Audits the plan, then runs process-phase on the first phase with a ready row, then the next ready phase after each closeout or park. Use when the user says process the plan, or asks how to run it. --audit is audit only. A named phase is one phase and does not chain.
---

# Process the Implementation Plan

The only front door for `todo/implementation-plan.md` when the user did not name a single phase. The file is a **derived projection**: processing it is not "pick a row and improvise", and it is not "tick the boxes".

This skill does not ship a section. It does not write a stamp. Writes stay serial, and the run this skill starts is the only writer on the tree.

## The loop

This is one continuous loop. You do not stop.

1. Finish every checklist item in the open section, in order. A green suite and a commit are the middle of the item, not the end of the turn. Start the next item in the same turn.
2. When the section's checklist is done, run the review panel and stamp it, then sync the plan. Then open the next ready section in the same phase.
3. When every section in the phase is stamped, write the closeout and start the next phase that still has a ready row.
4. Stop only when `todo/implementation-plan.md` has no open runnable work left: every row is stamped, or the only leftovers are blocked or runnable-elsewhere. That is the only halt, apart from an operator stop.

A report to the operator is not a stop. A heartbeat is not a quota and not a turn boundary. The self-correcting parts of the loop stay in it: correct drifted plan claims before building (`process-todo-section` step 2), file every gap and review advisory through `add-todo`, record lessons in the run file, and fix your own red gates. The aim is a product that is complete and ready to ship.

## 0. Route

```bash
git status -sb
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py query ready
```

| State | Do this |
| ----- | ------- |
| Another writer holds the tree | Stop and say so. Two writers on one tree is how a call ships without its interface. |
| Argument is `--audit` | Audit below, then stop. Do not start a run. |
| Argument is a phase (`0`, `Phase 0`) | That is `process-phase` for that phase only. It does not chain. |
| Empty argument, "the plan", "process the plan", or this file's path | Audit, then **start `process-phase` on the first phase with a ready row, in this same turn**. After that phase's closeout *or park*, pick the next ready phase. Repeat until no phase has a ready row. |

**An audit-only reply is a process defect.** Ending on the audit table while a ready phase exists is how a plan stalls while everyone agrees it is fine. Starting the phase is the next action, in the same turn.

## 1. Audit the whole plan

```bash
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py plan --check
python3 scripts/todo-graph.py query ready
python3 scripts/todo-graph.py query blocked
powershell -ExecutionPolicy Bypass -File tools/provision.ps1 -Verify
```

The audit is these commands and the recorded lines, nothing more: the deep phase repair belongs to `process-phase` step 1. Fix every FATAL before talking about shipping. If `plan --check` is stale, run `plan --sync`, then re-check. Run the provision verify half with the audit: if it faults, repair first (`tools/provision.ps1` without `-Verify`), then ship. **Never tick a box in `implementation-plan.md` by hand**: the boxes are a projection of the Implementation Order tables.

Record these lines **in the run's findings file**, not as the turn's last words:

1. Graph: fatal count.
2. Plan currency: the `--check` result.
3. Ready rows: count and first ref per phase.
4. Blocked rows: count and what blocks them.
5. The phase being started, and why it is first.

If no phase has a ready row, every remaining `[ ]` row is blocked or runnable-elsewhere in this context. Report them and stop. That is a genuine halt, and it is the only one this skill has.

Ready means runnable-now in the current context: `query ready` splits runnable-now from runnable-elsewhere, and this skill offers only runnable-now rows. Elsewhere rows stay visible in the recorded lines, never offered, never started; re-run the query rather than trusting a previous list.

### Run guard

A run without a guard dies silently when the session stalls, so starting the first phase also starts the run guard, always. The guard has two parts, and they cover different failures.

- **Stop hook** (`.claude/hooks/campaign-stop.ps1`, wired in `.claude/settings.json`): while the run is open, it blocks this session's end of turn and names the next ready row. It lets the turn end when the guard file is gone, the run file has a `## Closeout` heading or a column-0 `PARKED` line, or `query ready` prints `0 runnable now`. It blocks only the session named in the guard file, never subagents or a second session.
- **Stall breaker** (inside the hook): after 3 blocks in a row with no change to HEAD, the working-tree diff, the untracked set, or the run file, the hook lets the turn end and counts a trip in `build/claude-campaign-state.json`. Real progress resets the count. A session that cannot move is stuck, and pushing it again only spends money.
- **Heartbeat** (`CronCreate`): it fires only when this session is idle, and it runs inside this session with full context, so it is a real resume, not a detached reminder. It covers the turns the hook cannot hold: a tripped breaker, an API error, a crash out of the turn.

Start it in this order:

1. `CronList`. If a job whose prompt contains `Claude run-guard heartbeat for ScratchPad` exists, adopt it and do not create a second. Otherwise `CronCreate` with cron `3-59/5 * * * *`, recurring true, and the canonical prompt below with `<N>` and `<run file>` filled in.
2. Write `build/claude-campaign-guard.json` (gitignored) with `runner` = `claude`, `workspace` = the absolute workspace path, `phase` = the phase number, `run_file` = the repo-relative run file (`docs/phase-runs/<date>-phase-<N>.md`), `session_id` = the value of `$CLAUDE_CODE_SESSION_ID` read in the shell, and `cron_id` = the job id. Delete any stale `build/claude-campaign-state.json`.
3. Record the job id and the guard write in the run file's Critical events.

The run file's end markers are exact: a closeout is a line `## Closeout` followed by the closeout text, and a park is a column-0 line `PARKED <UTC stamp> <one-line reason>` followed by the park record. The hook and the heartbeat read only those two shapes.

The heartbeat is session-only: it dies with this session, and a recurring job expires after 7 days. A run still open on day 7 creates a new job and rewrites `cron_id`. A run resumed in a new session rewrites the guard with the new `session_id` and creates a new job; the old guard's session id no longer matches, so the hook never blocks the wrong session.

Operator stop: pressing Esc interrupts without the hook firing. A stop or pause said in words deletes the guard file, the state file, and the job (`CronDelete`), in that order, before confirming. Resume recreates all three before any other step.

Claude Code is the only runner (`AGENTS.md`, operator decision 2026-09-23). No other harness starts, adopts, or resumes a campaign.

Canonical prompt:

```text
Claude run-guard heartbeat for ScratchPad Phase <N> (run file <run file>). This session went idle while a campaign run may still be open. Check, then act, in this turn.

1. If build/claude-campaign-guard.json is missing, or <run file> has a line "## Closeout" or a column-0 line starting "PARKED": the run is over. CronDelete this job (find it with CronList by this prompt's first sentence), delete build/claude-campaign-state.json if present, and reply RUN FINISHED.
2. If build/claude-campaign-state.json has trips of 2 or more: the run stalled twice with no change to the tree. Do not resume. Append a Critical events line to the run file naming what blocks it, delete the guard file and the state file, CronDelete this job, and report the stall to the operator.
3. Otherwise resume the campaign under process-plan: re-run `python3 scripts/todo-graph.py query ready`, pick up the open section in the run file exactly where it stopped, and keep shipping: finish the section, stamp it, then the next section, then the next phase. A commit is not a stop. Stop only at closeout, park, or an operator stop.
```

## 2. After a phase closeout or park

`process-phase` ends in exactly one of three ways: the phase table is all `[x]` and closeout is written; every leftover `[ ]` row is blocked or runnable-elsewhere in this context and it parked; or the operator paused it.

A parked phase is **not** complete, and it is **not** a stall. Do not call it either.

```bash
python3 scripts/todo-graph.py query ready
```

If another phase has a ready row, re-point the guard to the new phase's run file (`CronDelete` the old job, `CronCreate` a new one from the canonical prompt, rewrite `run_file`, `phase`, and `cron_id` in the guard file, delete the state file, record the new id) and start `process-phase` on it in the same turn. Same session, same rules. Never park a ready phase on quiet time: completion-first binds the chain, not just the row. If no phase has a ready row, the remaining leftovers are blocked, runnable-elsewhere in this context, or the plan is done: delete the guard file, the state file, and the heartbeat job, record the deletions in the findings file, and report which.

## 3. Deny

- Do not invent a side loop that ships rows outside `process-todo-section` plus `review-todo-section`.
- Do not start a second run, and do not start one while the current run is paused unless the operator said resume.
- Do not tick `implementation-plan.md` by hand.
- Do not claim a phase is complete while its table has `[ ]` rows.
- Do not treat a named phase as the whole plan. Chaining is this skill's job, and only this skill's.
- Do not end the turn on the audit table. Starting is the next action, in the same turn.
- Do not start a run without its guard file and heartbeat job, and do not end, stop, or pause a run without deleting both.
- Do not delete the guard file to get out of a turn. The only exits are closeout, park, zero runnable rows, the stall breaker, and the operator.
