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
|   1   |   §1    | Main window shell with menu bar host | -- |  [x]   |
|   2   |   §2    | Tab model with dirty tracking | §1 |  [x]   |
|   3   |   §3    | Tab bar UI: open, switch, reorder, close | §2 |  [x]   |
|   4   |   §4    | File open with encoding detection | §2 |  [ ]   |
|   5   |   §5    | File save and Save As | §4 |  [ ]   |
|   6   |   §6    | Recent files and session restore | §5 |  [ ]   |
|   7   |   §7    | Dirty prompts and crash recovery | §3, §5 |  [ ]   |
|   8   |   §8    | File association and command-line open | §4, §6 |  [ ]   |
|   9   |   §9    | Multi-window with open-in mode | §2, §3 |  [ ]   |
|  10   |   §10   | Window border parity repair | §1 |  [ ]   |

---

## 1. Main Window Shell with Menu Bar Host

> **Started:** 2026-09-14T06:02:00Z

Why this section exists: everything visible hangs off the main window. Build the shell first so later sections have a host.

**Fidelity:** Notepad main window chrome -- `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png`. Window frame, title bar, and menu bar placement match the capture.

**Job:** The user can open the app to a window that looks and places like Notepad. Consumer: none, this surface is the consumer.

**Treatment:** WinUI 3 `Window` with the Notepad layout. Cheaper substitute that fails the checkpoint: a default blank window with no menu host.

**Chrome:** Consume the shared Notepad-matched styles settled in this section. Do not invent a second window frame.

**Groomed 2026-09-13:** Notepad audit: theme-bound Mica and rounded corners are now explicit (was capture-implicit); the first-run What's New dialog and megaphone entry are recorded from the capture.

**Corrected 2026-09-14:** the seed named `src/Notepad/MainWindow.xaml`, `tests/UI/MainWindowTest`, and `resources/baseline/main-window/`; the app project is `src/IntelligentNotepad/` (D00 T01 §2), the test file follows the `*Tests` convention, and the §3 store is flat with `stock/notepad-main-n11.2607.14.0-win25h2.png` as the main-window capture. Items 3 and 5 persist through a local seam the D01 T02 §2 store adopts, since the store ships later in this phase.

- [x] `src/IntelligentNotepad/MainWindow.xaml` hosts the menu bar region, tab region, editor region, and status region. Done when: all four regions exist with the Notepad layout.
- [x] The window title follows Notepad's convention (file name, dirty marker, app name). Done when: each state renders exactly as captured.
- [x] The window restores its size and position across launches, persisted in local app data behind a seam the D01 T02 §2 store adopts. Done when: move, close, reopen, and the geometry matches.
- [x] `tests/UI/MainWindowTests.cs` drives launch and asserts the regions exist. Done when: `dotnet test --filter MainWindow` passes on a Windows runner in CI.
- [x] The window frame uses Mica material with rounded corners, following the app theme resolved through the same seam the D01 T02 §2 store adopts. Done when: light, dark, and system themes each render Mica correctly against the captures. Source: https://blogs.windows.com/blog/2021/12/07/redesigned-notepad-for-windows-11-begins-rolling-out-to-windows-insiders/
- [x] First-run shows Notepad's What's New dialog as captured, revisitable through the megaphone entry; if the capture shows it removed, the removal is recorded instead. Done when: first-run is driven. Source: https://blogs.windows.com/windows-insider/2026/01/21/notepad-and-paint-updates-begin-rolling-out-to-windows-insiders/
- [x] Commit: `"notepad-core: build the main window shell"`

**Test checkpoint:** UI drive launches the app, asserts the four regions and the title convention, and compares against the golden capture within tolerance. Cheaper substitute that fails: regions asserted in unit tests without rendering the window.

