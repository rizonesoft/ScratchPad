---
ack-version: 2
run: 2026-09-25-023005-pid49540 sha256:ea9afee2b69e8c6b8b7c38f6ebb164aab1b69efc9d469db322bec54ac4d6e3b3
incidents: none
owner: claude-runner
disposition: fixed
corrective-owner: D00 T02 §29
due: 2026-09-25
finding: b9f1bee
signed: 2026-09-25
---

# RED acknowledgement: 2026-09-25 02:30 timer run

Signed by the Claude Code campaign runner (session 765b680e) during the Phase 0 run `docs/phase-runs/2026-09-25-phase-0.md`; the operator may countersign by committing an edit, which this file's git history records.

The timer run built green and then refused every leg on population drift: `Population: DRIFT: population drift: interactive-cases: fingerprinted 37 vs discovered 42`. Cause: d21ae60 (D00 T02 §21 R5) recorded 37 interactive cases, but the `NumberShortcutsCoverMiddlePositions` Theory expands to 6 cases (37 methods, 42 cases). Fixed forward in b9f1bee; the nightly's own comparer reads `population OK run-a=212/265 run-b=4/4 interactive=37/42` after the fix, and every later run on 2026-09-25 quotes `Population: OK`. No legs ran, so the run has no incidents. The gap that let it through (the fingerprint is only checked inside the night) is owned by D00 T02 §29.
