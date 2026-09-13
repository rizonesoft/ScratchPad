# Intelligent Notepad -- TODO Index

The live execution plan for the build. Format spec: [README.md](./README.md).

## How to use this tree

- **This file** carries domain order and the active TODOs. Keep it at that altitude: no checklists.
- **Each domain's `INDEX.md`** owns its own backlog and is the place to look for scope within a domain.
- Give every topic **one canonical home**. Cross-link with XREFs instead of duplicating scope.
- Numbering is local to a domain (`TODO-01`, `TODO-02`…) and never reused.
- When work graduates to documentation, move it to the domain's Completed section rather than leaving a stale checklist here.

## Domain order

Domains are numbered in **allocation order**. `DNN TNN §N` cross-references encode the domain number, so a remap rewrites every reference in the same commit.

**Execution order lives in the dependency graph**, not in this column. Ask the graph: `python3 scripts/todo-graph.py query ready`. The **Phase** column below is the coarse sequencing.

| No. | Domain | Phase | Purpose |
| :-: | ------ | :---: | ------- |
| 00 | [Workspace](./00-workspace/INDEX.md) | 0 | Repo, Windows toolchain, CI, this TODO system, test backbone. |
| 01 | [Notepad Core](./01-notepad-core/INDEX.md) | 1 | WinUI 3 app spine: window, tabs, file IO, menus, settings, status bar. Win11 Notepad parity. |
| 02 | [Editor](./02-editor/INDEX.md) | 1 | Editing surface: text engine, caret, find/replace, go-to, zoom, wrap. |
| 03 | [ACP Client](./03-acp-client/INDEX.md) | 2 | Agent Client Protocol: JSON-RPC stdio transport, session lifecycle, client methods, v2 readiness. |
| 04 | [Agents](./04-agents/INDEX.md) | 2 | Agent discovery and launch (Codex via codex-acp, Claude via claude-agent-acp), sessions, auth. |
| 05 | [AI Surface](./05-ai-surface/INDEX.md) | 3 | Chat panel, permission prompts, diff review and apply. New build, no Notepad counterpart. |
| 06 | [Quality](./06-quality/INDEX.md) | 3 | Automated test strategy, UI automation, ACP conformance harness. Testing is automatic and complete. |
| 07 | [Release](./07-release/INDEX.md) | 4 | MSIX packaging, install/update, release checklist. |

The Phase column is the original coarse domain grouping, not an executable schedule. Current dependency-safe sequencing and live counts come only from [`implementation-plan.md`](./implementation-plan.md) plus `python3 scripts/todo-graph.py query stats`. Do not infer readiness from a domain number or repeat fixed totals here.

## Coverage: every surface of Windows 11 Notepad, and who owns it

| Notepad surface | Domain | State |
| --------------- | ------ | ----- |
| Main window, tab bar, new/close/reorder tabs | 01-notepad-core | TODO written |
| File open/save/Save As, encoding and line-ending handling | 01-notepad-core | TODO written |
| Menu bar (File, Edit, View) with all items and shortcuts | 01-notepad-core | TODO written |
| Settings page (appearance, font, word wrap, etc.) | 01-notepad-core | TODO written |
| Status bar (line/column, zoom, encoding, line endings) | 01-notepad-core | TODO written |
| Editing surface, caret, selection, undo/redo | 02-editor | TODO written |
| Find/replace bar, find next/previous, go to line | 02-editor | TODO written |
| Zoom, word wrap toggle | 02-editor | TODO written |
| Spellcheck, autocorrect, per-file-type toggles | 02-editor | TODO written (D02 T03, groom 2026-09-14) |
| Formatting toolbar, Markdown, tables | 02-editor | TODO written (D02 T04, groom 2026-09-14) |
| Multi-window, open-in mode, startup preference | 01-notepad-core | TODO written (D01 T01 §9 + §6, groom 2026-09-14) |
| Theme and font settings | 01-notepad-core | TODO written (D01 T02 §3, groom 2026-09-14) |
| Rewrite/Write/Summarize entry points | 05-ai-surface | Answered by selection actions on the user's own agent, no subscription (D05 T02 §6, groom 2026-09-14) |
| Print | 01-notepad-core | TODO written (deferred slice) |

