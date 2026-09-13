---
schema_version: 1
id: repo-and-toolchain
domain: 00-workspace
status: draft
title: "TODO-01 -- Repo and Toolchain"
track: W0
---

# TODO-01 -- Repo and Toolchain

> **Goal:** A clean checkout builds the app and runs the tests with one command each, on a pinned Windows toolchain, with CI proving the same on every push.

> [!IMPORTANT]
> **Current state:** The repo holds only `todo/`, `scripts/`, `docs/`, and root docs. No source tree, no solution, no CI. The first section that touches a compiler decides the layout below; until then every path in this file is a proposal, not a fact.

## Inputs

- [Microsoft WinUI 3 setup docs](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/) -- SDK and workload requirements
- [`todo/README.md`](../README.md) -- the format this TODO's §7 gates in CI

## Outcome

- A clean Windows 11 checkout builds with one command and tests with one command.
- CI on a Windows runner builds and tests every push to `main`.
- Compiler warnings and static analysis gate the build, not a wiki page.
- The TODO graph's own checks run in CI so a broken plan fails the build.

**Adjacency:** all=not-applicable (toolchain and repo plumbing with no user-facing feature surface; the app surfaces it enables declare their own adjacency in their own files)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Repo layout and toolchain pin | -- |  [ ]   |
|   2   |   §2    | Solution scaffold with one-command build | §1 |  [ ]   |
|   3   |   §3    | CI on a Windows runner | §2 |  [ ]   |
|   4   |   §4    | Warning and analysis gates | §2 |  [ ]   |
|   5   |   §5    | CTest wiring and first smoke test | §2 |  [ ]   |
|   6   |   §6    | Developer bootstrap doc | §1 |  [ ]   |
|   7   |   §7    | TODO graph checks in CI | §3 |  [ ]   |

---

## 1. Repo Layout and Toolchain Pin

Why this section exists: every path, command, and gate below assumes a layout and a compiler. Pin both before anything else so later sections build on facts.

**Groomed 2026-09-13:** Operator decision: the toolchain is provisioned repo-local (script plus pins plus lockfiles), never system-dependent and never binaries in git.

**Needs:** Windows host (build/test)

- [ ] `README.md` records the layout (`src/`, `tests/`, `resources/`, `docs/`) and the pinned Windows SDK, MSVC, and CMake versions. Done when: the versions are exact numbers, not "latest".
- [ ] `src/` and `tests/` directories exist with a placeholder each so the layout is real before the scaffold lands. Done when: the tree matches the doc.
- [ ] `.gitignore` covers `build/`, `out/`, VS artifacts, and test output. Done when: a build leaves `git status` clean apart from intended files.
- [ ] `.gitattributes` pins line endings for the repo (CRLF for WinUI sources where the toolchain wants it, LF for scripts and markdown). Done when: a fresh clone shows no line-ending diffs.
- [ ] `tools/bootstrap.ps1` provisions the full toolchain into repo-local `.tools/` (gitignored): CMake, Ninja, vcpkg, and NuGet packages live there entirely, while MSVC and the Windows SDK pin to exact versions the script installs or verifies, since the vendor requires machine install. Done when: the layout doc names every component's home and no build step reads outside the repo plus the pinned install.
- [ ] Every version floats nowhere: compiler, SDK, CMake, Ninja, vcpkg baseline, and NuGet packages pin to exact versions or lockfiles with hashes verified at provision time. Done when: deleting `.tools/` and re-provisioning reproduces the identical toolchain, proven by version output.
- [ ] Commit: `"workspace: pin repo layout and toolchain"`

**Test checkpoint:** A reviewer on a second machine confirms the pinned versions install the documented workload; `git status` is clean after listing the tree. Falsifiable by any version that does not resolve or any path the doc names that does not exist.

## 2. Solution Scaffold with One-Command Build

Why this section exists: the scaffold is the first thing that compiles. One command, no IDE required, so CI and humans build the same bytes.

**Needs:** Windows host (build/test)

- [ ] `src/IntelligentNotepad.sln` (or the CMake equivalent chosen in §1) builds a stub WinUI 3 app that opens an empty window. Done when: the stub launches on Windows 11.
- [ ] `docs/build.md` gives the single build command and its prerequisites. Done when: following it on a clean machine produces the stub.
- [ ] The stub reports its own version and toolchain in an About surface or log line. Done when: the provenance of a binary is answerable from the binary.
- [ ] Build outputs land under `build/` (gitignored) and never beside sources. Done when: `git status` is clean after a full build.
- [ ] Commit: `"workspace: scaffold solution with one-command build"`

**Test checkpoint:** Clean-machine build with the documented command exits 0 and the stub window launches; `git status` shows no build outputs. Cheaper substitute that fails: a solution that builds only inside the IDE on the author's machine.

## 3. CI on a Windows Runner

Why this section exists: without CI the toolchain pin rots and "works on my machine" becomes the build system.

