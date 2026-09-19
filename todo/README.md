# TODO System -- Format Spec

The `todo/` tree is the live execution plan for the ScratchPad build. Markdown is canonical; the graph cache is a derived read-only projection rebuilt by `scripts/todo-graph.py`.

One rule governs everything below: **a TODO section must be implementable by someone with zero conversation context.** A fresh session starts with none, and a session that hits the usage limit resumes cold. If a section only makes sense to someone who was in the room, it is not done.

This system is a port of the JMR Online TODO system. Its history comments name JMR sections (`D00 T01 §21` and the like); those are provenance for why a rule exists, not live references in this repo.

## Tree shape

```
todo/
├── README.md               this file
├── TODO-00-INDEX.md        root index -- domain order + active work
├── 00-workspace/
│   ├── INDEX.md            domain index -- every TODO in this domain
│   ├── TODO-01-<short-name>.md
│   └── TODO-02-<short-name>.md
├── 01-notepad-core/
└── …
```

Domains are flat-numbered and ordered by allocation sequence. Each maps to a build area; the mapping lives in `TODO-00-INDEX.md` and in each domain's `INDEX.md`. Numbers are stable addresses: a new domain appends after the last one, because `DNN` cross-references encode them.

**Naming:** `TODO-NN-short-name.md`, where `NN` is the next free number *within that domain*. Numbers are local to the domain and never reused. Renaming a file is safe: the stable `id` in frontmatter is what cross-references resolve against.

## Frontmatter

Every TODO file opens with YAML frontmatter. Five required fields, four optional. That is the whole schema: resist adding more.

```yaml
---
schema_version: 1
id: winui-app-spine                # stable, kebab-case, globally unique, survives renames
domain: 01-notepad-core            # must match the containing directory
status: draft                      # draft | active | blocked | done | superseded
title: "TODO-01 -- WinUI 3 App Spine"
depends_on: ["repo-and-toolchain"] # optional -- other TODO ids that must ship first
frozen: true                       # optional -- touches parity-frozen behavior
track: N1                          # optional -- build-area reference
superseded_by: other-todo-id       # optional -- set with status: superseded
---
```

`id` rules: lowercase `a-z0-9-`, 2-60 chars, starts with a letter, no trailing dash. It is the key every cross-reference and the graph cache resolve against, so it must not change once other files point at it.

## File anatomy

```markdown
---
(frontmatter)
---

# TODO-01 -- WinUI 3 App Spine

> **Goal:** One paragraph. What is true when this file is finished, in plain terms.

## Current state

> [!IMPORTANT]
> **Current state:** What exists RIGHT NOW, before this TODO runs. Without this the implementer has to grep the repo to find the starting line. Name real files and real gaps. The `## Current state` heading is optional and exists for addressability: sections that must cite the block (D00 T01 §26) name the heading, and files that need no citation keep the unheaded shape.

## Inputs

- [`resources/baseline/notepad-parity.md`](…) -- the parity notes this TODO executes
- [`src/Notepad/App.xaml.cs`](…) -- exists; §2 extends it
- -> XREF: [`02-editor/TODO-01 §4`](…) -- consumes the buffer this section builds

## Outcome

- Bullet list. Each bullet is an observable end state, not an activity.
- "Staff open a tab, type, and save with no data loss" -- good.
- "Implement the editor" -- bad.

**Adjacency:** list=applicable @ D01 T01 §6; document=not-applicable (no printed output in this file); settings=applicable @ D01 T02 §1; reporting=not-applicable (no reports in a text editor); notifications=not-applicable (no notifications in this file); permissions=not-applicable (single-user desktop app, no roles); audit=not-applicable (no audit trail in this file); exchange=applicable @ D01 T01 §5; reverse=applicable @ D02 T01 §3

## Implementation Order

| Order | Section | Deliverable                              | Depends On   | Status |
| :---: | :-----: | ---------------------------------------- | ------------ | :----: |
|   1   |   §1    | Solution + WinUI 3 project + tests wired | --           |  [x]   |
|   2   |   §2    | Single-window shell with menu bar        | §1           |  [ ]   |
|   3   |   §3    | Tab model with dirty tracking            | §1           |  [ ]   |
|   4   |   §4    | File open and save with encoding detect  | §2, §3       |  [ ]   |

---

## 1. Solution Scaffold

One paragraph of context: why this section exists and what it must not break.

- [ ] `src/ScratchPad.slnx` builds clean with the pinned .NET SDK. Done when: a clean checkout builds with one command and the smoke test passes. Cheaper substitute: a solution that builds only on the author's machine.
- [ ] Another concrete item. Max 30 per section. See Work items below.
- [ ] Commit: `"notepad-core: scaffold solution + test wiring"`

**Test checkpoint:** `dotnet test` exits 0 with at least one passing test; the build reports zero warnings at the configured level.

> **Verified:** 2026-09-14 | §1 | dotnet test 3 passed · zero warnings · build `Debug/x64`

## 2. …

## Verification

- [ ] `dotnet test` -- full suite green
- [ ] Build warnings clean at the configured level (warnings as errors, analyzers run)
- [ ] Static analysis clean at the configured level
- [ ] Installed MSIX smoke-tested on a clean Windows 11 machine
```

### Sections appear in numerical order, and `## Verification` comes last

