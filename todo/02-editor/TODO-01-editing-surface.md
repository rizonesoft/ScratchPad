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
|   8   |   §8    | Selection utilities: case, sort, dedupe | §2, §4, D01 T02 §1 |  [ ]   |
|   9   |   §9    | Synonym picker | §4, §6 |  [ ]   |
|  10   |   §10   | Readability heatmap | §2, §3 |  [ ]   |
|  11   |   §11   | Text utilities: format, encode, normalize, slugify, inspect, tables | §2, §4, D01 T02 §1 |  [ ]   |
|  12   |   §12   | Bookmarked lines | §2, D01 T01 §4, D01 T02 §1 |  [ ]   |
|  13   |   §13   | Column selection | §2, §3, §4 |  [ ]   |
|  14   |   §14   | Smart paste | §3 |  [ ]   |
|  15   |   §15   | Clickable URLs | §3, §6 |  [ ]   |
|  16   |   §16   | Split view | §1, §2, D01 T01 §1, D01 T01 §2 |  [ ]   |
|  17   |   §17   | Distraction-free focus mode | §3, D01 T01 §1, D01 T02 §1 |  [ ]   |
|  18   |   §18   | Copy as Markdown, HTML, plain text | §3, D01 T01 §18, D01 T02 §1 |  [ ]   |
|  19   |   §19   | Side-by-side tab diff | §2, §16, D01 T01 §2 |  [ ]   |

---

## 1. Hosting Contract with the Shell

Why this section exists: the shell and the surface evolve separately, so their boundary is a contract settled once, in writing, before either side leans on it.

- [ ] `src/Notepad.Core/IEditorSurface.cs` defines the interface: set/get text, caret, selection, dirty events, undo/redo, find hooks. Done when: the shell compiles against the interface alone.
- [ ] Lifetime and threading rules are recorded: who owns the buffer, which thread edits, how the shell observes. Done when: the rules are written and the placeholder honors them.
- [ ] The placeholder surface implements the interface so the shell runs end to end before the real surface lands. Done when: the app runs with the placeholder and all shell tests pass.
- [ ] AI edits are declared as future consumers of this same interface, never as a second edit path. Done when: the declaration is recorded here.
- [ ] Commit: `"editor: settle the shell hosting contract"`

**Test checkpoint:** Shell tests green against the placeholder; an interface-conformance test fails if any method is unimplemented. Cheaper substitute that fails: the shell reaching into surface internals.

## 2. Text Buffer and Caret Model

Why this section exists: the buffer is the source of truth for every character. Correctness here is correctness everywhere.

**Groomed 2026-09-13:** Notepad audit: word-kill, EOP rules, hex/bracket entry, and the Unicode-controls display mode are now explicit.

- [ ] `src/Notepad.Core/TextBuffer.cs` models the document with Notepad's line and encoding semantics. Done when: the caret-math fixtures pass.
- [ ] Caret movement (arrows, word jump, line ends, page, document ends) matches Notepad key for key. Done when: the movement fixtures pass.
- [ ] Selection (keyboard, shift-extend, select-all) matches Notepad. Done when: the selection fixtures pass.
- [ ] Surrogate pairs, combining characters, and tab stops behave as Notepad's. Done when: the edge-case fixtures pass.
- [ ] Ctrl+Backspace deletes the previous word as Notepad's. Done when: the deletion fixtures pass. Source: https://blogs.windows.com/windows-insider/2018/07/11/announcing-windows-10-insider-preview-build-17713/
- [ ] End-of-paragraph selection follows Notepad: mouse drag and Shift+End exclude the EOP character, Shift+RightArrow and next-line extension include it, matching what Delete removes; with wrap off the caret follows typed spaces. Done when: the EOP fixtures pass. Source: https://devblogs.microsoft.com/math-in-office/windows-11-notepad/
- [ ] Alt+X converts preceding hex into its Unicode character and Ctrl+} jumps between matching brackets, as Notepad's RichEdit engine does. Done when: both fixtures pass. Source: https://devblogs.microsoft.com/math-in-office/windows-11-notepad/
- [ ] The Unicode-controls display mode (menu entry in §6) renders bidi RLO/LRO and ZWJ as zero-width glyphs and splits ZWJ emoji sequences for arrow-key navigation and Alt+X inspection. Done when: the mode fixtures pass. Source: https://devblogs.microsoft.com/math-in-office/windows-11-notepad/
- [ ] Commit: `"editor: add the text buffer and caret model"`

