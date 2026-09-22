---
name: process-todo-section
description: Grok campaign runner. Process exactly one TODO section end to end. Resolve it, validate and fact-check the plan against the repository, correct every drifted claim, build it, run the gates, hand to review, and commit. Use whenever asked to process, implement, ship, continue, or finish a TODO section.
---

# Process TODO Section

Grok runner. Do not open `.claude/skills/process-todo-section`. Host rules: `.grok/rules/campaign-runner.md`. Gates: `.grok/skills/process-todo-section/gates.md`.

One section. One commit. The section is the contract, and a contract is checked before it is signed.

Processing a section is two jobs, in order. First establish that the plan is sound: internally consistent, still true of the code, buildable as written, and verifiable when built. Then implement it. A section written weeks ago against a codebase that has since moved is a plan with a bug in it, and building it faithfully ships that bug with full ceremony.

So: do not improvise around the plan, and do not implement a plan you have found to be wrong. Correct it in the file, visibly, then build the corrected version.

## Use this skill when

- The user names a section in any form: a path and a section, a `DNN TNN §N` reference, or a row pasted straight out of `todo/implementation-plan.md`. Step 0 turns all of them into the same thing.
- An attended runner picks the next `[ ]` row from the plan.
- Do not use this to audit already-shipped work. That is `review-todo-section` in audit stance.

The section argument is the text after the skill name. Pass that string to `resolve`. Do not hand-translate it.

## Step 0 -- resolve the argument before anything else

Never hand-translate a reference into a filename. Ask the graph:

```powershell
python3 scripts/todo-graph.py resolve "<argument>"
```

It accepts whatever the caller had in front of them:

| Input | Works |
| --- | :-: |
| `D01 T01 §3` | yes |
| a plan row, pasted whole | yes |
| `01-notepad-core/TODO-01-winui-app-spine.md §3` | yes |
| Any prose containing one of the above | yes |

It prints the path, the section title, the item count, whether the TODO is frozen, and which dependencies are unmet. Its exit code is the instruction:

| Exit | Meaning | Do this |
| :-: | --- | --- |
| `0` | Resolved, open, dependencies met | Proceed to step 1 |
| `1` | No such TODO or no such section | Stop. Report the reference as unresolvable. Do not guess a near match. |
| `2` | No section reference in the input | Stop and ask which section. |
| `3` | The section is already `[x]` | Do not process it. This is `review-todo-section` in audit stance. Say so and hand over. |
| `4` | Unmet dependencies | Stop at the dependency gate and name the unmet sections. |
| `5` | The section moved out of the tree (`> **Moved:**` under its heading) | Stop. Its open work is worked from the file the `moved` line names, by that file's own rules. |

Use the `skill arg` line it prints as the canonical form for the rest of the run, so the commit message and the review call name the section the same way.

If `resolve` printed a `needs` line, the section needs a Windows host. Confirm the host is reachable before writing `Started:`. If it is not, stop and say which host the section waits on.

If `resolve` printed a `requires` line with requirements missing here, the section needs that environment. Confirm it is reachable before writing `Started:`. If it is not, stop and say which capability the section waits on.

Write `Started:` now, at the first resolve. If the section body carries no `> **Started:**` line, add one with the current UTC instant:

```powershell
[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
```

Do not overwrite an existing one on resume. Review subtracts it from stamp time for `Duration:`, which is the whole working interval.

Stop here if another writer holds the tree. Check `git status` for unfamiliar uncommitted work you do not understand, and ask before building over it. Two writers on one tree is how a call ships without its interface.

## Execution discipline

- Validate before building. Step 2 is a gate, not a formality. A section that cannot pass it gets fixed first.
- Follow the corrected contract. The checklist items define the scope. Do not widen because something adjacent looks wrong. File it with `add-todo`. Correcting a defect in the section is not widening. Adding work the section never asked for is.
- One section = one commit. If you cannot describe the change in one commit message, the section was mis-sized. Plan corrections may ride in that commit, or land as their own `todo:` commit first when they are substantial.
- Commits are free. Pushes are not. Commit locally as often as you like. Push twice per section: the SHIP push, then the STAMP push. While iterating, run the affected tests only (`dotnet test --filter '<names>'`), not the whole suite. A third push is allowed when it is named and the reason recorded.
- Never mark `[x]` without evidence. The Implementation Order row flips only after the review stamp exists.
- User data first. A section that writes files, syncs rows, numbers a document, or records consent is built to: atomic writes, read back what was written, skip and report rather than drop or duplicate, and every destructive path confirmed. Its Test checkpoint exercises the failure path, not only the happy path.
- Server-side authority, adapted. Any value the user trusts (file bytes, a permission decision, a diff hunk) is computed or verified in exactly one place, and the UI reflects it rather than deciding it. A UI calculation nothing verifies is a bug.
- Parity is the bar on Notepad surfaces. A section that builds a Notepad surface proves it against the captured baseline, not against memory of what Notepad looks like.

