# Test exclusions

The exclusion ledger (D00 T02 §52 item 4): every UI test case the built binaries list that no governed leg selects (Run A, Run B, or the Interactive collection) needs one row here, beside the capability accounting in `docs/testing.md`.

The population gate (`tools/Test-TestPopulation.ps1` in CI, and the nightly's own population check) lists every case with a filter every test matches, subtracts the three legs' cases, and reds on any excluded case without a row, a row with no reason or owner, a review date that is not `YYYY-MM-DD` or has passed, a duplicate row, and a stale row for a case that is no longer excluded.

A row names the case exactly as `dotnet test --list-tests` lists it, why it is excluded, who owns the exclusion, and the date by which it is reviewed again (move the date only after a real review; select the case in a leg to retire the row).

| Case | Reason | Owner | Review by |
| ---- | ------ | ----- | --------- |
