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
>
> **Corrected 2026-09-14 (phase-1 run 2):** §§1-3 have shipped since: the window shell with menu host, the tab model with dirty tracking, and the tab bar UI all exist. File IO (§§4-5) is still missing; later sections still host a placeholder until D02 T01 lands.

## Inputs

- `resources/baseline/` captures of the Notepad main window and tab bar (owned by `D00 T02 §3`)
- -> XREF: D02 T01 §1 -- the editing surface this spine hosts; the hosting contract (interface, lifetime) is settled there and consumed here
- -> XREF: D07 T01 §1 -- the package consumes `resources/notepad.ico` for its visuals; §11 wires the dev surface only

## Outcome

- The app window matches Notepad's main window layout for the shipped chrome.
- Tabs open, switch, reorder, and close with dirty-state prompts.
- Files round-trip byte-identical for supported encodings and line endings.
- Unsaved work is never lost silently: every destructive path prompts or recovers.

**Adjacency:** list=applicable @ D01 T01 §6; document=applicable @ D01 T02 §5; settings=applicable @ D01 T02 §2; reporting=not-applicable (a text editor reports nothing); notifications=not-applicable (no notification surface in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=applicable @ D01 T01 §4; reverse=applicable @ D01 T01 §7

**Adjacency rationale:** The tab bar is the list; open/save is the exchange; print is the document; close-without-save and crash recovery are the reversals. Settings live in T02 with their consumer named there. The §16 versions list and the §17 template picker follow the §6 list treatment.

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
|  11   |   §11   | App icon wiring | §1 |  [ ]   |
|  12   |   §12   | Split view | §1, §2, D02 T01 §1 |  [ ]   |
|  13   |   §13   | Pinned tabs | §2, §6 |  [ ]   |
|  14   |   §14   | Text statistics panel | §1 |  [ ]   |
|  15   |   §15   | Distraction-free focus mode | §1, D01 T02 §1 |  [ ]   |
|  16   |   §16   | File snapshots | §5, §7 |  [ ]   |
|  17   |   §17   | New-file templates | §2 |  [ ]   |
|  18   |   §18   | Export as Markdown, HTML, plain text | §5 |  [ ]   |
|  19   |   §19   | Encrypted notes | §4, §5 |  [ ]   |
|  20   |   §20   | Backup on save | §5 |  [ ]   |
|  21   |   §21   | Reload prompt on external change | §4 |  [ ]   |
|  22   |   §22   | First-line titles for untitled tabs | §2 |  [ ]   |
|  23   |   §23   | Side-by-side tab diff | §2, §12 |  [ ]   |
|  24   |   §24   | Share target | §1, §2 |  [ ]   |
|  25   |   §25   | Jump list tasks | §2, §6, §13 |  [ ]   |
|  26   |   §26   | Protocol handler | §4, §8 |  [ ]   |
|  28   |   §28   | UIA tab accessibility names | §3 |  [ ]   |
|  29   |   §29   | Open with explicit encoding | §4 |  [ ]   |

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

> **Started:** 2026-09-14T22:04:41Z

Why this section exists: opening must never corrupt. Detection decides the bytes' meaning, so it is tested against fixtures, not hoped for. Opening is the app's file import: bytes are read from disk into a tab.

**Groomed 2026-09-13:** Notepad audit: EOL detection, the Open dialog, the large-file limit, and .LOG append-on-open are now explicit (EOL was only implied by §5's preserve rule).

- [x] `src/Notepad.Core/FileOpen.cs` detects BOM, UTF-8, UTF-16 LE/BE, and ANSI fallback exactly as Notepad does. **Corrected 2026-09-14:** the seed named it `FileIO.cs`; CA1724 forbids the name (clashes with `Microsoft.VisualBasic.FileIO`). Done when: the fixture matrix in `tests/Fixtures/encodings/` passes byte-identical. **Corrected 2026-09-14:** the seed said `tests/Data/encodings/`; fixtures live in `tests/Fixtures/` (no `tests/Data` exists). Probed 2026-09-15: stock agrees on all 12 fixtures (1252 fallback, BOM-less UTF-16 both ways, invalid-UTF-8 to ANSI, empty to UTF-8); segment names match the §5 list exactly. Deliberate divergence: stock reads UTF-32 BOMs as UTF-16 (lossy); we decode UTF-32 correctly so round-trips never corrupt.
- [x] Open failure (missing file, locked file, unreadable file) reports Notepad's message and leaves the tab list unchanged. Done when: each failure is driven. Probed 2026-09-15: missing shows "The system cannot find the path specified.", locked shows "The process cannot access the file because it is being used by another process." (both OK-only, title "Notepad", captures in `resources/baseline/stock/`); a pagefile attempt yields the lock message. True ACL-denied is unstageable in an admin context, so unreadable shows the OS message in the same dialog shape (default, costs one string). **Corrected 2026-09-15:** the probe note titled our dialog "Intelligent Notepad" per §1, but §1 governs window titles only; stock titles the dialog "Notepad" (captures) and the stamped §3 prompt uses "Notepad" (`SavePromptDialog`), so ours is "Notepad" (`OpenMessages.DialogTitle`). Strings and mapping ship here and are driven (`MissingFileReportsNotFoundAndLeavesTabsAlone`, `LockedFileReportsLocked` with the OS message in Detail, `FailureMappingCoversKnownExceptionsAndRethrowsUnknown`, `FailureMessagesMatchStockVerbatim`, `UnreadablePrefersLiveOsMessageOverFallback`; Unreadable has no end-to-end open, unstageable as noted above); the rendered OK dialog lands with the D01 T02 §1 Open trigger, which owns the first open entry point.
- [x] Files that change on disk while open are detected. Done when: the watcher fires on external change. **Corrected 2026-09-14 (phase-1 run 2):** the reload prompt UI is D01 T01 §21 here (it deps this section); this item owns detection only. **Driven 2026-09-15:** `WatcherFiresWhenFileChanges` (shipped in the run-2 pass; box ticked now).
- [x] Opening a path that already has a tab focuses the existing tab instead of opening a duplicate. Done when: the dedup is driven. **Added 2026-09-14 (phase-1 run 2):** two tabs on one path invite dual-write data loss; focus-existing is the default, stock-confirmed 2026-09-15 (second open focuses, no new tab).
- [x] Large files open without blocking the UI: chunked/async open with progress past the threshold recorded here. Done when: a large-file open stays responsive and the threshold is recorded. **Corrected 2026-09-14:** the seed said "the committed budget", which D02 T01 §7 owns; this item owns the open-path threshold only. Recorded 2026-09-15: the threshold is 1 MiB (`DefaultProgressThresholdBytes`); stock opens 64 MiB in ~13 s for scale. **Driven 2026-09-15:** `ProgressReportsPastThresholdAndStaysSilentBelow` plus `LargeFileOpenReportsProgressAtScale` (4 MiB through the default threshold, final report equals length).
- [x] `src/Notepad.Core/FileOpen.cs` detects the file's line-ending convention (CRLF, LF, CR) per Notepad's extended-EOL rules; mixed-ending behavior is recorded from the capture. Done when: the fixture matrix in `tests/Fixtures/eol/` passes byte-identical. Source: https://devblogs.microsoft.com/commandline/extended-eol-in-notepad/ **Corrected 2026-09-14:** same `tests/Data/` to `tests/Fixtures/` move as item 1; the seed named the file `FileIO.cs` (CA1724, see item 1). Probed 2026-09-15: plurality wins, LF beats CR on ties, empty defaults CRLF; segments read "Windows (CRLF)", "Unix (LF)", "Macintosh (CR)" (consumed by D01 T02 §4).
- [x] The Open dialog defaults to Text documents (*.txt) with an All-files switch, as Notepad's. Done when: the dialog matrix is driven against the capture. Probed 2026-09-15: type defaults to "Text documents (*.txt)", Encoding to "Auto-Detect" (capture `resources/baseline/stock/notepad-open-dialog-n11.2607.14.0-win25h2.png`). We always auto-detect at open, matching the default; explicit-encoding open is §29 here (gap: stock offers it, this item owns the defaults only). The filter spec ships here as `OpenDialogDefaults` and is driven (`OpenDialogDefaultsToTextDocumentsWithAllFilesSwitch`); applying it to the picker lands with the D01 T02 §1 Open trigger.
- [x] Files past our size limit refuse with an OK notice in stock's shape instead of hanging; the limit is 1 GiB (`OpenOptions.DefaultMaxBytes`, engineering: whole-file reads cap at 2 GiB) with the wording recorded here. Done when: an over-limit open is driven (tests pass small values; the app passes the default). **Corrected 2026-09-15:** the seed's Wikipedia redirect dialog does not exist in stock 11.2607 (probed: 64/256/512 MiB all open, no refusal); our wording "The file is too large to open." with title "Notepad" (**Corrected 2026-09-15:** same title fix as item 2; stock shape and title, our wording) is honest non-parity, recorded here. The string ships here in `OpenMessages` and is driven (`OverLimitFileReportsTooLarge` with small MaxBytes, wording in `FailureMessagesMatchStockVerbatim`); the rendered notice lands with the D01 T02 §1 Open trigger.
- [x] A file whose first line is .LOG appends the current date and time at the end on every open, in the format recorded here from the capture (D02 T01 §5's F5 insert matches this recording). Done when: open-append round-trips are fixture-tested. Source: https://support.microsoft.com/en-us/windows/apps/help-in-notepad **Corrected 2026-09-14:** the seed pointed at D02 T01 §5's format, but §5 ships later; §4 records the format first. Probed 2026-09-15: stock appends eol plus stamp plus eol (file bytes end "…2026/09/15 CRLF"); the stamp is short-time, space, short-date in the current culture (`LogTimestamp.Format`); case-sensitive confirmed (lowercase `.log` unstamped).
- [x] Commit: `"notepad-core: open files with encoding detection"`

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
- [ ] Session restore reopens the window set as Notepad does. Done when: the multi-window restore is driven. **Moved 2026-09-14 (phase-1 run 2)** from §9 item 4: restore is this section here.
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
- [ ] Command-line paths open, including multiple files , a missing file (which offers to create, per Notepad), and large/over-limit files. Done when: each case is driven. **Corrected 2026-09-14 (phase-1 run 2):** these drives re-prove §4 failure dialogs (wording recorded there), responsiveness, and redirect in situ; §4 stamps on its neutral proof plus this forward cover.
- [ ] Association setup and teardown are clean: uninstall leaves no broken associations. Done when: install and uninstall are driven in Windows Sandbox. **Corrected 2026-09-14:** VM testing retired; Sandbox is the clean machine now.
- [ ] Only the extensions Notepad claims are claimed, and the claim is user-reversible. Done when: the list is recorded and the reversal driven.
- [ ] The taskbar Jump List offers recent files with pinning from the §6 store, as Notepad's. Done when: recents and pin are driven. Source: https://www.pctips.com/notepad-tips-and-tricks/
- [ ] Dropping files from Explorer onto the window opens them per the §4 path and the §9 open-in mode. Done when: single- and multi-file drops are driven.
- [ ] The /P and /PT command-line flags are verified against the real Notepad: supported flags print through D01 T02 §5, removed flags are recorded as removed with the version note. Done when: the verification record exists and supported flags are driven.
- [ ] Commit: `"notepad-core: associate files and open from the command line"`

**Test checkpoint:** Association, multi-file open, missing-file offer, and clean uninstall all driven in Windows Sandbox. Cheaper substitute that fails: association tested only on the dev machine.

## 9. Multi-Window with Open-In Mode

> **Started:** 2026-09-14T22:14:18Z

Why this section exists: Notepad opens new windows, and the "Opening files" setting decides tab vs window. Filed by groom 2026-09-14: the seed assumed one window.

**Fidelity:** Notepad multi-window behavior -- `resources/baseline/windows/`. New-window command, placement, and the open-in setting match the capture.

**Job:** The user can work in several windows as in Notepad. Consumer: the tab model, which lives per window.

**Treatment:** Per-window tab lists with the open-in setting.

> **Moved 2026-09-14 (phase-1 run 2):** item 4 (multi-window restore) to §6: restore is that section here; §9 consumes it. Cheaper substitute that fails the checkpoint: everything forced into one window.

**Chrome:** Consume the shared window styles. Do not invent a second window treatment.

**Groomed 2026-09-13:** Notepad audit: tab drag-out to a new window and drag-in docking are now explicit.

- [ ] The new-window command (menu, shortcut) opens a window as Notepad's. Done when: the command is driven.
- [ ] The "Opening files" setting (new tab vs new window) is honored everywhere files open. Done when: both modes are driven. **Corrected 2026-09-14 (phase-1 run 2):** end-to-end honor is driven at §8-time (command-line opens in each mode) and D01 T02 §1-time (File menu); this section proves the mode value and routing.
- [ ] Windows are independent: tabs, dirty state, and closed stacks never cross windows. Done when: the isolation test passes. **Corrected 2026-09-14 (phase-1 run 2):** undo isolation moved to D02 T01 §4 (noted there); undo does not exist until D02 lands.
- [ ] Dragging a tab out of the tab strip detaches it into a new window, and dragging a tab into another window's strip docks it there, per Notepad's threshold and cues. Done when: both directions are driven against the capture. Source: https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/
- [ ] Commit: `"notepad-core: support multiple windows"`

**Test checkpoint:** New window, open-in modes, and isolation driven (restore is now §6 here). Cheaper substitute that fails: multi-window that shares one tab list.

## 10. Window Border Parity Repair

> **Moved:** 2026-09-14 to docs/testing.md (operator instruction: Conclave-PC VM testing retired; the border defect was VM-session-only and the host renders stock parity, proven by FreshCaptureMatchesGolden green plus local pixel inspection).

Why this section exists: the operator viewed the running app over RDP on Conclave-PC and reported the window border renders wrong. §1 shipped the frame green on CI, so this is new granularity on shipped work, not a §1 reopen. The app itself runs correctly there since the hook-degrade fix (window `Untitled - Intelligent Notepad` verified live in the console session): only the border chrome is in question.

**Fidelity:** Notepad main window border -- `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` and its `-light-` twin. Border thickness, color, and corner radius match the capture on every side.

**Job:** The user can open the app to a window whose border is indistinguishable from Notepad's. Consumer: none, this surface is the consumer.

**Treatment:** Root-cause repair of the frame style; the diagnosis names the exact setting. Cheaper substitute that fails the checkpoint: a cosmetic overlay that matches at one size or theme.

**Chrome:** Consume the shared Notepad-matched styles. Do not invent a second window frame.

**Needs:** Windows host (build/test)

- [ ] ~~Capture the defect on Conclave-PC through the PMV2-aware PrintWindow path (PerMonitorV2 thread context plus PrintWindow full-content, which reads the DWM redirection bitmap regardless of viewer state). Done when: a non-black capture shows our window and the wrong border is described in pixels (thickness, color, radius, affected sides). Cheaper substitute that fails: diagnosing from the one-line operator report without a capture, or capturing unaware (reads virtualize to black at 150 percent session DPI). Source: operator RDP observation 2026-09-14.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Compare the border against `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` plus the `-light-` twin. Done when: every differing border attribute is listed with stock-vs-ours measurements.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Locate the root cause in `src/IntelligentNotepad/MainWindow.xaml` and `src/IntelligentNotepad/MainWindow.xaml.cs` (frame style, `ExtendsContentIntoTitleBar`, `AppWindow`/`OverlappedPresenter` settings, Mica brush, theme seam). Done when: the single setting or style producing the wrong border is named with its code reference, and sibling causes (DPI, theme, presenter) are ruled out with evidence.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Fix at the root cause in the app sources: no overlay, mask, or per-host special case. Done when: the change is the minimal edit the diagnosis names and the comment cites the stock behavior. Cheaper substitute that fails: padding or a repaint that matches at one DPI only.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Re-capture on Conclave-PC with the viewer attached and compare border pixels against the stock capture. Done when: the fresh capture matches stock on every attribute listed in item 2.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Extend `tests/UI/GoldenComparisonTests.cs` if the border region sat outside the compared area; refresh the golden only if the old golden froze the defect, recording why. Done when: the suite asserts the corrected border and `dotnet test tests/UI` on Conclave-PC shows no border-related failures; the 6 input-injection failures and the hook skip stay tracked in D00 T01 §8.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Record the VM capture procedure (PMV2-aware captures; unaware reads virtualize to black at 150 percent session DPI) in `docs/testing.md`. Done when: a cold agent captures pixels by following the doc.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Found 2026-09-14: drive the border regression capture through a PMV2-aware placed-window path (`UiCapture`-style Place plus settle inside `UiDpi.Enter`, as `tests/UI/UiCapture.cs` does), since unaware captures virtualize to black at 150 percent session DPI. Done when: the regression test's capture is verified non-black before its border asserts run.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] Commit: `"notepad-core: repair the window border to stock parity"`

**Test checkpoint:** A Conclave-PC capture of our window matches the stock border capture attribute-for-attribute; `dotnet test tests/UI` on Conclave-PC shows no border-related failures (input failures tracked in D00 T01 §8); the unaware-capture cause recorded. Cheaper substitute that fails: a fix verified only on CI's 800x600 dark render.

## 11. App Icon Wiring

> **Started:** 2026-09-14T22:14:51Z

Why this section exists: the operator supplied the app icon. It must show in the exe, the window chrome, and the taskbar with no default glyph anywhere.

**Fidelity:** new build, no baseline (operator-supplied `resources/notepad.ico`: 256px RGBA plus 16/32/48/64/72/128).

**Job:** The user can recognize the app in the taskbar and window chrome. Consumer: the shell, which paints but never stores.

**Treatment:** Exe icon from the asset via the project plus `AppWindow.SetIcon` for the window chrome; the taskbar follows the exe. Cheaper substitute that fails the checkpoint: a window-only icon with a default exe glyph.

**Chrome:** Consume the supplied asset. Do not redraw or recolor it.

**Needs:** Windows host (build/test)

- [x] The build embeds `resources/notepad.ico` as the exe icon in `src/IntelligentNotepad/IntelligentNotepad.csproj`. Done when: the built exe shows the icon in Explorer. Proven 2026-09-14: the extracted associated icon matches the asset 0/1024 pixels (byte proof for the Explorer eyeball).
- [ ] The main window sets the icon from the asset at startup in `src/IntelligentNotepad/MainWindow.xaml.cs`. Done when: window captures show it.
- [ ] Taskbar and window chrome show the asset with no default glyph anywhere. Done when: taskbar and window captures show it (Alt+Tab follows the exe by platform contract).
- [ ] Commit: `"notepad-core: wire the app icon"`

**Test checkpoint:** Exe, window, and taskbar captures show the asset; MSIX visual assets stay D07 T01 §1's. Cheaper substitute that fails: the icon in one place only.

## 12. Split View

> **Moved:** 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §16; phase-1 run 2 cycle repair: split needs live editor views, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

- [ ] ~~Split one file into two views on the same buffer, edits visible in both. Done when: typing in one pane appears in the other under host drive.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Split two different files side by side. Done when: each pane shows its file with independent dirty state.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Panes scroll and edit independently under host drive. Done when: scroll position and caret do not leak across panes.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Keyboard focus moves between panes and is announced. Done when: the shortcut moves focus both ways with UIA announcement.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] Commit: `"editor: split the view"`

**Test checkpoint:** splits on one buffer and two files, independence, and focus moves are all driven in the room. Cheaper substitute that fails: panes sharing one caret.

## 13. Pinned Tabs

Why this section exists: pinned tabs survive restarts and shrug off accidental close.

**Fidelity:** new build, no baseline (stock Notepad pins nothing).

**Job:** The user can pin tabs that persist across restarts. Consumer: the tab model (§2), which carries pin state into session restore (§6).

**Treatment:** Pin action with pinned tab visuals; unpin to release; close-all skips pinned. Cheaper substitute that fails the checkpoint: pinned look with no persistence.

**Chrome:** Consume the shared tab styles. Do not invent a second pin treatment.

**Needs:** Windows host (build/test)

- [ ] Pin and unpin a tab under host drive. Done when: pinned tabs render pinned and unpin restores normal.
- [ ] Pinned tabs survive restart through §6 session restore. Done when: pins persist across an app relaunch.
- [ ] Close-all and close-others skip pinned tabs. Done when: pinned tabs stay open while the rest close.
- [ ] Commit: `"notepad-core: pin tabs"`

**Test checkpoint:** pin, persist, and skip are all driven in the room. Cheaper substitute that fails: pins that forget.

## 14. Text Statistics Panel

> **Started:** 2026-09-14T22:56:00Z

Why this section exists: writers who measure want top words, sentence lengths, and repetition flags without leaving the app.

**Fidelity:** new build, no baseline (stock Notepad computes nothing).

**Job:** The user can inspect document statistics in a panel. Consumer: the panel, which computes on open and refreshes on demand.

**Treatment:** A panel shows computed stats over an injected text provider until D02 T01 §1 binds the real buffer; refresh is on demand so typing never pays. **Corrected 2026-09-14 (phase-1 run 2):** the D02 T01 §2 dep cycled through the T01-whole gate. The benchmark is a compute-count test, not BenchmarkDotNet: simulated typing must not recompute, refresh recomputes once. Cheaper substitute that fails the checkpoint: live recompute that taxes typing.

**Decided 2026-09-14:** top 10 words by count with alphabetical tie-break; a word is a maximal run of Unicode letters/digits with internal apostrophes kept, counted case-insensitively; sentences split naively on `.`/`!`/`?` runs (abbreviations over-split, recorded limitation); sentence buckets are short 1-10, medium 11-25, long 26+ words; repetition flags non-stopwords appearing 3+ times against a small built-in English stopword set (English-first, matching D02 T05). Cost of changing any rule: one constant plus the `tests/Fixtures/stats/` expectations.

**Chrome:** Consume the shared panel styles. Do not invent a second stats treatment.

**Needs:** Windows host (build/test)

- [ ] The panel lists top words with counts. Done when: counts match a fixture document exactly.
- [ ] The panel shows sentence length distribution. Done when: lengths match the fixture.
- [ ] Repetition flags call out overused words. Done when: a seeded repeat is flagged.
- [x] Stats compute on open and refresh on demand only. Done when: typing benchmarks show no recompute. Proven 2026-09-14 (neutral half): `StatsController` computes on open, ignores provider changes until `Refresh` (compute-count test, 9/9 `TextStatsTests` green); the panel binding is bedtime.
- [ ] Commit: `"notepad-core: show text statistics"`

**Test checkpoint:** words, lengths, flags, and on-demand refresh are all driven in the room. Cheaper substitute that fails: stats that never update.

## 15. Distraction-Free Focus Mode

> **Moved:** 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §17; phase-1 run 2 cycle repair: paragraph emphasis needs the rendered surface, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

- [ ] ~~Focus mode enters and exits under host drive. Done when: chrome fades on entry and restores exactly on exit.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] ~~The current paragraph stays lit while the rest dims. Done when: captures show the emphasis.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] ~~Exit restores the exact prior layout. Done when: pane, panel, and bar states match pre-entry.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] Commit: `"editor: fade the chrome"`

