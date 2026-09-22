---
name: process-plan
description: Grok campaign runner. Front door for todo/implementation-plan.md. Audits the plan, then runs process-phase on the first phase with a ready row, then the next ready phase after each closeout or park. Use when the user says process the plan, or asks how to run it. --audit is audit only. A named phase is one phase and does not chain.
---

# Process the Implementation Plan

Grok runner. Do not open `.claude/skills/process-plan`. Host rules: `.grok/rules/campaign-runner.md`.

The only front door for `todo/implementation-plan.md` when the user did not name a single phase. The file is a derived projection: processing it is not "pick a row and improvise", and it is not "tick the boxes".

This skill does not ship a section. It does not write a stamp. Writes stay serial, and the run this skill starts is the only writer on the tree.

## The loop

This is one continuous loop. You do not stop.

1. Finish every checklist item in the open section, in order. A green suite and a commit are the middle of the item, not the end of the turn. Start the next item in the same turn.
2. When the section's checklist is done, run the review panel and stamp it, then sync the plan. Then open the next ready section in the same phase.
3. When every section in the phase is stamped, write the closeout and start the next phase that still has a ready row.
4. Stop only when `todo/implementation-plan.md` has no open runnable work left: every row is stamped, or the only leftovers are blocked or runnable-elsewhere. That is the only halt.

A report to the operator is not a stop. A heartbeat is not a quota and not a turn boundary. If you were idle, the stall check means resume this loop, not ship one item and wait. Fix your own red gates. The TODO files say what to build. The review panel is the check that a finished section is actually done. The aim is a product that is complete and ready to ship.

## 0. Route

```powershell
git status -sb
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py query ready
```

| State | Do this |
| --- | --- |
| Another writer holds the tree | Stop and say so. Two writers on one tree is how a call ships without its interface. |
| Argument is `--audit` | Audit below, then stop. Do not start a run. |
| Argument is a phase (`0`, `Phase 0`) | That is `process-phase` for that phase only. It does not chain. |
| Empty argument, "the plan", "process the plan", or this file's path | Audit, then start `process-phase` on the first phase with a ready row, in this same turn. After that phase's closeout or park, pick the next ready phase. Repeat until no phase has a ready row. |

An audit-only reply is a process defect. Ending on the audit table while a ready phase exists is how a plan stalls. Starting the phase is the next action, in the same turn.

## 1. Audit the whole plan

```powershell
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py plan --check
python3 scripts/todo-graph.py query ready
python3 scripts/todo-graph.py query blocked
powershell -ExecutionPolicy Bypass -File tools/provision.ps1 -Verify
```

The audit is these commands and the recorded lines, nothing more: the deep phase repair belongs to `process-phase` step 1. Fix every FATAL before talking about shipping. If `plan --check` is stale, run `plan --sync`, then re-check. Run the provision verify half with the audit: if it faults, repair first (`tools/provision.ps1` without `-Verify`), then ship. Never tick a box in `implementation-plan.md` by hand. The boxes are a projection of the Implementation Order tables.

Record these lines in the run's findings file, not as the turn's last words:

1. Graph: fatal count.
2. Plan currency: the `--check` result.
3. Ready rows: count and first ref per phase.
4. Blocked rows: count and what blocks them.
5. The phase being started, and why it is first.

If no phase has a ready row, every remaining `[ ]` row is blocked or runnable-elsewhere in this context. Report them and stop. That is a genuine halt, and it is the only one this skill has.

Ready means runnable-now in the current context. `query ready` splits runnable-now from runnable-elsewhere, and this skill offers only runnable-now rows. Elsewhere rows stay visible in the recorded lines, never offered, never started. Re-run the query rather than trusting a previous list.

### Run guard

A run without a guard dies silently when the session stalls. Starting the first phase also starts the run guard, always.

Call `scheduler_list`. If a task already exists whose prompt contains `Grok run-guard heartbeat for ScratchPad` and this workspace path, adopt it: record its id, and do not create a second. If that prompt is not the reminder form below (it tells the heartbeat to resume the campaign, or it lacks `You are a reminder`), replace the prompt in place with `scheduler_create` on that same id. Otherwise create one with `scheduler_create`:

