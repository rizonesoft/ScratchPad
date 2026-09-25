# Alert acknowledgements

Trend alerts on otherwise passing runs (D00 T02 §47 item 4): a duration shift or a recurring flake on green nights has no RED to acknowledge, so its owner acknowledges the alert here. The alert keeps its lifecycle (it still closes as recovered once the condition clears), reads `acknowledged` in `build/nightly/alerts.json`, and stops counting as unowned persistence. Name the alert identity exactly as the ledger records it (`<host key>|<series>` or `<host key>|<series>|INC-<id>`); an owner and a reason are required, and a placeholder owner is ignored.

| Alert | Owner | Date | Reason |
| --- | --- | --- | --- |