**Test checkpoint:** `dotnet test --filter TextBuffer` green across movement, selection, and edge-case fixtures. Cheaper substitute that fails: caret math that works on ASCII and breaks on real text.

## 3. Rendering, Selection, Clipboard

Why this section exists: the surface must look and select like Notepad, and the clipboard must round-trip through the platform.

**Fidelity:** Notepad editor area -- `resources/baseline/editor/`. Font rendering, caret shape, selection color, and margins match the capture.

**Job:** The user can see and select text as in Notepad. Consumer: the shell, which hosts the surface; the clipboard, which receives cuts and copies.

**Treatment:** WinUI text rendering with Notepad's metrics. Cheaper substitute that fails the checkpoint: a plain text box with default metrics.

**Chrome:** Consume the shared editor styles. Do not invent a second text treatment.

**Groomed 2026-09-13:** Notepad audit: CF_TEXT-only paste, color emoji, text drag-drop, Ctrl+click paragraph, and spaceless double-click are now explicit.

- [ ] `src/Notepad/EditorSurface.xaml` renders the §2 buffer with the Notepad font, caret, and selection. Done when: the capture comparison passes.
- [ ] Cut, copy, paste, and paste-as-behavior match Notepad including formats offered. Done when: clipboard round-trips are driven. **Recorded 2026-09-16:** D01 T02 §1 ships Edit > Cut, Copy, Paste, Delete, and Select all disabled; this section enables all five through the `MenuCommands` registry and drives them on landing.
- [ ] Drag-select, double-click word, triple-click line match Notepad. Done when: each gesture is driven.
- [ ] IME and accessibility (narrator, keyboard-only use) behave as Notepad's. Done when: the accessibility checks pass.
- [ ] Paste accepts only CF_TEXT from the clipboard and strips all formatting, so every paste is effectively plain text. Done when: formatted-paste round-trips yield raw text. Source: https://en.wikipedia.org/wiki/Windows_Notepad
- [ ] Color emoji render through font fallback as Notepad's. Done when: the emoji fixtures pass against the capture. Source: https://devblogs.microsoft.com/math-in-office/windows-11-notepad/
- [ ] Dragging selected text moves or copies it per Notepad's modifiers, recorded from the capture. Done when: move and copy drags are driven.
- [ ] Ctrl+click selects the paragraph under the cursor. Done when: the gesture is driven. Source: https://techlasi.com/savvy/get-help-with-notepad-in-windows-complete-guide-for-2025/
- [ ] Double-click selects the word alone with no trailing space, as Win11 changed it. Done when: the gesture is driven. Source: https://www.anoopcnair.com/latest-features-of-notepad-in-windows-11/
- [ ] Commit: `"editor: render the surface with selection and clipboard"`

**Test checkpoint:** Capture comparison passes; clipboard round-trips driven; gestures driven; accessibility checks pass. Cheaper substitute that fails: rendering asserted without comparing to the capture.

## 4. Undo and Redo

Why this section exists: undo is the user's memory. Its grouping and limits must match Notepad's, or trust in the surface breaks.

- [ ] `src/Notepad.Core/UndoStack.cs` groups edits as Notepad groups them (typing bursts, single operations). Done when: the grouping fixtures pass. **Recorded 2026-09-16:** D01 T02 §1 ships Edit > Undo disabled (stock has no Redo item); this section enables Undo through the `MenuCommands` registry and drives it on landing.
- [ ] Undo and redo limits, and the dirty-flag interaction (undo-to-clean clears dirty), match Notepad. Done when: the fixtures pass.
- [ ] Undo across save boundaries behaves as Notepad's. Done when: the save-interaction fixtures pass.
- [ ] Redo clears exactly when Notepad clears it. Done when: the fixtures pass.
- [ ] Commit: `"editor: add undo and redo"`

