---
schema_version: 1
id: winui-app-spine
domain: 01-notepad-core
status: draft
title: "TODO-01 -- WinUI App Spine"
depends_on: ["repo-and-toolchain"]
track: N1
---

# TODO-01 -- WinUI App Spine

> **Goal:** The app opens as a window with a tab bar, opens and saves files without data loss, and tracks dirty state per tab, matching Windows 11 Notepad.

> [!IMPORTANT]
> **Current state:** Only the `D00 T01 §2` stub window exists. No tab model, no file IO, no menus. The editor surface this spine will host is `D02 T01`'s; until it lands, sections here host a placeholder.

## Inputs

- `resources/baseline/` captures of the Notepad main window and tab bar (owned by `D00 T02 §3`)
- -> XREF: D02 T01 §1 -- the editing surface this spine hosts; the hosting contract (interface, lifetime) is settled there and consumed here

## Outcome

- The app window matches Notepad's main window layout for the shipped chrome.
- Tabs open, switch, reorder, and close with dirty-state prompts.
- Files round-trip byte-identical for supported encodings and line endings.
- Unsaved work is never lost silently: every destructive path prompts or recovers.

**Adjacency:** list=applicable @ D01 T01 §6; document=applicable @ D01 T02 §6; settings=applicable @ D01 T02 §4; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=applicable @ D01 T01 §4; reverse=applicable @ D01 T01 §7

**Adjacency rationale:** The tab bar is the list; open/save is the exchange; print is the document; close-without-save and crash recovery are the reversals. Settings live in T02 with their consumer named there.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Main window shell with menu bar host | -- |  [ ]   |
|   2   |   §2    | Tab model with dirty tracking | §1 |  [ ]   |
|   3   |   §3    | Tab bar UI: open, switch, reorder, close | §2 |  [ ]   |
|   4   |   §4    | File open with encoding detection | §2 |  [ ]   |
|   5   |   §5    | File save and Save As | §4 |  [ ]   |
|   6   |   §6    | Recent files and session restore | §5 |  [ ]   |
|   7   |   §7    | Dirty prompts and crash recovery | §3, §5 |  [ ]   |
|   8   |   §8    | File association and command-line open | §4, §6 |  [ ]   |
|   9   |   §9    | Multi-window with open-in mode | §2, §3 |  [ ]   |

---

## 1. Main Window Shell with Menu Bar Host

Why this section exists: everything visible hangs off the main window. Build the shell first so later sections have a host.

**Fidelity:** Notepad main window chrome -- `resources/baseline/main-window/`. Window frame, title bar, and menu bar placement match the capture.

**Job:** The user can open the app to a window that looks and places like Notepad. Consumer: none, this surface is the consumer.

**Treatment:** WinUI 3 `Window` with the Notepad layout. Cheaper substitute that fails the checkpoint: a default blank window with no menu host.

**Chrome:** Consume the shared Notepad-matched styles settled in this section. Do not invent a second window frame.

**Groomed 2026-09-13:** Notepad audit: theme-bound Mica and rounded corners are now explicit (was capture-implicit); the first-run What's New dialog and megaphone entry are recorded from the capture.

- [ ] `src/Notepad/MainWindow.xaml` hosts the menu bar region, tab region, editor region, and status region. Done when: all four regions exist with the Notepad layout.
- [ ] The window title follows Notepad's convention (file name, dirty marker, app name). Done when: each state renders exactly as captured.
- [ ] The window restores its size and position across launches. Done when: move, close, reopen, and the geometry matches.
- [ ] `tests/UI/MainWindowTest` drives launch and asserts the regions exist. Done when: `dotnet test --filter MainWindow` passes on a Windows runner in CI.
- [ ] The window frame uses Mica material with rounded corners, following the app theme from the D01 T02 §2 store. Done when: light, dark, and system themes each render Mica correctly against the capture. Source: https://blogs.windows.com/blog/2021/12/07/redesigned-notepad-for-windows-11-begins-rolling-out-to-windows-insiders/
- [ ] First-run shows Notepad's What's New dialog as captured, revisitable through the megaphone entry; if the capture shows it removed, the removal is recorded instead. Done when: first-run is driven. Source: https://blogs.windows.com/windows-insider/2026/01/21/notepad-and-paint-updates-begin-rolling-out-to-windows-insiders/
- [ ] Commit: `"notepad-core: build the main window shell"`

**Test checkpoint:** UI drive launches the app, asserts the four regions and the title convention, and compares against the golden capture within tolerance. Cheaper substitute that fails: regions asserted in unit tests without rendering the window.

## 2. Tab Model with Dirty Tracking

Why this section exists: tabs are the unit of work. The model must be right before any UI touches it, because every file path flows through it.

