---
schema_version: 1
id: panel-rule-follow-ups
domain: 00-workspace
status: active
title: "TODO-04 -- Panel Rule Follow-Ups"
depends_on: []
track: W0
---

# TODO-04 -- Panel Rule Follow-Ups

> **Goal:** The review panel machinery keeps its follow-up work in one durable home past the T01 section cap: every filed panel residual ships with fixtures and review instead of swelling an omnibus section past the sizing rule.

> [!IMPORTANT]
> **Current state:** `D00 T01` holds 55 sections (capped; `validate` FATALs a 56th) and its §55 reached 34 checklist items past the 30-item sizing rule, so the §37 follow-ups below home here as the first overflow file instead of joining it. `D00 T01 §37` ships the Sol-outage accountability rule, the round-5 stop, finding dispositions with tables, all-Opus positions, the plan-health fallback definition, and the term alias; this file's §1 carries that review's 7 residuals (2 panel, 5 plan-review).

## Inputs

- [D00 T01 §37 review record](../../docs/reviews/00-workspace/D00-T01-s37.md) -- the R3 findings (R3-F1, R3-F2) plus the plan-review ledger this file's §1 works off
- [Review skill](../../.claude/skills/review-todo-section/SKILL.md) -- the outage matrix, disposition vocabulary, and table shape §1 tightens
- [`scripts/todo-validate.py`](../../scripts/todo-validate.py) -- the `panel-sol-outage-missing` leg §1 hardens and enforces
- [`todo/README.md`](../README.md) -- the severity table whose class row §1 completes

## Outcome

- An Opus-only record without an honest Sol account fails validation, and honest failure prose never false-fires.
- Panel findings disposition through enforced tables with an escalated terminal state, and blocking round-5 leftovers stop the run by gate, not just by prose.
- Partial Sol failure, interrupted runs, and the §55 Commit title read deterministically.

**Adjacency:** all=not-applicable (review-machinery follow-ups with no user-facing feature surface; the app surfaces the panel reviews declare their own adjacency in their own files)

**Adjacency rationale:** This file touches only the review loop: skill prose, validator rules, help text, and plan wording. No editor, protocol, agent, voice, or packaging surface changes, so no adjacency key applies; the line mirrors T01's toolchain stance for the same reason.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Sol-note and disposition follow-ups | D00 T01 §37 |  [ ]   |

---

## 1. Sol-Note and Disposition Follow-Ups

Why this section exists: the §37 review's sign-off round plus plan review returned 7 residuals that belong to the panel rules, and §55 (34 items past the 30-item sizing rule, and the file is at the 55-section cap) cannot take them, so they home here as the first overflow file. -> XREF: D00 T01 §37 (filed from its review and plan review); -> XREF: D00 T01 §55 (overflow source: 34 items past the 30-item sizing rule); -> SOURCE: Opus-panel-D00-T01-s37-round-3 (candidate a242025c, round-3 adversarial advisory 1 plus consistency 1; transcribed in docs/reviews/00-workspace/D00-T01-s37.md); -> SOURCE: plan-review-D00-T01-s37-2026-09-19-t04 D00-T01-S37-PR3 D00-T01-S37-PR4 D00-T01-S37-PR5 D00-T01-S37-PR13 D00-T01-S37-PR18 D00-T01-S37-PR22 (`gpt-5.6-sol` high over §37 plus §35 plus §36 plus §55, 26 findings, 6 filed here in 5 items with PR3 plus PR4 merged, 4 duplicates, 13 rejected with reasons in the §37 findings file).

- [ ] Sol-note nothing-check re-anchors to the whole value: honest failure prose opening with a listed word (`never responded...`, `none of the CLIs...`) passes while bare nothing-valued notes still fire, so the no-false-fire claim holds (R3-F1, record in the §37 findings file). This item is a joiner from the §37 review. Done when: the re-anchored check plus fixtures ship (honest openers pass, denials fire) and the rule comment drops the overclaim.
- [ ] Sol-evidence condition reaches the docs: the README class row plus the skill outage matrix state that only a GPT section carrying a verdict counts as a Sol round (empty GPT sections fire), matching the shipped rule and the §44 pin (R3-F2, record in the §37 findings file). This item is a joiner from the §37 review. Done when: both sites state the condition.
- [ ] Panel dispositions gain enforcement: the validator fires on missing, duplicate, or unknown disposition rows plus round-5 file-and-stamp over blocking leftovers, so the tables and the stop rule execute instead of advising (PR3 PR4 D00-T01-S37-PR3 D00-T01-S37-PR4). This item is a joiner from the §37 plan review. Done when: both legs plus fixtures ship.
- [ ] Dispositions gain the escalated state: blocking round-5 leftovers that stop the run record `escalated` with operator ownership, so the required outcome reads accurately (PR5 D00-T01-S37-PR5). This item is a joiner from the §37 plan review. Done when: the skill names the state and the table shape carries it.
- [ ] Partial Sol failure gets deterministic rules: per-round fallback, recovery, retry limits, and no-flap behavior, so transient failures produce one predictable panel shape (PR13 D00-T01-S37-PR13). This item is a joiner from the §37 plan review. Done when: the matrix names the rules.
- [ ] Interrupted reviews leave resumable state: a both-families-down stop writes a durable incomplete-run record the next session resumes without breaking lineage (PR18 D00-T01-S37-PR18). This item is a joiner from the §37 plan review. Done when: the record shape plus resume path ship.
- [ ] The §55 Commit line is retitled to cover the joined scope (runners, artifacts, integers, terminology, panel rules), so the eventual commit describes its behavior (PR22 D00-T01-S37-PR22). This item is a joiner from the §37 plan review, implemented in `todo/00-workspace/TODO-01-repo-and-toolchain.md`. Done when: the retitled line reads.
- [ ] Commit: `"workspace: follow up panel rules per §37 review"`

**Test checkpoint:** the re-anchored nothing-check passes honest openers and fires denials (matrix green), disposition tables validate with the escalated state, partial-failure and resume rules read in the matrix, the §55 Commit line is retitled; suite green, validate clean. Cheaper substitute that fails: prose controls nobody checks.

## Verification

- [ ] `python3 scripts/todo-graph.py validate` clean
- [ ] Self-test green with the new pins (matrix, enforcement legs, fixtures)
- [ ] §1 stamped with panel plus plan review
