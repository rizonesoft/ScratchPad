---
schema_version: 1
id: lightweight-formatting
domain: 02-editor
status: draft
title: "TODO-04 -- Lightweight Formatting"
depends_on: ["editing-surface"]
track: N2
---

# TODO-04 -- Lightweight Formatting

> **Goal:** Notepad's formatting toolbar and Markdown support exactly: inline styles, lists, tables, and a Markdown source view that round-trips.

> [!IMPORTANT]
> **Current state:** The `D02 T01` surface is plain text only. No toolbar, no styles, no Markdown. Filed by groom 2026-09-14 from the Notepad surface research: the formatting toolbar (bold, italic, lists, nested lists, strikethrough, tables) with Markdown syntax is now core Notepad, so a 1:1 clone owes it.

## Inputs

- Microsoft's Notepad formatting announcements (toolbar, Markdown syntax, tables in Insider builds rolling to stable)
- [`02-editor/TODO-01-editing-surface.md`](./TODO-01-editing-surface.md) -- the surface being formatted
- [`01-notepad-core/TODO-02-menus-settings-status.md`](../01-notepad-core/TODO-02-menus-settings-status.md) -- §2 owns the formatting toggle

**Groomed 2026-09-23:** Registry named: "the `MenuCommands` registry" is the `commands` dictionary in `src/ScratchPad/MenuBar.xaml.cs` (lines 39-80), driven through `AppMenuBar.SetEnabled(automationId, bool)`; no type is named MenuCommands.

## Outcome

- The formatting toolbar offers Notepad's styles with identical behavior.
- Markdown typed by hand renders, and rendered text keeps its Markdown source.
- Tables work as Notepad's, by toolbar and by Markdown syntax.
- Formatting is toggleable in settings and never corrupts plain text files.

**Adjacency:** list=applicable @ D02 T04 §2; document=applicable @ D01 T02 §5; settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D02 T01 §4

**Adjacency rationale:** Lists are the list; print renders the formatting; the toggle lives in the D01 store; every format change undoes through the D02 stack.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Format model over the buffer | D02 T01 §2, D01 T01 §18 |  [ ]   |
|   2   |   §2    | Toolbar: inline styles and lists | §1 |  [ ]   |
|   3   |   §3    | Markdown syntax and source fidelity | §1 |  [ ]   |
|   4   |   §4    | Tables by toolbar and syntax | §2, §3 |  [ ]   |
|   5   |   §5    | Formatting toggle and plain-text safety | §2, D01 T02 §2 |  [ ]   |

---

## 1. Format Model over the Buffer

Why this section exists: formatting is data on top of the buffer, not a second buffer. The model decides what Markdown means here, once.

- [ ] `src/Notepad.Core/FormatModel.cs` represents Notepad's styles as annotations on the §2 buffer. Done when: the model fixtures pass. **Recorded 2026-09-16:** D01 T02 §1 ships File > New Markdown tab disabled; this section enables it through the `MenuCommands` registry and drives it on landing.
- [ ] The supported syntax is exactly Notepad's (no extra Markdown dialect). Done when: the syntax list is recorded from the source and tested.
- [ ] Annotations survive edits, undo, and save/load without drifting from the text. Done when: the stability fixtures pass.
- [ ] `FormatConverter` extends to the recorded syntax list (nested lists, strikethrough, tables) so export, copy-as, and print keep them. Done when: each construct round-trips through the three converters (Groomed 2026-09-23.)
- [ ] Commit: `"editor: add the format model"`

**Test checkpoint:** `dotnet test --filter FormatModel` green on model, syntax, and stability fixtures. Cheaper substitute that fails: formatting stored as HTML nobody can diff.

## 2. Toolbar: Inline Styles and Lists

Why this section exists: the toolbar is the surface. Bold, italic, lists, nested lists, and strikethrough must behave as Notepad's.

**Fidelity:** Notepad formatting toolbar -- stock crops filed flat under `resources/baseline/stock/` with `-n11.2607.14.0-win25h2` names. Buttons, order, and active states match the capture. **Corrected 2026-09-17 (groom):** the seed dir `resources/baseline/formatting/` never existed (same seed error as D01 T02 §§1/3/4); this section's capture-first drive files the crops per the D01 T02 §4 precedent.

