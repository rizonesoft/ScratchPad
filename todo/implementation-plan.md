# Intelligent Notepad -- Implementation Plan to 100%

The order to run every section in, from today to a signed release.

> **Progress:** **120 of 309 sections complete (39%).** Derived from the Implementation Order tables by `python3 scripts/todo-graph.py plan --sync` -- never edited by hand.
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

The app is C# and WinUI 3 on .NET: neutral libraries build and test anywhere with the repo-local SDK, while the app itself runs on Windows only. **Corrected 2026-09-17:** the SDK pin (`D00 T01 §1`) shipped, so the wait is over; the standing fact is the OS boundary. Scripts and plan checks run anywhere; app launch, UI suites, captures, and packaging need the Windows 11 host (Venom-PC), with the UI suites driving the real binary on its interactive session. **Corrected 2026-09-20:** CI and dev are Windows-only (operator decision 2026-09-19); the neutral filter still builds anywhere but nothing proves it outside Windows.

### 2. Windows CI runners

`D00 T01 §3` owns them. **Corrected 2026-09-17:** was "Until CI runs the build and tests, gates are prose"; since 2026-09-17 CI gates the build plus launch smoke plus the TODO graph checks only, and the UI suites run locally on the dev box (background-safe default run per section, full fenced run on its own cadence). No implementation section is blocked on CI existing, but no section's build evidence is trustworthy without it, and no section's UI evidence is trustworthy without the local runs. **Corrected 2026-09-20:** was "Linux and Windows CI runners"; Linux legs retired (operator decision 2026-09-19).

### 3. Codex and Claude Code adapters for compatibility runs

`D04 T01 §5` and `D06 T02 §4` need real `codex-acp` and `claude-agent-acp` binaries on a schedule. Handshake and session-shape suites need no API keys; anything needing keys is marked and skipped honestly until keys exist.

---

### Phase 0 -- Workspace spine: toolchain, CI, and the test backbone

