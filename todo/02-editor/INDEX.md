# 02 Editor

> **Phase 1**

The editing surface: text engine, caret and selection, undo/redo, zoom, wrap, find/replace, go-to. Hosted by the `01-notepad-core` shell through the contract settled in `TODO-01 §1`.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-01](./TODO-01-editing-surface.md) | Editing Surface | `draft` |
| [TODO-02](./TODO-02-find-replace-goto.md) | Find, Replace and Go To | `draft` |
| [TODO-03](./TODO-03-spellcheck-autocorrect.md) | Spellcheck and Autocorrect | `draft` |
| [TODO-04](./TODO-04-lightweight-formatting.md) | Lightweight Formatting | `draft` |

## In scope

- Text buffer, caret, selection, clipboard, undo/redo
- Zoom, word wrap, line-ending display behavior
- Find/replace bar and go-to-line
- Spellcheck and autocorrect with per-file-type toggles
- Lightweight formatting: toolbar, Markdown, tables

## Out of scope

- The window, tabs, and file IO that host the surface (01-notepad-core)
- AI inline completions or edits (05-ai-surface consumes this surface; it does not live here)

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
