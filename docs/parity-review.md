# Parity Review

Every Notepad reference capture under `resources/baseline/` compared with our app, by eye, on 2026-10-14 (operator request: "do one comparison of every Notepad reference screenshot against our app, and file each difference as intended or as a fix"). Reference build: Windows Notepad 11.2607.14.0 on Windows 11 25H2. Our captures come from `tests/UI/ParityGoldenTests.cs` through `UiCapture.CaptureState`: a fresh seeded profile, the window off-screen and never activated, menus and dialogs composited into the frame, the frame settled before the shutter.

## How to read this record

A surface whose capture was stable across three consecutive runs is a golden under `resources/baseline/app/`, so every section gate re-checks it (`Visual=Golden`). Menus and in-window dialogs are not stable yet: their focus ring and menu row height follow WinUI's ambient input mode, so their captures live in `docs/parity-review/` until D06 T01 §7 pins that mode. A golden records our current approved state, known gaps included; the section that closes a gap refreshes the golden per `resources/baseline/README.md`.

Verdicts: **matches** (no difference beyond capture noise), **intended** (a recorded decision), **owned** (an open section already carries the fix), **filed** (a new section from this review), **open question** (needs an operator decision).

## Differences

| ID | Difference (ours vs Notepad) | Verdict | Owner or decision |
| -- | ---------------------------- | ------- | ----------------- |
| D1 | No formatting toolbar (heading, lists, bold, italic, strikethrough, link, table, clear formatting) | owned | D02 T04 §2 (toolbar), D02 T04 §4 (table) |
| D2a | No Copilot button | intended | D05 T03 §1: the status bar, not a Copilot button, is the agent entry |
| D2b | No account avatar | open question | No section or decision names it; review records point at D04 T02, which has no avatar item |
| D3 | Extra Tools menu | intended | D01 T02 §1, `docs/menu-audit.md:72` |
| D4a | Status bar adds words and reading time, goal flag, reading level | intended | D01 T02 §7, §9, §11 |
| D4b | Status segments packed left; stock places them at fixed positions | filed | D01 T02 §21 |
| D5 | Tabs about 100 px wide (stock about 240), ellipsized titles, close glyph on every tab | filed | D01 T01 §37 |
| D6a | File menu lacks the separators after Save all and after Print (the D01 T02 §1 record is wrong) | filed | D01 T02 §20 |
| D6b | New Markdown tab disabled | owned | D02 T04 §1 |
| D7a | Edit items disabled on an empty document; stock keeps them enabled | owned | D02 T01 §3, §4, §5; D02 T02 §2, §3, §4; D02 T04 §2 (each owner enables its items) |
| D7b | Edit separator grouping differs (the D01 T02 §1 record is wrong) | filed | D01 T02 §20 |
| D7c | Shortcut labels `Delete`, `Ctrl++`, `Ctrl+-` vs stock `Del`, `Ctrl+Plus`, `Ctrl+Minus` | filed | D01 T02 §20 (the earlier deferrals named owners that never carried them) |
| D8a | View > Word wrap disabled and unchecked; Zoom items disabled | owned | D02 T01 §5 |
| D8b | View > Markdown items disabled | owned | D02 T04 §3 |
| D8c | View > Markdown items have no icons | filed | D01 T02 §20 |
| D9a | Settings: no title row (app icon and name), smaller heading, different card icons, always two columns | filed | D01 T02 §22 |
| D9b | Settings: minimal About | owned | D01 T02 §17; the support rows are an intended omission (D01 T02 §3) |
| D9c | Settings: Formatting, Spell check, Autocorrect, Writing tools cards disabled | owned | D02 T04 §5, D02 T03 §4, D05 T02 §6 |
| D10 | OK-only dialogs draw a plain OK; stock draws the accent default button | filed | D01 T01 §38 |
| D11 | Editor text in a proportional font; stock Consolas 11 (our setting already defaults to Consolas) | owned | D02 T01 §3 item 1 |
| D12 | Status bar Markdown switch is a grey button without icon; stock shows the `AA` icon and label without chrome | filed | D01 T02 §21 (look); D02 T04 §3 (enablement) |
| D13 | Light-theme menu: ours sampled flat (249) with no border, stock brighter (252) with a border; inconclusive from an inactive capture | open question | D06 T01 §7 checks it on an active capture |

