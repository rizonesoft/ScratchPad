# Switchable writer implementation

1. Compare Steward, Recto and JMR reference mechanics and verify installed hook/queue capabilities.
2. Port and test the completion-last dispatcher and medium ceiling; verify real Antigravity output.
3. Implement independently owned Claude and Codex campaign runtimes, heartbeat and stop hooks, with regression coverage.
4. Update each harness workflow, remove the superseded Opus-only gate, and document handoff and native hook trust.
5. Run scoped checks, review the complete diff with Antigravity, fix findings, and report remaining activation limits honestly.

## Acceptance evidence

- `scripts/review-dispatch.py`, `.conclave/reviewers.toml`, and `scripts/tests/test_review*.py`: done when routes reject self-review and Claude review, the schedule is medium/medium/low/medium-last, failed executions spend no round, plan gaps cannot start rounds, and runtime effort never exceeds medium.
- `scripts/codex_campaign.py`, `scripts/claude_campaign.py`, `.codex/hooks.json`, `.claude/settings.json`, and `scripts/tests/test_campaign_runtime.py`: done when the same lifecycle fixtures pass independently, only one writer acquires, stale generations cannot resume, operator interruption defeats a held lock, owner death stops Codex's worker, and a live review does not trigger a stall.
- `AGENTS.md`, `CODEX.md`, `GEMINI.md`, harness-local execution skills and `docs/writer-campaigns.md`: done when both writers have complete local workflows, the former mandatory Opus review is removed, and heartbeat acquisition, cancellation, handoff and native hook trust are documented without claiming untested activation.
- Focused commands are `python -m unittest discover -s scripts/tests -p 'test_review*.py'`, `python -m unittest discover -s scripts/tests -p test_campaign_runtime.py`, `python scripts/agent_routing.py check`, `python scripts/todo-graph.py validate`, and `python scripts/todo-graph.py plan --check`. Keep full logs in `build/review-switch/` and record independent review outcomes separately from test results.