- [ ] `.github/workflows/build.yml` (or the chosen CI) runs the §2 build command on a Windows runner for every push to `main`. Done when: a push shows a green build run.
- [ ] CI uploads the built stub as an artifact. Done when: the binary is downloadable from the run.
- [ ] CI fails the run when the build fails, with the log naming the failing step. Done when: a deliberately broken commit (reverted immediately) shows red for the right reason.
- [ ] The workflow pins its runner image and tool versions. Done when: no `latest` floats the build.
- [ ] Commit: `"workspace: run the build on a Windows runner"`

**Test checkpoint:** Push a commit and read the run: green on good code, red-with-cause on a deliberately broken probe commit. Cheaper substitute that fails: a workflow that exists but never ran, or runs on Linux where the app cannot build.

## 4. Warning and Analysis Gates

Why this section exists: warnings are defects with seniority. Gate them at zero from the first compile so the count never has a legacy tail.

**Needs:** Windows host (build/test)

- [ ] The build treats warnings as errors at `/W4` (or the chosen level) for project code. Done when: an unused-variable probe fails the build.
- [ ] Static analysis (MSVC `/analyze` or clang-tidy, chosen here) runs in CI with a committed ruleset. Done when: the ruleset file is in the repo and CI runs it.
- [ ] Third-party and generated code are excluded by path, not by blanket suppression. Done when: the exclusion list names paths.
- [ ] Analysis findings block the build; the doc records how to run the same analysis locally. Done when: a probe finding fails CI and the local command reproduces it.
- [ ] Commit: `"workspace: gate warnings and static analysis"`

**Test checkpoint:** An unused-variable probe fails the build and a probe analysis finding fails CI; both reproduce locally with documented commands. Cheaper substitute that fails: warnings counted in a dashboard nobody reads.

## 5. CTest Wiring and First Smoke Test

Why this section exists: the test command must exist before the first real test, so every later section has somewhere to put its proof.

**Needs:** Windows host (build/test)

- [ ] `ctest --test-dir build --output-on-failure` runs the suite (empty-but-green counts today). Done when: the command exits 0 on a clean checkout.
- [ ] One smoke test asserts the stub app object constructs and reports its version. Done when: `ctest -R Smoke` passes and fails if the version string is blanked.
- [ ] CI runs the test command after the build and fails the run on test failure. Done when: a deliberately failing probe test (reverted immediately) shows red.
- [ ] Test output (logs, captures) lands under `build/` and never in the source tree. Done when: `git status` is clean after a full test run.
- [ ] Commit: `"workspace: wire CTest with a first smoke test"`

**Test checkpoint:** `ctest --test-dir build --output-on-failure` exits 0; blanking the version string turns it red; CI mirrors both. Cheaper substitute that fails: a test project that builds but whose tests CI never runs.

## 6. Developer Bootstrap Doc

Why this section exists: the second developer (or a fresh agent session) should reach a green build without asking anyone anything.

**Groomed 2026-09-13:** Operator decision: script-first bootstrap; the doc explains, the script provisions.

**Needs:** Windows host (build/test)

- [ ] `docs/bootstrap.md` lists prerequisites with versions, install order, and the build and test commands. Done when: a cold reader reaches green without improvising.
- [ ] The doc records the Windows-only boundary: what runs on Windows, and what (scripts, plan checks) runs anywhere. Done when: a Linux reader knows exactly which commands are theirs.
- [ ] The doc links the troubleshooting entries for the two most common bootstrap failures found while writing it. Done when: each entry was reproduced and fixed, not imagined.
- [ ] Bootstrap is script-first: a cold follow runs `tools/bootstrap.ps1` and reaches a green build with no manual installs, while `docs/bootstrap.md` explains what the script does. Done when: the script plus doc together pass the checkpoint with zero improvisation.
- [ ] Commit: `"workspace: write the developer bootstrap doc"`

**Test checkpoint:** A cold follow of the doc on a clean machine reaches a green build and test run. Falsifiable by any step that does not work as written.

## 7. TODO Graph Checks in CI

Why this section exists: the plan is load-bearing, so a broken plan must fail the build like any other defect.

- [ ] CI runs `python3 scripts/todo-graph.py self-test` on every push touching `scripts/` or `todo/`. Done when: the run shows the case count and zero failures.
- [ ] CI runs `python3 scripts/todo-graph.py validate` on the same pushes. Done when: a probe FATAL (reverted immediately) fails the run.
- [ ] CI runs `python3 scripts/todo-graph.py plan --sync` followed by a clean-tree check (or `plan --check` once the JSON paths are committed), so a stale projection fails the run. Done when: a hand-flipped plan box fails the run.
- [ ] The workflow triggers only on relevant paths so doc edits do not pay for graph checks. Done when: a docs-only push skips the job.
- [ ] Commit: `"workspace: gate the TODO graph in CI"`

**Test checkpoint:** Probe commits prove each of the three checks fails the run for the right reason; all probes reverted. Cheaper substitute that fails: checks that run but whose failures do not fail the run.

## Verification

- [ ] Clean-machine build and test both green from the docs alone
- [ ] CI green on `main` with all gates enforcing
- [ ] `python3 scripts/todo-graph.py validate` clean