Not differences: the Mica tint and dimmed caption buttons in our captures come from capturing an inactive window (the Mica behavior itself is `MainWindowTests.ThemesRenderWithMica`).

## Surfaces

| Reference | Our capture | Verdict |
| --------- | ----------- | ------- |
| `stock/notepad-main` | golden `main-window` | D1, D2, D3, D4 |
| `stock/notepad-main-light` | golden `parity-main-light` | as main |
| `stock/notepad-tabs`, `-light` | golden `parity-tabs` | D5, plus main |
| `stock/notepad-firstline-title`, `-truncate` | golden `parity-firstline-truncate` | title from the first line matches; clipping D5 |
| `stock/notepad-settings`, `-light` | goldens `settings-page`, `parity-settings-light` | D9 |
| `session/notepad-when-starts` | golden `parity-when-starts` | expander and options match; D9 |
| `windows/notepad-open-in-setting` | golden `parity-open-in-setting` | D9 |
| `stock/notepad-status-cr` | golden `parity-status-cr` | `Macintosh (CR)` matches; D4 |
| `stock/notepad-status-tabs` | covered by `main-window` and `parity-status-cr` | D4 |
| `stock/notepad-status-md-formatted` | golden `parity-status-md-formatted` | D12 |
| `stock/notepad-status-toggle-off` | golden `parity-status-toggle-off` | matches |
| `session/notepad-session-restored` | golden `parity-session-restored` | restore matches; D11 |
| `stock/notepad-menu-file`, `-light` | `docs/parity-review/parity-menu-file.png`, `parity-menu-file-light.png` | D6, D13 |
| `save/notepad-file-menu-save` | as File menu | D6 |
| `stock/notepad-menu-edit` | `docs/parity-review/parity-menu-edit.png` | D7 |
| `stock/notepad-menu-view`, `-zoom`, `-markdown` | `docs/parity-review/parity-menu-view*.png` | D8 |
| `session/notepad-recents-submenu` | `docs/parity-review/parity-recents-submenu.png` | matches (ours runs past the bottom of the smaller window) |
| `stock/notepad-missing-offer` | `docs/parity-review/parity-missing-offer.png` | matches |
| `stock/notepad-fail-missing` | `docs/parity-review/parity-fail-missing.png` | D10 |
| `stock/notepad-fail-locked` | same dialog as fail-missing | D10 |
| `stock/notepad-fail-unreadable` | none | the reference is byte-identical to `fail-locked` (it shows the locked message), so it proves nothing about the unreadable path; recapture it before relying on it |
| `prompts/notepad-save-prompt-path`, `-untitled` | `docs/parity-review/parity-save-prompt-*.png` | match; D11 behind the dialog |
| `session/notepad-missing-notice` | `docs/parity-review/parity-missing-notice.png` | D10 |
| `stock/notepad-status-md-syntax` | none | Markdown syntax mode is not built yet (D02 T04 §3) |
| `stock/notepad-status-eol-click` | none | shows behavior (clicking segments opens nothing), covered by `StatusBarTests.StatusSegmentsHaveNoClickPath` |
| `stock/notepad-open-dialog`, `-encoding-items`; `save/notepad-saveas-dialog`, `-encoding-items` | none | native file dialogs open only on a physical click (`MenuBarTests` drives them as Interactive tests); the dialog itself is the system's |
| `windows/notepad-new-window-first`, `-second` | none | the second window is born elsewhere, so a one-window capture shows nothing new; `MultiWindowTests` covers the behavior |
