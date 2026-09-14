---
schema_version: 1
id: test-backbone
domain: 00-workspace
status: draft
title: "TODO-02 -- Test Backbone"
track: W0
---

# TODO-02 -- Test Backbone

> **Goal:** The harnesses every test in the project runs on: a unit-test project, a UI automation driver, a golden-capture store, an ACP loopback fixture, and a soak procedure.

> [!IMPORTANT]
> **Current state:** Only `D00 T01 §5`'s `dotnet test` wiring and smoke test exist. The framework is xUnit (operator stack decision); no UI driver exists, no captures exist. This file builds the backbone; `D06 T01` decides what runs on it.

## Inputs

- [`00-workspace/TODO-01-repo-and-toolchain.md`](./TODO-01-repo-and-toolchain.md) -- §5's `dotnet test` wiring, which this file extends
- -> XREF: D06 T01 §1 -- the automated test strategy this backbone serves; the strategy names suites, this file names harnesses

## Outcome

- Unit, UI-automation, and protocol tests each have a harness wired into one `dotnet test` run.
- Golden captures for parity surfaces live in a committed store with a refresh procedure.
- A loopback ACP agent lets protocol tests run with no network and no API keys.
- Flaky tests are quarantined by procedure, never by deletion.

**Adjacency:** all=not-applicable (test harnesses with no user-facing feature surface; the suites that run on them belong to their own domains)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Unit test project and framework | T01 §5 |  [x]   |
|   2   |   §2    | UI automation driver spike | T01 §5 |  [ ]   |
|   3   |   §3    | Golden capture store and refresh | §2 |  [ ]   |
|   4   |   §4    | ACP loopback fixture | §1 |  [ ]   |
|   5   |   §5    | Soak and quarantine procedure | §1, §2 |  [ ]   |

---

## 1. Unit Test Project and Framework

> **Started:** 2026-09-14T01:00:00Z

Why this section exists: unit tests need a home and a framework before the first class lands, or the first class lands untested. UI-free code lives in `net10.0` libraries so these tests run on Linux; Windows-only code stays in the app project.

**Replatformed 2026-09-13:** xUnit on .NET 10, the steward stack; the neutral-library rule above is what lets this suite run anywhere.

