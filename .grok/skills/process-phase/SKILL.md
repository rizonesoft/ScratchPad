---
name: process-phase
description: Grok campaign runner. Attended runner that takes one phase of todo/implementation-plan.md to 100%. Repair the phase, gap-check it, then ship section after section via process-todo-section plus review-todo-section. Park only when every leftover row is blocked or runnable-elsewhere in this context. Use when the user says process, run, or finish a phase.
---

# Process Phase

Grok runner. Do not open `.claude/skills/process-phase`. Host rules: `.grok/rules/campaign-runner.md`. The run guard is specified in `process-plan`. Follow that spec. Do not invent a cron expression.

One phase, start to 100%, or parked when the rest of it is blocked or runnable-elsewhere here. You do not stop in between.

The loop, from `process-plan`: finish every checklist item in the open section before leaving it, then the review panel and the stamp, then the next section. A commit is not a stop. When this phase is closed or parked, return to `process-plan` and start the next ready phase in the same turn. The campaign stops only when the plan has no runnable work left, or the operator says stop.

Exactly three endings. Zero open rows and a written closeout. Every leftover row blocked or runnable-elsewhere here, so the phase is parked and `process-plan` moves to the next ready phase. Or the operator's own pause. There is no fourth. A parked phase is neither complete nor a stall.

The whole plan is `process-plan`, not this skill. This skill is one named phase. When the session entered through `process-plan` with no phase argument, return to it after closeout or park so it can start the next ready phase. A session pinned to one phase ends here.

The user is present but is not the engine. Talk to them when something genuinely needs them. Never wait on them for anything you can decide, verify, or fix yourself.

Completion-first never buys completion with a bypass. `--no-verify`, `--amend`, and force-push are forbidden to this run. If a gate refuses, the run fixes the cause. It does not push, and it does not pause: a red gate is work. A failed push is a red gate, not a skip: diagnose, fix, retry. Never leave an unpushed stack on the theory that CI will catch up later.

Attended means interruptible, not stoppable. When the user sends a message mid-run, answer it briefly and continue the loop in the same turn. The one exception outranks everything: if the user tells you to stop or pause the run, obey immediately, confirm, and wait. Their instruction beats completion-first, always. Stopping or pausing deletes the guard state file and the scheduled task first, so no heartbeat resumes against the operator's instruction. Resume recreates both before any other step.

## Step 0 -- open the run

Check that no other writer holds the tree (`git status`, and ask about unfamiliar uncommitted work). Then open the run's findings file: `docs/phase-runs/<YYYY-MM-DD>-phase-<N>.md` (create `docs/phase-runs/` if absent). Every finding this run produces is appended there the moment it is made, not at the end. Structure:

```markdown
# Phase run: <heading>

## Phase repairs
## Shipped-row verification
## Gap audit
## Sections
## Critical events
## Lessons
```

Read the most recent prior file in `docs/phase-runs/` for this phase, if one exists. Anything unresolved there is this run's first input.

Run guard: if this session entered through `process-plan`, the plan owns the guard. Call `scheduler_list`, confirm one task whose prompt contains `Grok run-guard heartbeat for ScratchPad` and this workspace, and record the id. Do not create a second. If that prompt tells the heartbeat to resume the campaign, replace it in place with the canonical reminder prompt from `process-plan`. If pinned to this phase standalone, start the guard exactly as `process-plan` specifies, with this phase's run file, and record its id in Critical events.

## Step 1 -- repair the phase before running it

The phase table is a plan, and plans drift. Fix it before building on it. In order:

1. `python3 scripts/todo-graph.py validate`: fix every FATAL now.
2. `python3 scripts/todo-graph.py plan --check`: if stale, `plan --sync`.
3. For every open row in the phase: `python3 scripts/todo-graph.py resolve '<ref>'`. Record the exit code.
   - Exit 4 with unmet deps outside this phase is a leftover, not a stall. Leave the row here, ship every exit-0 runnable-now row, and park when only leftovers remain. Do not drag a later phase's dependency into this one.
   - Exit 1 or 2: the row cites a section that does not exist. Repair the reference against the TODO file. A broken ref is repairable work, so it blocks a park.
   - A row whose `resolve` verdict is runnable-elsewhere in this context is a leftover, whatever the exit code. It stays visible, never ships here, and parks with the rest when only leftovers remain. Re-run `resolve` rather than trusting a previous verdict.
4. Read each open section's TODO file top to bottom, looking for phase-level staleness only (per-section validation happens again inside `process-todo-section`): sections whose work already shipped elsewhere, sections made moot by a decision since, callouts whose blocker no longer exists. Correct with dated `**Corrected YYYY-MM-DD:**` notes.

### Step 1b -- shipped rows are verified, not trusted

`[x]` rows in the phase are claims, and a claim is checked. At run start, re-check shipped rows that an open row in this phase depends on. For each spine row:

1. Confirm a `Verified:` stamp covers it (`resolve` exits 3 and the stamp names the section).
2. Re-run its `Test checkpoint` command if it names one. A checkpoint that no longer passes means the section regressed after shipping: treat it as this phase's work (diagnose, fix forward, re-review with `review-todo-section` in audit stance). UI checkpoints follow `.grok/skills/process-todo-section/gates.md`.
3. If anything about the implementation looks wrong against today's source, invoke `review-todo-section` in audit stance on that section. It either re-confirms the row or downgrades it to `[ ]`, and a downgraded row rejoins the loop.

## Step 2 -- gap-audit the phase

Read the phase as a user would use it, end to end, and ask what is missing: surfaces with no owner, controls with no section, handoffs between domains nobody specified. File each gap with `add-todo` (with evidence and an owner), pull the resulting rows into the phase table where they belong, and sync the plan. A gap found is a gap filed the same turn.

## Step 3 -- ship the phase, one row at a time

In table order, for each open row: `process-todo-section`, then `review-todo-section`. Record each outcome in the findings file's Sections log. After each stamp, sync the plan. Commit per section. Push per the two-push discipline (ship push, then stamp push).

Skip rows whose `resolve` is not exit 0 or whose verdict is runnable-elsewhere here, and re-check them after each stamp. Never park a ready row on quiet time: ship-with-debt rows run now and the collector closes their debt async. When every remaining open row is exit 4 (or otherwise unshippable here), the phase parks: write the park record (each leftover, what blocks it, where the blocker lives) and a column-0 line whose first word is `PARKED`. Commit the findings file. If pinned standalone, delete `build/grok-campaign-guard.json` and the scheduled task, and record the deletion. Then return to `process-plan` (or end, if pinned).

## Step 4 -- closeout

When the table is all `[x]`: re-run the full suite once (Interactive skips outside 02:00-06:50 are an honest green-plus-skipped result; quote them; do not force them), confirm the plan shows the phase complete, write the closeout under a heading `## Closeout` (what shipped, what was repaired, what was learned), commit, delete the guard state file and the scheduled task if pinned standalone (the plan deletes them when chained), and report. A phase is complete when its table says so and the closeout is written.

## Guardrails

- Do not invent a side loop that ships rows outside `process-todo-section` plus `review-todo-section`.
- Do not tick `implementation-plan.md` by hand. Sync it.
- Do not claim a phase complete while its table has `[ ]` rows.
- Do not call a parked phase complete, and do not call it a stall.
- Do not end the turn on the audit. Ship, park, or close out.
- Do not end the turn after one checklist item. The heartbeat is a stall detector, not the work loop. While items remain ready, start the next one in the same turn.
- Do not leave a run guarded after it ends, and do not pause with the guard live. Stop deletes the state file and the scheduled task first. Resume recreates them.
