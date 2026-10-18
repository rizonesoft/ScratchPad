---
name: add-todo
description: Front door for new work -- search the tree for an existing home first, then add a checklist item, a new section, or a whole new TODO file. Use whenever work needs capturing.
---

# Add TODO

New work enters through here. The failure this prevents is a near-duplicate section in a second file: two owners, neither complete.

## 1. Search before filing

```bash
grep -rn "<keywords>" todo/ --include='TODO-*.md' | head -30
```

A home exists when an open section's scope already covers the work, even if its checklist does not name it yet.

## 2. Route

| Outcome | When | Do this |
| ------- | ---- | ------- |
| Already covered | A section owns it | Point at the section. File nothing. |
| Fits a section | An open section's scope covers it | Add a checklist item there. Never touch a `[x]` section's checklist. |
| Needs a section | Real work inside an existing file's scope | Add `## N.` in numerical position (before `## Verification`) with its Implementation Order row. |
| Needs a file | A subject no file owns | Copy `todo-template.md` (beside this skill) to `todo/<domain>/TODO-NN-<name>.md`, fill every `CHANGEME`, and list the file in the domain `INDEX.md`. |

File only work with an observable reason: a user-visible gap, a wrong result a test or user would see, a safety or data-integrity fault, or an operator request. Hardening ideas with no failure behind them are not filed.

## 3. Born complete

A new section carries what `todo/README.md` Section anatomy requires: context paragraph, checklist ending in `Commit:`, a falsifiable `Test checkpoint:`, the UI blocks on surface work, `Needs:`/`Requires:` when they apply, and a row with real `Depends On` edges (`--` only when it truly stands alone). Every section must be buildable with zero conversation context.

## 4. Wire and verify

- Point at related sections with `-> XREF:` and add the line pointing back in each target.
- A deferral that hands this work to an owner names the owner's `(item: "...")`.
- Add a row for every new section to the right phase table in `todo/implementation-plan.md`, then:

```bash
python3 scripts/todo-graph.py validate
python3 scripts/todo-graph.py plan --sync
python3 scripts/todo-graph.py plan --check
```

## 5. Commit and report

Commit as `todo: file <what> in <ref>`. Report the section address (`DNN TNN §N`) and why that home won.