**Flag from T01 §5:** re-evaluate xUnit v3 with the MTP runner when standing up this suite: v3+MTP discovered zero tests on our stack (proven on our project and xUnit's own template, so v2 with VSTest shipped); record the re-evaluation verdict in `docs/testing.md` alongside item 1.

- [x] `tests/Unit/` hosts xUnit over the neutral libraries (the shop standard, proven in steward) with the choice recorded in `docs/testing.md`. Done when: the doc names the framework, its pinned versions, and why it won.
- [x] One passing test exercises the choice (a trivial pure function). Done when: `dotnet test tests/Unit` passes on Linux and fails when the assertion is inverted.
- [x] Test-only helpers live under `tests/Common/` so suites share fixtures without reaching into each other. Done when: the directory and its ownership rule exist.
- [x] CI runs the unit suite on every push. Done when: a deliberately failing probe test fails the run (reverted immediately).
- [x] Commit: `"workspace: add unit test project and framework"`

**Test checkpoint:** `dotnet test tests/Unit` green on Linux; inverted assertion red; CI mirrors both. Cheaper substitute that fails: a framework vendored but wired to nothing.

> **Verified:** 2026-09-14 | §1 | Unit 2/2 green locally on both OSes and in CI (run 34794828910); inverted assertion red locally; probe run 34795487610 red both jobs with the test named; run 34796097790 green after revert; v3/MTP re-evaluation reproduced zero-test discovery on the vendor template; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates f0b847c 1468835 7629678 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s1.md
> **CRUD:** applicable | test runs wrote results (read back via Passed/Failed counts); probe wrote failures (read back via the named test in both CI logs); inverted check wrote red locally
> **Duration:** 45
> **Implementer:** Muse Code (Meta Muse Spark)

## 2. UI Automation Driver Spike

Why this section exists: "automatic and complete" testing of a WinUI app needs a driver that clicks the real UI. Spike the options before committing the suites to one.

**Needs:** Windows host (build/test)

- [ ] `docs/ui-automation-spike.md` compares WinAppDriver and FlaUI (and any third contender) on our stub: launch, click, read text, screenshot. Done when: each contender has a measured verdict, not an opinion.
- [ ] The spike picks one driver and records the decision with its cost of reversal. Done when: the doc names the winner and what switching would cost.
- [ ] `tests/UI/` runs one passing drive of the stub window (launch, assert title, close) under the winner. Done when: the UISmoke drive passes on a Windows runner in CI.
- [ ] The spike records what the driver cannot do (if anything), with each gap routed to a named D06 section. Done when: no silent gaps remain.
- [ ] Commit: `"workspace: spike UI automation drivers and wire the winner"`

**Test checkpoint:** The UISmoke drive passes on a Windows runner in CI against the real stub window; the spike doc carries measured verdicts. Cheaper substitute that fails: a driver chosen by reputation with no drive of our binary.

## 3. Golden Capture Store and Refresh

Why this section exists: parity with Windows 11 Notepad is checkable only against captures. The store makes "matches Notepad" a diff, not an opinion.

**Needs:** Windows host (build/test)

- [ ] `resources/baseline/` holds the first captures (main window, tab bar, menus, settings) taken from stock Windows 11 Notepad with the capture procedure in `resources/baseline/README.md`. Done when: each capture names its source build.
- [ ] `tests/UI/` compares the app's rendered surfaces against the captures with a committed tolerance policy. Done when: a deliberate 10px layout shift fails the comparison.
- [ ] The refresh procedure re-captures after intentional changes and requires review of the diff. Done when: the procedure is written and was used once for real.
- [ ] Captures are versioned beside the code they verify, so a checkout is self-consistent. Done when: no capture lives outside the repo.
- [ ] Commit: `"workspace: add golden capture store and refresh"`

**Test checkpoint:** A deliberate layout shift fails the comparison; a reviewed refresh passes. Cheaper substitute that fails: screenshots in a chat thread instead of a committed store.

## 4. ACP Loopback Fixture

Why this section exists: protocol tests must run with no network, no API keys, and no real agent. A loopback fixture speaks ACP back at the client deterministically.

- [ ] `tests/Fixtures/AcpLoopback/` (a `net10.0` console app, spawned through the .NET host on either OS) implements a scripted fake agent over stdio: it answers `initialize`, `session/new`, and `session/prompt` from a script file. Done when: a test drives a full prompt turn against it on Linux.
- [ ] The fixture can inject faults on demand (malformed JSON, dropped responses, slow streams). Done when: each fault has a test proving the client survives it.
- [ ] The fixture validates every message it receives against the ACP schema and fails loudly on violations. Done when: a deliberately malformed client message fails the test.
- [ ] `D03` sections consume this fixture rather than building their own fakes. Done when: the ownership is recorded here and referenced there.
- [ ] Commit: `"workspace: add ACP loopback fixture"`

**Test checkpoint:** A scripted prompt turn passes; each injected fault is survived; a malformed client message fails. Cheaper substitute that fails: tests that pass against a mock that accepts anything.

## 5. Soak and Quarantine Procedure

Why this section exists: UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks.

- [ ] `docs/soak-and-quarantine.md` defines the nightly soak (what runs, how long, where results go). Done when: the soak ran once and its log is linked.
- [ ] Quarantine moves a flaky test to a named list with its failure signature and owner, and the suite stays green without it. Done when: the list exists with its fields, even if empty.
- [ ] A quarantined test owes a fix or a removal decision within a committed window. Done when: the window and the escalation are written.
- [ ] Deleting a test without a recorded decision fails review. Done when: the rule is written in the procedure.
- [ ] Commit: `"workspace: add soak and quarantine procedure"`

**Test checkpoint:** A deliberately flaky probe test is quarantined by the procedure, the suite stays green, and the probe is then removed with its decision recorded. Cheaper substitute that fails: a retry loop that hides the flake.

## Verification

- [ ] `dotnet test` green, all harnesses exercised
- [ ] `python3 scripts/todo-graph.py validate` clean
