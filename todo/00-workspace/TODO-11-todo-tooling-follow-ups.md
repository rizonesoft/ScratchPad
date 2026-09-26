---
schema_version: 1
id: todo-tooling-follow-ups
domain: 00-workspace
status: draft
title: "TODO-11 -- TODO Tooling Follow-Ups"
depends_on: []
track: W0
---

# TODO-11 -- TODO Tooling Follow-Ups

> **Goal:** The TODO graph tooling (`scripts/todo-graph.py`) refuses every reference it cannot resolve, so a cross-reference to a section that does not exist is caught at validation instead of surviving in the plan.

> [!IMPORTANT]
> **Current state:** `python scripts/todo-graph.py validate` checks that `-> XREF:` pairs are bidirectional between sections that exist, but on 2026-09-26 it read `0 fatal` while `todo/00-workspace/TODO-02-test-backbone.md` §33 carried a cross-reference to TODO-02 section 57, and TODO-02 has no section 57 (`resolve` on that address printed that the file has no such section). The line came from a residual renumbered after its reciprocal XREF was written; it was corrected by hand. TODO-01, which owns the TODO system's governance, reached its 55-section cap, so tooling follow-ups open here.

## Inputs

- [`scripts/todo-graph.py`](../../scripts/todo-graph.py) -- the validator this file extends (its XREF bidirectionality check and `resolve`)
- [`todo/README.md`](../README.md) -- the format spec that makes a one-sided or unresolvable XREF a defect
- -> XREF: D00 T01 §55 -- the last TODO-governance section in TODO-01, which reached its section cap; follow-ups on the same tooling continue here.

## Outcome

- `validate` reports FATAL for any `-> XREF:`, `Depends On` cell, or `(item: "...")` deferral naming a section that does not exist.

**Adjacency:** all=not-applicable (repository tooling for the TODO plan; nothing ships in the app, stores user data, or reaches app users)

**Adjacency rationale:** the change is confined to the stdlib-only plan validator and its self-test fixtures; no product surface or data path is involved.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Unresolvable reference refusal | D00 T01 §55 |  [ ]   |

---

## 1. Unresolvable Reference Refusal

Why this section exists: the validator accepted a cross-reference to TODO-02 section 57 in TODO-02 §33 although no section 57 exists, because the bidirectionality check only pairs sections it can find. A reference to a missing section is worse than a one-sided one: it points work at an owner that is not there. -> SOURCE: campaign-2026-09-26-d00t02s33-xref57

- -> XREF: D00 T01 §55 -- continues the TODO-governance tooling that file closed at its cap.

- [ ] `validate` resolves every `-> XREF:` target and reports FATAL naming the file, line, and missing address when the section does not exist. Done when: a self-test fixture with an XREF to a missing section reads FATAL with that address.
- [ ] `Depends On` cells and `(item: "...")` deferrals get the same resolution check. Done when: a fixture row depending on a missing section reads FATAL.
- [ ] The live tree validates clean after the check lands. Done when: `python scripts/todo-graph.py validate` reads 0 fatal on the tree.
- [ ] Commit: `"workspace: refuse unresolvable TODO references"`

**Test checkpoint:** `python scripts/todo-graph.py self-test` carries the missing-target fixtures and passes; `validate` on the live tree reads 0 fatal. Cheaper substitute that fails: a WARN that the gate never blocks on.

## Verification

- [ ] `python scripts/todo-graph.py self-test` green
- [ ] `python scripts/todo-graph.py validate` clean
