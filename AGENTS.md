# AGENTS.md

Agent instructions for this repository. Human orientation lives in `README.md`; Claude-specific guidance in `CLAUDE.md`.

## What is here

`intelligent-notepad` is the monorepo for an exact Windows 11 Notepad clone (C++, WinUI 3) with Claude Code and Codex inside via the Agent Client Protocol. Day 1: the plan and its tooling. `src/` lands with `D00 T01 §2`.

| Path | Purpose |
| ---- | ------- |
| `src/` | The app (not yet scaffolded) |
| `tests/` | Unit, UI, protocol, perf suites (backbone: `D00 T02`) |
| `resources/baseline/` | Captured Notepad baseline for parity checks (lands with `D00 T02 §3`) |
| `todo/` | Canonical execution contracts; read `todo/README.md` before authoring or implementing |
| `todo/implementation-plan.md` | Ordered execution plan synchronized through `scripts/todo-graph.py` |
| `scripts/` | Neutral tooling: graph, validator, adjacency inspector |
| `docs/` | User guide, review records, phase runs, plans |
| `build/` | Ignored derived output, never an authoritative record |

## Choose the work contract

For TODO work, read the target section, `todo/README.md`, its dependencies, and the applicable skill under `.claude/skills/`: capture through `add-todo`, build through `process-todo-section`, stamp through `review-todo-section`, close a file through `process-todo-file`, run a phase or the plan through `process-phase` or `process-plan`, harden the tree through `groom-plan`.

The lifecycle is: capture, author, validate the plan and source claims, record `Started:`, implement, run the section's gates, commit, review and stamp, then sync the plan. Each section must be executable with zero conversation context. Preserve section addresses and bidirectional cross-references (`§N`, `TNN §N`, `DNN TNN §N`). A TODO Implementation Order row turns `[x]` only with its `Verified:` stamp through the review skill. Do not rewrite a stamped checklist or transfer evidence across changed candidates. File new work with its own owner and dependency.

## Working rules

- **Output discipline:** bound every command (`ctest -R`, `tail`/`head`, field extraction, `>/dev/null`). Keep full logs in ignored scratch.
- **Act, then report:** complete authorized work and report evidence. Explicit operator stop instructions take effect immediately.
- **Writes are serial:** one session owns the working tree. Check `git status` before building over unfamiliar work.
- **User data first:** atomic writes, readback, skip-and-report, confirmed destructive paths. Checkpoints prove the failure path too.
- **Parity is proven:** captures for Notepad surfaces, ACP schema and docs for protocol behavior. No artifact, no claim.
- **Consent gates agents:** deny-by-default, exactly-once answers, diff review, undoable apply.
- **No em dashes** in authored prose. One line per paragraph and list item in Markdown.
- **Source of truth:** Notepad behavior via captures, ACP via agentclientprotocol.com, plan state via `todo/`. Intelligent Terminal is prior art, never a design authority. Disagreements are recorded decisions, not silent reinterpretations.

## Validation

```bash
python3 scripts/todo-graph.py self-test      # 391 cases, must stay green
python3 scripts/todo-graph.py validate       # FATAL blocks; new WARN* blocks until fixed or accepted
python3 scripts/todo-graph.py query ready    # dependency-safe work right now
python3 scripts/todo-graph.py plan --sync    # re-derive the plan projection after TODO edits
python3 scripts/todo-graph.py plan --check   # fail if the projection went stale
```

Run checks owed by the task. Report only commands actually run, and distinguish static evidence, test output, and review proof.

Use trunk-based `main` for routine work and concise imperative commits. Respect exact candidate identity and one-section scope. Never bypass hooks with `--no-verify`, amend a recorded candidate, or force-push.

## Credentials

Credentials never enter tracked files, arguments, logs, or handoff prose. Agent auth uses the platform credential store.
