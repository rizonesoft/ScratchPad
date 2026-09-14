# tests/Common

Shared test-only helpers live here so suites share fixtures without reaching into each other's projects.

Ownership rule: a helper starts in the suite that first needs it and moves to Common when a second suite needs it; Common gains its own classlib project with its first helper, not before. References run one way: suites may reference Common, Common never references a suite, and production code never references Common.
