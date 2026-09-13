---
schema_version: 1
id: acp-v2-readiness
domain: 03-acp-client
status: draft
title: "TODO-03 -- ACP v2 Readiness"
depends_on: ["acp-transport-lifecycle"]
track: A1
---

# TODO-03 -- ACP v2 Readiness

> **Goal:** The client negotiates v1 or v2 per connection, keeps v1 working untouched, and adds v2 behind feature flags until it stabilizes.

> [!IMPORTANT]
> **Current state:** `D03 T01` negotiates a version and serves v1. No v2 surface exists. The v2 protocol is still labeled draft, so this file treats v2 as additive and flagged, never as a rewrite.

## Inputs

- [ACP v2 migration guide](https://agentclientprotocol.com/protocol/v2/migration) -- breaking changes, side-by-side rules, flag discipline
- [`03-acp-client/TODO-01-acp-transport-lifecycle.md`](./TODO-01-acp-transport-lifecycle.md) -- the v1 surface that must keep working untouched

## Outcome

- v1 peers keep working exactly as before, proven by the unchanged v1 suite.
- v2 peers negotiate v2 with upsert updates and the restructured lifecycle.
- Every v2 behavior sits behind an explicit flag, off by default until stable.
- Dropping v1 is never on the table: the migration guide forbids it.

**Adjacency:** all=not-applicable (protocol versioning with no user-facing feature surface of its own)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Per-connection version selection | D03 T01 §3 |  [ ]   |
|   2   |   §2    | v2 lifecycle behind flags | §1 |  [ ]   |
|   3   |   §3    | v1 regression lock | §2 |  [ ]   |

---

## 1. Per-Connection Version Selection

Why this section exists: one connection speaks exactly one negotiated version. Selection is per connection, never global.

- [ ] `initialize` sends the latest supported version; a v1 answer selects the v1 surface for that connection. Done when: the selection matrix is tested.
- [ ] v1 and v2 connections coexist in one process (two agents, two versions). Done when: the coexistence test passes.
- [ ] The negotiated version is visible in diagnostics for every connection. Done when: the test asserts it.
- [ ] Commit: `"acp-client: select protocol version per connection"`

**Test checkpoint:** Selection and coexistence matrix green. Cheaper substitute that fails: a global version switch.

## 2. v2 Lifecycle Behind Flags

Why this section exists: v2 restructures the prompt lifecycle (acceptance responses, upsert state updates). Each piece lands behind its own flag.

- [ ] `session/prompt` acceptance and `state_update` completion are implemented per the v2 schema. Done when: the v2 loopback drives a full turn.
- [ ] Upsert semantics (omitted means unchanged, null clears, chunks append) are implemented and tested per the guide. Done when: the upsert fixtures pass.
- [ ] Removed v1 surfaces (client fs, terminal execution, session modes) are absent on v2 connections, with MCP as the documented replacement path. Done when: the absence is tested, not assumed.
- [ ] Every v2 behavior is flag-gated, off by default. Done when: flags-off runs the v1 surface only.
- [ ] Commit: `"acp-client: add the v2 lifecycle behind flags"`

**Test checkpoint:** v2 loopback turns green; upsert fixtures green; flags-off proves v1-only. Cheaper substitute that fails: v2 merged into the v1 code path.

## 3. v1 Regression Lock

Why this section exists: v2 work must never break v1 peers. The lock proves it on every run.

- [ ] The full v1 suite runs unchanged with v2 code present and flags on. Done when: CI proves it.
- [ ] A v1-only agent fixture pins the v1 wire format byte for byte. Done when: any drift fails the test.
- [ ] The day v2 stabilizes, the flag-flip procedure is one documented step with a rollback. Done when: the procedure is written (not executed).
- [ ] Commit: `"acp-client: lock v1 against v2 regression"`

**Test checkpoint:** v1 suite green with v2 present; wire-format pin green; flip procedure written. Cheaper substitute that fails: "v1 still works, we think".

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] v1 suite unchanged and green with v2 present
- [ ] `python3 scripts/todo-graph.py validate` clean