`## 1.` through `## N.` run in order down the file, with `## Verification` after all of them. New sections go in numerical position, not appended after `## Verification`: appending is what strands a section where no top-to-bottom reader finds it. The validator does not check this yet, so check it by eye when you add a section.

### The Implementation Order table IS the dependency graph

Every `## N.` body section has exactly one table row, and every row has exactly one body section. The graph script enforces both directions. `Depends On` uses the cross-reference notation below; `--` means no dependency.

`Status` is the section's own completion state and flips to `[x]` **only** when a `Verified:` stamp covering that section exists. The two are checked together.

## Cross-reference notation

| Form         | Means                                 | Example      |
| ------------ | ------------------------------------- | ------------ |
| `§N`         | Section N of this same file           | `§3`         |
| `TNN §N`     | TODO-NN in the same domain, section N | `T02 §1`     |
| `DNN TNN §N` | Domain NN, TODO-NN, section N         | `D03 T01 §4` |

Never a bare number, and never a cross-TODO reference without a section. `D03 T01` alone is not a dependency: it is a vague gesture at one.

**Cross-references are bidirectional.** If this file's Inputs point at `D03 T01 §4`, then `03-acp-client/TODO-01.md` must point back at this file. One-sided XREFs are broken XREFs, and the validator flags them FATAL.

## Stamps

A stamp is a blockquote recording verified work, written **at the end of the section it covers**: after the test checkpoint, with that section's deferrals beneath it. It is the section's conclusion: you read what was asked, then what was actually proven.

```
## 3. Tab Model

One paragraph of context, then the checklist.

**Test checkpoint:** …

> **Verified:** 2026-09-14 | §3 | dotnet test TabModelTest 12 passed · zero warnings
> **Deferred:** session restore across restarts -> XREF: D01 T01 §6 -- needs the settings store first
> **Review:** round 1, fingerprint `a3f91c2e5b04` -- `adversarial` approve · `consistency` approve · `integration` needs-attention (1). Raw findings: docs/reviews/01-notepad-core/D01-T01-s3.md
> **Plan review:** GPT high, no findings (run 20260914-D01-T01-S3-gpt)
> **CRUD:** applicable | TabModelTest + UI smoke: open, edit, save, close, readback byte-identical
> **Implementer:** assistant name (model-id)
```

Alternative markers, one per stamp (the last marker line governs, so these never stack):

```md
> **Plan review:** GPT high, filed D00 T01 §16 (run 20260918-D00-T01-S16-gpt)
> **Plan review:** GPT outage then Opus auth failure, outage: both rungs (owner ann, due 2026-09-25)
> **Plan review:** GPT high, filed D00 T01 §16 (run 20260918-D00-T01-S16-gpt-r2, supersedes 20260918-D00-T01-S16-gpt)
> **Plan review:** GPT high, partial: opus rung, filed D00 T01 §16 (run 20260918-D00-T01-S16-gpt)
```

