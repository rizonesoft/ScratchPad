# 05 AI Surface

> **Phase 3**

The new AI surfaces: chat panel, permission prompts, tool-call display, diff review, and apply-to-editor. New build throughout: Windows 11 Notepad has no counterpart, so Fidelity declares that explicitly and the design is judged on its own contract.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-chat-panel.md) | Chat Panel | `draft` |
| [TODO-02](./TODO-02-permission-apply-ux.md) | Permission and Apply UX | `draft` |
| [TODO-03](./TODO-03-agent-chrome.md) | Agent Chrome | `draft` |

## In scope

- Chat transcript, streaming, input, history, agent picker
- Permission prompts, tool-call and plan display
- Diff review and apply-to-editor through the D02 interface
- Editor-native agent chrome: status bar, per-tab pane, slash commands, management, usage

Prior art (non-authoritative): [microsoft/intelligent-terminal](https://github.com/microsoft/intelligent-terminal) proved ACP fits a native desktop app. The chrome here is designed for an editor and judged against `docs/ai-panel-contract.md`, never against the terminal.

## Out of scope

- Protocol transport and client methods (03-acp-client)
- Agent detection, sessions, auth (04-agents)
- The editor surface being edited (02-editor); this domain consumes its interface

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