**Test checkpoint:** entry, emphasis, and exact restore are all driven in the room. Cheaper substitute that fails: a mode that strands the user.

## 16. File Snapshots

Why this section exists: named local versions with one-click restore and no cloud.

**Fidelity:** new build, no baseline (stock Notepad versions nothing).

**Job:** The user can snapshot and restore named versions. Consumer: the file store, which keeps versions beside the file.

**Treatment:** Named snapshots in a versions list; one-click restore with a dirty check before overwriting. Dirty-tab content arrives through an injected provider until D02 T01 §1 binds the real buffer. Cheaper substitute that fails the checkpoint: an untracked .bak pile.

**Chrome:** Consume the shared list styles. Do not invent a second versions treatment.

**Needs:** Windows host (build/test)

- [ ] Take a named snapshot of the current file. Done when: the snapshot stores content byte-identical.
- [ ] The versions list shows snapshots and restores on click. Done when: restore replaces content under host drive.
- [ ] Restore over dirty content prompts first through §7. Done when: the prompt blocks a blind overwrite.
- [ ] Retention caps the snapshot count sanely. Done when: the cap is enforced and documented.
- [ ] Commit: `"notepad-core: snapshot files"`

**Test checkpoint:** snapshot, restore, dirty prompt, and retention are all driven in the room. Cheaper substitute that fails: restore that overwrites blindly.