**Test checkpoint:** `dotnet test --filter UndoStack` green across grouping, dirty, save, and redo-clear fixtures. Cheaper substitute that fails: per-keystroke undo that technically works and feels nothing like Notepad.

## 5. Zoom and Word Wrap

Why this section exists: zoom and wrap are small, visible, and easy to get subtly wrong. Match Notepad exactly, including persistence.

**Fidelity:** Notepad zoom and wrap behaviors -- `resources/baseline/editor/`. Zoom levels, wrap toggle placement, and status-bar readout match.

**Job:** The user can zoom and toggle wrap as in Notepad. Consumer: the settings store, which persists the choice.

**Treatment:** Notepad's zoom steps and wrap toggle. Cheaper substitute that fails the checkpoint: continuous zoom with different steps.

**Chrome:** Consume the shared editor styles. Do not invent a second zoom treatment.

**Groomed 2026-09-13:** Notepad audit: exact zoom keys, the wrap-on line/column rule, and the F5 time/date insert are now explicit.

- [ ] Zoom steps, shortcuts, and limits match Notepad; the level persists through the settings store. Done when: each step is driven and persistence proven.
- [ ] Word wrap toggles per Notepad with the choice persisted; wrapped and unwrapped caret math both hold. Done when: the wrap fixtures pass.
- [ ] The status bar zoom readout stays in sync (with `D01 T02 §4`). Done when: the sync is driven.
- [ ] Zoom keys are exactly Ctrl+Plus, Ctrl+Minus, Ctrl+0 for 100%, and Ctrl+mouse-wheel. Done when: each key is driven. **Recorded 2026-09-16:** D01 T02 §1 ships View > Zoom in, Zoom out, Restore default zoom, and Word wrap disabled; this section enables all four through the `MenuCommands` registry and drives them on landing.
- [ ] The line/column readout with wrap on follows Notepad's logical-versus-visual rule recorded from the capture. Done when: the wrap-on fixtures pass.
- [ ] F5 inserts the current time and date at the caret; the exact format is recorded from the capture. Done when: the insert is driven and matches the capture. Source: https://www.anoopcnair.com/latest-features-of-notepad-in-windows-11/ **Recorded 2026-09-16:** D01 T02 §1 ships Edit > Time/Date disabled; this section enables it through the `MenuCommands` registry and drives the shared insert on landing.
- [ ] Commit: `"editor: match zoom and word wrap"`

**Test checkpoint:** Steps, shortcuts, persistence, and wrap math all driven; capture comparison passes. Cheaper substitute that fails: zoom that works but with different steps than Notepad.

## 6. Context Menu and Mouse Behaviors

Why this section exists: right-click is a surface too. The context menu must carry Notepad's items in Notepad's order, all working.

**Fidelity:** Notepad editor context menu -- `resources/baseline/editor-context/`. Items, order, separators, and enablement match.

**Job:** The user can cut, copy, paste, and select through right-click. Consumer: the same handlers the keyboard and main menu use.

**Treatment:** Native context menu with Notepad's items. Cheaper substitute that fails the checkpoint: a context menu with a subset of items.

**Chrome:** Consume the shared menu styles. Do not invent a second context treatment.

**Groomed 2026-09-13:** Notepad audit: the compact layout specifics with AI, Spelling, and Unicode-controls routing are now explicit.

- [ ] The context menu carries Notepad's items in order with correct enablement. Done when: the capture comparison passes item by item.
- [ ] Each item routes to the same handler as its menu/shortcut twin. Done when: no handler exists twice.
- [ ] Mouse behaviors (right-click caret placement, selection drag) match Notepad. Done when: each is driven.
- [ ] The menu matches Notepad's compact layout as captured: the icon row (Cut, Copy, Paste, Select all, Undo, Delete), then Define with Bing, the AI entries routed to D05 T02 §6, Spelling routed to D02 T03 §2 and D02 T03 §4, and the Unicode-controls entry routed to §2. Done when: the capture comparison passes item by item. Source: https://www.windowslatest.com/2025/08/16/windows-11-cluttered-notepads-right-click-menu-but-its-now-getting-file-explorer-like-ui-as-a-fix/
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