**Groomed 2026-09-13:** Notepad audit: the display-title rule for auto-named untitled tabs and a closed-tab stack for reopen are now explicit.

- [ ] `src/Notepad.Core/TabModel.cs` models the tab list: identity, file path, dirty flag, encoding, line ending. Done when: the model compiles with no UI dependency.
- [ ] Dirty tracking flips on edit and clears on save, and only on save. Done when: `tests/Unit/TabModelTest` covers edit, save, and no-op edits.
- [ ] The model notifies the UI of list and dirty changes through one observable path. Done when: two observers cannot disagree about dirty state.
- [ ] An untitled tab carries no path until first save. Done when: save on untitled routes to Save As (§5).
- [ ] An untitled tab's display title follows Notepad's auto-naming from content; the exact rule (first line, truncation) is recorded from the capture. Done when: untitled tabs render titles exactly as captured. Source: https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/
- [ ] The model keeps a closed-tab stack so recently closed tabs can reopen; depth and what is kept (path, contents, caret) are recorded from the capture. Done when: `tests/Unit/TabModelTest` covers close-then-reopen round-trips.
- [ ] Commit: `"notepad-core: add the tab model with dirty tracking"`

**Test checkpoint:** `dotnet test --filter TabModel` green, including edit-then-undo-to-clean semantics as Notepad defines them. Cheaper substitute that fails: dirty tracked in the UI layer where two paths can disagree.

## 3. Tab Bar UI: Open, Switch, Reorder, Close

Why this section exists: the tab bar is the most-touched surface in the app. It must behave exactly like Notepad's.

**Fidelity:** Notepad tab bar -- `resources/baseline/tab-bar/`. Tab order, dirty dot, close glyph, and the new-tab button match the capture.

**Job:** The user can manage open documents through the tab bar. Consumer: the editor region, which shows the active tab.

**Treatment:** WinUI `TabView` styled to the Notepad capture. Cheaper substitute that fails the checkpoint: a list box standing in for tabs.

**Chrome:** Consume the shared Notepad-matched styles. Do not invent a second tab treatment.

**Groomed 2026-09-13:** Notepad audit: the closed-tab reopen shortcut and capture-recorded overflow behavior are now explicit.

- [ ] `src/Notepad/TabBar.xaml` renders the `TabModel` list with new-tab, switch, reorder, and close. Done when: every gesture in the capture works.
- [ ] Closing a dirty tab routes to the §7 prompt, never straight to close. Done when: the UI test proves the prompt appears.
- [ ] Keyboard shortcuts for tab management match Notepad. Done when: each shortcut is driven in the UI test.
- [ ] Middle-click and context-menu tab actions match Notepad where it has them. Done when: the capture comparison covers them.
- [ ] The reopen-closed-tab shortcut reopens the most recently closed tab from the §2 stack. Done when: close-then-reopen round-trips are driven for saved and untitled tabs.
- [ ] Tab-strip overflow with many tabs is recorded from the capture (scroll, chevron, or shrink) and renders the same. Done when: an overflow drive matches the capture.
- [ ] Commit: `"notepad-core: build the tab bar UI"`

**Test checkpoint:** UI drive opens three tabs, reorders, switches, and closes each, comparing against captures; dirty close prompts. Cheaper substitute that fails: tab actions unit-tested without rendering the bar.

## 4. File Open with Encoding Detection

Why this section exists: opening must never corrupt. Detection decides the bytes' meaning, so it is tested against fixtures, not hoped for.

