# Incident ledger record

The cross-night incident ledger (`build/nightly/incidents.json`, ignored scratch) started under identity contract v2 (D00 T02 §22, §30). This tracked record lets the governed nightly tell a ledger that never existed from one that was lost with every result carrying incidents (D00 T02 §38 item 4): with the ledger and all such results gone, the nightly reds instead of starting silently from empty.

Ledger started: 2026-09-25 (contract v2, first stamp 2026-09-25-000000)

When a ledger loss is intended (a deliberate reset), add a line `Reset: YYYY-MM-DD <reason>` below; a reset dated today or yesterday lets the next run start a fresh ledger.
