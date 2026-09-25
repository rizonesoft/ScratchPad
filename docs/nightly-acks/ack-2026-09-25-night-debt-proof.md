---
ack-version: 2
run: 2026-09-25-065954-pid58116 sha256:c8e66dda03801ab992ccf431d4ad73f657e5f9174de75665630713f9b9db0ff9
incidents: none
owner: claude-runner
disposition: expected
corrective-owner: D00 T02 §27
due: 2026-09-25
finding: D00 T02 §27
signed: 2026-09-25
---

# RED acknowledgement: 2026-09-25 night-debt proof run

Signed by the Claude Code campaign runner (session 765b680e) during the Phase 0 run `docs/phase-runs/2026-09-25-phase-0.md`; the operator may countersign by committing an edit, which this file's git history records.

A manual governed run with every leg skipped by design, on e2912fb, proving D00 T02 §27 item 6: the collector reads all four open debts again through `query night-debt --json` (it had parsed none since D00 T02 §19 changed the query line), and the report's debt status block quotes each debt's query line verbatim. It reads RED only for its skipped legs; no legs ran, so it carries no incident.