|  ✔  | Section       | Deliverable                                               | Items |
| :-: | ------------- | --------------------------------------------------------- | :---: |
| [x] | `D00 T01 §1`  | Repo layout and toolchain pin                             |   7   |
| [x] | `D00 T01 §2`  | Solution scaffold with one-command build                  |   5   |
| [x] | `D00 T01 §3`  | CI on Linux and Windows runners                           |   5   |
| [x] | `D00 T01 §4`  | Warning and analysis gates                                |   5   |
| [x] | `D00 T01 §5`  | Test wiring and first smoke test                          |   5   |
| [x] | `D00 T01 §6`  | Developer bootstrap doc                                   |   5   |
| [x] | `D00 T01 §7`  | TODO graph checks in CI                                   |   5   |
| [x] | `D00 T01 §9`  | Opus panel enforcement in the validator                   |   5   |
| [x] | `D00 T01 §10` | Opus panel rule hardening follow-ups                      |   4   |
| [x] | `D00 T01 §11` | Quote-end lookahead removal                               |   4   |
| [x] | `D00 T01 §12` | Repo-managed git hooks gating TODO edits                  |   3   |
| [x] | `D00 T01 §13` | Environment-gated ready queries                           |   6   |
| [x] | `D00 T01 §14` | Plan reviews with a second-family reviewer                |   6   |
| [x] | `D00 T01 §15` | First plan-review residuals                               |  11   |
| [x] | `D00 T01 §16` | Second plan-review residuals                              |  16   |
| [x] | `D00 T01 §17` | Third plan-review residuals                               |  21   |
| [x] | `D00 T01 §18` | Checker count residual                                    |   3   |
| [x] | `D00 T01 §19` | Fourth plan-review residuals                              |  23   |
| [x] | `D00 T01 §20` | Run-identity reconciliation                               |   6   |
| [x] | `D00 T01 §21` | Accountability records and surfacing                      |   6   |
| [x] | `D00 T01 §22` | Clearance binding                                         |   4   |
| [x] | `D00 T01 §23` | Ledger, provenance, and output hardening                  |   7   |
| [x] | `D00 T01 §24` | Lineage residuals and run inspection                      |   6   |
| [x] | `D00 T01 §25` | Rule-24 comment touch-up                                  |   3   |
| [x] | `D00 T01 §26` | Grandfathered migration execution                         |   8   |
| [x] | `D00 T01 §27` | Acceptance integrity                                      |   7   |
| [x] | `D00 T01 §28` | Partial records and governance docs                       |   7   |
| [x] | `D00 T01 §29` | Unattended checks and risk visibility                     |   9   |
| [x] | `D00 T01 §30` | Clearance fixture residuals                               |   4   |
| [x] | `D00 T01 §31` | Clearance causality and precision                         |   8   |
| [x] | `D00 T01 §32` | Clearance governance and diagnostics                      |   6   |
| [x] | `D00 T01 §33` | Provenance residuals                                      |   8   |
| [x] | `D00 T01 §34` | Amendment and runner residuals                            |  10   |
| [x] | `D00 T01 §35` | Mixed Sol/Opus panel with soft and hard caps              |  11   |
| [x] | `D00 T01 §36` | README mixed-panel touch-up                               |   2   |
| [x] | `D00 T01 §37` | Panel rule residuals                                      |   8   |
| [x] | `D00 T01 §38` | Architecture gate residuals                               |   7   |
| [x] | `D00 T01 §39` | Panel telemetry                                           |   6   |
| [x] | `D00 T01 §40` | Centralized build output in Bin                           |   6   |
| [x] | `D00 T01 §41` | Bin output residuals                                      |   9   |
| [x] | `D00 T02 §1`  | Unit test project and framework                           |   5   |
| [x] | `D00 T02 §2`  | UI automation driver spike                                |   5   |
| [x] | `D00 T02 §3`  | Golden capture store and refresh                          |   5   |
| [x] | `D00 T02 §4`  | ACP loopback fixture                                      |   5   |
| [x] | `D00 T02 §5`  | Soak and quarantine procedure                             |   5   |
| [x] | `D00 T02 §6`  | Golden comparison deterministic on CI                     |   9   |
| [x] | `D00 T02 §7`  | CI evidence capture pipeline                              |   4   |
| [x] | `D00 T02 §8`  | Focus-free UI suite conversion                            |  14   |
| [x] | `D00 T02 §9`  | Nightly full-suite regression run                         |   8   |
| [x] | `D00 T02 §10` | Completion-first night-debt system                        |  12   |
| [x] | `D00 T02 §11` | Central launch helper with off-screen birth               |   6   |
| [x] | `D00 T02 §12` | Accelerator binding coverage sweep                        |   4   |
| [x] | `D00 T02 §13` | Backgrounding leak on the default leg                     |  10   |
| [x] | `D00 T02 §14` | Run-level deadline for the governed run                   |   6   |
| [x] | `D00 T02 §15` | Nightly enforcement and count hardening                   |  27   |
| [ ] | `D00 T02 §16` | Verify timer-fired completion and green                   |  17   |
| [x] | `D00 T02 §17` | Nightly notify plus trend surface                         |  10   |
| [x] | `D00 T02 §18` | Central launch hardening and evidence                     |  10   |
| [x] | `D00 T02 §19` | Night-debt due dates and escalation                       |   3   |
| [x] | `D00 T02 §20` | Accelerator sweep sign-off polish                         |   3   |
| [x] | `D00 T02 §21` | Accelerator sweep follow-ups                              |  13   |
| [x] | `D00 T02 §22` | Nightly evidence hardening follow-ups                     |   8   |
| [x] | `D00 T02 §23` | Nightly acknowledgement hardening                         |   6   |
| [ ] | `D00 T02 §24` | Notify follow-ups                                         |  15   |
| [x] | `D00 T02 §25` | Trend and telemetry follow-ups                            |  11   |
| [x] | `D00 T02 §26` | Sibling sweep narrowing                                   |   3   |
| [x] | `D00 T02 §27` | Night-debt escalation lifecycle                           |   8   |
| [x] | `D00 T02 §28` | Binding guard and funnel hardening                        |  11   |
| [ ] | `D00 T02 §29` | Population fingerprint gate before the night              |   7   |
| [ ] | `D00 T02 §30` | Nightly evidence residuals                                |  11   |
| [ ] | `D00 T02 §31` | Acknowledgement residuals                                 |  15   |
| [ ] | `D00 T02 §32` | Trend and telemetry residuals                             |  16   |
| [ ] | `D00 T02 §33` | Notification residuals                                    |   5   |
| [ ] | `D00 T02 §34` | Sibling sweep residuals                                   |   7   |
| [ ] | `D00 T02 §35` | Night-debt lifecycle residuals                            |  13   |
| [ ] | `D00 T02 §36` | Binding guard residuals                                   |   9   |
| [ ] | `D00 T03 §1`  | App screenshots for README                                |   6   |
| [ ] | `D00 T03 §2`  | README rewrite plus repo-face files                       |  10   |
| [ ] | `D00 T03 §3`  | Setup-path CI plus reproducibility record                 |   6   |
| [ ] | `D00 T03 §4`  | Premium README presentation                               |   9   |
| [ ] | `D00 T03 §5`  | Agent showcase media                                      |   4   |
| [x] | `D00 T01 §42` | Requires operator vocabulary                              |   5   |
| [x] | `D00 T01 §43` | Findings count touch-up                                   |   5   |
| [x] | `D00 T01 §44` | Range-fallback lineage guards                             |   3   |
| [x] | `D00 T01 §45` | Run inspection residuals                                  |   3   |
| [x] | `D00 T01 §46` | Rule-description probe completeness                       |   3   |
| [x] | `D00 T01 §47` | Section-span scan helper                                  |   3   |
| [x] | `D00 T01 §48` | Migration completion assurance                            |   7   |
| [x] | `D00 T01 §49` | Multi-citer review evaluation                             |   3   |
| [x] | `D00 T01 §50` | Outage instance dating                                    |   3   |
| [x] | `D00 T01 §51` | Acceptance record follow-ups                              |   9   |
| [x] | `D00 T01 §52` | Partial-record and quorum follow-ups                      |   7   |
| [x] | `D00 T01 §53` | Unattended notification and register follow-ups           |  18   |
| [x] | `D00 T01 §54` | Clearance fixture follow-ups                              |   8   |
| [x] | `D00 T01 §55` | Clearance causality follow-ups                            |  30   |
| [ ] | `D00 T04 §1`  | Sol-note and disposition follow-ups                       |  30   |
| [ ] | `D00 T04 §2`  | Rule-24 probe follow-ups                                  |   6   |
| [ ] | `D00 T04 §3`  | Migration-assurance follow-ups                            |   5   |
| [ ] | `D00 T04 §4`  | Review-evaluation follow-ups                              |   4   |
| [ ] | `D00 T04 §5`  | Windows console and prompt follow-ups                     |   4   |
| [x] | `D00 T04 §6`  | Acceptance-record sign-off residuals                      |   6   |
| [ ] | `D00 T04 §7`  | Generation-map refusal parity                             |   3   |
| [ ] | `D00 T04 §8`  | Position-proof health results                             |   3   |
| [ ] | `D00 T04 §9`  | Acceptance semantic version binding                       |   3   |
| [ ] | `D00 T04 §10` | Section-52 sign-off residuals                             |   6   |
| [ ] | `D00 T04 §11` | Section-52 plan-review residuals                          |   4   |
| [ ] | `D00 T04 §12` | Section-54 sign-off residuals                             |  13   |
| [ ] | `D00 T04 §13` | Section-54 e2e and lane residuals                         |  10   |
| [x] | `D00 T04 §14` | Panel-label rename to Claude and GPT                      |   7   |
| [x] | `D00 T04 §15` | Panel rewire: sol bulk, opus governs                      |   7   |
| [ ] | `D00 T04 §16` | Section-15 plan-review residuals                          |   4   |
| [ ] | `D00 T04 §17` | Section-14 sign-off residuals                             |   4   |
| [ ] | `D00 T04 §18` | Section-14 plan-review residuals                          |   3   |
| [x] | `D00 T04 §19` | Opus 5.5 reviewer re-pin                                  |   6   |
| [ ] | `D00 T04 §20` | Section-19 plan-review residuals                          |   3   |
| [x] | `D00 T04 §21` | GPT-6 sol reviewer re-pin                                 |   6   |
| [ ] | `D00 T04 §22` | Section-21 review residuals                               |   4   |
| [x] | `D00 T04 §23` | Implementer-independent panel: GPT governs                |   9   |
| [ ] | `D00 T04 §24` | Section-23 sign-off residuals                             |   5   |
| [x] | `D00 T04 §25` | Simplified panel: sol primaries, Grok fallback            |   9   |
| [ ] | `D00 T04 §26` | Section-25 sign-off residuals                             |   6   |
| [ ] | `D00 T04 §27` | Self-test determinism on Windows                          |   4   |
| [ ] | `D00 T05 §1`  | Runner file-closeout wiring                               |   4   |
| [ ] | `D00 T05 §2`  | Run-guard proof                                           |   3   |
| [ ] | `D00 T06 §1`  | Prerequisite scope audit                                  |   5   |
| [ ] | `D00 T07 §1`  | Bin machinery follow-ups                                  |   9   |
| [ ] | `D00 T08 §1`  | Poster and delivery hardening                             |  12   |
| [ ] | `D00 T08 §2`  | Notification governance and premium views                 |  12   |
| [ ] | `D00 T09 §1`  | Hotkey-conflict preflight and environment-blocked outcome |  18   |
| [ ] | `D00 T09 §2`  | Control channel and nightly-ctl CLI                       |   8   |
| [ ] | `D00 T09 §3`  | Operator-presence yield                                   |   7   |
| [ ] | `D00 T09 §4`  | Toast action buttons                                      |   4   |
| [ ] | `D00 T09 §5`  | Tray status and control icon                              |   5   |
| [ ] | `D00 T09 §6`  | Nightly Claude skill                                      |   4   |
| [ ] | `D00 T09 §7`  | Adaptive run planning                                     |   6   |
| [ ] | `D00 T09 §8`  | Claude triage in the morning report                       |  10   |