## 17. New-File Templates

> **Started:** 2026-09-14T22:16:45Z

Why this section exists: new files start from templates with date and title filled in.

**Fidelity:** new build, no baseline (stock Notepad templates nothing).

**Job:** The user can start templated notes. Consumer: the new-tab flow (§2), which expands variables.

**Treatment:** A template picker on new; date and title variables expand; custom templates persist. Cheaper substitute that fails the checkpoint: static boilerplate with no variables.

**Chrome:** Consume the shared dialog styles. Do not invent a second picker treatment.

**Needs:** Windows host (build/test)

- [ ] The picker lists built-in templates on new. Done when: every built-in opens expanded. **Corrected 2026-09-14:** the seed named no built-ins; they are Blank note, Meeting notes, and Daily journal (adding one costs one static plus a picker row).
- [x] Date and title variables expand. Done when: fixtures show correct expansion. **Corrected 2026-09-14:** `{date}` is the locale short date, `{title}` comes from the picker prompt (empty means "Untitled"), unknown braces stay literal.
- [x] Custom templates persist across restarts. Done when: a user template survives relaunch. **Corrected 2026-09-14:** customs live as `.txt` files in `%LocalAppData%/IntelligentNotepad/templates/` (same root as the settings seam).
- [ ] Commit: `"notepad-core: template new files"`