- `Verified:` -- date, sections covered, and the *evidence*: real command output, not "tests pass".
- `Deferred:` -- one line per deferral, each naming a concrete owner via XREF. A deferral without an owner is an abandonment.
- `Review:` -- the independent review's cost and outcome: rounds, each lens's verdict with its finding count, then a link to the raw findings under `docs/reviews/`. A `Review:` line names its round and its candidate fingerprint, so a stale record cannot satisfy a freshness check for a different candidate.
- `Plan review:` -- the second-family round's completion marker: which family ran it and the filings it produced, `no findings`, `outage: <rung> (owner <name>, due <YYYY-MM-DD>)` when both runners failed, `retry-owed (owner <name>, due <YYYY-MM-DD>)` on a same-family fallback run, or `partial: <rung>` when one rung failed and the other's findings stand (filings beside `partial:` are the survivor's; the failed rung is `gpt rung` or `opus rung`: a fallback survivor owes `retry-owed (owner, due)`, a primary survivor carries no retry and no accountability fields). Lineage: every marker over a review record carries `(run <YYYYMMDD-DNN-TNN-SN-family[-rN]>)` minted by the `run-id` subcommand, the run's date prefix is its timestamp; within one date base the bare base is run 1 and `-rN` is run N for N >= 2 (numbering restarts per day, the date keeps runs distinct) (`-r1` is run 1's synonym and reads as the base in every comparison, `-r0` is outside the shape); genesis is a singleton marker (run, no supersedes), and a rerun marker chains with `supersedes <prior-run>` or with `follows-outage` when the immediately preceding marker is an outage marker; runs never repeat within a section and the last run is one the manifest carries. A rerun opens a new `Plan review` record (rows number past the file max across records). Grammar: the last marker line governs; `no findings` never sits beside filings; `outage:` never sits beside filings, `no findings`, `retry-owed`, or `partial:`; `partial:` composes with `retry-owed` exactly when the survivor is the fallback. Counts read in accepted findings (triaged ledger rows) versus implementation items (checklist lines); a merge states both numbers. Required on stamps dated after 2026-09-18; earlier stamps predate the rule.
- `Reopened:` -- `<YYYY-MM-DD> | <finding ref> | <reason>`, naming the audit locus whose finding voids the stamp. A reopened section reads as unverified everywhere downstream: its row must be `[ ]` and its stamped dependents park until it re-stamps.
- `Retired:` -- `<YYYY-MM-DD> | <section ref> | <reason>`, migrating a grandfathered stamp without asserting a review that never ran. Validator-silent prose by design (no validator class reads it, so it owns no rule-table row); plan-health drains stamps carrying a well-formed note (real date, ref naming the section, non-empty reason) out of grandfathered, and malformed notes read as absent so the stamp stays listed.
- `CRUD:` -- behavioral evidence for the section: the write path exercised and read back, not just unit-tested. Either `applicable | <what ran and what it proved>` or `not applicable (<reason>)`. A page with a `**Job:**` cannot claim not applicable.
- `Started:` -- optional UTC instant written when implementation starts. Do not overwrite on resume.
- `Duration:` -- optional minutes or instant range from `Started:` to stamp (implement, review, and stamp): either integer minutes (`7`, `45m`) or `<start> to <end>` Zulu instants (`2026-09-18T14:54:33Z to 2026-09-18T16:35:19Z`). The range end orders clearance: when both reviews carry ends the target must complete strictly after the finding's review, else day stamps rule and same-day fails closed.
- Clearance tokens -- a section clearing a filed critical names `fix <sha>` (or `fix <base>..<tip>` for a multi-commit loop, base excluded) and `proof <finding-id> <path>[::<test>]` in its own text; the query proves the fix against git and the proof against the fix tree, and a clearance missing either stays listed.
- `Implementer:` -- optional `Name (model-id)` recording who built the section.
- `Resolved:` -- a deferral that has been closed. Replaces the `Deferred:` marker **in place**, keeping the original text and XREF and adding the date and what closed it. Closure is a state change, not a deletion: what was owed, and who paid it, both stay on the record.

### A deferral cannot be left to rot

A deferral hands work to another section, and the parser resolves the owner and notices when the owner ships. Four rules close the loop, and the important one is **fatal**:

| Condition                                                                                                   | Severity    |
| ----------------------------------------------------------------------------------------------------------- | ----------- |
| The `-> XREF:` owner does not resolve to a real section                                                     | `FATAL`     |
| The `(item: "…")` names a checklist item the owner does not have                                            | `FATAL`     |
| **The owner has shipped it -- item `[x]`, or the section's row `[x]` -- and the line still says `Deferred:`** | **`FATAL`** |
| Marked `Resolved:` while the owner has *not* shipped it                                                     | `WARN`      |
| No `-> XREF:` owner at all                                                                                  | `FATAL`     |

The stale case is fatal because advisory is what lets rot happen. The moment a section ships, any deferral waiting on it turns the build red until someone closes it: so **the section that resolves a deferral is the section that closes it**, which is also the only moment anyone has the information to write the closure line.

A deferral whose owner has *not* shipped is not stale; it is pending, and it stays open silently. Name the `(item: "…")` whenever one exists: without it, closure can only be detected when the whole target section completes, which is much later and much coarser.

Write a closure as:

```
> **Resolved:** 2026-09-14 | <the original text> -> XREF: D01 T01 §6 (item: "…") | closed by `ac90135`
```

`query deferred` lists open and resolved separately. Staleness is not reported there, because a stale deferral cannot reach that list: `validate` fails first.

**Two kinds of rot the validator cannot see**, both owned by `process-todo-section`'s fact-check: a deferral whose *description* has drifted while its owner is still legitimately open, and one whose work was quietly done by someone who never ticked the owning box. Neither is stale by the rule above, so both need a human reading the line against today's repository. Closing the second means ticking the owner's item too; leaving it unticked moves the rot up a level rather than removing it.

**The stamp lives with its section, not in a block at the top of the file.** The stamp belongs where the question gets asked: at the end of the section it covers.

The parser finds stamps anywhere in the file and maps each to its section by the `§N` in the body, so the `§N` stays in the text even though the heading above it already says so. That redundancy is what lets one stamp cover a range (`§1-§3`) and what keeps the format position-independent.

For the whole file at a glance, read the Implementation Order table: `[x]` cannot exist without a stamp covering it, and the validator makes that a FATAL.

Re-verification replaces the stamp line in place. Never accumulate duplicates.

## Frozen behavior

Some behaviors are parity-critical: they must keep computing exactly what Windows 11 Notepad computes. Any TODO touching them sets `frozen: true` in frontmatter, and every section that changes a frozen behavior carries a freeze check alongside its test checkpoint:

```
**Freeze check:** Round-trip fixtures for CRLF/LF detection, UTF-8/UTF-16 BOM handling, and status-bar line/column math reproduce Windows 11 Notepad byte for byte. Fixture source: resources/baseline/parity-fixtures/.
```

Restructuring frozen code is allowed. Changing what it *computes* requires operator approval logged in the Freeze Register: the TODO records the approval, it does not grant it.

## UI fidelity

The freeze check has a visual twin. **Every section that builds or changes a user-facing surface carries a `Fidelity:` block** naming the Windows 11 Notepad surface it must match and the captured baseline artifact(s) under `resources/baseline/`:

```
**Fidelity:** Notepad main window (tab bar, editor, status bar) -- resources/baseline/main-window/. Placement, control order, and terminology match the capture; deviations only from the approved list.
```

**The same sections carry the documentation duty:** shipping or changing a user-facing surface updates `docs/user-guide/<surface-slug>.md` in the same commit; review checks it before stamping. `process-todo-section` refuses to build a surface whose named artifact does not exist: that means the capture has not shipped for it, and building from a one-line description freezes our guess instead of the real thing. `review-todo-section` compares the rendered surface against the artifact before stamping. A genuinely new surface with no counterpart in Windows 11 Notepad (the AI chat panel is the obvious one) says so explicitly: `**Fidelity:** new build, no baseline` -- so silence is never ambiguous.

### Surface completeness: what a UI section owes beyond looking right

A `Fidelity:` block governs how a surface **looks and is laid out**. It says nothing about whether the surface **works**. So a section that builds a user-facing surface owes an account of **every control, menu item, dialog, and permission** on the counterpart, each resolved to one of two states:

- **Working** -- proven on the rendered surface, with real data. For anything that lists data, the evidence is the **content beside the counterpart's content**.
- **Deferred to a named section** -- and the name must resolve. `python3 scripts/todo-graph.py resolve '<ref>'` must not exit 1 or 2. **A control disabled with a reason that names no section is not deferred, it is missing.**

Deferral is legitimate and expected. What is not legitimate is deferral that names nobody, because it is indistinguishable from an oversight. `review-todo-section` refuses the stamp for an unaccounted control, and `process-todo-section` requires the decision at build time so it is not discovered at review.

### The second layer the runner reads

Every section that builds or changes a user-facing surface carries three blocks next to `Fidelity:`:

```
**Job:** <the user> can <the verb this surface exists for>. Consumer: <what reads the write, or "none: this surface is the consumer">.
**Treatment:** <the asked treatment, named so a substitute can fail>. Cheaper substitute that fails the checkpoint: <the wrong thing>.
**Chrome:** consume <named shared styles/controls>. Do not invent a second <pattern>.
```

A section whose Fidelity line says the work has no surface of its own ("no page of its own", "not a page", "the transport is not a page") skips these three.

A section that cannot run without a live host the plan cannot otherwise see carries one more line, anywhere in its body:

```
**Needs:** Windows host (build/test)
```

The value comes from a closed list (`todo-graph.py` `NEEDS_ALLOWED`; `validate` refuses any other). `resolve` prints it as `needs`, so a future runner can skip the row while no Windows host is reachable and take the next host-free row instead.

A section that cannot run without an environment capability the plan cannot otherwise see carries one more line, anywhere in its body:

`**Requires:** display-session -- convicted by <measurement pointer>`

Values are comma-separated closed vocabulary (`todo-graph.py` `REQUIRES_ALLOWED`); the reason after ` -- ` is required and cites the measurement that convicted the section. `validate` refuses an unknown value (`requires-unknown`) and a mark without its reason (`requires-no-reason`), both FATAL. `query ready` splits dependency-ready rows into runnable-now (requirements met by the runner's context) versus runnable-elsewhere (requirements named per row); `resolve` prints the line with the local verdict. The runner's local context is detected (`display-session` holds on Windows with `SESSIONNAME` naming an interactive session -- never session 0 (`Services`), never elsewhere); `query ready --context` evaluates a declared set instead, for planning. Shipped sections are grandfathered: no retroactive marking, and a mark added later needs its reason like any other. `Needs:` (host) keeps its own closed list and its pre-start host check; the two lines compose, never merge.

| Value | Means | Detected how (local context) |
| ----- | ----- | ---------------------------- |
| `display-session` | A Windows interactive session able to render WinUI: eyeball probes, palette sampling, real pixels instead of black frames | `sys.platform == "win32"` with `SESSIONNAME` naming an interactive session (not `Services`, never empty); every other context evaluates False |

A section whose open work is worked OUTSIDE this tree carries a `Moved:` marker under its heading:

```
> **Moved:** 2026-09-14 to docs/plans/<plan>.md (operator instruction); worked there by its named owner.
```

The section keeps its Implementation Order row (`[ ]`, never ticked without a stamp) and every cross-reference, so addresses stay stable and `validate`'s reciprocity still holds. What changes is what the graph does with it: `query ready` and `query blocked` skip it, `query stats` counts it on its own `moved` line, `resolve` prints a `moved` line and exits 5, a dependency ON a moved section counts as met (section edges and whole-TODO edges alike: its row can never flip here, so a dependent waiting on it would wait forever), and `plan --sync` replaces its plan row with one `> **Moved:** \`DNN TNN §N\` -- ...` line at the end of the table the row sat in, which `plan --check` requires and the progress arithmetic never counts. The body's first `path/to/file.md` must exist, or `validate` is FATAL (`moved-target-missing`). Its remaining open items are struck in place with the same pointer so nobody reads them as work owed here.

The Job line is what completion measures. The Treatment line is what a cheaper substitute fails against. The Chrome line is what shared-style review gates. Naming them on the section is how the runner does not have to reconstruct them from a Goal paragraph.

## Section sizing

Max 30 checklist items per section. The validator warns above that; it is a ceiling, not a target.

Size a section by what holds together, not by a number. Two forces pull in opposite directions and both are real:

- **Too large** exhausts a fresh worker's context halfway through, and gives review more surface than it can cover well in one pass.
- **Too small** multiplies cost. A section is the unit the review contract prices, so three thin sections cost three review cycles where one coherent section costs one.

Split where the work genuinely divides: a different subsystem, a dependency boundary, a protocol layer separate from the UI that consumes it. Split at **authoring** time, not during implementation: splitting mid-flight costs a wasted context.

### Feature adjacency: the surfaces a domain owes beyond its record

Section sizing above decides how work is split. This decides whether the work is *all there*, and it is answered **before the Implementation Order table is final**, not at review.

So a TODO file's `## Outcome` carries an **Adjacency** line naming which of these apply to the domain, and which do not, with a one-line reason:

- **List and filters** (`list`) -- can somebody find one of these records without knowing its identifier?
- **Document or print** (`document`) -- what does a user carry, send, or file?
- **Settings with a named consumer** (`settings`) -- every tunable value. A value that needs a reinstall to change is a defect, and a setting nothing reads is worse than none.
- **Reporting** (`reporting`) -- summaries and exports over the domain's own data.
- **Lifecycle notifications** (`notifications`) -- registered with recipient rules, not an address list.
- **Permissions, exercised on refusal** (`permissions`) -- seeded both ways. A hidden button is not a refusal.
- **Audit and history** (`audit`) -- who changed what, with the reason where one is required.
- **Import or export** (`exchange`) -- wherever the counterpart has one. Through the shared path, scoped and gated.
- **The reverse of every create** (`reverse`) -- cancel, reopen, delete, undo. An irreversible action nobody can undo is a support call.

**"Not applicable" is a declaration, not silence.** A transport has no list; both say so in one line. The check is advisory (`query adjacency`), because the tool cannot know which kinds a domain genuinely lacks: but a file that stays silent and a file that decided are not the same thing, and only one of them is a plan.

**Executable declaration:** place one `**Adjacency:**` line inside `## Outcome`. Write every key exactly once, separated by semicolons: `key=applicable`, `key=applicable @ DNN TNN §N` for an explicit cross-domain owner, or `key=not-applicable (source-backed reason)`. A narrow non-feature file may instead declare `all=not-applicable (reason covering its entire scope)`. It cannot mix the blanket form with individual entries. Preserve substantive decisions in an `**Adjacency rationale:**` paragraph; that prose is evidence for human review, not a second machine declaration. A missing/unknown/duplicate key, missing NA reason or declaration outside Outcome remains visible and prevents explicit closeout.

`python3 scripts/todo-graph.py query adjacency --json` derives owner candidates from positive Job, checklist and Build-order clauses, retaining source anchors. A reference must uniquely identify a real, non-Moved section with the claimed capability. These semantic matches require source review and do not prove runtime completeness.

Ordinary query and `validate` print `WARN [adjacency advisory]` without entering the existing structural warning ratchet. Before closing a file, run `python3 scripts/todo-graph.py query adjacency --file 'todo/NN-domain/TODO-NN-name.md' --require-owned`; refuse closure on missing/undeclared/unowned obligations and name the diagnostic.

## Work items: one checkbox is one buildable step

A section that only names an outcome ("build the tab bar") leaves a cold agent to invent the class, the WinUI pattern, the message handling, and the cheaper substitute. That is how a tab bar ships as a combo box, and how a list ships where a write was owed.

Each checklist item except `Commit:` is a **micro-step**. Required on new work:

1. **One action.** One file, class, test, command, or control. If you need "and then" to describe it, it is two items, or one item with numbered sub-steps.
2. **A named path** in backticks (`src/Notepad.Core/TabModel.cs`, `TabBar.xaml`, `dotnet test --filter TabModel`). A verb with no object ("implement tabs") is not an item.
3. **Done when.** The observable end state in the same bullet. Example: "Done when: closing a dirty tab prompts, and Discard closes without writing."
4. **The cheaper substitute** on any UI or write item, so the Test checkpoint can fail on it.
5. **A source cite** when behavior is copied: a capture path, a protocol doc URL, or a Windows behavior note.

Numbered sub-steps (`1.` `2.` `3.`) under an item are the **procedure** for that one checkbox. They are not extra Implementation Order rows and they do not get their own review cycle. Use them when the action has a fixed order (header, then implementation, then test, then wiring).

**Build order** (a numbered list of files above the checklist) is the allowed retrofit on an already-written open section: it directs a cold agent without rewriting item text a deferral may name. Every numbered Build-order stage carries the same two non-negotiable anchors as a new micro-step: at least one intended implementation path, class, component, runnable command, or concrete source/evidence artifact in backticks, plus a literal observable `Done when:` in that stage. Put the cheaper substitute in the relevant UI/write stage. Prefer micro-step items on new work.

Split into a new `## N.` when the work has a different dependency, a different subsystem, or would push the parent past 30 items. **Split into a new FILE at 55 sections**, which `validate` enforces as FATAL: a section number is a permanent address, so a file only ever grows and can never be renumbered to tidy up. Split by subject, and leave every existing section exactly where it is. Do not split a stamped section.

**Do not rewrite a `[x]` section's checklist.** That is the contract the stamp covers. New granularity on shipped work is a new section.

Size still follows **Section sizing** above. Micro-steps are smaller items, not more review cycles.

## Tooling

```bash
python3 scripts/todo-graph.py build      # parse todo/ -> build/todo-cache.json
python3 scripts/todo-graph.py validate   # structural + graph integrity checks
python3 scripts/todo-graph.py query ready        # sections with all deps met, split into runnable-now versus runnable-elsewhere by the runner's context
python3 scripts/todo-graph.py query blocked      # sections waiting on something
python3 scripts/todo-graph.py query stats        # tree health
python3 scripts/todo-graph.py query plan-health  # review-loop governance: --json emits schema plan-health/4 (total sort keys, exits 0); --check/--fail-on gate automation
python3 scripts/todo-graph.py query summary      # operator digest: incomplete runs, blocked clearances, overdue owners, next action, gate verdict (text-only; exits 1 when the gate fails)
python3 scripts/todo-graph.py query run <id>     # one run ID resolves to candidate, scope, findings, lineage, outage, artifacts
python3 scripts/todo-graph.py render             # mermaid dependency graph
python3 scripts/todo-graph.py plan --sync        # re-derive the checkboxes AND re-align every table
python3 scripts/todo-graph.py plan --check       # fail if the boxes are stale (CI runs this)
python3 scripts/todo-graph.py resolve 'D03 T01 §3'   # ref -> file, section, deps, status
```

`resolve` is the front door for the two section skills, and it takes whatever you already had in front of you: a `DNN TNN §N` reference, a `<path> §N` pair, or a row pasted straight out of `implementation-plan.md`, backticks, pipes and all. Its exit code carries the verdict: `3` means the section is already `[x]` (audit stance, not implementation), `4` means a dependency is unmet, `5` means the section moved out of the tree. So

```
process todo section: | [ ] | `D00 T01 §2` | CI on Linux and Windows runners | 6 |
```

is a complete instruction: nobody has to translate domain `00` and TODO `01` into a filename, which is the step that gets done wrong at 3am.

`build/` is gitignored: the cache is always reproducible from the markdown.

[`implementation-plan.md`](./implementation-plan.md) is the second derived artefact, and the only one that is committed: it is prose a person reads, so it cannot live in `build/`. Its boxes are a projection of the Implementation Order tables and **are never ticked by hand**; `plan --check` runs in CI so a stale projection fails the build instead of quietly misinforming whoever reads it next. Run `plan --sync` after any row flips.

### FATAL blocks; WARN is ratcheted

`validate` reports two severities under a **two-layer contract**: a FATAL always exits `1` and is never ackable; a WARN is ratchet-managed, so one already in `todo/.warning-baseline` or the ack ledger exits `0`, while a NEW one prints as `WARN*` and exits `1` until it is fixed or deliberately accepted with `warnings --accept`. "Advisory" therefore describes only warnings that are already baselined or acked, never a new one.

| Severity | Exit code | Meaning |
| -------- | :-------: | ------- |
| `FATAL`  |    `1`    | The graph or the format is broken: a `Depends On` that does not resolve, a section without its Implementation Order row, a row without its section, a one-sided XREF, a deferral with no owner, a `superseded` TODO with no successor, and every other structural class in the per-class table below. Fix it before doing anything else. |
| `WARN`   | see below | Ratchet-managed: a warning already in `todo/.warning-baseline` or the ack ledger exits `0`; a NEW one prints as `WARN*` and exits `1` until fixed or deliberately accepted with `warnings --accept`. |

**CI enforces exactly this contract and nothing more.** The todo workflow runs `validate` on every push touching `todo/`, `scripts/todo-graph.py`, or the workflow itself, so a FATAL (or a NEW warning) fails the build like any other defect.

**The per-class map, mirrored from `SEVERITY_MAP` in `scripts/todo-graph.py`: the self-test compares this table to the map row-for-row, so editing one without the other fails `self-test`.** The rule is push-time actionability: FATAL where the fix is mechanical and the defect is a structural-integrity break; WARN where the fix is a judgement call a red build cannot resolve.

| Class | Severity | Why |
| ----- | -------- | --- |
| `over-section-cap` | FATAL | A TODO file may hold at most **55** sections. Past that the next work opens a NEW file in the same domain, split by subject. Section numbers are permanent addresses, so a file can never be renumbered or made smaller. |
| `duplicate-source-key` | FATAL | Two sections claim the same `-> SOURCE: <key>`. An automated filer stamps what it filed FROM, so a scanner that runs twice a day cannot open a second row for one build failure. |
| `superseded-no-successor` | FATAL | A superseded TODO must name where its work went; mechanical. |
| `filter-overclaim-open` | FATAL | An open checkpoint that cannot detect its promised regression; naming the test files is a two-minute fix. |
| `filter-overclaim-stamped` | WARN | The stamp must not be reopened; the fix-forward channel owns it. |
| `no-commit-item` | FATAL | One section = one commit is the format's core contract. |
| `orphaned-items-shipped` | FATAL | Unticked, unstruck work inside a `[x]` section breaks the shipped claim itself. |
| `fidelity-missing-lines-open` | FATAL | A Fidelity surface with no Job/Treatment/Chrome is unimplementable as a faithful clone. |
| `fidelity-missing-lines-stamped` | WARN | Fix-forward: the gap is real, the stamp stays. |
| `no-checklist-items` | FATAL | An empty section is unimplementable (co-emits `no-commit-item`). |
| `over-30-items` | WARN | Sizing is a judgement call; a red build cannot split a section. |
| `frozen-no-freeze-check` | FATAL | A frozen TODO without its check is a safety-marker mismatch; mechanical either way. |
| `freeze-check-not-frozen` | FATAL | A Freeze check in a TODO whose frontmatter does not say `frozen: true` is the same safety-marker mismatch in the other direction; mechanical fix. |
| `bare-todo-ref` | WARN | Prose legitimately mentions a TODO file without a section. |
| `one-sided-xref` | FATAL | This spec calls it broken; the validator now agrees. |
| `deferral-no-owner` | FATAL | A deferral with no owner is an abandonment. |
| `resolved-owner-unshipped` | WARN | Recording early resolution is evidence, not a defect. |
| `missing-from-index` | FATAL | Two-line mechanical fix; discoverability is structural. |
| `malformed-stamp` | FATAL | A `Verified:` line the parser refused. It reads as evidence while verifying nothing, so it is worse than a missing stamp; the fix is to write the line correctly. |
| `needs-unknown` | FATAL | A `**Needs:**` value outside the closed list in `todo-graph.py` (`NEEDS_ALLOWED`). The list is closed so a misspelt host cannot silently unmark a section that cannot run without it. |
| `moved-target-missing` | FATAL | A `> **Moved:**` marker that names no file, or a file that does not exist. The marker takes the section out of `query ready`, the plan and the progress totals on the strength of that pointer, so a dead pointer would hide work. |
| `pending-control-contract` | FATAL | Reserved: the coming-soon inspector is not ported yet, so this class cannot fire until it lands. |
| `stamp-no-opus-panel` | FATAL | A stamp dated after 2026-09-17 whose findings lack an `Opus panel` section with all four lens verdicts. It reads as reviewed evidence while verifying nothing; stamps on or before 2026-09-17 predate the rule and are grandfathered. The `Review:` line must carry `Raw findings: <path>`; the panel section is a level-2+ heading starting with `Opus panel` (last one wins in multi-round files); each verdict sits on its own `` `lens` verdict `` line opening (after up to 3 spaces) with a Markdown marker (`*`, backtick, `>`, `-`; mid-line mentions never count); fenced code blocks are stripped before the scan, quoted headings are not structure, quoted fences count as fences (closes match the opener's quote depth; an ended quote ends its fence, and a blank line ends the quote), a backtick in a backtick-fence info string is a paragraph, and an unbalanced fence fails naming its opener line. A `GPT panel` section (the fallback when the Opus panel is unreachable) satisfies the rule when it carries all four lens verdicts in the same shape plus a line with the words `Opus outage`; the last panel section of either family governs. Planned `GPT panel` early rounds under an Opus sign-off (the §35 mixed sequence) need no outage note; only a `GPT panel` last section does. |
| `requires-unknown` | FATAL | A `**Requires:**` value outside the closed list in `todo-graph.py` (`REQUIRES_ALLOWED`), or a mark with no values at all. The list is closed so a misspelt capability cannot silently unmark a section. |
| `requires-no-reason` | FATAL | A `**Requires:**` mark without its ` -- ` reason. The citation is what makes the mark auditable: every mark names the measurement that convicted it. |
| `stamp-no-plan-review` | FATAL | A stamp dated after 2026-09-18 that carries no `Plan review:` completion marker, or whose marker breaks the grammar. The second-family round runs after panel-close and its marker rides the stamp commit, naming the filings, `no findings`, `outage: <rung> (owner, due)`, `retry-owed (owner, due)`, or `partial: <rung>` (one rung failed, the other's findings stand); stamps on or before 2026-09-18 predate the rule and are grandfathered, so mechanical enforcement begins 2026-09-19 and landing-day stamps carry the marker voluntarily. The last marker line governs; `no findings` beside filings, and filings, `no findings`, `retry-owed`, or `partial:` beside `outage:`, are FATAL. A `partial:` names its failed rung (`gpt rung` or `opus rung`); a fallback survivor without `retry-owed`, a primary survivor with `retry-owed` or accountability fields, and an unknown rung are FATAL. Every named filing must resolve, and every ledger `filed` row's target must appear in that section's marker, checked per marker with no cross-section dedup (`outage:` markers skip both). |
| `plan-review-malformed` | FATAL | A post-cutoff plan-review record the query cannot parse: a `Plan review` section without its `Manifest:` line or its `Ledger:`/`End of ledger` block, a non-blank line inside the block outside the row shape, a content-illegal row (a `deferred` row without owner, date, and trigger; a `duplicate` row naming no canonical finding; a `filed` row naming no target; an `accepted` critical or major without owner and due, the deferred triple satisfying accountability through its date), or a run-less manifest on a chain that carries runs (run-less chains stay exempt: outage-only records name no run by design). Rows are only rows inside the block; `- [` lines outside it are prose. Pre-cutoff records predate the shapes and are grandfathered. |
| `filed-target-no-backlink` | FATAL | A `filed` ledger row whose finding ID appears nowhere in its target's file (word-bounded). The filing is untraceable from the target side, so remediation cannot be attributed to the finding. Reviews stamped on or before 2026-09-18 predate the back-link requirement and are grandfathered. |
| `stamp-reopened` | FATAL | A `> **Reopened:**` line outside `<YYYY-MM-DD> \| <finding ref> \| <reason>` with a resolvable `§`ref, a reopened section whose Implementation Order row is still `[x]`, or a still-stamped section with a reopened section anywhere in its Depends closure (the cascade is recursive: dependents park until the root re-stamps, bottom-up). A reopen voids the stamp everywhere downstream. |
| `plan-review-duplicate-id` | FATAL | A finding ID appearing twice in one plan-review ledger (case-insensitive), even with identical targets. Multi-target findings ride one row naming every target; split rows are never the honest shape. Reviews stamped on or before 2026-09-18 predate the uniqueness rule and are grandfathered. |
| `plan-review-no-lineage` | FATAL | A `Plan review:` marker over a review record that carries no run ID, carries one outside the `YYYYMMDD-DNN-TNN-SN-family[-rN]` shape (`-r0` and leading-zero suffixes rejected, `-r1` reads as the base in every comparison), reuses a run within its section, appends a rerun marker without `supersedes <prior-run>` (unless the immediately preceding marker is an outage and the rerun carries `follows-outage`), carries a dangling `follows-outage`, names a run no manifest carries, carries `supersedes` on a singleton genesis marker (a first run has no ancestry to name), re-supersedes one predecessor from a later marker, or points a non-last edge at a run outside its past. Precedence without lineage rests on line position alone. Outage markers and markers over record-less findings are exempt. Stamps dated on or before 2026-09-18 skip lineage entirely; the rule postdates them. |
| `ledger-history-violation` | FATAL | A ledger row whose disposition moved the forbidden way against the committed record (`filed`, `rejected`, and `duplicate` are terminal; `deferred` may only file; `accepted` may move anywhere), or a row that vanished between HEAD and the tree. Later evidence amends via a new row naming the superseded ID, never by rewriting the old row. Uncommitted findings skip: without history nothing is provable. |
| `provenance-malformed` | FATAL | A post-cutoff findings file with no `Provenance:` line, or a provenance line outside the field shape (candidate, command, exit, tool, digest, path, run), without a shaped run ID, with a candidate naming no git object, with a path naming no file under the repo root, or with a run no marker of its section carries. Unresolvable git skips the candidate leg (rule-22 precedent). The digest stays attested (presence plus shape, never re-verified). Fenced `Provenance:` examples strip before the scan. Pre-cutoff records predate the mandate and are grandfathered. |
| `ledger-supersession-broken` | FATAL | A ledger row whose `supersedes <finding-id>` link names no row of its own block, crosses review namespaces, closes a cycle (self-links included), or re-supersedes an already-claimed target (one target, one successor: the second claim breaks the single-current-head read). Only exactly ID-shaped tokens link, so prose carrying the word is never a link. plan-health reads the un-superseded head of each chain as current. No date scope: old ledgers deserve the same protection. |
| `risk-acceptance-malformed` | FATAL | A `Risk accepted:` line outside the record shape (target, approver, action owner, record date, expiry, review date, evidence commit, optional supersedes link, rationale), with a target that names no finding ID, run ID, or `outage <rung> <date>`, or expiring before it is recorded, or carrying a review date outside its record-expiry window. Fenced examples strip before the scan. Pre-cutoff records predate the mandate and are grandfathered. Coverage needs the record date on or before today and today on or before expiry; an acceptance in a findings file attached only to pre-cutoff stamps is never validated and covers nothing. |
| `risk-acceptance-silent-edit` | FATAL | A `Risk accepted:` record edited or deleted against the committed history, or a `supersedes <date>` link naming no record of the same target. Append-only is absolute: the predecessor stays byte-identical next to its successor, and a chain never licenses a rewrite. Amendments ride new records only, validated like ledger history; uncommitted findings skip. |
| `risk-acceptance-chain-broken` | FATAL | A `Risk accepted:` record that links to itself, sits in a supersedes cycle, claims one predecessor twice (one target, one successor), shares its target and record date with a twin (one record per target and date), or forks its target with a second unlinked record (one head per target: supersede or withdraw the twin). Mirrors the ledger supersession rule; needs no history, so uncommitted findings still fail. |

Treat a warning as a decision to make rather than noise to clear. The tree currently sits at zero FATAL and zero non-baselined warnings, and it is worth keeping there.

## Skills

| Skill                   | Use                                                                              |
| ----------------------- | -------------------------------------------------------------------------------- |
| `add-todo`              | **Front door.** Route new work to the right domain, file, and section            |
| `create-todo`           | Author a whole new TODO file, wire XREFs, update indexes                         |
| `groom-plan`            | Harden the tree for a weaker executor: sequence, drift, gaps, complete features  |
| `process-todo-section`  | **Fact-check the plan, correct what has drifted, then ship exactly one section** |
| `review-todo-section`   | Quality gate after implementation; writes the stamp                              |
| `process-todo-file`     | Loose-end sweep and closure when every section is `[x]`                          |
| `process-phase`         | Attended phase runner: repair + gap-audit the phase, then ship it to 100%        |
| `process-plan`          | Front door for `implementation-plan.md`; chains ready phases                     |

When something needs doing, start at `add-todo`: it decides whether the work belongs in an existing section, needs a new one, warrants a whole new file (delegating to `create-todo`), or is already covered. Reaching for `create-todo` directly tends to produce a second TODO over an existing one.
