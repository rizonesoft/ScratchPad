---
ack-version: 2
run: 2026-09-25-085626-pid54660 sha256:6e71ca06076d04ed68013683bfa3abd9ea2a6808250aa4c483808bb127b64498
run: 2026-09-25-090645-pid49952 sha256:169c17a4b1fbee4df97c7e8311ffb77b2838ded30ab0ded5395c14c78f6d2f53
incidents: none
owner: claude-runner
disposition: expected
corrective-owner: D00 T02 §30
due: 2026-09-25
finding: D00 T02 §30
signed: 2026-09-25
---

# RED acknowledgement: 2026-09-25 nightly evidence proof run

Signed by the Claude Code campaign runner (session 765b680e) during the Phase 0 run `docs/phase-runs/2026-09-25-phase-0.md`; the operator may countersign by committing an edit, which this file's git history records.

A manual governed run with every leg skipped by design, proving D00 T02 §30 end to end: the incident ledger presence check passes on the live tree (no v2 result carries incidents), the Run integrity line reads `Catalog: retained runs verified (3)`, and the result JSON carries the `incidentLifecycle` block that the run's own `Test-ResultFile -RequireLifecycle` self-check accepts. It reads RED only for its skipped legs; no legs ran, so it carries no incident.

The second run, on 3f60472 after the round-2 fixes, proves the same surfaces plus `incidentLifecycleSource: ledger` beside the block.
