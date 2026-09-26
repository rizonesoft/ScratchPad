# Nightly host aliases

Host key continuity (D00 T02 §47 item 3). A result records its host as an 8-hex hash of the machine name (`hostKey`), never the name itself. When a host is renamed or reinstalled under a new name, add one row mapping the old key to the new one, so the trend keeps one history; the trend follows the chain to the current key. A cloned machine keeps its own name and so its own key: never alias two live machines together. Keys are the 8-hex values the results carry.

Rules (D00 T02 §54 item 1): an old key maps to exactly one new key (two rows for one old key with different targets are both refused); a cycle is refused; an optional `Effective` date makes the alias apply only to nights on or after it, so the old key keeps its earlier history; two old keys may map to one new key (a rename followed by a reinstall); and an old key that still reports results after its alias took effect is a clone, whose alias is refused so it stays a separate host. Refusals print in the trend and the morning report.

| Old key | New key | Reason | Effective |
| --- | --- | --- | --- |
