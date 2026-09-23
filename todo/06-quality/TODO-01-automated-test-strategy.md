---
schema_version: 1
id: automated-test-strategy
domain: 06-quality
status: draft
title: "TODO-01 -- Automated Test Strategy"
depends_on: ["test-backbone"]
track: Q1
---

# TODO-01 -- Automated Test Strategy

> **Goal:** "Automatic and complete" is a written bar with measured compliance: layers, coverage, UI suites, and a flake policy that keeps the suite honest.

> [!IMPORTANT]
> **Current state:** No strategy is written. The `D00 T02` harnesses exist (or land first); this file decides what runs on them and what "complete" means.
>
> **Recorded 2026-09-17 (groom):** since 2026-09-17 CI proves build plus launch smoke only and the suites run locally on the dev box, so the `in CI` enforcement below is a placement §1 must decide per layer (CI vs local runs), not a settled fact. §1 stays the strategy owner; this note only records the constraint.

## Inputs

- [`00-workspace/TODO-02-test-backbone.md`](../00-workspace/TODO-02-test-backbone.md) -- the harnesses this strategy fills
- -> XREF: D00 T02 §5 -- the soak and quarantine procedure this strategy's flake policy extends

## Outcome

- Every layer (unit, integration, UI, protocol, perf) has an owner, a suite, and a bar.
- Coverage is measured per layer with a committed floor that the §1 placement enforces (CI or local runs). **Corrected 2026-09-17 (groom):** was "that CI enforces"; CI runs no suites since 2026-09-17, so §1 places each enforcement.
- UI suites drive the real app for every Notepad surface and every AI surface.
- Flakes are quarantined by procedure with a fix window, never deleted.

**Adjacency:** all=not-applicable (test strategy with no user-facing feature surface; the suites it defines live with their features)

**Groomed 2026-09-23:** CI scope corrected: `build.yml` runs no `dotnet test` since the 2026-09-17 operator decision (its header), so every "CI fails the run" or "green in CI" claim here reads as the §1-placed run (local full or nightly) failing or passing.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Strategy doc with layers and bars | D00 T02 §1 |  [ ]   |
|   2   |   §2    | Coverage floors enforced in CI | §1 |  [ ]   |
|   3   |   §3    | Notepad parity UI suites | §1, D02 T02 §5 |  [ ]   |
|   4   |   §4    | AI surface UI suites | §1, D05 T02 §5 |  [ ]   |
|   5   |   §5    | Perf budgets enforced in CI | §1 |  [ ]   |
|   6   |   §6    | Flake policy and quarantine operation | §1, D00 T02 §5 |  [ ]   |

---

## 1. Strategy Doc with Layers and Bars

Why this section exists: "automatic and complete" without a written definition is a slogan. The doc makes it a bar with owners.

**Groomed 2026-09-23:** Done-when corrected: the Linux bar is retired (the correction on the same item), so item 4 is done when `dotnet test src/Notepad.Neutral.slnf` is green on Windows with the WindowsPath rule stated.

- [ ] `docs/test-strategy.md` defines the layers (unit, integration, UI, protocol, perf), each with owner, suite location, and bar. Done when: every layer names all three.
- [ ] The doc defines what "complete" means per layer (behavior coverage, not line coverage alone). Done when: each definition is falsifiable.
- [ ] The doc maps every domain's surfaces to the suites that prove them. Done when: no surface is unmapped.
- [ ] The doc sets the platform rule for Windows-semantics unit tests (JumpList, protocol-association, launch-args path suites): neutral code never branches on the running OS for Windows-path strings (the `WindowsPath` rule, D00 T02 §6 track A), and `dotnet test src/Notepad.Neutral.slnf` is green on Linux. Done when: the neutral suite passes on Linux with the rule stated. **Corrected 2026-09-17 (groom):** was "they skip honestly or live in a Windows-only suite ... with every platform skip named"; D00 T02 §6 fixed the 16 Linux failures at root (explicit Windows-path handling, suites passing on Linux, not skipping). -> SOURCE: phase-1 run 4 (2026-09-16), 16 Linux failures while the same suites stand 285/285 on Windows. **Corrected 2026-09-19:** the neutral suite proves green on Windows (slnf or slnx); the Linux-green bar is retired (operator decision 2026-09-19: Windows-only CI) but the `WindowsPath` rule stands.
- [ ] Commit: `"quality: write the automated test strategy"`

**Test checkpoint:** A reviewer verifies every surface maps to a suite and every bar is falsifiable; gaps are filed, not waived. Cheaper substitute that fails: a strategy that says "test everything".

## 2. Coverage Floors Enforced in CI

Why this section exists: floors that CI does not enforce are wishes. Measure per layer, fail below the floor.

- [ ] Coverage is measured per layer with the tooling recorded in the strategy doc. Done when: a coverage report exists for every layer.
- [ ] CI fails the run when any layer drops below its committed floor. Done when: a probe deletion of tests fails the run (reverted immediately).
- [ ] Floors ratchet only upward; lowering one needs a recorded decision. Done when: the rule is written and the history shows no silent drop.
- [ ] Uncoverable code (platform shims, defensive branches) is marked with reason, not silently excluded. Done when: each marking names its reason.
- [ ] Commit: `"quality: enforce coverage floors in CI"`

**Test checkpoint:** Probe test deletion fails CI; floors documented; markings reasoned. Cheaper substitute that fails: one global percentage that hides an untested layer.

## 3. Notepad Parity UI Suites

Why this section exists: the clone claim is proven surface by surface, automatically, on every run.