**Job:** The user can format text as in Notepad. Consumer: the buffer annotations, through the undoable edit path.

**Treatment:** Toolbar per the capture. Cheaper substitute that fails the checkpoint: a format menu standing in for the toolbar.

**Chrome:** Consume the shared toolbar styles. Do not invent a second toolbar treatment.

**Groomed 2026-09-13:** Notepad audit: headings, nested-list clipboard, links with the scheme gate, and Clear Formatting are now explicit.

- [ ] `src/ScratchPad/FormatToolbar.xaml` offers Notepad's inline styles and lists with active states. Done when: the capture comparison passes. **Corrected 2026-09-17 (groom):** the seed path `src/Notepad/` never existed (same seed error as D01 T02 §§1/3/4/5).
- [ ] Nested lists indent and outdent as Notepad's. Done when: the nesting fixtures pass.
- [ ] Every format change is undoable per Notepad's grouping. Done when: the undo fixtures pass.
- [ ] Headings apply through the H1 toolbar picker with title, subtitle, section, and subsection levels. Done when: each level is driven. Source: https://www.windowslatest.com/2025/07/02/windows-11-notepads-rich-text-formatting-markdown-is-now-available/
- [ ] Nested lists preserve structure across copy and paste; list continuation and renumbering are recorded from the capture. Done when: the clipboard round-trips pass. Source: https://learn.microsoft.com/en-us/windows-insider/release-notes/apps/notepad
- [ ] Links insert through the toolbar or Ctrl+K with anchor text, and Ctrl+click opens them in the default browser; hand-typed Markdown link syntax works too, and editing or removing a link is recorded from the capture. Done when: insert, open, edit, and remove are driven. Source: https://www.windowslatest.com/2025/07/02/windows-11-notepads-rich-text-formatting-markdown-is-now-available/
- [ ] Link opening gates schemes as Notepad does post-CVE-2026-20841: http/https open directly, every other scheme warns and requires confirmation. Done when: adversarial fixtures (file, ms-appinstaller, custom schemes) pass. Source: https://www.ghacks.net/2026/02/12/windows-11-notepad-bug-let-markdown-links-run-files-without-warning/
- [ ] Clear Formatting strips styles, hyperlinks, and headings from the selection (or the document with no selection) through the toolbar button, Ctrl+Space, and the Edit menu. Done when: all three paths are driven. Source: https://allthings.how/how-to-remove-text-formatting-in-notepad-on-windows-11/ **Recorded 2026-09-16:** D01 T02 §1 ships Edit > Clear Formatting disabled; this section enables it through the `MenuCommands` registry as part of the Edit-menu path.
- [ ] Stock shortcuts Ctrl+B, Ctrl+I, and Ctrl+Shift+X apply bold, italic, and strikethrough, and Tools > Export's Ctrl+Shift+X is rebound with the move recorded. Done when: each shortcut is driven and Export keeps a free shortcut (Groomed 2026-09-23.)
- [ ] Commit: `"editor: build the formatting toolbar"`

**Test checkpoint:** Toolbar, nesting, and undo driven; capture comparison passes. Cheaper substitute that fails: styles that apply but never show active.

## 3. Markdown Syntax and Source Fidelity

Why this section exists: users type Markdown by hand. It must render, and the file on disk must keep clean Markdown source.

**Groomed 2026-09-13:** Notepad audit: the view switch, the .txt save warning, and per-tab activation are now explicit.

- -> XREF: D01 T02 §4 -- the disabled status-bar Formatted switch this section enables alongside the View pair

