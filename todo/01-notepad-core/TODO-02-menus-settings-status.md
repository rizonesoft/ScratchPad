---
schema_version: 1
id: menus-settings-status
domain: 01-notepad-core
status: draft
title: "TODO-02 -- Menus, Settings and Status"
depends_on: ["winui-app-spine"]
track: N1
---

# TODO-02 -- Menus, Settings and Status

> **Goal:** The full Notepad menu bar with working items and shortcuts, a persisted settings page, a live status bar, and the print path.

> [!IMPORTANT]
> **Current state:** Only the `D01 T01` window shell and menu host exist. No menu items, no settings store, no status bar. Every section here is UI and carries Fidelity.

## Inputs

- `resources/baseline/` captures of menus, settings, status bar, and print dialog
- [`01-notepad-core/TODO-01-winui-app-spine.md`](./TODO-01-winui-app-spine.md) -- the shell and tab model these surfaces hang off

## Outcome

- Every Notepad menu item exists, is enabled at the right time, and does its job or names its owner.
- Settings persist, take effect without restart where Notepad does, and have exactly one store.
- The status bar shows live line/column, zoom, encoding, and line endings.
- Print produces Notepad's output for the active document.

**Adjacency:** list=not-applicable (no lists in this file); document=applicable @ D01 T02 §5; settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D01 T02 §2

**Adjacency rationale:** The settings store is the settings owner with its consumer named in §2; print is the document; resetting settings to defaults is the reversal.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Menu bar with all items and enablement | D01 T01 §1 |  [ ]   |
|   2   |   §2    | Settings store with one writer | D01 T01 §1 |  [ ]   |
|   3   |   §3    | Settings page | §2 |  [ ]   |
|   4   |   §4    | Status bar | D01 T01 §1 |  [ ]   |
|   5   |   §5    | Print path | §1 |  [ ]   |
|   6   |   §6    | Menu and shortcut completeness audit | §1, T02 §3, T02 §4 |  [ ]   |

---

## 1. Menu Bar with All Items and Enablement

Why this section exists: a clone with a wrong menu is not a clone. Every item exists, and enablement follows selection and dirty state exactly.

**Fidelity:** Notepad menu bar (File, Edit, View) -- `resources/baseline/menus/`. Item order, labels, separators, and shortcuts match the capture.

**Job:** The user can reach every command through the menu. Consumer: the command handlers, each owned here or by a named section.

**Treatment:** Native WinUI menu bar with Notepad's structure. Cheaper substitute that fails the checkpoint: a toolbar standing in for menus.

**Chrome:** Consume the shared menu styles. Do not invent a second menu treatment.

**Groomed 2026-09-13:** Notepad audit: File-menu specifics, Time/Date, Font, and Clear Formatting routing, the no-Bing rule, View-menu toggles, and Alt+F/E/V access keys are now explicit.

- [ ] `src/Notepad/MenuBar.xaml` carries every Notepad item with its shortcut and separator placement. Done when: the capture comparison passes item by item.
- [ ] Each item routes to its handler; items whose work lives elsewhere route to that owner and are never dead. Done when: §6's audit finds no dead item.
- [ ] Enablement follows state (no selection, no tabs, clean buffer) exactly as Notepad's. Done when: the enablement matrix is driven.
- [ ] Recently added or AI-owned items (if any) are marked and owned, never snuck into Notepad's order. Done when: §6's audit approves each addition.
- [ ] The File menu names New, New Window, Open, Save, Save As, Save All, Page Setup, Print, Exit, and the recents submenu routed to D01 T01 §6; Close Tab and Close Window route to their tab and window owners. Done when: every item invokes its handler in the UI test.
- [ ] The Edit menu carries Time/Date routed to the F5 insert (D02 T01 §5). Done when: the item inserts exactly what F5 inserts.
- [ ] The Edit menu carries no Search-with-Bing item (removed in the Win11 redesign), and Edit > Font jumps to the Settings font page (§3) instead of a dialog. Done when: the capture comparison confirms both. Source: https://www.digitalcitizen.life/notepad-windows-11/
- [ ] The View menu carries Zoom In/Out/Restore, the Status Bar toggle, the Word Wrap toggle, and the formatted-versus-syntax Markdown view switch routed to D02 T04 §3. Done when: each toggle drives its behavior. Source: https://blogs.windows.com/windows-insider/2025/05/30/text-formatting-in-notepad-begin-rolling-out-to-windows-insiders/
- [ ] Menu access keys Alt+F, Alt+E, and Alt+V open their menus from the keyboard. Done when: each key is driven. Source: https://scottsekinger.com/2026/02/02/windows-notepad-keyboard-shortcuts-complete-guide/
- [ ] The Edit menu carries Clear Formatting routed to D02 T04 §2. Done when: the item strips exactly what the toolbar button strips.
- [ ] Commit: `"notepad-core: build the full menu bar"`

