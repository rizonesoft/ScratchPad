# TODO System -- Format Spec

The `todo/` tree is the live execution plan for the ScratchPad build. Markdown is canonical; `scripts/todo-graph.py` reads it, checks it and derives `implementation-plan.md` from it.

One rule governs everything below: **a TODO section must be implementable by someone with zero conversation context.** A fresh session starts with none. If a section only makes sense to someone who was in the room, it is not done.

Simplified 2026-10-18 (`docs/specs/2026-10-18-simplify-process-design.md`): review governance, risk acceptances, night debt and grandfathering were removed. Older stamps and `docs/reviews/` keep their historical lines; the tool ignores them.

## Tree shape

```
todo/
├── README.md               this file
├── TODO-00-INDEX.md        root index -- domain order + active work
├── implementation-plan.md  phase order; boxes derived by plan --sync
├── 00-workspace/
│   ├── INDEX.md            domain index -- every TODO in this domain
│   └── TODO-01-<short-name>.md
├── 01-notepad-core/
└── …
```

Domains are flat-numbered; a new domain appends after the last one, because `DNN` cross-references encode the numbers. Files are `TODO-NN-short-name.md`, where `NN` is the next free number in that domain and is never reused. A file holds at most 55 sections; past that, start a new file in the same domain split by subject.

## Frontmatter

```yaml
---
schema_version: 1
id: winui-app-spine                # stable, kebab-case, globally unique, survives renames
domain: 01-notepad-core            # the containing directory
status: draft                      # draft | active | blocked | done | superseded
title: "TODO-01 -- WinUI 3 App Spine"
depends_on: ["repo-and-toolchain"] # optional -- TODO ids that must fully ship first
track: N1                          # optional
superseded_by: other-todo-id       # required with status: superseded
---
```

`id`: lowercase `a-z0-9-`, 2-60 chars, starts with a letter. Cross-references resolve against it, so it never changes once anything points at it.

## File anatomy

```markdown
# TODO-01 -- WinUI 3 App Spine

> **Goal:** One paragraph. What is true when this file is finished.

> [!IMPORTANT]
> **Current state:** What exists right now, with real paths and real gaps.

## Inputs

- [`resources/baseline/notepad-parity.md`](…) -- what this TODO consumes from it
- -> XREF: D02 T01 §4 -- consumes the buffer this file builds

## Outcome

- Observable end states, not activities.

## Implementation Order

| Order | Section | Deliverable                       | Depends On | Status |
| :---: | :-----: | --------------------------------- | ---------- | :----: |
|   1   |   §1    | Solution + WinUI 3 project wired  | --         |  [x]   |
|   2   |   §2    | Single-window shell with menu bar | §1         |  [ ]   |

---

## 1. Solution Scaffold

One paragraph of context: why this section exists and what it must not break.

- [x] `src/ScratchPad.slnx` builds clean with the pinned SDK. Done when: a clean checkout builds with one command.
- [x] Commit: `"notepad-core: scaffold solution + test wiring"`

**Test checkpoint:** `dotnet test` exits 0 with at least one passing test.

> **Verified:** 2026-09-14 | §1 | dotnet test 3 passed, zero warnings
> **Review:** Opus, approve after 1 fix

## 2. …

## Verification

- [ ] File-level checks run at closeout (full focus-free suite, captures).
```

Sections run `## 1.` to `## N.` in order, with `## Verification` last.

**The Implementation Order table is the dependency graph.** Every `## N.` section has exactly one row and every row has a section. `Depends On` uses the notation below; `--` means none. `Status` flips to `[x]` only when a `Verified:` stamp covers the section.

## Cross-reference notation

| Form         | Means                                 | Example      |
| ------------ | ------------------------------------- | ------------ |
| `§N`         | Section N of this same file           | `§3`         |
| `TNN §N`     | TODO-NN in the same domain, section N | `T02 §1`     |
| `DNN TNN §N` | Domain NN, TODO-NN, section N         | `D03 T01 §4` |

Never a cross-TODO reference without a section. **Cross-references are bidirectional:** if this file has `-> XREF: D03 T01 §4`, that file points back at this one, or `validate` fails.

## Section anatomy

