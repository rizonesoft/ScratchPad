---
schema_version: 1
id: grammar-checking
domain: 02-editor
status: draft
title: "TODO-05 -- Grammar Checking"
depends_on: ["editing-surface"]
track: N2
---

# TODO-05 -- Grammar Checking

> **Goal:** Beyond-Notepad grammar and style checks that run fully offline and private: English-first findings underline in blue with explanations, apply through the undoable edit path, and toggle globally and per file type. Stock Notepad has no grammar surface, so nothing here answers to a baseline.

> [!IMPORTANT]
> **Current state:** No grammar exists. The `D02 T01` buffer and caret model (open) carry the text this file checks; the `D01 T02 §2` store (open) carries the toggles; the `D02 T03 §2` squiggle treatment (open) is the sibling pattern the underlines mirror. Harper is not vendored. Filed 2026-09-14 from the operator brainstorm as beyond-parity scope, scheduled after the parity base by table order.

## Inputs

- [Harper (Automattic/harper, Apache-2.0)](https://github.com/Automattic/harper) -- offline Rust grammar engine; this file consumes its native library plus its lint/explanation model, English-first
- [`02-editor/TODO-01-editing-surface.md`](./TODO-01-editing-surface.md) -- the buffer being checked
- [`01-notepad-core/TODO-02-menus-settings-status.md`](../01-notepad-core/TODO-02-menus-settings-status.md) -- §2 owns the toggles
- -> XREF: D02 T03 §2 -- the squiggle/menu treatment the grammar underlines mirror; no behavior deferred either way

## Outcome

- English grammar and style findings underline in blue with a plain-language explanation each.
- Applying a fix is one undo unit; ignoring lasts for the session unless the store says otherwise.
- Checking never blocks typing, never touches the network, and never flags non-English text.
- Grammar toggles globally and per file type through the settings store.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Grammar toggles live in the D01 store with their consumer named there; grammar fixes undo through the D02 stack like spelling fixes.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Grammar engine over the buffer | D02 T01 §2 |  [ ]   |
|   2   |   §2    | Grammar underlines and suggestion cards | §1 |  [ ]   |
|   3   |   §3    | Grammar toggle and language scope | §2, D01 T02 §2 |  [ ]   |
|   4   |   §4    | Style lints: passive voice and weasel words | §1, §2 |  [ ]   |

---

## 1. Grammar Engine over the Buffer

Why this section exists: the UI is thin; the engine carries the semantics. Findings, spans, and explanations are settled and tested here, offline.

**Decided 2026-09-14:** Harper (Automattic/harper, Apache-2.0) embedded as a native library: the best offline open-source grammar engine that embeds in a desktop app (sub-10ms checks, no server, no network). Grammarly-quality is not attainable open-source today; Harper's lint corpus plus the explanation card is the closest embeddable shape. Alternative recorded: a self-hosted LanguageTool server (more languages and rules, JVM weight, a sidecar process to ship and supervise) -- rejected for embed weight. Cost of changing engines: rewrite `src/Notepad.Core/GrammarEngine.cs` plus the native layer; the lint corpus and checkpoints stay.

- [ ] Harper builds from a pinned revision into a native library with a C ABI under `src/Notepad.Core/Native/`. Done when: the lib builds for win-x64 with no network at check time. Cheaper substitute that fails: a cloud grammar API.
- [ ] `src/Notepad.Core/GrammarEngine.cs` checks the buffer through P/Invoke and reports findings with spans plus explanations, English-first. Done when: the seeded lint corpus (agreement, articles, punctuation, common confusables) reports every finding and non-English text reports none.
- [ ] Checking never blocks typing: it runs debounced off the typing path within the committed budget on large buffers. Done when: the perf test measures check latency under load with typing unblocked.
- [ ] The engine exposes ignore-rule and per-file disable hooks for the UI. Done when: both are tested at the engine level.
- [ ] Commit: `"editor: add the grammar engine"`

**Test checkpoint:** `dotnet test --filter GrammarEngine` green on the corpus; perf budget measured; no network touched. Cheaper substitute that fails: grammar that phones home or hangs on ten thousand words.

## 2. Grammar Underlines and Suggestion Cards

Why this section exists: the blue underline is the surface users see. It must render, explain, and apply without ever looking like a spelling squiggle.

**Fidelity:** new build, no baseline (stock Notepad has no grammar surface).

**Job:** The user can see and fix grammar findings as a first-class surface. Consumer: the buffer, through the undoable edit path.

**Treatment:** Blue wavy underline, visually distinct from the red spelling squiggle; click opens a card with the explanation plus Apply and Ignore. Cheaper substitute that fails the checkpoint: underlines with no explanation.

**Chrome:** Consume the shared editor and menu styles; mirror the D02 T03 §2 card treatment. Do not invent a second suggestion treatment.

**Needs:** Windows host (build/test)

- [ ] Grammar findings render the blue underline with as-you-type timing, never styled as spelling. Done when: the render test passes.
- [ ] Clicking opens the card with the explanation plus Apply and Ignore. Done when: each action is driven.
- [ ] Applying a fix is one undo unit; Ignore lasts the session. Done when: apply-then-undo and ignore fixtures pass.
- [ ] Commit: `"editor: render grammar underlines and cards"`

**Test checkpoint:** Render, card actions, and undo grouping driven; capture comparison passes. Cheaper substitute that fails: fixes that bypass undo.

## 3. Grammar Toggle and Language Scope

Why this section exists: grammar is opinionated and English-first, so it must be trivially scoped: global, per file type, and visible in what it covers.

**Fidelity:** new build, no baseline (extends the D02 T03 §4 settings surface with one grammar row).

**Job:** The user can scope grammar to where they want it. Consumer: the settings store, which the grammar engine reads.

**Treatment:** One grammar row beside the spelling toggles, default on, with the English-first scope stated inline. Cheaper substitute that fails the checkpoint: a global toggle only.

**Chrome:** Consume the shared settings styles. Do not invent a second toggle treatment.

**Needs:** Windows host (build/test)

- [ ] The settings page carries the grammar toggle bound to the D01 T02 §2 store. Done when: the toggle is driven.
- [ ] Toggling takes effect on open buffers immediately. Done when: the live-effect test passes.
- [ ] The toggle defaults on with the English-first scope stated beside it. Done when: the default and the scope line are recorded and tested.
- [ ] Commit: `"editor: toggle grammar checking"`

**Test checkpoint:** Toggle, live effect, and default driven; capture comparison passes. Cheaper substitute that fails: toggles that need a restart.

## 4. Style Lints: Passive Voice and Weasel Words

Why this section exists: the grammar engine (§1) and cards (§2) gain two style rule sets. No new surface: the lints arrive as cards.

**Fidelity:** new build, no baseline (stock Notepad lints nothing).

**Job:** The user can see passive voice and weasel words flagged like grammar. Consumer: the suggestion cards (§2), which render the lints; the engine (§1), which runs the rules.

**Treatment:** Passive-voice and weasel-word rules run in §1; findings surface as §2 cards with rewrite suggestions. Cheaper substitute that fails the checkpoint: a separate style panel.

**Chrome:** Consume the shared card styles. Do not invent a second lint treatment.

**Needs:** Windows host (build/test)

- [ ] Passive-voice rules flag correctly on fixtures. Done when: the fixture suite passes with no false positives on the negatives.
- [ ] Weasel-word rules flag from a stated list. Done when: the list is recorded and fixtures pass.
- [ ] Both surface as §2 suggestion cards with rewrites. Done when: cards render under host drive.
- [ ] The lints stay offline like the engine. Done when: the network-negative tests pass.
- [ ] Commit: `"editor: lint style with grammar"`

**Test checkpoint:** both rule sets, card surfacing, and offline proof are all driven in the room. Cheaper substitute that fails: lints with no rewrite.

## Verification

- [ ] `dotnet test` green
- [ ] Offline proof: engine tests touch no network
- [ ] `python3 scripts/todo-graph.py validate` clean
