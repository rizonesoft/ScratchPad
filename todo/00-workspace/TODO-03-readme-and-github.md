---
schema_version: 1
id: readme-and-github
domain: 00-workspace
status: draft
title: "TODO-03 -- README and GitHub Repo Face"
depends_on: []
track: W0
---

# TODO-03 -- README and GitHub Repo Face

> **Goal:** A stranger landing on github.com/rizonesoft/ScratchPad understands the project in thirty seconds, runs it from a fresh clone by following the README verbatim, and finds every repo-face file (badges, contributing guide, issue templates, license link, troubleshooting) where GitHub convention says it should be.

> [!IMPORTANT]
> **Current state:** `README.md` carries purpose prose, a layout table, toolchain pins, and build notes, but no screenshot, no badges, no quick start, no configuration section, no usage examples, no troubleshooting, no contributing link, and no license link. `LICENSE` (GPL-3.0) exists and is unlinked. `.github/` holds only `workflows/` (`build.yml`, `plan.yml`, `soak.yml`); there are no issue or PR templates and no `CONTRIBUTING.md`. `docs/` has operator docs (`bootstrap.md`, `build.md`, `testing.md`, `soak-and-quarantine.md`) but no `docs/assets/` and no screenshots. The capture store (`D00 T02 §3`) is shipped and the app builds on Windows (D01 spine), so real screenshots are capturable on a display host.

## Inputs

- [`README.md`](../../README.md) -- the file §2 rewrites; §1 fills its screenshot slot.
- [`LICENSE`](../../LICENSE) -- GPL-3.0, exists; §2 links it from the README status section.
- [`.github/workflows/`](../../.github/workflows/) -- `build.yml`, `plan.yml`, `soak.yml`; §2 badges them and §3 adds the setup-path job.
- [`docs/bootstrap.md`](../../docs/bootstrap.md), [`docs/build.md`](../../docs/build.md), [`docs/testing.md`](../../docs/testing.md) -- the troubleshooting and quick-start source material.
- [`global.json`](../../global.json) -- SDK pin `10.0.400` for the toolchain badge.
- -> XREF: D99 T01 §1 -- the operator-only companion (About bar, branch protection, taste pass, demo clip); it consumes this file's screenshots, README, and CI job.

**Groomed 2026-09-23:** Current state corrected: `.github/` holds `workflows/` (`build.yml`, `plan.yml`, `soak.yml`) plus `owner-logins.json`; there are no issue or PR templates.

## Outcome

- The README follows the full structure (purpose, badges, screenshot, audience, quick start, configuration, usage, troubleshooting, docs and contributing, status and license) and every command in it runs verbatim.
- The repo face is complete: badges render, `CONTRIBUTING.md` exists, issue and PR templates exist, the license is one click away.
- CI runs the README quick start verbatim on every push, so the instructions cannot rot silently.
- Reproducibility is stated and true: pins verified, `.env` correctly recorded as not applicable, a sample file seeds the first run.

**Adjacency:** all=not-applicable (docs-and-repo-face file: no runtime behavior, no settings, no lists, no permissions, no audit, nothing to reverse)

**Adjacency rationale:** This file changes words, images, and CI YAML. Nothing here executes at app runtime, stores user data, or gates an action, so none of the nine adjacency kinds apply.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | App screenshots captured for the README | D00 T02 §3 |  [ ]   |
|   2   |   §2    | README rewritten plus repo-face files | §1 |  [ ]   |
|   3   |   §3    | Setup-path CI plus reproducibility record | §2 |  [ ]   |

---

## 1. Visual Proof Capture

Why this section exists: the README needs visible proof, and proof means real pixels from the shipped app, not mockups. The capture store (D00 T02 §3) owns the how; this section owns the two README shots plus their provenance. -> SOURCE: operator-readme-brief-2026-09-18-t03-s1.

**Needs:** Windows host (build/test)

**Requires:** display-session -- app screenshots need rendered WinUI pixels: local capture returns black frames per D00 T02 §7 evidence, so a display-bearing Windows 11 session is required.

- [ ] The app builds on the display host from a clean checkout (`Bin/` empty first) and launches to the main window. Done when: the main window renders with tab bar and status bar visible to the eyeball probe.
- [ ] `docs/assets/readme-hero.png` captures the main window (tabs, editor with text, status bar) at no less than 1280 px wide. Done when: the file exists, opens as PNG, and shows app pixels rather than a black frame. Cheaper substitute that fails the checkpoint: a crop of the Notepad baseline capture.
- [ ] `docs/assets/readme-agent-panel.png` captures the agent panel beside the editor. Done when: the file exists and both surfaces read in one frame.
- [ ] `docs/assets/captures.md` records provenance for both shots: capture date, host, app commit, build configuration, and capture command. Done when: a second operator can reproduce either shot from the note alone.
- [ ] Commit: `"workspace: capture README screenshots with provenance (D00 T03 §1)"`

**Test checkpoint:** both PNGs exist under `docs/assets/`, each at least 1280 px wide with pixel variance proving non-black content, and `captures.md` names the app commit they were taken from. Cheaper substitute that fails: screenshots whose provenance nobody recorded.

## 2. README Rewrite Plus Repo-Face Files

