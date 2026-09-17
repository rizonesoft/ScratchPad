---
schema_version: 1
id: spellcheck-autocorrect
domain: 02-editor
status: draft
title: "TODO-03 -- Spellcheck and Autocorrect"
depends_on: ["editing-surface"]
track: N2
---

# TODO-03 -- Spellcheck and Autocorrect

> **Goal:** Notepad's spelling behavior exactly: red squiggles with suggestions, autocorrect for common mistakes, and per-file-type toggles in settings.

> [!IMPORTANT]
> **Current state:** No spelling exists. The `D02 T01` buffer and caret model carry the text this file checks; the `D01 T02 §2` store carries the toggles. Filed by groom 2026-09-14 from the Notepad surface research: spellcheck and autocorrect shipped to all Windows 11 users with per-file-type settings.

## Inputs

- Microsoft's Notepad spellcheck announcement (red squiggle, click for suggestions, per-file-type toggles for txt/md/srt/ass/lrc/lic and more)
- [`02-editor/TODO-01-editing-surface.md`](./TODO-01-editing-surface.md) -- the buffer being checked
- [`01-notepad-core/TODO-02-menus-settings-status.md`](../01-notepad-core/TODO-02-menus-settings-status.md) -- §2 owns the toggles
- -> XREF: D02 T05 §2 -- the grammar underlines mirror §2's card treatment; no behavior deferred either way

## Outcome

- Misspelled words underline in red with suggestions on click, as Notepad's.
- Autocorrect fixes common mistakes as Notepad does, and can be disabled.
- Both are toggleable globally and per file type through the settings store.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Spelling toggles live in the D01 store with their consumer named there; autocorrect changes undo through the D02 stack.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Spellcheck engine over the buffer | D02 T01 §2 |  [ ]   |
|   2   |   §2    | Squiggles and suggestions UI | §1 |  [ ]   |
|   3   |   §3    | Autocorrect | §1 |  [ ]   |
|   4   |   §4    | Global and per-file-type toggles | §2, §3, D01 T02 §2 |  [ ]   |

---

## 1. Spellcheck Engine over the Buffer

Why this section exists: the UI is thin; the engine carries the semantics. Language, word breaking, and suggestion ranking are settled and tested here.

**Decided 2026-09-14:** Nuspell (LGPL, Hunspell-dictionary-compatible) behind the engine: the best maintained open-source spellchecker, with every locale's LibreOffice/Mozilla dictionaries reusable. Embedded via a C-ABI interop layer; corpus agreement with Notepad stays the acceptance. Alternative recorded: the Windows platform spellchecker (zero dependencies, exact-Notepad behavior, not open-source). Cost of changing engines: rewrite `src/Notepad.Core/SpellEngine.cs` plus dictionary shipping; fixtures stay.

- [ ] `src/Notepad.Core/SpellEngine.cs` checks the §-buffer in the system language with Notepad's word-breaking rules. Done when: the fixture corpus agrees with Notepad word for word.
- [ ] The engine is Nuspell behind `src/Notepad.Core/SpellEngine.cs`, running fully offline on bundled Hunspell-compatible dictionaries. Done when: the corpus checks with no network and no system spell service.
- [ ] Suggestions rank as Notepad ranks them for the fixture corpus. Done when: top suggestions match on every fixture.
- [ ] Checking never blocks typing: it runs within the committed budget on large buffers. Done when: the perf test measures it.
- [ ] The engine exposes ignore-word and add-to-dictionary hooks for the UI. Done when: both are tested at the engine level.
- [ ] Commit: `"editor: add the spellcheck engine"`

**Test checkpoint:** `dotnet test --filter SpellEngine` green on the corpus; perf budget measured. Cheaper substitute that fails: spellcheck that works on ten words and hangs on ten thousand.

## 2. Squiggles and Suggestions UI

Why this section exists: the red squiggle is the surface users see. It must render, offer, and apply exactly as Notepad's.