> **Moved:** `D00 T01 §8` -- 2026-09-14 to docs/testing.md (operator instruction: Conclave-PC VM testing retired; input capability proven by the local host suite instead, UI 18/18 with zero skips).

### Phase 1 -- Notepad parity: window, tabs, files, menus, editor

|  ✔  | Section       | Deliverable                                                         | Items |
| :-: | ------------- | ------------------------------------------------------------------- | :---: |
| [x] | `D01 T01 §1`  | Main window shell with menu bar host                                |   7   |
| [x] | `D01 T01 §2`  | Tab model with dirty tracking                                       |   7   |
| [x] | `D01 T01 §3`  | Tab bar UI: open, switch, reorder, close                            |   7   |
| [x] | `D01 T01 §4`  | File open with encoding detection                                   |  10   |
| [x] | `D01 T01 §5`  | File save and Save As                                               |   8   |
| [x] | `D01 T01 §6`  | Recent files and session restore                                    |   8   |
| [x] | `D01 T01 §7`  | Dirty prompts and crash recovery                                    |   6   |
| [x] | `D01 T01 §8`  | File association and command-line open                              |   8   |
| [x] | `D01 T02 §1`  | Menu bar with all items and enablement                              |  11   |
| [x] | `D01 T02 §2`  | Settings store with one writer                                      |   6   |
| [x] | `D01 T02 §3`  | Settings page                                                       |   9   |
| [x] | `D01 T02 §4`  | Status bar                                                          |   9   |
| [x] | `D01 T02 §13` | ScratchPad rename completion                                        |   6   |
| [x] | `D01 T02 §14` | Title-bar icon beside the tabs                                      |   5   |
| [ ] | `D01 T02 §15` | Chrome color finetune against stock                                 |   5   |
| [ ] | `D01 T02 §5`  | Print path                                                          |   9   |
| [ ] | `D01 T02 §6`  | Menu and shortcut completeness audit                                |   4   |
| [ ] | `D01 T02 §7`  | Reading level in the status bar                                     |   5   |
| [ ] | `D01 T02 §8`  | Command palette                                                     |   7   |
| [ ] | `D01 T02 §9`  | Live counts in the status bar                                       |   6   |
| [ ] | `D01 T02 §10` | Custom accent themes                                                |   6   |
| [ ] | `D01 T02 §11` | Session word goal                                                   |   5   |
| [ ] | `D01 T02 §12` | Recent Files display toggle                                         |   4   |
| [ ] | `D01 T02 §16` | Quarantine the MenuBarTests flakes                                  |   7   |
| [ ] | `D01 T02 §17` | About panel identity rows                                           |   8   |
| [ ] | `D01 T02 §18` | Fix-or-remove MenuBarTests flakes                                   |   2   |
| [ ] | `D02 T01 §1`  | Hosting contract with the shell                                     |   6   |
| [ ] | `D02 T01 §2`  | Text buffer and caret model                                         |  10   |
| [ ] | `D02 T01 §3`  | Rendering, selection, clipboard                                     |  13   |
| [ ] | `D02 T01 §4`  | Undo and redo                                                       |   7   |
| [ ] | `D02 T01 §5`  | Zoom and word wrap                                                  |  13   |
| [ ] | `D02 T01 §6`  | Context menu and mouse behaviors                                    |   5   |
| [ ] | `D02 T01 §7`  | Large-file behavior and budget                                      |   5   |
| [ ] | `D02 T01 §8`  | Selection utilities: case, sort, dedupe                             |   6   |
| [ ] | `D02 T01 §9`  | Synonym picker                                                      |   5   |
| [ ] | `D02 T01 §10` | Readability heatmap                                                 |   4   |
| [ ] | `D02 T01 §11` | Text utilities: format, encode, normalize, slugify, inspect, tables |   9   |
| [ ] | `D02 T01 §12` | Bookmarked lines                                                    |   6   |
| [ ] | `D02 T01 §13` | Column selection                                                    |   5   |
| [ ] | `D02 T01 §14` | Smart paste                                                         |   6   |
| [ ] | `D02 T01 §15` | Clickable URLs                                                      |   6   |
| [ ] | `D02 T01 §16` | Split view                                                          |   6   |
| [ ] | `D02 T01 §17` | Distraction-free focus mode                                         |   4   |
| [ ] | `D02 T01 §18` | Copy as Markdown, HTML, plain text                                  |   4   |
| [ ] | `D02 T01 §19` | Side-by-side tab diff                                               |   6   |
| [ ] | `D02 T02 §1`  | Search engine over the buffer                                       |   6   |
| [ ] | `D02 T02 §2`  | Find bar UI                                                         |   9   |
| [ ] | `D02 T02 §3`  | Replace mode                                                        |   6   |
| [ ] | `D02 T02 §4`  | Go-to-line dialog                                                   |   6   |
| [ ] | `D02 T02 §5`  | Options persistence and edge cases                                  |   4   |
| [ ] | `D02 T02 §6`  | Find across all open tabs                                           |   5   |
| [x] | `D01 T01 §9`  | Multi-window with open-in mode                                      |   5   |
| [x] | `D01 T01 §11` | App icon wiring                                                     |   4   |
| [x] | `D01 T01 §13` | Pinned tabs                                                         |   4   |
| [x] | `D01 T01 §14` | Text statistics panel                                               |   5   |
| [x] | `D01 T01 §16` | File snapshots                                                      |   5   |
| [x] | `D01 T01 §17` | New-file templates                                                  |   4   |
| [x] | `D01 T01 §18` | Copy and export as Markdown, HTML, plain text                       |   3   |
| [x] | `D01 T01 §19` | Encrypted notes                                                     |   6   |
| [x] | `D01 T01 §20` | Backup on save                                                      |   4   |
| [x] | `D01 T01 §21` | Reload prompt on external change                                    |   5   |
| [x] | `D01 T01 §22` | First-line titles for untitled tabs                                 |   3   |
| [x] | `D01 T01 §24` | Share target                                                        |   3   |
| [x] | `D01 T01 §25` | Jump list tasks                                                     |   4   |
| [x] | `D01 T01 §26` | Protocol handler                                                    |   4   |
| [x] | `D01 T01 §27` | Tab-strip chrome parity repair                                      |   7   |
| [x] | `D01 T01 §28` | UIA tab accessibility names                                         |   3   |
| [x] | `D01 T01 §29` | Open with explicit encoding                                         |   5   |
| [x] | `D01 T01 §30` | Locked-tab residue hardening                                        |   4   |
| [x] | `D01 T01 §32` | Quarantine the AppIcon and Launch CI flakes                         |   4   |
| [ ] | `D01 T01 §33` | F1 context help                                                     |   4   |
| [ ] | `D01 T01 §34` | Pinned-tab close regressions                                        |   3   |
| [ ] | `D01 T01 §35` | Fix-or-remove the night-triage quarantines                          |  11   |
| [ ] | `D02 T03 §1`  | Spellcheck engine over the buffer                                   |   6   |
| [ ] | `D02 T03 §2`  | Squiggles and suggestions UI                                        |   6   |
| [ ] | `D02 T03 §3`  | Autocorrect                                                         |   4   |
| [ ] | `D02 T03 §4`  | Global and per-file-type toggles                                    |   6   |
| [ ] | `D02 T04 §1`  | Format model over the buffer                                        |   5   |
| [ ] | `D02 T04 §2`  | Toolbar: inline styles and lists                                    |  10   |
| [ ] | `D02 T04 §3`  | Markdown syntax and source fidelity                                 |   8   |
| [ ] | `D02 T04 §4`  | Tables by toolbar and syntax                                        |   4   |
| [ ] | `D02 T04 §5`  | Formatting toggle and plain-text safety                             |   5   |
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
| [ ] | `D03 T01 §3` | Initialize and capability negotiation        |   6   |
| [ ] | `D03 T01 §4` | Session create and load                      |   5   |
| [ ] | `D03 T01 §5` | Prompt turns with streaming updates          |   6   |
| [ ] | `D03 T01 §6` | Cancellation and timeouts                    |   5   |
| [ ] | `D03 T01 §8` | Session list, resume, close, delete          |   4   |
| [ ] | `D03 T01 §7` | Fault survival: crashes and malformed output |   5   |
| [ ] | `D03 T01 §9` | Modes and config options                     |   3   |
| [ ] | `D03 T02 §1` | Permission request handling                  |   5   |
| [ ] | `D03 T02 §2` | File-system methods with scoped roots        |   6   |
| [ ] | `D03 T02 §3` | Terminal execution                           |   5   |
| [ ] | `D03 T02 §4` | Grant scope and revocation                   |   4   |
| [ ] | `D03 T02 §5` | Grant audit log                              |   4   |
| [ ] | `D03 T02 §6` | Elicitation requests                         |   3   |
| [ ] | `D03 T03 §1` | Per-connection version selection             |   4   |
| [ ] | `D03 T03 §2` | v2 lifecycle behind flags                    |   5   |
| [ ] | `D03 T03 §3` | v1 regression lock                           |   4   |
| [ ] | `D04 T01 §1` | Agent detection with versions                |   5   |
| [ ] | `D04 T01 §2` | Spawn over the stdio transport               |   4   |
| [ ] | `D04 T01 §3` | Launch health checks                         |   4   |
| [ ] | `D04 T01 §4` | Missing-agent guidance                       |   4   |
| [ ] | `D04 T01 §5` | Adapter compatibility record                 |   4   |
| [ ] | `D04 T02 §1` | Authenticate and logout                      |   6   |
| [ ] | `D04 T02 §2` | Session list and create                      |   4   |
| [ ] | `D04 T02 §3` | Session resume and delete                    |   4   |
| [ ] | `D04 T02 §4` | Session close and cleanup                    |   4   |
| [ ] | `D04 T02 §5` | Session log                                  |   4   |
| [ ] | `D04 T02 §6` | Per-file sidecar instructions                |   4   |

