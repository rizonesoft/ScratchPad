---
schema_version: 1
id: find-replace-goto
domain: 02-editor
status: draft
title: "TODO-02 -- Find, Replace and Go To"
depends_on: ["editing-surface"]
track: N2
---

# TODO-02 -- Find, Replace and Go To

> **Goal:** The Notepad find/replace bar and go-to-line dialog, behaving exactly as Notepad's down to match counting and wrap-around.

> [!IMPORTANT]
> **Current state:** No find UI and no search engine. The `D02 T01` surface owns the buffer and caret this file searches through.

## Inputs

- `resources/baseline/` captures of the find bar, replace mode, and go-to dialog
- [`02-editor/TODO-01-editing-surface.md`](./TODO-01-editing-surface.md) -- the buffer and caret model being searched

## Outcome

- Find, find next/previous, replace, and replace-all match Notepad including options and counts.
- Go-to-line lands on the right line with Notepad's validation and errors.
- Search never mutates the buffer except through replace, which is undoable.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Find options persist through the D01 store; replace is undone through the D02 undo stack.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Search engine over the buffer | D02 T01 §2 |  [ ]   |
|   2   |   §2    | Find bar UI | §1 |  [ ]   |
|   3   |   §3    | Replace mode | §2 |  [ ]   |
|   4   |   §4    | Go-to-line dialog | D02 T01 §2 |  [ ]   |
|   5   |   §5    | Options persistence and edge cases | §2, §4 |  [ ]   |

---

## 1. Search Engine over the Buffer

Why this section exists: the UI is thin; the engine carries the semantics. Case, whole-word, direction, wrap, and counting are settled and tested here.

**Groomed 2026-09-13:** Notepad audit: the wrap scope rule and the absent direction control are now explicit.

- [ ] `src/Editor/SearchEngine.cpp` finds matches with Notepad's options: case, whole word, direction, wrap-around. Done when: the option-matrix fixtures pass.
- [ ] Match counting matches Notepad's count exactly on the fixture corpus. Done when: every count agrees.
- [ ] Zero-length and regex-free semantics match Notepad (no regex unless Notepad has it). Done when: the behavior is recorded and tested.
- [ ] The engine never mutates the buffer; replace goes through the undoable edit path. Done when: a mutation probe test passes.
- [ ] Search scope follows Notepad: with wrap around off the search runs cursor-to-end only, with wrap around on it covers the whole file; there is no Up/Down direction control in the current bar. Done when: the scope fixtures pass. Source: https://www.howtogeek.com/359042/everything-new-in-notepad-in-windows-10-redstone-5/
- [ ] Commit: `"editor: add the search engine"`

**Test checkpoint:** `ctest -R SearchEngine` green across the option matrix and counts; mutation probe passes. Cheaper substitute that fails: search tested only through the UI with three cases.

## 2. Find Bar UI

Why this section exists: the find bar is the surface users touch. It must place, behave, and count like Notepad's.

**Fidelity:** Notepad find bar -- `resources/baseline/find-bar/`. Placement, options, match counter, and keyboard flow match the capture.

**Job:** The user can find text as in Notepad. Consumer: the caret, which lands on the match.

**Treatment:** WinUI bar with Notepad's layout and flow. Cheaper substitute that fails the checkpoint: a dialog standing in for the bar.

**Chrome:** Consume the shared bar styles. Do not invent a second find treatment.

**Groomed 2026-09-13:** Notepad audit: the exact exposed option set, F3/Shift+F3, and within-session memory with autofill are now explicit.

- [ ] `src/Editor/FindBar.xaml` binds to the §1 engine with Notepad's options and counter. Done when: the capture comparison passes.
- [ ] Enter, Shift+Enter, Escape, and option toggles flow as Notepad's. Done when: the keyboard flow is driven.
- [ ] No-match and wrap-around feedback match Notepad's. Done when: both are driven.
- [ ] The bar exposes exactly Match case and Wrap around under More options; no whole-word toggle and no Up/Down direction radio appear. Done when: the capture comparison confirms the set. Source: https://www.anoopcnair.com/latest-features-of-notepad-in-windows-11/
- [ ] F3 finds next and Shift+F3 finds previous through the bar. Done when: both keys are driven.
- [ ] The bar remembers entered values and option states across openings within the session, and opening it with a selection autofills the search field. Done when: memory and autofill are driven. Source: https://blogs.windows.com/windows-insider/2018/07/11/announcing-windows-10-insider-preview-build-17713/
- [ ] Commit: `"editor: build the find bar"`

**Test checkpoint:** UI drive walks find, next/previous, options, no-match, and wrap; capture comparison passes. Cheaper substitute that fails: the bar tested without the counter.

## 3. Replace Mode

Why this section exists: replace mutates through undo. The mode must match Notepad's replace, replace-all, and count reporting.

**Fidelity:** Notepad replace mode -- `resources/baseline/find-bar/`. Layout and count reporting match the capture.

**Job:** The user can replace text as in Notepad. Consumer: the buffer, through the undoable edit path, and the caret.

**Treatment:** Replace mode of the find bar per the capture. Cheaper substitute that fails the checkpoint: replace-all that skips the count.

**Chrome:** Consume the shared bar styles. Do not invent a second replace treatment.

- [ ] Replace and replace-all honor the §1 options and report Notepad's count. Done when: the count fixtures pass.
- [ ] Every replace is one undo unit per Notepad's grouping. Done when: undo-after-replace fixtures pass.
- [ ] Replace-all across a dirty buffer keeps dirty semantics exact. Done when: the dirty fixtures pass.
- [ ] Commit: `"editor: add replace mode"`

**Test checkpoint:** Replace and replace-all driven with counts; undo grouping proven. Cheaper substitute that fails: replace that bypasses undo.

## 4. Go-to-Line Dialog

Why this section exists: small surface, exact behavior. Validation, errors, and landing must match Notepad's.

**Fidelity:** Notepad go-to dialog -- `resources/baseline/goto/`. Layout, validation, and error text match the capture.

**Job:** The user can jump to a line as in Notepad. Consumer: the caret, which lands on the line.

**Treatment:** Dialog per the capture. Cheaper substitute that fails the checkpoint: silently clamping bad input.

**Chrome:** Consume the shared dialog styles. Do not invent a second dialog treatment.

- [ ] `src/Editor/GoToDialog.xaml` validates with Notepad's errors (non-numeric, out of range, wrap-mode restriction). Done when: each error is driven.
- [ ] Valid input lands the caret exactly (line, column rules as Notepad's). Done when: the landing fixtures pass.
- [ ] The dialog remembers nothing it should not and persists nothing. Done when: the behavior is recorded and tested.
- [ ] Commit: `"editor: add go-to-line"`

**Test checkpoint:** Errors and landings driven; capture comparison passes. Cheaper substitute that fails: validation that clamps instead of reporting.

## 5. Options Persistence and Edge Cases

Why this section exists: find options persist across sessions in Notepad, and the edge cases (huge files, huge match counts) must not hang the bar.

- [ ] Find options persist through the settings store with Notepad's scope. Done when: quit and relaunch keeps them.
- [ ] Huge match counts render and perform within the committed budget. Done when: the perf test measures it.
- [ ] Search in a dirty, wrapped, or zoomed buffer behaves identically. Done when: the combination fixtures pass.
- [ ] Commit: `"editor: persist find options and cover edge cases"`

**Test checkpoint:** Persistence driven; perf budget measured in CI; combination fixtures green. Cheaper substitute that fails: options kept in memory only.

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Option matrix, counts, and undo grouping all proven
- [ ] `python3 scripts/todo-graph.py validate` clean
