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

**Groomed 2026-09-23:** Chrome corrected: no shared panel, transcript, or input styles exist (`src/ScratchPad/App.xaml` merges only `XamlControlsResources`, and D01 T01 §14 recorded the same); follow the code-built dialog pattern (ExportDialog, WhatsNewDialog), and D05 T01 §1 defines the AI styles once in its contract.

## Outcome

- Every permission prompt shows kind, scope, and risk with allow, deny, and scope choices.
- Tool calls and plans display live with honest states.
- Agent edits reach the buffer only through diff review, and every apply is undoable.

**Adjacency:** list=applicable @ D05 T02 §7; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (no reports in this file); notifications=not-applicable (prompts are in-panel, not notifications); permissions=applicable @ D05 T02 §1; audit=applicable @ D03 T02 §5; exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** This file owns the permission prompt surface; grants audit in D03; applied edits undo through the D02 stack; the §7 language picker is the list.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Permission prompt surface | D05 T01 §1, D03 T02 §1, D03 T02 §4 |  [ ]   |
|   2   |   §2    | Tool-call and plan display | D05 T01 §2, D03 T02 §3 |  [ ]   |
|   3   |   §3    | Diff review | §1, D03 T02 §2 |  [ ]   |
|   4   |   §4    | Apply to editor through undo | §3, D02 T01 §4 |  [ ]   |
|   5   |   §5    | Elicitation forms | §1, D03 T02 §6 |  [ ]   |
|   6   |   §6    | Selection actions: explain, rewrite, summarize | §3, §4, D04 T02 §1, D04 T02 §5 |  [ ]   |
|   7   |   §7    | Document actions: translate, extract, summarize | §1, D01 T01 §2 |  [ ]   |
|   8   |   §8    | Continue writing with ghost drafts | §1, §4, D02 T01 §3 |  [ ]   |
|   9   |   §9    | Agent title suggestions for untitled tabs | §6, D01 T01 §22 |  [ ]   |

|  10   |  §10    | Grants and audit viewer | §1, D03 T02 §4, D03 T02 §5 |  [ ]   |
---

## 1. Permission Prompt Surface

Why this section exists: consent the user does not understand is not consent. The prompt shows kind, scope, and risk with real choices.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can answer permission requests with understanding. Consumer: the permission handler, which receives exactly one answer.

**Treatment:** In-panel prompt per the contract. Cheaper substitute that fails the checkpoint: allow/deny with no scope shown.

**Chrome:** Consume the shared prompt styles. Do not invent a second prompt treatment.

**Groomed 2026-09-23:** Permission shape corrected: ACP agents supply the options (kinds `allow_once`, `allow_always`, `reject_once`, `reject_always`) and the client answers `selected` plus `optionId` or `cancelled`; render the agent's options by kind and record how allow_always and reject_always persist against D03 T02 §4's no-cross-session rule. Timeout and dismiss select a reject option; a turn cancel answers every pending prompt `cancelled`, exactly once.

- [ ] `src/ScratchPad/PermissionPrompt.xaml` renders kind, scope, risk summary, and allow/deny/scope choices per the `D03 T02 §1` contract. Done when: the contract test passes against the real prompt. **Corrected 2026-09-17 (groom):** the seed path `src/Notepad/` never existed (same seed error as D01 T02 §§1/3/4/5).
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
- [ ] Tool-call content renders both kinds ACP sends: `terminal` (live output, with a user kill through `terminal/kill`) and `diff` (`oldText`/`newText`). Done when: a loopback turn with each kind renders and the kill reaches the agent (Groomed 2026-09-23.)
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
- [ ] Large diffs virtualize within the perf budget. Done when: the budget is measured in the local run on the dev box. **Corrected 2026-09-17 (groom):** was "measured in CI"; CI runs no suites since 2026-09-17.
- [ ] Agent file writes route through review: an `fs/write_text_file` or tool-call `diff` against an open tab opens this review, and a closed file gets a backup plus an undo entry, so no agent write bypasses diff review. Done when: both paths are driven and each undoes (Groomed 2026-09-23.)
- [ ] Commit: `"ai-surface: review agent edits as diffs"`