**Test checkpoint:** picker, variables, and custom persistence are all driven in the room. Cheaper substitute that fails: templates that never update.

## 18. Export as Markdown, HTML, Plain Text

Why this section exists: Markdown, HTML, or plain text out of any view, to file. Copy-as split to D02 T01 §18 by phase-1 run 2 (cycle repair); the converter below is shared.

**Fidelity:** new build, no baseline (stock Notepad converts nothing).

**Job:** The user can move text across formats. Consumer: the file writer (§5), which saves the converted text.

**Treatment:** Export dialog with faithful conversion of the buffer text; the buffer arrives through an injected text provider until D02 T01 §1 binds the real buffer. Cheaper substitute that fails the checkpoint: plain-text-only bytes under new extensions.

**Chrome:** Consume the shared dialog styles. Do not invent a second convert treatment.

**Needs:** Windows host (build/test)

- [ ] Export writes all three formats to file. Done when: exported files open in their native apps.
- [ ] Round-trip fidelity fixtures pin the conversions. Done when: fixtures cover structure, emphasis, and lists.
- [ ] Commit: `"notepad-core: export formats"`

**Test checkpoint:** export and fidelity are all driven in the room. Cheaper substitute that fails: HTML that drops structure.

## 19. Encrypted Notes

Why this section exists: some notes need a password. Files lock with a clearly stated algorithm, and a wrong password fails loud instead of producing garbage.