**Groomed 2026-09-23:** Corrected: `PollThemeSide` now calls `UiCapture.PrintCapture`, which enters UiDpi and uses PrintWindow full content (MainWindowTests.cs:146, UiCapture.cs:218), so the DPI half is fixed; the vacuous dark and system pass still stands, so add a non-black guard.

- [ ] `tests/UI/Parity/` drives every Notepad surface in the coverage table (`TODO-00-INDEX.md`) through the real UI. Done when: every row maps to a passing suite.
- [ ] Each suite compares against the `D00 T02 §3` captures within the committed tolerance. Done when: a deliberate deviation fails the suite.
- [ ] The suites classify into the D00 T02 §8 tiers: background-safe assertions run in the default set, placement premises in `Category=Primary`, physical-input flows in fenced `Category=Interactive` with quiet-hours collection. Done when: every suite names its tier and the default/Primary gates prove the runnable tiers. **Corrected 2026-09-19 (§8 plan review):** was "run in CI on a Windows runner"; CI is build-plus-launch-smoke only since c2c2362, UI proof is local tiers.
- [ ] Found 2026-09-14: `tests/UI/MainWindowTests.cs` `PollThemeSide` captures without `UiDpi.Enter`, so at 150 percent session DPI the reads virtualize to black; on Conclave-PC `ThemesRenderWithMica` light fails while dark and system pass vacuously. Harden the capture path (PMV2-aware captures or a non-black guard) and re-prove the matrix. Done when: `dotnet test tests/UI --filter ThemesRenderWithMica` passes on the dev box with center pixels verified non-black in all three themes. **Corrected 2026-09-17 (groom):** was "passes on Conclave-PC"; the Conclave-PC VM retired 2026-09-14, so the matrix re-proves on the dev box at 150 percent.
- [ ] Commit: `"quality: drive Notepad parity in UI suites"`

**Test checkpoint:** Suites green in their D00 T02 §8 tiers; deliberate deviations fail; coverage table fully mapped. Cheaper substitute that fails: parity checked by hand before release.

## 4. AI Surface UI Suites

Why this section exists: the AI panel, prompts, diffs, and elicitations are driven automatically against scripted agents, not clicked by hand.

- [ ] `tests/UI/AiPanel/` drives the panel, prompts, tool display, diff review, apply, and elicitation against the loopback. Done when: each flow passes.
- [ ] Consent and denial paths are driven, not just the allow path. Done when: the denial matrix passes.
- [ ] The suites classify into the D00 T02 §8 tiers: background-safe assertions run in the default set, placement premises in `Category=Primary`, physical-input flows in fenced `Category=Interactive` with quiet-hours collection. Done when: every suite names its tier and the default/Primary gates prove the runnable tiers. **Corrected 2026-09-19 (§8 plan review):** was "run in CI on a Windows runner"; CI is build-plus-launch-smoke only since c2c2362, UI proof is local tiers.
- [ ] Commit: `"quality: drive AI surfaces in UI suites"`

**Test checkpoint:** Suites green in their D00 T02 §8 tiers with denial paths proven. Cheaper substitute that fails: AI flows tested by hand because "scripting agents is hard".

## 5. Perf Budgets Enforced in CI

Why this section exists: budgets nobody measures are decorations. The perf tests from every domain run here as one enforced gate.

- [ ] `tests/Perf/` collects the latency, memory, and responsiveness budgets from all domains. Done when: every committed budget has a test.
- [ ] CI fails the run on budget breach with the offending measurement named. Done when: a probe slowdown fails the run (reverted immediately).
- [ ] Budgets are recorded with their hardware assumptions so results are comparable. Done when: the assumptions are written.
- [ ] Commit: `"quality: enforce perf budgets in CI"`

**Test checkpoint:** Budgets measured in CI; probe breach fails. Cheaper substitute that fails: perf tested on the dev machine before release.

## 6. Flake Policy and Quarantine Operation

Why this section exists: the quarantine procedure from `D00 T02 §5` needs an operator: triage cadence, fix windows, and escalation. Mass-failure runs need the same operator with a different verdict: a runner incident, not N test quarantines.

- -> XREF: D00 T02 §7 -- the incident-triage item is filed from its round-4 run; its review record carries the incident evidence.

**Groomed 2026-09-23:** Already written: docs/soak-and-quarantine.md "Fix-or-remove window" (7 days, day-3 note, auto-RED past due through D00 T02 §15); the strategy doc cites it.

- [ ] The flake policy sets triage cadence, fix window, and escalation for quarantined tests. Done when: the policy is written in the strategy doc.
- [ ] A quarantined test is retried on its schedule and either reinstated or removed with a recorded decision. Done when: the lifecycle is demonstrated once for real.
- [ ] Quarantine size is reported in CI; growth past the committed limit fails the run. Done when: the limit is tested.
- [ ] Mass-failure runs (many tests red at once on binaries proven green before and after) are triaged as runner incidents with a recorded verdict, not filed as N test quarantines. Done when: the 2026-09-17 incident series (runs 35238610077, 35241743948) is recorded as the first verdict under the policy, with its evidence (TODO-only or docs-only commits, adjacent greens, same image).
- [ ] Commit: `"quality: operate the flake policy"`

**Test checkpoint:** Lifecycle demonstrated for real; quarantine growth fails CI; one incident verdict recorded. Cheaper substitute that fails: quarantine as a trash can with no triage.

## Verification

- [ ] `dotnet test` green
- [ ] Every surface mapped to a suite, every suite green in CI
- [ ] `python3 scripts/todo-graph.py validate` clean
