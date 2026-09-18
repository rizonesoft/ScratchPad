---
schema_version: 1
id: operator-setup
domain: 99-manual
status: draft
title: "TODO-01 -- Operator Setup (Manual)"
depends_on: []
---

# TODO-01 -- Operator Setup (Manual)

> **Goal:** The GitHub-side setup no agent can perform is done by the operator following exact steps: the repo About bar, topics, and social preview are set, the `main` branch is protected with the real required checks, a cold-reader pass over the README files every gap as an issue, and a demo clip plays in the README.

> [!IMPORTANT]
> **Current state:** The repo lives at `github.com/rizonesoft/ScratchPad` with default Settings: no About description, no topics, no social preview, no branch protection. The agent-side work (screenshots, README, CI job) lands in D00 T03; every section here depends on the piece it consumes. Nothing in this file can run in an agent session: each section carries a `**Manual:**` line, its steps assume zero GitHub knowledge, and its proof is a screenshot or a public page the agent verifies afterward.

## Inputs

- [`README.md`](../../README.md) -- the §2 wording this file's About text and clip edit build on.
- [`docs/assets/`](../../docs/assets/) -- the §1 screenshots this file uploads from (social preview source).
- [`.github/workflows/`](../../.github/workflows/) -- the check names §2 requires.
- `https://github.com/rizonesoft/ScratchPad` -- every click path below starts here, logged in as the owner.
- -> XREF: D00 T03 §2 -- the agent-side companion that produces the README, screenshots, and CI job this file consumes.
- -> XREF: D00 T01 §42 -- the `Requires: operator` mark gating this file's rows; §§1-4 carry the mark once §42 ships.

## Outcome

- The repo page shows a description, topics, and a social preview image.
- `main` refuses direct pushes and merges without the required checks green.
- A cold-reader pass over the README exists as filed issues or an explicit no-gaps record.
- A demo clip plays in the README.

**Adjacency:** all=not-applicable (operator-click file: no runtime behavior, no settings surface, no lists, no permissions model, nothing to reverse)

**Adjacency rationale:** The work is GitHub Settings clicks plus proof screenshots. It creates no app behavior and no data, so none of the nine adjacency kinds apply.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | About bar, topics, social preview set | D00 T03 §2 |  [ ]   |
|   2   |   §2    | Branch protection with required checks | D00 T03 §3 |  [ ]   |
|   3   |   §3    | Cold-reader pass with gaps filed | D00 T03 §2 |  [ ]   |
|   4   |   §4    | Demo clip recorded and embedded | §1 |  [ ]   |

---

## 1. About Bar, Topics, and Social Preview

Why this section exists: the About bar is the repo's thirty-second pitch and the social preview is its face in every link unfurl. Both need the owner's logged-in session, and the preview needs the §1 hero shot committed first. -> SOURCE: operator-readme-brief-2026-09-18-t99-s1.

**Manual:** operator-only -- needs the owner's logged-in browser session; agents hold no GitHub credentials by design (AGENTS.md Credentials).

- [ ] The About description is set to the README one-liner. Done when: the repo page shows the description under the repo name.
  1. Open `https://github.com/rizonesoft/ScratchPad` in a browser where you are logged in as the owner.
  2. On the right side, find the `About` heading and click the gear icon beside it.
  3. In the `Description` field, paste the README one-liner: `Notepad, exact down to the status bar. Plus your AI agents. Minus the subscription nag.`
  4. Leave `Website` blank and click `Save changes`.
- [ ] The topics are set. Done when: the About bar lists all seven topics.
  1. Click the About gear icon again.
  2. In the `Topics` field, type each name and press Enter: `notepad`, `winui-3`, `dotnet`, `acp`, `ai-agents`, `windows-11`, `text-editor`.
  3. Click `Save changes`.
- [ ] The social preview shows the hero screenshot. Done when: the Settings social-preview box renders the hero image.
  1. Download the hero shot: open `https://github.com/rizonesoft/ScratchPad/raw/main/docs/assets/readme-hero.png` and save it to your machine (or copy it from your local clone).
  2. Open `https://github.com/rizonesoft/ScratchPad/settings`, scroll to `Social preview`, and click `Edit`.
  3. Click `Upload an image...`, pick the saved hero file, and click `Save`.