**Test checkpoint:** Hunk matrix, staleness, and perf driven. Cheaper substitute that fails: whole-file accept with no hunk granularity.

## 4. Apply to Editor through Undo

Why this section exists: applying is a write, and writes go through the editor's undoable path or they do not go at all.

- [ ] Accepted hunks apply through the `D02 T01` edit interface as undo units. Done when: apply-then-undo restores the buffer exactly.
- [ ] Partial accept applies exactly the accepted hunks, nothing more. Done when: the partiality test passes.
- [ ] Apply conflicts (buffer changed under the hunk) refuse with the conflict shown, never overwrite. Done when: the conflict test passes.
- [ ] Every apply marks the tab dirty through the `D01 T01 §2` model. Done when: the dirty test passes.
- [ ] Apply is exactly-once: a repeated or racing Apply click applies the change once. Done when: a double-click drive leaves one change and one undo step (Groomed 2026-09-23.)
- [ ] Commit: `"ai-surface: apply reviewed edits through undo"`

**Test checkpoint:** Apply, partial, conflict, dirty, and undo-restores tests green. Cheaper substitute that fails: apply that writes the buffer directly.

## 5. Elicitation Forms

Why this section exists: agents ask structured questions mid-turn. The forms render the schema faithfully and return exactly one answer.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can answer agent questions in place. Consumer: the turn, which receives exactly one answer.

**Treatment:** Schema-driven forms per the contract. Cheaper substitute that fails the checkpoint: free text for every question.

**Chrome:** Consume the shared form styles. Do not invent a second form treatment.

**Groomed 2026-09-23:** -> XREF: D03 T02 §6 (answers `elicitation/create` exactly once; this section renders the form).

**Groomed 2026-09-23:** Elicitation shape corrected: the three answers are `accept`, `decline`, and `cancel` (dismissed without choosing), so dismiss answers `cancel`, distinct from `decline`; URL mode opens out of band with consent; `clientCapabilities.elicitation` advertises form and url.

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

**Groomed 2026-09-23:** Toggle corrected: a disabled Writing tools card already exists (`SettingsCardWritingTools`, `SettingsWritingToolsToggle` in `SettingsPage.xaml`), and D01 T02 §3 assigns it to this item; enable and bind it as the AI master toggle instead of adding a card.

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

## 7. Document Actions: Translate, Extract, Summarize

Why this section exists: some agent work produces new documents, not buffer edits: translation, meeting-note extraction, whole-document summary. New tabs carry them, so nothing is overwritten and no review theater is owed.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can translate, extract, and summarize into new tabs. Consumer: the tab model, which receives finished documents.

**Treatment:** Actions per the contract, delivering to new tabs; consent-first like §6. Cheaper substitute that fails the checkpoint: document results inserted into the buffer without review.

**Chrome:** Consume the shared menu and tab styles. Do not invent a second action treatment.

**Needs:** Windows host (build/test)

- [ ] Translate renders the selection or document into the picked language in a new tab through a language picker that lists the supported target languages. Done when: both scopes and the picker are driven.
- [ ] Action items and dates extract from meeting notes into a checklist tab. Done when: the extraction is driven.
- [ ] Document summary lands in a new tab at short, medium, and long lengths. Done when: each length is driven.
- [ ] Each action uses the tab's connected agent or reports honestly that none is connected. Done when: the no-agent and no-network cases are driven.
- [ ] Consent follows §1: the first document action per session prompts with scope, then the grant governs. Done when: the consent flow is driven.
- [ ] Selection and document data go only to the connected agent; locality and redaction follow D01 T01 §6 and D04 T02 §5. Done when: the data-flow review passes.
- [ ] Commit: `"ai-surface: act on documents with the connected agent"`

