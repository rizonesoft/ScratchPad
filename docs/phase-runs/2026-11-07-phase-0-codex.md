# Phase 0 Codex plan run

Scope: whole implementation plan, resuming D00 T12 §3 from the operator-stopped 2026-11-06 run.

Session: 01a1b309-b8d2-7e92-a8f0-a5f368929f96. Writer: gpt-6-astra, medium.

Operator requested process plan in this fresh session. Inspected all ten dirty files and the closure handoff; preserve the physical-click implementation and prior evidence. Both guards are inactive. Graph: 34 TODOs, 352 sections, zero fatal; derived plan current at 160/306; provisioning 9/9; reviewer pin check passed. No prior interrupted review supplies approval.

The owning layer for the containment repair is the UI test harness, including owned-process cleanup and xUnit runner configuration. Obtain a returned plan review, prove cleanup and fail-fast without windows, then isolate each previously failing foreground case before larger scoped gates.

Resume evidence: current UiPointerGuardTests passed 40, failed 0, skipped 0 (build/d00-t12-s3-resume-guard-baseline.log). The headless two-failure fixture still ran both failures, exit 1 (build/d00-t12-s3-resume-stop-baseline.log). Read-only sonnet-researcher returned on claude-sonnet-5-5: PressKey assumes existing focus and the click helper never establishes or verifies foreground ownership; the old log does not prove why the click left Terminal foreground. No tracked delegate writes observed. The plan review is attached and pending, not approval. FlaUI v5.0.0 Application.Kill catches all exceptions and waits without a timeout, so the repair must explicitly prove owned-process exit rather than trusting Kill alone.

## Operator stop handoff

STOPPED 2026-11-06T22:56:45Z run=14dde00dde5947ec88e7ecf0cc4f7fa7 operator requested stop cleanly. Guard ended with operator-stop. No automatic resume.

Committed tip: 8c83cd2f8d5f8d01816c2eda81f93e2de10f5233, corrected containment contract and prior closure evidence. The second medium Argon plan review returned PLAN: complete, OVERALL: approve at that candidate (docs/cross-model-reviews/2026-11-07-d00-t12-s3-plan2.md); it remains uncommitted. No implementation or completion review has run. No section was stamped, flipped or pushed.

The original nine UI source changes are preserved unchanged. This session implemented no cleanup or runner fix and ran no foreground tests. Current guard baseline: 40 passed, zero failed or skipped. Headless stop fixture: both intentional failures executed, exit 1. Graph and provisioning passed. Full logs remain under build/d00-t12-s3-resume-*.log.

The read-only cleanup-inventory delegate was interrupted at operator stop before returning, so its empty output is not evidence. Earlier focus research is in build/d00-t12-s3-focus-research.json. Lead syntax inspection found 194 try/finally blocks calling the duplicate cleanup helpers; most return statements are inside nested lambdas, but StatusBarTests.SampleBulk has a real return and out-parameter assignment, requiring deliberate handling if execution wrappers are introduced. No migration was written. The reviewer summary's count of 13 helpers is not authoritative; the committed contract requires all duplicates, and a full inventory remains necessary.

Resume only on explicit operator instruction: implement the approved shared cleanup and failure-preservation contract, demonstrate red/green headless cleanup tests and deployed runner fail-fast, then dedicated MenuBar cursor proof and each formerly failing foreground case separately before larger scoped gates. Preserve original body failures, enforce owned-process identity and bounded exit confirmation, and never weaken input ownership guards.