**Fidelity:** new build, no baseline (stock Notepad encrypts nothing).

**Job:** The user can lock files with a password and unlock them later. Consumer: the file reader (§4) and writer (§5), which decrypt around the existing encoding path.

**Treatment:** Password-derived key with a stated algorithm (AES-256-GCM via platform crypto is the default; the section records the final choice); a wrong password fails loud before any bytes render. Cheaper substitute that fails the checkpoint: obfuscation, or silent mojibake on a wrong password.

**Chrome:** Consume the shared dialog styles. Do not invent a second lock treatment.

**Needs:** Windows host (build/test)

- [ ] The algorithm, KDF, and parameters are stated in the file header and in docs. Done when: a reader implements decrypt from the doc alone.
- [ ] Locking a file writes the encrypted form through §5. Done when: the ciphertext round-trips byte-identical.
- [ ] Unlocking with the right password restores the exact bytes. Done when: round-trip fixtures pass across encodings.
- [ ] A wrong password fails loud with no partial render. Done when: the failure path is driven and nothing leaks.
- [ ] The password never persists; the key lives in memory only. Done when: no password or key bytes reach disk or logs.
- [ ] Commit: `"notepad-core: lock notes with a password"`

**Test checkpoint:** stated algorithm, lock, unlock, loud failure, and memory-only keys are all driven in the room. Cheaper substitute that fails: encryption nobody can audit.

