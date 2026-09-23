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
- [`00-workspace/TODO-02-test-backbone.md`](../00-workspace/TODO-02-test-backbone.md) -- the §4 loopback fixture, the scripted agent that drives these methods in tests

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
|   2   |   §2    | File-system methods with scoped roots | §1, D02 T01 §2, D02 T01 §4 |  [ ]   |
|   3   |   §3    | Terminal execution | §1 |  [ ]   |
|   4   |   §4    | Grant scope and revocation | §2, §3 |  [ ]   |
|   5   |   §5    | Grant audit log | §4 |  [ ]   |

|  6   |  §6    | Elicitation requests | §1 |  [ ]   |
---

## 1. Permission Request Handling

Why this section exists: `session/request_permission` is the safety boundary of the whole product. Deny-by-default, prompt faithfully, answer exactly once.

**Groomed 2026-09-23:** Spec shape corrected: `session/request_permission` is answered with `outcome: selected` carrying an agent-supplied `optionId` (kinds `allow_once`, `allow_always`, `reject_once`, `reject_always`) or `outcome: cancelled`; deny maps to a reject option, and every pending request answers `cancelled` on `session/cancel`.

- [ ] `src/Notepad.Acp/Permissions.cs` answers `session/request_permission` with allow, deny, or escalate-to-user per policy. Done when: the policy matrix is tested.
- [ ] Deny is the default for unknown kinds, timed-out prompts, and any ambiguity. Done when: each default-deny case is tested.
- [ ] Each request is answered exactly once; double-answer and no-answer are impossible by construction. Done when: the exactly-once tests pass.
- [ ] The UI contract for prompts is defined for `D05 T02 §1` to render (kind, scope, risk summary). Done when: the contract test passes against a stub renderer.
- [ ] Commit: `"acp-client: answer permission requests deny-by-default"`

**Test checkpoint:** Policy matrix, default-deny cases, and exactly-once tests green. Cheaper substitute that fails: allow-by-default with a log line.

## 2. File-System Methods with Scoped Roots

Why this section exists: the agent reads and writes through the client. Scoped roots are what keep a prompt-injection from reading the disk.

**Groomed 2026-09-23:** Spec shape corrected: the schema has exactly `fs/read_text_file` (sessionId, absolute path, optional 1-based `line` and `limit`) and `fs/write_text_file`, advertised through `clientCapabilities.fs`; there are no sibling read methods, and write is offered.

- [ ] `fs/read_text_file` (and sibling read methods) serve only paths under the session's roots. Done when: escape attempts (`..`, symlinks, UNC) are refused in tests.
- [ ] Write methods (where the schema offers them) require a permission grant naming the path. Done when: ungranted writes are refused in tests.
- [ ] Reads outside the open document's directory require their own grant, recorded in the audit log. Done when: the boundary is tested.
- [ ] Binary and oversized files are refused with a structured error, never truncated silently. Done when: the refusal tests pass.
- [ ] Reads of a path open in a tab serve the live buffer (unsaved changes included, per the spec), and writes to an open tab land as one undoable edit routed through D05 T02 review; writes to closed files keep a backup. Done when: an open-tab read returns unsaved text and an open-tab write undoes in one step (Groomed 2026-09-23.)
- [ ] Commit: `"acp-client: scope file-system methods to session roots"`

**Test checkpoint:** Escape, ungranted-write, boundary, and binary refusal tests green. Cheaper substitute that fails: serving the whole disk because the roots were "too fiddly".

## 3. Terminal Execution

Why this section exists: agents run commands. Each run is consented, captured, bounded, and killable.

**Groomed 2026-09-23:** Spec shape corrected: `terminal/create` carries the agent's own absolute `cwd`, args, env, and `outputByteLimit` (output past the limit truncates from the start on a character boundary); the agent owns timeouts through `wait_for_exit` and `kill`; methods are create, output, wait_for_exit, kill, release. A client ceiling timeout is extra policy; the cwd must sit inside the scoped roots.

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

## 6. Elicitation Requests

Why this section exists: `elicitation/create` is an agent-to-client request that needs exactly one answer (`accept`, `decline`, or `cancel`), with an `elicitation/complete` notification and a `clientCapabilities.elicitation` advertisement (form and url modes), and no D03 section answers it (groom 2026-09-23). -> XREF: D05 T02 §5 (the form UI this wire feeds). -> XREF: D03 T01 §5 (routing sends elicitation here).

- [ ] `elicitation/create` reaches D05 T02 §5 and is answered exactly once with accept, decline, or cancel; a turn cancel answers `cancel`. Done when: the loopback proves exactly-once under a racing cancel
- [ ] URL-mode elicitation opens out of band only after consent, and `elicitation/complete` closes the pending form. Done when: the loopback drives both modes
- [ ] Commit: `"acp-client: answer elicitation requests"`

**Test checkpoint:** exactly-once answers under cancel and both modes driven on the loopback. Cheaper substitute that fails: treating elicitation as a session update.

## Verification

- [ ] `dotnet test` green
- [ ] Escape, consent, and exactly-once proofs all green
- [ ] `python3 scripts/todo-graph.py validate` clean
