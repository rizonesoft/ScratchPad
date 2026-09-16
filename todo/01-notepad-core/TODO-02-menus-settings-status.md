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
- -> XREF: D05 T03 §3 -- slash commands versus palette split; the palette lists without reimplementing

## Outcome

- Every Notepad menu item exists, is enabled at the right time, and does its job or names its owner.
- Settings persist, take effect without restart where Notepad does, and have exactly one store.
- The status bar shows live line/column, zoom, encoding, and line endings.
- Print produces Notepad's output for the active document.

**Adjacency:** list=applicable @ D01 T02 §8; document=applicable @ D01 T02 §5; settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=not-applicable (no import/export in this file); reverse=applicable @ D01 T02 §2

**Adjacency rationale:** The settings store is the settings owner with its consumer named in §2; print is the document; resetting settings to defaults is the reversal; the §8 palette is the list.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Menu bar with all items and enablement | D01 T01 §1 |  [ ]   |
|   2   |   §2    | Settings store with one writer | D01 T01 §1 |  [ ]   |
|   3   |   §3    | Settings page | §2 |  [ ]   |
|   4   |   §4    | Status bar | D01 T01 §1 |  [ ]   |
|   5   |   §5    | Print path | §1 |  [ ]   |
|   6   |   §6    | Menu and shortcut completeness audit | §1, T02 §3, T02 §4 |  [ ]   |
|   7   |   §7    | Reading level in the status bar | §4 |  [ ]   |
|   8   |   §8    | Command palette | §1, D05 T02 §6 |  [ ]   |
|   9   |   §9    | Live counts in the status bar | §4 |  [ ]   |
|  10   |   §10   | Custom accent themes | §2, §3 |  [ ]   |
|  11   |   §11   | Session word goal | §4, §9 |  [ ]   |

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
- [ ] The File menu names New, New Window, Open, Save, Save As, Save All, Page Setup, Print, Exit, and the recents submenu routed to D01 T01 §6; Close Tab and Close Window route to their tab and window owners. Done when: every item invokes its handler in the UI test. **Recorded 2026-09-15:** this item is the named home for every trigger the D01 T01 engine sections defer: Open applies the D01 T01 §4 OpenDialogDefaults spec and owns the first open entry point, Save As shows the D01 T01 §5 SaveDialogDefaults dialog, Save honors the D01 T01 §5 SaveRedirect contract, New Window invokes the D01 T01 §9 mechanism, and the recents submenu renders the D01 T01 §6 RecentFiles list. Rule: engine sections ship behavior fully driven through neutral seams; this item renders and re-drives every trigger, and no engine section stamps while its trigger contract is unspecified. **Recorded 2026-09-15:** D01 T01 §14 defers its ShowStatsPanel trigger here (always-enabled command, panel owned there, Ctrl+Shift+G ships meanwhile); placement follows item 4 (marked non-Notepad addition, never in Notepad's order). **Recorded 2026-09-16:** D01 T01 §16 defers its ShowSnapshots trigger here (always-enabled command, dialog owned there, Ctrl+Shift+H ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §17 defers its ShowTemplates trigger here (always-enabled command, dialog owned there, Ctrl+Shift+E ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §18 defers its ShowExport trigger here (always-enabled command, dialog owned there, Ctrl+Shift+X ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §19 defers its LockFile trigger here (always-enabled command, dialog owned there, Ctrl+Shift+L ships meanwhile; unlock rides the open path, never a menu command); placement follows item 4.
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

- [ ] `src/Notepad.Core/SettingsStore.cs` owns and records every tunable: theme, font, wrap, zoom default, and later AI settings. Done when: no other file writes a setting.
- [ ] The store persists atomically and migrates old versions forward. Done when: a corrupt store can restore defaults with a notice, driven in tests.
- [ ] Readers observe changes live; nothing caches a stale copy. Done when: a change propagates to all readers in the test.
- [ ] The store's schema is documented with each key's consumer. Done when: `docs/settings-schema.md` names every key and its reader.
- [ ] Fresh-install defaults for every key (font family, style, size; wrap; status bar; theme) match a clean Notepad install exactly and are recorded from the capture. Done when: a clean-profile drive matches the recorded values.
- [ ] Commit: `"notepad-core: add the settings store"`

**Test checkpoint:** `dotnet test --filter SettingsStore` green, including corrupt-store reset and live propagation. Cheaper substitute that fails: settings scattered across the registry and config files.

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

- [ ] `src/Notepad/PrintService.cs` renders the active document with Notepad's header/footer codes, margins, and wrap. Done when: print-to-PDF matches the golden output.
- [ ] Page setup persists per Notepad's behavior. Done when: the persistence is driven.
- [ ] Print failure (no printer, cancelled dialog) reports and changes nothing. Done when: both paths are driven.
- [ ] Header and footer codes &l, &c, &r, &d, &t, &f, and &p render as Notepad's, defaulting to header &f and footer Page &p; custom codes re-enter each print and an empty box prints nothing. Done when: print-to-PDF fixtures cover every code. Source: https://support.microsoft.com/en-gb/topic/how-to-use-notepad-to-create-a-log-file-dd228763-76de-a7a7-952b-d5ae203c4e12
- [ ] Command-line printing (/P, /PT) routed from D01 T01 §8 completes through this path. Done when: print-then-close is driven.
- [ ] Commit: `"notepad-core: add the print path"`

**Test checkpoint:** Print-to-PDF matches golden output byte-for-byte (modulo timestamps); failure paths driven. Cheaper substitute that fails: a print button that screenshots the window.

## 6. Menu and Shortcut Completeness Audit

Why this section exists: menus rot one item at a time. The audit makes "every control works or names its owner" a repeatable check, not a launch-day hope.

- [ ] `docs/menu-audit.md` enumerates every menu item, shortcut, and enablement rule from the capture, each resolved to working or to a named owning section. Done when: no item is unaccounted.
- [ ] `tests/UI/MenuAuditTest` invokes every working item and shortcut through the real menu. Done when: `dotnet test --filter MenuAudit` passes on a Windows runner in CI.
- [ ] The audit runs in CI so a newly dead item fails the build. Done when: a deliberately deadened probe item fails the run (reverted immediately).
- [ ] Commit: `"notepad-core: audit menu and shortcut completeness"`

**Test checkpoint:** Audit green in CI; probe dead item fails; every item working or owner-named. Cheaper substitute that fails: a spreadsheet audit nobody reruns.

## 7. Reading Level in the Status Bar

Why this section exists: writers calibrate difficulty. A click computes grade level locally with no agent and no network.

**Fidelity:** new build, no baseline (beyond the stock status bar).

**Job:** The user can read the document's grade level on demand. Consumer: the status bar, which shows the computed value.

**Treatment:** Click-to-compute readout in the status area; recomputes on demand only. Cheaper substitute that fails the checkpoint: always-on scoring that taxes typing.

**Chrome:** Consume the shared status styles. Do not invent a second metric treatment.

**Needs:** Windows host (build/test)

- [ ] Flesch-Kincaid grade computes locally over the buffer. Done when: fixtures match reference values.
- [ ] Clicking the status area computes and shows the score. Done when: driven.
- [ ] The score never recomputes unprompted and never touches the network. Done when: the negative tests pass.
- [ ] Commit: `"notepad-core: show reading level on demand"`

**Test checkpoint:** Computation, display, and the on-demand rule driven. Cheaper substitute that fails: a score that phones home.

## 8. Command Palette

Why this section exists: every command in one fuzzy list: menu items, agent actions, each runnable by name. Discoverable beats memorable.

**Fidelity:** new build, no baseline (stock Notepad has no palette).

**Job:** The user can run any command by name. Consumer: the command handlers, which the palette invokes identically to menus.

**Treatment:** Ctrl+Shift+P fuzzy list with shortcuts shown; entries mirror §1 menu items plus D05 T02 §6 selection actions. Cheaper substitute that fails the checkpoint: a palette missing commands the menus have.

**Chrome:** Consume the shared list styles. Do not invent a second palette treatment.

**Needs:** Windows host (build/test)

- [ ] `src/Notepad/CommandRegistry.cs` names every §1 menu item plus the D05 T02 §6 selection actions with shortcuts. Done when: the registry test enumerates them.
- [ ] The palette lists fuzzy-matched entries with shortcuts shown. Done when: driven.
- [ ] Invoking from the palette equals invoking from the menu. Done when: the equivalence test passes.
- [ ] The slash-command overlap resolves per the D05 T03 §3 XREF with no double implementation. Done when: the split is recorded and tested.
- [ ] Every §1 item and D05 T02 §6 action appears or names why not. Done when: the audit passes.
- [ ] Commit: `"notepad-core: add the command palette"`

**Test checkpoint:** Registry, UI, equivalence, and audit driven. Cheaper substitute that fails: a palette that lists half the app.

## 9. Live Counts in the Status Bar

Why this section exists: writers watch length as they type. Words, reading time, and characters update live beside the stock fields.

**Fidelity:** new build, no baseline (beyond the stock status bar in §4).

**Job:** The user can watch counts update while typing. Consumer: the status bar (§4), which renders the new fields in its existing layout.

**Treatment:** Debounced live counts off the buffer; typing never waits on arithmetic. Cheaper substitute that fails the checkpoint: counts on save only.

**Chrome:** Consume the shared status styles. Do not invent a second count treatment.

**Needs:** Windows host (build/test)

- [ ] Words and characters update live as the user types. Done when: every keystroke updates them under host drive.
- [ ] Reading time updates live beside the counts. Done when: the estimate tracks the words.
- [ ] Recompute is debounced off the keystroke path. Done when: rapid typing shows one recompute per pause.
- [ ] Typing benchmarks prove counts never block input. Done when: latency matches §4's bar without the fields.
- [ ] Commit: `"notepad-core: count live in the status bar"`

**Test checkpoint:** live counts, reading time, debounce, and non-blocking input are all driven in the room. Cheaper substitute that fails: counts that lag a paragraph behind.

## 10. Custom Accent Themes

Why this section exists: system dark and light are the floor. Writers pick accent themes that feel like theirs, previewed live before applying.

**Fidelity:** new build, no baseline (beyond the stock theme setting in §3).

**Job:** The user can pick and preview accent themes. Consumer: the settings page (§3), which previews before applying.

**Treatment:** A theme gallery with live preview; system themes stay the default. Cheaper substitute that fails the checkpoint: a hex field with no preview.

**Chrome:** Consume the shared settings styles. Do not invent a second gallery treatment.

**Needs:** Windows host (build/test)

- [ ] The gallery lists the built-in accent themes. Done when: every theme renders its swatch.
- [ ] Preview applies live before commit. Done when: hovering previews and leaving restores.
- [ ] The chosen accent persists across restarts through §2. Done when: relaunch keeps it.
- [ ] Stock dark and light stay default and untouched. Done when: a fresh install shows system themes.
- [ ] Commit: `"notepad-core: theme the accents"`

**Test checkpoint:** gallery, preview, persistence, and untouched defaults are all driven in the room. Cheaper substitute that fails: themes that need a restart to apply.

## 11. Session Word Goal

Why this section exists: a word goal with a thin progress line for the session. No accounts, no streaks, no cloud: the goal dies with the session.

**Fidelity:** new build, no baseline (stock Notepad goals nothing).

**Job:** The user can set a session word goal and watch the line fill. Consumer: the status bar (§4), which hosts the line; the live counter (§9), which feeds it.

**Treatment:** Goal set per session; the thin line fills from §9's live count; reaching it is a quiet full line, not a celebration. Cheaper substitute that fails the checkpoint: goals that persist, sync, or streak.

**Chrome:** Consume the shared status styles. Do not invent a second goal treatment.

**Needs:** Windows host (build/test)

- [ ] A session goal sets from the status bar. Done when: the set path is driven.
- [ ] The thin line fills from the live count. Done when: typing moves the line under host drive.
- [ ] The goal and progress vanish with the session. Done when: relaunch shows no goal.
- [ ] Commit: `"notepad-core: goal the session"`

**Test checkpoint:** set, fill, and session-death are all driven in the room. Cheaper substitute that fails: a goal that follows you home.

## Verification

- [ ] `dotnet test` green
- [ ] Every menu item working or owner-named, proven in CI
- [ ] `python3 scripts/todo-graph.py validate` clean
