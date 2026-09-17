# UI Input Audit (D00 T02 §8 item 1)

Measured 2026-09-17: 112 focus-dependent input calls across tests/UI: 88 convert, 24 fence, 0 keep after migration corrections (5 provisional converts proved fence-or-misattributed; plus 22 click sites: 1 convert, 17 fence, 4 keep; plus 51 Focus sites by rule; plus 2 raw-input sites, both fence). Every call is either convertible or genuinely physical; nothing keeps focus input by inertia.

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