**Groomed 2026-09-13:** Notepad audit: EOL detection, the Open dialog, the large-file limit, and .LOG append-on-open are now explicit (EOL was only implied by §5's preserve rule).

- [ ] `src/Notepad.Core/FileIO.cs` detects BOM, UTF-8, UTF-16 LE/BE, and ANSI fallback exactly as Notepad does. Done when: the fixture matrix in `tests/Data/encodings/` passes byte-identical.
- [ ] Open failure (missing file, locked file, unreadable file) reports Notepad's message and leaves the tab list unchanged. Done when: each failure is driven.
- [ ] Files that change on disk while open are detected and the user is asked before reload. Done when: the external-change prompt is driven.
- [ ] Large files open without blocking the UI past the committed budget. Done when: the budget is recorded and measured.
- [ ] `src/Notepad.Core/FileIO.cs` detects the file's line-ending convention (CRLF, LF, CR) per Notepad's extended-EOL rules; mixed-ending behavior is recorded from the capture. Done when: the fixture matrix in `tests/Data/eol/` passes byte-identical. Source: https://devblogs.microsoft.com/commandline/extended-eol-in-notepad/
- [ ] The Open dialog defaults to Text documents (*.txt) with an All-files switch, as Notepad's. Done when: the dialog matrix is driven against the capture.
- [ ] Files past Notepad's size limit refuse with its redirect dialog instead of hanging; the exact threshold and wording are recorded from the capture. Done when: an over-limit open is driven. Source: https://en.wikipedia.org/wiki/Windows_Notepad
- [ ] A file whose first line is .LOG appends the current date and time at the end on every open, in the same format as the F5 insert (D02 T01 §5). Done when: open-append round-trips are fixture-tested. Source: https://support.microsoft.com/en-us/windows/apps/help-in-notepad
- [ ] Commit: `"notepad-core: open files with encoding detection"`

**Test checkpoint:** Encoding fixture matrix green byte-identical; failure and external-change paths driven. Cheaper substitute that fails: UTF-8-only open that mangles the rest.

## 5. File Save and Save As

Why this section exists: saving is the one path where a bug destroys user data. It is atomic, verified, and boring.

**Groomed 2026-09-13:** Notepad audit: Save As option enumeration, new-file defaults, and Save All are now explicit.

- [ ] Save writes atomically (temp file plus rename) so a crash mid-save keeps either the old or the new bytes, never a mix. Done when: a fault-injection test proves it.
- [ ] Save As offers Notepad's encodings and line endings and honors the choice. Done when: each combination round-trips byte-identical.
- [ ] Saving preserves the detected encoding and line ending unless the user changes them. Done when: open-save round-trips are byte-identical across the matrix.
- [ ] Save failure reports and keeps the dirty flag set. Done when: a read-only-destination drive proves no silent loss.
- [ ] Save As offers exactly Notepad's encoding list (ANSI, UTF-16 LE, UTF-16 BE, UTF-8, UTF-8 with BOM) and its line-ending list as captured. Done when: each offered combination round-trips byte-identical.
- [ ] New never-saved files default to UTF-8 and CRLF as captured. Done when: the defaults are recorded from a fresh install and driven. Source: https://www.thewindowsclub.com/how-to-change-the-default-character-encoding-in-notepad-on-windows-10
- [ ] Save All saves every dirty tab, routing untitled tabs through Save As per Notepad's order and cancellation. Done when: multi-tab Save All with cancellation is driven.
- [ ] Commit: `"notepad-core: save atomically with Save As"`

**Test checkpoint:** Round-trip matrix byte-identical; fault-injection save keeps old-or-new; Save As honors every offered combination. Cheaper substitute that fails: direct overwrite that can leave a truncated file.

## 6. Recent Files and Session Restore

Why this section exists: Notepad reopens where the user left off. So do we, without ever resurrecting a file the user closed on purpose.

**Fidelity:** Notepad recent-files menu and restored session -- `resources/baseline/session/`. Order and truncation match.

**Job:** The user can reopen recent files and resume the last session. Consumer: the tab model, which receives the restored list.

**Treatment:** Persisted session list with Notepad's truncation and ordering. Cheaper substitute that fails the checkpoint: restoring only the active tab.

**Chrome:** Consume the shared menu styles. Do not invent a second recent-files treatment.

**Corrected 2026-09-14:** the seed said session state stores paths only. Notepad's "open content from previous session" restores unsaved buffers too, so this section now persists unsaved content locally, plus the "When Notepad starts" preference (restore vs new window).

**Groomed 2026-09-13:** Notepad audit: the startup preference's fresh-install default is now recorded from the capture instead of unnamed.

- [ ] `src/Notepad.Core/SessionStore.cs` persists open paths, active tab, caret positions, and unsaved buffer contents. Done when: quit and relaunch restores all four, including an untitled tab with unsaved text.
- [ ] The "When Notepad starts" preference offers restore-previous-session or open-new-window, as Notepad's. Done when: both modes are driven.
- [ ] Missing or moved files are skipped with a notice, never resurrected as ghosts. Done when: the skip path is driven.
- [ ] The recent-files list matches Notepad's order, truncation, and clearing. Done when: the UI test walks all three.
- [ ] Unsaved content is stored locally only, never synced or logged, with the privacy review recorded. Done when: the store format review names every field.
- [ ] The "When Notepad starts" preference defaults to the fresh-install value recorded from the capture. Done when: a clean profile launches with the recorded default.
- [ ] Commit: `"notepad-core: restore sessions and recent files"`

**Test checkpoint:** UI drive quits with saved tabs, an untitled unsaved tab, and a dirty tab, and relaunches to all three with contents and carets; both startup modes driven; missing-file skip driven. Cheaper substitute that fails: restore that works only when every file still exists.

## 7. Dirty Prompts and Crash Recovery

Why this section exists: this section is the last line before data loss. Every destructive path prompts, and a crash recovers to a prompt, never to silence.

**Fidelity:** Notepad save prompts and recovery behavior -- `resources/baseline/prompts/`. Button order and wording match.

**Job:** The user can never lose work without choosing to. Consumer: the tab model, which only closes clean tabs unprompted.

**Treatment:** Notepad's prompt wording and button order. Cheaper substitute that fails the checkpoint: a generic OK/Cancel dialog.

**Chrome:** Consume the shared dialog styles. Do not invent a second prompt treatment.

**Corrected 2026-09-14:** the seed prompted on every close. Notepad prompts when closing an unsaved tab, but closing the window preserves the session silently for §6 to restore. This section now draws that line exactly.

- [ ] Closing an unsaved tab prompts per Notepad (save, don't save, cancel). Done when: all three answers are driven.
- [ ] Closing the window with dirty tabs preserves everything silently for §6 restore, as Notepad's. Done when: the drive proves zero prompts and full restore.
- [ ] Cancel on a tab prompt aborts that close only, leaving the tab exactly as it was. Done when: the drive proves nothing closed and nothing saved.
- [ ] Crash recovery snapshots dirty buffers periodically and offers restore on next launch. Done when: a killed-process drive recovers to the prompt.
- [ ] Recovery never overwrites the user's files without the prompt's explicit choice. Done when: the drive proves files untouched until chosen.
- [ ] Commit: `"notepad-core: prompt on dirty close and recover crashes"`

**Test checkpoint:** Tab-prompt answers driven; silent window close with full restore driven; killed-process recovery driven; files untouched until chosen. Cheaper substitute that fails: prompting on window close as if it were tab close.

## 8. File Association and Command-Line Open

Why this section exists: Notepad opens from Explorer and from the command line. An exact clone does both.

**Groomed 2026-09-13:** Notepad audit: the Jump List, Explorer file-drop, and the /P + /PT print flags are now explicit.

- [ ] Double-clicking an associated extension opens the file in the app (new window or new tab per Notepad's rule). Done when: the rule is recorded and driven.
- [ ] Command-line paths open, including multiple files and a missing file (which offers to create, per Notepad). Done when: each case is driven.
- [ ] Association setup and teardown are clean: uninstall leaves no broken associations. Done when: install and uninstall are driven on a clean VM.
- [ ] Only the extensions Notepad claims are claimed, and the claim is user-reversible. Done when: the list is recorded and the reversal driven.
- [ ] The taskbar Jump List offers recent files with pinning from the §6 store, as Notepad's. Done when: recents and pin are driven. Source: https://www.pctips.com/notepad-tips-and-tricks/
- [ ] Dropping files from Explorer onto the window opens them per the §4 path and the §9 open-in mode. Done when: single- and multi-file drops are driven.
- [ ] The /P and /PT command-line flags are verified against the real Notepad: supported flags print through D01 T02 §5, removed flags are recorded as removed with the version note. Done when: the verification record exists and supported flags are driven.
- [ ] Commit: `"notepad-core: associate files and open from the command line"`

**Test checkpoint:** Association, multi-file open, missing-file offer, and clean uninstall all driven on a clean VM. Cheaper substitute that fails: association tested only on the dev machine.

## 9. Multi-Window with Open-In Mode

Why this section exists: Notepad opens new windows, and the "Opening files" setting decides tab vs window. Filed by groom 2026-09-14: the seed assumed one window.

**Fidelity:** Notepad multi-window behavior -- `resources/baseline/windows/`. New-window command, placement, and the open-in setting match the capture.

**Job:** The user can work in several windows as in Notepad. Consumer: the tab model, which lives per window.

**Treatment:** Per-window tab lists with the open-in setting. Cheaper substitute that fails the checkpoint: everything forced into one window.

**Chrome:** Consume the shared window styles. Do not invent a second window treatment.

**Groomed 2026-09-13:** Notepad audit: tab drag-out to a new window and drag-in docking are now explicit.

- [ ] The new-window command (menu, shortcut) opens a window as Notepad's. Done when: the command is driven.
- [ ] The "Opening files" setting (new tab vs new window) is honored everywhere files open. Done when: both modes are driven.
- [ ] Windows are independent: tabs, dirty state, and undo never cross windows. Done when: the isolation test passes.
- [ ] Session restore reopens the window set as Notepad does. Done when: the multi-window restore is driven.
- [ ] Dragging a tab out of the tab strip detaches it into a new window, and dragging a tab into another window's strip docks it there, per Notepad's threshold and cues. Done when: both directions are driven against the capture. Source: https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/
- [ ] Commit: `"notepad-core: support multiple windows"`

**Test checkpoint:** New window, open-in modes, isolation, and multi-window restore driven. Cheaper substitute that fails: multi-window that shares one tab list.

## Verification

- [ ] `dotnet test` green
- [ ] Round-trip matrix byte-identical across encodings and line endings
- [ ] No destructive path without its prompt, all driven
- [ ] `python3 scripts/todo-graph.py validate` clean
