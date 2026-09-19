# Clean-bin fixture (D00 T01 §41 item 8)

A fake `Bin/` holding one live project dir (`AcpLoopback`, matching a real stem) and one stale dir (`DefunctProject`, matching nothing). The marker files are text, never executed. Excluded from the conformance probe's no-bin scan (see `tools/check-bin-layout.py`). CI copies this tree aside and proves the clean script removes only the stale dir: `rm -rf /tmp/clean-proof && cp -r tests/Fixtures/clean-bin/Bin /tmp/clean-proof && python3 tools/clean-bin.py --bin-dir /tmp/clean-proof` (expect `DefunctProject` gone, `AcpLoopback` kept).
