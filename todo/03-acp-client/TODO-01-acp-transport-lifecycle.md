---
schema_version: 1
id: acp-transport-lifecycle
domain: 03-acp-client
status: draft
title: "TODO-01 -- ACP Transport and Lifecycle"
depends_on: ["repo-and-toolchain"]
track: A1
---

# TODO-01 -- ACP Transport and Lifecycle

> **Goal:** The client launches an agent subprocess, speaks JSON-RPC 2.0 over stdio, and drives the full session lifecycle: initialize, session/new, prompt turns with streaming updates, and cancellation.

> [!IMPORTANT]
> **Current state:** No protocol code exists. The `D00 T02 §4` loopback fixture is the test peer for every section here; no section in this file may require a real agent or network access to prove itself.

## Inputs

- [ACP protocol overview](https://agentclientprotocol.com/protocol/v1/overview) -- methods, notifications, message flow
- [ACP transports](https://agentclientprotocol.com/protocol/v1/transports) -- stdio framing rules
- [`00-workspace/TODO-02-test-backbone.md`](../00-workspace/TODO-02-test-backbone.md) -- §4's loopback fixture, the test peer
- -> XREF: D05 T01 §1 -- the chat panel consumes this lifecycle; the transcript contract is settled there
- -> XREF: D04 T01 §2 -- agent launching consumes this transport; the spawn contract is settled there

## Outcome

- Every message on the wire validates against the ACP schema in both directions.
- Prompt turns stream updates to the UI contract and end with a stop reason.
- Cancellation, timeouts, agent crashes, and malformed output are all survived and tested.
- No section here depends on a real agent, the network, or API keys.

**Adjacency:** all=not-applicable (protocol transport and lifecycle with no user-facing feature surface; the conversation surface that consumes it declares its own adjacency in D05)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | JSON-RPC message layer | -- |  [ ]   |
|   2   |   §2    | Stdio subprocess transport | §1 |  [ ]   |
|   3   |   §3    | Initialize and capability negotiation | §2 |  [ ]   |
|   4   |   §4    | Session create and load | §3 |  [ ]   |
|   5   |   §5    | Prompt turns with streaming updates | §4 |  [ ]   |
|   6   |   §6    | Cancellation and timeouts | §5 |  [ ]   |
|   7   |   §7    | Fault survival: crashes and malformed output | §5 |  [ ]   |

---

## 1. JSON-RPC Message Layer

Why this section exists: every byte on the wire goes through this layer. Correct framing and schema validation here is correctness everywhere.

- [ ] `src/Acp/JsonRpc.h` and `JsonRpc.cpp` encode and decode JSON-RPC 2.0 requests, responses, and notifications. Done when: the codec fixtures pass, including batch-free single-message framing.
- [ ] Outgoing messages validate against the ACP schema before send; violations fail loudly in tests. Done when: a deliberately malformed message fails the test.
- [ ] Incoming messages validate on receipt with structured errors, never exceptions across the transport. Done when: each violation shape is tested.
- [ ] Request ids correlate responses under concurrency. Done when: interleaved responses route to the right callers in the test.
- [ ] Commit: `"acp-client: add the JSON-RPC message layer"`

**Test checkpoint:** `ctest -R JsonRpc` green, including malformed-in and malformed-out cases. Cheaper substitute that fails: a JSON library used raw with no schema validation.

## 2. Stdio Subprocess Transport

Why this section exists: stdio is the required ACP transport. The client launches the agent, owns its pipes, and must never write a non-message byte.

- [ ] `src/Acp/StdioTransport.cpp` spawns a child process with piped stdin/stdout/stderr on Windows. Done when: the loopback fixture spawns and shakes hands.
- [ ] Messages are newline-delimited with no embedded newlines; stdout carries only ACP messages. Done when: a byte-level capture test proves it.
- [ ] Stderr is captured as agent logs and never parsed as protocol. Done when: noisy-stderr fixtures pass.
- [ ] Shutdown closes stdin and terminates the child cleanly with a committed timeout, then force-kills. Done when: the shutdown matrix is tested.
- [ ] Commit: `"acp-client: add the stdio subprocess transport"`

**Test checkpoint:** Loopback spawn, byte-level framing proof, noisy stderr, and shutdown matrix all green. Cheaper substitute that fails: a transport tested only against an in-process mock.

## 3. Initialize and Capability Negotiation

Why this section exists: every connection begins with `initialize`. Versions and capabilities negotiated wrong here break every later call.

- [ ] `src/Acp/Session.cpp` sends `initialize` with the client's protocol version and capabilities. Done when: the loopback records the exact params.
- [ ] The client honors the agent's answered version (v1 peer stays v1) and records the negotiated surface. Done when: v1-only and v2-capable peers are both tested.
- [ ] Unknown capabilities and fields are ignored forward-compatibly, never rejected. Done when: the tolerance fixtures pass.
- [ ] A failed or timed-out `initialize` surfaces a structured error, not a hang. Done when: the failure is tested.
- [ ] Commit: `"acp-client: negotiate initialize and capabilities"`

**Test checkpoint:** Negotiation matrix green against scripted peers; unknown-field tolerance proven; failure structured. Cheaper substitute that fails: assuming v1 and crashing on anything else.

## 4. Session Create and Load

Why this section exists: sessions are the unit of conversation. Create and load must handle capability absence honestly.

- [ ] `session/new` creates a session and returns its handle with the working directory and options applied. Done when: the loopback proves the params.
- [ ] `session/load` resumes where the agent advertises `loadSession`, and reports unsupported cleanly where it does not. Done when: both peers are tested.
- [ ] Session handles are tracked with exactly one owner; double-close and use-after-close are impossible by construction. Done when: the lifetime tests pass.
- [ ] Commit: `"acp-client: create and load sessions"`

**Test checkpoint:** Create and load matrix green, including unsupported-load honesty and lifetime tests. Cheaper substitute that fails: assuming load support everywhere.

## 5. Prompt Turns with Streaming Updates

Why this section exists: the prompt turn is the core loop. Updates stream to the UI contract as they arrive, and the turn ends with a stop reason.

- [ ] `session/prompt` sends the user message with content blocks per the schema. Done when: the loopback records exact params.
- [ ] `session/update` notifications dispatch to the transcript contract (`D05 T01 §1`) in arrival order. Done when: an out-of-order script still renders in order.
- [ ] The turn ends with the agent's stop reason recorded; every reason maps to UI-visible state. Done when: each reason is tested.
- [ ] Tool calls, elicitations, and plan updates during the turn route to their owners (`D03 T02`, `D05 T02`). Done when: each routes in the test.
- [ ] Commit: `"acp-client: drive prompt turns with streaming updates"`

**Test checkpoint:** Scripted multi-update turns render in order with stop reasons; tool-call routing proven. Cheaper substitute that fails: waiting for the full turn before showing anything.

## 6. Cancellation and Timeouts

Why this section exists: users cancel, agents stall. Both must end the turn cleanly with the session left usable.

- [ ] `session/cancel` interrupts a running turn; the client treats the race (cancel vs completion) deterministically. Done when: the race matrix is tested.
- [ ] Response timeouts are committed per method with the values recorded; a timeout never orphans a session. Done when: each timeout is tested.
- [ ] After cancel or timeout the session accepts the next prompt. Done when: the reuse test passes.
- [ ] Commit: `"acp-client: cancel turns and time out cleanly"`

**Test checkpoint:** Cancel race matrix and timeout matrix green; session reuse proven. Cheaper substitute that fails: cancel that kills the agent process.

## 7. Fault Survival: Crashes and Malformed Output

Why this section exists: agents are separate processes that can die or misbehave. The client survives all of it with the user's work intact.

- [ ] Agent crash mid-turn surfaces a structured error with the captured stderr tail attached. Done when: the crash fixtures pass.
- [ ] Malformed JSON, non-message stdout lines, and protocol violations end the turn with diagnostics, never a hang or crash. Done when: each fault is tested.
- [ ] Restart-after-crash offers a clean session without losing the transcript shown so far. Done when: the recovery is tested.
- [ ] Commit: `"acp-client: survive crashes and malformed output"`

**Test checkpoint:** Crash, malformed, and violation fixtures all green with diagnostics; recovery tested. Cheaper substitute that fails: a client that exits when the agent does.

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Full prompt turn proven against the loopback with byte-level framing proof
- [ ] No test in this file needs network, keys, or a real agent
- [ ] `python3 scripts/todo-graph.py validate` clean
