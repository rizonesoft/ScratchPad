---
schema_version: 1
id: agent-sessions-auth
domain: 04-agents
status: draft
title: "TODO-02 -- Agent Sessions and Auth"
depends_on: ["agent-discovery-launch"]
track: A2
---

# TODO-02 -- Agent Sessions and Auth

> **Goal:** Sessions with agents are created, listed, resumed, and closed cleanly, and authentication uses the platform credential store with explicit logout.

> [!IMPORTANT]
> **Current state:** `D04 T01` launches agents; nothing here manages their sessions. `D03 T01 §4` owns the wire calls; this file owns the policy around them.

## Inputs

- [ACP session setup](https://agentclientprotocol.com/protocol/v1/session-setup) -- create and load
- [ACP authentication](https://agentclientprotocol.com/protocol/v1/authentication) -- authenticate and logout
- -> XREF: D05 T02 §1 -- permission prompts gate session actions that need consent; the consent contract is settled there
- -> XREF: D08 T02 §3 -- the voice provider settings follow the platform-store pattern for the OpenRouter key

## Outcome

- Session list, create, resume, and close all work with exactly-once semantics.
- Auth state is explicit (in or out) with no half-logged limbo.
- Credentials live in the platform store, never in our files or logs.

**Adjacency:** list=applicable @ D04 T02 §2; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (no notification surface in this file); permissions=applicable @ D05 T02 §1; audit=applicable @ D04 T02 §5; exchange=applicable @ D04 T02 §6; reverse=applicable @ D04 T02 §4

**Adjacency rationale:** The session list is the list; session close is the reversal; the session log is the audit; consent UI lives in D05. The sidecar read is the import.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Authenticate and logout | D04 T01 §3 |  [ ]   |
|   2   |   §2    | Session list and create | §1 |  [ ]   |
|   3   |   §3    | Session resume and delete | §2 |  [ ]   |
|   4   |   §4    | Session close and cleanup | §2 |  [ ]   |
|   5   |   §5    | Session log | §4 |  [ ]   |
|   6   |   §6    | Per-file sidecar instructions | §2, D01 T01 §4 |  [ ]   |

---

## 1. Authenticate and Logout

Why this section exists: auth state must be explicit and credentials must never touch our files. The platform store owns secrets; we own state.

- [ ] `authenticate` runs where the agent requires it, with the flow's prompts routed through the permission contract. Done when: the auth matrix passes.
- [ ] `logout` ends the authenticated state where the agent offers it, and reports unsupported cleanly where it does not. Done when: both are tested.
- [ ] Credentials live in the platform credential store; none appear in settings files, logs, or crash dumps. Done when: a secret-scan test proves it.
- [ ] Auth state (in, out, unknown) is queryable and shown honestly in the UI contract. Done when: the state test passes.
- [ ] Commit: `"agents: authenticate and log out cleanly"`

**Test checkpoint:** Auth matrix green; secret scan clean; state explicit. Cheaper substitute that fails: credentials in a config file.

## 2. Session List and Create

Why this section exists: the session list is the user's map of conversations. Create is exactly-once; the list never shows ghosts.

- [ ] Session create issues one `session/new` per user action with idempotency on retry. Done when: the retry test proves one session, not two.
- [ ] The list reflects the agent's sessions with no ghosts after crash or restart. Done when: the reconciliation test passes.
- [ ] Concurrent sessions to one agent are isolated: prompts never cross. Done when: the isolation test passes.
- [ ] Commit: `"agents: list and create sessions"`

**Test checkpoint:** Exactly-once create, ghost-free list, and isolation tests green. Cheaper substitute that fails: a list that trusts its cache over the agent.

## 3. Session Resume and Delete

Why this section exists: resume must restore context faithfully, and delete must actually delete, including server-side where the protocol offers it.

- [ ] Resume loads the session with its history intact, or reports honestly when the agent cannot. Done when: both are tested.
- [ ] Delete removes the session locally and calls the protocol delete where offered, with confirmation first. Done when: the delete matrix passes.
- [ ] A deleted session never reappears on rescan or restart. Done when: the permanence test passes.
- [ ] Commit: `"agents: resume and delete sessions"`

**Test checkpoint:** Resume, delete, and permanence tests green. Cheaper substitute that fails: delete that hides the row.

## 4. Session Close and Cleanup

Why this section exists: closing ends the conversation's resources: process, grants, temp state. Nothing lingers to surprise the next session.

- [ ] Close terminates the agent process (or detaches, per the agent's model) and releases the transport. Done when: no process or handle leaks in tests.
- [ ] The session can revoke its grants at close. Done when: the expiry test passes.
- [ ] Temp state (partial transcripts, caches) is cleaned with the user's data preserved per the session log. Done when: the cleanup test passes.
- [ ] Commit: `"agents: close sessions and clean up"`

**Test checkpoint:** Leak, expiry, and cleanup tests green. Cheaper substitute that fails: close that orphans the process.

## 5. Session Log

Why this section exists: "what happened in that session" must be answerable after the fact, from our side, without the agent's help.

- [ ] `src/Notepad.Agents/SessionLog.cs` records session lifecycle events in the audit log with time, agent, and outcome. Done when: the schema test passes.
- [ ] The log excludes secrets and prompt contents by default, with the exclusion tested. Done when: the redaction test passes.
- [ ] The user can export and clear the log. Done when: both are tested.
- [ ] Commit: `"agents: log session lifecycle"`

**Test checkpoint:** Schema, redaction, export, and clear tests green. Cheaper substitute that fails: a log that records prompts verbatim.

## 6. Per-File Sidecar Instructions

Why this section exists: notes carry their own agent instructions in a sidecar file next to the note. Project conventions travel with the document, not the app.

**Fidelity:** new build, no baseline (no stock counterpart; judged on its own contract).

**Job:** The user can pin instructions to a file. Consumer: the session (§2), which loads the sidecar at create.

**Treatment:** A sidecar file beside the note (name and format recorded here) loads into the session context at §2 create time; missing or malformed sidecars degrade to no instructions with a notice. Cheaper substitute that fails the checkpoint: global instructions with a filename filter.

**Chrome:** No new surface; the file list is the surface.

**Needs:** Windows host (build/test)

- [ ] The sidecar name and format are recorded and parsed. Done when: fixtures cover frontmatter and plain text.
- [ ] Session create imports the note's sidecar through §2. Done when: the load is driven.
- [ ] Missing or malformed sidecars degrade to no instructions with a notice. Done when: both paths are driven.
- [ ] Commit: `"agents: read per-file sidecar instructions"`

**Test checkpoint:** format, load, and degrade are all driven in the room. Cheaper substitute that fails: instructions that load for the wrong file.

## Verification

- [ ] `dotnet test` green
- [ ] Secret scan clean, session semantics proven
- [ ] `python3 scripts/todo-graph.py validate` clean
