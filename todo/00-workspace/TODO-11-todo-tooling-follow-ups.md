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

> **Goal:** The TODO graph tooling (`scripts/todo-graph.py`) refuses every reference it cannot resolve, so a cross-reference to a section that does not exist is caught at validation instead of surviving in the plan, and its night-debt governance (the `Night-*` lifecycle it replays) reads every debt's history causally, recoverably, and explainably.

> [!IMPORTANT]
> **Current state:** `python scripts/todo-graph.py validate` checks that `-> XREF:` pairs are bidirectional between sections that exist, but on 2026-09-26 it read `0 fatal` while `todo/00-workspace/TODO-02-test-backbone.md` §33 carried a cross-reference to TODO-02 section 57, and TODO-02 has no section 57 (`resolve` on that address printed that the file has no such section). The line came from a residual renumbered after its reciprocal XREF was written; it was corrected by hand. TODO-01, which owns the TODO system's governance, reached its 55-section cap, so tooling follow-ups open here.

## Inputs

- [`scripts/todo-graph.py`](../../scripts/todo-graph.py) -- the validator this file extends (its XREF bidirectionality check and `resolve`)
- [`todo/README.md`](../README.md) -- the format spec that makes a one-sided or unresolvable XREF a defect
- -> XREF: D00 T01 §55 -- the last TODO-governance section in TODO-01, which reached its section cap; follow-ups on the same tooling continue here.
- -> XREF: D00 T02 §50 -- the night-debt governance whose residuals §2 carries.

## Outcome

- `validate` reports FATAL for any `-> XREF:`, `Depends On` cell, or `(item: "...")` deferral naming a section that does not exist.
- Every night debt replays causally, resolves conflicts by record, closes only on complete and durable evidence, and explains itself.

**Adjacency:** all=not-applicable (repository tooling for the TODO plan; nothing ships in the app, stores user data, or reaches app users)

**Adjacency rationale:** the change is confined to the stdlib-only plan validator and its self-test fixtures; no product surface or data path is involved.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Unresolvable reference refusal | D00 T01 §55 |  [ ]   |
|   2   |   §2    | Night-debt governance third residuals | D00 T02 §50 |  [ ]   |

---

## 1. Unresolvable Reference Refusal

Why this section exists: the validator accepted a cross-reference to TODO-02 section 57 in TODO-02 §33 although no section 57 exists, because the bidirectionality check only pairs sections it can find. A reference to a missing section is worse than a one-sided one: it points work at an owner that is not there. -> SOURCE: campaign-2026-09-26-d00t02s33-xref57

- -> XREF: D00 T01 §55 -- continues the TODO-governance tooling that file closed at its cap.

- [ ] `validate` resolves every `-> XREF:` target and reports FATAL naming the file, line, and missing address when the section does not exist. Done when: a self-test fixture with an XREF to a missing section reads FATAL with that address.
- [ ] `Depends On` cells and `(item: "...")` deferrals get the same resolution check. Done when: a fixture row depending on a missing section reads FATAL.
- [ ] The live tree validates clean after the check lands. Done when: `python scripts/todo-graph.py validate` reads 0 fatal on the tree.
- [ ] Commit: `"workspace: refuse unresolvable TODO references"`

**Test checkpoint:** `python scripts/todo-graph.py self-test` carries the missing-target fixtures and passes; `validate` on the live tree reads 0 fatal. Cheaper substitute that fails: a WARN that the gate never blocks on.

## 2. Night-Debt Governance Third Residuals

Why this section exists: the D00 T02 §50 plan review returned 14 findings, all filed here with §50's round-5 finding R5-I1 (TODO-02, which holds §50, reached its 55-section cap, and night debt is TODO-graph tooling). §50 made replay ordered by effective time, contradictions ineffective, inventory, candidate, and schedule captured, the inline override governed, accepted remediation visible, writes reconciled, reassignment attributed, and evidence retained; these carry that through causal predecessors, conflict resolution, one transition contract, branch and working-tree identity, inventory migration, per-case completion, immutable schedules, durable operation identity, evidence integrity, ownership escalation, extension arithmetic, successor findings, generated invariants, and an explanation per debt. -> SOURCE: plan-review-D00-T02-s50-2026-09-26-d00t11s2 D00-T02-S50-PR1 D00-T02-S50-PR2 D00-T02-S50-PR3 D00-T02-S50-PR4 D00-T02-S50-PR5 D00-T02-S50-PR6 D00-T02-S50-PR7 D00-T02-S50-PR8 D00-T02-S50-PR9 D00-T02-S50-PR10 D00-T02-S50-PR11 D00-T02-S50-PR12 D00-T02-S50-PR13 D00-T02-S50-PR14 D00-T02-S50-R5-I1

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §50 -- filed from its plan review and its round-5 cap; carries the night-debt governance it settled.

