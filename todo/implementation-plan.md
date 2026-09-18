# Intelligent Notepad -- Implementation Plan to 100%

The order to run every section in, from today to a signed release.

> **Progress:** **62 of 195 sections complete (32%).** Derived from the Implementation Order tables by `python3 scripts/todo-graph.py plan --sync` -- never edited by hand.
>
> **Plan/graph parity.** Every numbered TODO section, open or shipped, appears in exactly one phase table row. `plan --check` enforces missing, unknown, duplicate, and status parity. Read live totals from the generated Progress line above and `python3 scripts/todo-graph.py query stats`; never repeat a fixed denominator in prose.

Seeded 2026-09-14 by porting the JMR Online TODO system. Current state and dependency ordering are derived from the repository; dated operational evidence remains dated evidence and must be re-read before an external change.

**How to use this.** The front door for this file is the `process-plan` skill. It audits, then runs `process-phase` on the first phase that has a ready row, then the next ready phase after that closeout or park, until no ready phase remains. A phase whose leftover `[ ]` rows are blocked by another phase (or another unmet dep) is parked, not a stall, and is not called complete. One row is `process-todo-section` then `review-todo-section`. Do not invent a side loop. Within a phase, follow the rows in order; if a newly discovered edge points later, add or split the prerequisite under `groom-plan` rather than moving the existing consumer.

**Copy a row and paste it.** The skills resolve a reference from whatever shape it arrives in, so this is a complete instruction:

```
process todo section: | [ ] | `D00 T01 §1` | Repo layout and toolchain pin | 5 |
```

No translating domain `00` and TODO `01` into a filename. `todo-graph.py resolve` does it, and reports the unmet dependencies while it is there.

> [!IMPORTANT]
> **The boxes are derived. Never tick one by hand.**
>
> They are a projection of each TODO's Implementation Order table, and those flip in exactly one place: `review-todo-section`, after a `Verified:` stamp exists. A box ticked here would be a second record of the same fact.
>
> ```bash
> python3 scripts/todo-graph.py plan --sync     # rewrite the boxes, then re-align every table
> python3 scripts/todo-graph.py plan --check    # fail if they have gone stale (CI runs this)
> ```
>
> `--sync` also pads the table columns, so the file stays readable in source without anyone hand-padding it. `--check` deliberately ignores alignment: a build that goes red over whitespace is a build people stop reading.
>
> `--check` also fails when a row names a section the graph has never heard of, and when an open section appears in **no** phase: which is how this file would otherwise quietly stop being a plan for the whole project.

---

## The acceptance bar

The finished system is **Windows 11 Notepad, exact, with AI tools inside**: every Notepad surface present and behaving as Notepad behaves, proven by automated UI suites against golden captures; the ACP client speaking v1 (and v2 behind flags) to Codex and Claude Code through their adapters; every agent action gated by consent the user understands; every agent edit reviewed as a diff and applied through undo; and testing that is automatic and complete per the bar `D06 T01 §1` writes. This is the bar every phase closes against.

Each clause already has an owner, and this table is where to look when asking "is aim X actually covered":

| Aim                            | Owned by                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| Notepad parity, no deviation   | `D00 T02 §3` (captures) · Fidelity blocks on every UI section · `D06 T01 §3` (parity suites) |
| Every control functional       | Surface-completeness rule in `todo/README.md` · `D01 T02 §6` (menu audit)                    |
| Automatic and complete testing | `D00 T02` (backbone) · `D06 T01` (strategy) · `D06 T02` (conformance)                        |
| ACP client correctness         | `D03 T01` (transport/lifecycle) · `D03 T02` (client methods) · `D06 T02` (conformance)       |
| Consent-gated agent actions    | `D03 T02 §1` (deny-by-default) · `D05 T02 §1` (prompt surface) · `D03 T02 §5` (audit)        |
| Reviewed, undoable agent edits | `D05 T02 §3` (diff review) · `D05 T02 §4` (apply through undo)                               |
| Shippable releases             | `D07 T01` (packaging, install test, update, checklist)                                       |

---

## Where the project stands

