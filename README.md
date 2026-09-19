# Intelligent Notepad

Notepad, exact down to the status bar. Plus your AI agents. Minus the subscription nag.

## Why this exists

Somewhere along the way, the humble text editor learned a new trick: asking for money. You highlight a paragraph, click Rewrite, and instead of better prose you get a message explaining that intelligence costs $10 a month, billed annually, terms and conditions apply, have you tried turning your wallet off and on again.

Intelligent Notepad is built on a contrarian belief: that the AI subscription you already have should work in the text editor you already use. No Microsoft account sign-in to summarize a grocery list. No AI credits deducted because you dared to rephrase a sentence. No Copilot+ PC required to fix a typo with anything smarter than hope.

Just Notepad. Every tab, every menu, every pixel of the status bar, reproduced 1:1 in C# and WinUI 3 on .NET. And sitting beside it, a panel where Claude Code and Codex do the thinking, reached through the open [Agent Client Protocol](https://agentclientprotocol.com/get-started/agents). Your agents, your keys, your machine. The paywall is not included, because there isn't one.

Design authority is split exactly two ways: Windows 11 Notepad dictates the editor, and the Agent Client Protocol specification dictates the agent layer. Microsoft's [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) proved that ACP fits inside a native desktop app, and it is cited in the plan as prior art for that lesson only. Nothing here is designed to match it: the context is your document, never a shell, and nobody suggests running `rm -rf` anything.

## What it is not

It is not a terminal, and it is not designed like one. Nothing here runs shell commands, detects failed builds, or knows what a TTY is. The agent chrome (status bar, pane, sessions, slash commands) solves editor problems for documents; any resemblance to terminal agent UX ends at "both talk ACP". If you came looking for a command line with opinions, that project is excellent and it lives next door.

It is not Word. There will be no paperclip, no mail merge, and no Clippy resurrection arc, no matter how politely you ask.

It is not a subscription. Saying it twice because it bears repeating.

## Layout

| Path | What it is |
| ---- | ---------- |
| `src/` | The app (WinUI 3 shell plus editor, ACP, agents) |
| `tests/` | Unit, UI, protocol, and perf suites (backbone: `D00 T02`) |
| `resources/baseline/` | Captured Notepad baseline for parity checks |
| `todo/` | The live execution plan. Start here. |
| `scripts/todo-graph.py` | Build, validate, query, and render the TODO graph (stdlib-only) |
| `docs/` | User guide, review records, phase runs, plans |

## Toolchain pins

Exact versions, verified 2026-09-13 against the .NET release metadata and NuGet. Nothing here floats.

| Component | Version | Pinned in |
| --------- | ------- | --------- |
| .NET SDK | 10.0.401 (runtime 10.0.12, released 2026-09-08) | `global.json` (`rollForward: disable`) |
| Windows App SDK | 2.4.0 | this file until §2's lockfile |
| xunit | 2.9.3 | `tests/Smoke/packages.lock.json` |
| xunit.runner.visualstudio | 2.8.2 | `tests/Smoke/packages.lock.json` |
| Microsoft.NET.Test.Sdk | 17.14.1 | `tests/Smoke/packages.lock.json` |

`tools/provision.sh` (Linux) and `tools/provision.ps1` (Windows) read the SDK version from `global.json`, download that exact build from `builds.dotnet.microsoft.com`, verify its published SHA512 (linux-x64 `51c8b999…ce25b`, win-x64 `24b670ad…79430`; full hashes in the [release metadata](https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json)), and extract into repo-local `.tools/dotnet-<rid>/` (one SDK per OS so both coexist in one checkout). No machine-wide install, no build step reads outside the repo. Run `./tools/provision.sh` (or `powershell -ExecutionPolicy Bypass -File tools\provision.ps1`), then prefix SDK commands with `export DOTNET_ROOT="$PWD/.tools/dotnet-linux-x64" PATH="$PWD/.tools/dotnet-linux-x64:$PATH" DOTNET_MULTILEVEL_LOOKUP=0` (Windows: `.tools\dotnet-win-x64`).

The xunit v2 line is pinned, reversing the §1 v3 default: v3 on MTP (`xunit.v3.mtp-v2` 4.0.1 + MTP 2.4.0 + SDK 10.0.401) discovers zero tests under `dotnet test`, proven on our project and on xunit's own official template alike, while the v2 VSTest stack passes first try. T02 §1 re-evaluates v3/MTP when the ecosystem heals; swapping majors costs a `PackageReference` edit plus lockfile regeneration until suites exist.

## Start here

1. `todo/TODO-00-INDEX.md` -- domain order and active work.
2. `todo/implementation-plan.md` -- every section in dependency order, grouped in phases.
3. `todo/README.md` -- the format spec: sections, stamps, XREFs, gates.
4. `AGENTS.md` -- working rules.

```bash
python3 scripts/todo-graph.py self-test      # the script's own contract, ~1s
python3 scripts/todo-graph.py validate       # structural + graph integrity of todo/
python3 scripts/todo-graph.py query ready    # sections whose dependencies are met
python3 scripts/todo-graph.py resolve 'D00 T01 §1'   # any section reference -> file, section, deps, status
```

## The build

.NET and WinUI 3 on Windows 11. One-command build and one-command test, pinned SDK, CI on Linux and Windows runners: all owned by `D00 T01`. Testing is automatic and complete per the bar `D06 T01` writes; no feature is done until its automated proof is green, because "works on my machine" is a confession, not a test result.

Only the ACP client talks to agents, over JSON-RPC 2.0 on stdio: the client launches the agent subprocess (Codex via `codex-acp`, Claude via `claude-agent-acp`), negotiates versions, and drives sessions. Every agent action is consent-gated (`D03 T02`, `D05 T02`); every agent edit is reviewed as a diff and applied through undo (`D05 T02 §3-§4`). The agent can suggest; only you can commit. Literally: one section, one commit, and the row flips only when review says so.

## Port notes

The TODO system (graph script, format, skills, plan mechanics) is a day-1 port of the JMR Online TODO system, seeded 2026-09-14 and groomed against real Windows 11 Notepad behavior the same week. History comments in the scripts name JMR sections (`D00 T01 §21` and the like): those are provenance for why a rule exists, not live references here.

## Deferred

Ported deliberately later, when the repo earns them:

- `plan-gate.py` (routing authority with host probes and clock parks): `query ready` plus the phase tables route until then.
- External review panel scripts (`review-batch`, `review-rounds`, `review-families`, `review-slices`): lens verdicts come from the headless Opus panel per `review-todo-section` until then.
- `section_commit_gate.py` (stamp provenance at commit time): `validate` plus review carry the contract until then.
- Run-guard Stop hook: `process-phase` holds completion-first as procedure until then.
- `coming-soon-inspect.py`: the `pending-control-contract` severity class stays reserved until it lands.
- CI workflows (build, test, todo gates): owned by `D00 T01 §3` and `§7`, not scaffolded here.