- `interval`: `10m`
- `durable`: true
- `fire_immediately`: false
- `prompt`: the canonical prompt below, with `<N>`, `<date>`, and `<workspace>` filled in

Record the id. Write `build/grok-campaign-guard.json` (gitignored) as JSON with `runner` = `grok`, `workspace` = the absolute workspace path, `phase` = the phase number, `run_file` = the repo-relative run file, and `scheduler_id` = the task id. The Stop hook reads this file. It allows the stop once the run file contains a `## Closeout` heading or a column-0 `PARKED` line, and it allows the stop when the file is gone.

The schedule is an interval. Do not pass a cron expression. Each fire is a detached subagent that cannot see this conversation, so the prompt has to stand alone. The subagent only checks whether the run is still open and returns a stall reminder. It never becomes a writer and it is not a quota. If this session is already shipping, ignore the reminder and keep going. If this session was idle, resume and keep shipping ready items in the same turn. Do not stop after one item to wait for the next fire. `fire_immediately` stays false so the first fire waits out the interval. A Grok schedule expires after 7 days. If a run is still open on that day, create the task again and record the new id.

Canonical prompt:

```text
Grok run-guard heartbeat for ScratchPad Phase <N> (workspace <workspace>). You are a reminder for the main campaign session, and only a stall check. You are not a writer and not a quota. You cannot see that session. Do not audit, do not edit, do not commit, do not start a phase, and do not resume the campaign yourself. You are not the Muse runner: do not read .claude/skills, and do not look for Muse session logs.

Read docs/phase-runs/<date>-phase-<N>.md. If that file has a heading line "## Closeout" or a column-0 line "PARKED", the run is finished. Delete build/grok-campaign-guard.json if it exists, delete this scheduled task, and reply: RUN FINISHED. Stop.

Otherwise reply with only this, filling the run file path:

STALL CHECK. If you are already shipping, ignore this and keep going. If you were idle, resume the loop in docs/phase-runs/<date>-phase-<N>.md: finish the open section, stamp it, then the next section, then the next phase. Do not stop after one item. Do not end the turn after a commit. Stop only when the plan has no runnable work left. Do not start another session.

This guard is deleted at closeout. Do not extend it.
```

## 2. After a phase closeout or park

`process-phase` ends in exactly one of three ways: the phase table is all `[x]` and closeout is written; every leftover `[ ]` row is blocked or runnable-elsewhere in this context and it parked; or the operator paused it.

A parked phase is not complete, and it is not a stall. Do not call it either.

```powershell
python3 scripts/todo-graph.py query ready
```

If another phase has a ready row, re-point the guard: `scheduler_delete` the old id, `scheduler_create` a new one from the canonical reminder prompt with the new phase and run file filled in, rewrite `build/grok-campaign-guard.json`, record the new id, and start `process-phase` on that phase in the same turn. Same session, same rules. Never park a ready phase on quiet time.

If no phase has a ready row, the remaining leftovers are blocked, runnable-elsewhere in this context, or the plan is done. Delete the guard file, delete the scheduled task, record both deletions in the findings file, and report which leftovers remain.

## 3. Deny

- Do not invent a side loop that ships rows outside `process-todo-section` plus `review-todo-section`.
- Do not start a second run, and do not start one while the current run is paused unless the operator said resume.
- Do not tick `implementation-plan.md` by hand.
- Do not claim a phase is complete while its table has `[ ]` rows.
- Do not treat a named phase as the whole plan. Chaining is this skill's job, and only this skill's.
- Do not end the turn on the audit table. Starting is the next action, in the same turn.
- Do not start a run without its guard file and its scheduled task, and do not end, stop, or pause a run without deleting both.
- Do not continue the campaign inside the heartbeat subagent. The heartbeat only reminds this session if it has gone idle. The loop above is the work. Do not end the turn after a commit.
