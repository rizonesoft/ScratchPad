# Nightly host aliases

Host key continuity (D00 T02 §47 item 3). A result records its host as an 8-hex hash of the machine name (`hostKey`), never the name itself. When a host is renamed or reinstalled under a new name, add one row mapping the old key to the new one, so the trend keeps one history; the trend follows the chain to the current key. A cloned machine keeps its own name and so its own key: never alias two live machines together. Keys are the 8-hex values the results carry.

| Old key | New key | Reason |
| --- | --- | --- |
