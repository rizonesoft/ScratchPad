---
schema_version: 1
id: unattended-notification-follow-ups
domain: 00-workspace
status: active
title: "TODO-08 -- Unattended Notification Follow-Ups"
depends_on: []
track: W0
---

# TODO-08 -- Unattended Notification Follow-Ups

> **Goal:** The unattended notification plus register machinery D00 T01 §53 shipped (poster, heartbeat, owner mapping, retry, dispositions, linkage) keeps hardening after its review: every filed residual ships with fixtures and review instead of rotting as a known gap.

> [!IMPORTANT]
> **Current state:** D00 T01 §53 shipped the per-obligation poster, the cron heartbeat, the owner-login registry, bounded retry, review dispositions, and superseded linkage. Its plan review returned 30 findings; 22 file here in two sections (delivery hardening plus governance), 1 closes in the §53 stamp, 2 correct §29 in place, 3 correct §54 in place, and 3 are rejected with reasons in the §53 findings file.

## Inputs

- [`tools/notify_poster.py`](../../tools/notify_poster.py) -- the per-obligation poster §1 hardens
- [`tools/check_heartbeat.py`](../../tools/check_heartbeat.py) -- the cron heartbeat §1 hardens
- [`.github/owner-logins.json`](../../.github/owner-logins.json) -- the owner registry §1 hardens
- [`.github/workflows/plan.yml`](../../.github/workflows/plan.yml) -- the unattended job §§1-2 harden
- [§53 review record](../../docs/reviews/00-workspace/D00-T01-s53.md) -- the plan-review ledger this file works off

## Outcome

- Poster waves prove themselves against disposable repositories, key on immutable obligation IDs, consume versioned JSON, reconcile under concurrency, and retire with idempotent operations plus classified retry.
- Bootstrap grace expires, latency SLOs read, acknowledgements escalate, the trust model reconciles, retention archives, renewals stay fresh, governance tiers by severity, notifications redact, and the dashboard shows premium views.

**Adjacency:** all=not-applicable (plan tooling plus the unattended CI job with no user-facing feature surface; GitHub issues are the operator channel, and the app surfaces the machinery guards declare their own adjacency in their own files)

**Adjacency rationale:** This file touches only plan tooling: the poster, the heartbeat, the owner registry, the workflow, fixtures, and operator docs for unattended notification. Nothing executes at app runtime or stores user data, so no adjacency key applies.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Poster and delivery hardening | D00 T01 §53 |  [ ]   |
|   2   |   §2    | Notification governance and premium views | D00 T01 §53 |  [ ]   |

---

## 1. Poster and Delivery Hardening

Why this section exists: the §53 plan review returned 30 findings; 11 harden the poster plus delivery path (integration proof, reminder cadence, mapping failures, multi-owner reconciliation, login preflight, machine IDs, JSON payloads, concurrency, snapshot guards, operation idempotency, retry classification), so they home here as the delivery half of the second resident file past the 55-section cap. -> XREF: D00 T01 §53 (filed from its plan review); -> SOURCE: plan-review-D00-T01-s53-2026-09-21-t08-s1 D00-T01-S53-PR2 D00-T01-S53-PR3 D00-T01-S53-PR4 D00-T01-S53-PR5 D00-T01-S53-PR6 D00-T01-S53-PR7 D00-T01-S53-PR8 D00-T01-S53-PR9 D00-T01-S53-PR10 D00-T01-S53-PR11 D00-T01-S53-PR12 (`gpt-5.6-sol` high over §53 plus §28 plus §29 plus §54, 30 findings, 11 filed here, 11 filed at D00 T08 §2, 1 closed in the §53 stamp, 2 correct D00 T01 §29 in place, 3 correct D00 T01 §54 in place, 3 rejected with reasons in the §53 findings file).

