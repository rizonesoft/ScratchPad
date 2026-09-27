# Menu and Shortcut Audit (D01 T02 §6)

Every menu item the app ships, read against the stock captures (`resources/baseline/stock/notepad-menu-file-n11.2607.14.0-win25h2.png`, `notepad-menu-edit-...`, `notepad-menu-view-...`, `notepad-menu-view-zoom-...`, `notepad-menu-view-markdown-...`) and `src/ScratchPad/MenuBar.xaml`, each resolved to working (a named test invokes it through the real menu) or to the open section that owns it.

This file is not a one-time sweep. `tests/UI/MenuAuditTests.cs` parses the table below and fails the run when the live menu drifts from it: an item missing, extra, relabeled, or reordered; a `working` or `owner-owed` item disabled (a dead item); a `pending` item enabled without its row moving; a `working` row whose named test no longer exists or no longer names the item; or a `pending` or `owner-owed` owner that is no longer an open row in `todo/implementation-plan.md` (the owner shipped and the item stayed dead). `MenuAuditTests.InWindowItemsInvokeThroughTheMenu` also invokes the in-window working items itself, focus-free.

## Statuses

| Status | Meaning | Enabled | Last cell |
| --- | --- | --- | --- |
| `working` | the item is live and a named test invokes it through the real menu | yes | the proving test, `Class.Method` |
| `container` | a submenu parent; its children carry their own rows | yes | `-` |
| `owner-owed` | the item is live but its menu-driven proof is owed by an open section | yes | the owing section, `DNN TNN §N` |
| `pending` | the item ships disabled until its owner lands (accounted, not dead) | no | the owning section, `DNN TNN §N` |

## Enablement rule

Stock enables every File and Edit item in every probed state (empty buffer, text, selected text; D01 T02 §1 item 3, probed 2026-09-16), so the rule is: every `working` and `owner-owed` item is enabled in every state, and every `pending` item is disabled until its owner enables it on landing. `MenuBarTests.LiveItemsStayEnabledAcrossStates` drives the three states; this audit pins the per-item status.

## Items

The Shortcut column is the text stock displays (the chord declared in `MenuBar.xaml` is the same key; `docs/ui-input-audit.md` owns chord coverage).

