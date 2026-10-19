# Subagent routing

Operator direction 2026-10-01: minimize agent cost without lowering the bar. The lead Claude Code session delegates bounded read-only work (research, gate runs, and routine pre-review passes) to Sonnet agents at high effort, and keeps implementation, architecture, integration, acceptance, and consequential review. Operator direction 2026-10-02: no Sonnet agent implements; every code, test, and docs change is the lead's. The working rules live in `AGENTS.md` (Delegation); this file is the routing record and its live evidence.

## Routing

| Agent | Model alias | Effort | Writes | Tools |
| ----- | ----------- | ------ | ------ | ----- |
| `sonnet-researcher` | `sonnet` | `high` | no | Read, Grep, Glob, Bash, PowerShell, WebFetch, WebSearch |
| `sonnet-verifier` | `sonnet` | `high` | no | Read, Grep, Glob, Bash, PowerShell |
| `sonnet-reviewer` | `sonnet` | `high` | no | Read, Grep, Glob, Bash, PowerShell |
| `code-explorer` | `sonnet` | `high` | no | Read, Glob, Grep, Bash |
| `debug-evidence` | `sonnet` | `high` | no | Bash, Read, Glob, Grep |
| `git-runner` | `sonnet` | `high` | no | Bash, Read, Grep |
| `mutation-tester` | `sonnet` | `high` | no (mutates only its own throwaway worktree) | Bash, Read, Glob, Grep |
| `test-runner` | `sonnet` | `high` | no | Bash, Read, Glob, Grep |

The last five come from the Conclave-SDK base kit (imported 2026-10-19, operator decision to route all five). Refreshing a body from the kit drops the `effort: high` line ScratchPad adds; `check` then fails until the line is restored. In this repo `git-runner` stays read-only: the lead owns every commit, so a brief never asks it to commit, push, rebase, reset, or clean.

Definitions: `.claude/agents/<name>.md`. No routed agent holds a write tool or the Agent tool, so delegates cannot edit files through their tools, delegation never nests, and the lead stays the only writer and integrator.

## Enforcement

- **Pins:** `scripts/agent_routing.py` holds the closed set (`ROUTED_AGENTS`). `check` fails when an agent file's model, effort, or tool list drifts, when any routed agent lists a tool outside the read-only allowlist (Read, Grep, Glob, Bash, PowerShell, WebFetch, WebSearch; scoped forms count as their tool, so `Write(src/**)` and MCP tools fail) or a frontmatter key outside `name`, `description`, `model`, `effort`, `tools`, `disallowedTools` (so `memory`, `mcpServers`, or `hooks` cannot grant capabilities the tools list hides), when a tools entry is malformed, when an agent exists without a pin or a pin without an agent, when the hook is unwired, carries any key beyond `type`, `command`, and `timeout` (`async` or `asyncRewake` would run it in the background, where it cannot deny), or is disabled, when project settings set an env override of the pinned model or effort, or when this record stops naming an agent. It runs in `plan-gates` CI and in `tools/githooks/pre-commit` on the staged tree; `self-test` covers both directions with red fixtures.
- **Hook:** `.claude/settings.json` runs `agent_routing.py pre-agent` on every `Agent` call. It denies a model override on a routed agent, a session env that would change a routed agent's model or effort, any agent defined under `.claude/agents/` that is not routed (a re-added `sonnet-implementer.md` included), and built-in `general-purpose`, `claude`, `Explore`, `Plan`, and `claude-code-guide` (or no type) unless the call passes `model: "opus"` as a deliberate escalation. `fork` (the lead's own model) and other types pass. It fails open on a malformed payload; the `check` gate guards its wiring.
- **Observation:** `python3 scripts/agent_routing.py observe <session dir>` reads the session's subagent transcripts and prints, per agent, the model ids the API actually served and the per-turn effort the harness actually sent. Re-run it after any Claude Code update, alias change, or pin edit, and append the result below.

## Brief template

A delegate starts with no conversation context, so the brief carries everything:

- **Goal:** one sentence, and the TODO ref when there is one.
- **Scope:** exact paths to read and commands to run.
- **Sources:** which captures, spec pages, or sections are authoritative.
- **Acceptance:** observable criteria and the bounded commands that prove them.
- **Stop rules:** what to report instead of deciding (design choices, contradictions, out-of-scope files).

## Verification record

Session start loads `.claude/agents/`; settings hooks reload mid-session. A session that predates an agent file cannot spawn it until Claude Code rescans (observed: the authoring session refused the new agents at first and listed them later in the same session), so live verification runs in a fresh session.