- [ ] The poster proves itself against a disposable repository: create, comment-on-open dedup, close-when-clear, reopen, and failure handling run against throwaway GitHub issues where auth exists and skip honestly elsewhere, so fake-`gh` argument fixtures stop standing in for authentication, permissions, pagination, and API behavior (PR2 D00-T01-S53-PR2). This item is a joiner from the §53 plan review. Done when: the integration leg runs green where auth exists and skips loud where it does not.
- [ ] Reminder cadence resolves the re-notify tension: overdue obligations either earn a periodic reminder comment or the no-repeat policy documents explicitly, so "re-notify every run" plus "quiet when identical" stop contradicting and an ignored issue cannot sit silent indefinitely (PR3 D00-T01-S53-PR3). This item is a joiner from the §53 plan review. Done when: the cadence or the documented policy ships with fixtures.
- [ ] Production mapping absence fails loud: a missing owner-login file or an unmapped escalation owner in production errors the wave (or documents the degradation contract explicitly), so the "owners receive notice" guarantee stops degrading to an unassigned issue in silence (PR4 D00-T01-S53-PR4). This item is a joiner from the §53 plan review. Done when: the failure or the contract ships with fixtures.
- [ ] Assignee reconciliation is exact: multi-owner obligations define handling and reassignment removes stale assignees as well as adding newly-mapped ones, so ownership changes leave neither missing nor stale accountable parties (PR5 D00-T01-S53-PR5). This item is a joiner from the §53 plan review. Done when: the reconciliation ships with fixtures.
- [ ] Login mapping gains a permission-aware preflight: assignees prove they exist and are assignable in the repository (or an integration fixture pins the failure), so invalid logins fail the wave loud instead of turning every notification wave into a failing job (PR6 D00-T01-S53-PR6). This item is a joiner from the §53 plan review. Done when: the preflight or the fixture ships.
- [ ] Obligations carry versioned machine IDs: `query notify` emits a stable obligation ID stored in an immutable issue label or body marker, so wording or title edits stop closing history and minting duplicates (PR7 D00-T01-S53-PR7). This item is a joiner from the §53 plan review. Done when: the ID ships with fixtures plus a migration for live issues.
- [ ] Poster payloads ride versioned JSON: `query notify` emits a schema-validated JSON payload the poster consumes, so display-copy changes stop altering identity, assignment, or closure behavior (PR8 D00-T01-S53-PR8). This item is a joiner from the §53 plan review. Done when: the schema plus both halves ship with fixtures.
- [ ] Concurrent waves reconcile safely: the workflow carries a concurrency group and the poster re-checks adoption before mutating, so overlapping push plus schedule runs cannot duplicate comments, reopen cleared issues, or close live ones (PR9 D00-T01-S53-PR9). This item is a joiner from the §53 plan review. Done when: the group plus guards ship with an overlap fixture.
- [ ] Clear-on-absence requires a complete snapshot: a successfully generated, schema-valid, generation-tagged inventory gates every clear, so partial or truncated output cannot falsely close obligations (PR10 D00-T01-S53-PR10). This item is a joiner from the §53 plan review. Done when: the gate ships with a truncation fixture.
- [ ] Mutating operations idle safely under retry: edit, comment, reopen, assign, clear, and close carry idempotency keys (extending the create adoption), so retries duplicate no reminder and apply no stale transition (PR11 D00-T01-S53-PR11). This item is a joiner from the §53 plan review. Done when: the keys ship with fixtures.
- [ ] Retry classifies before it sleeps: auth loss, rate limits (with `Retry-After`), and transient faults route to distinct backoff plus budget behavior, so blind fixed-sleep retry stops adding latency to permanent failures (PR12 D00-T01-S53-PR12). This item is a joiner from the §53 plan review. Done when: the classification ships with fixtures.
- [ ] Commit: `"workspace: harden poster and delivery per §53 plan review"`

**Test checkpoint:** Integration proves, cadence resolves, absence fails loud, assignees reconcile, logins preflight, IDs persist, JSON validates, waves serialize, snapshots gate, operations idle, retries classify. Falsifiable by any unproven post, silent wave, or duplicate issue.

## 2. Notification Governance and Premium Views

Why this section exists: the §53 plan review returned 30 findings; 11 harden notification governance (bootstrap grace, latency SLO, acknowledgement ladder, trust model, schema policy, retention, linkage breadth, renewal freshness, tiered governance, redaction, dashboard views), so they home here as the governance half of the second resident file past the 55-section cap. -> XREF: D00 T01 §53 (filed from its plan review); -> SOURCE: plan-review-D00-T01-s53-2026-09-21-t08-s2 D00-T01-S53-PR15 D00-T01-S53-PR16 D00-T01-S53-PR17 D00-T01-S53-PR18 D00-T01-S53-PR20 D00-T01-S53-PR21 D00-T01-S53-PR22 D00-T01-S53-PR23 D00-T01-S53-PR24 D00-T01-S53-PR26 D00-T01-S53-PR27 (`gpt-5.6-sol` high over §53 plus §28 plus §29 plus §54, 30 findings, 11 filed here, 11 filed at D00 T08 §1, 1 closed in the §53 stamp, 2 correct D00 T01 §29 in place, 3 correct D00 T01 §54 in place, 3 rejected with reasons in the §53 findings file).

