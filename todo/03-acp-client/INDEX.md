# 03 ACP Client

> **Phase 2**

The Agent Client Protocol implementation: JSON-RPC over stdio, session lifecycle, client-side methods, and v2 readiness. This domain speaks the protocol; `04-agents` launches the agents and `05-ai-surface` shows the conversation.

Protocol reference: [agentclientprotocol.com](https://agentclientprotocol.com/get-started/agents). Transports: stdio is required; the client launches the agent as a subprocess and exchanges newline-delimited JSON-RPC.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-acp-transport-lifecycle.md) | Transport and Lifecycle | `draft` |
| [TODO-02](./TODO-02-acp-client-methods.md) | Client Methods | `draft` |
| [TODO-03](./TODO-03-acp-v2-readiness.md) | v2 Readiness | `draft` |

## In scope

- JSON-RPC 2.0 framing over stdio, request/response/notification handling
- initialize, authenticate, session/new, session/prompt, session/update, session/cancel
- Client methods: session/request_permission, fs access, terminal execution
- Version negotiation and v2 behind feature flags

## Out of scope

- Which agents are installed and how they are spawned (04-agents)
- Conversation UI (05-ai-surface)
- Conformance test content (06-quality owns the harness suites; this domain owns the implementation)

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
