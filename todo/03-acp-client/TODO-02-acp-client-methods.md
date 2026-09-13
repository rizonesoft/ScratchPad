---
schema_version: 1
id: acp-client-methods
domain: 03-acp-client
status: draft
title: "TODO-02 -- ACP Client Methods"
depends_on: ["acp-transport-lifecycle"]
track: A1
---

# TODO-02 -- ACP Client Methods

> **Goal:** The client answers the agent's calls: permission requests, file-system access, and terminal execution, each gated by policy the user can see.

> [!IMPORTANT]
> **Current state:** `D03 T01` carries agent-to-client traffic one way so far. No client method is implemented; this file adds the answering side.

## Inputs

- [ACP tool calls](https://agentclientprotocol.com/protocol/v1/tool-calls) -- permission request flow
- [ACP file system](https://agentclientprotocol.com/protocol/v1/file-system) -- client fs methods
- [ACP terminals](https://agentclientprotocol.com/protocol/v1/terminals) -- terminal execution
- [`03-acp-client/TODO-01-acp-transport-lifecycle.md`](./TODO-01-acp-transport-lifecycle.md) -- the transport these methods ride on

## Outcome

- Permission requests reach the user and the answer reaches the agent, with deny as the safe default.
- File-system methods serve exactly the scoped roots, and nothing else.
- Terminal execution runs with the user's consent and full output capture.
- Every grant is logged with actor, scope, and time.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (permission prompts are D05 T02 §1, not notifications); permissions=applicable @ D05 T02 §1; audit=applicable @ D03 T02 §5; exchange=not-applicable (no import/export in this file); reverse=applicable @ D03 T02 §4

**Adjacency rationale:** Permission UI lives in D05 with the user; the grant log here is the audit; revoking a grant mid-session is the reversal.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Permission request handling | D03 T01 §5 |  [ ]   |
|   2   |   §2    | File-system methods with scoped roots | §1 |  [ ]   |
|   3   |   §3    | Terminal execution | §1 |  [ ]   |
|   4   |   §4    | Grant scope and revocation | §2, §3 |  [ ]   |
|   5   |   §5    | Grant audit log | §4 |  [ ]   |

---

## 1. Permission Request Handling

Why this section exists: `session/request_permission` is the safety boundary of the whole product. Deny-by-default, prompt faithfully, answer exactly once.

- [ ] `src/Notepad.Acp/Permissions.cs` answers `session/request_permission` with allow, deny, or escalate-to-user per policy. Done when: the policy matrix is tested.
- [ ] Deny is the default for unknown kinds, timed-out prompts, and any ambiguity. Done when: each default-deny case is tested.
- [ ] Each request is answered exactly once; double-answer and no-answer are impossible by construction. Done when: the exactly-once tests pass.
- [ ] The UI contract for prompts is defined for `D05 T02 §1` to render (kind, scope, risk summary). Done when: the contract test passes against a stub renderer.
- [ ] Commit: `"acp-client: answer permission requests deny-by-default"`

**Test checkpoint:** Policy matrix, default-deny cases, and exactly-once tests green. Cheaper substitute that fails: allow-by-default with a log line.

## 2. File-System Methods with Scoped Roots

Why this section exists: the agent reads and writes through the client. Scoped roots are what keep a prompt-injection from reading the disk.

- [ ] `fs/read_text_file` (and sibling read methods) serve only paths under the session's roots. Done when: escape attempts (`..`, symlinks, UNC) are refused in tests.
- [ ] Write methods (where the schema offers them) require a permission grant naming the path. Done when: ungranted writes are refused in tests.
- [ ] Reads outside the open document's directory require their own grant, recorded in the audit log. Done when: the boundary is tested.
- [ ] Binary and oversized files are refused with a structured error, never truncated silently. Done when: the refusal tests pass.
- [ ] Commit: `"acp-client: scope file-system methods to session roots"`

**Test checkpoint:** Escape, ungranted-write, boundary, and binary refusal tests green. Cheaper substitute that fails: serving the whole disk because the roots were "too fiddly".

## 3. Terminal Execution

Why this section exists: agents run commands. Each run is consented, captured, bounded, and killable.

- [ ] Terminal methods execute with the session's working directory and a committed timeout and output cap. Done when: the bounds are tested.
- [ ] Every execution requires a permission grant naming the command. Done when: ungranted execution is refused in tests.
- [ ] Output streams to the transcript contract as it arrives; exit codes and signals are recorded. Done when: the streaming test passes.
- [ ] Runaway processes are killed at the timeout with the kill recorded. Done when: the kill test passes.
- [ ] Commit: `"acp-client: execute terminals with consent and bounds"`

**Test checkpoint:** Bounds, consent, streaming, and kill tests green. Cheaper substitute that fails: unbounded execution with output only at the end.

## 4. Grant Scope and Revocation

Why this section exists: grants are the user's standing choices. Scoped narrowly, revocable instantly, expired automatically.

- [ ] Grants carry kind, scope (path, command pattern), session, and expiry. Done when: the grant fixtures pass.
- [ ] The user can revoke any grant mid-session with immediate effect. Done when: the revocation test passes.
- [ ] Grants never cross sessions; expiry is enforced, not advisory. Done when: the boundary tests pass.
- [ ] Commit: `"acp-client: scope and revoke grants"`

**Test checkpoint:** Grant, revoke, cross-session, and expiry tests green. Cheaper substitute that fails: allow-once that quietly becomes allow-always.

## 5. Grant Audit Log

Why this section exists: every grant and denial is a security event. The log makes "what did the agent touch" answerable.

- [ ] `src/Notepad.Acp/GrantLog.cs` records actor, time, kind, scope, decision, and reason for every permission event. Done when: the schema test passes.
- [ ] The log is append-only within a session and exportable by the user. Done when: tamper and export tests pass.
- [ ] The UI surfaces the log where `D05 T02` designs it; this section owns the data and its integrity. Done when: the data contract test passes.
- [ ] Commit: `"acp-client: log every grant and denial"`

**Test checkpoint:** Schema, append-only, and export tests green. Cheaper substitute that fails: logging to a debug console nobody can open.

## Verification

- [ ] `dotnet test` green
- [ ] Escape, consent, and exactly-once proofs all green
- [ ] `python3 scripts/todo-graph.py validate` clean
