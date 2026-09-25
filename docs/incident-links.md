# Incident links

Triage records the finding each nightly incident was filed under (D00 T02 §30 item 7). The governed nightly copies each link onto its incident in the ledger (`build/nightly/incidents.json`) and the result JSON's `incidentLifecycle` block, and re-lists every open incident with no link in each morning report until one is recorded here.

A row names the incident id and its finding: a TODO section (`DNN TNN §N`) or a commit. Add rows with `powershell -NoProfile -ExecutionPolicy Bypass -File tools/NightlyLedger.ps1 -Link <INC-id> -Finding <ref>` (D00 T02 §38 item 9): the same link twice writes once and a conflicting link refuses.

| Incident | Finding | Note |
| --- | --- | --- |
