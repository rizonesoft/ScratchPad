---
schema_version: 1
id: agent-chrome
domain: 05-ai-surface
status: draft
title: "TODO-03 -- Agent Chrome"
depends_on: ["chat-panel"]
track: A3
---

# TODO-03 -- Agent Chrome

> **Goal:** The agent UX around the chat panel, designed for an editor: a status bar, a per-tab pane with document context, slash commands, a session management panel, and token usage display.

> [!IMPORTANT]
> **Current state:** The `D05 T01` chat panel and `D05 T02` consent/apply UX exist (or land first). No status bar, no per-tab binding, no slash commands, no management panel. This file is editor-native agent chrome: the same problems (reach, context, sessions, cost) solved for documents, judged against the design contract, never against the terminal.

## Inputs

- [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) -- prior art (non-authoritative): proof that ACP fits a native desktop app. Selection actions and apply-to-editor are owned in `D05 T02`.
- [`05-ai-surface/TODO-01-chat-panel.md`](./TODO-01-chat-panel.md) -- the panel this chrome surrounds
- [`04-agents/TODO-02-agent-sessions-auth.md`](../04-agents/TODO-02-agent-sessions-auth.md) -- the sessions the management panel lists
- -> XREF: D01 T02 §8 -- the palette lists this file's slash surface without reimplementing it

## Outcome

- The user reaches every agent control from a persistent status bar.
- Each tab has its own agent pane with the open document as context.
- Slash commands drive the common actions without leaving the keyboard.
- Sessions are listed, resumed, and checked from one management panel.
- Token usage is visible for the working session.

**Adjacency:** list=applicable @ D05 T03 §4; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (agent states are in-chrome, not notifications); permissions=applicable @ D05 T02 §1; audit=applicable @ D03 T02 §5; exchange=not-applicable (no import/export in this file); reverse=applicable @ D05 T01 §4

**Adjacency rationale:** The management panel is the list; cancelling a turn is the reversal; consent and grants audit where they already do; chrome visibility persists through the D01 store.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Agent status bar | D05 T01 §1 |  [ ]   |
|   2   |   §2    | Per-tab pane with document context | §1, D01 T01 §2 |  [ ]   |
|   3   |   §3    | Slash commands | D05 T01 §3 |  [ ]   |
|   4   |   §4    | Agent management panel | §1, D04 T02 §2 |  [ ]   |
|   5   |   §5    | Token usage display | D05 T01 §2 |  [ ]   |

---

## 1. Agent Status Bar

