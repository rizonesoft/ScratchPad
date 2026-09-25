---
ack-version: 2
run: 2026-09-25-054048-pid46828 sha256:3726ed8598337e37fc21800cf5f0aa4ffc9d385fca296873d6b1a752cddcaf95
incidents: none
owner: claude-runner
disposition: fixed
corrective-owner: D00 T02 §24
due: 2026-09-25
finding: 359fa77
signed: 2026-09-25
---

# RED acknowledgement: 2026-09-25 notification failure proof run

Signed by the Claude Code campaign runner (session 765b680e) during the Phase 0 run `docs/phase-runs/2026-09-25-phase-0.md`; the operator may countersign by committing an edit, which this file's git history records.

A manual governed run with every leg skipped and the notify ledger deliberately corrupted, run on 9caadf9 to prove D00 T02 §24 R4-F2: the notification failure after the final publication was caught (`notification failed after publication (record stands)`) and the result kept its legs, environment, and budget. The run also read `Agreement RED` on the environment topology: a real defect in the candidate (the topology value carries the '; ' the Environment line split on), fixed in 359fa77 and pinned by a two-monitor fixture. No legs ran, so the run carries no incident.
