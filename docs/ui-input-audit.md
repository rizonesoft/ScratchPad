# UI Input Audit (D00 T02 §8 item 1)

Measured 2026-09-17: 112 focus-dependent input calls across tests/UI: 87 convert, 25 fence, 0 keep after migration corrections (5 provisional converts proved fence-or-misattributed; plus 22 click sites: 1 convert, 17 fence, 4 keep; plus 51 Focus sites by rule; plus 2 raw-input sites, both fence). **Corrected 2026-09-19 (§8 R5):** was 88/24; recount 87 convert plus 25 fence (whole file 88/44/4, totals 112 and 187 intact). Every call is either convertible or genuinely physical; nothing keeps focus input by inertia.

| Site | Enclosing method | Call | Disposition | Rationale |
| ---- | ---------------- | ---- | ----------- | --------- |
| `tests/UI/BackupTests.cs:241` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/BackupTests.cs:243` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/BackupTests.cs:248` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/BackupTests.cs:250` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/BackupTests.cs:255` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ChromeTests.cs:120` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ChromeTests.cs:122` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/DirtyPromptTests.cs:287` | KillRecoversBuffersSilentlyWithFilesUntouched | Keyboard.Type | convert | dirtying only; ValuePattern |
| `tests/UI/DirtyPromptTests.cs:291` | KillRecoversBuffersSilentlyWithFilesUntouched | Keyboard.Type | convert | dirtying only; ValuePattern |
| `tests/UI/DirtyPromptTests.cs:370` | FreshTypingDeletesStaleSession | Keyboard.Type | convert | dirtying only; ValuePattern |
| `tests/UI/DirtyPromptTests.cs:593` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/DirtyPromptTests.cs:595` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/DirtyPromptTests.cs:600` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/DirtyPromptTests.cs:602` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/DirtyPromptTests.cs:607` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/EncryptedNotesTests.cs:469` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/EncryptedNotesTests.cs:471` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/EncryptedNotesTests.cs:476` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/EncryptedNotesTests.cs:478` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/EncryptedNotesTests.cs:483` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ExportTests.cs:264` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ExportTests.cs:266` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ExportTests.cs:271` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ExportTests.cs:273` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ExportTests.cs:278` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LaunchTests.cs:214` | MissingFileOfferYesBindsTabAndSaveCreates | Keyboard.Type | convert | text content only; ValuePattern |
| `tests/UI/LaunchTests.cs:257` | MissingFileOfferEnterAcceptsAsYes | Keyboard.Press | fence | ENTER acceptance IS the point |
| `tests/UI/LaunchTests.cs:863` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LaunchTests.cs:865` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LaunchTests.cs:870` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LockedResidueTests.cs:291` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LockedResidueTests.cs:293` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LockedResidueTests.cs:298` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LockedResidueTests.cs:300` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/LockedResidueTests.cs:305` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MenuBarTests.cs:248` | AccessKeysOpenEachMenu | Keyboard.Pressing | fence | Alt access keys ARE the point |
| `tests/UI/MenuBarTests.cs:250` | AccessKeysOpenEachMenu | Keyboard.Press | fence | Alt access keys ARE the point |
| `tests/UI/MenuBarTests.cs:567` | FileOpenOpensExactlyOneFile | Keyboard.Press | fence | test fenced (dialog needs real clicks); stays physical (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:589` | FileOpenOpensExactlyOneFile | Keyboard.Pressing | fence | test fenced (dialog needs real clicks); stays physical (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:591` | FileOpenOpensExactlyOneFile | Keyboard.Press | fence | test fenced (dialog needs real clicks); stays physical (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:1239` | DismissMenu | Keyboard.Press | convert | Collapse pattern on the menu |
| `tests/UI/MenuBarTests.cs:1619` | EncodingComboItems | Keyboard.Press | fence | misattributed to DialogText by the inventory regex; combo dismiss inside fenced FileOpenShowsPickerWithEncodingList, stays physical (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:1705` | SelectAll | Keyboard.Pressing | convert | text selection range via TextPattern |
| `tests/UI/MenuBarTests.cs:1707` | SelectAll | Keyboard.Press | convert | text selection range via TextPattern |
| `tests/UI/MenuBarTests.cs:1748` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MenuBarTests.cs:1750` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MenuBarTests.cs:1755` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MultiWindowTests.cs:100` | TabDragOutsideStripDetachesNothing | Mouse.Position | fence | drag physics IS the point |
| `tests/UI/MultiWindowTests.cs:102` | TabDragOutsideStripDetachesNothing | Mouse.Down | fence | drag physics IS the point |
| `tests/UI/MultiWindowTests.cs:107` | TabDragOutsideStripDetachesNothing | Mouse.Position | fence | drag physics IS the point |
| `tests/UI/MultiWindowTests.cs:115` | TabDragOutsideStripDetachesNothing | Mouse.Up | fence | drag physics IS the point |
| `tests/UI/MultiWindowTests.cs:195` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MultiWindowTests.cs:197` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MultiWindowTests.cs:202` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MultiWindowTests.cs:204` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/MultiWindowTests.cs:209` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/PinnedTabsTests.cs:362` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/PinnedTabsTests.cs:364` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/PinnedTabsTests.cs:369` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ReloadTests.cs:480` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ReloadTests.cs:482` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ReloadTests.cs:487` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ReloadTests.cs:489` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/ReloadTests.cs:494` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SessionRestoreTests.cs:66` | QuitAndRelaunchRestoresTabsContentsAndCarets | Keyboard.Type | fence | caret-offset asserts need real keystroke insertion |
| `tests/UI/SessionRestoreTests.cs:71` | QuitAndRelaunchRestoresTabsContentsAndCarets | Keyboard.Type | fence | caret-offset asserts need real keystroke insertion |
| `tests/UI/SessionRestoreTests.cs:579` | PositionCaretFromEnd | Keyboard.Pressing | fence | caret positioning probe needs real keys |
| `tests/UI/SessionRestoreTests.cs:581` | PositionCaretFromEnd | Keyboard.Press | fence | caret positioning probe needs real keys |
| `tests/UI/SessionRestoreTests.cs:587` | PositionCaretFromEnd | Keyboard.Press | fence | caret positioning probe needs real keys |
| `tests/UI/SessionRestoreTests.cs:602` | AssertTypeLandsAt | Keyboard.Type | fence | insert-at-caret probe needs real keys |
| `tests/UI/SessionRestoreTests.cs:645` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SessionRestoreTests.cs:647` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SessionRestoreTests.cs:652` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SessionRestoreTests.cs:654` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SessionRestoreTests.cs:659` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SettingsPageTests.cs:642` | PickFamily | Keyboard.Press | convert | dialog Close-button Invoke |
| `tests/UI/SettingsPageTests.cs:679` | DismissMenu | Keyboard.Press | convert | Collapse pattern on the menu |
| `tests/UI/SnapshotTests.cs:498` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SnapshotTests.cs:500` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SnapshotTests.cs:505` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SnapshotTests.cs:507` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/SnapshotTests.cs:512` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatsPanelTests.cs:329` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatsPanelTests.cs:331` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatsPanelTests.cs:336` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatsPanelTests.cs:338` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatsPanelTests.cs:343` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatusBarTests.cs:64` | KeystrokesAndCaretMovesUpdateStrip | Keyboard.Type | fence | keystroke handling IS the point |
| `tests/UI/StatusBarTests.cs:66` | KeystrokesAndCaretMovesUpdateStrip | Keyboard.Press | fence | keystroke handling IS the point |
| `tests/UI/StatusBarTests.cs:71` | KeystrokesAndCaretMovesUpdateStrip | Keyboard.Press | fence | keystroke handling IS the point |
| `tests/UI/StatusBarTests.cs:98` | TabSwitchUpdatesStrip | Keyboard.Type | convert | text content only; ValuePattern |
| `tests/UI/StatusBarTests.cs:424` | DismissMenu | Keyboard.Press | convert | Collapse pattern on the menu |
| `tests/UI/StatusBarTests.cs:443` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatusBarTests.cs:445` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/StatusBarTests.cs:450` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TabAccessibilityTests.cs:127` | PressClose | Keyboard.Pressing | convert | close-button Invoke; shortcut is not the point |
| `tests/UI/TabAccessibilityTests.cs:129` | PressClose | Keyboard.Press | convert | close-button Invoke; shortcut is not the point |
| `tests/UI/TabBarTests.cs:222` | DragAttemptLeavesOrderUnchanged | Mouse.Position | fence | drag physics IS the point |
| `tests/UI/TabBarTests.cs:224` | DragAttemptLeavesOrderUnchanged | Mouse.Down | fence | drag physics IS the point |
| `tests/UI/TabBarTests.cs:229` | DragAttemptLeavesOrderUnchanged | Mouse.Position | fence | drag physics IS the point |
| `tests/UI/TabBarTests.cs:237` | DragAttemptLeavesOrderUnchanged | Mouse.Up | fence | drag physics IS the point |
| `tests/UI/TabBarTests.cs:383` | ContextMenuDrives | Keyboard.Press | fence | test fenced (context menu needs the cursor); ESC stays physical (corrected 2026-09-17) |
| `tests/UI/TabBarTests.cs:538` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TabBarTests.cs:540` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TabBarTests.cs:545` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TabBarTests.cs:547` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TabBarTests.cs:552` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TemplateTests.cs:378` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TemplateTests.cs:380` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TemplateTests.cs:385` | Press | Keyboard.Pressing | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TemplateTests.cs:387` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |
| `tests/UI/TemplateTests.cs:392` | Press | Keyboard.Press | convert | fold into shared UiInput; call sites migrate to patterns or fenced Press |

## Cursor-moving clicks (added 2026-09-17)

Element `.Click()`/`.DoubleClick()`/`.RightClick()` move the real cursor, so they interrupt exactly like physical keys. 22 sites: 1 convert, 17 fence, 4 keep (final; the provisional converts proved fence-or-keep during migration, see corrections).

| Site | Enclosing method | Call | Disposition | Rationale |
| ---- | ---------------- | ---- | ----------- | --------- |
| `tests/UI/LaunchTests.cs:248` | MissingFileOfferEnterAcceptsAsYes | Click | fence | test already fenced: ENTER acceptance IS the point |
| `tests/UI/MenuBarTests.cs:1231` | OpenSubmenu | Click | keep | pattern-first with Click fallback; fallback audited by the foreground log (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:1294` | InvokeOrClick | Click | keep | fallback only when Invoke unsupported; foreground log audits any hit |
| `tests/UI/MenuBarTests.cs:1544` | ExpandCombo | Click | fence | inside fenced FileOpenShowsPickerWithEncodingList; stays physical (corrected 2026-09-17) |
| `tests/UI/MenuBarTests.cs:1648` | SelectEncoding | Click | fence | inside fenced FileOpenShowsPickerWithEncodingList; stays physical (corrected 2026-09-17) |
| `tests/UI/PinnedTabsTests.cs:31` | DoubleClickTogglesPinGlyph | DoubleClick | fence | double-click IS the point; no pattern path pins a tab |
| `tests/UI/PinnedTabsTests.cs:33` | DoubleClickTogglesPinGlyph | DoubleClick | fence | double-click IS the point; no pattern path pins a tab |
| `tests/UI/PinnedTabsTests.cs:61` | PinsSurviveRelaunch | DoubleClick | fence | pin setup needs the cursor; no pattern path pins a tab |
| `tests/UI/PinnedTabsTests.cs:115` | CloseOthersSkipsPinned | DoubleClick | fence | pin setup needs the cursor; no pattern path pins a tab |
| `tests/UI/PinnedTabsTests.cs:117` | CloseOthersSkipsPinned | RightClick | fence | context menu needs the cursor |
| `tests/UI/PinnedTabsTests.cs:158` | CloseRightSkipsPinned | DoubleClick | fence | pin setup needs the cursor; no pattern path pins a tab |
| `tests/UI/PinnedTabsTests.cs:160` | CloseRightSkipsPinned | RightClick | fence | context menu needs the cursor |
| `tests/UI/PinnedTabsTests.cs:202` | SingleCloseStillClosesPinned | DoubleClick | fence | pin setup needs the cursor; no pattern path pins a tab |
| `tests/UI/SettingsPageTests.cs:691` | InvokeOrClick | Click | keep | fallback only when Invoke unsupported; foreground log audits any hit |
| `tests/UI/StatusBarTests.cs:106` | TabSwitchUpdatesStrip | Click | convert | tab SelectionItem pattern switches without the cursor |
| `tests/UI/StatusBarTests.cs:178` | StatusSegmentsHaveNoClickPath | Click | fence | the click IS the point (proves no-op) |
| `tests/UI/TabBarTests.cs:378` | ContextMenuDrives | RightClick | fence | context menu IS the point |
| `tests/UI/TabBarTests.cs:388` | ContextMenuDrives | RightClick | fence | context menu IS the point |
| `tests/UI/TabBarTests.cs:409` | ContextMenuDrives | RightClick | fence | context menu IS the point |
| `tests/UI/TabBarTests.cs:416` | ContextMenuDrives | RightClick | fence | context menu IS the point |
| `tests/UI/UiCapture.cs:88` | PrepareSettings | Click | keep | fallback only when Invoke unsupported; foreground log audits any hit |
| `tests/UI/MenuBarTests.cs:1272` | ClickFoundItem | Click | fence | MouseOnlyItems path: Invoke blocks on the synchronous native dialog (recorded in 156839b; the §8 Invoke spike hung corroborating it), so dialog tests keep real clicks |

## Focus calls (added 2026-09-17)

`Focus()` on a background window activates it, so it interrupts exactly like physical input. 51 sites dispositioned by rule instead of by row: each dies with its input site in default-suite tests (patterns need no focus, spiked) and stays in fenced interactive tests. The foreground log plus suite green proves every site resolved.

| Site | Enclosing method | Disposition |
| ---- | ---------------- | ----------- |
| `tests/UI/BackupTests.cs:237` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ChromeTests.cs:118` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/DirtyPromptTests.cs:286` | KillRecoversBuffersSilentlyWithFilesUntouched | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/DirtyPromptTests.cs:290` | KillRecoversBuffersSilentlyWithFilesUntouched | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/DirtyPromptTests.cs:369` | FreshTypingDeletesStaleSession | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/DirtyPromptTests.cs:589` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/EncryptedNotesTests.cs:465` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ExportTests.cs:260` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/LaunchTests.cs:213` | MissingFileOfferYesBindsTabAndSaveCreates | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/LaunchTests.cs:859` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/LockedResidueTests.cs:287` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:244` | AccessKeysOpenEachMenu | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:563` | FileOpenOpensExactlyOneFile | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:587` | FileOpenOpensExactlyOneFile | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:1209` | OpenMenu | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:1703` | SelectAll | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MenuBarTests.cs:1728` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/MultiWindowTests.cs:191` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/PinnedTabsTests.cs:358` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:35` | CleanChangePromptsAndReloadRefreshes | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:71` | KeepHoldsBufferAndDirties | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:116` | CancelKeepsLikeKeep | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:156` | DirtyReloadDiscardsEdits | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:192` | DirtyKeepPreservesEdits | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:228` | UntitledAndIdenticalWritesNeverPrompt | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:261` | DeletedFileReloadFailsLoud | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:301` | LockedReloadRoutesThroughUnlock | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/ReloadTests.cs:476` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SessionRestoreTests.cs:65` | QuitAndRelaunchRestoresTabsContentsAndCarets | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SessionRestoreTests.cs:70` | QuitAndRelaunchRestoresTabsContentsAndCarets | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SessionRestoreTests.cs:577` | PositionCaretFromEnd | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SessionRestoreTests.cs:600` | AssertTypeLandsAt | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SessionRestoreTests.cs:641` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SettingsPageTests.cs:347` | EditFontMenuJumpsToSettings | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/SnapshotTests.cs:494` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/StatsPanelTests.cs:325` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/StatusBarTests.cs:63` | KeystrokesAndCaretMovesUpdateStrip | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/StatusBarTests.cs:97` | TabSwitchUpdatesStrip | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/StatusBarTests.cs:413` | OpenMenu | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/StatusBarTests.cs:439` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabAccessibilityTests.cs:125` | PressClose | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:70` | ThreeTabsSwitchAndClose | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:142` | NumberShortcutsAndReopenMatchNotepad | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:198` | DragAttemptLeavesOrderUnchanged | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:271` | DirtyClosePromptsAndCancelKeepsTheTab | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:309` | DontSaveClosesAndNeverReopens | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:342` | ContextMenuMatchesNotepad | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:433` | MiddleClickClosesTheTabUnderTheCursor | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TabBarTests.cs:534` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/TemplateTests.cs:374` | Press | rule: dropped in default tests with its input site, kept in fenced tests |
| `tests/UI/UiInput.cs:18` | Press | rule: dropped in default tests with its input site, kept in fenced tests |

## Raw input APIs (added 2026-09-17)

`SetCursorPos` plus `mouse_event` move the real cursor outside FlaUI, so they interrupt like any physical input. Two helpers, both fenced with their tests.

| Site | Enclosing method | Call | Disposition | Rationale |
| ---- | ---------------- | ---- | ----------- | --------- |
| `tests/UI/TabBarTests.cs:571` | MiddleClick | SetCursorPos + mouse_event | fence | middle-click IS the point (FlaUI middle-click never lands the close) |
| `tests/UI/TitleBarIconTests.cs:146` | LeftClick | SetCursorPos + mouse_event | fence | real click through the caption zone IS the point (hit-testing invisible to Invoke) |

## Accelerator binding sweep (D00 T02 §12 item 1)

Swept 2026-09-20: every `KeyboardAccelerator` declared in `src/ScratchPad/MenuBar.xaml` (31 declarations) plus the 13 programmatic tab accelerators in `src/ScratchPad/MainWindow.xaml.cs` `AddTabAccelerators` (no other key handling in `src/`: no `KeyDown`/`PreviewKeyDown` handlers, no other XAML accelerators) against physical-press coverage in `tests/UI` (`UiInput.Press` plus `Keyboard.Press` call sites). **Corrected 2026-09-20 (§12 review R1):** was 31 XAML only; the sweep missed the 13 programmatic tab bindings. A binding is covered only by a test pressing the physical chord; menu-Invoke tests assert the command, not the binding.

| Binding | Command | Covering test or none |
| ------- | ------- | --------------------- |
| Ctrl+N | File: New tab | `MenuBarTests.FileMenuLiveAcceleratorsWork` |
| Ctrl+Shift+N | File: New window | none (restored by §12 item 2) |
| Ctrl+O | File: Open | `MenuBarTests.FileMenuLiveAcceleratorsWork` |
| Ctrl+S | File: Save | `MenuBarTests.FileSaveOnUntitledOpensSaveAs` |
| Ctrl+Shift+S | File: Save as | `MenuBarTests.FileMenuLiveAcceleratorsWork` |
| Ctrl+Alt+S | File: Save all | `MenuBarTests.FileSaveAllWalksDirtyTabs` |
| Ctrl+P | File: Print (disabled) | none: command disabled (pending-owner per D01 T02 §1); no dispatch to assert until it ships |
| Ctrl+W | File: Close tab | `TabBarTests.ThreeTabsSwitchAndClose` |
| Ctrl+Shift+W | File: Close window | `MenuBarTests.FileMenuLiveAcceleratorsWork` |
| Ctrl+Z | Edit: Undo (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+X | Edit: Cut (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+C | Edit: Copy (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+V | Edit: Paste (disabled) | none: command disabled; no dispatch to assert until it ships |
| Delete | Edit: Delete (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+E | Edit: Search with Bing | none: effect escapes the app (`Launcher.LaunchUriAsync` opens the system browser); URL shape unit-pinned by `BingSearchTests` |
| Ctrl+E | Edit: Define with Bing | none: same chord as Search with Bing (duplicate declaration); same browser-launch reason; URL shape unit-pinned by `BingSearchTests` |
| Ctrl+F | Edit: Find (disabled) | none: command disabled; no dispatch to assert until it ships |
| F3 | Edit: Find next (disabled) | none: command disabled; no dispatch to assert until it ships |
| Shift+F3 | Edit: Find previous (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+H | Edit: Replace (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+G | Edit: Go to (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+A | Edit: Select all (disabled) | none: command disabled; no dispatch to assert until it ships |
| F5 | Edit: Time/Date (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+Plus | View: Zoom in (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+Minus | View: Zoom out (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+0 | View: Restore default zoom (disabled) | none: command disabled; no dispatch to assert until it ships |
| Ctrl+Shift+G | Tools: Statistics | none (restored by §12 item 2) |
| Ctrl+Shift+H | Tools: Snapshots | none (restored by §12 item 2) |
| Ctrl+Shift+E | Tools: Templates | none (restored by §12 item 2) |
| Ctrl+Shift+X | Tools: Export | none (restored by §12 item 2) |
| Ctrl+Shift+L | Tools: Lock file | none (restored by §12 item 2) |
| Ctrl+T | Tabs: new tab (programmatic) | `TabBarTests`, `PinnedTabsTests` |
| Ctrl+Tab | Tabs: cycle next (programmatic) | `TabBarTests.ThreeTabsSwitchAndClose` |
| Ctrl+Shift+Tab | Tabs: cycle previous (programmatic) | `TabBarTests.NumberShortcutsAndReopenMatchNotepad` |
| Ctrl+Shift+T | Tabs: reopen last (programmatic) | `TabBarTests.NumberShortcutsAndReopenMatchNotepad` |
| Ctrl+1 | Tabs: goto 1 (programmatic) | `TabBarTests.ThreeTabsSwitchAndClose` |
| Ctrl+2 | Tabs: goto 2 (programmatic) | none (restored by §12 item 2) |
| Ctrl+3 | Tabs: goto 3 (programmatic) | `TabBarTests.NumberShortcutsAndReopenMatchNotepad` |
| Ctrl+4 | Tabs: goto 4 (programmatic) | none (restored by §12 item 2) |
| Ctrl+5 | Tabs: goto 5 (programmatic) | none (restored by §12 item 2) |
| Ctrl+6 | Tabs: goto 6 (programmatic) | none (restored by §12 item 2) |
| Ctrl+7 | Tabs: goto 7 (programmatic) | none (restored by §12 item 2) |
| Ctrl+8 | Tabs: goto 8 (programmatic) | none (restored by §12 item 2) |
| Ctrl+9 | Tabs: goto last (programmatic) | `TabBarTests.NumberShortcutsAndReopenMatchNotepad` |

Pressed but not app-declared (framework or control behavior, outside the sweep; covering tests named so a future declaration does not double-cover): Ctrl+Home/Ctrl+End (caret moves in `StatusBarTests`/`SessionRestoreTests`), Alt+letter access keys (`MenuBarTests.AccessKeysOpenEachMenu`). **Corrected 2026-09-20 (§12 review R1):** was including tab chords as framework; Ctrl+T, Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+Shift+T, and Ctrl+1..9 are app-declared in `AddTabAccelerators` and now ride the table above.