## 8. Selection Utilities: Case, Sort, Dedupe

Why this section exists: selections get reshaped constantly: case fixed, lines sorted, duplicates dropped. Each transform lands as one undo unit.

**Fidelity:** new build, no baseline (stock Notepad transforms nothing).

**Job:** The user can transform the selection in place. Consumer: the undoable edit path (§4), which groups each transform.

**Treatment:** Edit-menu entries with shortcuts; each transform one undo unit through §4. Cheaper substitute that fails the checkpoint: transforms that bypass undo.

**Chrome:** Consume the shared menu styles. Do not invent a second utility treatment.

**Needs:** Windows host (build/test)

- [ ] Case conversion (upper, lower, title, sentence) transforms the selection. Done when: each mode is driven on fixtures.
- [ ] Sort lines orders the selected lines. Done when: ascending and descending both driven.
- [ ] Dedupe drops repeated lines keeping the first. Done when: the dedupe fixtures pass.
- [ ] Each transform lands as exactly one undo unit through §4. Done when: one undo reverses each transform.
- [ ] Edit-menu entries with shortcuts expose all three through D01 T02 §1. Done when: the audit names them.
- [ ] Commit: `"editor: add selection utilities"`

**Test checkpoint:** transforms, undo grouping, and menu exposure are all driven in the room. Cheaper substitute that fails: sort that scrambles blank lines.

## 9. Synonym Picker

Why this section exists: the current word, better options, one click, one undo unit, no network.

**Fidelity:** new build, no baseline (stock Notepad suggests nothing).

**Job:** The user can pick a synonym for the word at the caret. Consumer: the undoable edit path (§4), which groups the swap; the context menu (§6), which offers it.

**Treatment:** Offline open word list shipped with the app; the picker shows options for the current word and applies the pick as one undo unit. Cheaper substitute that fails the checkpoint: an online thesaurus call.

**Chrome:** Consume the shared menu styles. Do not invent a second picker treatment.

**Needs:** Windows host (build/test)

- [ ] An offline open word list ships with the app. Done when: the license and coverage are recorded.
- [ ] The picker offers synonyms for the word at the caret. Done when: driven with fixtures.
- [ ] The pick applies as exactly one undo unit through §4. Done when: one undo reverses the swap.
- [ ] The context menu offers the picker through §6. Done when: the menu path is driven.
- [ ] Commit: `"editor: pick synonyms offline"`

**Test checkpoint:** word list, picker, undo grouping, and menu path are all driven in the room. Cheaper substitute that fails: synonyms that phone home.

## 10. Readability Heatmap

Why this section exists: long sentences shade darker so dense paragraphs show at a glance.

**Fidelity:** new build, no baseline (stock Notepad shades nothing).

**Job:** The user can see density at a glance. Consumer: the renderer (§3), which shades per sentence; the buffer (§2), which supplies sentences.

**Treatment:** Sentence-length shading over the text; darker means longer; a single command shows and hides the overlay. Cheaper substitute that fails the checkpoint: a readability score with no map.

**Chrome:** Consume the shared editor styles. Do not invent a second shade treatment.

**Needs:** Windows host (build/test)

- [ ] Sentences shade by length under host drive. Done when: captures show the gradient.
- [ ] The overlay shows and hides on one command. Done when: both are driven.
- [ ] Shading never alters the buffer. Done when: content fixtures prove display-only.
- [ ] Commit: `"editor: map readability as heat"`

**Test checkpoint:** shading, command, and display-only are all driven in the room. Cheaper substitute that fails: heat that edits.

## 11. Text Utilities: Format, Encode, Normalize, Slugify, Inspect, Tables

Why this section exists: the TextFX drawer: six small tools on the selection or caret, each one undo unit where it edits.