## 20. Backup on Save

Why this section exists: saves overwrite. A timestamped .bak sibling beside the file is the automatic safety net under the named §16 snapshots.

**Fidelity:** new build, no baseline (stock Notepad keeps no backups).

**Job:** The user can recover the pre-save version. Consumer: the save path (§5), which writes the sibling first.

**Treatment:** Timestamped .bak sibling on every save with a retention count; old siblings rotate out. Cheaper substitute that fails the checkpoint: one .bak that the next save eats.

**Chrome:** No new surface; the file list is the surface.

**Needs:** Windows host (build/test)

- [ ] Every save writes a timestamped .bak sibling first. Done when: the sibling predates the save under host drive.
- [ ] Retention caps the sibling count. Done when: old siblings rotate out at the cap.
- [ ] A crashed save leaves the newest .bak intact. Done when: the failure path is driven.
- [ ] Commit: `"notepad-core: back up on save"`

**Test checkpoint:** sibling, retention, and crash safety are all driven in the room. Cheaper substitute that fails: backups that pile up forever.

## 21. Reload Prompt on External Change

Why this section exists: files change behind us (sync tools, other editors). The app notices and asks instead of silently overwriting or showing stale bytes.

**Fidelity:** new build, no baseline (the capture session records whether stock prompts; this section defines our behavior either way).