## The session does every step

One session validates, builds, gates, commits, and hands to review. It dispatches nobody to implement, gate, or keep records. Bound every command (`dotnet test --filter` for affected tests, `Select-Object -First` or `-Last` on logs, field extraction on JSON). An unbounded dump lands in the one context that must carry the rest of the run. Do not shell out to `grep`, `head`, `tail`, `sed`, `awk`, or `find`.

## Workflow

### 1. Read the whole contract

Step 0 gave you the path, the section, and the dependency verdict. Read the entire TODO file, not just the section. The Goal, Current state, and Inputs carry context the section assumes. Read the sections this one depends on. Their `Verified:` stamps tell you what actually shipped versus what was planned.

Confirm every dependency in the `Depends On` column is `[x]`. If one is not, stop and say so.

### 2. Validate the plan before building it

The section was written before the code existed. Check it still holds. Seven questions, each answered against the repository rather than from memory:

| Check | What you are asking | The failure it catches |
| --- | --- | --- |
| **Legitimacy** | Does a real source demand this: Notepad behavior, the ACP spec, a user need? Or was it inferred? | Work invented by the plan, built faithfully, wanted by nobody |
| **Currency** | Do the files, classes, routes, versions, and protocol shapes it names still exist and still behave that way? | A section pinned to a path or count that moved |
| **Consistency** | Do its own items agree with each other, with the file's Current state block, and with the sections it depends on? | Two items specifying different things; the later one silently wins |
| **Correctness** | Are the behaviors, names, and protocol details it states actually what the source says? | A stale behavior ported confidently into code |
| **Sufficiency** | Is there enough here to build without inventing? Are the decisions made, or deferred into the implementer's lap? | A section that becomes a design session for an unattended executor |
| **Verifiability** | Can the `Test checkpoint` be executed and can it fail? Does a `Freeze check` name fixtures that exist? | A checkpoint that passes by being unfalsifiable |
| **Accuracy** | Is every concrete claim still literally true: every reference, path, count, ID, and deferral? | A section that reads as authoritative while quietly citing things that moved |

Ground each answer:

```powershell
python3 scripts/todo-graph.py validate
git log --oneline -5 -- <the paths the section touches>
```

Search named classes and files with the `grep` tool.

#### Fact-check the section, claim by claim

`validate` proves the graph is well-formed. It cannot tell you whether a sentence is true. Walk the section (prose, items, checkpoint) and check every concrete assertion against the thing it describes.

| Claim in the section | Check it against |
| --- | --- |
| A file, class, test, command, or protocol method | It exists, spelled that way, at that path |
| A count, size, version, or measurement | Re-derive it |
| A commit SHA or run ID | It resolves |
| An `-> XREF:` reference | The target section exists, and points back |
| "Nothing exists yet" / "there is still no X" | X really does not exist |
| A quotation from the source or spec | It says that, verbatim, at that location |

#### Deferrals in both directions

```powershell
python3 scripts/todo-graph.py query deferred
```

Deferrals this section owns: another section handed you this work, and it is part of your scope whether or not the checklist mentions it. It turns FATAL the moment this row flips, so it is not optional.

Deferrals this section wrote: re-read each one against today's repository, not the day it was written. Three things can be wrong with an open deferral, and only the first is caught by tooling:

- The owner shipped it. `validate` already makes this FATAL. Close it with `> **Resolved:**`.
- The description has drifted. The owner is still legitimately open, but the deferral describes a state that has since changed. Correct the text in place, or close it if the reason for deferring is gone even though the owner has not shipped.
- The work was quietly done by someone else. The owner never ticked its box, so it is not formally stale, but the thing is fixed. Verify it, then close the deferral and tick the owner's item.

Read the `Verified:` stamps on the sections this one depends on. They record what actually shipped, which is frequently narrower than what was planned.

Anything unclear at this point becomes a question you answer from the source, not a decision you defer. Where the source is silent, take the industry-standard option, record that it is a default, and carry on with the cost of changing it noted.

### 3. Correct the section when validation fails

