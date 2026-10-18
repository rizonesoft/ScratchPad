# Simplify the process tooling: plan

Spec: `docs/specs/2026-10-18-simplify-process-design.md`. Each phase is one commit and leaves CI green.

## Phase 0: close D00-T02-S10-PR1 and freeze

- [x] Record acceptance A4 (outcome `closed`) on `docs/reviews/00-workspace/D00-T02-s10.md`: the flip-blocker list the finding critiqued was replaced on 2026-10-14 by "a red test of the feature holds the flip".
- [x] Write this spec and plan.
- [x] Tag the last commit before the cut as `pre-simplify`.

## Phase 1: rewrite `scripts/todo-graph.py` to the core

- [x] Capture the old tool's outputs on the live tree into scratch: `plan --sync` result, `query ready`, `query blocked`, `query stats`, `resolve` for a sample of references.
- [x] Write the new tool (parse, validate, plan, queries, resolve, self-test) with no imports outside the standard library and no git or `docs/reviews` reads.
- [x] Prove equivalence: `plan --sync` leaves `todo/implementation-plan.md` byte-identical; `ready`, `blocked`, `stats` and the `resolve` sample match; `validate` reports 0 fatal; `self-test` passes; each validate rule has a red fixture.
- [x] Delete `scripts/todo-validate.py`, `todo-adjacency.py`, `panel_slots.py`, `review_prompt.py`, `probe_runner.py`, `.conclave/`, `todo/.warning-baseline`.
- [x] `plan.yml`: keep `self-test`, `validate`, routing checks and the projection check; delete the unattended job and the probe step. Delete `.github/owner-logins.json`, `tools/check_heartbeat.py`, `tools/notify_poster.py`, `docs/risk-register.md`.
- [x] Pre-commit hook keeps working against the new `validate`.

## Phase 2: docs and skills

- [x] `todo/README.md`: drop the governance rule table, outcome matrix, clearance, plan-review, night-debt and grandfathering material; the stamp section shows `Verified`, `Review` (one line), `Deferred`, `Resolved`, `Moved`, `Started`.
- [x] Skills: merge into `add-todo`, `process-todo-section`, `process-phase`, `groom-plan`; delete the rest.
- [x] `AGENTS.md`: Validation lists only the kept commands; review is one Opus pass; drop the panel references.
- [x] `docs/agent-routing.md`, `CONTRIBUTING.md`, `README.md`, PR and issue templates: kept commands only.

## Phase 3: nightly machinery and governance docs

- [x] `docs/testing.md`: replace `tools/nightly.ps1` with the two foreground commands; drop night-debt collection.
- [x] Move the build-evidence and test-population functions the build and CI still need into `tools/TestBuild.ps1` (they lived in `NightlyParse.ps1`). Delete `tools/nightly.ps1`, `tools/Nightly*.ps1`, `tools/NightDebt*.ps1`, `tools/tasks/`, and docs that only serve them (`docs/nightly-*`, `docs/night-owed/`, `docs/incident-*`, `docs/owed-case-retirements.md`). Check each for a live caller first (`tools/provision.ps1`, `build.yml`, `soak.yml`, tests).
- [x] `.claude/hooks/campaign-stop.ps1` stays inert (no skill writes its guard file); removing its `Stop` entry from `.claude/settings.json` is the operator's edit.

## Phase 4: retire governance TODO sections

- [x] Each open D00 section whose purpose is review or nightly governance gets a `Moved:` note pointing at the spec, then `plan --sync`.
- [x] Open product and test-infrastructure sections stay untouched.

## Phase 5: verify

- [ ] `validate`, `self-test`, `plan --check` green; `dotnet build` clean; CI green on push.
- [ ] Line count report: process scripts before and after.