A coverage claim rests on the source it was derived from. This table was derived from the Windows 11 Notepad UI as observed on a stock install; `D00 T02 §3` owns the captured baseline that makes each row checkable, and any surface found later gets a row and an owner here first.

## Active TODOs

- [00 Workspace] [TODO-01 Repo and Toolchain](./00-workspace/TODO-01-repo-and-toolchain.md) -- layout, pinned Windows SDK and compiler, CI on a Windows runner, warning and analysis gates, this TODO system's own CI checks.
- [00 Workspace] [TODO-02 Test Backbone](./00-workspace/TODO-02-test-backbone.md) -- unit-test project, UI automation driver, golden captures, ACP loopback fixture, soak procedure.
- [01 Notepad Core] [TODO-01 WinUI App Spine](./01-notepad-core/TODO-01-winui-app-spine.md) -- window, tab model, file IO with encoding detection, open/save round-trips.
- [01 Notepad Core] [TODO-02 Menus, Settings and Status](./01-notepad-core/TODO-02-menus-settings-status.md) -- full menu bar, settings page, status bar, print slice.
- [02 Editor] [TODO-01 Editing Surface](./02-editor/TODO-01-editing-surface.md) -- text engine, caret and selection, undo/redo, zoom, wrap, line endings.
- [02 Editor] [TODO-02 Find, Replace and Go To](./02-editor/TODO-02-find-replace-goto.md) -- find/replace bar and go-to-line with Notepad behavior.
- [02 Editor] [TODO-03 Spellcheck and Autocorrect](./02-editor/TODO-03-spellcheck-autocorrect.md) -- squiggles, suggestions, autocorrect, per-file-type toggles.
- [02 Editor] [TODO-04 Lightweight Formatting](./02-editor/TODO-04-lightweight-formatting.md) -- formatting toolbar, Markdown, tables.
- [03 ACP Client] [TODO-01 Transport and Lifecycle](./03-acp-client/TODO-01-acp-transport-lifecycle.md) -- JSON-RPC over stdio, initialize, session/new, prompt turns, cancellation.
- [03 ACP Client] [TODO-02 Client Methods](./03-acp-client/TODO-02-acp-client-methods.md) -- session/request_permission, fs methods, terminals surface.
- [03 ACP Client] [TODO-03 v2 Readiness](./03-acp-client/TODO-03-acp-v2-readiness.md) -- version negotiation, v2 behind flags, migration path.
- [04 Agents] [TODO-01 Agent Discovery and Launch](./04-agents/TODO-01-agent-discovery-launch.md) -- installed-agent detection, adapter spawning (codex-acp, claude-agent-acp), health checks.
- [04 Agents] [TODO-02 Agent Sessions and Auth](./04-agents/TODO-02-agent-sessions-auth.md) -- session create/load/list, authenticate/logout, multi-session handling.
- [05 AI Surface] [TODO-01 Chat Panel](./05-ai-surface/TODO-01-chat-panel.md) -- the new AI panel: transcript, streaming updates, input, history.
- [05 AI Surface] [TODO-02 Permission and Apply UX](./05-ai-surface/TODO-02-permission-apply-ux.md) -- permission prompts, tool-call display, diff review and apply-to-editor.
- [05 AI Surface] [TODO-03 Agent Chrome](./05-ai-surface/TODO-03-agent-chrome.md) -- status bar, per-tab pane with document context, slash commands, management panel, token usage. Editor-native; the terminal is prior art only.
- [06 Quality] [TODO-01 Automated Test Strategy](./06-quality/TODO-01-automated-test-strategy.md) -- what automatic and complete means here: layers, coverage bar, UI automation suites, flake policy.
- [06 Quality] [TODO-02 ACP Conformance Harness](./06-quality/TODO-02-acp-conformance-harness.md) -- scripted fake agents, schema validation, session fixtures, adapter compatibility matrix.
- [07 Release] [TODO-01 Packaging and Update](./07-release/TODO-01-packaging-and-update.md) -- MSIX packaging, clean-machine install test, update channel, release checklist.

## Queries

```bash
python3 scripts/todo-graph.py query ready     # what can be worked right now
python3 scripts/todo-graph.py query blocked   # what is waiting, and on what
python3 scripts/todo-graph.py query stats     # tree health
```
