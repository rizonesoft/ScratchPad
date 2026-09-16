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
>
> **Corrected 2026-09-15 (phase-1 run 3):** §§4-7, 9, 27 have shipped since: file open, atomic save with Save As, session restore with recents, dirty prompts with crash recovery, multi-window with open-in mode, and the tab-strip chrome repair all exist; §8 is implemented but unstamped. Open: §§8, 11, 13, 14, 16-22, 24-26, 28, 29 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.
>
> **Corrected 2026-09-15 (phase-1 run 3, §14 validation):** §§8, 11, 13 have shipped since (association routing, icon wiring, pinned tabs). Open: §§14, 16-22, 24-26, 28, 29 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.
>
> **Corrected 2026-09-16 (phase-1 run 3, §17 validation):** §§14, 16 have shipped since (stats panel, file snapshots). Open: §§17-22, 24-26, 28, 29 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.
>
> **Corrected 2026-09-16 (phase-1 run 3, §18 validation):** §17 has shipped since (new-file templates). Open: §§18-22, 24-26, 28, 29 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.
>
> **Corrected 2026-09-16 (phase-1 run 3, §19 validation):** §18 has shipped since (export across formats). Open: §§19-22, 24-26, 28, 29 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.
>
> **Corrected 2026-09-16 (phase-1 run 3, §20 validation):** §19 has shipped since (encrypted notes) and §30 was filed (locked-tab residue hardening). Open: §§20-22, 24-26, 28-30 (§10, §12, §15, §23 moved out). Later sections still host a placeholder until D02 T01 lands.

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

**Adjacency rationale:** The tab bar is the list; open/save is the exchange; print is the document; close-without-save and crash recovery are the reversals. Settings live in T02 with their consumer named there. The §16 versions list follows the code-built ContentDialog pattern (**Corrected 2026-09-16 (§16 validation):** no shared list styles exist) and the §17 template picker follows the code-built ContentDialog pattern (**Corrected 2026-09-16 (§17 validation):** the §6 list treatment is prose only, same finding as §16).

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Main window shell with menu bar host | -- |  [x]   |
|   2   |   §2    | Tab model with dirty tracking | §1 |  [x]   |
|   3   |   §3    | Tab bar UI: open, switch, reorder, close | §2 |  [x]   |
|   4   |   §4    | File open with encoding detection | §2 |  [x]   |
|   5   |   §5    | File save and Save As | §4 |  [x]   |
|   6   |   §6    | Recent files and session restore | §5 |  [x]   |
|   7   |   §7    | Dirty prompts and crash recovery | §3, §5 |  [x]   |
|   8   |   §8    | File association and command-line open | §4, §6 |  [x]   |
|   9   |   §9    | Multi-window with open-in mode | §2, §3 |  [x]   |
|  10   |   §10   | Window border parity repair | §1 |  [ ]   |
|  11   |   §11   | App icon wiring | §1 |  [x]   |
|  12   |   §12   | Split view | §1, §2, D02 T01 §1 |  [ ]   |
|  13   |   §13   | Pinned tabs | §2, §6 |  [x]   |
|  14   |   §14   | Text statistics panel | §1 |  [x]   |
|  15   |   §15   | Distraction-free focus mode | §1, D01 T02 §1 |  [ ]   |
|  16   |   §16   | File snapshots | §5, §7 |  [x]   |
|  17   |   §17   | New-file templates | §2 |  [x]   |
|  18   |   §18   | Export as Markdown, HTML, plain text | §5 |  [x]   |
|  19   |   §19   | Encrypted notes | §4, §5 |  [x]   |
|  20   |   §20   | Backup on save | §5 |  [x]   |
|  21   |   §21   | Reload prompt on external change | §4 |  [ ]   |
|  22   |   §22   | First-line titles for untitled tabs | §2 |  [ ]   |
|  23   |   §23   | Side-by-side tab diff | §2, §12 |  [ ]   |
|  24   |   §24   | Share target | §1, §2 |  [ ]   |
|  25   |   §25   | Jump list tasks | §2, §6, §13 |  [ ]   |
|  26   |   §26   | Protocol handler | §4, §8 |  [ ]   |
|  27   |   §27   | Tab-strip chrome parity repair | §1, §3 |  [x]   |
|  28   |   §28   | UIA tab accessibility names | §3 |  [ ]   |
|  29   |   §29   | Open with explicit encoding | §4 |  [ ]   |
|  30   |   §30   | Locked-tab residue hardening | §6, §7, §16, §19 |  [ ]   |

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

- [x] `src/IntelligentNotepad/MainWindow.xaml` hosts the menu bar region, tab region, editor region, and status region. Done when: all four regions exist with the Notepad layout. Measured chrome row heights (43/32 DIP) land with §27 here.
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

