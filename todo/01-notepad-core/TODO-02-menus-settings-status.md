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

- [ ] `src/Notepad/MenuBar.xaml` carries every Notepad item with its shortcut and separator placement. Done when: the capture comparison passes item by item.
- [ ] Each item routes to its handler; items whose work lives elsewhere route to that owner and are never dead. Done when: §6's audit finds no dead item.
- [ ] Enablement follows state (no selection, no tabs, clean buffer) exactly as Notepad's. Done when: the enablement matrix is driven.
- [ ] Recently added or AI-owned items (if any) are marked and owned, never snuck into Notepad's order. Done when: §6's audit approves each addition.
- [ ] Commit: `"notepad-core: build the full menu bar"`

**Test checkpoint:** Capture comparison item by item; enablement matrix driven across states; no dead items. Cheaper substitute that fails: items asserted present without invoking their handlers.

## 2. Settings Store with One Writer

Why this section exists: settings with two writers disagree. One store, one writer, every reader through it.

- [ ] `src/Notepad/SettingsStore.h` and `SettingsStore.cpp` own every tunable: theme, font, wrap, zoom default, and later AI settings. Done when: no other file writes a setting.
- [ ] The store persists atomically and migrates old versions forward. Done when: a corrupt store resets to defaults with a notice, driven in tests.
- [ ] Readers observe changes live; nothing caches a stale copy. Done when: a change propagates to all readers in the test.
- [ ] The store's schema is documented with each key's consumer. Done when: `docs/settings-schema.md` names every key and its reader.
- [ ] Commit: `"notepad-core: add the settings store"`

**Test checkpoint:** `ctest -R SettingsStore` green, including corrupt-store reset and live propagation. Cheaper substitute that fails: settings scattered across the registry and config files.

## 3. Settings Page

Why this section exists: the settings page is the store made visible. Every control binds to the store, and the store is the only writer.

**Fidelity:** Notepad settings page -- `resources/baseline/settings/`. Control order, labels, and grouping match the capture.

**Job:** The user can change every setting and see it take effect. Consumer: the settings store, which is the only writer.

**Treatment:** WinUI settings page with Notepad's grouping. Cheaper substitute that fails the checkpoint: a dialog with a subset of controls.

**Chrome:** Consume the shared settings styles. Do not invent a second settings treatment.

- [ ] `src/Notepad/SettingsPage.xaml` binds every control to the §2 store. Done when: changing each control changes the store and the app behavior.
- [ ] App theme (light, dark, use-system) matches Notepad's options and applies live. Done when: each theme is driven with capture comparison.
- [ ] Font family, style, and size match Notepad's picker and apply to the editor live. Done when: each choice is driven.
- [ ] Settings take effect without restart wherever Notepad applies them live. Done when: each live-applied setting is driven.
- [ ] Reset to defaults restores every key and is confirmed before applying. Done when: the reset path is driven.
- [ ] AI settings (when they land) extend this page through the same store, not a second one. Done when: the extension point is recorded.
- [ ] Commit: `"notepad-core: build the settings page"`

**Test checkpoint:** UI drive changes every control and proves the behavior change; reset driven; capture comparison passes. Cheaper substitute that fails: controls that write the UI but not the store.

## 4. Status Bar

Why this section exists: the status bar is always visible, so any staleness is always visible. It shows live truth for the active tab.

**Fidelity:** Notepad status bar -- `resources/baseline/status-bar/`. Segments, order, and click behaviors match the capture.

**Job:** The user can read line/column, zoom, encoding, and line endings at a glance. Consumer: none, this surface is the consumer.

**Treatment:** Live-bound status segments per the capture. Cheaper substitute that fails the checkpoint: labels updated only on save.

**Chrome:** Consume the shared status styles. Do not invent a second status treatment.

- [ ] `src/Notepad/StatusBar.xaml` binds line/column, zoom, encoding, and line endings to the active tab. Done when: every keystroke and switch updates it.
- [ ] Clicking a segment opens its Notepad behavior (encoding menu, line-ending menu, zoom control). Done when: each click path is driven.
- [ ] CRLF/LF and tab/space counts follow Notepad's rules exactly. Done when: the math fixtures pass.
- [ ] A selection shows its character count as Notepad does. Done when: the selection-count fixtures pass.
- [ ] The bar hides and shows per the View menu with the choice persisted. Done when: the toggle is driven.
- [ ] Commit: `"notepad-core: build the status bar"`

**Test checkpoint:** UI drive proves live updates on edit, switch, and setting change; click paths driven; math fixtures green. Cheaper substitute that fails: a status bar that updates on a timer instead of on state.

## 5. Print Path

Why this section exists: Notepad prints. The slice is small but must be exact: headers, footers, margins, and wrapping as Notepad does them.

**Fidelity:** Notepad print output and dialog -- `resources/baseline/print/`. Header/footer codes and layout match.

**Job:** The user can print the active document as Notepad prints it. Consumer: the printer (or PDF), which receives Notepad's layout.

**Treatment:** System print dialog with Notepad's header/footer codes. Cheaper substitute that fails the checkpoint: printing plain text with no headers.

**Chrome:** Consume the shared dialog styles. Do not invent a second print treatment.

- [ ] `src/Notepad/PrintService.cpp` renders the active document with Notepad's header/footer codes, margins, and wrap. Done when: print-to-PDF matches the golden output.
- [ ] Page setup persists per Notepad's behavior. Done when: the persistence is driven.
- [ ] Print failure (no printer, cancelled dialog) reports and changes nothing. Done when: both paths are driven.
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
