# AGENTS.md

Agent instructions for this repository. Human orientation lives in `README.md`. Claude Code loads this file through the `CLAUDE.md` import stub.

## What is here

`ScratchPad` is the monorepo for an exact Windows 11 Notepad clone (C#, WinUI 3 on .NET) with Claude Code and Codex inside via the Agent Client Protocol. Toolchain, scaffold, CI, and the TODO tooling are live; the app grows under `src/`.

| Path | Purpose |
| ---- | ------- |
| `src/` | The app (WinUI 3 shell plus editor, ACP, agents) |
| `tests/` | Unit, UI, protocol, perf suites (backbone: `D00 T02`) |
| `resources/baseline/` | Captured Notepad baseline for parity checks |
| `todo/` | Canonical execution contracts; read `todo/README.md` before authoring or implementing |
| `todo/implementation-plan.md` | Ordered execution plan synchronized through `scripts/todo-graph.py` |
| `scripts/` | `todo-graph.py` (validate, plan, queries) and `agent_routing.py` |
| `docs/` | User guide, testing policy, phase runs, specs and plans; `docs/reviews/` is read-only history |
| `build/` | Ignored derived output, never an authoritative record |

The app runs on Windows only; neutral libraries build and test on Windows with the repo-local .NET SDK. The TODO tooling (`scripts/`, plan checks) runs on Windows with Python 3. CI and dev are Windows-only since the 2026-09-19 operator decision.

## The TODO system

`todo/` is the live execution plan; **format spec: `todo/README.md`.** Markdown is canonical; `todo/implementation-plan.md` is derived from it by `plan --sync`. Simplified 2026-10-18: `docs/specs/2026-10-18-simplify-process-design.md`.

Nine flat-numbered domains `00`-`08`: `00-workspace` (toolchain/CI/this system/test backbone), `01-notepad-core` (window/tabs/files/menus/settings), `02-editor` (text surface/find), `03-acp-client` (protocol), `04-agents` (launch/sessions/auth), `05-ai-surface` (chat/consent/diff), `06-quality` (test strategy/conformance), `07-release` (packaging/update), `08-voice` (speech engines/surface). Numbers are stable addresses: a new domain appends after `08`.

Files are `todo/NN-domain/TODO-NN-short-name.md`. The **Implementation Order table is the dependency graph**: every `## N.` section has exactly one row and vice versa, and a row flips to `[x]` only when a `Verified:` stamp covers it. Cross-references use `§N` / `TNN §N` / `DNN TNN §N` and must be bidirectional.

## Choose the work contract

For TODO work, read the target section, `todo/README.md`, its dependencies, and the skill under `.claude/skills/`: capture or author through `add-todo`, ship or audit one section through `process-todo-section`, run a phase or the plan through `process-phase`, harden the tree through `groom-plan`.

The lifecycle is: capture, check the section's claims against the repository, record `Started:`, implement, run the section's gates, commit, one independent Opus review with fixes, stamp, flip the row, sync the plan, commit. Each section must be executable with zero conversation context. Preserve section addresses and bidirectional cross-references. A row turns `[x]` only with its `Verified:` stamp. Do not rewrite a stamped checklist. File new work only for an observable failure or an operator request, with its own owner and dependency.

## Working rules

- **Output discipline:** bound every command (`dotnet test --filter`, `tail`/`head`, field extraction, `>/dev/null`). Keep full logs in ignored scratch.
- **Act, then report:** complete authorized work and report evidence. Explicit operator stop instructions take effect immediately.
- **Writes are serial:** one session owns the working tree. Check `git status` before building over unfamiliar work.
- **Claude Code is the only writer** (operator decision 2026-09-23): no other harness edits or commits in this repo. Codex reviews only when the operator asks.
- **User data first:** atomic writes, readback, skip-and-report, confirmed destructive paths. Checkpoints prove the failure path too.
- **Testing is scoped and quiet** (operator decision 2026-10-14, `docs/testing.md`): no scheduled test runs; a section runs every test of its feature and nothing else, and checks anything the user sees visually against Notepad; the full suite runs when a phase, file, or release closes, and only the operator starts the foreground legs.
- **Parity is proven:** captures for Notepad surfaces, ACP schema and docs for protocol behavior. No artifact, no claim.
- **Consent gates agents:** deny-by-default, exactly-once answers, diff review, undoable apply.
- **No em dashes** in authored prose. One line per paragraph and list item in Markdown.
- **One section is one logical change:** review fixes land as new commits (never amend) and are re-reviewed.
- **Source of truth:** Notepad behavior via captures, ACP via [agentclientprotocol.com](https://agentclientprotocol.com/get-started/agents), plan state via `todo/`. [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) is prior art, never a design authority. Disagreements are recorded decisions, not silent reinterpretations.

Completion-first: finish the section in the shipping session: run every test of what it implemented, its own Interactive and Primary tests included, scoped by filter (never the whole suite), and flip the same session. Tests the host cannot run are noted in the `Verified:` evidence and covered by the phase-close run; they never park work.

## Delegation

Cost rule (operator direction 2026-10-01): the lead session delegates every bounded read-only task a Sonnet agent can reliably finish to the bar, and keeps what needs judgment. Delegates never write: implementation stays with the lead (operator direction 2026-10-02). Routing, pins, and the live verification record: `docs/agent-routing.md`; pins are enforced by `scripts/agent_routing.py` (PreToolUse hook, `check` in CI and pre-commit).

| Agent | Pin | Delegate |
| ----- | --- | -------- |
| `sonnet-researcher` | sonnet, high | fact-checks of section claims, code location, reference tracing, source and spec lookup |
| `sonnet-verifier` | sonnet, high | named build, test, validator, and checkpoint runs with bounded results |
| `sonnet-reviewer` | sonnet, high | routine pre-review diff pass: test quality, scope, drift, style |

- **The lead keeps:** all implementation (code, tests, docs, TODO edits), architecture and design decisions, TODO plan corrections, `Started:`, integration, commits, the final Test checkpoint run, stamps and row flips, the review call, and its own review of consequential design, security, privacy, consent, data integrity, and critical correctness.
- **Briefs are complete:** goal, exact paths, sources to use, acceptance criteria, and the commands that prove them. A delegate gets what it needs and nothing it must rediscover.
- **Delegates never write:** routed agents hold no write tools (`check` enforces it); the lead checks `git status` after every delegate run and reverts anything a delegate changed through its shell.
- **Escalate, do not absorb:** a delegate's ambiguity, failed check, or unresolved finding comes back to the lead. After two unsuccessful delegations of the same task, the lead does it itself or stops and reports; it never accepts a weaker result.
- **Stronger model on purpose:** built-in `general-purpose`, `claude`, `Explore`, `Plan`, and `claude-code-guide` are denied by the hook unless the call passes `model: "opus"`; that, a fork, or the lead itself is the escalation path for consequential review. Routed agents never take a model override.
- **Independent review** is one Opus pass per section (`process-todo-section` step 4); `sonnet-reviewer` passes are advisory input to the lead's own review.

## Unknowns and questions

Answer from source first (captures, protocol docs, code). When an unanswered question would change implementation, take a justified default, record that it is a default with its cost of changing, and carry on. Do not stall a section waiting for an answer; do not silently reinterpret a section into something buildable.

## Validation

```bash
python3 scripts/todo-graph.py self-test      # the tool's own fixtures
python3 scripts/todo-graph.py validate       # integrity; exit 1 on any problem
python3 scripts/todo-graph.py query ready    # dependency-safe work right now
python3 scripts/todo-graph.py query blocked  # sections waiting on something
python3 scripts/todo-graph.py query stats    # tree totals
python3 scripts/todo-graph.py plan --sync    # re-derive the plan after TODO edits
python3 scripts/todo-graph.py plan --check   # fail if the plan went stale
python3 scripts/todo-graph.py resolve 'D00 T01 §1'   # ref -> file, section, deps, status
```

One-command build and `dotnet test` suite live under `src/` and `tests/` (owned by `D00 T01 §2`); `todo-graph.py` stays stdlib-only by design.

Run checks owed by the task. Report only commands actually run, and distinguish static evidence, test output, and review proof.

Use trunk-based `main` for routine work and concise imperative commits. Respect exact candidate identity and one-section scope. Never bypass hooks with `--no-verify`, amend a recorded candidate, or force-push.

## Credentials

Credentials never enter tracked files, arguments, logs, or handoff prose. Agent auth uses the platform credential store; protocol test suites needing API keys are marked and skipped honestly until keys exist.