- [ ] Proof is captured in the repo. Done when: `docs/assets/setup-proof/phase99-s1-about.png` exists on `main` and shows the finished About bar.
  1. Screenshot the repo page About bar (description plus topics visible) and save it as `phase99-s1-about.png`.
  2. On GitHub, open the `docs/assets/setup-proof/` folder (create the folders with `Add file`, `Create new file`, typing `docs/assets/setup-proof/.gitkeep` first if the folder does not exist yet), click `Add file`, `Upload files`, drop the screenshot, and click `Commit changes`.
- [ ] Agent verification (agent-run, after your record commit below lands): the agent curls the public repo API and reads the proof image. Done when: the API quotes the description plus all seven topics and the proof image shows them.
- [ ] Commit: `"docs: record Phase 99 §1 completion with proof"` -- operator ticks every item above via the GitHub web editor (open this file, pencil icon, `- [ ]` to `- [x]` on each finished line, `Commit changes`); the agent appends its verification note in a second commit, and review stamps the range.

**Test checkpoint:** a logged-out browser on the repo page shows the description and topics, the social-preview box in Settings renders the hero, and the proof file exists on `main`. Cheaper substitute that fails: trusting the Settings form without reloading the public page.

## 2. Branch Protection with Required Checks

Why this section exists: `main` currently accepts anything, including a force-push. The rule below needs the real check names, which only exist once the §3 CI job has run, so the first item collects them from a live Actions run rather than guessing. -> SOURCE: operator-readme-brief-2026-09-18-t99-s2.

**Manual:** operator-only -- branch rules need owner admin clicks; agents hold no GitHub credentials by design (AGENTS.md Credentials).

- [ ] The exact check names are collected from a live run. Done when: you hold the list of check names from the newest `main` run.
  1. Open `https://github.com/rizonesoft/ScratchPad/actions` and click the newest completed run on `main`.
  2. Expand the jobs and write down every check name (the build, plan-check, soak, and readme-lane jobs), exactly as spelled.
- [ ] The `main` rule requires PRs plus green checks and blocks force-pushes. Done when: the rule page shows the rule active with every collected check required.
  1. Open `https://github.com/rizonesoft/ScratchPad/settings/branches` and click `Add classic branch protection rule`.
  2. In `Branch name pattern`, type `main`.
  3. Check `Require a pull request before merging` (leave the approvals count at 1).
  4. Check `Require status checks to pass before merging`, click `Add checks`, and add every name from the collected list, one by one.
  5. Check `Block force pushes` and leave `Allow deletions` unchecked.
  6. Click `Create` (or `Save changes`).
- [ ] Proof is captured in the repo. Done when: `docs/assets/setup-proof/phase99-s2-protection.png` exists on `main` and shows the active rule with its required checks.
  1. Screenshot the finished rule page and save it as `phase99-s2-protection.png`.
  2. Upload it to `docs/assets/setup-proof/` via `Add file`, `Upload files`, `Commit changes`, as in §1.
- [ ] Agent verification (agent-run, after your record commit below lands): the agent reads the proof image. Done when: the rule name, the required-checks list, and the force-push block all read in the image. (Branch rules are not public, so the image is the evidence.)
- [ ] Commit: `"docs: record Phase 99 §2 completion with proof"` -- operator ticks via the web editor and commits; the agent appends its verification note; review stamps the range.

**Test checkpoint:** the rule page shows `main` protected with the collected checks required, and pushing straight to `main` is refused (try it from a scratch clone and watch it fail). Cheaper substitute that fails: a rule page that was opened but never saved.

## 3. Cold-Reader Taste Pass

Why this section exists: the best README test is a stranger following it in a clean environment. The operator is that stranger here: every undocumented step, surprise error, and confusion becomes a filed issue, or the pass records explicitly that there were none. -> SOURCE: operator-readme-brief-2026-09-18-t99-s3.

**Manual:** operator-only -- needs human taste and a human-owned clean machine; an agent grading its own README proves nothing.

