# CODEX.md

Follow [AGENTS.md](./AGENTS.md). This file holds only what is specific to OpenAI Codex (`codex`).

- In ScratchPad you only review. Claude Code is the only writer (AGENTS.md, operator decision 2026-09-23): run read-only, and never edit, stage, or commit.
- Skills live in `.codex/skills/<name>/` (with `agents/openai.yaml` metadata) and are mirrored as real files in `.agents/skills/<name>/` and `.claude/skills/<name>/`. Change all three together.
- Use `.codex/skills/local-tool-safety` before local tool, Windows/WSL, connector, mail, cloud, SQL, or outbound work.
- Rules live in `.codex/rules/`.