| Menu | Item | AutomationId | Shortcut | Status | Proof or owner |
| --- | --- | --- | --- | --- | --- |
| File | New tab | `MenuFileNewTab` | Ctrl+N | working | `MenuBarTests.FileNewTabOpensAndFocusesTab` |
| File | New window | `MenuFileNewWindow` | Ctrl+Shift+N | working | `MenuBarTests.FileNewWindowOpensSecondWindow` |
| File | New Markdown tab | `MenuFileNewMarkdownTab` | - | pending | D02 T04 §1 |
| File | Open | `MenuFileOpen` | Ctrl+O | working | `MenuBarTests.FileOpenLoadsFileWithForcedEncoding` |
| File | Recent | `MenuFileRecent` | - | working | `MenuBarTests.FileRecentRendersListClearAndReopen` |
| File | Save | `MenuFileSave` | Ctrl+S | working | `MenuBarTests.FileSaveWritesPathedTabInPlace` |
| File | Save as | `MenuFileSaveAs` | Ctrl+Shift+S | working | `MenuBarTests.FileSaveAsWritesChosenPathAndEncoding` |
| File | Save all | `MenuFileSaveAll` | Ctrl+Alt+S | working | `MenuAuditTests.InWindowItemsInvokeThroughTheMenu` |
| File | Page setup | `MenuFilePageSetup` | - | owner-owed | D01 T02 §5 |
| File | Print | `MenuFilePrint` | Ctrl+P | owner-owed | D01 T02 §5 |
| File | Close tab | `MenuFileCloseTab` | Ctrl+W | working | `MenuBarTests.FileCloseTabFollowsPrompt` |
| File | Close window | `MenuFileCloseWindow` | Ctrl+Shift+W | working | `MenuBarTests.FileCloseWindowPreservesSilently` |
| File | Exit | `MenuFileExit` | - | working | `MenuBarTests.FileExitClosesApp` |
| Edit | Undo | `MenuEditUndo` | Ctrl+Z | pending | D02 T01 §4 |
| Edit | Cut | `MenuEditCut` | Ctrl+X | pending | D02 T01 §3 |
| Edit | Copy | `MenuEditCopy` | Ctrl+C | pending | D02 T01 §3 |
| Edit | Paste | `MenuEditPaste` | Ctrl+V | pending | D02 T01 §3 |
| Edit | Delete | `MenuEditDelete` | Del | pending | D02 T01 §3 |
| Edit | Clear formatting | `MenuEditClearFormatting` | - | pending | D02 T04 §2 |
| Edit | Search with Bing | `MenuEditSearchBing` | Ctrl+E | working | `BingLaunchTests.BingCommandLaunchesItsEscapedUriWithoutABrowser` |
| Edit | Define with Bing | `MenuEditDefineBing` | Ctrl+E | working | `BingLaunchTests.BingCommandLaunchesItsEscapedUriWithoutABrowser` |
| Edit | Find | `MenuEditFind` | Ctrl+F | pending | D02 T02 §2 |
| Edit | Find next | `MenuEditFindNext` | F3 | pending | D02 T02 §2 |
| Edit | Find previous | `MenuEditFindPrevious` | Shift+F3 | pending | D02 T02 §2 |
| Edit | Replace | `MenuEditReplace` | Ctrl+H | pending | D02 T02 §3 |
| Edit | Go to | `MenuEditGoTo` | Ctrl+G | pending | D02 T02 §4 |
| Edit | Select all | `MenuEditSelectAll` | Ctrl+A | pending | D02 T01 §3 |
| Edit | Time/Date | `MenuEditTimeDate` | F5 | pending | D02 T01 §5 |
| Edit | Font | `MenuEditFont` | - | working | `SettingsPageTests.EditFontMenuJumpsToSettings` |
| View | Zoom | `MenuViewZoom` | - | container | - |
| View | Zoom in | `MenuViewZoomIn` | Ctrl+Plus | pending | D02 T01 §5 |
| View | Zoom out | `MenuViewZoomOut` | Ctrl+Minus | pending | D02 T01 §5 |
| View | Restore default zoom | `MenuViewZoomRestore` | Ctrl+0 | pending | D02 T01 §5 |
| View | Status bar | `MenuViewStatusBar` | - | working | `StatusBarTests.ToggleHidesBarAndPersistsAcrossRelaunch` |
| View | Word wrap | `MenuViewWordWrap` | - | pending | D02 T01 §5 |
| View | Markdown | `MenuViewMarkdown` | - | container | - |
| View | Formatted | `MenuViewMarkdownFormatted` | - | pending | D02 T04 §3 |
| View | Syntax | `MenuViewMarkdownSyntax` | - | pending | D02 T04 §3 |
| Tools | Statistics | `MenuToolsStats` | Ctrl+Shift+G | working | `MenuBarTests.ToolsMenuInvokesStats` |
| Tools | Snapshots | `MenuToolsSnapshots` | Ctrl+Shift+H | working | `MenuBarTests.ToolsMenuInvokesSnapshots` |
| Tools | Templates | `MenuToolsTemplates` | Ctrl+Shift+E | working | `MenuBarTests.ToolsMenuInvokesTemplates` |
| Tools | Export | `MenuToolsExport` | Ctrl+Shift+X | working | `MenuBarTests.ToolsMenuInvokesExport` |
| Tools | Lock file | `MenuToolsLock` | Ctrl+Shift+L | working | `MenuBarTests.ToolsMenuInvokesLock` |

## Additions and advisories

- The Tools menu is not in stock: it carries this app's own tools (statistics, snapshots, templates, export, encrypted lock) after View, so File, Edit, and View keep stock order and the menu itself marks the addition (D01 T02 §1 item 4).
- Stock shows toolbar buttons (heading, list, bold, italic, strikethrough, link, table, clear formatting) and a Copilot button beside the menus; they are not menu items and belong to D02 T04 §2, not this audit.
- Accelerator text (D01 T02 §1 review advisory 1): WinUI renders `Delete`, `Ctrl++`, and `Ctrl+-` on the disabled Delete and Zoom items where the stock captures read `Del`, `Ctrl+Plus`, and `Ctrl+Minus`. The keys match the captures; the text difference rides with the owners (D02 T01 §3 for Delete, D02 T01 §5 for Zoom), which drive the items on landing.
- Markdown icons (D01 T02 §1 review advisory 2): stock renders glyph icons on Formatted and Syntax; ours ship plain and disabled, and icon parity rides with D02 T04 §3.
