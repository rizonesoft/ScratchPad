---
schema_version: 1
id: runner-loop
domain: 00-workspace
status: active
title: "TODO-05 -- Runner Loop"
depends_on: []
track: W0
---

# TODO-05 -- Runner Loop

> **Goal:** The runner skills that ship the plan stay wired to the file lifecycle: closeouts close fully-shipped files through `process-todo-file`, so file-level `## Verification` blocks execute instead of waiting to be remembered.

> [!IMPORTANT]
> **Current state:** `.claude/skills/process-phase/SKILL.md` Step 4 and the `process-plan` closeout ship rows and write closeouts without invoking `process-todo-file` (verified 2026-09-19: zero mentions across `process-phase`, `process-plan`, `process-todo-section`), while every TODO file carries a `## Verification` block only that skill executes. This file's §1 wires the invocation into both closeouts.

## Inputs

- [process-phase skill](../../.claude/skills/process-phase/SKILL.md) -- Step 4 closeout §1 extends with the file-closeout invocation
- [process-plan skill](../../.claude/skills/process-plan/SKILL.md) -- plan closeout §1 extends the same way for chained runs
- [process-todo-file skill](../../.claude/skills/process-todo-file/SKILL.md) -- the file closeout both closeouts invoke

## Outcome

- Phase and plan closeouts close every touched file whose rows are all `[x]` before the closeout is written.
- File-level `## Verification` blocks execute as part of the run, not on operator memory.

**Adjacency:** all=not-applicable (runner-skill wiring with no user-facing feature surface; the app surfaces the runs ship declare their own adjacency in their own files)

**Adjacency rationale:** This file touches only runner skill prose: two closeout steps gain one invocation line each. No editor, protocol, agent, voice, or packaging surface changes, so no adjacency key applies; the line mirrors T01's toolchain stance for the same reason.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Runner file-closeout wiring | -- |  [ ]   |

|  2   |  §2    | Run-guard proof | -- |  [ ]   |
---

## 1. Runner File-Closeout Wiring

Why this section exists: the runner loop ships rows and writes closeouts but no closeout step invokes `process-todo-file`, so file-level `## Verification` blocks execute only when someone remembers. Both closeouts name the invocation: per touched file whose rows are all `[x]`, run file closeout after the all-green confirm and before writing the closeout. -> SOURCE: operator-finding-2026-09-19-runner-closeout (closeout never invokes process-todo-file; verified 2026-09-19: zero mentions across process-phase, process-plan, process-todo-section).

**Groomed 2026-09-23:** Anchor corrected: `process-plan` has no closeout step; the anchor is "## 2. After a phase closeout or park" in `.claude/skills/process-plan/SKILL.md`, which since 0da6bd2 also tears down the run guard (guard file plus CronDelete). The item reads: `process-plan` §2 invokes `process-todo-file` for fully-shipped touched files before the guard teardown.

- [ ] `process-phase` Step 4 runs file closeout: per touched file whose rows are all `[x]`, invoke `process-todo-file` after the all-green confirm and before writing the closeout, so the closeout reports file completions. Done when: the step names the invocation with its trigger.
- [ ] `process-plan` closeout carries the same line: chained runs end there, not in the phase, so the plan closeout closes fully-shipped touched files the same way. Done when: the step names the invocation with its trigger.
- [ ] Commit: `"workspace: wire file closeout into runner closeouts"`

**Test checkpoint:** both closeout steps name `process-todo-file` with the fully-shipped trigger; grep proves the lines; a walkthrough over the current tree names the files that would close. Falsifiable by any closeout text missing the invocation.

## 2. Run-Guard Proof

Why this section exists: `.claude/hooks/campaign-stop.ps1` blocks the campaign session's end of turn, trips a stall breaker, fails open, and writes `build/claude-campaign-*.json`, and it is wired into every session through `.claude/settings.json`, yet it has no self-test, no fixtures, and no TODO owner; its deleted predecessor had `.grok/scripts/campaign-selftest.ps1` (groom 2026-09-23).

- [ ] A checked-in self-test drives the hook with fixture payloads: another session allows, a missing or malformed guard allows, a `## Closeout` heading or column-0 `PARKED` line allows, zero runnable rows allows, the campaign session blocks, three blocks with no tree change trip the breaker, a tree change resets it, and the state file reads back. Done when: each case asserts its exit and output
- [ ] The self-test runs where the plan gates run, so a hook edit that breaks a case fails. Done when: flipping one allow to a block fails the gate
- [ ] Commit: `"workspace: prove the run guard"`

**Test checkpoint:** the hook self-test passes every case and fails on a deliberately broken hook. Cheaper substitute that fails: testing the hook only by running a campaign.

## Verification

- [ ] Both closeout steps name `process-todo-file` with the fully-shipped trigger
- [ ] `python3 scripts/todo-graph.py validate` clean
