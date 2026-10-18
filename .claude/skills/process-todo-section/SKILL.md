---
name: process-todo-section
description: Ship exactly one TODO section end to end -- resolve it, check the plan still holds, build it, run its gates, get one independent review, write the stamp, flip the row and commit. Also re-checks a shipped section (audit). Use whenever asked to process, implement, ship, review, or finish a TODO section.
---

# Process TODO Section

One section, one logical change. The section is the contract: check it, build it, prove it, stamp it.

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

## 2. Build

Work the checklist top to bottom and tick each item when its `Done when` holds. Keep the diff to the section; file adjacent problems with `add-todo`. User data first: atomic writes, read back what was written, every destructive path confirmed, the failure path tested. Notepad surfaces are proven against the captures in `resources/baseline/`, never memory. UI sections consume the shared styles named in `**Chrome:**` and account for every control on the counterpart (working, or deferred to a named section).

## 3. Gates

Follow `gates.md` beside this skill (it defers to `docs/testing.md`): clean build, every test of the feature plus the golden set, the feature's own Primary and Interactive tests, the visual check against Notepad for anything the user sees, and `validate`. Never the whole suite. Quote exit codes and pass, fail and skip counts. A red test of the feature blocks the stamp.

## 4. Review

Commit the candidate first. Then get **one independent review** of the diff (`git show <sha>` or the range) against the section text: an `Agent` call with `subagent_type: "general-purpose"` and `model: "opus"`, or Codex when the operator asks for it. Brief it with the section text, the diff, and three questions:

1. Does it do exactly what the section asks, without extra scope?
2. Is it correct: logic, failure paths, trust boundaries (file writes, encodings, consent, protocol validation, values the UI decides that nothing verifies)?
3. Did it break a caller, consumer, test, or adjacent workflow?

Ask for findings with `file:line` and the concrete failure, or `approve`. Verify each finding against the code before acting on it. Fix real ones in new commits (never amend), re-run the affected gates, and re-review the new diff. At most three rounds; anything real left after that, or anything out of the section's scope, is filed with `add-todo` and named in the report.

## 5. Stamp, flip, commit

At the end of the section:

```
> **Verified:** <YYYY-MM-DD> | §N | <quoted gate evidence>
> **Review:** Opus, <approve | approve after N fixes>[, filed <refs>]
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
