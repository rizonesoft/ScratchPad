---
schema_version: 1
id: acp-conformance-harness
domain: 06-quality
status: draft
title: "TODO-02 -- ACP Conformance Harness"
depends_on: ["acp-transport-lifecycle"]
track: Q1
---

# TODO-02 -- ACP Conformance Harness

> **Goal:** Protocol claims are proven against scripted fake agents and schema validation: every method, every version, every adapter we claim.

> [!IMPORTANT]
> **Current state:** The `D00 T02 §4` loopback exists for unit-level protocol tests. This file builds the conformance layer above it: scripted agents, schema pins, and the adapter matrix.

## Inputs

- [ACP schema](https://agentclientprotocol.com/protocol/v1/schema) -- the pinned conformance target
- [`00-workspace/TODO-02-test-backbone.md`](../00-workspace/TODO-02-test-backbone.md) -- §4's loopback, which this harness extends

## Outcome

- Scripted fake agents cover every method and notification in both directions.
- The client validates against a pinned schema revision with drift detection.
- Claimed adapters are compatibility-tested on a schedule, with results recorded.

**Adjacency:** all=not-applicable (protocol conformance with no user-facing feature surface)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Scripted agent library | D00 T02 §4 |  [ ]   |
|   2   |   §2    | Schema pin and drift detection | §1 |  [ ]   |
|   3   |   §3    | Version matrix (v1 and v2) | §1 |  [ ]   |
|   4   |   §4    | Adapter compatibility schedule | §3, D04 T01 §5 |  [ ]   |

---

## 1. Scripted Agent Library

Why this section exists: one loopback is not coverage. The library scripts every method, notification, and fault the protocol defines.

- [ ] `tests/Fixtures/AcpScripts/` covers every client and agent method with happy-path scripts. Done when: each method has a passing script.
- [ ] Fault scripts cover malformed messages, dropped responses, slow streams, and mid-turn crashes. Done when: each fault has a passing script.
- [ ] Scripts are data (driven by the loopback), not code, so adding one needs no harness change. Done when: a new script is added without touching the fixture.
- [ ] Commit: `"quality: build the scripted agent library"`

**Test checkpoint:** Full script library green in CI; a new script added without fixture changes. Cheaper substitute that fails: three golden-path scripts called coverage.

## 2. Schema Pin and Drift Detection

Why this section exists: the protocol moves. The pin names what we conform to; drift detection notices when it moves.

- [ ] The ACP schema revision is pinned with its source and date in `tests/Fixtures/acp-schema/`. Done when: the pin is recorded.
- [ ] Every message in every script validates against the pin in both directions. Done when: validation failures fail the suite.
- [ ] A scheduled check fetches the latest schema and reports drift without auto-updating. Done when: the check runs and its report is recorded.
- [ ] Commit: `"quality: pin the ACP schema and detect drift"`

**Test checkpoint:** Pin recorded; bidirectional validation enforced; drift check scheduled. Cheaper substitute that fails: validating against a schema copied once and forgotten.

## 3. Version Matrix (v1 and v2)

Why this section exists: v1 and v2 are both live surfaces. The matrix proves each peer version against each client flag state.

- [ ] Scripted v1-only, v2-capable, and version-mismatched peers cover the negotiation matrix. Done when: each cell passes.
- [ ] v2 flag states (off, on) are crossed with peer versions in CI. Done when: the matrix runs green.
- [ ] Unknown future versions degrade to the highest mutual version or disconnect cleanly. Done when: the degradation is tested.
- [ ] Commit: `"quality: test the v1/v2 matrix"`

**Test checkpoint:** Negotiation matrix green in CI; future-version degradation tested. Cheaper substitute that fails: testing only the version the dev machine has.

## 4. Adapter Compatibility Schedule

Why this section exists: claimed adapters are proven on a schedule against their real binaries, with results in the compatibility record.

- [ ] The schedule runs handshake and session suites against real `codex-acp` and `claude-agent-acp` binaries. Done when: the schedule runs and reports.
- [ ] Results land in the `D04 T01 §5` compatibility record automatically. Done when: a run updates the record.
- [ ] Failures file work with the adapter version attached; the claim is narrowed until green. Done when: the procedure is demonstrated once.
- [ ] Real-agent runs need no API keys for handshake and session-shape suites; suites needing keys are marked and skipped honestly. Done when: the marking is tested.
- [ ] Commit: `"quality: schedule adapter compatibility runs"`

**Test checkpoint:** Scheduled runs green with the record updated; key-gated suites marked honestly. Cheaper substitute that fails: "tested once on the author's machine".

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Script library, schema pin, and matrix all green in CI
- [ ] `python3 scripts/todo-graph.py validate` clean
