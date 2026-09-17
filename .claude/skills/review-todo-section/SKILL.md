---
name: review-todo-section
description: Quality-gate a just-implemented TODO section -- self-review, independent review lenses, fix loop, then the Verified stamp and the row flip. Also runs in audit stance on shipped sections. Use after process-todo-section or when asked whether a section is really done.
---

# Review TODO Section

The gate between "code exists" and "the row says `[x]`". Nothing else may flip that row.

**Review is mandatory.** A `Verified:` stamp whose `Review:` line does not record real review work, with a committed findings file, is not a valid stamp. Self-review stays in-session, but the lens verdicts come from the headless Opus panel below, never from the implementing session alone: and the findings file is what makes that honest.

## Use this skill when

- A section was just implemented (`process-todo-section` ends by invoking this).
- The user asks "is §N really done?", "re-verify §N", "audit §N": run in **audit stance** (below).
- Before closing out a TODO file with `process-todo-file`.

## Step 0 -- resolve the argument

Same front door as `process-todo-section`. Never hand-translate a reference into a filename:

```bash
python3 scripts/todo-graph.py resolve "$ARGUMENTS"
```

Exit `3` means the row is already `[x]`. That is not an error here: it is the signal to run in **audit stance**, where the only permitted row change is `[x]` to `[ ]` on regression evidence.

## The three questions

Every review answers these with code and behavior evidence, never with assertion:

1. **Does it make sense?** Does the implementation produce the exact outcome the section asked for, without unnecessary scope?
2. **Is it logical?** Do the domain relationships, validation, calculations, permissions, UI behavior, and failure paths agree with each other?
3. **Did it break anything else?** Inspect callers, consumers, tests, and any adjacent workflow that reads what you changed.

Answer each by naming files and behavior. "Reviewed the changes, looks correct" is not an answer.

## Workflow

### 1. Map the evidence, then fix the candidate

For each checklist item marked `[x]` in this session, find the code that satisfies it. An item with no corresponding change is either not done (un-tick it) or was already true (worth a note).

Read the actual diff (`git diff`, `git show`), not your memory of writing it.

Then fix the **candidate**: the commit (or commit range) under review, recorded verbatim in the findings file with its hashes. A candidate nobody wrote down cannot be re-derived, and a review of an unknown candidate proves nothing. For an audit of shipped work, the candidate is the section's own commit(s), not the current tree: the tree has moved on.

### 2. Self-review

Work the three questions across the diff and its blast radius. Fix what you find, then re-ask them: a fix changes the answers. Self-review runs before the lenses, and it costs no round.

Look specifically for the failure modes this codebase is prone to:

- A trusted value decided in the UI with nothing verifying it.
- A file write that is not atomic, or a dirty flag that can disagree with the buffer.
- A permission or consent check the UI performs but the handler does not re-check.
- An encoding or line-ending path that assumes UTF-8.
- A protocol message built without schema validation.
- An agent-facing path with allow-by-default behavior.
- A frozen behavior that moved.
- A test that passes without exercising the behavior (mock that accepts anything, assertion on nothing).
- A UI surface compared against memory instead of the captured baseline.

Cheap defects caught here cost nothing; the same defect caught by a lens costs a whole round.

### 3. The lenses

Run each lens as a separate pass over the candidate, recording findings in the findings file (`docs/reviews/<domain>/D<NN>-T<NN>-s<N>.md`). Commit the findings file with the review.

| Lens | Asks |
| ---- | ---- |
| `adversarial` | How would this fail in hostile hands? Malformed input, races, injection, revoked consent mid-flow. |
| `consistency` | Does this agree with the rest of the tree: naming, patterns, shared styles, the settings store, the undo path? |
| `integration` | Do the callers and consumers still hold: shell/surface contract, transcript contract, session lifetime? |
| `source-defect` | When owed (a Notepad behavior or protocol detail is at stake): is the source read correctly, and is the deviation declared? |
| `design` | On a surface: judge the RENDERED surface against the baseline or contract, never source alone. Screenshots or driven captures, not impressions. |
| `record` | Is the record honest: does the stamp's evidence match what ran, do deferrals name owners, is the row flip earned? |

Each lens ends in a verdict: `approve`, `needs-attention` (with findings), or `advisory` (noted, not blocking). Findings are fixed in the candidate and the affected lens re-runs: iterate until no lens reports anything the plan would fix, with a cap of 5 rounds. A unit patched three rounds running is stopped and re-thought instead of patched again.

### The headless Opus panel

Run the lenses through headless Claude Code on Opus, with the candidate diff and the section contract inline (no tools needed, nothing to install):

