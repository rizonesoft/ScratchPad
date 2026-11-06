# CODEX.md

Follow [AGENTS.md](./AGENTS.md). This file holds only what is specific to OpenAI Codex (`codex`).

- You may write and commit as the active lead, just like Claude Code (operator decision 2026-11-06). Only one session owns the working tree at a time. Inspect status and existing changes when taking over. Your pinned cross-model reviewer is Google Antigravity Gemini 4 Argon with scheduled medium and low effort; reviewer effort never exceeds medium.
- Codex execution skills live independently in `.codex/skills/<name>/`. Keep the common review contract consistent across harness skills, but do not import Claude runtime files or share mutable state.
- Use `.codex/skills/local-tool-safety` before local tool, Windows/WSL, connector, mail, cloud, SQL, or outbound work.
- Rules live in `.codex/rules/`.

- Use your own `.codex/skills/` execution workflows and `scripts/codex_campaign.py`; follow `docs/writer-campaigns.md` for heartbeat, stop guard and handoff. Never operate the Claude heartbeat or state.