The generated Progress line at the top is the phase-plan snapshot; `python3 scripts/todo-graph.py query stats` is the full graph/item snapshot. Those are the only current totals. **Corrected 2026-09-17:** was "Nothing is built yet: Phase 0 is the first ready work"; Phase 0 is nearly complete (only `D00 T01 §§12-13` hooks plus environment-gated queries and `D00 T02 §§8-9` focus-free conversion plus nightly-run governance open) and Phase 1 (Notepad parity) is in progress with the window, tabs, files, menus, and settings spine shipped.

Every open section is in scope and must appear in exactly one phase. A dependency may park a row; it does not remove it. `plan --check` is the proof.

The total can rise when an audit identifies real scope. Say so plainly, route it once, and sync the plan/progress projection; a lower percentage after adding required work is more truthful than a false completion claim.

---

## Prerequisites

**These are not sections. They are the things that must be true before certain sections can start, and most of them are owned by somebody who is not you.** Their lead time is the real risk in this plan: a section can be rescheduled in an afternoon, a machine or account cannot.

Chase them in this order. The first gates the whole build.

### 1. A Windows 11 host to run the app

The app is C# and WinUI 3 on .NET: neutral libraries build and test anywhere with the repo-local SDK, while the app itself runs on Windows only. **Corrected 2026-09-17:** the SDK pin (`D00 T01 §1`) shipped, so the wait is over; the standing fact is the OS boundary. Scripts and plan checks run anywhere; app launch, UI suites, captures, and packaging need the Windows 11 host (Venom-PC), with the UI suites driving the real binary on its interactive session.

### 2. Linux and Windows CI runners

`D00 T01 §3` owns them. **Corrected 2026-09-17:** was "Until CI runs the build and tests, gates are prose"; since 2026-09-17 CI gates the build plus launch smoke plus the TODO graph checks only, and the UI suites run locally on the dev box (background-safe default run per section, full fenced run on its own cadence). No implementation section is blocked on CI existing, but no section's build evidence is trustworthy without it, and no section's UI evidence is trustworthy without the local runs.

### 3. Codex and Claude Code adapters for compatibility runs

`D04 T01 §5` and `D06 T02 §4` need real `codex-acp` and `claude-agent-acp` binaries on a schedule. Handshake and session-shape suites need no API keys; anything needing keys is marked and skipped honestly until keys exist.

---

### Phase 0 -- Workspace spine: toolchain, CI, and the test backbone

|  ✔  | Section       | Deliverable                                | Items |
| :-: | ------------- | ------------------------------------------ | :---: |
| [x] | `D00 T01 §1`  | Repo layout and toolchain pin              |   5   |
| [x] | `D00 T01 §2`  | Solution scaffold with one-command build   |   5   |
| [x] | `D00 T01 §3`  | CI on Linux and Windows runners            |   5   |
| [x] | `D00 T01 §4`  | Warning and analysis gates                 |   5   |
| [x] | `D00 T01 §5`  | Test wiring and first smoke test           |   5   |
| [x] | `D00 T01 §6`  | Developer bootstrap doc                    |   4   |
| [x] | `D00 T01 §7`  | TODO graph checks in CI                    |   5   |
| [x] | `D00 T01 §9`  | Opus panel enforcement in the validator    |   5   |
| [x] | `D00 T01 §10` | Opus panel rule hardening follow-ups       |   4   |
| [x] | `D00 T01 §11` | Quote-end lookahead removal                |   4   |
| [x] | `D00 T01 §12` | Repo-managed git hooks gating TODO edits   |   3   |
| [x] | `D00 T01 §13` | Environment-gated ready queries            |   5   |
| [x] | `D00 T01 §14` | Plan reviews with a second-family reviewer |   6   |
| [x] | `D00 T01 §15` | First plan-review residuals                |  11   |
| [x] | `D00 T01 §16` | Second plan-review residuals               |  16   |
| [x] | `D00 T01 §17` | Third plan-review residuals                |  21   |
| [x] | `D00 T01 §18` | Checker count residual                     |   3   |
| [x] | `D00 T01 §19` | Fourth plan-review residuals               |  23   |
| [x] | `D00 T01 §20` | Run-identity reconciliation                |   6   |
| [x] | `D00 T01 §21` | Accountability records and surfacing       |   6   |
| [x] | `D00 T01 §22` | Clearance binding                          |   4   |
| [x] | `D00 T01 §23` | Ledger, provenance, and output hardening   |   7   |
| [ ] | `D00 T01 §24` | Lineage residuals and run inspection       |   6   |
| [ ] | `D00 T01 §25` | Rule-24 comment touch-up                   |   3   |
| [ ] | `D00 T01 §26` | Grandfathered migration execution          |   8   |
| [ ] | `D00 T01 §27` | Acceptance integrity                       |   7   |
| [ ] | `D00 T01 §28` | Partial records and governance docs        |   7   |
| [ ] | `D00 T01 §29` | Unattended checks and risk visibility      |   3   |
| [ ] | `D00 T01 §30` | Clearance fixture residuals                |   4   |
| [ ] | `D00 T01 §31` | Clearance causality and precision          |   7   |
| [ ] | `D00 T01 §32` | Clearance governance and diagnostics       |   6   |
| [ ] | `D00 T01 §33` | Provenance residuals                       |   8   |
| [ ] | `D00 T01 §34` | Amendment and runner residuals             |   6   |
| [x] | `D00 T02 §1`  | Unit test project and framework            |   5   |
| [x] | `D00 T02 §2`  | UI automation driver spike                 |   5   |
| [x] | `D00 T02 §3`  | Golden capture store and refresh           |   5   |
| [x] | `D00 T02 §4`  | ACP loopback fixture                       |   5   |
| [x] | `D00 T02 §5`  | Soak and quarantine procedure              |   5   |
| [x] | `D00 T02 §6`  | Golden comparison deterministic on CI      |   7   |
| [x] | `D00 T02 §7`  | CI evidence capture pipeline               |   4   |
| [ ] | `D00 T02 §8`  | Focus-free UI suite conversion             |   6   |
| [ ] | `D00 T02 §9`  | Nightly full-suite regression run          |   5   |