```bash
git show <candidate> > /tmp/review-diff.patch
{ echo 'You are an independent code reviewer. Review the candidate diff below against the section contract below it.';
  echo 'Return one verdict per lens (approve / needs-attention / advisory): adversarial, consistency, integration, record.';
  echo 'Every non-approve verdict names files with line numbers and the exact defect. No other text.';
  echo '--- SECTION CONTRACT ---'; <section text: Why, items with Done-whens, checkpoint>;
  echo '--- CANDIDATE DIFF ---'; cat /tmp/review-diff.patch; } > /tmp/review-prompt.md
claude "$(cat /tmp/review-prompt.md)" -p --model opus --allowedTools Read
```

(Prompt first as the positional argument, `--allowedTools` last: the flag is variadic and swallows anything after it. `Read` keeps the panel read-only; the diff and contract ride inline.)

Record the panel's per-lens verdicts verbatim in the findings file under a level-2 (or deeper) heading starting with the words `Opus panel` (a `Round N` suffix is fine; anything else, like `Round 2 Opus panel`, does not match), transcribed so each lens verdict sits on its own line as `` `lens` verdict `` (lens name immediately followed by `approve`, `needs-attention`, or `advisory`): the validator matches that shape per line, reading the LAST panel section as the record of verdict. Fenced code blocks are stripped before the scan, so quoting the panel shape inside a fence neither satisfies the rule nor displaces the real panel. Each verdict line must open (after up to 3 spaces) with a Markdown marker (`*`, backtick, `>`, `-`): mid-line mentions never count, so unheaded prose after an incomplete panel cannot supply its verdicts. Quoted headings are not structure: a fenced heading neither terminates nor displaces the panel. Quoted fences count as fences: a close must match the opener's quote depth, and a quote that ends ends its fence (a blank line ends the quote, so keep quoted fences blank-free). A backtick in a backtick-fence info string makes the line a paragraph. An unbalanced fence fails naming its opener line. The stamp's `Review:` line must name the findings file as `Raw findings: <repo-relative path>`: without it the validator cannot find the verdicts. A `needs-attention` verdict opens a fix-loop round: fix in the candidate, commit the fix, and re-run the panel against the NEW candidate diff with the prior verdicts appended (so fixed findings stay fixed and only live ones re-report). The loop is bounded, never infinite: at most 5 panel rounds per review, and a unit patched in 3 consecutive rounds is stopped and re-thought instead of patched again. If round 5 still reports `needs-attention`, file each leftover through `add-todo` (a new section, or an item on an existing section when small), record the filed refs in the findings file, and stamp with the `Review:` line naming the filed follow-ups: tracked work, not dropped work. If the panel is unreachable (no CLI, auth failure), stop and say so: a session-only lens pass is not a substitute, and filing the outage does not earn the stamp.

### 4. Re-run the gates

After the last fix, re-run the section's Test checkpoint and the owed gates (affected suites, warnings, analysis, `validate`). Quote the outputs. A fix verified by reasoning is not verified.

### 5. Surface check (UI sections)

Every control, menu item, dialog, and state on the Fidelity counterpart is working (proven on the rendered surface in this review) or deferred to a named, resolving section. Refuse the stamp for an unaccounted control. Compare the rendered surface against the baseline artifact or design contract before stamping, and confirm the user-guide update shipped in the same commit.

### 6. Frozen check (frozen TODOs)

Every `**Freeze check:**` in the section ran and passed, with the result quoted. No frozen behavior moved without a recorded operator approval. If one did, there is no stamp: there is a question for the operator.

### 7. Write the stamp and flip the row

Append the stamp block at the end of the section: `Verified:` (date, coverage, quoted evidence), `Review:` (rounds, candidate fingerprint or hashes, per-lens verdicts, findings-file link), `CRUD:` (behavioral evidence or an honest not-applicable), plus `Duration:` and carried `Deferred:` lines. Then flip the Implementation Order row to `[x]`.

Re-verification replaces the stamp in place. Never accumulate duplicates, and never edit a stamp to fit new code: the fix goes forward in a new commit and the stamp is rewritten by review.

### 8. Audit stance

On an already-`[x]` section: run steps 1-6 against the section's own candidate. Confirm the stamp's evidence still holds (re-run the checkpoint), or find the regression. The only permitted row change is `[x]` to `[ ]`, with the reason written into the section as a blocking note. A re-confirmed row keeps its stamp; say so in one line.

## Guardrails

- Do not stamp without a findings file. A verdict with no record is an opinion.
- Do not stamp an unaccounted control on a UI section.
- Do not stamp a frozen behavior that moved without approval.
- Do not flip a row this review did not earn.
- Do not review the working tree when the candidate is a commit. Name the hashes.
