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
>
> **Corrected 2026-09-15 (phase-1 run 3):** `D01 T01` has shipped §§1-9 and §27 since, so the shell, tab model and bar, file engines, session restore, prompts, multi-window, and chrome repair all exist behind the T01-whole gate this file waits on; §8 is implemented but unstamped. Still true: no menu items, no settings store, no status bar.
>
> **Corrected 2026-09-16 (§2 validation):** `ShellSettings` (settings.json seam: geometry, theme, opening, startup, recents, pins, jump-list hash, whatsnew) exists since D01 T01; "no settings store" now means no single-writer store. §2 adopts its keys (same file, same names, per the header note) and takes over writes; D01 T02 §1 has shipped since (menu bar with all items).
>
> **Corrected 2026-09-16 (phase-1 run 4 repair):** §§1-3 have shipped and stamped since (menu bar, single-writer store, settings page); open work is §§4-12. Still true: no status bar, no print path.
>
> **Corrected 2026-09-17 (rename filing):** §§1-4 have shipped and stamped since (menu bar, single-writer store, settings page, status bar); open work is §§5-15. §§13-15 (ScratchPad rename completion, title-bar icon, chrome color finetune) keep their §13-15 addresses and sequence before §5 in the Order column and the plan.
>
> **Corrected 2026-09-17 (groom):** §§13-14 have shipped and stamped since (rename completion, title-bar icon) and §16 (quarantine the MenuBarTests flakes) was filed. Open work is §§5-12, §15, §16; since 2026-09-17 the suites proving them run locally on the dev box, not in CI.

## Inputs

- `resources/baseline/` captures of menus, settings, and status bar, plus the §5 spec-constructed print goldens. **Corrected 2026-09-17 (groom):** was "and print dialog"; per the §5 validation no dialog capture is owed (Page Setup and Print are OS dialogs §5 binds but does not build).
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
|   1   |   §1    | Menu bar with all items and enablement | D01 T01 §1 |  [x]   |
|   2   |   §2    | Settings store with one writer | D01 T01 §1 |  [x]   |
|   3   |   §3    | Settings page | §2 |  [x]   |
|   4   |   §4    | Status bar | D01 T01 §1 |  [x]   |
|   5   |   §13   | ScratchPad rename completion | D01 T01 §1 |  [x]   |
|   6   |   §14   | Title-bar icon beside the tabs | §13, D01 T01 §11 |  [x]   |
|   7   |   §15   | Chrome color finetune against stock | §13, D01 T01 §1 |  [ ]   |
|   8   |   §5    | Print path | §1 |  [ ]   |
|   9   |   §6    | Menu and shortcut completeness audit | §1, T02 §3, T02 §4 |  [ ]   |
|  10   |   §7    | Reading level in the status bar | §4 |  [ ]   |
|  11   |   §8    | Command palette | §1, D05 T02 §6 |  [ ]   |
|  12   |   §9    | Live counts in the status bar | §4 |  [ ]   |
|  13   |   §10   | Custom accent themes | §2, §3 |  [ ]   |
|  14   |   §11   | Session word goal | §4, §9 |  [ ]   |
|  15   |   §12   | Recent Files display toggle | §1, §2, §3, D01 T01 §8 |  [ ]   |
|  16   |   §16   | Quarantine the MenuBarTests flakes | §1 |  [ ]   |

---

## 1. Menu Bar with All Items and Enablement

> **Started:** 2026-09-16T07:28:20Z

Why this section exists: a clone with a wrong menu is not a clone. Every item exists, and enablement follows selection and dirty state exactly.

**Fidelity:** Notepad menu bar (File, Edit, View) -- `resources/baseline/stock/notepad-menu-{file,edit,view,view-zoom,view-markdown}-n11.2607.14.0-win25h2.png`. Item order, labels, separators, and shortcuts match the captures. **Corrected 2026-09-16 (§1 validation):** the seed cited `resources/baseline/menus/`, which never existed; the File capture predates this section and the Edit/View/Zoom/Markdown captures were taken 2026-09-16.

**Job:** The user can reach every command through the menu. Consumer: the command handlers, each owned here or by a named section.

**Treatment:** Native WinUI menu bar with Notepad's structure. Cheaper substitute that fails the checkpoint: a toolbar standing in for menus. **Decided 2026-09-16 (§1 validation):** Open and Save As use `IFileOpenDialog`/`IFileSaveDialog` via COM interop with `IFileDialogCustomize` encoding combos (the same OS dialog stock shows); `FileOpenPicker` cannot host the stock encoding slot. Handlers hang off an `IMenuHost` seam MainWindow implements; pending-owner enablement goes through an id-keyed `MenuCommands` registry.

**Chrome:** Consume the shared menu styles. Do not invent a second menu treatment.

**Groomed 2026-09-13:** Notepad audit: File-menu specifics, Time/Date, Font, and Clear Formatting routing, the no-Bing rule, View-menu toggles, and Alt+F/E/V access keys are now explicit.

