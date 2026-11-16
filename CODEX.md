# CODEX.md

Follow [AGENTS.md](./AGENTS.md). This file holds only what is specific to OpenAI Codex (`codex`).

- In ScratchPad you only review, read-only: never edit, stage, or commit (operator decision 2026-11-17). Claude Code or Antigravity owns the working tree. You review their work as GPT-6 Astra through `scripts/review-dispatch.py`, in a read-only sandbox, at the effort the pin in `.conclave/reviewers.toml` schedules; never above medium.
- Codex has no campaign runtime here: no hooks, no guard, no TODO execution skills.
- Use `.codex/skills/local-tool-safety` before local tool, Windows/WSL, connector, mail, cloud, SQL, or outbound work.
- Rules live in `.codex/rules/`.