**Fidelity:** new build, no baseline (stock Notepad transforms nothing).

**Job:** The user can reshape text without leaving the app. Consumer: the undoable edit path (§4), which groups each edit.

**Treatment:** Menu commands over the selection or caret: JSON/XML format, base64/URL/HTML codec, whitespace normalization, slugify, Unicode inspector, Markdown table alignment. Cheaper substitute that fails the checkpoint: tools that bypass undo.

**Chrome:** Consume the shared menu styles; the inspector shows in a surface-owned popup. Do not invent a second utility treatment.

**Needs:** Windows host (build/test)

- [ ] JSON and XML pretty print plus minify run on the selection. Done when: all four are driven on fixtures.
- [ ] Base64, URL, and HTML-entity encode and decode run on the selection. Done when: round-trips pass.
- [ ] Whitespace normalization (trailing spaces, blank runs, mixed tabs) runs one command each. Done when: each is driven.
- [ ] Slugify turns the selection into a URL slug. Done when: fixtures match.
- [ ] The Unicode inspector shows codepoint, name, and UTF-8 bytes for the caret character. Done when: driven, including astral-plane characters.
- [ ] The Markdown table formatter aligns the pipes. Done when: ragged fixtures align exactly.
- [ ] Each editing tool lands as one undo unit through §4. Done when: one undo reverses each.
- [ ] Menu entries with shortcuts expose all six through D01 T02 §1. Done when: the audit names them.
- [ ] Commit: `"editor: add the text utility drawer"`

**Test checkpoint:** all six tools, undo grouping, and menu exposure are all driven in the room. Cheaper substitute that fails: a drawer with one tool.

## 12. Bookmarked Lines

Why this section exists: marked lines with next/previous jumps that persist per file, gutter-free.

**Fidelity:** new build, no baseline (stock Notepad marks nothing).

**Job:** The user can mark lines and jump between them across restarts. Consumer: the buffer (§2), which maps lines; the menu (D01 T02 §1), which lists them.

**Treatment:** Toggle-bookmark per line with next/previous jumps; a menu lists the file's marks; marks track their lines across edits and persist per file path. Cheaper substitute that fails the checkpoint: marks that forget.

**Chrome:** Consume the shared menu styles. Do not invent a second mark treatment.

**Needs:** Windows host (build/test)

- [ ] Toggle, next, and previous jumps work and marks track their lines across edits. Done when: each is driven.
- [ ] A menu lists the file's bookmarks and jumps on click. Done when: the list matches the marks.
- [ ] Marks persist per file path across restarts. Done when: relaunch keeps them.
- [ ] Untitled (pathless) files hold marks for the session only. Done when: the session rule is driven.
- [ ] Commit: `"editor: bookmark lines"`

**Test checkpoint:** jumps, menu list, persistence, and the untitled rule are all driven in the room. Cheaper substitute that fails: bookmarks by line number that never adjust.

## 13. Column Selection

Why this section exists: Alt+drag selects a rectangle for tabular text. Columns cut, copy, paste, and type as one.

**Fidelity:** new build, no baseline (stock Notepad selects no columns).

**Job:** The user can edit text in columns. Consumer: the caret model (§2), which carries the rectangle; the renderer (§3), which paints it.

**Treatment:** Alt+drag anchors a rectangular selection; edits apply per line; ragged lines pad with spaces. Cheaper substitute that fails the checkpoint: a rectangle that pastes as one line.

**Chrome:** Consume the shared selection styles. Do not invent a second block treatment.

**Needs:** Windows host (build/test)

- [ ] Alt+drag anchors a rectangular selection. Done when: the drag path is driven.
- [ ] Cut, copy, paste, and typing apply per line. Done when: each is driven on fixtures.
- [ ] Ragged lines pad with spaces. Done when: the padding fixtures pass.
- [ ] One undo reverses a column edit through §4. Done when: grouping is driven.
- [ ] Commit: `"editor: select columns"`

**Test checkpoint:** rectangle, per-line edits, padding, and undo grouping are all driven in the room. Cheaper substitute that fails: columns that flatten.