**Test checkpoint:** Capture comparison item by item; enablement matrix driven across states; no dead items. Cheaper substitute that fails: items asserted present without invoking their handlers.

## 2. Settings Store with One Writer

Why this section exists: settings with two writers disagree. One store, one writer, every reader through it.

**Groomed 2026-09-13:** Notepad audit: fresh-install default values are now recorded from the capture (research conflicts on wrap/statusbar defaults, so the capture decides).

- [ ] `src/Notepad/SettingsStore.h` and `SettingsStore.cpp` own every tunable: theme, font, wrap, zoom default, and later AI settings. Done when: no other file writes a setting.
- [ ] The store persists atomically and migrates old versions forward. Done when: a corrupt store resets to defaults with a notice, driven in tests.
- [ ] Readers observe changes live; nothing caches a stale copy. Done when: a change propagates to all readers in the test.
- [ ] The store's schema is documented with each key's consumer. Done when: `docs/settings-schema.md` names every key and its reader.
- [ ] Fresh-install defaults for every key (font family, style, size; wrap; status bar; theme) match a clean Notepad install exactly and are recorded from the capture. Done when: a clean-profile drive matches the recorded values.
- [ ] Commit: `"notepad-core: add the settings store"`

**Test checkpoint:** `ctest -R SettingsStore` green, including corrupt-store reset and live propagation. Cheaper substitute that fails: settings scattered across the registry and config files.

## 3. Settings Page

Why this section exists: the settings page is the store made visible. Every control binds to the store, and the store is the only writer.

**Fidelity:** Notepad settings page -- `resources/baseline/settings/`. Control order, labels, and grouping match the capture.

**Job:** The user can change every setting and see it take effect. Consumer: the settings store, which is the only writer.

**Treatment:** WinUI settings page with Notepad's grouping. Cheaper substitute that fails the checkpoint: a dialog with a subset of controls.

**Chrome:** Consume the shared settings styles. Do not invent a second settings treatment.

**Groomed 2026-09-13:** Notepad audit: the gear entry point and About info on the Settings page are now explicit.

- [ ] `src/Notepad/SettingsPage.xaml` binds every control to the §2 store. Done when: changing each control changes the store and the app behavior.
- [ ] App theme (light, dark, use-system) matches Notepad's options and applies live. Done when: each theme is driven with capture comparison.
- [ ] Font family, style, and size match Notepad's picker and apply to the editor live. Done when: each choice is driven.
- [ ] Settings take effect without restart wherever Notepad applies them live. Done when: each live-applied setting is driven.
- [ ] Reset to defaults restores every key and is confirmed before applying. Done when: the reset path is driven.
- [ ] AI settings (when they land) extend this page through the same store, not a second one. Done when: the extension point is recorded.
- [ ] The Settings page opens from the gear button in the top-right corner of the window. Done when: the entry is driven. Source: https://www.digitalcitizen.life/notepad-windows-11/
- [ ] About and app-version info live on the Settings page itself; there is no separate Help menu or About dialog. Done when: the capture comparison confirms placement.
- [ ] Commit: `"notepad-core: build the settings page"`

**Test checkpoint:** UI drive changes every control and proves the behavior change; reset driven; capture comparison passes. Cheaper substitute that fails: controls that write the UI but not the store.

## 4. Status Bar

Why this section exists: the status bar is always visible, so any staleness is always visible. It shows live truth for the active tab.

**Fidelity:** Notepad status bar -- `resources/baseline/status-bar/`. Segments, order, and click behaviors match the capture.

**Job:** The user can read line/column, zoom, encoding, and line endings at a glance. Consumer: none, this surface is the consumer.

**Treatment:** Live-bound status segments per the capture. Cheaper substitute that fails the checkpoint: labels updated only on save.

**Chrome:** Consume the shared status styles. Do not invent a second status treatment.