Alias resolution: `sonnet` resolves to `claude-sonnet-5-5` on the Anthropic API under Claude Code 2.1.287; the newest Sonnet id the installed CLI knows is also `claude-sonnet-5-5` (binary scan, 2026-10-01). No `ANTHROPIC_DEFAULT_SONNET_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`, or `CLAUDE_CODE_EFFORT_LEVEL` was set in the verifying environment.

Observed: 2026-10-01, Claude Code 2.1.287, `observe` over the subagent transcripts (`message.model` is the id the API served; `perTurnEffort` is the effort the harness sent).

| Session | Lead | Delegate | Real task | Model | Effort |
| ------- | ---- | -------- | --------- | ----- | ------ |
| fresh `claude -p` 6bf3137b | `claude-opus-5-5`, high | `sonnet-researcher` | sweep skills and docs for rules contradicting delegation | `claude-sonnet-5-5` x37 turns | `high` x37 |
| fresh `claude -p` 9882c31f | `claude-opus-5-5`, high | `sonnet-verifier` | run routing, validator, plan, probe, and graph self-tests | `claude-sonnet-5-5` x34 | `high` x34 |
| same, in parallel | | `sonnet-reviewer` | routine review of this change's diff | `claude-sonnet-5-5` x25 | `high` x25 |
| authoring session 17bfea76 | `claude-opus-5-5`, high | `sonnet-verifier` | full gate run: routing, validator, plan, probe, graph self-tests, pre-commit simulation, em-dash scan | `claude-sonnet-5-5` | `high` |
| fresh `claude -p` faccc373 (2026-10-19, Claude Code 2.1.303) | `claude-opus-5-5`, high | `code-explorer` | locate the effort pin check | `claude-sonnet-5-5` x2 | `high` x2 |
| same, in parallel | | `debug-evidence` | try to reproduce a reported `check` failure | `claude-sonnet-5-5` x2 | `high` x2 |
| same, in parallel | | `git-runner` | status and last three commits | `claude-sonnet-5-5` x2 | `high` x2 |
| same, in parallel | | `test-runner` | `todo-graph.py self-test` | `claude-sonnet-5-5` x2 | `high` x2 |
| same, in parallel | | `mutation-tester` | disable the effort pin check, run routing self-test (killed: 117/119) | `claude-sonnet-5-5` x11 | `high` x11 |

Hook: a live `general-purpose` spawn without a model was denied with the routing message (authoring session, 2026-10-01).

History: a `sonnet-implementer` agent was routed on 2026-10-01 (it ran at `claude-sonnet-5-5`, `high`) together with a delegation audit (`delegate-start`/`delegate-audit`) meant to prove an implementer never weakened an implementation. On 2026-10-02 the operator removed the implementer, and the audit, which had no other consumer, was removed with it.

Independent review: GPT sign-off slot (`.conclave/panel.toml`, `gpt-6-astra`, high, read-only). Rounds 1 to 3 on the routing hook and `check` (effort env overrides, nested agent files, YAML tool lists, `disableAllHooks`, block scalars, escapes, the forced subagent-model fallback) were fixed and re-reviewed; later rounds' tool-list findings (quoted arguments, capability words inside arguments, unbalanced parentheses) were fixed with regression cases. Rounds 4 to 7 reviewed the delegation audit; it was removed before round 7's last two findings were fixed, so they no longer apply.

## Limitations

- Routed agents keep Bash and PowerShell for reading and running gates, so a shell command could still write; their instructions forbid it, and the lead checks `git status` after every delegate run and reverts any such change.
- `mutation-tester` works in a fresh `git worktree`, which lacks the ignored repo-local SDK `global.json` pins (`.tools/dotnet-win-x64`), so a `dotnet test` baseline there goes red. Brief it with Python gates (`agent_routing.py`, `todo-graph.py`, dispatcher tests); a .NET mutation run stays with the lead until the agent can link `.tools` into its copy.
- `debug-evidence` is written for Linux services (`journalctl`, WSL paths); on this Windows-only repo, brief it with the Windows logs and commands to use.
- Agents spawned by the Workflow tool's `agent()` do not pass through the Agent PreToolUse hook; a workflow script must pass `model: 'sonnet'` itself and must not delegate writes to it.
- User-level `~/.claude/agents/`, plugin agents, and user settings are outside `check`; the hook still sees the env they leave in the session.
- The hook runs under `python3`; if it is missing from the hook shell, Claude Code treats the error as non-blocking and routing is unenforced.