> **Moved:** `D00 T01 §8` -- 2026-09-14 to docs/testing.md (operator instruction: Conclave-PC VM testing retired; input capability proven by the local host suite instead, UI 18/18 with zero skips).

### Phase 1 -- Notepad parity: window, tabs, files, menus, editor

|  ✔  | Section       | Deliverable                                                         | Items |
| :-: | ------------- | ------------------------------------------------------------------- | :---: |
| [x] | `D01 T01 §1`  | Main window shell with menu bar host                                |   5   |
| [x] | `D01 T01 §2`  | Tab model with dirty tracking                                       |   5   |
| [x] | `D01 T01 §3`  | Tab bar UI: open, switch, reorder, close                            |   5   |
| [x] | `D01 T01 §4`  | File open with encoding detection                                   |  10   |
| [x] | `D01 T01 §5`  | File save and Save As                                               |   5   |
| [x] | `D01 T01 §6`  | Recent files and session restore                                    |   6   |
| [x] | `D01 T01 §7`  | Dirty prompts and crash recovery                                    |   6   |
| [x] | `D01 T01 §8`  | File association and command-line open                              |   5   |
| [x] | `D01 T02 §1`  | Menu bar with all items and enablement                              |   5   |
| [x] | `D01 T02 §2`  | Settings store with one writer                                      |   5   |
| [x] | `D01 T02 §3`  | Settings page                                                       |   7   |
| [x] | `D01 T02 §4`  | Status bar                                                          |   6   |
| [x] | `D01 T02 §13` | ScratchPad rename completion                                        |   6   |
| [x] | `D01 T02 §14` | Title-bar icon beside the tabs                                      |   5   |
| [ ] | `D01 T02 §15` | Chrome color finetune against stock                                 |   5   |
| [ ] | `D01 T02 §5`  | Print path                                                          |   4   |
| [ ] | `D01 T02 §6`  | Menu and shortcut completeness audit                                |   4   |
| [ ] | `D01 T02 §7`  | Reading level in the status bar                                     |   4   |
| [ ] | `D01 T02 §8`  | Command palette                                                     |   6   |
| [ ] | `D01 T02 §9`  | Live counts in the status bar                                       |   5   |
| [ ] | `D01 T02 §10` | Custom accent themes                                                |   5   |
| [ ] | `D01 T02 §11` | Session word goal                                                   |   4   |
| [ ] | `D01 T02 §12` | Recent Files display toggle                                         |   4   |
| [ ] | `D01 T02 §16` | Quarantine the MenuBarTests flakes                                  |   5   |
| [ ] | `D02 T01 §1`  | Hosting contract with the shell                                     |   5   |
| [ ] | `D02 T01 §2`  | Text buffer and caret model                                         |   5   |
| [ ] | `D02 T01 §3`  | Rendering, selection, clipboard                                     |   5   |
| [ ] | `D02 T01 §4`  | Undo and redo                                                       |   5   |
| [ ] | `D02 T01 §5`  | Zoom and word wrap                                                  |   4   |
| [ ] | `D02 T01 §6`  | Context menu and mouse behaviors                                    |   4   |
| [ ] | `D02 T01 §7`  | Large-file behavior and budget                                      |   5   |
| [ ] | `D02 T01 §8`  | Selection utilities: case, sort, dedupe                             |   6   |
| [ ] | `D02 T01 §9`  | Synonym picker                                                      |   5   |
| [ ] | `D02 T01 §10` | Readability heatmap                                                 |   4   |
| [ ] | `D02 T01 §11` | Text utilities: format, encode, normalize, slugify, inspect, tables |   9   |
| [ ] | `D02 T01 §12` | Bookmarked lines                                                    |   5   |
| [ ] | `D02 T01 §13` | Column selection                                                    |   5   |
| [ ] | `D02 T01 §14` | Smart paste                                                         |   5   |
| [ ] | `D02 T01 §15` | Clickable URLs                                                      |   5   |
| [ ] | `D02 T01 §16` | Split view                                                          |   6   |
| [ ] | `D02 T01 §17` | Distraction-free focus mode                                         |   4   |
| [ ] | `D02 T01 §18` | Copy as Markdown, HTML, plain text                                  |   4   |
| [ ] | `D02 T01 §19` | Side-by-side tab diff                                               |   6   |
| [ ] | `D02 T02 §1`  | Search engine over the buffer                                       |   5   |
| [ ] | `D02 T02 §2`  | Find bar UI                                                         |   4   |
| [ ] | `D02 T02 §3`  | Replace mode                                                        |   4   |
| [ ] | `D02 T02 §4`  | Go-to-line dialog                                                   |   4   |
| [ ] | `D02 T02 §5`  | Options persistence and edge cases                                  |   4   |
| [ ] | `D02 T02 §6`  | Find across all open tabs                                           |   5   |
| [x] | `D01 T01 §9`  | Multi-window with open-in mode                                      |   5   |
| [x] | `D01 T01 §11` | App icon wiring                                                     |   4   |
| [x] | `D01 T01 §13` | Pinned tabs                                                         |   4   |
| [x] | `D01 T01 §14` | Text statistics panel                                               |   5   |
| [x] | `D01 T01 §16` | File snapshots                                                      |   5   |
| [x] | `D01 T01 §17` | New-file templates                                                  |   4   |
| [x] | `D01 T01 §18` | Copy and export as Markdown, HTML, plain text                       |   4   |
| [x] | `D01 T01 §19` | Encrypted notes                                                     |   6   |
| [x] | `D01 T01 §20` | Backup on save                                                      |   4   |
| [x] | `D01 T01 §21` | Reload prompt on external change                                    |   5   |
| [x] | `D01 T01 §22` | First-line titles for untitled tabs                                 |   3   |
| [x] | `D01 T01 §24` | Share target                                                        |   3   |
| [x] | `D01 T01 §25` | Jump list tasks                                                     |   5   |
| [x] | `D01 T01 §26` | Protocol handler                                                    |   4   |
| [x] | `D01 T01 §27` | Tab-strip chrome parity repair                                      |   7   |
| [x] | `D01 T01 §28` | UIA tab accessibility names                                         |   3   |
| [x] | `D01 T01 §29` | Open with explicit encoding                                         |   4   |
| [x] | `D01 T01 §30` | Locked-tab residue hardening                                        |   4   |
| [x] | `D01 T01 §32` | Quarantine the AppIcon and Launch CI flakes                         |   4   |
| [ ] | `D02 T03 §1`  | Spellcheck engine over the buffer                                   |   5   |
| [ ] | `D02 T03 §2`  | Squiggles and suggestions UI                                        |   4   |
| [ ] | `D02 T03 §3`  | Autocorrect                                                         |   4   |
| [ ] | `D02 T03 §4`  | Global and per-file-type toggles                                    |   4   |
| [ ] | `D02 T04 §1`  | Format model over the buffer                                        |   4   |
| [ ] | `D02 T04 §2`  | Toolbar: inline styles and lists                                    |   4   |
| [ ] | `D02 T04 §3`  | Markdown syntax and source fidelity                                 |   5   |
| [ ] | `D02 T04 §4`  | Tables by toolbar and syntax                                        |   4   |
| [ ] | `D02 T04 §5`  | Formatting toggle and plain-text safety                             |   4   |
| [ ] | `D02 T05 §1`  | Grammar engine over the buffer                                      |   5   |
| [ ] | `D02 T05 §2`  | Grammar underlines and cards                                        |   4   |
| [ ] | `D02 T05 §3`  | Grammar toggle and scope                                            |   4   |
| [ ] | `D02 T05 §4`  | Style lints: passive voice and weasel words                         |   5   |

