# AGENTS.md

Agent instructions for this repository. Human orientation lives in `README.md`. Claude Code loads this file through the `CLAUDE.md` import stub.

## What is here

`ScratchPad` is the monorepo for an exact Windows 11 Notepad clone (C#, WinUI 3 on .NET) with Claude Code and Codex inside via the Agent Client Protocol. Day 1: the plan and its tooling. `src/` lands with `D00 T01 §2`.

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

The app runs on Windows only; neutral libraries build and test anywhere with the repo-local .NET SDK. The TODO tooling (`scripts/`, plan checks) runs anywhere with Python 3.

## The TODO system

`todo/` is the live execution plan; **format spec: `todo/README.md`.** Markdown is canonical and `build/` holds derived, gitignored projections.

Nine flat-numbered domains `00`-`08`: `00-workspace` (toolchain/CI/this system/test backbone), `01-notepad-core` (window/tabs/files/menus/settings), `02-editor` (text surface/find), `03-acp-client` (protocol), `04-agents` (launch/sessions/auth), `05-ai-surface` (chat/consent/diff), `06-quality` (test strategy/conformance), `07-release` (packaging/update), `08-voice` (speech engines/surface). Numbers are stable addresses: a new domain appends after `08`.

Files are `todo/NN-domain/TODO-NN-short-name.md`. The **Implementation Order table is the dependency graph**: every `## N.` section has exactly one row and vice versa, and a row flips to `[x]` only when a `Verified:` stamp covers it. Cross-references use `§N` / `TNN §N` / `DNN TNN §N` and must be bidirectional.

## Choose the work contract

For TODO work, read the target section, `todo/README.md`, its dependencies, and the applicable skill under `.claude/skills/`: capture through `add-todo`, author a file through `create-todo`, build through `process-todo-section`, stamp through `review-todo-section`, close a file through `process-todo-file`, run a phase or the plan through `process-phase` or `process-plan`, harden the tree through `groom-plan`.

The lifecycle is: capture, author, validate the plan and source claims, record `Started:`, implement, run the section's gates, commit, review and stamp, then sync the plan. Each section must be executable with zero conversation context. **One section = one commit.** Preserve section addresses and bidirectional cross-references (`§N`, `TNN §N`, `DNN TNN §N`). A TODO Implementation Order row turns `[x]` only with its `Verified:` stamp through the review skill. Do not rewrite a stamped checklist or transfer evidence across changed candidates. File new work with its own owner and dependency.

## Working rules

- **Output discipline:** bound every command (`dotnet test --filter`, `tail`/`head`, field extraction, `>/dev/null`). Keep full logs in ignored scratch.
- **Act, then report:** complete authorized work and report evidence. Explicit operator stop instructions take effect immediately.
- **Writes are serial:** one session owns the working tree. Check `git status` before building over unfamiliar work.
- **User data first:** atomic writes, readback, skip-and-report, confirmed destructive paths. Checkpoints prove the failure path too.
- **Parity is proven:** captures for Notepad surfaces, ACP schema and docs for protocol behavior. No artifact, no claim.
- **Consent gates agents:** deny-by-default, exactly-once answers, diff review, undoable apply.
- **No em dashes** in authored prose. One line per paragraph and list item in Markdown.
- **Section atomicity is the candidate range:** one section ships as one logical change, and review fix-loop commits append to that range (never amend); each fix is re-reviewed and the stamp names the whole range. "One section = one commit" never means "one hash".
- **Source of truth:** Notepad behavior via captures, ACP via [agentclientprotocol.com](https://agentclientprotocol.com/get-started/agents), plan state via `todo/`. [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) is prior art, never a design authority. Disagreements are recorded decisions, not silent reinterpretations.

## Unknowns and questions

Answer from source first (captures, protocol docs, code). When an unanswered question would change implementation, take a justified default, record that it is a default with its cost of changing, and carry on. Do not stall a section waiting for an answer; do not silently reinterpret a section into something buildable.

## Validation

```bash
python3 scripts/todo-graph.py self-test      # 696 cases, must stay green
python3 scripts/todo-graph.py validate       # FATAL blocks; new WARN* blocks until fixed or accepted
python3 scripts/todo-graph.py query ready    # dependency-safe work right now
python3 scripts/todo-graph.py query blocked  # sections waiting on something
python3 scripts/todo-graph.py query stats    # tree health
python3 scripts/todo-graph.py query plan-health  # review-loop governance: --json emits schema plan-health/3 (total sort keys, exits 0); --check/--fail-on gate automation
python3 scripts/todo-graph.py query summary      # operator digest: incomplete runs, blocked clearances, overdue owners, next action, gate verdict (text-only; exits 1 when the gate fails)
python3 scripts/todo-graph.py plan --sync    # re-derive the plan projection after TODO edits
python3 scripts/todo-graph.py plan --check   # fail if the projection went stale
python3 scripts/todo-graph.py resolve 'D00 T01 §1'   # ref -> file, section, deps, status
```

Build and test commands arrive with `D00 T01` (one-command build, `dotnet test` suite). Until they land, `todo-graph.py` is the only thing to run, and it is stdlib-only by design.

Run checks owed by the task. Report only commands actually run, and distinguish static evidence, test output, and review proof.

Use trunk-based `main` for routine work and concise imperative commits. Respect exact candidate identity and one-section scope. Never bypass hooks with `--no-verify`, amend a recorded candidate, or force-push.

## Credentials

Credentials never enter tracked files, arguments, logs, or handoff prose. Agent auth uses the platform credential store; protocol test suites needing API keys are marked and skipped honestly until keys exist.
