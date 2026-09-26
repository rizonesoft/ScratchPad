# Alert acknowledgements

Trend alerts on otherwise passing runs (D00 T02 §47 item 4): a duration shift or a recurring flake on green nights has no RED to acknowledge, so its owner acknowledges the alert here. The alert keeps its lifecycle (it still closes as recovered once the condition clears), reads `acknowledged` in `build/nightly/alerts.json`, and stops counting as unowned persistence. Name the alert identity exactly as the ledger records it (`<host key>|<series>` or `<host key>|<series>|INC-<id>`); an owner and a reason are required, and a placeholder owner is ignored. As with a run ack, a row counts only once committed: the acknowledgement gate (`Test-Acknowledgements`, which the nightly and `tools/NightlyAck.ps1` run) lists each open alert as acknowledged or unowned, and a row still only in the working copy as pending.

Rules (D00 T02 §54 items 3, 4): the latest dated row for an alert governs (a revision keeps its alert); an ack covers an alert occurrence only when dated on or after the night that occurrence began, so a new regression after the ack stays unowned; an optional `until YYYY-MM-DD` fifth cell is the ack's deadline; the ack binds the magnitude it was given at, and a recurrence materially worse than that reads unowned again; an ack never marks an alert recovered. Only the committed file counts.

| Alert | Owner | Date | Reason | Until |
| --- | --- | --- | --- | --- |