## 14. Smart Paste

Why this section exists: a pasted URL becomes a titled link, pasted code becomes a fenced block, plain text stays plain. Uncertainty always resolves to plain.

**Fidelity:** new build, no baseline (stock Notepad pastes bytes).

**Job:** The user can paste rich text without reformatting. Consumer: the paste path (§3), which classifies before inserting.

**Treatment:** Classify the clipboard: URL-shaped becomes a titled Markdown link (title fetched with a timeout, URL-as-text on failure); code-shaped per the recorded heuristic becomes a fenced block; everything uncertain pastes plain. The fence heuristic is paste-scoped: it creates no highlighting, gutter, or code surface. Cheaper substitute that fails the checkpoint: guessing that mangles plain text.

**Chrome:** No new surface; the pasted text is the surface.

**Needs:** Windows host (build/test)

- [ ] A pasted URL becomes a titled Markdown link. Done when: driven with a fetched title.
- [ ] Title fetch times out to URL-as-text with no hang. Done when: the slow-network path is driven.
- [ ] Code-shaped pastes become fenced blocks per the recorded heuristic. Done when: fixtures pass and the heuristic is recorded.
- [ ] Uncertain pastes stay plain. Done when: the negative fixtures pass.
- [ ] Commit: `"editor: paste smart"`

**Test checkpoint:** link, fetch fallback, fence, and fail-plain are all driven in the room. Cheaper substitute that fails: paste that rewrites what you copied.

## 15. Clickable URLs

Why this section exists: URLs in the text are interactive: detected, styled, hoverable, and opened on Ctrl+click. Plain click still places the caret.

**Fidelity:** new build, no baseline (stock Notepad links nothing).

**Job:** The user can open URLs without leaving the app. Consumer: the renderer (§3), which styles and hit-tests; the mouse path (§6), which clicks.

**Treatment:** URL detection over the buffer with link styling; hover shows the pointer and the target; Ctrl+click opens through the OS shell; schemes recorded here (http/https by default). Cheaper substitute that fails the checkpoint: single-click open that steals caret placement.

**Chrome:** Consume the shared editor styles. Do not invent a second link treatment.

**Needs:** Windows host (build/test)

- [ ] URLs detect and style under host drive. Done when: fixtures cover bare, wrapped, and trailing-punctuation URLs.
- [ ] Hover shows the pointer and the target URL. Done when: the hover path is driven.
- [ ] Ctrl+click opens the URL through the OS shell. Done when: the open path is driven.
- [ ] Plain click still places the caret on a link. Done when: caret placement on links is driven.
- [ ] Commit: `"editor: link the URLs"`

**Test checkpoint:** detection, hover, open, and caret preservation are all driven in the room. Cheaper substitute that fails: links that open on any click.

## 16. Split View

Why this section exists: writers compare passages and work two notes at once. Stock Notepad shows one pane, so this is beyond parity: two fully live panes in one window. Moved here from D01 T01 §12 by phase-1 run 2 (cycle repair: split needs live views).

**Fidelity:** new build, no baseline (stock Notepad shows one pane).

**Job:** The user can view and edit two panes side by side. Consumer: the shell layout, which hosts both panes through the same surface contract.

**Treatment:** A splitter divides the editor area into two independent panes; the keyboard moves focus between them. Cheaper substitute that fails the checkpoint: a second window instead of a real split.

**Chrome:** Consume the shared shell styles. Do not invent a second pane treatment.

**Needs:** Windows host (build/test)

- [ ] Split one file into two views on the same buffer, edits visible in both. Done when: typing in one pane appears in the other under host drive.
- [ ] Split two different files side by side. Done when: each pane shows its file with independent dirty state.
- [ ] Panes scroll and edit independently under host drive. Done when: scroll position and caret do not leak across panes.
- [ ] Keyboard focus moves between panes and is announced. Done when: the shortcut moves focus both ways with UIA announcement.
- [ ] Commit: `"editor: split the view"`

**Test checkpoint:** splits on one buffer and two files, independence, and focus moves are all driven in the room. Cheaper substitute that fails: panes sharing one caret.

