---
name: process-phase
description: Run a phase of todo/implementation-plan.md (or the whole plan) section by section through process-todo-section until every runnable row is shipped, then close the phase and any finished TODO files. Use when the user says process, run, or finish a phase or the plan.
---

# Process Phase

Ship rows until nothing runnable is left, then close out. With no phase named, start at the first phase that has a ready row and move to the next when it closes or parks.

The operator is present but is not the engine: decide, verify and fix what you can. If the operator says stop or pause, stop at once.

## 0. Open the run

```bash
git status -sb
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py plan --check || python3 scripts/todo-graph.py plan --sync
python3 scripts/todo-graph.py query ready
powershell -ExecutionPolicy Bypass -File tools/provision.ps1 -Verify
```

Fix any `validate` failure first; if provisioning faults, run `tools/provision.ps1` without `-Verify` to repair. Create `docs/phase-runs/<YYYY-MM-DD>-phase-<N>.md` and append to it as you go (it survives a lost session): each section's outcome, plan corrections, anything filed, stops.

## 1. Ship

For each row of the phase in table order that `resolve` exits `0` for and that is runnable in this context: run `process-todo-section` on it. Re-check skipped rows after each stamp, because rows unblock as others flip. A row blocked on another phase stays where it is. A broken reference in the phase table is repaired, not skipped.

Gaps you notice while shipping (a surface or control no section owns) are filed with `add-todo` the same turn.

## 2. Park or close

- **Park:** every open row left is blocked or runnable only elsewhere. Write a column-0 `PARKED <UTC> <reason>` line and list each leftover with what blocks it.
- **Close:** every row is `[x]`. Run the focus-free full suite once:

  ```powershell
  dotnet test src/ScratchPad.slnx --filter "Category!=Interactive&Category!=Primary" -e SCRATCHPAD_BACKGROUND=1
  ```

  List the two foreground commands from `docs/testing.md` as owed to the operator (they take the screen; do not wait for them). Write `## Closeout` in the run file: what shipped, what was corrected, what was filed.

For each TODO file whose rows are now all `[x]` or Moved: run its `## Verification` items, grep the touched paths for new `TODO`/`FIXME` markers (finish each or give it an owning section), confirm its open deferrals still name live owners, set `status: done` in its frontmatter, and move it to a Completed list in the domain `INDEX.md`.

Commit, sync the plan, and continue with the next phase that has a ready row unless a single phase was named. Stop when no phase has one, and report what shipped and what is left.

## Guardrails

- Rows ship only through `process-todo-section`. Never tick a plan box by hand.
- A parked phase is neither complete nor stalled; say which rows block it.
- No `--no-verify`, amends or force-pushes. A red gate is work to fix.
