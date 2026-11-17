---
name: process-todo-section
description: Ship exactly one TODO section end to end -- resolve it, check the plan still holds, build it, run its gates, get one independent review, write the stamp, flip the row and commit. Also re-checks a shipped section (audit). Use whenever asked to process, implement, ship, review, or finish a TODO section.
---

# Process TODO Section

One section, one logical change. The section is the contract: check it, build it, prove it, stamp it. Under Orchestrator (Carbon), Carbon performs pre-build validation against the live repository and `docs/design-contract.md` in Plan Mode (naming exact theme resources, shared `Chrome:` controls, UI states, and verification commands) before calling `exit_plan_mode` for that one section, and sets `Re-plan if:` so Hydrogen hands back after `stamp` and `ci_status.py` before resolving the next row (whether `Surface` is `yes` or `no`), or immediately mid-section on a missing theme resource or control, `COMPLETION: gaps` or a `P1`/`P2` architectural or design-contract finding, or two failed fix attempts.

## 0. Resolve

```bash
python3 scripts/todo-graph.py resolve "$ARGUMENTS"
```

| Exit | Do this |
| :-: | --- |
| `0` | Proceed. |
| `1` / `2` | Stop: the reference does not resolve. Say so; never guess a near match. |
| `3` | Already `[x]`: run the **Audit** step below instead. |
| `4` | Stop and name the unmet dependencies. |
| `5` | Stop: the work lives in the file the `moved` line names. |

A `needs` line means a Windows host; a `requires` line with something missing means that environment. Confirm it is here before starting. Check `git status` for unfamiliar work before building over it. Add `> **Started:** <UTC instant>` under the heading if there is none.

## 1. Check the plan still holds

Read the whole TODO file and the stamps of the sections this one depends on (they record what actually shipped). Then check every concrete claim in the section against the repository: paths, classes, counts, versions, protocol shapes, "nothing exists yet", XREF targets, open deferrals this section owns (`query deferred`). Bounded fact-checks can go to `sonnet-researcher` (`AGENTS.md` Delegation).

Fix drift in the TODO file before building, marked `**Corrected YYYY-MM-DD:**` with what it said and what is true. Make an unfalsifiable checkpoint falsifiable. Never narrow the section to fit the code you meant to write. If the whole section is wrong, stop and say what you propose. Where the source is silent, take the standard option and record it as a default.

Before building, commit the corrected contract and run the plan pass through `independent-review`. Resolve its findings first.

## 2. Build

Work the checklist top to bottom and tick each item when its `Done when` holds. Keep the diff to the section; file adjacent problems with `add-todo`. User data first: atomic writes, read back what was written, every destructive path confirmed, the failure path tested. Notepad behavior is read from the captures in `resources/baseline/stock/`, never memory; they are a behavior and layout reference, not a pixel target (`docs/design-contract.md`). UI sections consume the shared styles named in `**Chrome:**` and account for every control on the counterpart (working, or deferred to a named section).

## 3. Gates

Follow `gates.md` beside this skill (it defers to `docs/testing.md`): clean build, every test of the feature, the feature's own Primary and Interactive tests, one capture checked for defects when the section changes something the user sees, and `validate`. Never the whole suite. Quote exit codes and pass, fail and skip counts. A red test of the feature blocks the stamp.

## 4. Review

Commit the candidate first. Run `independent-review` on the three-pass schedule the pin sets (`.conclave/reviewers.toml`): one round on the candidate (`--kind round`), every real finding fixed in new commits with the affected gates rerun, then the completion review on the final commit (`--kind completion`), and a reconciliation (`--kind reconciliation`) only after a pass that asks for one, up to the pin's `pass_cap`. Name the section's findings file `docs/cross-model-reviews/<NN-domain>/D<NN>-T<NN>-s<N>.md` and pass your own harness as `--writer` (`claude` or `agy`); the dispatcher picks the reviewer. This replaces the former Opus-only section gate. Preserve the review record and name its path in the stamp. No returned review, unresolved findings, budget exhaustion or completion gaps permit a stamp.


## 5. Stamp, flip, commit

At the end of the section:

```
> **Verified:** <YYYY-MM-DD> | §N | <quoted gate evidence>
> **Review:** <pinned reviewer and exact model>, <findings path>, completion complete[, filed <refs>]
```

Close any deferral this section resolved (`Deferred:` to `Resolved:` in place). Flip the Implementation Order row to `[x]`, then:

```bash
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py plan --sync
```

Commit as `<area>: <what now works> (<ref>)` with the gate evidence in the body, and push.

## Audit (a shipped section)

Re-run the section's Test checkpoint and read its code against the checklist. If it still holds, say so in one line. If it regressed, flip the row back to `[ ]` with a dated note under the heading saying why, then fix it through steps 1 to 5; the new `Verified:` and `Review:` lines replace the old ones in place.

## Report

What was built, what the gates proved (quoted), plan corrections, review outcome, and what was filed instead of fixed.