> **Verified:** 2026-09-14 | §1 | Shell with 4 UIA regions, title convention (5 theory cases plus live asserts), geometry restore, light/dark/system Mica with brightness proof, first-run plus megaphone dialog drives, shell golden in tolerance; UI 9/9, Unit 7/7, Protocol 8/8 locally and in CI both jobs (run 34813967613) after the artifact-proven first-run red (run 34812982991, fixed by seam-seeding captures); validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates 8d7c266 93bf74f 79f6786 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s1.md
> **CRUD:** applicable | title composer wrote window titles (read back via 5 cases plus live asserts); seam wrote geometry, theme, seen-flag (read back via relaunch, brightness polls, flag polls); dialog wrote dismissals (read back via close plus persist); captures wrote goldens (read back via comparison fractions and the 3.537% red artifact)
> **Duration:** 43
> **Implementer:** Muse Code (Meta Muse Spark)

## 2. Tab Model with Dirty Tracking

> **Started:** 2026-09-14T06:50:00Z

Why this section exists: tabs are the unit of work. The model must be right before any UI touches it, because every file path flows through it.

**Groomed 2026-09-13:** Notepad audit: the display-title rule for auto-named untitled tabs and a closed-tab stack for reopen are now explicit.

**Corrected 2026-09-14:** the seed named `tests/Unit/TabModelTest` (twice); the suite convention is `*Tests` (`tests/Unit/TabModelTests.cs`). The `--filter TabModel` checkpoint is unchanged.

- [x] `src/Notepad.Core/TabModel.cs` models the tab list: identity, file path, dirty flag, encoding, line ending. Done when: the model compiles with no UI dependency.
- [x] Dirty tracking flips on edit and clears on save, and only on save. Done when: `tests/Unit/TabModelTests` covers edit, save, and no-op edits.
- [x] The model notifies the UI of list and dirty changes through one observable path. Done when: two observers cannot disagree about dirty state.
- [x] An untitled tab carries no path until first save. Done when: save on untitled routes to Save As (§5).
- [x] An untitled tab's display title follows Notepad's auto-naming from content; the exact rule (first line, truncation) is recorded from the capture. Done when: untitled tabs render titles exactly as captured. Source: https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/
- [x] The model keeps a closed-tab stack so recently closed tabs can reopen; depth and what is kept (path, contents, caret) are recorded from the capture. Done when: `tests/Unit/TabModelTests` covers close-then-reopen round-trips.
- [x] Commit: `"notepad-core: add the tab model with dirty tracking"`

**Test checkpoint:** `dotnet test --filter TabModel` green, including edit-then-undo-to-clean semantics as Notepad defines them. Cheaper substitute that fails: dirty tracked in the UI layer where two paths can disagree.

> **Verified:** 2026-09-14 | §2 | Tab model with dirty tracking, auto-naming (first-line/trim/35), observable path, SaveAs routing, unbounded closed stack with proven skip rules; TabModel 24/24 locally and Unit 31/31 in CI both jobs (run 34816231797); mutation probe on the discard guard red then green; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates f16aeae a0dbe54 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s2.md
> **CRUD:** applicable | edits wrote dirty plus display names (read back via IsDirty and DisplayName asserts); closes wrote stack entries or skips (read back via entry fields and empty-stack asserts); reopens wrote tabs (read back via path, contents, dirty, LIFO order); observers wrote event streams (read back via identical-sequence assert)
> **Duration:** 28
> **Implementer:** Muse Code (Meta Muse Spark)

## 3. Tab Bar UI: Open, Switch, Reorder, Close

> **Started:** 2026-09-14T07:25:00Z

Why this section exists: the tab bar is the most-touched surface in the app. It must behave exactly like Notepad's.

**Fidelity:** Notepad tab bar -- `resources/baseline/stock/notepad-tabs-n11.2607.14.0-win25h2.png`. Tab order, dirty dot, close glyph, and the new-tab button match the capture.

**Job:** The user can manage open documents through the tab bar. Consumer: the editor region, which shows the active tab.

**Treatment:** WinUI `TabView` styled to the Notepad capture. Cheaper substitute that fails the checkpoint: a list box standing in for tabs.

**Chrome:** Consume the shared Notepad-matched styles. Do not invent a second tab treatment.

