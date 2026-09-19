# Bad-output fixture (D00 T01 §41 item 5)

One project overriding `BaseOutputPath` to its own directory: the project-level bypass PR7 names. Never built; the conformance probe excludes this tree from the default scan, and CI proves the probe fires here: `python3 tools/check-bin-layout.py conformance --root tests/Fixtures/bad-output` (expect exit 1 naming the shape violation; needs the SDK on PATH).