- [ ] The README quick start runs on a clean machine, exactly as written. Done when: you reach a running app (Windows lane) or a green neutral lane (Linux lane) with a written list of every surprise.
  1. Pick a machine or folder the project has never touched.
  2. Open the README on `main` and follow the quick start top to bottom: no skipping, no fixing from memory, no peeking at other docs.
  3. Write down every step that fails, confuses, or needs something the README never said, in a plain text file.
- [ ] Every surprise is a filed issue, or the pass records no gaps. Done when: each surprise has an issue URL, or the record says `no gaps` with the date.
  1. Open `https://github.com/rizonesoft/ScratchPad/issues` and click `New issue`.
  2. Pick the bug template for failures and the feature template for missing guidance; paste one surprise per issue with the README line it breaks.
  3. If nothing surprised you, write that down instead: `no gaps found <YYYY-MM-DD>`.
- [ ] The record lands in this section via the web editor. Done when: the issue URLs (or the no-gaps line) read under this item on `main`.
  1. Open this file on GitHub, click the pencil icon, and paste the issue URLs (or the no-gaps line) directly under this checklist item.
  2. Commit the edit (this is the record commit below; tick the boxes in the same edit).
- [ ] Agent verification (agent-run, after your record commit below lands): the agent checks every pasted issue URL over the public API, or confirms the no-gaps line. Done when: every URL resolves to an open issue, or the line is present.
- [ ] Commit: `"docs: record Phase 99 §3 completion with issue list"` -- operator ticks via the web editor and commits; the agent appends its verification note; review stamps the range.

**Test checkpoint:** the section on `main` names every surprise as a resolving issue URL, or carries a dated no-gaps line, and the quick start you ran is the one on `main`, not a draft. Cheaper substitute that fails: a pass run from memory instead of from the page.

## 4. Demo Clip Recorded and Embedded

Why this section exists: a playing demo beats a static screenshot for the premium feel, and recording one needs a human driving the app. The operator records a short clip with a free recorder, uploads it, and embeds it under the hero line. -> SOURCE: operator-readme-brief-2026-09-18-t99-s4.

**Manual:** operator-only -- needs a human driving the app on a display machine plus the owner's session for the upload.

- [ ] ScreenToGif is installed from the Microsoft Store. Done when: the app launches.
  1. Open the Microsoft Store on the Windows machine, search `ScreenToGif`, and install it.
  2. If the Store has no listing, download the latest release from its GitHub releases page and install that instead.
- [ ] A 15-to-30-second clip shows the app story: launch, type a line, open the agent panel. Done when: `demo.gif` plays the story end to end and stays under 10 MB so it renders inline.
  1. Launch ScreenToGif, pick `Recorder`, and drag the frame over the app window.
  2. Press record, launch the app, type one line, open the agent panel, then stop.
  3. Trim dead ends, save as `demo.gif`, and confirm the file is under 10 MB (lower the frame rate and re-save if not).
- [ ] The clip is uploaded and embedded under the hero line. Done when: the README on `main` plays the clip directly under the hero screenshot.
  1. Upload `demo.gif` to `docs/assets/` via `Add file`, `Upload files`, `Commit changes`.
  2. Open `README.md` on GitHub, click the pencil icon, find the hero image line (the one ending in `readme-hero.png`), and add directly under it: `![Demo](docs/assets/demo.gif)`.
  3. Commit the edit.
- [ ] Agent verification (agent-run, after your record commit below lands): the agent checks the file exists, stays under 10 MB, and is referenced exactly once. Done when: all three hold with quoted output.
- [ ] Commit: `"docs: record Phase 99 §4 completion with demo clip"` -- operator ticks via the web editor and commits; the agent appends its verification note; review stamps the range.

**Test checkpoint:** the README on `main` plays the clip under the hero image, and the clip file on `main` is under 10 MB. Cheaper substitute that fails: a clip that plays locally but was never uploaded.

## Verification

- [ ] The repo page shows description, topics, and social preview to a logged-out browser.
- [ ] `main` refuses direct pushes and merges without green required checks.
- [ ] The §3 record names resolving issues or a dated no-gaps line.
- [ ] The README on `main` plays the demo clip under the hero.
- [ ] `python3 scripts/todo-graph.py validate` clean and `plan --check` current.