Findings from step 2 are fixed in the TODO file, before implementation, so the plan and the build never disagree in the record.

| Finding | Do this |
| --- | --- |
| Stale fact: a name, count, version, or path that moved | Correct it in place. Mark it `**Corrected YYYY-MM-DD:**` with what it said before and what the source says now. |
| Two items contradict | Resolve toward the source and the later decision. Say which one lost and why, in the item itself. |
| Item is unbuildable as written | Rewrite it to be concrete: name the file, class, or command. |
| Item is already true | Tick it and note that it shipped elsewhere, with the XREF. Do not rebuild it. |
| Item is genuinely wrong work | Do not silently drop it. Strike it with a stated reason, and if something must replace it, add that item. |
| `Test checkpoint` cannot fail | Rewrite it so it can. |
| The whole section is wrong | Stop. Do not implement. Report what is wrong and what you propose, and let the user decide. |
| A frozen behavior looks wrong | Do not change it, in code or in the plan. Record the question for the operator with the proposed fix, and continue around it. |
| A reference, path, count, or ID is wrong | Correct it to what the source says, marked `**Corrected YYYY-MM-DD:**`. Never delete a wrong figure silently. |
| A deferral's owner has shipped it | Close it: replace `> **Deferred:**` with `> **Resolved:**` in place, keeping the text and XREF, adding the date and the commit. |
| A deferral's description has drifted | Correct the text in place. If the reason for deferring is gone, close it and say so, even though the owner has not shipped. |
| A deferral's work was done without its owner ticking it | Verify it, close the deferral, and tick the owner's item. |

Two rules keep this honest:

- Correct the plan, never the goalpost. Narrowing a section so the code you were about to write happens to satisfy it is not validation. If the section demands more than you can deliver, the section wins.
- Say what you changed. The plan correction is reported alongside the implementation and appears in the commit body.

If step 2 finds nothing, say so in one line and move on.

### 4. Build the corrected contract

Work the checklist top to bottom. Tick each item as its Done-when becomes true, in the file, as you go.

- Build the cheaper substitute's failure into the work: the checkpoint must be able to catch the wrong thing, so build the test that distinguishes them.
- Keep the diff to the section. Adjacent wrongness gets filed with `add-todo`, not fixed in passing.
- UI sections: consume the shared styles named in `**Chrome:**`. A second tab bar, caret, or dialog is a defect, not a shortcut.

### 5. Surface completeness (UI sections)

Before the checkpoint, account for every control, menu item, dialog, and state the section's Fidelity counterpart has, each resolved to working (proven on the rendered surface) or deferred to a named, resolving section. A control disabled with a reason that names no section is missing, not deferred. `review-todo-section` refuses the stamp for an unaccounted control. Decide here, not there.

### 6. Run the Test checkpoint, for real

Execute the checkpoint command and read the output. Quote the result in the commit body. If the checkpoint cannot run (no Windows host, missing fixture), the section is not done: record what ran, what did not, and why, and stop without a stamp. A checkpoint half-run is not evidence.

UI proof follows `.grok/skills/process-todo-section/gates.md`: the focus-free default run and the focus-free Primary placement run. Interactive skips outside 02:00-06:50 local are `Night-owed` debt. Record the debt and flip the same session. Quiet time never holds a flip. Do not set `SCRATCHPAD_INTERACTIVE_FORCE` unless the operator accepted that interruption in this turn.

Then run the section's other owed gates: warnings clean, analysis clean, `validate` clean. Run the affected tests, not only the new ones.

### 7. Commit, push, hand to review

Commit as one section commit with the evidence in the body:

```text
<area>: <what now works> (<ref>)

<checkpoint output, quoted>
<plan corrections, if any>
```

Push the SHIP push. Then invoke `review-todo-section` on the same ref. Review writes the stamp and flips the row. This skill never flips a row itself. After the stamp lands, push the STAMP push and sync the plan:

```powershell
python3 scripts/todo-graph.py plan --sync
```

### 8. Report

Tell the user plainly: what was built, what the checkpoint proved (quoted), what plan corrections were made, what was filed rather than fixed, and where the stamp stands.

## Guardrails

- Do not implement a section you judged wrong. Correct it or stop.
- Do not widen the section. File adjacent work.
- Do not flip the Implementation Order row. Review owns that.
- Do not claim a checkpoint passed without running it. Quote the output.
- Do not build a UI surface whose named baseline artifact does not exist. The capture ships first.
- Do not end with the plan unsynced.
