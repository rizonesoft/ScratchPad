# Simplify the process tooling: design

Date: 2026-10-18. Owner: Derick Payne. Decision: operator chose "cut to core" on 2026-10-18.

## Problem

The process around the app outgrew the app. On 2026-10-18 the repository held about 22k lines of app source and 32k lines of tests, against 57k lines of process scripts: `scripts/todo-graph.py` alone was 29,062 lines (19,370 of them self-test) and `scripts/todo-validate.py` 3,430 lines, with 35 of its 60 named rule classes enforcing review governance (risk acceptances, clearance chains, provenance, run IDs, panel telemetry, plan-review ledgers, grandfathering cutoffs). Plan reviews filed 1,612 findings, which became 885 more TODO items. Of 1,197 commits, 107 touched `src/` since 2026-09-01.

The trigger: finding D00-T02-S10-PR1 was fixed on 2026-09-20 and its rule was replaced outright on 2026-10-14, yet the tooling could never clear it (it was filed against the section that reviewed it), so it lived on a risk-acceptance waiver that had to be renewed every two weeks and turned CI red when a review date passed.

## Target

The TODO tree stays the plan. Everything that exists only to govern reviews goes.

**Kept, unchanged in shape:** `todo/` files (frontmatter, Goal, Current state, Inputs, Outcome, Implementation Order table, numbered sections with checklists and a Test checkpoint), `todo/implementation-plan.md` and the INDEX files, `§N` / `TNN §N` / `DNN TNN §N` references, `Started:`, `Verified:`, `Deferred:`, `Resolved:`, `Moved:`, `Needs:`, `Requires:`, the testing policy in `docs/testing.md`, the dotnet build and test suites, `scripts/agent_routing.py` and its hook, `build.yml`.

**`scripts/todo-graph.py` is rewritten in place** (same name and core commands, so the hundreds of prose references stay valid), target under 2,000 lines including its self-test:

- `validate`: frontmatter fields, one Implementation Order row per section and the reverse, a Test checkpoint per section, `[x]` only with a `Verified:` stamp covering it, dependencies resolve and are acyclic, cross-references are bidirectional, `Needs:`/`Requires:` name known values, `Moved:` targets exist, deferrals name an owner, every file is in its INDEX, the 55-section cap. Unknown stamp lines (`Review:`, `Plan review:`, `CRUD:`, `Night-owed:` and the rest on historical stamps) are ignored, never errors.
- `plan --sync` / `plan --check`: byte-identical projection to the old tool on the live tree.
- `query ready`, `query blocked`, `query stats`, `query deferred`, `resolve`.
- `self-test`: a temp fixture tree, one case per rule and command.

**Deleted:** `scripts/todo-validate.py`, `scripts/todo-adjacency.py`, `scripts/panel_slots.py`, `scripts/review_prompt.py`, `scripts/probe_runner.py`, `.conclave/`, the nightly machinery in `tools/` (`nightly.ps1`, `Nightly*.ps1`, `NightDebt*.ps1`, `notify_poster.py`, `check_heartbeat.py` and their tests), the unattended CI job, `docs/risk-register.md`, `todo/.warning-baseline`, `.github/owner-logins.json`, and governance-only docs. History stays in git under the tag `pre-simplify`.

**Review becomes one step:** after the section's gates pass, one independent review of the section diff by an Opus subagent (or Codex when the operator asks). Findings are fixed in the same range or filed as ordinary TODO items through `add-todo`. No panel, no plan review, no ledger, no waiver, no clearance. The stamp is:

```
> **Verified:** 2026-10-18 | §3 | <real command output>
> **Review:** Opus, approve after 2 fixes
```

**Skills shrink to four:** `add-todo` (capture and author, absorbing `create-todo`), `process-todo-section` (build, gates, review, stamp, commit, absorbing `review-todo-section`), `process-phase` (run a phase and close its files, absorbing `process-plan` and `process-todo-file`), and `groom-plan`. Each under about 80 lines.

**Foreground tests:** the operator's phase-close run becomes two plain commands in `docs/testing.md` (Primary with `SCRATCHPAD_BACKGROUND=1`, Interactive with `SCRATCHPAD_INTERACTIVE_FORCE=1`). Night debt stops being a ledger: a section that cannot run its own foreground tests says so in its `Verified:` line, and the phase-close run covers it. Failures become ordinary TODO items.

**TODO tree:** open sections whose only purpose is review or nightly governance (D00 T04, T05, T07, T08, T10, T11, and governance residuals elsewhere) are retired with a `Moved:` note pointing at this spec. Product and real test-infrastructure sections stay.

## Historical records

`docs/reviews/`, `docs/phase-runs/` and old stamps stay as read-only history; no tool parses them. Nothing is rewritten.

## Cost of reversing

Everything removed is recoverable from tag `pre-simplify`. Re-adding a governance rule later means writing it fresh against the small tool, which is the intended bar: a rule earns its place by preventing an observed failure.
