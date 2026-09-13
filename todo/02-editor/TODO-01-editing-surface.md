---
schema_version: 1
id: editing-surface
domain: 02-editor
status: draft
title: "TODO-01 -- Editing Surface"
depends_on: ["winui-app-spine"]
track: N2
---

# TODO-01 -- Editing Surface

> **Goal:** A text surface that types, selects, undoes, zooms, and wraps exactly like Windows 11 Notepad, hosted in the app shell.

> [!IMPORTANT]
> **Current state:** The `D01 T01` shell hosts a placeholder where this surface goes. No buffer, no caret handling, no undo. This file settles the hosting contract first, then builds the surface behind it.

## Inputs

- `resources/baseline/` captures of the editor area, caret, selection, and context menu
- -> XREF: D01 T01 §1 -- the shell that hosts this surface; the hosting contract below is the interface it consumes

## Outcome

- Typing, caret movement, selection, clipboard, and undo/redo match Notepad key for key.
- Zoom and word wrap behave as Notepad's, with the choice persisted through the settings store.
- The surface exposes one interface the shell hosts; AI edits later go through the same interface.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (print lives in D01 T02 §5); settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (undo history is not an audit trail); exchange=not-applicable (clipboard is platform behavior, not an import/export surface); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Font, wrap, and zoom settings are consumed from the D01 store, never stored locally; undo/redo is the reversal.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Hosting contract with the shell | D01 T01 §1 |  [ ]   |
|   2   |   §2    | Text buffer and caret model | §1 |  [ ]   |
|   3   |   §3    | Rendering, selection, clipboard | §2 |  [ ]   |
|   4   |   §4    | Undo and redo | §2 |  [ ]   |
|   5   |   §5    | Zoom and word wrap | §3 |  [ ]   |
|   6   |   §6    | Context menu and mouse behaviors | §3 |  [ ]   |
|   7   |   §7    | Large-file behavior and budget | §2 |  [ ]   |

---

## 1. Hosting Contract with the Shell

Why this section exists: the shell and the surface evolve separately, so their boundary is a contract settled once, in writing, before either side leans on it.

- [ ] `src/Editor/IEditorSurface.h` defines the interface: set/get text, caret, selection, dirty events, undo/redo, find hooks. Done when: the shell compiles against the interface alone.
- [ ] Lifetime and threading rules are recorded: who owns the buffer, which thread edits, how the shell observes. Done when: the rules are written and the placeholder honors them.
- [ ] The placeholder surface implements the interface so the shell runs end to end before the real surface lands. Done when: the app runs with the placeholder and all shell tests pass.
- [ ] AI edits are declared as future consumers of this same interface, never as a second edit path. Done when: the declaration is recorded here.
- [ ] Commit: `"editor: settle the shell hosting contract"`

**Test checkpoint:** Shell tests green against the placeholder; an interface-conformance test fails if any method is unimplemented. Cheaper substitute that fails: the shell reaching into surface internals.

## 2. Text Buffer and Caret Model

Why this section exists: the buffer is the source of truth for every character. Correctness here is correctness everywhere.

- [ ] `src/Editor/TextBuffer.cpp` models the document with Notepad's line and encoding semantics. Done when: the caret-math fixtures pass.
- [ ] Caret movement (arrows, word jump, line ends, page, document ends) matches Notepad key for key. Done when: the movement fixtures pass.
- [ ] Selection (keyboard, shift-extend, select-all) matches Notepad. Done when: the selection fixtures pass.
- [ ] Surrogate pairs, combining characters, and tab stops behave as Notepad's. Done when: the edge-case fixtures pass.
- [ ] Commit: `"editor: add the text buffer and caret model"`

**Test checkpoint:** `ctest -R TextBuffer` green across movement, selection, and edge-case fixtures. Cheaper substitute that fails: caret math that works on ASCII and breaks on real text.

## 3. Rendering, Selection, Clipboard

Why this section exists: the surface must look and select like Notepad, and the clipboard must round-trip through the platform.

**Fidelity:** Notepad editor area -- `resources/baseline/editor/`. Font rendering, caret shape, selection color, and margins match the capture.

**Job:** The user can see and select text as in Notepad. Consumer: the shell, which hosts the surface; the clipboard, which receives cuts and copies.

**Treatment:** WinUI text rendering with Notepad's metrics. Cheaper substitute that fails the checkpoint: a plain text box with default metrics.

**Chrome:** Consume the shared editor styles. Do not invent a second text treatment.