### Phase 3 -- AI surface and quality: panel, consent, conformance

|  ✔  | Section       | Deliverable                                     | Items |
| :-: | ------------- | ----------------------------------------------- | :---: |
| [ ] | `D05 T01 §1`  | Panel shell and transcript contract             |   4   |
| [ ] | `D05 T01 §2`  | Streaming transcript rendering                  |   5   |
| [ ] | `D05 T01 §3`  | Input, send, and stop                           |   4   |
| [ ] | `D05 T01 §4`  | Turn states and cancellation UX                 |   4   |
| [ ] | `D05 T01 §5`  | Agent picker and history                        |   5   |
| [ ] | `D05 T01 §6`  | Panel and editor coexistence                    |   4   |
| [ ] | `D05 T01 §7`  | Chat export to Markdown                         |   4   |
| [ ] | `D05 T02 §1`  | Permission prompt surface                       |   5   |
| [ ] | `D05 T02 §2`  | Tool-call and plan display                      |   5   |
| [ ] | `D05 T02 §3`  | Diff review                                     |   5   |
| [ ] | `D05 T02 §4`  | Apply to editor through undo                    |   6   |
| [ ] | `D05 T02 §5`  | Elicitation forms                               |   4   |
| [ ] | `D05 T02 §6`  | Selection actions: explain, rewrite, summarize  |  14   |
| [ ] | `D05 T02 §7`  | Document actions: translate, extract, summarize |   7   |
| [ ] | `D05 T02 §8`  | Continue writing with ghost drafts              |   6   |
| [ ] | `D05 T02 §9`  | Agent title suggestions for untitled tabs       |   4   |
| [ ] | `D05 T02 §10` | Grants and audit viewer                         |   3   |
| [ ] | `D06 T01 §1`  | Strategy doc with layers and bars               |   5   |
| [ ] | `D06 T01 §2`  | Coverage floors enforced in CI                  |   5   |
| [ ] | `D06 T01 §3`  | Notepad parity UI suites                        |   5   |
| [ ] | `D06 T01 §4`  | AI surface UI suites                            |   4   |
| [ ] | `D06 T01 §5`  | Perf budgets enforced in CI                     |   4   |
| [ ] | `D06 T01 §6`  | Flake policy and quarantine operation           |   5   |
| [ ] | `D06 T02 §1`  | Scripted agent library                          |   6   |
| [ ] | `D06 T02 §2`  | Schema pin and drift detection                  |   4   |
| [ ] | `D06 T02 §3`  | Version matrix (v1 and v2)                      |   4   |
| [ ] | `D06 T02 §4`  | Adapter compatibility schedule                  |   5   |
| [ ] | `D05 T03 §1`  | Agent status bar                                |   5   |
| [ ] | `D05 T03 §2`  | Per-tab pane with document context              |   5   |
| [ ] | `D05 T03 §3`  | Slash commands                                  |   6   |
| [ ] | `D05 T03 §4`  | Agent management panel                          |   5   |
| [ ] | `D05 T03 §5`  | Token usage display                             |   4   |
| [ ] | `D05 T03 §6`  | AI settings group                               |   3   |
| [ ] | `D08 T01 §1`  | Kokoro TTS embedded                             |   6   |
| [ ] | `D08 T01 §2`  | Audio transcode and provisioning                |   4   |
| [ ] | `D08 T01 §3`  | Whisper STT embedded                            |   5   |
| [ ] | `D08 T01 §4`  | Provider interface with OpenRouter              |   6   |
| [ ] | `D08 T02 §1`  | Read-aloud UI with MP3                          |   5   |
| [ ] | `D08 T02 §2`  | Dictate and transcribe UI                       |   5   |
| [ ] | `D08 T02 §3`  | Provider settings and consent                   |   5   |
| [ ] | `D08 T02 §4`  | Voice menus and shortcuts                       |   4   |

