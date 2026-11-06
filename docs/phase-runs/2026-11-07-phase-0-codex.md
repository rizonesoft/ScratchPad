# Phase 0 Codex plan run

Scope: whole implementation plan, resuming D00 T12 §3 from the operator-stopped 2026-11-06 run.

Session: 01a1b309-b8d2-7e92-a8f0-a5f368929f96. Writer: gpt-6-astra, medium.

Operator requested process plan in this fresh session. Inspected all ten dirty files and the closure handoff; preserve the physical-click implementation and prior evidence. Both guards are inactive. Graph: 34 TODOs, 352 sections, zero fatal; derived plan current at 160/306; provisioning 9/9; reviewer pin check passed. No prior interrupted review supplies approval.

The owning layer for the containment repair is the UI test harness, including owned-process cleanup and xUnit runner configuration. Obtain a returned plan review, prove cleanup and fail-fast without windows, then isolate each previously failing foreground case before larger scoped gates.

Resume evidence: current UiPointerGuardTests passed 40, failed 0, skipped 0 (build/d00-t12-s3-resume-guard-baseline.log). The headless two-failure fixture still ran both failures, exit 1 (build/d00-t12-s3-resume-stop-baseline.log). Read-only sonnet-researcher returned on claude-sonnet-5-5: PressKey assumes existing focus and the click helper never establishes or verifies foreground ownership; the old log does not prove why the click left Terminal foreground. No tracked delegate writes observed. The plan review is attached and pending, not approval. FlaUI v5.0.0 Application.Kill catches all exceptions and waits without a timeout, so the repair must explicitly prove owned-process exit rather than trusting Kill alone.
