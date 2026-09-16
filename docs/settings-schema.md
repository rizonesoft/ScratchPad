# Settings schema

Store: `src/Notepad.Core/SettingsStore.cs` (owned by D01 T02 §2), file `%LocalAppData%/IntelligentNotepad/settings.json`. One writer: every mutation flows through `SettingsStore.Update`, every persist through `SettingsStore.WriteSnapshot` (atomic temp-file plus move); `ShellSettings.Save` delegates to the write path so test seeding keeps working. Reads are live through `SettingsStore.Shared.Current` plus the `Changed` event; readers must re-read rather than hold the reference because `Update` replaces `Current`. `Update` reloads the file first (out-of-band changes merge instead of clobbering) and rolls `Current` back to the file when the persist throws; UI-thread affinity, reentrant `Update` from inside `Changed` throws. Schema version key `Version` (current 1; absent means the v0 file §2 inherited); migration runs in memory and persists lazily. A file that exists but does not parse, deserializes to null, or claims a future version resets to defaults with `WasResetFromCorrupt` set (surfaced once at startup through `CorruptSettingsDialog`); a missing file or an unreadable one falls back silently. Unknown JSON keys round-trip untouched via `JsonExtensionData`, which is how later AI settings land without a store redesign.

| Key | Type | Default | Default source | Consumer |
| --- | ---- | ------- | -------------- | -------- |
| `Version` | int | 1 | §2 (v0 is the inherited unversioned file) | Store migration |
| `X`, `Y`, `Width`, `Height` | int | 50, 50, 900, 650 | D01 T01 §1 choice | MainWindow restore on open, geometry on close |
| `Theme` | string | `system` | Stock "Use system setting" radio (probed 2026-09-16) | MainWindow theme, §3 page |
| `FontFamily` | string | `Consolas` | Stock font dropdown (UIA dump) plus reset guides | §3 page, D02 T01 |
| `FontStyle` | string | `Regular` | Stock style dropdown selection (probed 2026-09-16) | §3 page, D02 T01 |
| `FontSize` | int | 11 | Stock size dropdown (UIA dump) plus reset guides | §3 page, D02 T01 |
| `WordWrap` | bool | true | Stock settings capture (switch on) | D02 T01 §4 |
| `ShowStatusBar` | bool | true | Stock view-menu capture (checked) | D01 T02 §4 |
| `ZoomDefault` | int | 100 | Recorded default (stock exposes no zoom setting) | D02 T01 §5 |
| `OpenIn` | string | `new-tab` | Stock "Open in a new tab" (capture plus probe) | App launch routing |
| `WhenStarts` | string | `continue` | Stock "Continue previous session" (capture plus probe) | App startup routing |
| `RecentFiles` | string[] | empty | User data, MRU-first | File Recent submenu, jump list |
| `PinnedFiles` | string[] | empty | User data, pin order | Pin state, jump list |
| `JumpListHash` | string | empty | Computed feed fingerprint | JumpListService commit-on-change |
| `WhatsNewSeen` | bool | false | First-run latch | MainWindow first-run gate |

Future keys observed on stock 11.2607.14.0: spellcheck plus autocorrect (D02 T03 §4), formatting (D02 T04 §5), writing tools (D05 T02 §6 item 10), recent-files toggle (D01 T02 §12). Owners add their keys on landing following the extension pattern above (new property, default with a recorded source, row in this table).

Page pattern (D01 T02 §3): each stock card lands in stock position on the settings page bound to its key through `SettingsStore.Update`; cards whose owners have not landed render disabled with the owner recorded in the card comment and enable on landing. Adding a card: XAML card in `SettingsPage.xaml` following the established card treatment, key with a recorded default, row in the table above, owner drive proving both directions.
