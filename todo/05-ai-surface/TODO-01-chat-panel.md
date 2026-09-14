---
schema_version: 1
id: chat-panel
domain: 05-ai-surface
status: draft
title: "TODO-01 -- Chat Panel"
depends_on: ["winui-app-spine", "acp-transport-lifecycle"]
track: A3
---

# TODO-01 -- Chat Panel

> **Goal:** A chat panel beside the editor where the user picks an agent, sends prompts, watches streamed updates, and reviews history.

> [!IMPORTANT]
> **Current state:** No AI surface exists. `D03 T01 §5` streams updates to the transcript contract settled in §1 here; the shell hosts the panel per `D01 T01 §1`.

## Inputs

- [ACP prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn) -- the conversation flow being rendered
- [ACP content](https://agentclientprotocol.com/protocol/v1/content) -- the content blocks being rendered
- -> XREF: D03 T01 §5 -- the prompt-turn stream this panel renders; the transcript contract below is what it delivers to

## Outcome

- The panel renders transcripts faithfully in arrival order with stop reasons visible.
- Input, agent picker, history, and cancellation all work with keyboard and mouse.
- The panel never blocks the editor: both stay live during a turn.

**Adjacency:** list=applicable @ D05 T01 §5; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (turn completion is in-panel state, not a notification); permissions=applicable @ D05 T02 §1; audit=applicable @ D03 T02 §5; exchange=applicable @ D05 T01 §7; reverse=applicable @ D05 T01 §4

**Adjacency rationale:** History is the list; cancelling a turn is the reversal; grants audit in D03; AI settings persist through the D01 store. §7 exports transcripts through the D01 file writer.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Panel shell and transcript contract | D01 T01 §1, D03 T01 §5 |  [ ]   |
|   2   |   §2    | Streaming transcript rendering | §1 |  [ ]   |
|   3   |   §3    | Input, send, and stop | §1 |  [ ]   |
|   4   |   §4    | Turn states and cancellation UX | §2, §3 |  [ ]   |
|   5   |   §5    | Agent picker and history | §1 |  [ ]   |
|   6   |   §6    | Panel and editor coexistence | §2, §3 |  [ ]   |
|   7   |   §7    | Chat export to Markdown | §1, D01 T01 §5 |  [ ]   |

---

## 1. Panel Shell and Transcript Contract

Why this section exists: the panel is new, so its contract is settled before its pixels: placement, transcript data shape, and the stream it consumes.

**Fidelity:** new build, no baseline. The design contract in `docs/ai-panel-contract.md` (written here) is the artifact review judges against.

**Job:** The user can hold an agent conversation beside the editor. Consumer: the transcript view, which renders the contract.

**Treatment:** Docked panel per the design contract. Cheaper substitute that fails the checkpoint: a modal dialog standing in for the panel.

**Chrome:** Consume the shared panel styles. Do not invent a second panel treatment.

- [ ] `docs/ai-panel-contract.md` specifies placement, transcript shape, update ordering, and stop-reason display. Done when: the doc exists and `D03 T01 §5` delivers to it.
- [ ] `src/Notepad/ChatPanel.xaml` hosts the transcript region, input region, and agent picker per the contract. Done when: the regions render.
- [ ] The panel opens, closes, and persists its visibility through the settings store. Done when: the toggle is driven.
- [ ] Commit: `"ai-surface: settle the panel shell and transcript contract"`

**Test checkpoint:** Contract exists and the stream test delivers to it; regions render; toggle driven. Cheaper substitute that fails: pixels first with the contract reconstructed later.

## 2. Streaming Transcript Rendering

Why this section exists: streaming is the product feel. Updates render as they arrive, in order, with content blocks rendered by kind.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can watch the turn unfold live. Consumer: none, this surface is the consumer.

**Treatment:** Append-in-order streaming per the contract. Cheaper substitute that fails the checkpoint: rendering only at turn end.

**Chrome:** Consume the shared transcript styles. Do not invent a second message treatment.

- [ ] `src/Notepad/TranscriptView.xaml` renders text, code, tool-call, and plan blocks by kind. Done when: each kind is driven with a scripted turn.
- [ ] Out-of-order arrivals still render in order; duplicates never render twice. Done when: the ordering fixtures pass.
- [ ] Long transcripts virtualize so the panel stays responsive. Done when: the perf budget is measured in CI.
- [ ] Stop reasons render visibly at turn end. Done when: each reason is driven.
- [ ] Commit: `"ai-surface: render the streaming transcript"`

**Test checkpoint:** Scripted turns render by kind in order; perf budget measured; stop reasons visible. Cheaper substitute that fails: a text dump of raw updates.

## 3. Input, Send, and Stop

Why this section exists: input is the user's voice. Send, stop, multiline, and history must all work by keyboard.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can compose and send prompts and stop a running turn. Consumer: the session, which receives the prompt.

**Treatment:** Input box with send/stop per the contract. Cheaper substitute that fails the checkpoint: send without stop.

**Chrome:** Consume the shared input styles. Do not invent a second input treatment.

- [ ] The input box sends on Enter, newlines on Shift+Enter, and recalls history on Up. Done when: the keyboard flow is driven.
- [ ] Send is disabled exactly when no session can take a prompt, with the reason visible. Done when: the enablement matrix is driven.
- [ ] Stop cancels the running turn through `D03 T01 §6` and the panel reflects the cancelled state. Done when: the stop flow is driven.
- [ ] Commit: `"ai-surface: add input, send, and stop"`

**Test checkpoint:** Keyboard flow, enablement, and stop driven. Cheaper substitute that fails: mouse-only input.

## 4. Turn States and Cancellation UX

Why this section exists: a turn is always in exactly one visible state. Ambiguity here reads as a frozen app.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can always tell what the turn is doing. Consumer: none, this surface is the consumer.

**Treatment:** Explicit turn states per the contract. Cheaper substitute that fails the checkpoint: a spinner with no state.

**Chrome:** Consume the shared state styles. Do not invent a second state treatment.

- [ ] Idle, sending, streaming, awaiting-permission, cancelling, done, and failed states each render distinctly. Done when: each is driven.
- [ ] Cancellation from any cancellable state reaches a settled state with no stuck spinner. Done when: the state matrix is driven.
- [ ] Failed turns show the structured error with a retry that starts a clean turn. Done when: the failure flow is driven.
- [ ] Commit: `"ai-surface: show turn states and cancellation"`

**Test checkpoint:** State matrix driven; no stuck states; failure and retry driven. Cheaper substitute that fails: states asserted in unit tests while the panel shows one spinner.

## 5. Agent Picker and History

Why this section exists: users switch agents and revisit conversations. The picker shows health honestly; history restores faithfully.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can pick an agent and revisit past turns. Consumer: the session layer, which receives the choice.

**Treatment:** Picker and history per the contract. Cheaper substitute that fails the checkpoint: a picker that offers unhealthy agents.

**Chrome:** Consume the shared picker styles. Do not invent a second picker treatment.

- [ ] The picker lists detected agents with health state from `D04 T01 §3`; unhealthy agents are unselectable with cause. Done when: the picker matrix is driven.
- [ ] History lists past turns per session and restores the transcript on selection. Done when: the restore is driven.
- [ ] Switching agents mid-conversation is either supported with clear semantics or refused with a reason, never silently destructive. Done when: the behavior is tested.
- [ ] Commit: `"ai-surface: add the agent picker and history"`

**Test checkpoint:** Picker, history restore, and switch semantics driven. Cheaper substitute that fails: history that restores the wrong transcript.

## 6. Panel and Editor Coexistence

Why this section exists: the panel must never break the editor. Both stay live, focused correctly, during turns.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can edit while the agent works. Consumer: the editor surface, which stays fully live.

**Treatment:** Coexistence per the contract. Cheaper substitute that fails the checkpoint: a modal panel that blocks editing.

**Chrome:** Consume the shared layout styles. Do not invent a second layout treatment.

- [ ] Focus moves between panel and editor by keyboard and mouse with no traps. Done when: the focus matrix is driven.
- [ ] Typing in the editor during a streaming turn never corrupts the transcript or the buffer. Done when: the concurrency test passes.
- [ ] The panel resizes and collapses without disturbing the editor layout. Done when: the layout test passes.
- [ ] Commit: `"ai-surface: keep panel and editor live together"`

**Test checkpoint:** Focus, concurrency, and layout tests green. Cheaper substitute that fails: coexistence claimed without a concurrency test.

## 7. Chat Export to Markdown

Why this section exists: any agent transcript saves as a Markdown file in one click.

**Fidelity:** new build, no baseline (no stock counterpart; judged on its own contract).

**Job:** The user can export a transcript as Markdown. Consumer: the file writer (D01 T01 §5), which saves the export.

**Treatment:** One click renders the §1 transcript (turns, code blocks, timestamps) to Markdown and saves through the file dialog. Cheaper substitute that fails the checkpoint: copy-paste instructions instead of an export.

**Chrome:** Consume the shared panel styles. Do not invent a second export treatment.

**Needs:** Windows host (build/test)

- [ ] One click exports the current transcript to Markdown. Done when: the click path is driven.
- [ ] Turns, code blocks, and timestamps render faithfully. Done when: fixtures match exactly.
- [ ] The export saves through D01 T01 §5's dialog. Done when: the save path is driven.
- [ ] Commit: `"ai-surface: export chats to Markdown"`

**Test checkpoint:** one-click path, faithful render, and save are all driven in the room. Cheaper substitute that fails: an export that drops turns.

## Verification

- [ ] `dotnet test` green
- [ ] Design contract exists and every surface is judged against it
- [ ] `python3 scripts/todo-graph.py validate` clean
