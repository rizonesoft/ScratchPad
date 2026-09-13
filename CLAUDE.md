# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## What this repository is

**Intelligent Notepad**: an exact Windows 11 Notepad clone in C++ and WinUI 3, with Claude Code and Codex inside via the Agent Client Protocol. Day 1: the repo holds the plan and its tooling; `src/` lands with `D00 T01 §2`.

```
todo/                   the live execution plan -- 8 numbered domains 00-07
todo/implementation-plan.md  every section in dependency order; checkboxes DERIVED, never hand-ticked
scripts/todo-graph.py   build / validate / query / render / plan the TODO graph (stdlib-only)
docs/reviews/           per-section review findings, committed with the review
docs/phase-runs/        phase-runner findings files (created by process-phase)
build/                  gitignored derived output (graph cache, progress JSON)
```

The app builds and tests on Windows only. The TODO tooling (`scripts/`, plan checks) runs anywhere with Python 3.

## The TODO system -- how work is planned and shipped

`todo/` is the live execution plan; **format spec: `todo/README.md`.** Markdown is canonical and `build/` holds derived, gitignored projections.

Eight flat-numbered domains `00`-`07`: `00-workspace` (toolchain/CI/this system/test backbone), `01-notepad-core` (window/tabs/files/menus/settings), `02-editor` (text surface/find), `03-acp-client` (protocol), `04-agents` (launch/sessions/auth), `05-ai-surface` (chat/consent/diff), `06-quality` (test strategy/conformance), `07-release` (packaging/update). Numbers are stable addresses: a new domain appends after `07`.

Files are `todo/NN-domain/TODO-NN-short-name.md`. The **Implementation Order table is the dependency graph**: every `## N.` section has exactly one row and vice versa, and a row flips to `[x]` only when a `Verified:` stamp covers it. Cross-references use `§N` / `TNN §N` / `DNN TNN §N` and must be bidirectional.

Eight skills drive it: **`add-todo`** (front door for new work), **`create-todo`** (author a file), **`process-todo-section`** (validate one section's plan, correct drift, then ship it), **`review-todo-section`** (quality gate; the only thing that flips a row), **`process-todo-file`** (closeout), **`process-phase`** (attended runner to 100% or parked), **`process-plan`** (front door for the whole plan), **`groom-plan`** (harden the tree without shipping).

Two rules worth stating here because they are the ones that get broken: **one section = one commit**, and **write every section for an executor with zero conversation context**: a fresh session starts with none, so "as discussed" is unimplementable.

## Commands

```bash
python3 scripts/todo-graph.py self-test      # the script's OWN contract, against fixtures
python3 scripts/todo-graph.py validate       # structural + graph integrity of todo/
python3 scripts/todo-graph.py query ready    # sections whose dependencies are met
python3 scripts/todo-graph.py query blocked  # sections waiting on something
python3 scripts/todo-graph.py query stats    # tree health
python3 scripts/todo-graph.py plan --sync    # re-derive implementation-plan.md's checkboxes
python3 scripts/todo-graph.py plan --check   # fail if the boxes are stale (CI runs this)
python3 scripts/todo-graph.py resolve 'D00 T01 §1'   # ref -> file, section, deps, status
```

Build and test commands arrive with `D00 T01` (one-command build, `ctest` suite). Until they land, `todo-graph.py` is the only thing to run, and it is stdlib-only by design.

## Working rules

- **Output discipline:** bound every command. `ctest -R` for affected suites, `tail`/`head` on logs, field extraction on JSON, `>/dev/null` for output nobody reads. An unbounded dump into the session is a process defect.
- **Act, then report:** complete authorized work and report evidence. Resolve ordinary unknowns from source, then choose and record a default where needed. Explicit operator stop instructions take effect immediately.
- **Writes are serial:** one session owns the working tree. Check `git status` for unfamiliar uncommitted work before building over it.
- **User data first:** atomic writes, read back what was written, skip and report rather than drop or duplicate, every destructive path confirmed. Checkpoints exercise the failure path, not only the happy path.
- **Parity is proven, not remembered:** Notepad surfaces are checked against the captured baseline under `resources/baseline/`; protocol behavior against the ACP schema and docs. A claim without its artifact is not evidence.
- **Consent gates every agent action:** deny-by-default, prompt faithfully, answer exactly once. An agent edit reaches the buffer only through diff review and the undoable edit path.
- **No em dashes:** use ordinary punctuation in authored prose. One line per paragraph and per list item in Markdown.
- **Source-of-truth hierarchy:** Windows 11 Notepad behavior (via captures) for the clone surfaces; [agentclientprotocol.com](https://agentclientprotocol.com/get-started/agents) for protocol behavior; this repo's `todo/` for what is planned and what shipped. [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) is prior art (it proved ACP fits a native app), never a design authority. Where sources disagree, say so and record the decision.

## Unknowns and questions

Answer from source first (captures, protocol docs, code). When an unanswered question would change implementation, take a justified default, record that it is a default with its cost of changing, and carry on. Do not stall a section waiting for an answer; do not silently reinterpret a section into something buildable.

## Credentials

Credentials never enter tracked files, command arguments, logs, or handoff prose. Agent auth uses the platform credential store; protocol test suites needing API keys are marked and skipped honestly until keys exist.
