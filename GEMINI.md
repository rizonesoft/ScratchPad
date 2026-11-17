# GEMINI.md

Follow [AGENTS.md](./AGENTS.md). This file holds only what is specific to Google Antigravity (`agy`).

- You may write and commit as the active lead, the Carbon runner, just like Claude Code (operator decision 2026-11-17). Only one session owns the working tree at a time. Inspect status and existing changes when taking over. Your work is reviewed by GPT-6.2 Astra through Codex (`independent-review`, `--writer agy`); never review your own work or raise reviewer effort above medium.
- Your execution skills live in `.agents/skills/<name>/` (`add-todo`, `process-todo-section`, `process-phase`, `groom-plan`, `independent-review`). Use `scripts/agy_campaign.py` and follow `docs/writer-campaigns.md` for the guard, heartbeat, stop and handoff. Never operate the Claude guard or its state.
- Delegation in AGENTS.md names Claude Code's routed agents; on Antigravity use the Orchestrator's own built-in subagents for the same bounded read-only tasks, and keep all writes in the lead session.
- Use `.agents/skills/local-tool-safety` before local tool, Windows/WSL, connector, mail, cloud, SQL, or outbound work.
- Rules live in `.agents/rules/`.