- [ ] Hand-typed Markdown renders with Notepad's timing and rules. Done when: the render fixtures pass.
- [ ] Save writes clean Markdown source, byte-stable across open-format-save cycles. Done when: the round-trip fixtures pass.
- [ ] Malformed or partial syntax renders as literal text, never corrupts. Done when: the malformed fixtures pass.
- [ ] Non-Markdown files are unaffected: no syntax is ever injected into plain text. Done when: the plain-text fixtures pass.
- [ ] The formatted-versus-syntax view switch from the View menu and status bar changes rendering without touching the source. Done when: the switch is driven both ways. Source: https://blogs.windows.com/windows-insider/2025/05/30/text-formatting-in-notepad-begin-rolling-out-to-windows-insiders/ **Recorded 2026-09-16:** D01 T02 §1 ships View > Formatted and Syntax disabled; this section enables both through the `MenuCommands` registry and drives the switch on landing. **Recorded 2026-09-16 (D01 T02 §4):** the status-bar switch ships disabled in §4; this section enables it alongside the View pair and drives both entries. The count follows the rendered view (Formatted counts rendered text, Syntax counts source; §4 probes).
- [ ] Saving formatted content as .txt warns that formatting is lost and strips it; saving as .md retains it. Done when: both paths are driven. Source: https://www.ghacks.net/2025/07/09/we-take-a-closer-look-at-notepads-formatting-options/
- [ ] Formatting activates per tab: a blank tab stays plain until formatting is used in it. Done when: the activation fixtures pass. Source: https://www.ghacks.net/2025/07/09/we-take-a-closer-look-at-notepads-formatting-options/
- [ ] Commit: `"editor: render Markdown with source fidelity"`

**Test checkpoint:** Render, round-trip, malformed, and plain-text fixtures green. Cheaper substitute that fails: a renderer that rewrites the user's source.

## 4. Tables by Toolbar and Syntax

Why this section exists: tables are the newest formatting surface. Both entry paths (toolbar, Markdown pipes) must work and agree.

**Fidelity:** Notepad tables -- stock crops filed flat under `resources/baseline/stock/` with `-n11.2607.14.0-win25h2` names. Grid behavior and pipe-syntax rendering match the capture. **Corrected 2026-09-17 (groom):** the seed dir `resources/baseline/formatting/` never existed (same seed error as D01 T02 §§1/3/4); this section's capture-first drive files the crops per the D01 T02 §4 precedent.

**Job:** The user can make tables as in Notepad. Consumer: the buffer annotations and the saved Markdown source.

**Treatment:** Toolbar grid plus pipe syntax per the capture. Cheaper substitute that fails the checkpoint: tables by toolbar only.

**Chrome:** Consume the shared toolbar and table styles. Do not invent a second table treatment.

- [ ] The toolbar inserts and edits tables as Notepad's. Done when: the grid fixtures pass.
- [ ] Pipe-syntax tables render and stay editable as source. Done when: the syntax fixtures pass.
- [ ] Both paths produce identical saved Markdown. Done when: the agreement fixtures pass.
- [ ] Commit: `"editor: add tables by toolbar and syntax"`

**Test checkpoint:** Grid, syntax, and agreement fixtures green; capture comparison passes. Cheaper substitute that fails: tables that save in a private format.

## 5. Formatting Toggle and Plain-Text Safety

Why this section exists: formatting is optional in Notepad, and plain text must stay plain. The toggle and the safety net live here.

**Groomed 2026-09-13:** Notepad audit: the on-by-default value and the disable confirmation are now explicit.

**Groomed 2026-09-23:** Card already exists: `SettingsCardFormatting` sits disabled in SettingsPage.xaml with an owner comment naming this item, and no key exists yet (settings-schema.md); enable and bind it to a new formatting key.

- [ ] The settings page carries the formatting toggle bound to the store. Done when: the toggle is driven.
- [ ] With formatting off, the toolbar hides and all syntax stays literal. Done when: the off-state fixtures pass.
- [ ] Opening a `.txt` file never interprets Markdown, regardless of the toggle. Done when: the plain-text fixtures pass.
- [ ] Formatting is enabled by default; disabling it prompts for confirmation as captured. Done when: the default and the prompt are driven. Source: https://blogs.windows.com/windows-insider/2025/05/30/text-formatting-in-notepad-begin-rolling-out-to-windows-insiders/
- [ ] Commit: `"editor: gate formatting on its toggle"`

**Test checkpoint:** Toggle, off-state, and plain-text fixtures green. Cheaper substitute that fails: formatting that cannot be turned off.

## Verification

- [ ] `dotnet test` green
- [ ] Markdown round-trips byte-stable; plain text untouched
- [ ] `python3 scripts/todo-graph.py validate` clean
