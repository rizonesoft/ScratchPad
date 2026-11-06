---
name: independent-review
description: "Run ScratchPad's required pinned review cycle: medium plan, medium adversarial, low follow-ups, medium completion last. Claude uses Codex Astra; Codex uses Antigravity Argon."
---

# Independent review

The active writer owns fixes. The reviewer is read-only and comes only from `.conclave/reviewers.toml`. Claude work goes to GPT-6 Astra through Codex. Codex work goes to Gemini 4 Argon through Antigravity. There is one reviewer, no fallback, and no Claude review. Never raise effort above medium. Historical records are evidence, not permission to run an old high-effort policy.

## Cycle

1. Commit the corrected section contract or design before implementation. Use `docs/plan-review-prompt.md` to prepare a scratch prompt naming that exact commit, the section, dependencies and governing documents. Begin a new findings file under `docs/cross-model-reviews/`. Run `python scripts/review-dispatch.py --writer <claude|codex> --writer-model <exact-author-model> --kind plan --candidate <full-sha> --prompt <scratch-prompt> --record <findings>`. This pass runs at medium. Verify all findings and correct the contract before building. If the returned plan has gaps, start a new reviewed plan cycle after fixing them; preserve the previous findings.
2. Implement, run the feature's gates, review your own diff, and commit the candidate. Build a round prompt from `docs/review-round-prompt.md` naming the candidate and requirements. Run the same dispatcher with `--kind round` (omit `--candidate`, put the exact candidate in the prompt). The first adversarial pass runs at medium. Keep the writer identity, exact model and findings file unchanged for this cycle.
3. Verify findings, fix every real in-scope issue in new commits, and run affected gates. Repeat `--kind round` using the updated candidate prompt. The dispatcher selects low effort after the first returned round and enforces the eight-low-round cap. Stop rounds when clean; never treat an outage or exhausted budget as approval. Record dispositions for findings without modifying the sealed review text. P3 findings still need disposition and cheap real fixes are done now.
4. Run `--kind completion --candidate <final-full-sha>` with `docs/completion-review-prompt.md`, the same writer and findings file. Completion is medium and last. Only a complete result with resolved findings permits the verification stamp. A completion gap starts a new repair cycle; do not append new rounds after completion.

Use the current writer model reported by the session. Do not invent a model id. The dispatcher requires the policy to be committed and binds the review lineage to it. Exit 1 is no review; exit 2 is refusal. Neither is approval. Do not bypass the dispatcher, raise effort, ask the reviewer to write, or share credentials. Keep the invocation attached to a tool session and poll it; do not detach it into a fire-and-forget shell job.

The JSON output and sealed findings file are the evidence. Put review prompts and full tool logs in ignored `build/`; keep the canonical findings in `docs/cross-model-reviews/`.