## 17. Distraction-Free Focus Mode

Why this section exists: chrome fades, the current paragraph stays lit, exit restores exactly. Moved here from D01 T01 §15 by phase-1 run 2 (cycle repair: paragraph emphasis needs the rendered surface).

**Fidelity:** new build, no baseline (stock Notepad has no focus mode).

**Job:** The user can write with the chrome faded. Consumer: the shell, which fades and restores.

**Treatment:** Shortcut plus View-menu entry enter and exit; the current paragraph stays lit. Cheaper substitute that fails the checkpoint: fullscreen without the fade.

**Chrome:** Consume the shared shell styles. Do not invent a second fade treatment.

**Needs:** Windows host (build/test)

- [ ] Focus mode enters and exits under host drive. Done when: chrome fades on entry and restores exactly on exit.
- [ ] The current paragraph stays lit while the rest dims. Done when: captures show the emphasis.
- [ ] Exit restores the exact prior layout. Done when: pane, panel, and bar states match pre-entry.
- [ ] Commit: `"editor: fade the chrome"`

**Test checkpoint:** entry, emphasis, and exact restore are all driven in the room. Cheaper substitute that fails: a mode that strands the user.

## 18. Copy as Markdown, HTML, Plain Text

Why this section exists: copy-as puts Markdown, HTML, or plain text on the clipboard from any view. Split from D01 T01 §18 by phase-1 run 2 (cycle repair: conversion needs buffer content; export stays there, copy-as lives here).

**Fidelity:** new build, no baseline (stock Notepad converts nothing).

**Job:** The user can copy the buffer across formats. Consumer: the clipboard (§3), which receives the converted text; the converter (D01 T01 §18), which renders the formats.

**Treatment:** Copy-as submenu with faithful conversion through the shared converter. Cheaper substitute that fails the checkpoint: plain-text-only bytes under new labels.

**Chrome:** Consume the shared menu styles. Do not invent a second convert treatment.

**Needs:** Windows host (build/test)

- [ ] Copy-as places Markdown, HTML, and plain text on the clipboard. Done when: all three formats paste correctly.
- [ ] Menu entries with shortcuts expose copy-as through D01 T02 §1. Done when: the audit names them.
- [ ] Clipboard carries both the format and plain-text fallback. Done when: pasting into plain and rich targets both work.
- [ ] Commit: `"editor: copy across formats"`

**Test checkpoint:** copy, menu, and formats are all driven in the room. Cheaper substitute that fails: HTML that drops structure.

## 19. Side-by-Side Tab Diff

Why this section exists: two tabs, side by side, word-level change marks. Review lives in the app, paired with the D02 T01 §16 split. Moved here from D01 T01 §23 by phase-1 run 2 (cycle repair: diff needs buffer content).

**Fidelity:** new build, no baseline (stock Notepad diffs nothing).

**Job:** The user can compare two tabs word by word. Consumer: the split panes (D02 T01 §16), which host the pair.

**Treatment:** Pick any two open tabs; they open paired in a D02 T01 §16 split with word-level change marks; the marks are display-only. Cheaper substitute that fails the checkpoint: line hashes with no word marks.

**Chrome:** Consume the shared pane styles. Do not invent a second diff treatment.

**Needs:** Windows host (build/test)

- [ ] Any two open tabs pair into a diff. Done when: the pair path is driven.
- [ ] Word-level change marks render on both sides. Done when: fixtures match exactly.
- [ ] The pair hosts in a D02 T01 §16 split. Done when: panes show the pair under host drive.
- [ ] Marks are display-only; editing either side re-marks live. Done when: re-marking is driven.
- [ ] Commit: `"editor: diff two tabs"`

**Test checkpoint:** pairing, word marks, split hosting, and live re-mark are all driven in the room. Cheaper substitute that fails: a diff of screenshots.

## Verification

- [ ] `dotnet test` green
- [ ] Caret, selection, undo, and clipboard fixtures all green
- [ ] `python3 scripts/todo-graph.py validate` clean