Why this section exists: the status bar is the persistent one-click surface for everything agent-related. Without it the agent features are reachable only to users who memorized them.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md` only.

**Job:** The user can reach the panel, sessions, and usage from one bar. Consumer: the panel, the management panel, and the usage readout.

**Treatment:** Persistent bar per the contract. Cheaper substitute that fails the checkpoint: agent controls buried in menus only.

**Chrome:** Consume the shared bar styles. Do not invent a second status treatment.

**Groomed 2026-09-13:** Notepad audit: the status bar (not a Copilot button) as the persistent agent entry is now explicit.

- [ ] `src/Notepad/AgentStatusBar.xaml` carries the panel toggle, turn-state indicator, and management entry with committed shortcuts. Done when: each control is driven by mouse and shortcut.
- [ ] The bar is the persistent agent entry instead of a Notepad-style Copilot button; AI toggle-off hides it with the panel. Done when: the contract records the placement and toggle-off is driven. Source: https://support.microsoft.com/en-gb/windows/enhance-your-writing-with-ai-in-notepad-4088b954-c97b-46dc-813f-959be01746d5
- [ ] The bar reflects live state (idle, streaming, awaiting-permission, failed) without polling the session. Done when: the state test passes.
- [ ] The bar hides with the panel per the persisted visibility choice. Done when: the toggle is driven.
- [ ] Commit: `"ai-surface: add the agent status bar"`

**Test checkpoint:** Controls, live states, and visibility driven; shortcuts proven. Cheaper substitute that fails: a status bar that renders but never updates.

## 2. Per-Tab Pane with Document Context

Why this section exists: each tab is its own document, so each tab gets its own agent context. The agent sees the open document without copy-paste.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can ask about the open document and be understood. Consumer: the session, which receives document context with the prompt.

**Treatment:** Per-tab session binding with document context attached. Cheaper substitute that fails the checkpoint: one global session that mixes tabs together.

**Chrome:** Consume the shared panel styles. Do not invent a second pane treatment.

- [ ] Each tab binds its own agent session; switching tabs switches the transcript. Done when: the binding test passes with three tabs.
- [ ] The open document (path, language guess, dirty state, selection) is attached as context within the committed size budget. Done when: the context test proves what the agent receives.
- [ ] Context never leaks across tabs: a prompt in tab A cannot see tab B. Done when: the isolation test passes.
- [ ] Unsaved (untitled, dirty) documents contribute their buffer, marked as unsaved. Done when: the unsaved-context test passes.
- [ ] Commit: `"ai-surface: bind the pane per tab with document context"`

**Test checkpoint:** Binding, context-content, isolation, and unsaved-context tests green against scripted sessions. Cheaper substitute that fails: context that works only for saved files.

## 3. Slash Commands

Why this section exists: the common actions (new session, clear, stop, model pick) must work without leaving the keyboard. The command set is defined in the design contract.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can drive the agent session from the input box. Consumer: the session layer, which executes each command.

**Treatment:** `/`-prefixed commands with a discoverable list. Cheaper substitute that fails the checkpoint: commands that exist but are undiscoverable.

**Chrome:** Consume the shared input styles. Do not invent a second command treatment.

- [ ] `/new`, `/clear`, `/stop`, `/sessions`, and `/help` work with the semantics recorded in the contract. Done when: each is driven.
- [ ] `/model [id]` switches models where the agent offers them, and reports honestly where it does not. Done when: both are driven.
- [ ] Unknown commands report with the list, never silently fail. Done when: the unknown-command test passes.
- [ ] Typing `/` shows the available commands for the current session. Done when: the discovery is driven.
- [ ] Commit: `"ai-surface: add slash commands"`

**Test checkpoint:** Command matrix driven including unknown and undiscoverable-model cases. Cheaper substitute that fails: slash commands parsed but acting on the wrong session.

## 4. Agent Management Panel

Why this section exists: users run long tasks and return to them. The management panel shows active agents, their states, and past sessions in one place.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can check and resume agent work from one panel. Consumer: the session layer, which resumes what the user picks.

**Treatment:** Management panel per the contract. Cheaper substitute that fails the checkpoint: a session list that cannot resume.

**Chrome:** Consume the shared panel styles. Do not invent a second management treatment.

- [ ] `src/Notepad/AgentManagement.xaml` lists active sessions with live states from `D04 T02 §2`. Done when: the list test passes with mixed states.
- [ ] Selecting a session resumes its transcript in the panel. Done when: the resume is driven.
- [ ] Long-running sessions are checkable without disturbing them. Done when: the check-without-disturb test passes.
- [ ] Commit: `"ai-surface: add the agent management panel"`

**Test checkpoint:** List, resume, and check-without-disturb driven. Cheaper substitute that fails: management that shows sessions but resumes the wrong one.

## 5. Token Usage Display

Why this section exists: agent work costs tokens. The session shows its usage where the user works, toggleable, honest about what the agent reports.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can see session token usage at a glance. Consumer: none, this surface is the consumer.

**Treatment:** Usage readout in the status bar with detail on demand. Cheaper substitute that fails the checkpoint: usage nobody can find.

**Chrome:** Consume the shared status styles. Do not invent a second usage treatment.

- [ ] The readout shows the session's reported usage, updating as turns complete. Done when: the update test passes against scripted turns.
- [ ] Agents that report no usage show an honest absence, never a zero that implies free. Done when: the absence test passes.
- [ ] The display toggles in Agent settings with the choice persisted. Done when: the toggle is driven.
- [ ] Commit: `"ai-surface: display token usage"`

**Test checkpoint:** Update, absence-honesty, and toggle tests green. Cheaper substitute that fails: a hardcoded zero.

## Verification

- [ ] `dotnet test` green
- [ ] Chrome judged against the design contract, all surfaces covered
- [ ] `python3 scripts/todo-graph.py validate` clean