**Corrected 2026-09-14 (reorder):** live probes show stock Notepad tabs do NOT drag-reorder (three negative probes: named AAA/BBB tabs dragged slowly across an on-screen foreground strip twice plus an identity-tracked drag, order unchanged every time), so CanReorderTabs stays off as parity and the first row plus the checkpoint verify a drag attempt leaves the order unchanged. The dirty dot sits where the X was and the X hides until hover (D01 T01 §2 recon). Ctrl+Shift+T re-verified live (a Don't-save close yields no reopen); the prompt names untitled tabs "{first-line}.txt" (single observation, §7 re-verifies); closing the last tab leaves a live zero-tab window (unprobed default, probed with §27: live, plus a fixed close-transition crash).

- [x] `src/IntelligentNotepad/TabBar.xaml` renders the `TabModel` list with new-tab, switch, and close, and no-reorder parity. Done when: every gesture in the capture works and a drag attempt leaves the order unchanged. Measured chrome geometry (caption inset, zero-tab centering, 6-DIP dot) lands with §27 here.
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

> **Verified:** 2026-09-15 | §4 | File open: 12-case encoding matrix plus 7-case EOL matrix byte-identical, stock-verbatim failure messages with OS detail, watcher detection, focus-existing dedup, 1 MiB progress threshold with 4 MiB scale drive, .txt-plus-all-files filter spec, 1 GiB over-limit refusal; FileOpen 37/37, Unit 89/89, Protocol 35/35 both OSes, UI 18/18 and Smoke 1/1 on Windows, build 0 warnings; stock quotes read verbatim from the failure and dialog captures; validate 0 fatal; self-test 393/393
> **Review:** rounds 2, candidates 625c7f2 plus 5c28ed3 (review fix: >2 GiB refuses as TooLarge instead of throwing) -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve (neutral section, rendered dialog defers to the menus TODO Open trigger). Raw findings: docs/reviews/01-notepad-core/D01-T01-s4.md
> **CRUD:** applicable | temp-file opens wrote bytes (read back via OpenSuccess text, encoding, BOM, and EOL asserts); failure opens wrote nothing (read back via tab-count and result-type asserts); external writes wrote Changed (read back via the fired gate); the 4 MiB open wrote progress (read back via final-report-equals-length); .LOG opens wrote the stamp (read back via exact-text asserts); fixtures wrote bytes once (read back via blob inspection after the gitattributes fix)
> **Duration:** 179
> **Implementer:** Muse Code (Meta Muse Spark)

## 5. File Save and Save As

> **Started:** 2026-09-15T05:20:00Z

Why this section exists: saving is the one path where a bug destroys user data. It is atomic, verified, and boring.

**Groomed 2026-09-13:** Notepad audit: Save As option enumeration, new-file defaults, and Save All are now explicit.

- [x] Save writes atomically (temp file plus rename) so a crash mid-save keeps either the old or the new bytes, never a mix. Done when: a fault-injection test proves it. **Driven 2026-09-15:** `SaveWritesAtomicallyViaTempAndRename` (same-dir temp plus move, no litter) plus `FaultBeforeCommitKeepsOldBytesIntact` (injected crash throws, old bytes intact).
- [x] Save As offers Notepad's encodings and line endings and honors the choice. Done when: each combination round-trips byte-identical. **Corrected 2026-09-15:** stock Save As offers encodings only (probed: no EOL dropdown in the dialog); the EOL choice UI is the D01 T02 §4 status-bar menu, and this item owns the encoding offer plus the EOL conversion the preserve path and that menu need. The rendered Save As dialog lands with the D01 T02 §1 trigger; the spec ships here as `SaveDialogDefaults`. **Driven 2026-09-15:** `SaveAsMatrixHonorsEveryOfferedCombination` (5 encodings times 3 EOLs through detect) plus `BomFlagRoundTripsIndependentOfName`.
- [x] Saving preserves the detected encoding and line ending unless the user changes them. Done when: open-save round-trips are byte-identical across the matrix. **Probed 2026-09-15:** stock writes a BOM when saving BOM-less UTF-16 (saved bytes start FF FE); we preserve `HasBom` so round-trips stay byte-identical (declared divergence, costs one branch). **Driven 2026-09-15:** `OpenSaveRoundTripsAcrossDetectionMatrix` (all 12 §4 fixtures byte-identical) plus `UnencodableCharactersFailLoudlyInsteadOfCorrupting`. **Default 2026-09-15 (review):** unencodable characters fail the save with the detail instead of writing '?' (stock's exact warning is unprobed; costs the dialog wording).
- [x] Save failure reports and keeps the dirty flag set. Done when: a read-only-destination drive proves no silent loss. **Corrected 2026-09-15:** stock shows no error for read-only or locked destinations (probed both: each opens Save As instead, bytes intact); so those map to `SaveRedirect` (the app opens Save As at D01 T02 §1-time) while only unmapped failures report the OS message. Dirty stays set on every non-saved outcome. **Driven 2026-09-15:** `LockedSaveRedirectsToSaveAsAndKeepsBytesIntact` plus `ReadOnlyAttributeSaveRedirects` (both Windows-only: POSIX rename ignores locks, root overrides bits) plus `RedirectMapCoversDestinationsAndPassesThroughUnknown` plus `UnmappedFailureReportsOsMessage`.
- [x] Save As offers exactly Notepad's encoding list (ANSI, UTF-16 LE, UTF-16 BE, UTF-8, UTF-8 with BOM) and its line-ending list as captured. Done when: each offered combination round-trips byte-identical. **Probed 2026-09-15:** the asserted list reads verbatim from the expanded Encoding dropdown (capture `resources/baseline/save/notepad-saveas-encoding-items-n11.2607.14.0-win25h2.png`); the dialog has no line-ending list (see item 2), so "each offered combination" is the 5 encodings times the 3 engine EOLs. **Driven 2026-09-15:** same matrix as item 2 (`SaveAsMatrixHonorsEveryOfferedCombination`) plus `SaveDialogPrefillAppendsTxtToDisplayName` (filter, offer list, prefill).
- [x] New never-saved files default to UTF-8 and CRLF as captured. Done when: the defaults are recorded from a fresh install and driven. Source: https://www.thewindowsclub.com/how-to-change-the-default-character-encoding-in-notepad-on-windows-10 **Probed 2026-09-15:** stock agrees on this box (Save As defaults a new file to UTF-8, capture `resources/baseline/save/notepad-saveas-dialog-n11.2607.14.0-win25h2.png`; a fresh tab reads UTF-8 plus Windows (CRLF)); true fresh-install state is unconfirmed and costs one string per default. **Driven 2026-09-15:** `NewTabDefaultsToUtf8WithoutBomAndCrlf`.
- [x] Save All saves every dirty tab, routing untitled tabs through Save As per Notepad's order and cancellation. Done when: multi-tab Save All with cancellation is driven. **Probed 2026-09-15:** strict tab order (a saved dirty tab before an untitled prompt saves first; an untitled prompt first leaves a later saved tab for after); dirty path tabs save silently, dirty untitled tabs prompt in order, clean tabs skipped; Cancel skips that tab and CONTINUES (no abort). Mid-All save failure is unprobed: record-then-continue (default, mirrors cancel). **Driven 2026-09-15:** `SaveAllWalksTabOrderAndContinuesPastCancel` (order log plus outcomes) plus `SaveAllContinuesPastFailure` plus `SaveAllRedirectPromptsInlineSaveAs` (Windows-only).
- [x] Commit: `"notepad-core: save atomically with Save As"`

**Test checkpoint:** Round-trip matrix byte-identical; fault-injection save keeps old-or-new; Save As honors every offered combination. Cheaper substitute that fails: direct overwrite that can leave a truncated file.

> **Verified:** 2026-09-15 | §5 | File save: atomic temp-plus-rename with fault injection, 5-by-3 Save As matrix through detect, 12-fixture open-save byte-identical round-trips, read-only and locked redirect to Save As, structural failures report OS text, UTF-8/CRLF/Untitled.txt defaults, Save All strict tab order with continue-on-cancel; Unit 119/119 Windows (116 plus 3 OS-skipped Linux), Protocol 35/35, UI 22/22, Smoke 1/1, build 0 warnings; encoding list verbatim from the expanded dropdown capture; validate 0 fatal; self-test 393/393
> **Review:** rounds 2, candidates 911ff19 plus 4615807 (review fix: strict encoders fail loud on unencodable characters) -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve (neutral section, Save As rendering defers to the menus TODO trigger). Raw findings: docs/reviews/01-notepad-core/D01-T01-s5.md
> **CRUD:** applicable | saves wrote bytes (read back via exact-text and byte-identical asserts); injected crash wrote old bytes (read back via intact original); redirects wrote nothing (read back via intact originals); Save All wrote per-tab files (read back via bytes, tab state, entries, and the call-order log); skips and failures wrote nothing (read back via dirty flags and entries)
> **Duration:** 50
> **Implementer:** Muse Code (Meta Muse Spark)

## 6. Recent Files and Session Restore

> **Started:** 2026-09-15T06:15:00Z

Why this section exists: Notepad reopens where the user left off. So do we, without ever resurrecting a file the user closed on purpose.

**Fidelity:** Notepad recent-files menu and restored session -- `resources/baseline/session/`. Order and truncation match.

**Job:** The user can reopen recent files and resume the last session. Consumer: the tab model, which receives the restored list.

**Treatment:** Persisted session list with Notepad's truncation and ordering. Cheaper substitute that fails the checkpoint: restoring only the active tab.

**Chrome:** Consume the shared menu styles. Do not invent a second recent-files treatment.

**Corrected 2026-09-14:** the seed said session state stores paths only. Notepad's "open content from previous session" restores unsaved buffers too, so this section now persists unsaved content locally, plus the "When Notepad starts" preference (restore vs new window).

**Groomed 2026-09-13:** Notepad audit: the startup preference's fresh-install default is now recorded from the capture instead of unnamed.

- [x] `src/Notepad.Core/SessionStore.cs` persists open paths, active tab, caret positions, and unsaved buffer contents. Done when: quit and relaunch restores all four, including an untitled tab with unsaved text.
- [x] The "When Notepad starts" preference offers restore-previous-session or open-new-window, as Notepad's. Done when: both modes are driven. **Corrected 2026-09-15:** stock 11.2607.14.0 labels the radios "Continue previous session" and "Start new session and discard unsaved changes" (capture `notepad-when-starts-n11.2607.14.0-win25h2.png`, both read live); the item's older labels named the same two modes. Normalized to "continue" and "fresh".
- [x] Missing or moved files are skipped with a notice, never resurrected as ghosts. Done when: the skip path is driven. **Corrected 2026-09-15:** probes contradict the skip-at-restore reading. Stock resurrects the missing file as an empty tab, shows "Cannot find the {path} file." with OK lazily on activation (capture `notepad-missing-notice-n11.2607.14.0-win25h2.png`), keeps the tab past OK, and drops it from the next snapshot (probed s2missing). Implemented stock-exact; the drive covers notice plus eviction. Dirty tabs over missing files are kept with their buffer (user-data-first default; the clean-missing drop is the probed half).
- [x] The recent-files list matches Notepad's order, truncation, and clearing. Done when: the UI test walks all three. **Corrected 2026-09-15:** no menu bar exists until D01 T02 §1, so the rendered recents submenu lands there (it hosts the bar and the open/save triggers that populate the list); this item ships the list behavior (order, truncation, clearing) driven, and T02 §1 walks the rendered submenu. **Corrected 2026-09-15:** the record trigger is tab close only (decisive s2m1: opens and window closes record nothing), newest first, cap 10 oldest-evicted (s2m2), "Clear list" without confirm. Order and truncation are UI-driven through closes plus settings readback; clearing is unit-driven (no UI trigger exists pre-T02).
- [x] Unsaved content is stored locally only, never synced or logged, with the privacy review recorded. Done when: the store format review names every field.
- [x] The "When Notepad starts" preference defaults to the fresh-install value recorded from the capture. Done when: a clean profile launches with the recorded default. **Corrected 2026-09-15:** the value is "continue". The capture shows Continue previous session selected and eight independent setup guides concur it is the out-of-box default; no clean-room reinstall was available (no Sandbox, no spare profile), so this is cited-default, not reinstalled-default. Cost of being wrong: one constant.
- [x] Session restore reopens the window set as Notepad does. Done when: the multi-window restore is driven. **Moved 2026-09-14 (phase-1 run 2)** from §9 item 4: restore is this section here. **Corrected 2026-09-15:** non-last window closes drop their tabs (probed s2merge: no merge, survivor keeps only its own); the snapshot rule is survivors-or-self, so clean quits always narrow to one window and multi-window sessions only meet crash/shutdown paths (§7 owns the continuous checkpoint). Geometry is not restored (two clean negatives), so session windows skip it. A trivial session (one empty untitled tab) is not written, keeping empty quits file-clean and geometry intact.
- [x] Commit: `"notepad-core: restore sessions and recent files"`

**Test checkpoint:** UI drive quits with saved tabs, an untitled unsaved tab, and a dirty tab, and relaunches to all three with contents and carets; both startup modes driven; missing-file skip driven. Cheaper substitute that fails: restore that works only when every file still exists.

> **Verified:** 2026-09-15 | §6 | Session restore (paths, active, carets, buffers) plus both when-starts modes, missing-file resurrect with lazy notice plus snapshot eviction, recents order/truncation/trigger with the rendered submenu deferred to the menu-bar owner, cited continue default, multi-window restore; UI 7/7, Unit §6 24/24 (suite 143/143), full gate green with 1 pre-existing quarantine; validate 0 fatal; self-test 393/393
> **Review:** round 2, candidates 9f43493 62656a2 44021cc ae76a8a -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s6.md
> **CRUD:** applicable | session store wrote session.json (read back via relaunch plus snapshot asserts plus typing-at-caret); settings wrote whenstarts plus recents (read back via mode drives plus recents asserts); dialog wrote nothing persistent (read back via notice text plus OK-keeps-tab); captures wrote goldens (read back via wording and label reads)
> **Duration:** 180
> **Implementer:** Muse Code (Meta Muse Spark)

## 7. Dirty Prompts and Crash Recovery

-> **Started:** 2026-09-15T09:24:07Z

Why this section exists: this section is the last line before data loss. Every destructive path prompts, and a crash recovers to the user's buffers, never to silence about them.

**Fidelity:** Notepad save prompts and recovery behavior -- `resources/baseline/prompts/`. Button order and wording match.

**Corrected 2026-09-15:** the Why line said a crash "recovers to a prompt". Probed 2026-09-15: stock 11.2607.14.0 shows no offer, notice, or prompt after a kill (relaunch opened zero dialogs) and silently restores every dirty buffer. The line now says what stock does. The prompt matrix below is tab-close only; window close and crash relaunch are both silent.

**Job:** The user can never lose work without choosing to. Consumer: the tab model, which only closes clean tabs unprompted.

**Treatment:** Notepad's prompt wording and button order. Cheaper substitute that fails the checkpoint: a generic OK/Cancel dialog.

**Chrome:** Consume the shared dialog styles. Do not invent a second prompt treatment.

**Corrected 2026-09-14:** the seed prompted on every close. Notepad prompts when closing an unsaved tab, but closing the window preserves the session silently for §6 to restore. This section now draws that line exactly.

- [x] Closing an unsaved tab prompts per Notepad (save, don't save, cancel). Done when: all three answers are driven. **Corrected 2026-09-15:** the prompt names the tab's full path for saved tabs (capture `notepad-save-prompt-path-n11.2607.14.0-win25h2.png`: "Do you want to save changes to C:\...?"), not the file name the §3 `PromptName` ships; untitled tabs are "{tab-name}.txt" (double-confirmed: §3 FIRST to FIRST.txt plus this probe's "FIRSTLINE7 rest of line" to "FIRSTLINE7 rest of line.txt", capture `notepad-save-prompt-untitled-n11.2607.14.0-win25h2.png`). Button order Save (default, accent) / "Don't save" / Cancel with title "Notepad" matches the §3 dialog verbatim, straight apostrophe included. **Corrected 2026-09-15:** stock answers Save on untitled with the Save As dialog (probed: title "Save as", cancel keeps the tab dirty and open); no Save As dialog exists until D01 T02 §1, so Save on untitled keeps the tab open with no loss (the cancel-outcome, driven), Save on pathed tabs saves in place and closes (driven with bytes), and SaveRedirect/SaveFailed keep the tab open (redirect needs the same dialog; failures report at D01 T02 §1-time). The drives cover Save (pathed, bytes plus closed), Don't-save (closed, discarded), Cancel (kept), and untitled-Save (kept, dirty, nothing written). **Driven 2026-09-15:** `SaveOnPathedDirtyTabWritesBytesAndCloses` (bytes plus closed, full-path message), `DontSaveDiscardsAndCloses` (bytes intact), `CancelKeepsTabExactly`, `UntitledSaveKeepsTabDirtyWithNothingWritten` (name.txt message, kept dirty, dir empty).
- [x] Closing the window with dirty tabs preserves everything silently for §6 restore, as Notepad's. Done when: the drive proves zero prompts and full restore. **Probed 2026-09-15:** window close is silent for one dirty tab and for two (both closed with zero dialogs; the singleton case re-verified after a debris scare, and the silently closed singleton restored dirty on next launch). The 2026-09-14 Corrected line stands as drawn. **Driven 2026-09-15:** `WindowCloseWithDirtyTabsIsSilentAndRestores` (zero modals across 3 s of close, both buffers restored dirty, file bytes intact).
- [x] Cancel on a tab prompt aborts that close only, leaving the tab exactly as it was. Done when: the drive proves nothing closed and nothing saved. **Driven 2026-09-15:** `CancelKeepsTabExactly` (text, name, count, and file bytes unchanged; the re-prompt proves still dirty).
- [x] Crash recovery checkpoints dirty buffers continuously and restores them silently on next launch, as Notepad's. Done when: a killed-process drive relaunches to all dirty buffers with contents and zero dialogs. **Corrected 2026-09-15:** the seed offered restore through a prompt. Probed 2026-09-15: stock shows no offer after a kill (relaunch opened zero dialogs) and restores every dirty buffer, including untitled content typed seconds before the kill, so the checkpoint is continuous, not periodic. Our session.json doubles as the checkpoint (debounced 2 s after edits, skipped in fresh mode so killed fresh sessions leave nothing stale), and relaunch restores through the §6 path with no new file, marker, or dialog. The 2 s debounce is an engineering default (cost: one constant); stock's exact cadence is unobservable from outside. **Driven 2026-09-15:** `KillRecoversBuffersSilentlyWithFilesUntouched` (checkpoint gated on session.json markers, kill, relaunch to both buffers with zero dialogs).
- [x] Recovery never writes the user's files: restored buffers arrive dirty, and bytes change only through the §5 save paths. Done when: the drive proves file bytes identical before the kill and after the relaunch. **Driven 2026-09-15:** `KillRecoversBuffersSilentlyWithFilesUntouched` asserts file bytes identical before the kill and after the relaunch. **Corrected 2026-09-15:** the seed gated overwrites on "the prompt's explicit choice". No prompt exists (see item 4); the explicit choice is the user's later save. Probed 2026-09-15: stock's file bytes were identical before the kill and after the relaunch.
- [x] Commit: `"notepad-core: prompt on dirty close and recover crashes"`

**Test checkpoint:** Tab-prompt answers driven (Save on pathed saves bytes and closes; untitled-Save keeps the tab dirty with nothing written); silent window close with full restore driven; killed-process drive relaunches to all dirty buffers with zero dialogs; file bytes identical across the kill. Cheaper substitute that fails: prompting on window close as if it were tab close; a recovery offer dialog stock never shows.

**Forwarded 2026-09-15 (not this section):** a bare `notepad.exe` launch with a live window opens a NEW window (for §8's launch rules), and stock Ctrl+T opens a new tab (matches our TabBar; for the record).
> **Verified:** 2026-09-15 | §7 | Dirty prompts and crash recovery: tab-close prompt matrix over the §3 dialog (pathed Save writes bytes and closes, untitled Save keeps dirty with nothing written, Dont-save discards, Cancel keeps exactly), full-path and tab-name.txt prompt naming from the prompts captures, silent window close with full restore, continuous 2 s checkpoint with silent kill recovery and files untouched; DirtyPrompt 7/7, CrashCheckpoint 5/5, Smoke 1/1, Unit 148/148, Protocol 35/35, UI 37 plus 1 pre-existing quarantine of 38, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** round 1, candidates 0a40085 284e49a -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s7.md
> **CRUD:** applicable | prompt answers wrote tab fates (read back via closed/kept plus file-bytes asserts); window close wrote the session (read back via zero-dialog plus restored-buffer asserts); checkpoint ticks wrote session.json (read back via kill-relaunch buffer and identical-bytes asserts); fresh typing wrote stale deletion (read back via file-gone assert); probes wrote the prompts captures (read back via verbatim wording asserts)
> **Duration:** 260

## 8. File Association and Command-Line Open

> **Started:** 2026-09-15T16:48:37Z

Why this section exists: Notepad opens from Explorer and from the command line. An exact clone does both.

**Groomed 2026-09-13:** Notepad audit: the Jump List, Explorer file-drop, and the /P + /PT print flags are now explicit.

- [x] Double-clicking an associated extension opens the file in the app (new window or new tab per Notepad's rule). Done when: the rule is recorded and driven. **Probed 2026-09-15:** bare launch opens a NEW window (7 launches, 7 windows; confirms the §7 forward); a file launch with a live window opens a TAB in it (deduped: same-file-twice changes nothing); stock is single-instance with activation routing into the live process. Second launches redirect to the first instance (AppInstance) and route per OpenIn. **Driven 2026-09-15:** `SingleFileLaunchOpensTab`, `MultiFileLaunchOpensTabsInOneWindow`, `SecondLaunchRedirectsFileIntoFirst`, `BareSecondLaunchOpensNewWindow`, `OpenInNewWindowModeOpensSecondWindow`, `FreshLaunchHoldsFilesInOneWindowInNewWindowMode`, `DoubleClickCommandOpensTab` (all green in the §8 filter run).
- [x] Command-line paths open, including multiple files , a missing file (which offers to create, per Notepad), and large/over-limit files. Done when: each case is driven. **Probed 2026-09-15:** the missing offer is modal with Yes/No and the verbatim text "Cannot find the {full-path} file." plus "Do you want to create a new file?" (two identical observations, third 2026-09-15 via UIA text dump; dialog crop `resources/baseline/stock/notepad-missing-offer-n11.2607.14.0-win25h2.png`, clipped at the live window's off-screen right edge, full text in the UIA dump); No creates nothing. Yes opens an empty tab bound to the path with bytes written on save (default; cost: one branch plus a Yes-probe; stock Yes unprobed). Stock Yes is default (accent in the crop); ours matches (`CreateFileDialog`, Yes default). Multi-file opens tabs in the existing window (same-file-twice dedupes; distinct-multi inferred from the single-file rule, cost: one routing branch). Directories skip silently in both entries (default; stock launch-a-folder unprobed, cost one branch; `OpenFilesAsync`). **Corrected 2026-09-14 (phase-1 run 2):** these drives re-prove §4 failure dialogs (wording recorded there), responsiveness, and redirect in situ; §4 stamps on its neutral proof plus this forward cover. **Driven 2026-09-15:** `MissingFileOfferNoCreatesNothing` (verbatim text asserted), `MissingFileOfferYesBindsTabAndSaveCreates`, `MissingFileOfferEnterAcceptsAsYes` (Yes default, review round 1), `LockedFileReportsLocked`, `OverLimitFileRefusesTooLarge`, `LargeFileOpensResponsively` (all green in the §8 filter run).
- [x] Association setup and teardown are clean: uninstall leaves no broken associations. Done when: install and uninstall are driven in Windows Sandbox. **Corrected 2026-09-14:** VM testing retired; Sandbox is the clean machine now. **Corrected 2026-09-15:** no Sandbox on this host (WindowsSandbox.exe absent, feature query needs elevation), so the register/unregister cycle is driven on the dev machine with registry snapshot-diff proof (before/after identical) on a scratch extension plus the real nine-ext list unit-covered; the verbs are the seam D07's installer calls, and the Sandbox re-drive is owed when a Sandbox host exists. UserChoice (the OS-owned current-default hash) cannot be set programmatically; the double-click drive runs the registered ProgId command exactly as Explorer would. **Driven 2026-09-15:** `AssociationVerbsCycleCleanly`, `DoubleClickCommandOpensTab` (green in the §8 filter run).
- [x] Only the extensions Notepad claims are claimed, and the claim is user-reversible. Done when: the list is recorded and the reversal driven. **Probed 2026-09-15:** stock 11.2607.14.0 claims .txt .log .ini .inf .ps1 .psd1 .psm1 .scp .wtx (AppxManifest FileTypeAssociation; plus ShellNew .txt). Register backs up prior defaults per extension and unregister restores them. **Driven 2026-09-15:** `FileAssociationTests` (list, backup, release, trees) plus `AssociationVerbsCycleCleanly` (green in the §8 filter run).
- [x] The taskbar Jump List offers recent files with pinning from the §6 store, as Notepad's. Done when: recents and pin are driven. Source: https://www.pctips.com/notepad-tips-and-tricks/ **Driven 2026-09-15:** `JumpListCommitsRecentsAndPinsFromStore`, `JumpListFeedTests`, `JumpListApiWorksUnpackaged` spike (green in the §8 filter run).
- [x] Dropping files from Explorer onto the window opens them per the §4 path and the §9 open-in mode. Done when: single- and multi-file drops are driven. **Corrected 2026-09-15:** end-to-end OLE delivery is host-blocked on this machine (Explorer-sourced strokes never engage a drag here: a verified button-held traverse plus an Explorer-to-Explorer control that moved nothing; self-sourced DoDragDrop with a shell file-drop object hangs before its first QueryContinueDrag with zero app events), so the drop entry ships wired (AllowDrop plus handlers, attach proven by a content-present drive log) with the single/multi end-to-end owed on a capable host; the drop file-open path is the §4 engine shared with the command-line drives. The capable-host drive also probes stock's multi-drop limit and caps ours (no cap today). **Driven 2026-09-15:** wired at startup (`MainWindow.xaml.cs:46` calls `WireFileDrops`, `MainWindow.Launch.cs:140-142` sets AllowDrop plus DragOver/Drop, drops open through `OpenFilesAsync` §4 path); wire record quoted from the scratch log (`s8drop.log`: `wire contentnull=False`); single/multi end-to-end stays owed per the correction.
- [x] The /P and /PT command-line flags are verified against the real Notepad: supported flags print through D01 T02 §5, removed flags are recorded as removed with the version note. Done when: the verification record exists and supported flags are driven. **Probed 2026-09-15:** /p and /pt are RECOGNIZED (consumed, not treated as filenames: /pt with a missing file and bad printer, and /p with a missing file, both produced no offer and no tab where ignored flags would offer). §8 ships the parser plus the print seam with a silent-exit interim default (parse, no-op seam, exit without windows; declared gap, cost: T02 §5 binds the seam); print-then-close drives land with D01 T02 §5 item 5 (pre-wired). **Driven 2026-09-15:** `PrintFlagsExitWithoutWindows` (/p and /pt cases) plus `LaunchArgsTests` parser matrix (green in the §8 filter run).
- [x] Commit: `"notepad-core: associate files and open from the command line"` (`511c99a`).

**Test checkpoint:** Association, multi-file open, missing-file offer, and clean uninstall all driven in Windows Sandbox. Cheaper substitute that fails: association tested only on the dev machine. **Corrected 2026-09-15:** Sandbox absent (see box 3): the association cycle is driven on the dev machine with registry snapshot-diff proof, and multi-file plus missing-offer are driven in-process; the Sandbox re-drive is owed when a Sandbox host exists.

> **Verified:** 2026-09-15 | §8 | File association and command-line open: single-instance routing per OpenIn (7 drives), missing offer verbatim with No/Yes/Enter-default (crop filed), §4 failures rendered in situ, HKCU assoc cycle with backup/restore plus double-click command, 9-extension claim, jump recents plus pins with taskbar read-back, wired drop entry (end-to-end owed on a capable host), /p and /pt parser plus print seam; Unit 26/26, UI 20/20, full gate Smoke 1/1 Unit 174/174 Protocol 35/35 UI 54 plus 1 pre-existing quarantine, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 2, candidates 511c99a plus 973d50e (review fix: Enter-default drive, Press honors withControl, dialog comment current) -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s8.md
> **CRUD:** applicable | launches wrote tabs and windows (read back via counts, names, contents, origins); offer answers wrote tab fates (read back via bound tabs, names, file absence/presence); registry verbs wrote claims and backups (read back via snapshot-diff identical plus claim reads); drops wrote JSON (read back via drains in redirect tests); jump refresh wrote the feed (read back via taskbar read-back); probes wrote the crop (read back via eyeball plus UIA text)
> **Duration:** 319
> **Implementer:** Muse Code (Meta Muse Spark)

## 9. Multi-Window with Open-In Mode

> **Started:** 2026-09-14T22:14:18Z

Why this section exists: Notepad opens new windows, and the "Opening files" setting decides tab vs window. Filed by groom 2026-09-14: the seed assumed one window.

**Fidelity:** Notepad multi-window behavior -- `resources/baseline/windows/`. New-window command, placement, and the open-in setting match the capture.

**Job:** The user can work in several windows as in Notepad. Consumer: the tab model, which lives per window.

**Treatment:** Per-window tab lists with the open-in setting.

> **Moved 2026-09-14 (phase-1 run 2):** item 4 (multi-window restore) to §6: restore is that section here; §9 consumes it. Cheaper substitute that fails the checkpoint: everything forced into one window.

**Chrome:** Consume the shared window styles. Do not invent a second window treatment.

**Groomed 2026-09-13:** Notepad audit: tab drag-out to a new window and drag-in docking are now explicit.

- [x] The new-window command (menu, shortcut) opens a window as Notepad's. Done when: the command is driven. **Corrected 2026-09-15:** the menu half lands with D01 T02 §1 (the File menu owns invocation); this item ships the Ctrl+Shift+N shortcut plus the window-opening mechanism it invokes. Probed 2026-09-15: the shortcut opens a same-size window at a small OS cascade (offsets +261/-38, +38/-38, +38/0 across three runs) with one untitled tab and identical chrome (captures in `resources/baseline/windows/`). **Driven 2026-09-15:** `CtrlShiftNOpensSecondWindowAtCascade` (count 1 to 2 to 1, origins differ, untitled tab, no first-run in the second).
- [x] The "Opening files" setting (new tab vs new window) is honored everywhere files open. Done when: both modes are driven. **Corrected 2026-09-14 (phase-1 run 2):** end-to-end honor is driven at §8-time (command-line opens in each mode) and D01 T02 §1-time (File menu); this section proves the mode value and routing. **Probed 2026-09-15:** the setting reads "Opening files" ("Choose where your files are opened") with values "Open in a new tab" (selected) and "Open in a new window" (capture `resources/baseline/windows/notepad-open-in-setting-n11.2607.14.0-win25h2.png`); `ShellSettings.OpenIn` (`new-tab`/`new-window`) matches. **Driven 2026-09-15:** `OpenInDefaultsToNewTab` plus `OpenInRoutesBothModesAndDefaultsUnknownToActiveWindow`.
- [x] Windows are independent: tabs, dirty state, and closed stacks never cross windows. Done when: the isolation test passes. **Corrected 2026-09-14 (phase-1 run 2):** undo isolation moved to D02 T01 §4 (noted there); undo does not exist until D02 lands. **Driven 2026-09-15:** `WindowsKeepSeparateTabsDirtyAndClosedStacks` (model) plus `WindowsKeepIndependentTabs` (live two windows: counts, content, clean title, close).
- [ ] ~~Dragging a tab out of the tab strip detaches it into a new window, and dragging a tab into another window's strip docks it there, per Notepad's threshold and cues. Done when: both directions are driven against the capture. Source: https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/~~ **Struck 2026-09-15:** stock 11.2607.14.0 has no tear-off (two clean drag-out negatives plus the standing §3 no-reorder claim, both directions re-confirmed; a 260 px drop outside the strip leaves the tab home and the window count unchanged). The cited 2023 tabs announcement predates tear-out and never mentions it; parity is no detach, which `TabBar` already ships (`CanDragTabs` off). No replacement: there is no stock behavior to build. Parity negative driven: `TabDragOutsideStripDetachesNothing`.
- [x] Commit: `"notepad-core: support multiple windows"`

**Test checkpoint:** New window, open-in modes, and isolation driven (restore is now §6 here). Cheaper substitute that fails: multi-window that shares one tab list.

> **Verified:** 2026-09-15 | §9 | Multi-window: Ctrl+Shift+N opens a same-size second window at the OS cascade (3 probed offsets, captures filed), Opening-files value plus routing proven with unknown staying put, model plus live two-window isolation, merge-on-close mutation-driven, no-tear-off parity negative; Unit 90/90, Protocol 35/35 both OSes, UI 22/22 and Smoke 1/1 on Windows, build 0 warnings; item 4 struck with two clean drag-out negatives; validate 0 fatal; self-test 393/393
> **Review:** rounds 2, candidates d4416bb plus 172a857 (review fix: close merges onto fresh settings instead of clobbering) -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s9.md
> **CRUD:** applicable | Ctrl+Shift+N wrote a window (read back via count 1 to 2 to 1, differing origins, untitled tab, no dialog); Ctrl+T in the second wrote a tab (read back via per-window counts 1 vs 2); content set wrote isolation (read back via empty first-window box and clean title); external flag flip plus close wrote preservation (read back via flag still flipped; red unfixed); outside-strip drag wrote nothing (read back via count 1 and 1 tab)
> **Duration:** 418
> **Implementer:** Muse Code (Meta Muse Spark)

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

- [x] The build embeds `resources/notepad.ico` as the exe icon in `src/IntelligentNotepad/IntelligentNotepad.csproj`. Done when: the built exe shows the icon in Explorer. Proven 2026-09-14: the extracted associated icon matches the asset 0/1024 pixels (byte proof for the Explorer eyeball). **Corrected 2026-09-15:** that proof targeted the superseded asset; re-proven against the operator's 01:44Z replacement (131902 bytes, 8 images, valid header): `ExeIconMatchesAsset` extracts the exe icon and diffs 0 pixels against the shipped asset, green in the §11 filter run.
- [x] The main window sets the icon from the asset at startup in `src/IntelligentNotepad/MainWindow.xaml.cs`. Done when: window captures show it. **Corrected 2026-09-15:** the chrome is content-extended (`ExtendsContentIntoTitleBar`), so no caption glyph surface exists; the window icon handle is the checkable surface (taskbar and Alt+Tab render from it). Shipped in `9f43493` (§6 commit, `// D01 T01 §11:` comment at `OnFirstLoaded`); `WindowChromeIconMatchesAsset` reads `WM_GETICON` small and diffs 0 pixels against the asset 16x16, green in the §11 filter run. Chrome crop `resources/baseline/app/icon-window-chrome-evidence.png` documents the glyph-free extended chrome.
- [x] Taskbar and window chrome show the asset with no default glyph anywhere. Done when: taskbar and window captures show it (Alt+Tab follows the exe by platform contract). **Driven 2026-09-15:** taskbar crop `resources/baseline/app/icon-taskbar-evidence.png` filed and eyeballed (asset mark with running underline, no default glyph); exe plus window 0-diff pins above plus the platform contract close the loop.
- [x] Commit: `"notepad-core: wire the app icon"` (`22f6b4c`).

**Test checkpoint:** Exe, window, and taskbar captures show the asset; MSIX visual assets stay D07 T01 §1's. Cheaper substitute that fails: the icon in one place only.

> **Verified:** 2026-09-15 | §11 | App icon wiring: exe embeds the operator asset, window sets it at Loaded, taskbar renders the mark with no default glyph; `ExeIconMatchesAsset` plus `WindowChromeIconMatchesAsset` 0-diff, taskbar and chrome crops filed and eyeballed; UI 2/2, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** round 1, candidate 22f6b4c plus the `SetIcon` lines in 9f43493 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s11.md
> **CRUD:** applicable | build wrote the exe icon and content copy (read back via extraction 0-diff plus shipped-asset presence); `SetIcon` wrote the window icon (read back via `WM_GETICON` 0-diff); captures wrote PNGs (read back via eyeball)
> **Duration:** 115
> **Implementer:** Muse Code (Meta Muse Spark)

## 12. Split View

> **Moved:** 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §16; phase-1 run 2 cycle repair: split needs live editor views, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

- [ ] ~~Split one file into two views on the same buffer, edits visible in both. Done when: typing in one pane appears in the other under host drive.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Split two different files side by side. Done when: each pane shows its file with independent dirty state.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Panes scroll and edit independently under host drive. Done when: scroll position and caret do not leak across panes.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] ~~Keyboard focus moves between panes and is announced. Done when: the shortcut moves focus both ways with UIA announcement.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §16.
- [ ] Commit: `"editor: split the view"`

**Test checkpoint:** splits on one buffer and two files, independence, and focus moves are all driven in the room. Cheaper substitute that fails: panes sharing one caret.

## 13. Pinned Tabs

> **Started:** 2026-09-15T22:18:04Z

Why this section exists: pinned tabs survive restarts and shrug off accidental close.

**Fidelity:** new build, no baseline (stock Notepad pins nothing).

**Job:** The user can pin tabs that persist across restarts. Consumer: the tab model (§2), which carries pin state into session restore (§6).

**Treatment:** Pin action with pinned tab visuals; unpin to release; close-all skips pinned. Cheaper substitute that fails the checkpoint: pinned look with no persistence.

**Chrome:** Consume the shared tab styles. Do not invent a second pin treatment.

**Needs:** Windows host (build/test)

- [x] Pin and unpin a tab under host drive. Done when: pinned tabs render pinned and unpin restores normal. **Corrected 2026-09-15:** the gesture is double-click on the tab (toggle); the context menu keeps its 4 stock items untouched (parity surface, §3-pinned). Stock tab double-click is a no-op by default (probe attempted: try 1 mismatched windows with no change observed, tries 2-3 defeated by single-instance routing; cost if wrong: one gesture plus this drive). Pin state also feeds `ShellSettings.PinnedFiles` for pathed tabs (the §8 jump feed reads it; §25 launches from it; untitled pins stay session-only). **Driven 2026-09-15:** `DoubleClickTogglesPinGlyph` (pin FontIcon named Pinned appears/vanishes), `PinsSurviveRelaunch` (settings write read back), green in the §13 filter run.
- [x] Pinned tabs survive restart through §6 session restore. Done when: pins persist across an app relaunch. Pins round-trip in `session.json` (`SessionTab.IsPinned`, additive default false); §6's missing-file rules are unchanged (pin protects against close, not deletion); a pinned tab makes a session non-trivial. **Driven 2026-09-15:** `PinsSurviveRelaunch` end-to-end plus `CaptureCopiesPinState` and `TrivialPinnedTabPersists`, green in the §13 filter run.
- [x] Close-all and close-others skip pinned tabs. Done when: pinned tabs stay open while the rest close. **Corrected 2026-09-15:** no close-all command exists (and none is added: menus are D01 T02 §1's surface); the bulk closes are close-others and close-right, both skip pinned; window close preserves everything silently per §7 (pins included); explicit single closes (X, menu, Ctrl+W, middle-click) close pinned tabs normally, browser-style. **Driven 2026-09-15:** `CloseOthersSkipsPinned`, `CloseRightSkipsPinned`, `SingleCloseStillClosesPinned`, green in the §13 filter run.
- [x] Commit: `"notepad-core: pin tabs"` (`a14f5d8`).

**Test checkpoint:** pin, persist, and skip are all driven in the room. Cheaper substitute that fails: pins that forget.

> **Verified:** 2026-09-15 | §13 | Pinned tabs: double-click toggles the pin glyph with the 4-item menu untouched, pins persist through session restore, bulk closes skip pinned while single closes release normally (feed entry goes with the tab), pathed pins feed the jump list; PinnedTabs 5/5, full gate Smoke 1/1 Unit 182/182 Protocol 35/35 UI 62 plus 1 pre-existing quarantine of 63, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 0-1, candidate a14f5d8 plus 6a5d36d plus 7799a73 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s13.md
> **CRUD:** applicable | double-click wrote pin state (read back via glyph UIA plus settings feed); relaunch wrote session.json (read back via restored glyph); close wrote feed removal (read back via settings absence); jump refresh ran through the §8 fingerprint-gated commit (no pin-specific taskbar read-back; §8's read-back covers the path)
> **Duration:** 75
> **Implementer:** Muse Code (Meta Muse Spark)

## 14. Text Statistics Panel

> **Started:** 2026-09-14T22:56:00Z

Why this section exists: writers who measure want top words, sentence lengths, and repetition flags without leaving the app.

**Fidelity:** new build, no baseline (stock Notepad computes nothing).

**Job:** The user can inspect document statistics in a panel. Consumer: the panel, which computes on open and refreshes on demand.

**Treatment:** A panel shows computed stats over an injected text provider until D02 T01 §1 binds the real buffer; refresh is on demand so typing never pays. **Corrected 2026-09-14 (phase-1 run 2):** the D02 T01 §2 dep cycled through the T01-whole gate. The benchmark is a compute-count test, not BenchmarkDotNet: simulated typing must not recompute, refresh recomputes once. **Decided 2026-09-15 (§14 validation):** the panel opens on Ctrl+Shift+G (free in-tree, no stock meaning; a chrome button was rejected because new chrome would break the goldens); the menu trigger is deferred to D01 T02 §1 item 5 per its engine-trigger rule, contract named there: command ShowStatsPanel, always enabled (zero tabs shows zeros), handler MainWindow.ShowStatsPanel. Cost of changing the shortcut: one accelerator line plus the drive. Cheaper substitute that fails the checkpoint: live recompute that taxes typing.

**Decided 2026-09-14:** top 10 words by count with alphabetical tie-break (**Clarified 2026-09-15 (§14 validation):** the tie-break is Ordinal over first-seen casing: deterministic and locale-independent, uppercase sorts before lowercase, so it differs from dictionary order on mixed-case ties; the fixture pins `The` before `cat`; cost of changing: the comparator plus the fixture expectations); a word is a maximal run of Unicode letters/digits with internal apostrophes kept, counted case-insensitively; sentences split naively on `.`/`!`/`?` runs (abbreviations over-split, recorded limitation); sentence buckets are short 1-10, medium 11-25, long 26+ words; repetition flags non-stopwords appearing 3+ times against a small built-in English stopword set (English-first, matching D02 T05). Cost of changing any rule: one constant plus the `tests/Fixtures/stats/` expectations.

**Chrome:** Consume the code-built ContentDialog treatment shared with SavePromptDialog/WhatsNewDialog (default WinUI styling). **Corrected 2026-09-15 (§14 validation):** no shared panel styles exist in the tree (three XAML files, no Themes dir); the dialog follows the existing code-built dialog pattern instead. Do not invent a second stats treatment.

**Needs:** Windows host (build/test)

- [x] The panel lists top words with counts. Done when: counts match a fixture document exactly. **Driven 2026-09-15:** `PanelListsFixtureExactStats` (fixture-exact rows in a right-aligned label/value grid, panel contained in the window), green in the §14 filter run. Two transient fused-word reads disclosed (UIA settling mid-render; fixed by box-write readback plus stable-double-read section polling, green since).
- [x] The panel shows sentence length distribution. Done when: lengths match the fixture. **Driven 2026-09-15:** `PanelListsFixtureExactStats` (7 fixture-exact rows including buckets) plus `EmptyTabsShowZeros` (all-zero rows), green in the §14 filter run.
- [x] Repetition flags call out overused words. Done when: a seeded repeat is flagged. **Driven 2026-09-15:** `PanelListsFixtureExactStats` (seeded `cat` flagged, stopword `The` excluded) plus `LongRepetitionListTruncatesWithTrailer` (50-row cap, `+10 more` trailer exact), green in the §14 filter run.
- [x] Stats compute on open and refresh on demand only. Done when: typing benchmarks show no recompute. Proven 2026-09-14 (neutral half): `StatsController` computes on open, ignores provider changes until `Refresh` (compute-count test, 9/9 `TextStatsTests` green, re-proven 9/9 this run). **Bound 2026-09-15:** `StatsDialog` constructs a fresh controller per open over the active tab's buffer with a Refresh control; `RefreshAndReopenRecompute` drives reopen-recompute plus Refresh in the room, green in the §14 filter run.
- [x] Commit: `"notepad-core: show text statistics"` (`b247cff` plus round-1 `ab51d4f`).

**Test checkpoint:** words, lengths, flags, and on-demand refresh are all driven in the room. Cheaper substitute that fails: stats that never update.

> **Verified:** 2026-09-16 | §14 | Text statistics panel: Ctrl+Shift+G dialog with fixture-exact top words, sentence distribution, and repetition flags over the active tab's buffer, compute on open with on-demand Refresh, menu trigger deferred to the menu owner with a recorded contract; StatsPanel 4/4, TextStats 9/9, full gate Smoke 1/1 Unit 182/182 Protocol 35/35 UI 66 plus 1 pre-existing quarantine of 67, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 0-1, candidate b247cff plus ab51d4f -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s14.md
> **CRUD:** applicable | open wrote a fresh compute (read back via exact rows); Refresh wrote a recompute (read back via re-rendered rows); close wrote nothing (reopen recomputes); settings and session untouched by the panel
> **Duration:** 1519
> **Implementer:** Muse Code (Meta Muse Spark)

## 15. Distraction-Free Focus Mode

> **Moved:** 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §17; phase-1 run 2 cycle repair: paragraph emphasis needs the rendered surface, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

- [ ] ~~Focus mode enters and exits under host drive. Done when: chrome fades on entry and restores exactly on exit.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] ~~The current paragraph stays lit while the rest dims. Done when: captures show the emphasis.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] ~~Exit restores the exact prior layout. Done when: pane, panel, and bar states match pre-entry.~~ Moved 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md §17.
- [ ] Commit: `"editor: fade the chrome"`

**Test checkpoint:** entry, emphasis, and exact restore are all driven in the room. Cheaper substitute that fails: a mode that strands the user.

## 16. File Snapshots

> **Started:** 2026-09-16T00:22:00Z

Why this section exists: named local versions with one-click restore and no cloud.

**Fidelity:** new build, no baseline (stock Notepad versions nothing).

**Job:** The user can snapshot and restore named versions. Consumer: the file store, which keeps versions beside the file.

**Treatment:** Named snapshots in a versions list; one-click restore with a dirty check before overwriting. Dirty-tab content arrives through an injected provider until D02 T01 §1 binds the real buffer. **Decided 2026-09-16 (§16 validation):** the store is `<filename>.snapshots/` beside the file holding `manifest.json` (nextId plus name/createdUtc/bytes/spec entries) and `snap-{id:0000}.bin` content files (cost of moving: one const plus a migrator); snapshot bytes are exactly what `FileSave.SaveFile` would write for the buffer under the tab's spec, restore decodes through `FileOpen` detection; retention is 10 per file with oldest-first eviction at take (cost: one const plus the drives); the panel opens on Ctrl+Shift+H (free in-tree, H for history) with the menu trigger deferred to the menu owner per its engine-trigger rule (contract: command ShowSnapshots, always enabled, handler MainWindow.ShowSnapshotsPanelAsync; recorded both sides); untitled tabs get a save-first note with Take disabled (a state, not a deferral); restore replaces buffer text with natural dirty tracking (identical restores stay clean; encoding follows the tab); names are non-empty, at most 80 chars, unique per file case-insensitively, defaulting to UTC `yyyy-MM-dd HH:mm`; restore over a dirty buffer reuses the §7 prompt (Save saves then restores, Don't-save restores, Cancel aborts). Cheaper substitute that fails the checkpoint: an untracked .bak pile.

**Chrome:** Consume the code-built ContentDialog treatment shared with SavePromptDialog/StatsDialog (default WinUI styling, ListView for the versions). **Corrected 2026-09-16 (§16 validation):** no shared list styles exist in the tree (the §6 list treatment is prose only; recents rendering is deferred to the menu owner); the dialog follows the existing code-built dialog pattern instead. **Corrected 2026-09-16 (§16 review round 3):** the versions render as one-click restore buttons in a StackPanel (at most 10 rows), not a ListView; buttons satisfy item 2's "restores on click" directly while a ListView would need selection plus a separate restore control. Do not invent a second versions treatment.

**Needs:** Windows host (build/test)

- [x] Take a named snapshot of the current file. Done when: the snapshot stores content byte-identical. **Driven 2026-09-16:** `TakeStoresSaveIdenticalBytes` (take bytes equal a `FileSave` reference) plus `TakeStoresBytesAndListsVersion` (take lists, stored bytes decode to the buffer), green.
- [x] The versions list shows snapshots and restores on click. Done when: restore replaces content under host drive. **Driven 2026-09-16:** `RestoreDontSaveReplacesBuffer`, `RestoreSaveWritesThenRestores`, and `RestoreOnCleanBufferSkipsPrompt` (one-click restore buttons, sequential reshow flow), green.
- [x] Restore over dirty content prompts first through §7. Done when: the prompt blocks a blind overwrite. **Driven 2026-09-16:** the Save/Don't-save/Cancel matrix across `RestoreSaveWritesThenRestores`, `RestoreDontSaveReplacesBuffer`, and `RestoreCancelKeepsBuffer` (real `SavePromptDialog`, shown sequentially) plus `RestoreSaveFailureAbortsWithWorkPreserved` (read-only file: Save redirects, restore aborts, buffer and disk untouched), green.
- [x] Retention caps the snapshot count sanely. Done when: the cap is enforced and documented. **Driven 2026-09-16:** `RetentionEvictsOldestPastTen` in unit (11 takes hold 10, oldest bytes deleted) and in UI (11 takes in the room, s01 gone, s11 kept, bin deleted), green. Cap documented in-dialog ("Keeps the last 10 versions.").
- [x] Commit: `"notepad-core: snapshot files"` (`44404da` plus round-1 `089922a` plus round-2 `a628db3`).

**Test checkpoint:** snapshot, restore, dirty prompt, and retention are all driven in the room. Cheaper substitute that fails: restore that overwrites blindly.

> **Verified:** 2026-09-16 | §16 | File snapshots: Ctrl+Shift+H dialog with named takes byte-identical to FileSave output, one-click restore buttons with sequential §7 dirty prompt (Save saves then restores, Don't-save restores, Cancel aborts, save-failure aborts with work preserved), retention cap 10 with oldest-first eviction, menu trigger deferred to the menu owner with a recorded contract; SnapshotTests 8/8, SnapshotStoreTests 8/8, full gate Smoke 1/1 Unit 190/190 Protocol 35/35 UI 74 plus 1 pre-existing quarantine of 75, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 1-3, candidate 44404da plus 089922a plus a628db3 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s16.md
> **CRUD:** applicable | take wrote a snap bin plus manifest entry (read back via list plus decode); restore wrote buffer text (read back via the room); eviction deleted the oldest bin (read back via absence); failed save wrote nothing (buffer and disk read back unchanged); settings and session untouched by the dialog
> **Duration:** 34
> **Implementer:** Muse Code (Meta Muse Spark)

## 17. New-File Templates

> **Started:** 2026-09-14T22:16:45Z

Why this section exists: new files start from templates with date and title filled in.

**Fidelity:** new build, no baseline (stock Notepad templates nothing).

**Job:** The user can start templated notes. Consumer: the new-tab flow (§2), which expands variables.

**Treatment:** A template picker on new; date and title variables expand; custom templates persist. **Decided 2026-09-16 (§17 validation):** "on new" reads as a separate entry that creates a new tab from a template: Ctrl+N, the strip + button, and Ctrl+T stay blank (parity, §2-owned; cost of rerouting them through the picker: their drives plus the parity proofs). The picker opens on Ctrl+Shift+E (free in-tree; T taken by new-tab/reopen, E for tEmplate) with the menu trigger deferred to the menu owner per its engine-trigger rule (contract: command ShowTemplates, always enabled, handler MainWindow.ShowTemplatesPanelAsync; recorded both sides); choosing a template opens an untitled tab with the expanded body, dirty via NotifyEdited (mirrors the restore fill path), `{date}` the locale short date of use (local today). The title box is the `{title}` prompt and doubles as the custom-template name: "Save current as template" stores the active tab's buffer under it (empty name disables; mirrors §16 Take), which is what makes item 3 user-reachable (cost: one button plus the drive). Cheaper substitute that fails the checkpoint: static boilerplate with no variables.

**Chrome:** Consume the code-built ContentDialog treatment shared with SavePromptDialog/StatsDialog/SnapshotsDialog (default WinUI styling, template rows as use-buttons). **Corrected 2026-09-16 (§17 validation):** no shared dialog styles exist in the tree (same finding as §16); the dialog follows the existing code-built dialog pattern instead. Do not invent a second picker treatment.

**Needs:** Windows host (build/test)

- [x] The picker lists built-in templates on new. Done when: every built-in opens expanded. **Corrected 2026-09-14:** the seed named no built-ins; they are Blank note, Meeting notes, and Daily journal (adding one costs one static plus a picker row). **Driven 2026-09-16:** `PickerListsBuiltInsAndUsesMeetingNotes` (all three listed, Meeting notes opens with title plus locale date) plus `BlankNoteOpensCleanEmptyTab` plus `DailyJournalOpensExpanded` (review round 1: the third built-in opens expanded, panel contained), green.
- [x] Date and title variables expand. Done when: fixtures show correct expansion. **Corrected 2026-09-14:** `{date}` is the locale short date, `{title}` comes from the picker prompt (empty means "Untitled"), unknown braces stay literal. **Re-proved 2026-09-16:** neutral `TemplateTests` 5/5 plus `UnknownBracesStayLiteralInRoom` (custom with braces expands title and keeps `{unknown}`), green.
- [x] Custom templates persist across restarts. Done when: a user template survives relaunch. **Corrected 2026-09-14:** customs live as `.txt` files in `%LocalAppData%/IntelligentNotepad/templates/` (same root as the settings seam). **Re-proved 2026-09-16:** `SaveCurrentPersistsAcrossRelaunch` (save in the room, relaunch, still listed and usable) plus `EmptyTitleDisablesSave`, green.
- [x] Commit: `"notepad-core: template new files"`

**Test checkpoint:** picker, variables, and custom persistence are all driven in the room. Cheaper substitute that fails: templates that never update.

> **Verified:** 2026-09-16 | §17 | New-file templates: Ctrl+Shift+E picker with three built-ins opening expanded (title prompt plus locale date), save-current-as-template customs persisting as .txt across relaunch, menu trigger deferred to the menu owner with a recorded contract; UI TemplateTests 6/6, Unit TemplateTests 5/5, full gate Smoke 1/1 Unit 190/190 Protocol 35/35 UI 80 plus 1 pre-existing quarantine of 81, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 1, candidate 2ff23cb plus d7cc0d1 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s17.md
> **CRUD:** applicable | save-custom wrote a .txt (read back via list plus use); use wrote a new tab body (read back via the room); relaunch wrote nothing (custom read back still listed); session untouched beyond the suite's standard cleanup
> **Duration:** 1625
> **Implementer:** Muse Code (Meta Muse Spark)

## 18. Export as Markdown, HTML, Plain Text

> **Started:** 2026-09-16T01:24:00Z

Why this section exists: Markdown, HTML, or plain text out of any view, to file. Copy-as split to D02 T01 §18 by phase-1 run 2 (cycle repair); the converter below is shared.

**Fidelity:** new build, no baseline (stock Notepad converts nothing).

**Job:** The user can move text across formats. Consumer: the file writer (§5), which saves the converted text.

**Treatment:** Export dialog with faithful conversion of the buffer text; the buffer arrives through an injected text provider until D02 T01 §1 binds the real buffer. **Decided 2026-09-16 (§18 validation):** the converter is `FormatConverter` in Notepad.Core, UI-free so copy-as reuses it: input is buffer text read as Markdown source; Markdown output is line-break-normalized identity; HTML output is a structural rendering; plain output strips inline markers. Supported subset: ATX headings (`#` plus space), `*` emphasis, `**` strong, single-backtick code spans, `[text](url)` links, flat `-`/`*` and `1.` lists, paragraphs; everything else (underscores, images, nested lists, unmatched markers) passes through literally (pinned). Copy-as needs a fragment while export ships a document, so the converter exposes `ToHtmlFragment` (shared core) plus a `ToHtmlDocument` shell (title plus meta charset) used by export; plain links render as `text (url)`. The dialog opens on Ctrl+Shift+X (free in-tree, X for eXport) with the menu trigger deferred to the menu owner per its engine-trigger rule (contract: command ShowExport, always enabled, handler MainWindow.ShowExportPanelAsync; recorded both sides); each format button delivers its converted file beside the source, with an editable base-name box defaulting to `{basename}-export` so export never overwrites the source (no Save As picker exists yet; cost of rerouting: the T02 dialog plus the drives); untitled tabs get a save-first note with Export disabled (a state, not a deferral, mirrors §16); exports write UTF-8 no-BOM CRLF (the tab defaults; cost: one spec). Cheaper substitute that fails the checkpoint: plain-text-only bytes under new extensions.

**Chrome:** Consume the code-built ContentDialog treatment shared with SavePromptDialog/StatsDialog/SnapshotsDialog/TemplatesDialog (default WinUI styling, one export button per format). **Corrected 2026-09-16 (§18 validation):** no shared dialog styles exist in the tree (same finding as §16/§17); the dialog follows the existing code-built dialog pattern instead. Do not invent a second convert treatment.

**Needs:** Windows host (build/test)

- [x] Export writes all three formats to file. Done when: exported bytes equal the pinned fixtures and the HTML carries the structural tags. **Corrected 2026-09-16 (§18 validation):** the seed's "open in their native apps" is not room-drivable (launching native apps on the operator host is out); fixture-exact bytes plus structural tags are the falsifiable form. **Driven 2026-09-16:** `ExportMarkdownWritesConvertedFile` (exact bytes, source untouched), `ExportHtmlRendersStructure` (exact document plus `h1`/`ul`/title tags), `ExportPlainStripsMarkers` (exact text, heading marker gone, link kept as `text (url)`), and `UntitledShowsSaveFirstNote`, green.
- [x] Round-trip fidelity fixtures pin the conversions. Done when: fixtures cover structure, emphasis, and lists. **Driven 2026-09-16:** `FormatConverterTests` 13/13 (headings, emphasis/strong, code, links, both list kinds, paragraphs, literal fallbacks, document shell, escaping), green.
- [x] Commit: `"notepad-core: export formats"`

**Test checkpoint:** export and fidelity are all driven in the room. Cheaper substitute that fails: HTML that drops structure.

> **Verified:** 2026-09-16 | §18 | Export as Markdown, HTML, plain text: Ctrl+Shift+X dialog converting the live buffer through the shared UI-free converter and writing beside the source with a safe default name, HTML as a document shell, untitled save-first state, menu trigger deferred to the menu owner with a recorded contract; UI ExportTests 4/4, Unit FormatConverterTests 13/13, full gate Smoke 1/1 Unit 203/203 Protocol 35/35 UI 84 plus 1 pre-existing quarantine of 85, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 1, candidate 29b9f2f -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s18.md
> **CRUD:** applicable | each export wrote converted bytes beside the source (read back exact, source untouched); the failure path is undriven (invalid names fail gracefully by construction, advisory); session untouched beyond the suite's standard cleanup
> **Duration:** 14
> **Implementer:** Muse Code (Meta Muse Spark)

## 19. Encrypted Notes

> **Started:** 2026-09-16T01:40:00Z

Why this section exists: some notes need a password. Files lock with a clearly stated algorithm, and a wrong password fails loud instead of producing garbage.

**Fidelity:** new build, no baseline (stock Notepad encrypts nothing).

**Job:** The user can lock files with a password and unlock them later. Consumer: the file reader (§4) and writer (§5), which decrypt around the existing encoding path.

**Treatment:** Password-derived key with a stated algorithm (AES-256-GCM via platform crypto is the default; the section records the final choice); a wrong password fails loud before any bytes render. **Decided 2026-09-16 (§19 validation):** final choice is AES-256-GCM (.NET AesGcm, CNG on Windows) with PBKDF2-HMAC-SHA256 at 600,000 iterations (OWASP password-storage guidance), 16-byte salt, 12-byte nonce, 16-byte tag, the header line bound as AAD. File layout: `IntelligentNotepad-Encrypted-1` plus LF, one JSON header line (`alg`, `kdf`, `iter`, `salt`, `nonce`, b64), LF, then raw ciphertext plus tag; unknown algorithms and corrupt headers fail loud like wrong passwords (no oracle detail). The doc is `docs/encrypted-notes.md` with a pinned test vector. Lock opens on Ctrl+Shift+L (free in-tree, L for lock) with the menu trigger deferred to the menu owner per its engine-trigger rule (contract: command LockFile, always enabled, handler MainWindow.ShowLockPanelAsync; recorded both sides); unlock rides the open path (launch-args and drops now, the T02 Open trigger reuses it), never a separate command. The lock dialog carries password plus confirm boxes (must match, non-empty); the unlock dialog carries password plus Unlock/Cancel with inline retry on a wrong password. Saves never silently decrypt: locked-origin tabs (`Tab.IsLocked`, memory only, never persisted) re-lock on every file write (close-save shows the lock dialog, Cancel aborts the close with nothing written; the snapshot-restore Save branch fails safe so the restore aborts; no direct save key exists yet and the T02 one reuses this rule); the plaintext escape hatch waits on Save As (copy to a new tab meanwhile). Restore ghosts locked files (no password at startup; the password is never persisted). Memory-only means key bytes cleared after use with the password living only in the dialog; the drive scans app data for the password and asserts the ciphertext holds no plaintext. Cheaper substitute that fails the checkpoint: obfuscation, or silent mojibake on a wrong password.

**Chrome:** Consume the code-built ContentDialog treatment shared with SavePromptDialog/StatsDialog/SnapshotsDialog/TemplatesDialog/ExportDialog (default WinUI styling, PasswordBox inputs). **Corrected 2026-09-16 (§19 validation):** no shared dialog styles exist in the tree (same finding as §16/§17/§18); the dialogs follow the existing code-built dialog pattern instead. Do not invent a second lock treatment.

**Needs:** Windows host (build/test)

- [x] The algorithm, KDF, and parameters are stated in the file header and in docs. Done when: a reader implements decrypt from the doc alone. **Driven 2026-09-16:** `docs/encrypted-notes.md` (layout, parameters, normative decrypt steps) with `DocumentedVectorPinsCiphertext` (vector cross-checked against an independent Python implementation), green.
- [x] Locking a file writes the encrypted form through §5. Done when: the ciphertext round-trips byte-identical. **Driven 2026-09-16:** `LockUnlockRoundTripsExactBytes` (lock in the room, ciphertext holds no plaintext, source path overwritten with locked bytes) plus `RelockMarksTabLockedAndClean`, green.
- [x] Unlocking with the right password restores the exact bytes. Done when: round-trip fixtures pass across encodings. **Driven 2026-09-16:** `LockUnlockRestoresExactBytes` theory over UTF-8/BOM/UTF-16LE/UTF-16BE/ANSI plus the room unlock half of `LockUnlockRoundTripsExactBytes`, green.
- [x] A wrong password fails loud with no partial render. Done when: the failure path is driven and nothing leaks. **Driven 2026-09-16:** `WrongPasswordFailsLoudWithNothingRendered` (inline error, no new tab, file bytes untouched) plus `TamperedCiphertextFailsLikeWrongPassword` and `TamperedHeaderFailsLoud`, green.
- [x] The password never persists; the key lives in memory only. Done when: no password or key bytes reach disk or logs. **Driven 2026-09-16:** `PasswordNeverReachesDisk` (lock plus unlock, then app-data scan finds no password) plus `RelockOnCloseSaveKeepsCiphertext` and `RestoreGhostsLockedFile`, green.
- [x] Commit: `"notepad-core: lock notes with a password"`

**Test checkpoint:** stated algorithm, lock, unlock, loud failure, and memory-only keys are all driven in the room. Cheaper substitute that fails: encryption nobody can audit.

> **Verified:** 2026-09-16 | §19 | Encrypted notes: AES-256-GCM plus PBKDF2-SHA256-600k with a stated header and doc plus pinned vector, Ctrl+Shift+L lock dialog, unlock on open with in-dialog retry, re-lock on every write with restore ghosting, menu trigger deferred to the menu owner with a recorded contract; UI EncryptedNotesTests 6/6, Unit NoteCryptoTests 16/16, full gate Smoke 1/1 Unit 219/219 Protocol 35/35 UI 90 plus 1 pre-existing quarantine of 91, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 1, candidate f0937c8 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s19.md
> **CRUD:** applicable | lock wrote ciphertext over the source (read back locked, no plaintext); unlock wrote a buffer (read back exact); wrong password wrote nothing (file bytes read back untouched); re-lock wrote ciphertext again (read back decrypting to the edit); app data scanned clean of the password
> **Duration:** 31
> **Implementer:** Muse Code (Meta Muse Spark)

## 20. Backup on Save

> **Started:** 2026-09-16T02:14:00Z

Why this section exists: saves overwrite. A timestamped .bak sibling beside the file is the automatic safety net under the named §16 snapshots.

**Fidelity:** new build, no baseline (stock Notepad keeps no backups).

**Job:** The user can recover the pre-save version. Consumer: the save path (§5), which writes the sibling first.

**Treatment:** Timestamped .bak sibling on every save with a retention count; old siblings rotate out. **Decided 2026-09-16 (§20 validation):** names are `{filename}.{yyyyMMdd-HHmmssfff UTC}.bak` with a `-2`/`-3` collision suffix; rotation orders by creation-timeUtc then name (suffix-safe) and manages only own-pattern names (foreign `.bak` files are left alone). Cap is 5 (full copies; named snapshots cover deep history; cost: one const). Both `SaveFile` and `SaveBytes` back up (every write counts; locked files back up ciphertext); a missing destination means no backup. Order inside the write: encode first (encode failures write nothing), then the backup, then the temp commit, then rotation (never delete before the replacement lands). Backup failures map through the §5 redirect map (locked destinations redirect with nothing overwritten so no backup is owed, anything else `SaveFailed` with the original untouched); rotation-delete failures are best-effort and never fail the save. Backups commit atomically through the same temp-move. The §5 atomic-save leftover test is updated to expect the sibling (contract change this section mandates; its no-temp-debris intent is preserved as a `.tmp` check). Cheaper substitute that fails the checkpoint: one .bak that the next save eats.

**Chrome:** No new surface; the file list is the surface.

**Needs:** Windows host (build/test)

- [x] Every save writes a timestamped .bak sibling first. Done when: the sibling predates the save under host drive. **Driven 2026-09-16:** `SaveWritesSiblingWithPreSaveBytes` (sibling holds the pre-save bytes, file holds the edit) plus `SecondSaveKeepsPreSaveBytesInSibling` and `SaveBytesBacksUpToo`, green.
- [x] Retention caps the sibling count. Done when: old siblings rotate out at the cap. **Driven 2026-09-16:** `RotationEvictsOldestSeededSibling` (seeded cap plus one save evicts the oldest, foreign `.bak` untouched) plus `RetentionRotatesPastFive` (seven real saves hold five) and `ForeignBakFilesAreLeftAlone`, green.
- [x] A crashed save leaves the newest .bak intact. Done when: the failure path is driven. **Driven 2026-09-16:** `FailedSaveStillWritesSibling` (read-only destination: save redirects, sibling holds the original, file untouched) plus `FaultBeforeCommitLeavesSiblingAndOriginalIntact` (injected fault: sibling plus original intact), green.
- [x] Commit: `"notepad-core: back up on save"`

**Test checkpoint:** sibling, retention, and crash safety are all driven in the room. Cheaper substitute that fails: backups that pile up forever.

> **Verified:** 2026-09-16 | §20 | Backup on save: every SaveFile and SaveBytes commit keeps the pre-save bytes in a timestamped sibling first, cap 5 with oldest-first rotation of own-pattern names, backup failures map through the §5 redirect map, rotation best-effort after the commit; UI BackupTests 3/3, Unit FileSaveBackupTests 5/5, full gate Smoke 1/1 Unit 224/224 Protocol 35/35 UI 93 plus 1 pre-existing quarantine of 94, build 0 warnings; validate 0 fatal; self-test 393/393
> **Review:** rounds 1, candidate f32b447 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s20.md
> **CRUD:** applicable | each save wrote a sibling with the pre-save bytes (read back exact); rotation deleted the oldest past the cap (read back absent, foreign `.bak` untouched); the failed save wrote a sibling and left the file untouched (both read back); no temp debris left behind
> **Duration:** 17
> **Implementer:** Muse Code (Meta Muse Spark)

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

## 27. Tab-Strip Chrome Parity Repair

> **Started:** 2026-09-15T13:25:00Z

Why this section exists: the operator compared the app against Windows 11 Notepad side by side and reported four chrome defects (2026-09-15): the add-tab button slides under the caption buttons on a full strip, it sits top-hugged with zero tabs, the toolbar band carries too much padding (top worst), and the dirty dot reads half-size. Canonical captures plus same-screen probes measured every one: the add center sat 67 DIP inside the caption zone (tucked under maximize at 12 tabs), the zero-tab add centered 17px above the strip middle, our editor started at 96 DIP against stock's 75, and our bullet-glyph dot rendered 5px against stock's 10-11px at 150%.

**Fidelity:** stock tab bar -- `resources/baseline/stock/notepad-tabs-n11.2607.14.0-win25h2.png` (strip 0-42, tab bottom edge 41, File text 53-63, editor step 75, all canonical DIP) plus the live dirty-dot probe (stock dot 10-11px at 150%, 154 gray; stock tab text center 26.5 DIP, add glyph center 25.5 DIP). Row heights, add placement, and dot size match these numbers; the 2.5px-high tab text (template pads) is recorded non-parity.

**Job:** The user can compare our chrome against Notepad without seeing a difference. Consumer: the §1 shell rows and the §3 strip, which this section re-measures without changing their contracts.

**Treatment:** Measured geometry, not restyle: 43/32-DIP shell rows land the editor at stock's 75; a caption-width inset (AppWindow RightInset) parks the add button left of minimize with shrink-to-fit reading the narrowed strip; the zero-tab add re-margins to the strip middle (stock has no zero-tab state, so centered-to-match is by construction); the dot becomes a 6-DIP ellipse at stock gray keeping its "•" accessible name; tab items bottom-hug with a second drag rect covering the band above them.

**Chrome:** No new surface; the strip, menu band, and dot are the surface.

**Needs:** Windows host (build/test)

- -> XREF: D01 T01 §1 -- the shell rows this re-measures; §1 item 1 points here for the measured heights
- -> XREF: D01 T01 §3 -- the strip, dot, and add button this repairs; §3 item 1 points here for the measured geometry, and the zero-tab default there is now probed
- -> SOURCE: operator chrome report 2026-09-15 (four defects) plus the canonical-capture measurement campaign

- [x] Shell rows are 43/32 DIP with the editor step at 75. Done when: the canonical capture measures the editor step at 75. **Measured 2026-09-15:** editor step at capture y114 (150%) = 76 DIP, 1px rounding over stock's 75.
- [x] A full 12-tab strip parks the add button left of minimize. Done when: `FullStripParksAddButtonLeftOfCaption` passes (add right at most minimize left). **Measured 2026-09-15:** add center x1030 vs caption zone from x1132 (94px clearance); pre-fix the add sat under maximize at x1239.
- [x] The zero-tab strip centers the add button. Done when: `ZeroTabsCentersAddButton` passes (within 8px of strip center). **Measured 2026-09-15:** add center 33 vs strip center 32.25; pre-fix it top-hugged 17px high.
- [x] The dirty dot is a 6-DIP ellipse at stock gray keeping the "•" accessible name. Done when: the capture measures ~9px/156 and the §3 dot drives stay green. **Measured 2026-09-15:** dot 9px peak 156 vs stock 10-11px/154 (pre-fix 5px near-white); `DirtyClosePromptsAndCancelKeepsTheTab` plus `InitialTabRendersFromModel` green on the kept name.
- [x] Last-tab close after move/resize never crashes 0xC000027B (template sets run one dispatch past layout; stowed reads are caught). Done when: repeated closes stay alive where 3/3 crashed pre-fix. **Driven 2026-09-15:** 3/3 native crashes pre-fix (event log 0xC000027B in Microsoft.UI.Xaml.dll), 5/5 alive post-fix.
- [x] The shell golden is refreshed per procedure and the full gate is green. Done when: `main-window.png` shows the new chrome with an inspected diff, and Smoke/Unit/Protocol/UI pass with 0 warnings. **Driven 2026-09-15:** golden recaptured (diff: chrome shift plus sub-threshold Mica tint) and green; Smoke 1/1, Unit 148/148, Protocol 35/35, UI 37/38 with the 1 pre-existing quarantine.
- [x] Commit: `"notepad-core: repair tab-strip chrome parity"`

**Test checkpoint:** add-vs-caption, zero-tab centering, dot size/color, and crash survival are all measured in the room, and the §3 dot contract plus the full suite stay green. Cheaper substitute that fails: geometry asserted from constants without rendering the strip.
> **Verified:** 2026-09-15 | §27 | Tab-strip chrome parity repair: 43/32 rows with the editor step at 76 DIP (1px rounding over stock 75), full-strip add parked left of minimize, zero-tab add centered, 6-DIP dot at stock gray with the kept bullet name, last-tab close crash-free, golden refreshed; ChromeTests 2/2, Smoke 1/1, Unit 148/148, Protocol 35/35, UI 37 plus 1 pre-existing quarantine of 38, build 0 warnings; tab-top clicks proven live; validate 0 fatal; self-test 393/393
> **Review:** round 1, candidates 1b19937 69d082f -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve · `design` approve. Raw findings: docs/reviews/01-notepad-core/D01-T01-s27.md

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

## 30. Locked-Tab Residue Hardening

Why this section exists: §19 locks the file but the decrypted buffer still rests on disk outside it: snapshot sidecars (§16) store buffer bytes, and session restore (§6) plus the crash checkpoint (§7, same file) persist dirty buffers. The password and key stay memory-only per §19; this section extends the guarantee to the buffer.

**Fidelity:** new build, no baseline (stock Notepad encrypts nothing).

**Job:** Locked tabs leave no plaintext on disk outside the locked file. Consumer: the §19 lock flow, which gains residue-free persistence.

**Treatment:** Takes on locked tabs are refused with an inline note in the versions dialog (a state, not a deferral, mirrors the §16 save-first note; prompting for a re-lock password per take is the rejected alternative, cost one dialog plus the drives). Session and checkpoint persistence omit locked-tab buffers (path-only entries, which restore as ghosts through the §19 ghost rule). Residues written before this section ships are left in place and named in the §19 doc (no retroactive wipe; cost: a one-way migration). Cheaper substitute that fails the checkpoint: a unit-only assertion with the room paths untouched.

**Chrome:** Reuse the save-first note treatment. Do not invent a second refusal treatment.

**Needs:** Windows host (build/test)

- -> SOURCE: §19 review advisory (a), 2026-09-16 (decrypted-buffer residues in snapshots, session, and checkpoint)

- [ ] Takes on locked tabs are refused with an inline note and no sidecar written. Done when: the room shows the note and the sidecar directory stays absent.
- [ ] Session and checkpoint persistence omit locked-tab buffers. Done when: path-only entries restore as ghosts, driven.
- [ ] Room drives prove no plaintext reaches disk for locked tabs. Done when: the sidecar scan and the app-data scan both come back clean.
- [ ] Commit: `"notepad-core: harden locked-tab residues"`

**Test checkpoint:** refused takes, path-only persistence, and both disk scans are all driven in the room. Cheaper substitute that fails: plaintext asserted absent only where the test looked before.

## Verification

- [ ] `dotnet test` green
- [ ] Round-trip matrix byte-identical across encodings and line endings
- [ ] No destructive path without its prompt, all driven
- [ ] `python3 scripts/todo-graph.py validate` clean