**Groomed 2026-09-13:** Notepad audit: the document-total count, the Markdown view toggle, and CR display are now explicit.

- [ ] `src/Notepad/StatusBar.xaml` binds line/column, zoom, encoding, and line endings to the active tab. Done when: every keystroke and switch updates it.
- [ ] Clicking a segment opens its Notepad behavior (encoding menu, line-ending menu, zoom control). Done when: each click path is driven.
- [ ] CRLF/LF and tab/space counts follow Notepad's rules exactly. Done when: the math fixtures pass.
- [ ] A selection shows its character count as Notepad does. Done when: the selection-count fixtures pass.
- [ ] The bar hides and shows per the View menu with the choice persisted. Done when: the toggle is driven.
- [ ] With no selection the bar shows the document-total character count; with a selection it shows selected-plus-total counts. Done when: the count fixtures pass. Source: https://blogs.windows.com/windows-insider/2023/12/07/announcing-windows-11-insider-preview-build-23601-dev-channel/
- [ ] The bar offers the formatted-versus-syntax Markdown view switch routed to D02 T04 §3. Done when: the switch drives the view change.
- [ ] The line-ending segment displays CR alongside CRLF and LF per the detected convention. Done when: the CR fixture passes.
- [ ] Commit: `"notepad-core: build the status bar"`

**Test checkpoint:** UI drive proves live updates on edit, switch, and setting change; click paths driven; math fixtures green. Cheaper substitute that fails: a status bar that updates on a timer instead of on state.

## 5. Print Path

Why this section exists: Notepad prints. The slice is small but must be exact: headers, footers, margins, and wrapping as Notepad does them.

**Fidelity:** Notepad print output and dialog -- `resources/baseline/print/`. Header/footer codes and layout match.

**Job:** The user can print the active document as Notepad prints it. Consumer: the printer (or PDF), which receives Notepad's layout.

**Treatment:** System print dialog with Notepad's header/footer codes. Cheaper substitute that fails the checkpoint: printing plain text with no headers.

**Chrome:** Consume the shared dialog styles. Do not invent a second print treatment.

**Groomed 2026-09-13:** Notepad audit: header/footer codes with defaults and command-line print routing are now explicit.

- [ ] `src/Notepad/PrintService.cpp` renders the active document with Notepad's header/footer codes, margins, and wrap. Done when: print-to-PDF matches the golden output.
- [ ] Page setup persists per Notepad's behavior. Done when: the persistence is driven.
- [ ] Print failure (no printer, cancelled dialog) reports and changes nothing. Done when: both paths are driven.
- [ ] Header and footer codes &l, &c, &r, &d, &t, &f, and &p render as Notepad's, defaulting to header &f and footer Page &p; custom codes re-enter each print and an empty box prints nothing. Done when: print-to-PDF fixtures cover every code. Source: https://support.microsoft.com/en-gb/topic/how-to-use-notepad-to-create-a-log-file-dd228763-76de-a7a7-952b-d5ae203c4e12
- [ ] Command-line printing (/P, /PT) routed from D01 T01 §8 completes through this path. Done when: print-then-close is driven.
- [ ] Commit: `"notepad-core: add the print path"`

**Test checkpoint:** Print-to-PDF matches golden output byte-for-byte (modulo timestamps); failure paths driven. Cheaper substitute that fails: a print button that screenshots the window.

## 6. Menu and Shortcut Completeness Audit

Why this section exists: menus rot one item at a time. The audit makes "every control works or names its owner" a repeatable check, not a launch-day hope.

- [ ] `docs/menu-audit.md` enumerates every menu item, shortcut, and enablement rule from the capture, each resolved to working or to a named owning section. Done when: no item is unaccounted.
- [ ] `tests/UI/MenuAuditTest` invokes every working item and shortcut through the real menu. Done when: `ctest -R MenuAudit` passes on CI.
- [ ] The audit runs in CI so a newly dead item fails the build. Done when: a deliberately deadened probe item fails the run (reverted immediately).
- [ ] Commit: `"notepad-core: audit menu and shortcut completeness"`

**Test checkpoint:** Audit green in CI; probe dead item fails; every item working or owner-named. Cheaper substitute that fails: a spreadsheet audit nobody reruns.

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Every menu item working or owner-named, proven in CI
- [ ] `python3 scripts/todo-graph.py validate` clean
