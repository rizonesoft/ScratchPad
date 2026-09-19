---
schema_version: 1
id: operator-docs
domain: 00-workspace
status: active
title: "TODO-06 -- Operator Docs"
depends_on: []
track: W0
---

# TODO-06 -- Operator Docs

> **Goal:** The operator docs a clean clone follows stay true as the tree moves: every prerequisite, path, and command they name matches what the repo currently requires.

> [!IMPORTANT]
> **Current state:** `docs/bootstrap.md` carries the prerequisite table plus the setup steps, `docs/build.md` the build, clean, and launch commands. D00 T01 §41 made Python the only documented way to launch the stub and prune `Bin/` on Windows, but the prerequisite table still scopes Windows Python to the pre-commit TODO gate. This file's §1 audits the table for post-§41 accuracy.

## Inputs

- [`docs/bootstrap.md`](../../docs/bootstrap.md) -- the prerequisite table plus setup steps §1 audits
- [`docs/build.md`](../../docs/build.md) -- the launch and clean commands that widened Python's role
- [§41 review record](../../docs/reviews/00-workspace/D00-T01-s41.md) -- round-5 advisory R5-F1 this file's §1 works off

## Outcome

- Every prerequisite-table row names every live consumer of its prerequisite.
- No setup step runs a command its row's prerequisite does not provide.

**Adjacency:** all=not-applicable (operator-docs wording with no runtime behavior; the app surfaces the docs describe declare their own adjacency in their own files)

**Adjacency rationale:** This file changes doc prose only: prerequisite scope plus any understated rows the audit finds. Nothing executes at app runtime, stores user data, or gates an action, so no adjacency key applies.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Prerequisite scope audit | D00 T01 §41 |  [ ]   |

---

## 1. Prerequisite Scope Audit

Why this section exists: the §41 review's round-5 advisory found `docs/bootstrap.md:12` scoping Windows Python to the pre-commit TODO gate while §41's launcher and clean docs make Python the only documented launch and prune path. Below bar at round 5, so it files here instead of re-rounding. Audit the whole prerequisite table (both OSes) against the post-§41 operator paths and correct every understated row. -> XREF: D00 T01 §41 (filed from its round-5 review); -> SOURCE: panel-D00-T01-s41-round-5-R5-F1 (consistency advisory; transcribed in docs/reviews/00-workspace/D00-T01-s41.md).

- [ ] Every prerequisite-table row is audited against the post-§41 operator paths (launch, clean, hooks, builds, tests): each row names every live consumer of its prerequisite. Done when: the audit names each row's consumers with file and line.
- [ ] Understated rows are corrected, starting with the Windows Python row gaining the launcher and clean consumers. Done when: no row omits a live consumer.
- [ ] Commit: `"workspace: audit prerequisite scope per §41 review"`

**Test checkpoint:** each prerequisite row lists its consumers and each setup command resolves to a provided prerequisite; falsifiable by any live consumer missing from its row or any step naming an unprovided command.

## Verification

- [ ] Prerequisite rows name every live consumer
- [ ] `python3 scripts/todo-graph.py validate` clean