- [ ] `src/Editor/EditorSurface.xaml` renders the §2 buffer with the Notepad font, caret, and selection. Done when: the capture comparison passes.
- [ ] Cut, copy, paste, and paste-as-behavior match Notepad including formats offered. Done when: clipboard round-trips are driven.
- [ ] Drag-select, double-click word, triple-click line match Notepad. Done when: each gesture is driven.
- [ ] IME and accessibility (narrator, keyboard-only use) behave as Notepad's. Done when: the accessibility checks pass.
- [ ] Commit: `"editor: render the surface with selection and clipboard"`

**Test checkpoint:** Capture comparison passes; clipboard round-trips driven; gestures driven; accessibility checks pass. Cheaper substitute that fails: rendering asserted without comparing to the capture.

## 4. Undo and Redo

Why this section exists: undo is the user's memory. Its grouping and limits must match Notepad's, or trust in the surface breaks.

- [ ] `src/Editor/UndoStack.cpp` groups edits as Notepad groups them (typing bursts, single operations). Done when: the grouping fixtures pass.
- [ ] Undo and redo limits, and the dirty-flag interaction (undo-to-clean clears dirty), match Notepad. Done when: the fixtures pass.
- [ ] Undo across save boundaries behaves as Notepad's. Done when: the save-interaction fixtures pass.
- [ ] Redo clears exactly when Notepad clears it. Done when: the fixtures pass.
- [ ] Commit: `"editor: add undo and redo"`

**Test checkpoint:** `ctest -R UndoStack` green across grouping, dirty, save, and redo-clear fixtures. Cheaper substitute that fails: per-keystroke undo that technically works and feels nothing like Notepad.

## 5. Zoom and Word Wrap

Why this section exists: zoom and wrap are small, visible, and easy to get subtly wrong. Match Notepad exactly, including persistence.

**Fidelity:** Notepad zoom and wrap behaviors -- `resources/baseline/editor/`. Zoom levels, wrap toggle placement, and status-bar readout match.

**Job:** The user can zoom and toggle wrap as in Notepad. Consumer: the settings store, which persists the choice.

**Treatment:** Notepad's zoom steps and wrap toggle. Cheaper substitute that fails the checkpoint: continuous zoom with different steps.

**Chrome:** Consume the shared editor styles. Do not invent a second zoom treatment.

- [ ] Zoom steps, shortcuts, and limits match Notepad; the level persists through the settings store. Done when: each step is driven and persistence proven.
- [ ] Word wrap toggles per Notepad with the choice persisted; wrapped and unwrapped caret math both hold. Done when: the wrap fixtures pass.
- [ ] The status bar zoom readout stays in sync (with `D01 T02 §4`). Done when: the sync is driven.
- [ ] Commit: `"editor: match zoom and word wrap"`

**Test checkpoint:** Steps, shortcuts, persistence, and wrap math all driven; capture comparison passes. Cheaper substitute that fails: zoom that works but with different steps than Notepad.

## 6. Context Menu and Mouse Behaviors

Why this section exists: right-click is a surface too. The context menu must carry Notepad's items in Notepad's order, all working.

**Fidelity:** Notepad editor context menu -- `resources/baseline/editor-context/`. Items, order, separators, and enablement match.

**Job:** The user can cut, copy, paste, and select through right-click. Consumer: the same handlers the keyboard and main menu use.

**Treatment:** Native context menu with Notepad's items. Cheaper substitute that fails the checkpoint: a context menu with a subset of items.

**Chrome:** Consume the shared menu styles. Do not invent a second context treatment.

- [ ] The context menu carries Notepad's items in order with correct enablement. Done when: the capture comparison passes item by item.
- [ ] Each item routes to the same handler as its menu/shortcut twin. Done when: no handler exists twice.
- [ ] Mouse behaviors (right-click caret placement, selection drag) match Notepad. Done when: each is driven.
- [ ] Commit: `"editor: match the context menu and mouse behaviors"`

**Test checkpoint:** Capture comparison item by item; shared-handler check passes; mouse behaviors driven. Cheaper substitute that fails: context items with their own duplicate handlers.

## 7. Large-File Behavior and Budget

Why this section exists: Notepad opens big files without dying. Our surface commits to a budget and degrades honestly past it.

- [ ] `docs/large-file-budget.md` records the size budget and the expected behavior at and past it (measured, not guessed). Done when: the numbers come from runs.
- [ ] Typing latency at the budget size stays within the committed bound. Done when: the perf test measures it in CI.
- [ ] Past the budget the app degrades honestly (a notice, read-only mode, or chunked load) rather than hanging. Done when: the degradation is driven.
- [ ] Memory use at the budget size stays within the committed bound. Done when: the perf test measures it in CI.
- [ ] Commit: `"editor: commit the large-file budget"`

**Test checkpoint:** Perf tests measure latency and memory in CI; degradation driven. Cheaper substitute that fails: a budget nobody measures.

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Caret, selection, undo, and clipboard fixtures all green
- [ ] `python3 scripts/todo-graph.py validate` clean