- [x] `src/ScratchPad/MenuBar.xaml` carries every Notepad item with its shortcut and separator placement. Done when: the capture comparison passes item by item. **Corrected 2026-09-16 (§1 validation):** the seed path `src/Notepad/` never existed; the app is `src/ScratchPad/`. **Probed 2026-09-16 (captures plus live UIA dumps, stock 11.2607.14.0):** File reads New tab Ctrl+N, New window Ctrl+Shift+N, New Markdown tab, Open Ctrl+O, Recent submenu, Save Ctrl+S, Save as Ctrl+Shift+S, Save all Ctrl+Alt+S, Page setup, Print Ctrl+P, Close tab Ctrl+W, Close window Ctrl+Shift+W, Exit, no separators; Recent shows `No recent files` plus Clear list when empty. Edit reads Undo Ctrl+Z, Cut Ctrl+X, Copy Ctrl+C, Paste Ctrl+V, Delete Del, Clear formatting, Search with Bing Ctrl+E, Define with Bing Ctrl+E, Find Ctrl+F, Find next F3, Find previous Shift+F3, Replace Ctrl+H, Go to Ctrl+G, Select all Ctrl+A, Time/Date F5, Font, with separators after Undo, Delete, Clear formatting, Define with Bing, Go to, and Time/Date; there is no Redo item. View reads Zoom submenu (Zoom in Ctrl+Plus, Zoom out Ctrl+Minus, Restore default zoom Ctrl+0), Status bar toggle, Word wrap toggle, Markdown submenu (Formatted, Syntax, no shortcuts, neither checked on plain text), no separators.
- [x] Each item routes to its handler; items whose work lives elsewhere route to that owner and are never dead. Done when: §6's audit finds no dead item. **Decided 2026-09-16 (§1 validation):** §6 runs later and re-audits as backstop; §1 stamps on its own every-live-item-invoked drive plus the pending table below. Items whose owners ship later in Phase 1 are present with stock labels and shortcuts but disabled, each naming its owner (accounted, not dead): Undo to D02 T01 §4; Cut, Copy, Paste, Delete, Select all to D02 T01 §3; Time/Date, Zoom in, Zoom out, Restore default zoom, Word wrap to D02 T01 §5; Find, Find next, Find previous to D02 T02 §2; Replace to D02 T02 §3; Go to to D02 T02 §4; New Markdown tab to D02 T04 §1; Clear formatting to D02 T04 §2; Formatted, Syntax to D02 T04 §3; Font to §3; Status bar to §4; Page setup, Print to §5. Each owner enables its items on landing through the `MenuCommands` registry (id-keyed `SetEnabled`); the enablement line is recorded on every owner section.
- [x] Enablement follows state (no selection, no tabs, clean buffer) exactly as Notepad's. Done when: the enablement matrix is driven. **Probed 2026-09-16:** stock enables every File and Edit item in all probed states (empty buffer, text, selected text; UIA `IsEnabled` true throughout and no greyed pixels), so our rule is all-live-items-enabled in every state; pending-owner items stay disabled until their owner lands (item 2). **Corrected 2026-09-16 (§1 validation):** the `no tabs` leg is moot (stock has no zero-tab state per D01 T01 §27); our zero-tab window keeps the same rule.
- [x] Recently added or AI-owned items (if any) are marked and owned, never snuck into Notepad's order. Done when: §6's audit approves each addition. **Decided 2026-09-16 (§1 validation):** the five deferred T01 triggers (ShowStatsPanel, ShowSnapshots, ShowTemplates, ShowExport, LockFile) live in a new fourth top-level `Tools` menu after View, keeping File/Edit/View in stock order; the menu itself is the mark. §6 re-audits; §1 stamps on the placement plus per-item ownership.
- [x] The File menu names New tab, New window, New Markdown tab, Open, Save, Save as, Save all, Page setup, Print, Exit, and the recents submenu routed to D01 T01 §6; Close tab and Close window route to their tab and window owners. Done when: every live item invokes its handler in the UI test. **Corrected 2026-09-16 (§1 validation):** the seed said `New` and omitted `New Markdown tab`; stock reads `New tab` plus `New Markdown tab` (capture). New tab opens and focuses a tab; New window invokes the D01 T01 §9 mechanism; Open shows the picker (D01 T01 §4 filter plus D01 T01 §29 encoding list, single-select, missing typed names get the §8 offer, failures render the §4 messages); Save writes pathed tabs in place (SaveRedirect opens Save As inline) and opens Save As on untitled; Save as shows the dialog (§5 filter plus encoding offer, tab-encoding prefill, tab EOL, `FileNameFor` prefill); Save all walks the §5 order with inline Save As prompts; Recent renders the §6 list with `No recent files` plus Clear list when empty (missing entries report NotFound); Close tab follows the §7 prompt path; Close window preserves silently for §6 restore; Exit follows the window-close path. **Default 2026-09-16:** typed-missing-name offer, missing-recent NotFound, and Exit-equals-window-close are unprobed (costs one branch each). **Contract change 2026-09-16:** Save on untitled now opens Save As (the §7 keep-open fallback stood only until this dialog existed); the §7 `UntitledSaveKeepsTabDirtyWithNothingWritten` drive is updated here to Save-then-Cancel-keeps-dirty. **Recorded 2026-09-15:** this item is the named home for every trigger the D01 T01 engine sections defer: Open applies the D01 T01 §4 OpenDialogDefaults spec and owns the first open entry point, Save As shows the D01 T01 §5 SaveDialogDefaults dialog, Save honors the D01 T01 §5 SaveRedirect contract, New Window invokes the D01 T01 §9 mechanism, and the recents submenu renders the D01 T01 §6 RecentFiles list. Rule: engine sections ship behavior fully driven through neutral seams; this item renders and re-drives every trigger, and no engine section stamps while its trigger contract is unspecified. **Recorded 2026-09-15:** D01 T01 §14 defers its ShowStatsPanel trigger here (always-enabled command, panel owned there, Ctrl+Shift+G ships meanwhile); placement follows item 4 (marked non-Notepad addition, never in Notepad's order). **Recorded 2026-09-16:** D01 T01 §16 defers its ShowSnapshots trigger here (always-enabled command, dialog owned there, Ctrl+Shift+H ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §17 defers its ShowTemplates trigger here (always-enabled command, dialog owned there, Ctrl+Shift+E ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §18 defers its ShowExport trigger here (always-enabled command, dialog owned there, Ctrl+Shift+X ships meanwhile); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §19 defers its LockFile trigger here (always-enabled command, dialog owned there, Ctrl+Shift+L ships meanwhile; unlock rides the open path, never a menu command); placement follows item 4. **Recorded 2026-09-16:** D01 T01 §29 defers its open-picker rendering here: Open shows the D01 T01 §29 `OpenDialogDefaults.EncodingOptions` list (Auto-Detect default) and passes the choice as `OpenOptions.ForcedEncoding` (Auto-Detect passes null), and Save As prefills the tab's recorded encoding (the forced name flows through `OpenSuccess`).
- [x] The Edit menu carries Time/Date routed to the F5 insert (D02 T01 §5). Done when: the item inserts exactly what F5 inserts. **Corrected 2026-09-16 (§1 validation):** the owner ships later, so §1 carries the item disabled (item 2) and D02 T01 §5 drives the insert plus the enablement on landing.
- [x] The Edit menu carries Search with Bing and Define with Bing (both Ctrl+E) launching the default browser, and Edit > Font jumps to the Settings font page (§3) instead of a dialog. Done when: the capture comparison confirms the items; Font ships disabled pending §3 (item 2) and §3 drives the jump. **Corrected 2026-09-16 (§1 validation):** the seed claimed Bing was removed (digitalcitizen source), but stock 11.2607.14.0 shows both items (capture plus UIA dump plus `SearchWithBingMenuItem`/`DefineWithBingMenuItem` in the binary); the no-Bing rule is dead. **Default 2026-09-16:** Search opens `https://www.bing.com/search?q=<selection>` and Define opens `https://www.bing.com/search?q=define+<selection>` (URL-encoded); with no selection both open the bare search page (unprobed, costs one branch each; clicking was never probed live because it opens the operator's browser). The URL builder is unit-pinned; the room asserts presence, shortcut, and enabled state only.
- [x] The View menu carries a Zoom submenu (Zoom in, Zoom out, Restore default zoom), the Status bar toggle, the Word wrap toggle, and a Markdown submenu (Formatted, Syntax) routed to D02 T04 §3. Done when: each toggle drives its behavior. **Corrected 2026-09-16 (§1 validation):** labels and submenu structure read off the captures (the seed's `Zoom In/Out/Restore` and `switch` wording was loose); every entry ships disabled pending its owner (Zoom trio and Word wrap to D02 T01 §5, Status bar to §4, Markdown pair to D02 T04 §3; item 2), unchecked, and each owner drives its behavior plus the enablement on landing. Source: https://blogs.windows.com/windows-insider/2025/05/30/text-formatting-in-notepad-begin-rolling-out-to-windows-insiders/
- [x] Menu access keys Alt+F, Alt+E, and Alt+V open their menus from the keyboard. Done when: each key is driven. Source: https://scottsekinger.com/2026/02/02/windows-notepad-keyboard-shortcuts-complete-guide/
- [x] The Edit menu carries Clear Formatting routed to D02 T04 §2. Done when: the item strips exactly what the toolbar button strips. **Corrected 2026-09-16 (§1 validation):** the owner ships later, so §1 carries the item disabled (item 2) and D02 T04 §2 drives the strip plus the enablement on landing.
- [x] Commit: `"notepad-core: build the full menu bar"`

> **Verified:** 2026-09-16 | §1 | Full menu bar: File/Edit/View labels, order, separators, and shortcuts pinned against the six stock captures (rendered comparison plus UIA drives), every live item invoking its handler through the `IMenuHost` seam, COM open/save dialogs with the §29/§5 encoding combos (Auto-Detect default mapping to null, forced names decoded with replacement fallback), pending-owner items disabled with enablement lines on all ten owner sections, Tools carrying the five deferred T01 triggers, Bing pair present and enabled with unit-pinned URLs, Alt+F/E/V/T access keys driven, §7 Save-then-Cancel updated for inline Save As; UI MenuBarTests 27/27, Unit BingSearchTests 4/4, full gate Smoke 1/1 Unit 275/275 Protocol 35/35 UI 144 plus 1 pre-existing quarantine of 145, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 2, candidate 156839b -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` advisory (framework accelerator text plus markdown icons, both dispositioned to the §6 audit note). Raw findings: docs/reviews/01-notepad-core/D01-T02-s1.md
> **CRUD:** applicable | Save/Save As wrote file bytes (read back via exact byte decode); close-window and exit wrote session state (read back via relaunch restore); RecentFiles wrote through use (read back via the reopened submenu); Create-offer decline wrote nothing (read back via absent tab and absent file)
> **Duration:** 153
> **Implementer:** Muse Code (Meta Muse Spark)

**Test checkpoint:** Capture comparison item by item; enablement matrix driven across states; no dead items. Cheaper substitute that fails: items asserted present without invoking their handlers.

## 2. Settings Store with One Writer

> **Started:** 2026-09-16T10:04:31Z

Why this section exists: settings with two writers disagree. One store, one writer, every reader through it.

**Groomed 2026-09-13:** Notepad audit: fresh-install default values are now recorded from the capture (research conflicts on wrap/statusbar defaults, so the capture decides).

- [x] `src/Notepad.Core/SettingsStore.cs` owns and records every tunable: theme, font, wrap, zoom default, and later AI settings. Done when: no other file writes a setting. **Recorded 2026-09-16 (§2 validation):** adopts the `ShellSettings` keys (geometry, theme, opening, startup, recents, pins, jump-list hash, whatsnew; same file, same names) and adds font family/style/size, word wrap, status-bar visibility, and zoom default; AI rides `JsonExtensionData` passthrough with no AI keys yet. One writer means one write implementation (`SettingsStore.WriteSnapshot`, which `ShellSettings.Save` delegates to so test seeding keeps working); production mutates only through `Update`, verified by review grep.
- [x] The store persists atomically and migrates old versions forward. Done when: a corrupt store can restore defaults with a notice, driven in tests. **Decided 2026-09-16 (§2 validation):** no version field exists, so v0 is today's unversioned file and §2 adds `Version` (current v1); migration runs in memory and persists lazily on the next `Update`; unknown future versions reset like corrupt with no backup kept (settings are not user data; cost of adding a backup: one `.bak` write). The notice is the store's `WasResetFromCorrupt` flag surfaced once at startup through a `CorruptSettingsDialog` in our wording (honest-non-parity: stock has no such notice).
- [x] Readers observe changes live; nothing caches a stale copy. Done when: a change propagates to all readers in the test. **Recorded 2026-09-16 (§2 validation):** no production reader needs live updates today (no settings UI exists; menus re-read per open), so §2 ships the `Changed` mechanism proven with test readers plus a reentrancy guard, and §3 with the D02 owners subscribe on landing; the one cached copy (`MainWindow.settings` field) is removed here.
- [x] The store's schema is documented with each key's consumer. Done when: `docs/settings-schema.md` names every key and its reader. **Recorded 2026-09-16 (§2 validation):** the doc covers adopted plus new keys with consumers, defaults, and default sources; observed stock keys without a Phase 1 home are listed as future (spellcheck/autocorrect to D02 T03, formatting to D02 T04, writing tools and the recent-files toggle unowned).
- [x] Fresh-install defaults for every key (font family, style, size; wrap; status bar; theme) match a clean Notepad install exactly and are recorded from the capture. Done when: a clean-profile drive matches the recorded values. **Probed 2026-09-16 (§2 validation, stock 11.2607.14.0 settings page plus UIA dumps):** font Consolas/Regular/11 (dropdown selections read live; cross-checked against documented reset guides), word wrap on (settings capture), status bar on (checked in the view-menu capture), theme "Use system setting" (selected radio), opening new tab and when-starts continue (selected; match current defaults). Zoom default 100 is a recorded default (stock exposes no zoom setting; cost: one int). Freshness caveat: the operator profile, not a clean install; every value sits at its canonical default and none looks customized.
- [x] Commit: `"notepad-core: add the settings store"`

**Test checkpoint:** `dotnet test --filter SettingsStore` green, including corrupt-store reset and live propagation. Cheaper substitute that fails: settings scattered across the registry and config files.

> **Verified:** 2026-09-16 | §2 | Single-writer settings store: every tunable owned by the store (adopted shell keys plus font family/style/size, wrap, status bar, zoom default), all production mutation through Update and all persists through the atomic snapshot write (Save delegates for test seeding), the unversioned file migrating in memory with lazy persist, corrupt/null/future files resetting to defaults with the flag surfaced once at startup through the notice dialog, live Changed plus a reentrancy guard with the cached window copy removed, schema with consumers and default sources in docs/settings-schema.md, fresh-install defaults pinned from the recorded stock probes; checkpoint Unit 10/10 plus UI 1/1 with the notice drive named, full gate Smoke 1/1 Unit 285/285 Protocol 35/35 UI 145 plus 1 pre-existing quarantine of 146, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** round 1, candidate abae736 -- `adversarial` approve (1 advisory: persist catch scope complete only while the path stays fixed, dispositioned in findings) · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T02-s2.md
> **CRUD:** applicable | Update wrote settings (read back via the reopened store plus file asserts); the corrupt launch wrote defaults plus the notice (read back via restored keys and the dismissed dialog); pin, recents, geometry, and jumplist wrote through Update (read back via Load probes in the green UI suite); reentrant Update wrote nothing further (read back via the throw assert)
> **Duration:** 93
> **Implementer:** Muse Code (Meta Muse Spark)

## 3. Settings Page

> **Started:** 2026-09-16T11:40:00Z

Why this section exists: the settings page is the store made visible. Every control binds to the store, and the store is the only writer.

**Fidelity:** Notepad settings page -- `resources/baseline/stock/notepad-settings[-light]-n11.2607.14.0-win25h2.png` (top viewport both themes) plus `resources/baseline/windows/notepad-open-in-setting-n11.2607.14.0-win25h2.png` (full page with the About panel). **Corrected 2026-09-16 (§3 validation):** the seed path `resources/baseline/settings/` never existed; the store is flat. Control order, labels, grouping, and control kinds match the captures.

**Job:** The user can change every setting and see it take effect. Consumer: the settings store, which is the only writer.

**Treatment:** WinUI settings page with Notepad's grouping. Cheaper substitute that fails the checkpoint: a dialog with a subset of controls.

**Chrome:** **Corrected 2026-09-16 (§3 validation):** no shared settings styles exist (App.xaml carries only the WinUI defaults; no settings toolkit is referenced), so this section establishes the settings-card treatment as first consumer with stock WinUI controls (Expander, ToggleSwitch, ComboBox, RadioButtons); later card owners consume it. Do not invent a second settings treatment.

**Needs:** Windows host (build/test)

**Groomed 2026-09-13:** Notepad audit: the gear entry point and About info on the Settings page are now explicit.

- -> XREF: D01 T02 §12 -- owns the Recent Files card's key and behavior; the card ships disabled here

- [x] `src/ScratchPad/SettingsPage.xaml` (+ `.xaml.cs`) binds every control to the §2 store. Done when: changing each bound control changes the store and the app behavior. **Corrected 2026-09-16 (§3 validation):** the seed path `src/Notepad/` never existed (same seed error as §1). **Probed 2026-09-16 (full UIA dump plus full-page shot, stock 11.2607.14.0):** 6 groups, 13 cards in order: Appearance (App theme expander), Text Formatting (Font expander; Word wrap toggle; Formatting toggle), Opening Notepad (Opening files dropdown; When Notepad starts expander; Recent Files toggle), Spelling (Spell check toggle-plus-expander; Autocorrect toggle), Advanced Features (Writing tools toggle), About side panel. Bound live here: App theme, Font, Word wrap, Opening files, When Notepad starts. Disabled with owner: Formatting (D02 T04 §5 item 1), Spell check plus Autocorrect (D02 T03 §4 item 1), Recent Files (D01 T02 §12), Writing tools (D05 T02 §6 item 10); disabled cards show stock-default state statically and enable on landing. Zoom and status-bar visibility have no stock card (probe), so those keys bind nowhere here (consumed by D02 T01 §5 and §4).
- [x] App theme (Light, Dark, Use system setting: stock-verbatim radios in the expander) applies live. Done when: each theme is driven with capture comparison. **Probed 2026-09-16:** the card is an expander holding exactly those three radios (Use system setting selected). Live apply subscribes the §2 Changed event and sets the window theme; comparison is our dark-canonical page golden plus human item-compare against the stock dark/light captures.
- [x] Font family, style, and size match Notepad's picker and apply to the editor live. Done when: each choice is driven. **Recorded 2026-09-16:** D01 T02 §1 ships Edit > Font disabled; this section enables it through the `MenuCommands` registry and drives the jump on landing. **Probed 2026-09-16 (stock 11.2607.14.0):** the Font expander holds Family/Style/Size dropdown rows (Consolas/Regular/11) plus a preview pangram; stock Edit > Font lands on the settings page (jump confirmed, parity). Style offers Regular/Italic/Bold/Bold Italic; Size offers 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72; Family lists installed families (runtime-populated). **Recorded 2026-09-16 (§3 validation):** no editor surface exists yet (EditorRegion is an empty D02-owned ContentControl), so this section drives each choice to the store and the live-apply-to-editor drive lands with D02 T01 §3; the §2 Changed event is the subscription point.
- [x] Settings take effect without restart wherever Notepad applies them live. Done when: each live-applied setting is driven. **Recorded 2026-09-16 (§3 validation):** theme applies live now (Changed-subscription drive); Opening-files and When-starts apply at next launch on stock too (no live behavior to drive); font, wrap, and zoom go live to the editor with D02 T01 §3 (font) and D02 T01 §5 (wrap, zoom); disabled cards have no live behavior until their owners land.
- [ ] ~~Reset to defaults restores every key and is confirmed before applying. Done when: the reset path is driven.~~ **Struck 2026-09-16:** stock 11.2607.14.0 carries no reset control (full-page UIA dump plus full-page shot: 13 cards and the About panel, no reset, no restore-defaults). A reset button would break this section's own Fidelity contract; parity is no reset. No replacement: there is no stock behavior to build. Parity negative driven: `SettingsPageHasNoReset`.
- [x] AI settings (when they land) extend this page through the same store, not a second one. Done when: the extension point is recorded. **Recorded 2026-09-16 (§3 validation):** the store half is already recorded (§2 schema doc: JsonExtensionData plus the key-adding pattern); this item records the page half (card-adding pattern: new card in stock position, key with a recorded default, schema-doc row, owner drive) in the same doc.
- [x] The Settings page opens from the gear button in the top-right corner of the window. Done when: the entry is driven. Source: https://www.digitalcitizen.life/notepad-windows-11/ **Probed 2026-09-16:** the stock main capture shows the gear at the far right of the toolbar row; ours sits after the whatsnew button in the menu row.
- [x] About and app-version info live on the Settings page itself; there is no separate Help menu or About dialog. Done when: the capture comparison confirms placement. **Probed 2026-09-16 (stock 11.2607.14.0):** About is a right-side panel (name, version, copyright, 4 Microsoft legal links, Send feedback, Help). **Decided 2026-09-16 (§3 validation):** ours carries our name and the assembly version; the support rows are omitted (Microsoft-support surfaces with no product equivalent; one card each to add) and copyright/publisher rows land with D07 identity. The version number itself belongs to the release packaging work (D07 T01 §1 pins identity); this page displays whatever the assembly says.
- [x] Commit: `"notepad-core: build the settings page"`

**Test checkpoint:** UI drive changes every bound control and proves the behavior change; no-reset negative driven; capture comparison passes. Cheaper substitute that fails: controls that write the UI but not the store.

> **Verified:** 2026-09-16 | §3 | Settings page in stock order: 13 cards across 6 groups (App theme, Font, Word wrap, Opening files, When Notepad starts bound live through Update-only writes; Formatting, Spell check, Autocorrect, Recent Files, Writing tools disabled with owner recorded; About panel with name and assembly version), gear entry with back return, Edit > Font enabled with jump to the expanded Font card, theme live through the store Changed event, page-half extension pattern recorded; reset struck (no stock control, parity negative driven); main golden refreshed (gear plus settled labels, all 598 diffs confined to the menu band) with a capture settle-wait; coverage 11 page drives plus 27 menu drives; full gate Smoke 1/1 Unit 285/285 Protocol 35/35 UI 156 plus 1 pre-existing quarantine of 157, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** round 2, candidate 224998a -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve (2 advisories, dispositioned in findings). Round 1 found 2 defects (unknown Opening value display, null-key preview crash), both fixed and re-verified; fixes ride this Ship commit, the candidate being pushed. Raw findings: docs/reviews/01-notepad-core/D01-T02-s3.md
> **CRUD:** applicable | Every card drive wrote settings (read back via reopened store asserts); theme flip wrote and re-rendered (read back via store plus pixel diff); font jump wrote nothing (read back via the expanded onscreen card); disabled cards wrote nothing (read back via UIA disabled asserts); golden wrote the baseline (read back via fresh compare)
> **Duration:** 91
> **Implementer:** Muse Code (Meta Muse Spark)

## 4. Status Bar

> **Started:** 2026-09-16T13:22:00Z

Why this section exists: the status bar is always visible, so any staleness is always visible. It shows live truth for the active tab.

**Fidelity:** Notepad status bar -- `resources/baseline/status-bar/`. Segments, order, and click behaviors match the capture. **Corrected 2026-09-16 (§4 validation):** the seed dir never existed (same seed error as §§1/3); stock status-bar crops are filed flat under `resources/baseline/stock/` with `-n11.2607.14.0-win25h2` names by this section's capture-first drive, and the app side is the main-window golden (status band included), refreshed per procedure with the diff confined to that band.

**Job:** The user can read line/column, zoom, encoding, and line endings at a glance. Consumer: none, this surface is the consumer.

**Treatment:** Live-bound status segments per the capture. Cheaper substitute that fails the checkpoint: labels updated only on save.

**Chrome:** Consume the shared status styles. Do not invent a second status treatment. **Corrected 2026-09-16 (§4 validation):** no shared status styles exist (App.xaml carries only the WinUI defaults, verified this run), so this section establishes the status treatment as first consumer with stock WinUI controls; §§7/9/11 consume it.

**Groomed 2026-09-13:** Notepad audit: the document-total count, the Markdown view toggle, and CR display are now explicit.

**Needs:** Windows host (build/test)

- -> XREF: D02 T04 §3 -- owns the Formatted-switch enablement; the switch ships disabled here

- [x] `src/ScratchPad/StatusBar.xaml` (+ `.xaml.cs`) binds line/column, zoom, encoding, and line endings to the active tab. Done when: every keystroke and switch updates it. **Corrected 2026-09-16 (§4 validation):** the seed path `src/Notepad/` never existed (same seed error as §§1/3). **Recorded 2026-09-16:** this section measures and records the per-keystroke status-update latency bar that §9 item 4 measures against.
- [ ] ~~Clicking a segment opens its Notepad behavior (encoding menu, line-ending menu, zoom control). Done when: each click path is driven.~~ **Struck 2026-09-16:** stock 11.2607.14.0 plain-text segments are static Text (single-click probed twice foreground-pinned plus double-click once across EOL/encoding/zoom/count/LnCol: no popup, no state change, frames plus UIA dumps agree); parity is no click path. The only clickable strip element is the Formatted switch (item 7, Button). No replacement: there is no stock behavior to build. Parity negative driven: `StatusSegmentsHaveNoClickPath`.
- [x] CRLF/LF and tab/space counts follow Notepad's rules exactly. Done when: the math fixtures pass.
- [x] A selection shows its character count as Notepad does. Done when: the selection-count fixtures pass.
- [x] The bar hides and shows per the View menu with the choice persisted. Done when: the toggle is driven. **Recorded 2026-09-16:** D01 T02 §1 ships View > Status bar disabled and unchecked; this section enables it through the `MenuCommands` registry and drives the toggle on landing.
- [x] With no selection the bar shows the document-total character count; with a selection it shows selected-plus-total counts. Done when: the count fixtures pass. Source: https://blogs.windows.com/windows-insider/2023/12/07/announcing-windows-11-insider-preview-build-23601-dev-channel/
- [x] The bar offers the formatted-versus-syntax Markdown view switch routed to D02 T04 §3. Done when: the switch drives the view change. **Decided 2026-09-16 (§4 validation):** the §1 item-2 pending-owner pattern: this section renders the switch disabled with its stock label, and D02 T04 §3 enables it alongside the View pair and drives the view change on landing (enablement line recorded on its item 5).
- [x] The line-ending segment displays CR alongside CRLF and LF per the detected convention. Done when: the CR fixture passes.
- [x] Commit: `"notepad-core: build the status bar"`

**Test checkpoint:** UI drive proves live updates on edit, switch, and setting change; click paths driven; math fixtures green. Cheaper substitute that fails: a status bar that updates on a timer instead of on state.

> **Verified:** 2026-09-16 | §4 | Status strip live-bound to the active tab: six segments in stock order (Ln/Col, count, mode left; zoom, EOL, encoding right) refreshing on every keystroke, caret move, tab switch, edit, per-tab property change, and settings change; neutral StatusSegments plus StatusBar control with stock WinUI treatment; programmatic fills through SetBoxText (8 sites) with TabsEdited announce; View > Status bar toggle enabled through the §1 registry, collapsing the 32-DIP row with the choice persisted; click paths struck (stock segments are static Text, parity negative driven); Formatted switch rendered disabled with its stock label, enablement owned by D02 T04 §3 (bidirectional); CR segment plus 1 MiB/500 ms latency bar recorded for §9; main golden refreshed (all 933 diffs confined to the status band); coverage 8 strip drives plus 46 math fixtures plus golden pair; cheap gate Smoke 1/1 Unit 331/331 Protocol 35/35, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** round 2, candidate fbf0088 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve (2 advisories, dispositioned in findings). Round 1 found 1 record defect (deferral owner syntax plus one-sided XREF, validator-caught), fixed and re-validated; pre-findings folds (Dispose unhook, golden refresh, TODO-04 enablement line) ride the unpushed candidate, the round-2 XREF bullets ride this Ship commit. Raw findings: docs/reviews/01-notepad-core/D01-T02-s4.md
> **CRUD:** applicable | Every strip drive wrote tab content or settings (read back via UIA segment asserts); toggle wrote visibility (read back via the collapsed row plus reopened store); fills wrote boxes (read back via refreshed segment text); golden wrote the baseline (read back via fresh compare)
> **Duration:** 485
> **Implementer:** Muse Code (Meta Muse Spark)
> **Deferred:** Formatted-switch enablement -> XREF: D02 T04 §3 (item: "The formatted-versus-syntax view switch from the View menu and status bar") -- status-bar switch ships disabled in §4; §3 enables it alongside the View pair and drives both entries

## 5. Print Path

> **Started:** 2026-09-17T17:55:00Z

Why this section exists: Notepad prints. The slice is small but must be exact: headers, footers, margins, and wrapping as Notepad does them.

**Fidelity:** Notepad print output and dialog -- `resources/baseline/print/`. Header/footer codes and layout match. **Corrected 2026-09-17 (§5 validation):** the seed dir never existed and no stock print artifacts are capturable from a window-station-less session (Server CI runners ship classic notepad, not 11.x); this section creates the dir holding spec-constructed PDF goldens with a provenance README instead. No dialog capture is owed: Page Setup and Print are OS dialogs this section binds but does not build. **Decided 2026-09-17 (§5 validation):** byte-for-byte can only mean self-consistency (two PDF engines never byte-match), so the checkpoint's golden is constructed from the documented code spec plus Page Setup defaults, and parity lives in item 4's per-code coverage; a Win11 session diffing our PDF against stock's stays unfiled future work (cost: one capture session).

**Job:** The user can print the active document as Notepad prints it. Consumer: the printer (or PDF), which receives Notepad's layout.

**Treatment:** System print dialog with Notepad's header/footer codes. Cheaper substitute that fails the checkpoint: printing plain text with no headers.

**Chrome:** Consume the shared dialog styles. Do not invent a second print treatment.

**Groomed 2026-09-13:** Notepad audit: header/footer codes with defaults and command-line print routing are now explicit.

**Needs:** Windows host (build/test)

**Corrected 2026-09-17 (§5 validation):** the seed carried no `Needs` although printing, the OS dialogs, and PDF output are Windows-only; every sibling declares it.

- [ ] `src/ScratchPad/PrintService.cs` renders the active document with Notepad's header/footer codes, margins, and wrap. Done when: print-to-PDF matches the golden output. **Corrected 2026-09-17 (§5 validation):** the seed path `src/Notepad/` never existed (same seed error as §§1/3/4). **Recorded 2026-09-16:** D01 T02 §1 ships File > Print and File > Page setup disabled; this section enables both through the `MenuCommands` registry and drives them on landing. PrintSeam.cs (D01 T01 §8) absorbs here per its header; the render engine is the implementer's choice with reasons (must print-to-PDF headless on the dev box. **Corrected 2026-09-17 (groom):** was "headless on CI"; CI runs no suites since 2026-09-17).
- [ ] Page setup persists per Notepad's behavior. Done when: the persistence is driven. **Decided 2026-09-17 (§5 validation):** behavior means the Page Setup dialog set (header, footer, margins, orientation, paper) surviving restarts and applying to prints, persisted in the §2 store (same file, new keys, schema-doc rows); stock's own storage location is not probed (default, costs one migrator if stock parity ever demands its exact keys).
- [ ] Print failure (no printer, cancelled dialog) reports and changes nothing. Done when: both paths are driven. **Decided 2026-09-17 (§5 validation):** no-printer drives through `/pt` to a bogus printer (in-tree precedent `NoSuchPrinter8`); cancel drives through UIA dismiss of the OS dialog.
- [ ] Header and footer codes &l, &c, &r, &d, &t, &f, and &p render as Notepad's, defaulting to header &f and footer Page &p; custom codes re-enter each print and an empty box prints nothing. Done when: print-to-PDF fixtures cover every code. Source: https://support.microsoft.com/en-gb/topic/how-to-use-notepad-to-create-a-log-file-dd228763-76de-a7a7-952b-d5ae203c4e12
- [ ] Command-line printing (/P, /PT) routed from D01 T01 §8 completes through this path. Done when: print-then-close is driven.
- [ ] Commit: `"notepad-core: add the print path"`

**Test checkpoint:** Print-to-PDF matches golden output byte-for-byte (modulo timestamps); failure paths driven. Cheaper substitute that fails: a print button that screenshots the window.

## 6. Menu and Shortcut Completeness Audit

Why this section exists: menus rot one item at a time. The audit makes "every control works or names its owner" a repeatable check, not a launch-day hope.

- [ ] `docs/menu-audit.md` enumerates every menu item, shortcut, and enablement rule from the capture, each resolved to working or to a named owning section. Done when: no item is unaccounted. **Recorded 2026-09-16 (D01 T02 §1 review):** two advisories disposition here: (1) WinUI renders accelerator text `Delete`/`Ctrl++`/`Ctrl+-` on the disabled Delete/Zoom items where stock reads `Del`/`Ctrl+Plus`/`Ctrl+Minus` (correct keys, no XAML text override exists); confirm the keys against the captures and leave text rendering to the D02 owners' landing drives unless an override surfaces. (2) Stock renders glyph icons on the Markdown Formatted/Syntax pair; ours ships plain pending D02 T04 §3; confirm icon parity with that owner's landing.
- [ ] `tests/UI/MenuAuditTest` invokes every working item and shortcut through the real menu. Done when: `dotnet test --filter MenuAudit` passes in the local full run on the dev box. **Corrected 2026-09-17 (groom):** was "on a Windows runner in CI"; CI runs no suites since 2026-09-17, and the audit drives the real menu, so it rides the fenced Interactive run.
- [ ] The audit runs in the local full suite so a newly dead item fails the run. Done when: a deliberately deadened probe item fails the run (reverted immediately). **Corrected 2026-09-17 (groom):** was "runs in CI"; same CI narrowing.
- [ ] Commit: `"notepad-core: audit menu and shortcut completeness"`

**Test checkpoint:** Audit green in the local full run; probe dead item fails; every item working or owner-named. Cheaper substitute that fails: a spreadsheet audit nobody reruns.

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

- [ ] `src/ScratchPad/CommandRegistry.cs` names every §1 menu item plus the D05 T02 §6 selection actions with shortcuts. Done when: the registry test enumerates them. **Corrected 2026-09-17 (groom):** the seed path `src/Notepad/` never existed (same seed error as §§1/3/4/5).
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

- -> XREF: D01 T02 §15 -- chrome color finetune preserves the accent coloring this gallery themes.

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

## 12. Recent Files Display Toggle

Why this section exists: stock's Opening Notepad group carries a Recent Files toggle, on by default; the §3 page renders the card disabled until this section binds it. The toggle is display-side only: recording never stops, so flipping it destroys nothing.

**Probed 2026-09-16 (§3 validation, stock 11.2607.14.0):** the toggle reads On; toggling off leaves the File > Recent entry in place (menu dump), so the entry stays and the contents hide. Exact stock semantics (record vs display) unconfirmed; display-side is the recorded default (reversible; a recording-side toggle would destroy user data on an unconfirmed control, cost: the submenu plus jump-list branches).

**Needs:** Windows host (build/test)

- -> XREF: D01 T02 §3 -- the disabled Recent Files card this section enables, binds, and drives
- [ ] The store carries a `ShowRecentFiles` key defaulting true, with a schema-doc row naming this section as consumer. Done when: the key round-trips and the doc row exists.
- [ ] Toggle-off shows the Recents submenu empty state and omits recents from the jump-list feed; toggle-on restores both. Done when: each state is driven.
- [ ] The §3 Recent Files card is enabled and bound to the key. Done when: the card drive passes both ways.
- [ ] Commit: `"notepad-core: toggle recent-files display"`

**Test checkpoint:** Key round-trip, submenu empty state, jump-list omission, and both card directions driven. Cheaper substitute that fails: a toggle that stops recording recents.

## 13. ScratchPad Rename Completion

> **Started:** 2026-09-17T10:34:16Z

Why this section exists: the tree is mid-rename (uncommitted `src/ScratchPad/`, renamed solution, migrated settings path), and nothing else should land until the rename is verified whole and committed alone. A mechanical rename mixed with behavior changes is unreviewable. **Corrected 2026-09-17 (§13 validation):** the mechanical commit already landed as `0dbdaf8` (2026-09-17, 83 files) before this section ran, with behavior commits after it; history is immutable, so this section completes the rename (one functional straggler: the `intelligent-notepad://` URL scheme, inconsistent with its own `URL:ScratchPad Protocol` description) and verifies the landed whole. Identity audit 2026-09-17: ProgId `ScratchPad.Document`, AppId `Rizonesoft.ScratchPad`, assembly `ScratchPad.dll` all new; only the scheme is old.

**Fidelity:** renamed surfaces read ScratchPad with nothing else redrawn: the About panel name, window titles, and the refreshed settings golden; the main golden is pixel-identical. Deviations: none beyond the name.

**Job:** The user can run the app under its final name with prior settings carried over. Consumer: the settings and session stores, which read the migrated paths.

**Treatment:** Verify-everything, commit-once mechanical rename. Cheaper substitute that fails the checkpoint: committing the tree with stale references left for later.

**Chrome:** No new chrome. Do not restyle anything in the rename commit.

**Needs:** Windows host (build/test)

- -> XREF: D07 T01 §1 -- packaging pins the renamed identity (exe, AppId, ProgId, URL scheme); the rename lands first so identity is final.

- [x] Zero stale `IntelligentNotepad` references outside the documented keep-list (the `NoteCrypto` lock magic, historical reviews and phase-runs, ignored scratch). Done when: the grep is quoted clean with each keep named. **Corrected 2026-09-17 (§13 validation):** keep-list extended: the `AppDataDir` legacy-folder constant plus its tests (functional migration source, kept forever), historical `docs/plans/` (dated records, same class as reviews), and the §6 Why historical note (stamped prose, correct as history). The URL scheme is not a keep (next item). Case-insensitive grep; `obj/`/`bin/` ignored dirt excluded. Done: census 33 hits in 13 files (excluding `docs/reviews/` and `docs/phase-runs/`, which hold only historical keeps); fixed 17 scheme hits (item 2) plus the process-plan skill prompt line; keeps are NoteCrypto magic + tests (3), AppDataDir migration + test (3), docs/plans (1), §6 history (1), plan prose quoting the old name as before-state (TODO-01 2, this section 5). Zero functional stragglers.
- [x] **Corrected 2026-09-17 (added):** The URL scheme renames `intelligent-notepad` to `scratchpad` in `ProtocolAssociation` (constant, comment, registry key derivation) with its Unit and UI tests plus any docs following; old-scheme links need no compat (unreleased app, zero deployed links). Done when: the scheme grep is clean and the link suites pass on both OSes. Later items renumbered +1. Done: const + comment + 15 test literals renamed; `scratchpad` verified unclaimed in HKCU and HKCR; Linux link units 38/38, Windows ProtocolHandlerTests 5/5 (register cycle, link open, malformed decline, shell click); §26 decision lines corrected with the re-run evidence.
- [x] `src/ScratchPad.slnx` builds on Windows and `src/Notepad.Neutral.slnf` builds from Linux, both with zero warnings. Done when: both commands are quoted green. Done: `dotnet build src/ScratchPad.slnx` (Windows) 0 warnings 0 errors; `dotnet build src/Notepad.Neutral.slnf` (Linux) 0 warnings 0 errors.
- [x] Cheap gate plus the title, settings-name, migration, and golden suites are green. Done when: Smoke/Unit/Protocol plus the UI subset outputs are quoted. Done: Windows neutral scope (cheap-gate substance; `build/gate-cheap-win.ps1` itself hardcodes the pre-rename path and is ignored scratch, so the equivalent command ran with correct paths) Smoke 1/1, Unit 336/336, Protocol 35/35; UI golden subset 5/5 (Fresh, Shell, Settings, wobble pin, shift probe). Title (WindowTitleTests) and migration (AppDataDirTests) fixtures ride the Unit green.
- [x] The legacy `%LocalAppData%\IntelligentNotepad` folder migrates once to `%LocalAppData%\ScratchPad` and is never deleted. Done when: the migration fixtures pass and a live launch with seeded legacy data proves the copy. Done: AppDataDirTests fixtures ride the green Unit suites both OSes; live proof 2026-09-17 (new home staged aside with byte-verified backup, marker seeded in legacy, real exe launched): marker plus settings.json copied to the recreated home with identical bytes, legacy intact (only delta the seeded marker, since removed), user data restored byte-identical (diff-verified both dirs).
- [x] Commit: `"chore: complete the ScratchPad rename"` (**Corrected 2026-09-17:** the prescribed `"chore: rename IntelligentNotepad to ScratchPad"` was taken by the landed `0dbdaf8`; this commit carries the scheme plus stragglers only, no behavior work). Done: `f9e38b2`, pushed.

**Test checkpoint:** Grep clean; both-OS builds green; gates quoted; migration proven live; this section's commit contains only rename-completion. (**Corrected 2026-09-17:** "exactly one commit" described the unlanded plan; the mechanical `0dbdaf8` plus this completion commit is the immutable shape. The phase-run record rides the commit per precedent (`04c766c`, `7e0283d`); "only rename-completion" means no behavior work, not no run file.)

> **Verified:** 2026-09-17 | §13 | Rename completed and verified whole: scheme `intelligent-notepad` to `scratchpad` (const, comment, 15 test literals; unclaimed in HKCU/HKCR; Linux link units 38/38, Windows ProtocolHandlerTests 5/5); tracked grep clean outside documented keeps (33-hit census with exclusions stated); both-OS builds 0 warnings; Windows neutral plus UI golden subset green, Linux neutral green; live migration proof (marker copied byte-identical, legacy intact, user data restored byte-verified); CI 35212112337 success both jobs
> **Review:** round 1, candidate f9e38b2 -- Opus panel `adversarial` advisory · `consistency` advisory · `integration` advisory · `record` advisory, all four applied (old-key queried absent, comments rewrapped, scheme in both XREFs, checkpoint/census wording). Raw findings: docs/reviews/01-notepad-core/D01-T02-s13.md
> **CRUD:** applicable | registry wrote scheme keys during drives (read back via live key asserts, unregistered in finally, both keys verified absent after); grep wrote the census (read back via counts per file); builds wrote binaries (read back via 0-warning summaries); app-data wrote the migrated home (read back via byte comparison, then restored byte-verified)
> **Duration:** 33
> **Implementer:** Muse Code (Meta Muse Spark)

## 14. Title-Bar Icon Beside the Tabs

> **Started:** 2026-09-17T12:48:44Z

Why this section exists: stock Notepad shows its glyph at the left of the title bar, but our content-extended chrome draws no caption icon, so the tab strip starts bare. The icon is drawn by us, in our row, from the shipped asset.

**Fidelity:** stock title bar with app glyph -- `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` (glyph at the far left of the tab row). Placement matches the capture; the glyph itself is our asset per D01 T01 §11, not stock's.

**Job:** The user can recognize the app at a glance in its own title bar. Consumer: none, this surface is the consumer.

**Treatment:** App-drawn 16px image pinned left of the tab strip inside the extended chrome. Cheaper substitute that fails the checkpoint: relying on the caption icon the extended chrome never draws.

**Chrome:** Consume the shipped `resources/notepad.ico` via a rasterized content asset. Do not redraw or recolor it.

**Needs:** Windows host (build/test)

- -> XREF: D01 T01 §11 -- owns the icon asset this section rasterizes and places; the asset stays the single source.
- -> XREF: D00 T02 §7 -- owns the CI evidence capture this section's chrome crop is deferred to; the crop commits there.

- [x] A 16px raster of `resources/notepad.ico` ships as build content. Done when: the asset lands in the build output. Done: `resources/titlebar-icon-16.png` exported from the ico's native 16px frame via PIL (0 byte diffs over 1024, no resample); csproj Content with `Link`; output copy byte-identical; Windows build 0 warnings. Round-1: `resources/titlebar-icon-32.png` added the same way (0 diffs over 4096) for non-100% displays, selected by `XamlRoot.RasterizationScale` at load (16 below 1.5, 32 at/above); both frames native, no redraw.
- [x] The glyph renders left of the first tab in the extended title row. Done when: a UI drive asserts presence plus left-of-tabs geometry. Done: `TitleBarIcon` Image (16 DIP, margin 12/0/4/0, hit-test off) pinned in a two-column row ahead of `tabBar` in `MainWindow.xaml.cs`; `tests/UI/TitleBarIconTests.cs` drives presence, DPI-aware 16px size, left-of-first-tab, and strip centering; 2/2 green on the host (host at 150% caught a fixed 16px assertion, now scale-aware). Round-2: decode state rides ItemStatus (`ImageOpened`/`ImageFailed`), and the drive waits for `loaded`, proving `ms-appx` resolves unpackaged (green on the host, so the scheme is proven, not assumed); the asset re-selects on `XamlRoot.Changed` so cross-monitor moves keep a native frame. Round-3: selection skips unchanged assets and the Changed hook parks on `closed` with a once guard; raw-view hiding was tried for the AT surface and reverted (measured: both UIA drives missed the icon with Raw set and passed after the revert), so decode state stays on ItemStatus, observable to UIA clients that ask. **Corrected 2026-09-17 (§14 panel round 4):** the earlier clause claimed an unfocusable icon announces nothing unprompted and that FlaUI misses raw-view elements as an inference; the panel falsified both wordings, now stated as the observations taken (Name is the only other automation property set; both drives red with Raw set, green after the revert).
- [x] Tab gestures, drag rectangles, and the zero-tab layout are unaffected. Done when: the tab and chrome suites stay green. Done: round-1 review caught a real regression (TabBar-local content edge used in window-space drag rects would have covered the add button); fixed by mapping through `TabRegion` at the call site with a teardown guard, plus a comment pinning `TabStripContentRight` as TabBar-local. Proof: host TabBar/Chrome/MainWindow filter shows the identical 9 failures with and without this change (pre-existing Venom-PC headless-session reds, black pixel captures plus dead input, delta 0); new `AddButtonRealClickOpensTab` clicks the add button through real hit-testing as a plain Fact (red on headless hosts exactly like its TabBarTests input siblings, of which only the HookFact middle-click test carries any gate, on hook availability rather than a display); the full TitleBarIconTests filter on the host reads 2 passed plus that expected headless red; CI at 100% with a display is the green gate and must quote green before the stamp.
- [x] Eyeball evidence of the dressed tab row is committed. Done when: the chrome crop sits beside the D01 T01 §11 crops in `resources/baseline/app/`. **Decided 2026-09-17 (§14 validation):** the window-station-less session cannot take pixel captures (measured black frames, invalid desktop handle), so the crop is deferred to D00 T02 §7, whose CI evidence pipeline captures on a display-bearing runner (capture line recorded on its item 2); presence, size, and geometry are driven here and the raster is pixel-pinned to the asset.
- [x] Commit: `"notepad-core: draw the title-bar icon"`.

**Test checkpoint:** Asset in output; presence plus geometry driven; tab suites green; evidence crop eyeballed. Cheaper substitute that fails: an icon asserted in XAML but never rendered.

> **Resolved:** 2026-09-17 | Chrome crop of the dressed tab row -> XREF: D00 T02 §7 (item: "Eyeball evidence of the dressed tab row is committed") -- crop deferred for lack of a display session (measured black captures); §7 captured it on CI and committed it beside the D01 T01 §11 crops as `resources/baseline/app/titlebar-icon-evidence.png` | closed by `bcb6bb4` (crop re-taken from the fresh frame in `91e6d46`)
> **Verified:** 2026-09-17 | §14 | Title-bar icon drawn and verified whole: 16px plus 32px rasters exported from the ico's native frames (0 byte diffs), shipped as Content with Link, output byte-identical; `TitleBarIcon` pinned left of the tab strip (16 DIP, hit-test off) with decode proven through ItemStatus (`ImageOpened`, drive waits for `loaded`) and per-scale selection with change guard plus teardown parking; drag rects mapped window-space through TabRegion (round-1 panel caught the add-button cover regression) with a real-click regression test; host TabBar/Chrome/MainWindow delta 0 (9 pre-existing headless reds both ways); chrome crop deferred to D00 T02 §7 with a parsed marker; CI 35228650168 success both jobs (Windows UI.dll 169 passed, 1 skipped, 0 failed)
> **Review:** round 5, candidate 4a0e2d2 -- Opus panel `adversarial` approve · `consistency` advisory · `integration` approve · `record` advisory, both advisories fixed in the stamp commit (Name-only automation wording in the code comment, `Corrected` marker on the round-4 rewrite). Raw findings: docs/reviews/01-notepad-core/D01-T02-s14.md
> **CRUD:** applicable | PIL exports wrote the two rasters (read back via 0-diff byte comparison against the ico frames); builds wrote binaries (read back via 0-warning summaries); UI drives launched the app (read back via ItemStatus transitions and host test output; no user data touched)
> **Duration:** 66
> **Implementer:** Muse Code (Meta Muse Spark)

## 15. Chrome Color Finetune Against Stock

Why this section exists: side by side with stock, our chrome reads slightly off (editor surface and title zone sample lighter than the captures). This section closes the gap without touching what makes the window ours: Mica stays, accent coloring stays.

**Fidelity:** stock main window in dark and light -- `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` and its `-light-` twin. Chrome surfaces match the captures within the golden tolerance; Mica and accent behavior match stock behavior, not flat colors.

**Job:** The user can hold our window against Notepad's and see the same chrome. Consumer: none, this surface is the consumer.

**Treatment:** Brush-level adjustments against same-machine stock probes, Mica and accent rules preserved. Cheaper substitute that fails the checkpoint: flat colors that match one wallpaper and break the backdrop.

**Chrome:** Consume the WinUI theme resources; adjust values, never replace the Mica backdrop or the accent pipeline. Do not invent a second theme system (D01 T02 §10 owns accents).

**Needs:** Windows host (build/test)

- -> XREF: D01 T02 §10 -- accent themes compose with this finetune; this section preserves the accent coloring §10 themes.
- -> XREF: D00 T01 §13 -- the environment gate's first proving instance; this section's display-session requirement is what the marker names.

- [ ] Same-machine stock-versus-app palette probes are captured and their sampled values recorded. Done when: the A/B numbers are quoted per surface.
- [ ] Chrome brushes match stock within tolerance with the Mica backdrop and accent-conditional rules untouched. Done when: per-surface deltas are quoted and the Mica plus accent drives stay green.
- [ ] Dark, light, and system themes are all driven. Done when: the theme matrix passes.
- [ ] Goldens refresh per procedure with diffs confined to chrome bands. Done when: inspected diffs are quoted.
- [ ] Commit: `"notepad-core: finetune chrome colors"`.

**Test checkpoint:** A/B probes recorded; deltas quoted; theme matrix green; goldens refreshed with confined diffs. Cheaper substitute that fails: eyeballed colors with no sampled numbers.

## 16. Quarantine the MenuBarTests Flakes

Why this section exists: three `MenuBarTests` failed nondeterministically on CI within the hours (details in the SOURCE line), each red-then-green with no test-affecting change between, which is exactly the D00 T02 §5 quarantine criterion. Until they are quarantined, every full run gambles on them. **Corrected 2026-09-17 (groom):** UI suites left CI the day this section was filed, so the quarantine proves on the local full run, not a main CI run; the CI signatures below stay as the filing evidence.

**Job:** The suite stays green without the flakes while their owners get a fix-or-remove window. Consumer: every local full run.

**Treatment:** Quarantine by the D00 T02 §5 procedure verbatim (prove, Skip with the quarantine stamp, quarantine-list rows), one row per test. No test logic changes; the fix-or-remove window that follows belongs to the owners, not this section. Cheaper substitute that fails the checkpoint: re-running red builds until one goes green.

- -> XREF: D00 T02 §7 -- filed from its pipeline run; the flakes blocked its first artifact.
- -> SOURCE: CI-flakes-2026-09-17 (`UI.MenuBarTests.FileSaveAllWalksDirtyTabs`: COMException UIA timeout in `WaitForNativeModalGone`, red on run 35230396785 attempt 1, green on the rerun of the same commit; `UI.MenuBarTests.ToolsMenuInvokesStats`: `Assert.NotNull` in `OpenToolsDialog`, red on run 35230230322, green on run 35230396785 whose tree differs only in workflow YAML plus TODO prose, i.e. a bit-identical test binary; `UI.MenuBarTests.FileMenuLiveAcceleratorsWork`: `Assert.NotNull`, red on run 35234746568 attempt 1, green on the rerun of the same commit. All smell like slow-runner load; the owners confirm via soak.)

- [ ] `FileSaveAllWalksDirtyTabs` carries the quarantine Skip with its signature id and quarantine-list row. Done when: the attribute names the doc entry and the row quotes both runs.
- [ ] `ToolsMenuInvokesStats` carries the quarantine Skip with its signature id and quarantine-list row. Done when: the attribute names the doc entry and the row quotes both runs.
- [ ] `FileMenuLiveAcceleratorsWork` carries the quarantine Skip with its signature id and quarantine-list row. Done when: the attribute names the doc entry and the row quotes both runs.
- [ ] A local full run is green with all three tests skipped. Done when: the run output is quoted with the 3-skip line.
- [ ] Commit: `"notepad-core: quarantine the MenuBarTests flakes"`

**Test checkpoint:** All three Skips plus all three rows land; local full run green with the skips counted. Cheaper substitute that fails: Skips without rows, or rows without the quoted proof.

## Verification

- [ ] `dotnet test` green
- [ ] Every menu item working or owner-named, proven in the local full run **Corrected 2026-09-17 (groom):** was "proven in CI"; CI runs no suites since 2026-09-17.
- [ ] `python3 scripts/todo-graph.py validate` clean