> **Moved:** `D01 T01 §12` -- 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §16; phase-1 run 2 cycle repair: split needs live editor views, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).
> **Moved:** `D01 T01 §15` -- 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §17; phase-1 run 2 cycle repair: paragraph emphasis needs the rendered surface, which cannot exist behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).
> **Moved:** `D01 T01 §23` -- 2026-09-14 to todo/02-editor/TODO-01-editing-surface.md (D02 T01 §19; phase-1 run 2 cycle repair: diffing open tabs needs buffer content plus the moved split, neither behind the T01-whole gate; in-tree move, the D02 row carries the work and this row is skipped so it counts once).

> **Moved:** `D01 T01 §10` -- 2026-09-14 to docs/testing.md (operator instruction: Conclave-PC VM testing retired; the border defect was VM-session-only and the host renders stock parity, proven by FreshCaptureMatchesGolden green plus local pixel inspection).

### Phase 2 -- Protocol and agents: ACP client, launch, sessions

|  ✔  | Section      | Deliverable                                  | Items |
| :-: | ------------ | -------------------------------------------- | :---: |
| [ ] | `D03 T01 §1` | JSON-RPC message layer                       |   5   |
| [ ] | `D03 T01 §2` | Stdio subprocess transport                   |   5   |
| [ ] | `D03 T01 §3` | Initialize and capability negotiation        |   5   |
| [ ] | `D03 T01 §4` | Session create and load                      |   4   |
| [ ] | `D03 T01 §5` | Prompt turns with streaming updates          |   5   |
| [ ] | `D03 T01 §6` | Cancellation and timeouts                    |   4   |
| [ ] | `D03 T01 §7` | Fault survival: crashes and malformed output |   4   |
| [ ] | `D03 T02 §1` | Permission request handling                  |   5   |
| [ ] | `D03 T02 §2` | File-system methods with scoped roots        |   5   |
| [ ] | `D03 T02 §3` | Terminal execution                           |   5   |
| [ ] | `D03 T02 §4` | Grant scope and revocation                   |   4   |
| [ ] | `D03 T02 §5` | Grant audit log                              |   4   |
| [ ] | `D03 T03 §1` | Per-connection version selection             |   4   |
| [ ] | `D03 T03 §2` | v2 lifecycle behind flags                    |   5   |
| [ ] | `D03 T03 §3` | v1 regression lock                           |   4   |
| [ ] | `D04 T01 §1` | Agent detection with versions                |   5   |
| [ ] | `D04 T01 §2` | Spawn over the stdio transport               |   4   |
| [ ] | `D04 T01 §3` | Launch health checks                         |   4   |
| [ ] | `D04 T01 §4` | Missing-agent guidance                       |   4   |
| [ ] | `D04 T01 §5` | Adapter compatibility record                 |   4   |
| [ ] | `D04 T02 §1` | Authenticate and logout                      |   5   |
| [ ] | `D04 T02 §2` | Session list and create                      |   4   |
| [ ] | `D04 T02 §3` | Session resume and delete                    |   4   |
| [ ] | `D04 T02 §4` | Session close and cleanup                    |   4   |
| [ ] | `D04 T02 §5` | Session log                                  |   4   |
| [ ] | `D04 T02 §6` | Per-file sidecar instructions                |   4   |