- [ ] Bootstrap grace expires: the never-ran pass carries a bounded grace period anchored to deployment or workflow creation, so deleted run history or a never-started cron cannot masquerade as a valid first run past it (PR15 D00-T01-S53-PR15). This item is a joiner from the §53 plan review. Done when: the bound ships with fixtures.
- [ ] Notification latency reads as an SLO: maximum detection plus delivery latency across the 00:00 UTC transition, the cron fire, retries, and owner delivery documents (and measures where cheap), so "unattended" stops permitting an unstated multi-hour blind window (PR16 D00-T01-S53-PR16). This item is a joiner from the §53 plan review. Done when: the SLO reads with its measurement or its stated gap.
- [ ] Assignment completes into acknowledgement: acknowledgement state, acknowledgement deadlines, and a severity-based escalation ladder land on assigned issues, so an assigned-but-unnoticed obligation escalates instead of sitting indefinitely (PR17 D00-T01-S53-PR17). This item is a joiner from the §53 plan review. Done when: the ladder ships with fixtures.
- [ ] The trust model reconciles: §28's free-form owners plus approvers meet §53's validated owner-to-login registry in one stated model naming delivery identity, authorization identity, and approval authority, with dated notes where the reconciliation lands (PR18 D00-T01-S53-PR18). This item is a joiner from the §53 plan review. Done when: the model reads with its landing notes.
- [ ] Schema compatibility reads as policy: the plan-health /5-to-/9 trail plus the migration rule for consumers documents, so no consumer guesses which schema is authoritative or how to migrate (PR20 D00-T01-S53-PR20, policy half; the §29 trail note lands in §29). This item is a joiner from the §53 plan review. Done when: the policy reads beside the contract.
- [ ] The register retains plus archives: retention duration, archive policy, and audit export land on the risk register, so superseded and closed risk evidence cannot disappear operationally (PR21 D00-T01-S53-PR21). This item is a joiner from the §53 plan review. Done when: the policy ships with fixtures.
- [ ] Linkage covers every severity or says why not: supersession linkage extends past critical plus major rows, or the exclusion rationale records explicitly, so minor accepted risks keep an auditable history when they recur or aggregate (PR22 D00-T01-S53-PR22). This item is a joiner from the §53 plan review. Done when: the extension or the rationale ships.
- [ ] Renewals prove freshness: external-assumption rechecks, reviewer identity, and evidence expiry gate the renew disposition, so legal, threat, vendor, and operational drift cannot hide behind an unchanged tree (PR23 D00-T01-S53-PR23). This item is a joiner from the §53 plan review. Done when: the gates ship with fixtures.
- [ ] Governance tiers by severity: configurable lead times, quorum, and separation of duties replace the universal one-day plus single-operator default where severity demands, so critical risk earns stronger governance than minor risk (PR24 D00-T01-S53-PR24). This item is a joiner from the §53 plan review. Done when: the tiers ship with fixtures.
- [ ] Notifications redact: repository-visibility checks, secret scanning, and public-safe summaries gate issue bodies, so notification convenience never discloses internal vulnerabilities (PR26 D00-T01-S53-PR26). This item is a joiner from the §53 plan review. Done when: the gates ship with fixtures.
- [ ] The dashboard shows premium views: aging, recurrence, delivery status, owner load, and links to the governing acceptance plus issue extend the point-in-time rollup (PR27 D00-T01-S53-PR27). This item is a joiner from the §53 plan review. Done when: the views render with fixtures.
- [ ] Commit: `"workspace: govern notification per §53 plan review"`

**Test checkpoint:** Grace expires, latency reads, acknowledgement escalates, trust reconciles, policy versions, retention archives, linkage covers, renewals freshen, governance tiers, bodies redact, views drill. Falsifiable by any silent expiry, unstated trust, or undisclosed risk.

## Verification

- [ ] Poster waves prove idempotent end to end and governance artifacts gate their dates
- [ ] `python3 scripts/todo-graph.py validate` clean