**Test checkpoint:** Entry points, no-agent honesty, new-tab delivery, and consent driven. Cheaper substitute that fails: document actions that overwrite the buffer.

## 8. Continue Writing with Ghost Drafts

Why this section exists: the agent drafts the next paragraph where the caret is. Ghost text shows it; accept applies through undo and dismiss vanishes it.

**Fidelity:** new build, no baseline; judged against `docs/ai-panel-contract.md`.

**Job:** The user can continue writing from an agent draft. Consumer: the apply path (§4), which receives only accepted text.

**Treatment:** Ghost render per the contract with streaming partials; accept and dismiss inline. Cheaper substitute that fails the checkpoint: drafts inserted without ghost review.

**Chrome:** Consume the shared editor styles. Do not invent a second ghost treatment.

**Needs:** Windows host (build/test)

- [ ] Continue-writing drafts the next paragraph from buffer context. Done when: driven.
- [ ] Drafts render ghosted with streaming partials. Done when: driven.
- [ ] Accept applies through §4 undo and dismiss clears without a trace. Done when: both are driven.
- [ ] No-agent and no-network cases report honestly. Done when: both are driven.
- [ ] Consent follows §1. Done when: the consent flow is driven.
- [ ] Commit: `"ai-surface: continue writing with ghost drafts"`

**Test checkpoint:** Draft, ghost, accept, dismiss, undo, and consent driven. Cheaper substitute that fails: drafts that bypass review.

## 9. Agent Title Suggestions for Untitled Tabs

Why this section exists: the first-line default (D01 T01 §22) is a starting point; the agent suggests better titles on request, applied title-only, never touching content.

**Fidelity:** new build, no baseline (no stock counterpart; judged on its own contract).

**Job:** The user can rename an untitled tab with agent help. Consumer: the tab bar (D01 T01 §22), which renders the picked title; the action path (§6), which invokes the agent.

**Treatment:** A suggest command sends the note's opening to the agent through §6's invocation; the picked suggestion applies as the tab title only. Title-only and reversible: no consent gate, but the request is explicit. Cheaper substitute that fails the checkpoint: titles that rewrite themselves unprompted.

**Chrome:** Consume the shared tab styles. Do not invent a second title treatment.

**Needs:** Windows host (build/test)

- [ ] A suggest command asks the agent for titles. Done when: the suggestion round-trip is driven.
- [ ] The picked suggestion applies as the tab title only. Done when: content fixtures prove no edit.
- [ ] Suggestions never fire unprompted. Done when: the negative test passes.
- [ ] Commit: `"ai-surface: suggest tab titles"`

**Test checkpoint:** round-trip, title-only apply, and explicit-only are all driven in the room. Cheaper substitute that fails: a title that edits the note.

## 10. Grants and Audit Viewer

Why this section exists: nothing lists or revokes remembered allow_always and reject_always choices, D03 T02 §4 revocation has no UI, and D03 T02 §5 says the UI surfaces the grant log where this file designs it, with no item doing so (groom 2026-09-23). -> XREF: D03 T02 §4 (grants and revocation), D03 T02 §5 (the audit log).

**Groomed 2026-09-23:** -> XREF: D05 T03 §6 (the AI settings group links to this viewer and hosts the master toggle).

- [ ] A viewer lists live grants and remembered choices per agent and session, and revoking one takes effect on the next request. Done when: revoke is driven and the next request prompts again
- [ ] The viewer shows the D03 T02 §5 audit log with filtering by agent and outcome, read-only. Done when: a seeded log renders and filters
- [ ] Commit: `"ai-surface: grants and audit viewer"`

**Test checkpoint:** list, revoke, and audit rendering driven against seeded grants. Cheaper substitute that fails: a viewer that shows grants but cannot revoke them.

## Verification

- [ ] `dotnet test` green
- [ ] No agent edit reaches the buffer without review and undo
- [ ] `python3 scripts/todo-graph.py validate` clean