Why this section exists: the current README has voice but no structure a stranger can act on. This section rewrites it to the full shape (name and purpose, badges, screenshot, audience and capabilities, quick start, configuration, usage, troubleshooting, docs and contributing, status and license), then lands the surrounding repo-face files so every link resolves. -> SOURCE: operator-readme-brief-2026-09-18-t03-s2.

- [ ] `README.md` opens with the one-sentence purpose, the audience and key capabilities, and the hero screenshot (`docs/assets/readme-hero.png`) above the fold. Done when: the first screen answers what it does and who it helps.
- [ ] `README.md` carries a badges row: `build.yml`, `plan.yml`, `soak.yml` workflow badges, a GPL-3.0 shields badge, a `.NET 10.0.400` shields badge matching `global.json`, and a Windows 11 platform badge. Done when: every badge URL returns 200 and the SDK badge matches the pin exactly, not "latest".
- [ ] `README.md` carries a quick start: the shortest complete route from fresh clone to running app on Windows, plus the Linux neutral lane (toolchain provision, neutral build, `todo-graph.py self-test`). Done when: each lane states its working directory and runs with no unexplained placeholders. **Corrected 2026-09-19:** the Linux neutral lane is retired (operator decision 2026-09-19: Windows-only CI and dev); the quick start is the Windows route only.
- [ ] `README.md` carries configuration (desktop app, no environment variables, settings live in the app), usage examples (open, edit, save, agent panel pointer), and troubleshooting (the common failures from `docs/bootstrap.md`, `docs/build.md`, `docs/testing.md`, each with its fix and no credentials). Done when: configuration states the `.env` non-applicability with its reason, and every troubleshooting fix names a command or a click path.
- [ ] `README.md` ends with documentation links (every `docs/*.md` entry point), a contributing pointer, project status (active build, pre-release), and a license link to `LICENSE`. Done when: no link 404s and the status reads as experimental-or-maintained honestly.
- [ ] `CONTRIBUTING.md` tells a contributor where work lives (`todo/`, the `process-todo-section` flow), the one-command build, and the gates before a PR (tests, `validate`, `plan --check`). Done when: a newcomer can go from clone to first PR without asking a question the file should answer.
- [ ] `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`, and `.github/PULL_REQUEST_TEMPLATE.md` exist with the fields the project needs (repro steps and build for bugs, plan ref for PRs). Done when: GitHub offers both templates on a new issue.
- [ ] README's Deferred and Layout sections match the shipped tree: the review scripts (`scripts/review_prompt.py`, `panel_slots.py`, `probe_runner.py`) ship and leave Deferred, and Layout lists `tools/`, `.claude/`, and `.conclave/`. Done when: each README path exists and each shipped top-level folder is listed (Groomed 2026-09-23.)
- [ ] Commit: `"workspace: rewrite README and land repo-face files (D00 T03 §2)"`

**Test checkpoint:** the README headings appear in the specified order, every badge URL returns 200, every internal link resolves to a file that exists, and the issue templates render on a new-issue dry run. Cheaper substitute that fails: a README whose links were never clicked.

## 3. Setup-Path CI Plus Reproducibility Record

Why this section exists: README instructions rot the moment nothing executes them. This section wires CI to run the §2 quick start verbatim on every push, re-verifies the pins the README claims, and records the reproducibility facts (no `.env`, lockfiles, sample data) so the first run is useful and success is recognizable. -> SOURCE: operator-readme-brief-2026-09-18-t03-s3.

- [ ] `.github/workflows/readme-check.yml` runs the §2 quick start verbatim: the Windows lane on a Windows runner, the Linux neutral lane on a Linux runner, each step copied from the README with no paraphrase. Done when: the workflow file quotes the same commands the README prints, and the Linux lane passes locally before push. **Corrected 2026-09-19:** the Linux neutral lane is retired (operator decision 2026-09-19: Windows-only CI); `readme-check.yml` runs the Windows lane only.
- [ ] The pins the README claims are re-verified: `global.json` still pins `10.0.400` with `rollForward: disable`, and every `PackageReference` in `src/` and `tests/` has a lockfile entry. Done when: a pin drift fails the check rather than shipping silently.
- [ ] The `.env` non-applicability is recorded as a checked fact, not a guess: no `src/`, `tests/`, or `docs/` path references `.env*` files. Done when: the grep proving it is quoted in the commit body.
- [ ] `resources/samples/welcome.txt` seeds the first run (a short note telling the user what to try first) and the README quick start points at it. Done when: a fresh clone opens the sample with content that orients, not lorem ipsum.
- [ ] Commit: `"workspace: CI the README setup path plus reproducibility record (D00 T03 §3)"`

**Test checkpoint:** the Linux lane of `readme-check.yml` runs verbatim locally with exit 0, the pin and `.env` checks pass with quoted output, and the review cites the CI run green on the SHIP push. Cheaper substitute that fails: a workflow that was pushed but never watched go green. **Corrected 2026-09-19:** the Linux lane is retired (operator decision 2026-09-19: Windows-only CI); the Windows lane runs verbatim locally with exit 0.

## Verification

- [ ] README headings match the specified structure in order, badges render, all links resolve.
- [ ] `readme-check.yml` is green on `main` for both lanes. **Corrected 2026-09-19:** Windows lane only (operator decision 2026-09-19: Windows-only CI); the Linux lane is retired.
- [ ] `python3 scripts/todo-graph.py validate` clean and `plan --check` current.
