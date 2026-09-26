# Contributing to ScratchPad

Thanks for looking. This file takes you from a clone to a first pull request.

## Where the work lives

Every piece of planned work is a section in a TODO file under `todo/`, grouped into nine domains (`00-workspace` through `08-voice`). `todo/implementation-plan.md` lists every section in dependency order, and `todo/README.md` is the format spec. A section is self-contained: its context paragraph, a checklist of steps each with a "Done when", a commit message, and a test checkpoint.

To find work that is ready now:

```powershell
py scripts/todo-graph.py query ready
py scripts/todo-graph.py resolve 'D01 T02 §5'   # one section: file, dependencies, status
```

A section ships as one logical change: implement its checklist, run its gates, and commit with the message the section names. The project's own agent follows the `process-todo-section` skill (`.claude/skills/process-todo-section/`) for the same flow; reading it shows exactly what "done" means here. Review and the `Verified:` stamp that flips a section to done are run by the maintainer, so a pull request needs to carry the implementation and its evidence, not the stamp.

New work that has no section yet starts as an issue (the feature template names the plan reference it would belong to), not as code.

## Build and test

Set up once with the quick start in [README.md](README.md) (provision the pinned SDK, put it on PATH). Then:

```powershell
dotnet build src/ScratchPad.slnx          # everything; warnings are errors
dotnet test src/Notepad.Neutral.slnf      # fast: core, ACP, agents, unit, protocol
dotnet test src/ScratchPad.slnx           # everything, including UI automation that drives real windows
py tools/launch.py                        # run the app you built
```

[docs/build.md](docs/build.md) and [docs/testing.md](docs/testing.md) are the full references.

## Gates before a pull request

Run these and paste their results into the pull request template:

1. `dotnet build src/ScratchPad.slnx` passes with no warnings.
2. `dotnet test src/ScratchPad.slnx` passes (or the neutral filter, when your change cannot touch the app, saying so).
3. `py scripts/todo-graph.py validate` shows 0 fatal, and `py scripts/todo-graph.py plan --check` is current (run `plan --sync` after any TODO edit).
4. Anything that changes Notepad behavior cites the Windows 11 Notepad capture it matches (`resources/baseline/`); anything that changes the agent protocol cites the [Agent Client Protocol](https://agentclientprotocol.com/get-started/agents) text it follows.

The pre-commit hook runs the validator on every commit; never bypass it with `--no-verify`.

## House rules

- User data first: file writes are atomic, and nothing a user typed is ever discarded silently.
- No credentials in files, arguments, logs, or pull requests.
- Prose uses no em dashes and one line per paragraph in Markdown.
- Working rules for automated contributors are in [AGENTS.md](AGENTS.md).
