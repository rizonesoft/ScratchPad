# 01 Notepad Core

> **Phase 1**

The WinUI 3 app spine and its chrome: window, tab model, file IO, menus, settings, status bar. Windows 11 Notepad parity is the bar; every section here carries Fidelity against the captured baseline.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-winui-app-spine.md) | WinUI App Spine | `draft` |
| [TODO-02](./TODO-02-menus-settings-status.md) | Menus, Settings and Status | `draft` |

## In scope

- App window, tab bar, tab model with dirty tracking
- File open/save/Save As with encoding and line-ending handling
- Menu bar, settings page, status bar, print slice

## Out of scope

- The editing surface itself (02-editor owns the text engine; this domain hosts it)
- AI surfaces (05-ai-surface)
- Test strategy content (06-quality); this domain writes the tests its sections owe

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