### Phase 3 -- AI surface and quality: panel, consent, conformance

|  ✔  | Section      | Deliverable                                     | Items |
| :-: | ------------ | ----------------------------------------------- | :---: |
| [ ] | `D05 T01 §1` | Panel shell and transcript contract             |   4   |
| [ ] | `D05 T01 §2` | Streaming transcript rendering                  |   5   |
| [ ] | `D05 T01 §3` | Input, send, and stop                           |   4   |
| [ ] | `D05 T01 §4` | Turn states and cancellation UX                 |   4   |
| [ ] | `D05 T01 §5` | Agent picker and history                        |   4   |
| [ ] | `D05 T01 §6` | Panel and editor coexistence                    |   4   |
| [ ] | `D05 T01 §7` | Chat export to Markdown                         |   4   |
| [ ] | `D05 T02 §1` | Permission prompt surface                       |   5   |
| [ ] | `D05 T02 §2` | Tool-call and plan display                      |   4   |
| [ ] | `D05 T02 §3` | Diff review                                     |   4   |
| [ ] | `D05 T02 §4` | Apply to editor through undo                    |   5   |
| [ ] | `D05 T02 §5` | Elicitation forms                               |   4   |
| [ ] | `D05 T02 §6` | Selection actions: explain, rewrite, summarize  |   6   |
| [ ] | `D05 T02 §7` | Document actions: translate, extract, summarize |   7   |
| [ ] | `D05 T02 §8` | Continue writing with ghost drafts              |   6   |
| [ ] | `D05 T02 §9` | Agent title suggestions for untitled tabs       |   4   |
| [ ] | `D06 T01 §1` | Strategy doc with layers and bars               |   4   |
| [ ] | `D06 T01 §2` | Coverage floors enforced in CI                  |   5   |
| [ ] | `D06 T01 §3` | Notepad parity UI suites                        |   5   |
| [ ] | `D06 T01 §4` | AI surface UI suites                            |   4   |
| [ ] | `D06 T01 §5` | Perf budgets enforced in CI                     |   4   |
| [ ] | `D06 T01 §6` | Flake policy and quarantine operation           |   5   |
| [ ] | `D06 T02 §1` | Scripted agent library                          |   4   |
| [ ] | `D06 T02 §2` | Schema pin and drift detection                  |   4   |
| [ ] | `D06 T02 §3` | Version matrix (v1 and v2)                      |   4   |
| [ ] | `D06 T02 §4` | Adapter compatibility schedule                  |   5   |
| [ ] | `D05 T03 §1` | Agent status bar                                |   4   |
| [ ] | `D05 T03 §2` | Per-tab pane with document context              |   5   |
| [ ] | `D05 T03 §3` | Slash commands                                  |   5   |
| [ ] | `D05 T03 §4` | Agent management panel                          |   4   |
| [ ] | `D05 T03 §5` | Token usage display                             |   4   |
| [ ] | `D08 T01 §1` | Kokoro TTS embedded                             |   5   |
| [ ] | `D08 T01 §2` | Audio transcode and provisioning                |   4   |
| [ ] | `D08 T01 §3` | Whisper STT embedded                            |   5   |
| [ ] | `D08 T01 §4` | Provider interface with OpenRouter              |   5   |
| [ ] | `D08 T02 §1` | Read-aloud UI with MP3                          |   5   |
| [ ] | `D08 T02 §2` | Dictate and transcribe UI                       |   5   |
| [ ] | `D08 T02 §3` | Provider settings and consent                   |   5   |
| [ ] | `D08 T02 §4` | Voice menus and shortcuts                       |   4   |

### Phase 4 -- Release: packaging, install, update

|  ✔  | Section      | Deliverable                   | Items |
| :-: | ------------ | ----------------------------- | :---: |
| [ ] | `D07 T01 §1` | MSIX package build            |   4   |
| [ ] | `D07 T01 §2` | Clean-machine install test    |   4   |
| [ ] | `D07 T01 §3` | Update channel with rollback  |   4   |
| [ ] | `D07 T01 §4` | Release checklist             |   4   |
| [ ] | `D07 T01 §5` | First signed release          |   4   |
| [ ] | `D07 T01 §6` | Store and WinGet distribution |   4   |
| [ ] | `D07 T01 §7` | Share target registration     |   4   |