**Groomed 2026-09-13:** Notepad audit: the closed-tab reopen shortcut and capture-recorded overflow behavior are now explicit.

**Corrected 2026-09-14:** the seed named `src/Notepad/TabBar.xaml`; the app project is `src/IntelligentNotepad/`. The tab-close prompt dialog is implemented here per the recorded wording (title "Notepad", "Do you want to save changes to {name}?", Save / "Don't save" / Cancel) with Don't-save and Cancel driven; §7 reuses the dialog for the full answer matrix, window-close silence, and crash recovery. No file IO exists yet, so the UI drives untitled flows while saved round-trips stay model-level until §4, which re-drives them with real files; the untitled reopen drive asserts Notepad's no-restore parity (Don't-save closes never reopen, probed 0/11). The shortcut list is recorded live in-run since the shortcuts guide link is dead.

**Corrected 2026-09-14 (reorder):** live probes show stock Notepad tabs do NOT drag-reorder (three negative probes: named AAA/BBB tabs dragged slowly across an on-screen foreground strip twice plus an identity-tracked drag, order unchanged every time), so CanReorderTabs stays off as parity and the first row plus the checkpoint verify a drag attempt leaves the order unchanged. The dirty dot sits where the X was and the X hides until hover (D01 T01 §2 recon). Ctrl+Shift+T re-verified live (a Don't-save close yields no reopen); the prompt names untitled tabs "{first-line}.txt" (single observation, §7 re-verifies); closing the last tab leaves a live zero-tab window (unprobed default).

- [x] `src/IntelligentNotepad/TabBar.xaml` renders the `TabModel` list with new-tab, switch, and close, and no-reorder parity. Done when: every gesture in the capture works and a drag attempt leaves the order unchanged.
- [x] Closing a dirty tab routes to the §7 prompt, never straight to close. Done when: the UI test proves the prompt appears.
- [x] Keyboard shortcuts for tab management match Notepad. Done when: each shortcut is driven in the UI test.
- [x] Middle-click and context-menu tab actions match Notepad where it has them. Done when: the capture comparison covers them.
- [x] The reopen-closed-tab shortcut reopens the most recently closed tab from the §2 stack. Done when: close-then-reopen round-trips are driven for saved and untitled tabs.
- [x] Tab-strip overflow with many tabs is recorded from the capture (scroll, chevron, or shrink) and renders the same. Done when: an overflow drive matches the capture.
- [x] Commit: `"notepad-core: build the tab bar UI"`

**Test checkpoint:** UI drive opens three tabs, attempts reorder (order unchanged), switches, and closes each, comparing against captures; dirty close prompts. Cheaper substitute that fails: tab actions unit-tested without rendering the bar.

> **Verified:** 2026-09-14 | §3 | Tab bar UI: TabView strip with new-tab, switch, close glyph, Ctrl+T/W/Tab/1-9, Ctrl+Shift+T, 4-item context menu, middle-click close via low-level hook, shrink-to-fit overflow, dirty prompt with cancel-keeps-tab; UI 18/18 (9 TabBar, 3 consecutive 9/9 runs), Unit 31/31, Protocol 8/8, Smoke 1/1 on Windows, neutral suite green on Linux, build 0 warnings, golden refreshed and in tolerance; two transient flakes disclosed (unknown 8/9 once, empty TabItems query once, both green on rerun, latter covered by polling helper); validate 0 fatal; self-test 391/391
> **Review:** round 1, candidate fea3412 -- `adversarial` advisory · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s3.md
> **CRUD:** applicable | tab gestures wrote model tabs (read back via UIA counts, names, content asserts); edits wrote dirty plus display names (read back via dot glyph, title marker, prompt naming); closes wrote removals and stack entries (read back via counts, survivor contents, reopen no-ops); dialog wrote answers (read back via tab kept on Cancel, closed on Don't-save); captures wrote the refreshed golden (read back via in-tolerance comparison)
> **Duration:** 125
> **Implementer:** Muse Code (Meta Muse Spark)

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

## 10. Window Border Parity Repair

Why this section exists: the operator viewed the running app over RDP on Conclave-PC and reported the window border renders wrong. §1 shipped the frame green on CI, so this is new granularity on shipped work, not a §1 reopen. The app itself runs correctly there since the hook-degrade fix (window `Untitled - Intelligent Notepad` verified live in the console session): only the border chrome is in question.

**Fidelity:** Notepad main window border -- `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` and its `-light-` twin. Border thickness, color, and corner radius match the capture on every side.

**Job:** The user can open the app to a window whose border is indistinguishable from Notepad's. Consumer: none, this surface is the consumer.

**Treatment:** Root-cause repair of the frame style; the diagnosis names the exact setting. Cheaper substitute that fails the checkpoint: a cosmetic overlay that matches at one size or theme.

**Chrome:** Consume the shared Notepad-matched styles. Do not invent a second window frame.

**Needs:** Windows host (build/test)

- [ ] Capture the defect on Conclave-PC through the PMV2-aware PrintWindow path (PerMonitorV2 thread context plus PrintWindow full-content, which reads the DWM redirection bitmap regardless of viewer state). Done when: a non-black capture shows our window and the wrong border is described in pixels (thickness, color, radius, affected sides). Cheaper substitute that fails: diagnosing from the one-line operator report without a capture, or capturing unaware (reads virtualize to black at 150 percent session DPI). Source: operator RDP observation 2026-09-14.
- [ ] Compare the border against `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` plus the `-light-` twin. Done when: every differing border attribute is listed with stock-vs-ours measurements.
- [ ] Locate the root cause in `src/IntelligentNotepad/MainWindow.xaml` and `src/IntelligentNotepad/MainWindow.xaml.cs` (frame style, `ExtendsContentIntoTitleBar`, `AppWindow`/`OverlappedPresenter` settings, Mica brush, theme seam). Done when: the single setting or style producing the wrong border is named with its code reference, and sibling causes (DPI, theme, presenter) are ruled out with evidence.
- [ ] Fix at the root cause in the app sources: no overlay, mask, or per-host special case. Done when: the change is the minimal edit the diagnosis names and the comment cites the stock behavior. Cheaper substitute that fails: padding or a repaint that matches at one DPI only.
- [ ] Re-capture on Conclave-PC with the viewer attached and compare border pixels against the stock capture. Done when: the fresh capture matches stock on every attribute listed in item 2.
- [ ] Extend `tests/UI/GoldenComparisonTests.cs` if the border region sat outside the compared area; refresh the golden only if the old golden froze the defect, recording why. Done when: the suite asserts the corrected border and `dotnet test tests/UI` on Conclave-PC shows no border-related failures; the 6 input-injection failures and the hook skip stay tracked in D00 T01 §8.
- [ ] Record the VM capture procedure (PMV2-aware captures; unaware reads virtualize to black at 150 percent session DPI) in `docs/testing.md`. Done when: a cold agent captures pixels by following the doc.
- [ ] Found 2026-09-14: drive the border regression capture through a PMV2-aware placed-window path (`UiCapture`-style Place plus settle inside `UiDpi.Enter`, as `tests/UI/UiCapture.cs` does), since unaware captures virtualize to black at 150 percent session DPI. Done when: the regression test's capture is verified non-black before its border asserts run.
- [ ] Commit: `"notepad-core: repair the window border to stock parity"`

**Test checkpoint:** A Conclave-PC capture of our window matches the stock border capture attribute-for-attribute; `dotnet test tests/UI` on Conclave-PC shows no border-related failures (input failures tracked in D00 T01 §8); the unaware-capture cause recorded. Cheaper substitute that fails: a fix verified only on CI's 800x600 dark render.

## Verification

- [ ] `dotnet test` green
- [ ] Round-trip matrix byte-identical across encodings and line endings
- [ ] No destructive path without its prompt, all driven
- [ ] `python3 scripts/todo-graph.py validate` clean