**Fidelity:** Notepad spellcheck UI -- stock crops filed flat under `resources/baseline/stock/` with `-n11.2607.14.0-win25h2` names. Squiggle style, suggestion menu, and apply behavior match the capture. **Corrected 2026-09-17 (groom):** the seed dir `resources/baseline/spellcheck/` never existed (same seed error as D01 T02 §§1/3/4); this section's capture-first drive files the crops per the D01 T02 §4 precedent.

**Job:** The user can see and fix misspellings as in Notepad. Consumer: the buffer, through the undoable edit path.

**Treatment:** Red squiggle with click-for-suggestions per the capture. Cheaper substitute that fails the checkpoint: underlines with no menu.

**Chrome:** Consume the shared editor and menu styles. Do not invent a second suggestion treatment.

**Groomed 2026-09-13:** Notepad audit: the Shift+F10 suggestions trigger is now explicit.

- [ ] Misspelled words render the squiggle with Notepad's timing (as-you-type, not on save). Done when: the render test passes.
- [ ] Clicking offers suggestions with ignore and add-to-dictionary, as Notepad's. Done when: each action is driven.
- [ ] Applying a suggestion is one undo unit. Done when: apply-then-undo fixtures pass.
- [ ] Shift+F10 on a misspelled word opens its suggestions as Notepad's. Done when: the key is driven. Source: https://www.bleepingcomputer.com/news/microsoft/notepad-finally-gets-spellcheck-autocorrect-for-all-windows-11-users/
- [ ] Commit: `"editor: render squiggles and suggestions"`

**Test checkpoint:** Render, menu actions, and undo grouping driven; capture comparison passes. Cheaper substitute that fails: suggestions that bypass undo.

## 3. Autocorrect

Why this section exists: autocorrect changes text the user did not explicitly change, so its word list and behavior must match Notepad's, and it must be disableable.

- [ ] `src/Notepad.Core/AutoCorrect.cs` applies Notepad's common-mistake corrections as the user types. Done when: the correction fixtures pass.
- [ ] Every autocorrection is one undo unit and announces itself as Notepad does. Done when: the undo fixtures pass.
- [ ] Autocorrect never fires inside words the user just fixed manually. Done when: the fight-with-user test passes.
- [ ] Commit: `"editor: add autocorrect"`

**Test checkpoint:** Correction, undo, and no-fight fixtures green. Cheaper substitute that fails: autocorrect with no off switch.

## 4. Global and Per-File-Type Toggles

Why this section exists: Notepad lets users disable spelling globally or per file type. The toggles live in the settings store with the editor as consumer.

**Fidelity:** Notepad spelling settings -- stock crops filed flat under `resources/baseline/stock/` with `-n11.2607.14.0-win25h2` names. Toggle placement and per-type list match the capture. **Corrected 2026-09-17 (groom):** the seed dir `resources/baseline/settings/` never existed (same seed error as D01 T02 §§1/3/4); this section's capture-first drive files the crops per the D01 T02 §4 precedent.

**Job:** The user can scope spelling to the file types they want. Consumer: the settings store, which the spelling engine reads.

**Treatment:** Global toggle plus per-type list per the capture. Cheaper substitute that fails the checkpoint: a global toggle only.

**Chrome:** Consume the shared settings styles. Do not invent a second toggle treatment.

**Groomed 2026-09-13:** Notepad audit: the temporary per-file context toggle is now explicit.

- [ ] The settings page carries the spelling toggles bound to the §2 store with Notepad's file-type list. Done when: each toggle is driven.
- [ ] Toggling takes effect on open buffers immediately, as Notepad's. Done when: the live-effect test passes.
- [ ] New file types default as Notepad defaults them. Done when: the default is recorded and tested.
- [ ] The context menu offers a temporary spellcheck toggle for the current file only. Done when: the toggle is driven and does not touch the store. Source: https://www.bleepingcomputer.com/news/microsoft/notepad-finally-gets-spellcheck-autocorrect-for-all-windows-11-users/
- [ ] Commit: `"editor: toggle spelling globally and per file type"`

**Test checkpoint:** Toggles, live effect, and defaults driven; capture comparison passes. Cheaper substitute that fails: toggles that need a restart.

## Verification

- [ ] `dotnet test` green
- [ ] Corpus agreement with Notepad proven
- [ ] `python3 scripts/todo-graph.py validate` clean