**Job:** The user can choose keep or reload when the file changes on disk. Consumer: the open document, which refreshes or holds per the answer.

**Treatment:** A watcher notices external change; a prompt offers reload or keep; dirty documents resolve both sides explicitly. Cheaper substitute that fails the checkpoint: silent reload that eats edits, or no notice at all.

**Chrome:** Consume the shared dialog styles. Do not invent a second reload treatment.

**Needs:** Windows host (build/test)

- [ ] External change raises the prompt on a clean document. Done when: the prompt is driven under host file writes.
- [ ] Reload refreshes from disk; keep holds the buffer. Done when: both answers are driven.
- [ ] A dirty document resolves explicitly with no silent data loss either way. Done when: both paths are driven.
- [ ] Unsaved (never-pathed) documents never prompt. Done when: the negative test passes.
- [ ] Commit: `"notepad-core: prompt on external change"`

**Test checkpoint:** prompt, both answers, dirty resolution, and the unsaved negative are all driven in the room. Cheaper substitute that fails: a prompt that defaults to data loss.

## 22. First-Line Titles for Untitled Tabs

Why this section exists: untitled tabs show their first line as the live default. Agent suggestions live at D05 T02 §9.

**Fidelity:** new build, no baseline (the capture session confirms the first-line default against stock; this section defines it either way).

**Job:** The user can read untitled tabs at a glance. Consumer: the tab bar (§2), which renders titles.

**Treatment:** First line as the live default, trimmed per §2's auto-name rule. Cheaper substitute that fails the checkpoint: static "Untitled" for every blank tab.

**Chrome:** Consume the shared tab styles. Do not invent a second title treatment.

**Needs:** Windows host (build/test)

- [x] Untitled tabs show the first line as their live default. Proven by D01 T01 §2 shipped test UntitledShowsFirstLineOnly; bedtime UI drive re-confirms at the surface. Done when: typing the first line renames the tab under host drive.
- [ ] The first-line default is confirmed against the stock capture or the difference recorded. Done when: the capture comparison or the recorded difference exists.
- [ ] Commit: `"notepad-core: title untitled tabs from the first line"`

**Test checkpoint:** live default and capture confirmation are driven in the room. Cheaper substitute that fails: tabs that all read Untitled.

## 23. Side-by-Side Tab Diff

> **Moved:** 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §19; phase-1 run 2 cycle repair: diffing open tabs needs buffer content plus the moved split, neither behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

- [ ] ~~Any two open tabs pair into a diff. Done when: the pair path is driven.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §19.
- [ ] ~~Word-level change marks render on both sides. Done when: fixtures match exactly.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §19.
- [ ] ~~The pair hosts in a D02 T01 §16 split. Done when: panes show the pair under host drive.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §19.
- [ ] ~~Marks are display-only; editing either side re-marks live. Done when: re-marking is driven.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §19.
- [ ] Commit: `"editor: diff two tabs"`

**Test checkpoint:** pairing, word marks, split hosting, and live re-mark are all driven in the room. Cheaper substitute that fails: a diff of screenshots.

## 24. Share Target

> **Started:** 2026-09-14T22:19:07Z

Why this section exists: Windows apps share text; we receive it into a new tab. The OS registration lives at D07 T01 §7; this section owns the receive path.

**Fidelity:** new build, no baseline (the capture session records whether stock receives shares; this section defines our behavior either way). **Corrected 2026-09-14:** the seed asserted stock receives nothing; unverified.

**Job:** The user can share text from other apps into a new tab. Consumer: the tab model (§2), which opens the shared text.

**Treatment:** Incoming text opens a new untitled tab through the receive path. Cheaper substitute that fails the checkpoint: share support that opens an empty tab.

> **Moved 2026-09-14 (phase-1 run 2):** item 1 (share-target registration) to D07 T01 §7. Registration needs package identity, which D07 T01 §1 owns; an unpackaged app cannot declare the share contract. The receive path stays here and §7 routes activation into it.

**Chrome:** No new surface; the new tab is the surface.

**Needs:** Windows host (build/test)

- [x] Shared text opens in a new untitled tab. Done when: the receive path is driven.
- [x] Non-text shares decline gracefully. Done when: the negative path is driven.
- [ ] Commit: `"notepad-core: receive shared text"`