- [ ] Replay is causal, not only ordered: a lifecycle record may name its predecessor event, and late, backdated, and future-dated events have rules, so a revocation or renewal never replays before the event it modifies. Done when: a revocation dated before its acceptance but naming it as predecessor reads after it. (D00-T02-S50-PR1.)
- [ ] Contradictions have an authorized, append-only resolution: a resolution record names the conflicting event identities and the one that governs, so a debt recovers without deleting history. Done when: a resolution record makes the named event govern and the other stay on record. (D00-T02-S50-PR2.)
- [ ] One versioned transition contract separates event order from state precedence (§35's collected over accepted over acknowledged), replacing §42's text order everywhere it is documented. Done when: the contract names both rules and every doc points at it. (D00-T02-S50-PR3.)
- [ ] Candidate binding requires ancestry on the governed branch and identifies the tested working-tree state (clean or the dirty paths), so evidence from an unrelated branch or a dirty tree never proves the owed implementation. Done when: a green run on an unrelated branch or a dirty tree keeps the debt open. (D00-T02-S50-PR4.)
- [ ] The owed inventory has an explicit migration for renamed, removed, and undiscoverable tests, with unresolved tests reported, so test churn neither forgives debt nor makes closure impossible. Done when: a renamed owed test migrates by record and an undiscoverable one is named. (D00-T02-S50-PR5.)
- [ ] Closure requires a successful terminal result for every owed case: skips, cancellations, partial runs, and duplicate results each have a defined effect, so a matching digest cannot prove completion by itself. Done when: a matching digest with one skipped owed case keeps the debt open. (D00-T02-S50-PR6.)
- [ ] Schedule identity is immutable: the schedule definition and the resolved trigger instants (with the timezone-rule version) are retained, so later configuration or timezone-database changes never alter a historical deadline. Done when: a schedule change after owing leaves the owed debt's due unchanged. (D00-T02-S50-PR7.)
- [ ] Reconciliation has a durable operation identity and restart recovery across crashes and concurrent file changes, so a landed collection is neither duplicated nor overwritten. Done when: a crash between write and record, retried concurrently, lands one line. (D00-T02-S50-PR8.)
- [ ] Closure evidence has a minimum durable content, integrity checks, a retention duration, and a degraded-evidence status in the debt's verified state. Done when: a collected line whose evidence fails its integrity check reads degraded. (D00-T02-S50-PR9.)
- [ ] A debt with no accountable owner, or one assigned to an unavailable owner, escalates for reassignment instead of resting on the default owner. Done when: a debt owned only by the default escalates for an owner. (D00-T02-S50-PR10.)
- [ ] Extension arithmetic is defined in calendar days on the recorded wall clock, and revoked extensions are counted against the cumulative cap, so renewals cannot bypass the limit. Done when: a revoked 15-day extension plus a new 10-day one exceeds the cap. (D00-T02-S50-PR11.)
- [ ] A closed remediation finding followed by another failed collection reopens or names a successor finding with an owner, so an unresolved failure always has an actionable remediation. Done when: a red after the finding closed names a successor finding. (D00-T02-S50-PR12.)
- [ ] Whole-history invariants hold under generated lifecycle sequences (permutations, retries, conflicts, restarts): closure and protected deadlines never change with order or replay. Done when: a generated suite of sequences reads one outcome per history. (D00-T02-S50-PR13.)
- [ ] Each debt carries a deterministic explanation: its effective events, rejected evidence with reasons, the deadline calculation, and the next owner action. Done when: a debt's explanation names each of the four for a fixture history. (D00-T02-S50-PR14.)
- [ ] In the repeated fall-back hour, the first collector night compares instants, not wall-clock times: an owed time after a trigger that already fired in the first occurrence counts the next night (absorbs the §50 round-5 finding). Done when: a debt owed at 02:10+01:00 after a 02:30+02:00 trigger reads the next night's due. (D00-T02-S50-R5-I1.)
- [ ] Commit: `"workspace: settle the third night-debt governance residuals"`

**Test checkpoint:** `python scripts/todo-graph.py self-test` carries a fixture per item, including generated lifecycle sequences, and passes; `tools/NightDebt.Tests.ps1` proves the durable reconciliation. Cheaper substitute that fails: more WARN text with no rule behind it.

## Verification

- [ ] `python scripts/todo-graph.py self-test` green
- [ ] `python scripts/todo-graph.py validate` clean
