---
schema_version: 1
id: agent-discovery-launch
domain: 04-agents
status: draft
title: "TODO-01 -- Agent Discovery and Launch"
depends_on: ["acp-transport-lifecycle"]
track: A2
---

# TODO-01 -- Agent Discovery and Launch

> **Goal:** The app finds installed ACP agents (Codex via codex-acp, Claude via claude-agent-acp), reports their health honestly, and launches them over the D03 transport.

> [!IMPORTANT]
> **Current state:** No agents are detected or launched. The `D03 T01` transport is the spawn target; this file decides what to spawn and proves it healthy first.

## Inputs

- [ACP agents list](https://agentclientprotocol.com/get-started/agents) -- Codex via `codex-acp`, Claude via `claude-agent-acp`
- -> XREF: D03 T01 §2 -- the stdio transport this file spawns through; the spawn contract is settled there

## Outcome

- Installed agents are detected with versions and adapter paths, or reported missing with install guidance.
- Launch failures name the cause (missing binary, bad version, spawn error), never a generic failure.
- An agent that fails health checks cannot be selected until it passes.

**Adjacency:** list=applicable @ D04 T01 §1; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (agent launch consent is D05 T02 §1); audit=not-applicable (launches are logged with sessions in D04 T02 §5); exchange=not-applicable (no import/export in this file); reverse=not-applicable (stopping an agent is session close in D04 T02 §4)

**Adjacency rationale:** The agent picker is the list; agent choice persists through the D01 store; stopping and logging live with sessions.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Agent detection with versions | D03 T01 §3 |  [ ]   |
|   2   |   §2    | Spawn over the stdio transport | §1 |  [ ]   |
|   3   |   §3    | Launch health checks | §2 |  [ ]   |
|   4   |   §4    | Missing-agent guidance | §1 |  [ ]   |
|   5   |   §5    | Adapter compatibility record | §3 |  [ ]   |

---

## 1. Agent Detection with Versions

Why this section exists: "no agents found" must mean none are installed, not that detection looked in the wrong place.

- [ ] `src/Notepad.Agents/AgentDetector.cs` finds `codex-acp` and `claude-agent-acp` on PATH and in their documented install locations. Done when: the detection matrix passes on fixtures.
- [ ] Each found agent reports its version and protocol versions. Done when: the version probe is tested.
- [ ] Detection rescans on demand and on a committed trigger (startup, settings change). Done when: install-then-rescan is tested.
- [ ] The detector lists unknown but ACP-shaped binaries as unverified, never silently ignoring or trusting them. Done when: the unverified path is tested.
- [ ] Commit: `"agents: detect installed agents with versions"`

**Test checkpoint:** Detection matrix green on fixtures; rescan proven; unverified binaries listed honestly. Cheaper substitute that fails: hardcoding two PATH lookups.

## 2. Spawn over the Stdio Transport

Why this section exists: spawning is the D03 transport's job; this section is the policy around it (which binary, which args, which environment).

- [ ] Spawning uses the `D03 T01 §2` transport with the agent's documented args and a clean environment. Done when: the loopback spawns through this path in tests.
- [ ] Spawn failures (missing binary, permission, bad args) surface structured causes. Done when: each cause is tested.
- [ ] Only one instance spawns per launch request; double-launch races are impossible by construction. Done when: the race test passes.
- [ ] Commit: `"agents: spawn through the stdio transport"`

**Test checkpoint:** Spawn matrix green through the real transport; races tested. Cheaper substitute that fails: a second spawn path that bypasses the transport.

## 3. Launch Health Checks

Why this section exists: a spawned agent that cannot handshake is not launched. Health checks run before the agent is offered to the user.

- [ ] Health checks run `initialize` with a committed timeout and verify the version and capabilities. Done when: the check matrix passes.
- [ ] Unhealthy agents are marked with cause and time, and excluded from selection until they pass. Done when: the exclusion is tested.
- [ ] Health rechecks on a committed schedule and on demand. Done when: recover-then-recheck is tested.
- [ ] Commit: `"agents: gate launch on health checks"`

**Test checkpoint:** Healthy, unhealthy, and recovered agents all behave in tests. Cheaper substitute that fails: offering the agent the moment the process exists.

## 4. Missing-Agent Guidance

Why this section exists: most users will have no agent installed. Guidance turns that into a five-minute setup, not a dead end.

- [ ] Each supported agent has install guidance (where to get it, how to verify) shown when missing. Done when: the guidance is tested for accuracy on a clean VM.
- [ ] Guidance never installs or downloads anything itself; it links and instructs. Done when: the boundary is recorded and tested.
- [ ] After install, rescan picks the agent up with no restart. Done when: the flow is tested.
- [ ] Commit: `"agents: guide missing-agent setup"`

**Test checkpoint:** Guidance accuracy proven on a clean VM; install-to-detected flow tested. Cheaper substitute that fails: "agent not found" with no next step.

## 5. Adapter Compatibility Record

Why this section exists: adapters move independently of us. The record pins what we tested against so drift is visible.

- [ ] `docs/adapter-compatibility.md` records each supported adapter with tested versions and known gaps. Done when: the record exists and CI checks it is current.
- [ ] A new adapter version triggers re-verification of the health and handshake suites. Done when: the trigger is tested with a fixture version bump.
- [ ] Known gaps are each routed to a named section or accepted with a recorded reason. Done when: no gap is silent.
- [ ] Commit: `"agents: record adapter compatibility"`

**Test checkpoint:** Compatibility record current in CI; version-bump trigger tested; gaps routed or accepted. Cheaper substitute that fails: "works with latest" as a strategy.

## Verification

- [ ] `dotnet test` green
- [ ] Detection, spawn, and health proven on fixtures and a clean VM
- [ ] `python3 scripts/todo-graph.py validate` clean