**Test checkpoint:** receive and graceful decline are driven in the room (registration is D07 T01 §7's). Cheaper substitute that fails: a target that eats shares silently.

## 25. Jump List Tasks

Why this section exists: new note and pinned notes on the taskbar icon. (Jump-list recents are §8 item 5. **Corrected 2026-09-14:** the seed duplicated them here.) The app starts working before it opens.

**Fidelity:** new build, no baseline (stock Notepad lists no tasks).

**Job:** The user can jump straight to a note from the taskbar. Consumer: the taskbar, which renders the app's tasks.

**Treatment:** Jump list tasks for new note, pinned notes (§13), and recent files (§6); each launches to the right place. Cheaper substitute that fails the checkpoint: tasks that all open a blank window.

**Chrome:** No new surface; the taskbar is the surface.

**Needs:** Windows host (build/test)

- [ ] The taskbar icon carries new-note, pinned, and recent tasks. Done when: all three appear.
- [ ] New note opens a fresh untitled tab through §2. Done when: the launch path is driven.
- [ ] Pinned notes open their files through §13. Done when: each pin launches correctly.
- [ ] Commit: `"notepad-core: task the jump list"`

**Test checkpoint:** tasks, new, pinned, and recent launches are all driven in the room. Cheaper substitute that fails: a jump list that jumps nowhere.

## 26. Protocol Handler

Why this section exists: links can open a path in the app.

**Fidelity:** new build, no baseline (stock Notepad handles no protocol).

**Job:** The user can open app paths from links. Consumer: the file opener (§4), which opens the carried path; the association path (§8), which shares registration mechanics.

**Treatment:** Registered protocol links carry a path; activation opens it through §4; malformed links decline. Cheaper substitute that fails the checkpoint: a protocol that opens the app and drops the path.

**Chrome:** No new surface; the opened file is the surface.

**Needs:** Windows host (build/test)

- [ ] The protocol scheme is registered (name recorded here). Done when: links offer the app.
- [ ] Activation opens the carried path through §4. Done when: the open path is driven.
- [ ] Malformed links decline gracefully. Done when: the negative path is driven.
- [ ] Commit: `"notepad-core: handle the protocol"`

**Test checkpoint:** registration, open, and graceful decline are all driven in the room. Cheaper substitute that fails: links that open the wrong file.

## 28. UIA Tab Accessibility Names

> **Started:** 2026-09-14T22:20:48Z

Why this section exists: stock tab UIA names carry ". Modified." / ". Unmodified." suffixes ours does not reproduce (phase-1 run 1 recon). Screen readers and automation tell dirty from clean by name.

**Fidelity:** stock tab UIA names, recorded from the capture during implementation; ours match or the difference is recorded.

**Job:** The user can hear tab dirty state by name. Consumer: screen readers and UIA clients, which read the tab names §3 exposes.

**Treatment:** Tab UIA names carry the stock dirty/clean suffixes, updating with the §2 model. Cheaper substitute that fails the checkpoint: names that update on selection only.

**Chrome:** No visual surface; the accessible name is the surface.

**Needs:** Windows host (build/test)

- [ ] Tab UIA names carry the stock Modified/Unmodified suffixes. Done when: names match stock under host drive.
- [ ] Suffixes track the §2 dirty model live. Done when: edits flip the suffix.
- [ ] Commit: `"notepad-core: name tabs for accessibility"`

**Test checkpoint:** stock-matching names and live tracking are driven in the room. Cheaper substitute that fails: accessible names that lie about dirty state.

## 29. Open with Explicit Encoding

Why this section exists: stock's Open dialog offers an Encoding picker defaulting to Auto-Detect (probed 2026-09-15); §4 matches the default by always auto-detecting, so files stock's detector misreads have no recourse here. This section adds the override.

**Fidelity:** stock Open dialog Encoding picker -- `resources/baseline/stock/notepad-open-dialog-n11.2607.14.0-win25h2.png`. Option list and behavior match the capture.

**Job:** The user can open a file forcing an encoding. Consumer: the §4 open path, which decodes with the forced encoding instead of detecting.

**Treatment:** An encoding option on the open flow offering the §5 encoding list plus Auto-Detect; the forced encoding flows into `FileOpen` as a decode override, and the tab records it as its encoding. Cheaper substitute that fails the checkpoint: an option that re-detects and ignores the choice.

**Chrome:** Consume the shared dialog styles. Do not invent a second picker treatment.

**Needs:** Windows host (build/test)

- -> XREF: D01 T01 §4 -- the open path and detector this overrides; §4 item 7 points here for the non-default half
- -> SOURCE: stock-open-dialog probe 2026-09-15 (Encoding Auto-Detect default with picker options)

- [ ] The open flow offers Auto-Detect plus every §5 encoding. Done when: the option list matches the capture.
- [ ] Opening with a forced encoding decodes with it, bypassing §4 detection. Done when: a 1252 file forced to UTF-8 shows replacement characters, driven.
- [ ] Auto-Detect behaves exactly as §4 alone. Done when: the §4 fixture matrix passes through this path unchanged.
- [ ] The tab records the forced encoding for §5's save path. Done when: save offers the forced encoding back.
- [ ] Commit: `"notepad-core: open with explicit encoding"`

**Test checkpoint:** option list, forced decode, auto-detect equivalence, and save handoff are all driven in the room. Cheaper substitute that fails: a picker that detects anyway.

## Verification

- [ ] `dotnet test` green
- [ ] Round-trip matrix byte-identical across encodings and line endings
- [ ] No destructive path without its prompt, all driven
- [ ] `python3 scripts/todo-graph.py validate` clean