### Phase 4 -- Release: packaging, install, update

|  ✔  | Section       | Deliverable                           | Items |
| :-: | ------------- | ------------------------------------- | :---: |
| [ ] | `D07 T01 §9`  | Dynamic version scheme                |   5   |
| [ ] | `D07 T01 §10` | Product identity registry             |   5   |
| [ ] | `D07 T01 §13` | User-guide backfill                   |   3   |
| [ ] | `D07 T01 §11` | Help content pipeline                 |   5   |
| [ ] | `D07 T01 §1`  | MSIX package build                    |   7   |
| [ ] | `D07 T01 §2`  | Clean-machine install test            |   5   |
| [ ] | `D07 T01 §3`  | Update channel with rollback          |   5   |
| [ ] | `D07 T01 §4`  | Release checklist                     |   4   |
| [ ] | `D07 T01 §5`  | First signed release                  |   4   |
| [ ] | `D07 T01 §12` | Guide web publishing and link switch  |   3   |
| [ ] | `D07 T01 §6`  | Store and WinGet distribution         |   4   |
| [ ] | `D07 T01 §7`  | Share target registration             |   4   |
| [ ] | `D07 T01 §8`  | Inno Setup installer and distribution |   7   |

### Phase 99 -- Manual: operator-only steps

No agent runner takes rows from this phase: every section carries a `**Manual:**` line and assumes zero GitHub knowledge. The operator works the steps from `todo/99-manual/`, commits ticked items plus proof screenshots through the GitHub web UI, and an agent session verifies the public proof afterward; review stamps the evidence range like any other. The steps live in the TODO file, never here: this table holds one row per section and nothing else.

|  ✔  | Section      | Deliverable                   | Items |
| :-: | ------------ | ----------------------------- | :---: |
| [ ] | `D99 T01 §1` | About, topics, social preview |   6   |
| [ ] | `D99 T01 §2` | Branch protection             |   5   |
| [ ] | `D99 T01 §3` | Cold-reader pass              |   5   |
| [ ] | `D99 T01 §4` | Demo clip                     |   5   |