- **Context paragraph:** why the section exists and what it must not break.
- **Checklist:** one buildable step per item, each naming a path in backticks and a `Done when:` end state; UI and write items also name the cheaper substitute the checkpoint must catch. The last item is `Commit:`. Keep it under about 30 items; split where the work genuinely divides (another subsystem, a dependency boundary).
- **`**Test checkpoint:**`:** a command or drive that can fail. Required.
- **UI sections** also carry `**Fidelity:**` (the Notepad surface and its capture under `resources/baseline/`, or `new build, no baseline`), `**Job:**` (what the user can do; who reads the write), `**Treatment:**` (the asked treatment and the substitute that fails it) and `**Chrome:**` (the shared styles to consume). A surface section accounts for every control on its counterpart: working, or deferred to a named section.
- **`**Needs:** Windows host (build/test)`** when the section needs a live Windows host (closed list in `NEEDS_ALLOWED`).
- **`**Requires:** <values> -- <reason>`** when it needs an environment capability: `display-session` (an interactive Windows session; detected) or `operator` (a person at the keyboard; only `--context operator` declares it). `query ready` lists such rows as runnable elsewhere when the context lacks them. `**Manual:** operator-only -- <reason>` travels with `**Requires:** operator`.
- **Do not rewrite a `[x]` section's checklist.** New work on shipped code is a new section.

## Stamps

`> **Started:** <UTC instant>` goes under the section heading when work begins and is never overwritten on resume. The rest are written at the end of the section they cover, after the test checkpoint:

```
> **Verified:** 2026-10-18 | §3 | dotnet test --filter TabModel 12 passed, golden set 41 passed
> **Review:** Opus, approve after 2 fixes
> **Deferred:** session restore across restarts -> XREF: D01 T01 §6 (item: "Restore open tabs")
```

- `Verified:` is `<YYYY-MM-DD> | <coverage> | <evidence>`: a real date, `§N` or `§N-§M` (comma-separated, at most 65 sections), and real command output. A malformed line is refused by `validate`. Re-verification replaces the line in place.
- `Review:` names the reviewer and the outcome in one line.
- If a section cannot run its own Primary or Interactive tests on this host, its `Verified:` evidence says so; the phase-close foreground run covers them (`docs/testing.md`).

## Deferrals

A deferral hands work to another section: `> **Deferred:** <what> -> XREF: <owner ref> (item: "<owner checklist item>")`. `validate` fails when the owner does not resolve, when the named item does not exist, and when the owner has shipped the work but the line still says `Deferred:`. The section that ships the work closes it in place:

```
> **Resolved:** 2026-10-18 | <the original text> -> XREF: D01 T01 §6 (item: "…") | closed by `ac90135`
```

`query deferred` lists open and resolved deferrals.

## Moved sections

A section whose open work is done outside this tree carries `> **Moved:** <date> to <path/to/file.md> (<why>)` under its heading. The row stays `[ ]` and the references stay valid; `query ready` and `blocked` skip it, a dependency on it counts as met, `resolve` exits 5, and `plan --sync` replaces its plan row with a `> **Moved:**` line. The named file must exist.

## Tooling

```bash
python3 scripts/todo-graph.py validate             # integrity: exit 1 on any problem
python3 scripts/todo-graph.py query ready          # dependency-met sections, split by runnable context
python3 scripts/todo-graph.py query blocked        # sections waiting, and on what
python3 scripts/todo-graph.py query stats          # tree totals
python3 scripts/todo-graph.py query deferred       # open and resolved deferrals
python3 scripts/todo-graph.py plan --sync          # rewrite plan boxes, Items counts, Progress line
python3 scripts/todo-graph.py plan --check         # fail if the plan is stale (CI)
python3 scripts/todo-graph.py resolve 'D03 T01 §3' # any pasted ref -> file, state, unmet deps
python3 scripts/todo-graph.py self-test            # the tool's own fixtures
```

`resolve` takes a `DNN TNN §N` reference, a `<path> §N` pair, or a whole row pasted from the plan. Exit codes: `0` ready, `1` unknown, `2` no reference, `3` already `[x]`, `4` unmet dependencies, `5` moved.

`validate` checks: frontmatter fields, unique ids, rows and sections one to one, a test checkpoint and checklist per section, `[x]` only under a covering `Verified:` stamp, no unticked work left in a shipped section, dependencies that resolve without cycles, bidirectional XREFs, the `Needs`/`Requires`/`Manual` vocabularies, Moved targets, the deferral rules, INDEX listings and the 55-section cap.

## Skills

| Skill                  | Use                                                                    |
| ---------------------- | ---------------------------------------------------------------------- |
| `add-todo`             | **Front door** for new work: find its home, add a section or a file    |
| `process-todo-section` | Build, test, review, stamp and commit exactly one section              |
| `process-phase`        | Run a phase (or the plan) section by section; close finished files     |
| `groom-plan`           | Sequence check, drift sweep and gap scan, without shipping anything    |
