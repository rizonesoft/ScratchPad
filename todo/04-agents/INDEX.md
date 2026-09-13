# 04 Agents

> **Phase 2**

Agent discovery and launch, sessions, and auth. The supported agents are Codex (via the `codex-acp` adapter) and Claude Code (via the `claude-agent-acp` adapter); the design admits any ACP-speaking agent.

Agent reference: [agentclientprotocol.com/get-started/agents](https://agentclientprotocol.com/get-started/agents).

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-agent-discovery-launch.md) | Agent Discovery and Launch | `draft` |
| [TODO-02](./TODO-02-agent-sessions-auth.md) | Agent Sessions and Auth | `draft` |

## In scope

- Detecting installed agents and their adapters
- Spawning adapters over the D03 transport
- Session create/load/list/delete, authenticate/logout

## Out of scope

- The protocol transport itself (03-acp-client)
- Conversation UI (05-ai-surface)
- Credentials storage details beyond using the platform store

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
