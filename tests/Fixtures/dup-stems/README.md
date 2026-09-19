# Duplicate-stem fixture (D00 T01 §41 item 2)

Two projects sharing the `Foo` stem. Never built, never in any solution; the stems guard excludes this tree from the default scan (see `tools/check-bin-layout.py`), and CI proves the guard fires here: `python3 tools/check-bin-layout.py stems --root tests/Fixtures/dup-stems` (expect exit 1 naming the collision).
