---
schema_version: 1
id: permission-apply-ux
domain: 05-ai-surface
status: draft
title: "TODO-02 -- Permission and Apply UX"
depends_on: ["chat-panel", "agent-sessions-auth"]
track: A3
---

# TODO-02 -- Permission and Apply UX

> **Goal:** Permission prompts the user can answer with understanding, tool calls shown honestly, and agent edits applied to the editor only through review and the undoable edit path.

> [!IMPORTANT]
> **Current state:** `D03 T02` answers permissions and `D04 T02` manages sessions, but no UI renders either. The chat panel exists per `D05 T01`. This file is where the agent's actions meet the user's judgment.

## Inputs

- [ACP elicitation](https://agentclientprotocol.com/protocol/v1/elicitation) -- structured user input during turns
- [ACP agent plan](https://agentclientprotocol.com/protocol/v1/agent-plan) -- plan display during turns
- -> XREF: D04 T02 §1 -- session auth this UX gates; the consent contract below is what auth prompts render through

## Outcome

- Every permission prompt shows kind, scope, and risk with allow, deny, and scope choices.
- Tool calls and plans display live with honest states.
- Agent edits reach the buffer only through diff review, and every apply is undoable.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (prompts are in-panel, not notifications); permissions=applicable @ D05 T02 §1; audit=applicable @ D03 T02 §5; exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** This file owns the permission prompt surface; grants audit in D03; applied edits undo through the D02 stack.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Permission prompt surface | D05 T01 §1, D03 T02 §1 |  [ ]   |
|   2   |   §2    | Tool-call and plan display | D05 T01 §2 |  [ ]   |
|   3   |   §3    | Diff review | §1 |  [ ]   |
|   4   |   §4    | Apply to editor through undo | §3, D02 T01 §4 |  [ ]   |
|   5   |   §5    | Elicitation forms | §1 |  [ ]   |
|   6   |   §6    | Selection actions: explain, rewrite, summarize | §3, §4 |  [ ]   |

---

## 1. Permission Prompt Surface

Why this section exists: consent the user does not understand is not consent. The prompt shows kind, scope, and risk with real choices.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can answer permission requests with understanding. Consumer: the permission handler, which receives exactly one answer.

**Treatment:** In-panel prompt per the contract. Cheaper substitute that fails the checkpoint: allow/deny with no scope shown.

**Chrome:** Consume the shared prompt styles. Do not invent a second prompt treatment.

- [ ] `src/Notepad/PermissionPrompt.xaml` renders kind, scope, risk summary, and allow/deny/scope choices per the `D03 T02 §1` contract. Done when: the contract test passes against the real prompt.
- [ ] Timeout and dismiss count as deny, visibly. Done when: both are driven.
- [ ] Scope choices (once, session, always-for-scope) map exactly to `D03 T02 §4` grants. Done when: the mapping test passes.
- [ ] Prompts queue without loss when several arrive at once. Done when: the queue test passes.
- [ ] Commit: `"ai-surface: build the permission prompt"`

**Test checkpoint:** Prompt matrix driven against scripted requests; timeout, scope mapping, and queue proven. Cheaper substitute that fails: prompts answered in tests without rendering them.

## 2. Tool-Call and Plan Display

Why this section exists: users must see what the agent is doing while it does it. Live states, honest completion, no theater.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can follow tool calls and plans live. Consumer: none, this surface is the consumer.

**Treatment:** Live display per the contract. Cheaper substitute that fails the checkpoint: showing only completed calls.

**Chrome:** Consume the shared transcript styles. Do not invent a second call treatment.

- [ ] Tool calls render pending, running, awaiting-permission, done, failed, and denied states. Done when: each is driven.
- [ ] Plans render with step states as the agent reports them. Done when: the plan fixtures pass.
- [ ] Failed and denied calls show cause with the next step visible. Done when: both are driven.
- [ ] Commit: `"ai-surface: display tool calls and plans"`

**Test checkpoint:** State matrix and plan fixtures driven against scripted turns. Cheaper substitute that fails: states asserted without rendering.

## 3. Diff Review

Why this section exists: no agent edit reaches the buffer unseen. The diff shows exactly what would change, in terms the user can verify.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can review proposed edits before they apply. Consumer: the apply path, which receives only reviewed hunks.

**Treatment:** Side-by-side or unified diff per the contract. Cheaper substitute that fails the checkpoint: apply without review.

**Chrome:** Consume the shared diff styles. Do not invent a second diff treatment.

- [ ] Proposed edits render as diffs against the current buffer with hunk accept/reject. Done when: the hunk matrix is driven.
- [ ] Diffs rebase honestly when the buffer changed since the proposal; stale hunks are marked, never silently applied. Done when: the staleness test passes.
- [ ] Large diffs virtualize within the perf budget. Done when: the budget is measured in CI.
- [ ] Commit: `"ai-surface: review agent edits as diffs"`

**Test checkpoint:** Hunk matrix, staleness, and perf driven. Cheaper substitute that fails: whole-file accept with no hunk granularity.

## 4. Apply to Editor through Undo

Why this section exists: applying is a write, and writes go through the editor's undoable path or they do not go at all.

- [ ] Accepted hunks apply through the `D02 T01` edit interface as undo units. Done when: apply-then-undo restores the buffer exactly.
- [ ] Partial accept applies exactly the accepted hunks, nothing more. Done when: the partiality test passes.
- [ ] Apply conflicts (buffer changed under the hunk) refuse with the conflict shown, never overwrite. Done when: the conflict test passes.
- [ ] Every apply marks the tab dirty through the `D01 T01 §2` model. Done when: the dirty test passes.
- [ ] Commit: `"ai-surface: apply reviewed edits through undo"`

**Test checkpoint:** Apply, partial, conflict, dirty, and undo-restores tests green. Cheaper substitute that fails: apply that writes the buffer directly.

## 5. Elicitation Forms

Why this section exists: agents ask structured questions mid-turn. The forms render the schema faithfully and return exactly one answer.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can answer agent questions in place. Consumer: the turn, which receives exactly one answer.

**Treatment:** Schema-driven forms per the contract. Cheaper substitute that fails the checkpoint: free text for every question.

**Chrome:** Consume the shared form styles. Do not invent a second form treatment.

- [ ] Elicitation schemas render as typed forms (text, choice, confirmation) with validation. Done when: each field kind is driven.
- [ ] Dismiss counts as the schema's default or as decline, visibly and exactly once. Done when: both are driven.
- [ ] Malformed schemas render an error, never a broken form. Done when: the malformed test passes.
- [ ] Commit: `"ai-surface: render elicitation forms"`

**Test checkpoint:** Field kinds, dismiss semantics, and malformed schemas driven. Cheaper substitute that fails: elicitation answered without rendering.

## 6. Selection Actions: Explain, Rewrite, Summarize

Why this section exists: this is the answer to Notepad's subscription-gated Write/Rewrite/Summarize. The same verbs, powered by the user's own connected agent, with no Microsoft account, no AI credits, and no paywall. Filed by groom 2026-09-14 from the Notepad surface research.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`. Placement follows Notepad's Rewrite entry points (context menu, Edit menu) so users find it where they looked before.

**Job:** The user can explain, rewrite, or summarize the selection through their agent. Consumer: the diff review (§3), which receives every proposed change.

**Treatment:** Selection actions per the contract, placed where Notepad places Rewrite. Cheaper substitute that fails the checkpoint: actions that send the selection without showing what will happen.

**Chrome:** Consume the shared menu and diff styles. Do not invent a second action treatment.

**Groomed 2026-09-13:** Notepad audit: committed shortcuts, rewrite presets, summarize lengths, the Write flow, the off-switch, the no-Microsoft-AI-stack and privacy stances, and streaming proposals are now explicit (Write was named in scope but had no items).

- [ ] Explain, rewrite, and summarize appear on the selection context menu and Edit menu with committed shortcuts. Done when: each entry point is driven.
- [ ] Each action needs no Microsoft account, subscription, or credit: it uses the tab's connected agent or reports honestly that none is connected. Done when: the no-agent and no-network cases are driven.
- [ ] Rewrite and summarize proposals land in §3 diff review; nothing applies directly. Done when: the routing test passes.
- [ ] Explain renders in the panel without touching the buffer. Done when: the buffer-untouched test passes.
- [ ] Consent follows §1: the first selection action per session prompts with scope, then the grant governs. Done when: the consent flow is driven.
- [ ] Rewrite, Summarize, and Write use Ctrl+D, Ctrl+M, and Ctrl+Q; Explain's shortcut is committed in the design contract with no Notepad conflict. Done when: each shortcut is driven and the contract records the conflict matrix. Source: https://support.microsoft.com/en-gb/windows/enhance-your-writing-with-ai-in-notepad-4088b954-c97b-46dc-813f-959be01746d5
- [ ] Rewrite offers length, tone, and format presets plus free-prompt custom rewrite; preset effects and tone values are recorded from the capture. Done when: each preset and custom rewrite route a proposal to §3. Source: https://www.digitalcitizen.life/rewrite-text-notepad-windows-11/
- [ ] Summarize offers short, medium, and long lengths with regenerate; inserting a summary routes through §3 diff review, never directly. Done when: each length and the review routing are driven. Source: https://support.microsoft.com/en-gb/windows/enhance-your-writing-with-ai-in-notepad-4088b954-c97b-46dc-813f-959be01746d5
- [ ] Write opens a cursor-anchored prompt; output lands in §3 diff review as Keep/Discard hunks with follow-up refine. Done when: prompt, keep, discard, and follow-up are driven. Source: https://blogs.windows.com/windows-insider/2025/05/22/paint-snipping-tool-and-notepad-updates-with-new-features-begin-rolling-out-to-windows-insiders/
- [ ] An AI master toggle in Settings hides every selection-action entry (menus, context items, shortcuts inert). Done when: toggle-off hides all entries. Source: https://www.windowslatest.com/2025/03/15/microsoft-is-adding-recent-files-feature-copilot-button-to-notepad-on-windows-11/
- [ ] No Microsoft AI stack exists: no MS sign-in, no AI credits, no Copilot+ local-model mode, no Entra unlock; agents authenticate with user keys in the platform credential store (D04 T02 §1). Done when: the absence is verified and the auth path driven. Source: https://support.microsoft.com/en-gb/windows/enhance-your-writing-with-ai-in-notepad-4088b954-c97b-46dc-813f-959be01746d5
- [ ] Selection and document data go only to the connected agent; nothing reaches Microsoft; locality and redaction follow D01 T01 §6 and D04 T02 §5. Done when: the data-flow review passes and the redaction tests cover selection actions.
- [ ] Selection-action proposals stream into §3 review as they arrive; the UI never waits silently for turn end. Done when: partial-proposal rendering is driven. Source: https://blogs.windows.com/windows-insider/2026/01/21/notepad-and-paint-updates-begin-rolling-out-to-windows-insiders/
- [ ] Commit: `"ai-surface: act on selections with the connected agent"`

**Test checkpoint:** Entry points, no-agent honesty, diff routing, untouched-buffer explain, and consent driven. Cheaper substitute that fails: a rewrite that applies without review.

## Verification

- [ ] `dotnet test` green
- [ ] No agent edit reaches the buffer without review and undo
- [ ] `python3 scripts/todo-graph.py validate` clean
