---
schema_version: 1
id: repo-and-toolchain
domain: 00-workspace
status: draft
title: "TODO-01 -- Repo and Toolchain"
track: W0
---

# TODO-01 -- Repo and Toolchain

> **Goal:** A clean checkout builds the app and runs the tests with one command each, on a pinned .NET toolchain, with CI proving the same on Linux and Windows runners on every push.

> [!IMPORTANT]
> **Current state:** The repo holds only `todo/`, `scripts/`, `docs/`, and root docs. No source tree, no solution, no CI. The first section that touches the .NET SDK decides the layout below; until then every path in this file is a proposal, not a fact.

## Inputs

- [Windows App SDK and WinUI 3 docs for .NET](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/) -- WinUI 3 with .NET: SDK and workload requirements
- [`todo/README.md`](../README.md) -- the format this TODO's §7 gates in CI

## Outcome

- A clean checkout builds with one command and tests with one command, on Linux or Windows.
- CI on Linux and Windows runners builds and tests every push to `main`.
- Compiler warnings and static analysis gate the build, not a wiki page.
- The TODO graph's own checks run in CI so a broken plan fails the build.

**Adjacency:** all=not-applicable (toolchain and repo plumbing with no user-facing feature surface; the app surfaces it enables declare their own adjacency in their own files)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Repo layout and toolchain pin | -- |  [x]   |
|   2   |   §2    | Solution scaffold with one-command build | §1 |  [ ]   |
|   3   |   §3    | CI on Linux and Windows runners | §2 |  [ ]   |
|   4   |   §4    | Warning and analysis gates | §2 |  [ ]   |
|   5   |   §5    | Test wiring and first smoke test | §2 |  [ ]   |
|   6   |   §6    | Developer bootstrap doc | §1 |  [ ]   |
|   7   |   §7    | TODO graph checks in CI | §3 |  [ ]   |

---

## 1. Repo Layout and Toolchain Pin

> **Started:** 2026-09-13T21:14:39Z

Why this section exists: every path, command, and gate below assumes a layout and an SDK. Pin both before anything else so later sections build on facts.

**Groomed 2026-09-13:** Operator decision: the toolchain is provisioned repo-local (script plus pins plus lockfiles), never system-dependent and never binaries in git.

**Replatformed 2026-09-13:** C# on .NET 10, the steward stack. The .NET SDK installs repo-local, so no machine install exists anywhere in this file; MSVC/CMake/CTest assumptions are replaced throughout.

- [x] `README.md` records the layout (`src/`, `tests/`, `resources/`, `docs/`) and the pins: the .NET SDK (`global.json`), the Windows App SDK, and the test packages. Done when: the versions are exact numbers, not "latest".
- [x] `src/` and `tests/` directories exist with a placeholder each so the layout is real before the scaffold lands. Done when: the tree matches the doc.
- [x] `.gitignore` covers `bin/`, `obj/`, `dist/`, `TestResults/`, `.tools/`, and VS artifacts. Done when: a build plus a test run leaves `git status` clean apart from intended files.
- [x] `.gitattributes` pins line endings for the repo (CRLF for WinUI sources where the toolchain wants it, LF for scripts and markdown). Done when: a fresh clone shows no line-ending diffs.
- [x] `tools/provision.sh` (Linux) and `tools/provision.ps1` (Windows) install the pinned .NET SDK into repo-local `.tools/` (gitignored), with NuGet packages restored per project from lockfiles. Done when: the layout doc names every component's home and no build step reads outside the repo.
- [x] Every version floats nowhere: the .NET SDK (`global.json`), the Windows App SDK, and NuGet packages (lockfiles) pin to exact versions with hashes verified at provision time. Done when: deleting `.tools/` and re-provisioning reproduces the identical toolchain, proven by version output. **Clarified 2026-09-13:** no project exists yet, so package lockfiles materialize with the first `PackageReference`s in §2; the chosen versions are recorded in `README.md` now and verified to exist on NuGet today.
- [x] Commit: `"workspace: pin repo layout and toolchain"`

**Test checkpoint:** Wipe `.tools/`, re-run the provisioner for the session OS, and confirm `dotnet --info` reproduces the pinned versions; `git status` is clean after listing the tree. Falsifiable by any version that does not resolve or any path the doc names that does not exist.

> **Verified:** 2026-09-13 | §1 | wipe+provision reproduces SDK 10.0.401/runtime 10.0.12 from repo-local .tools (Linux twice, Windows via interop once); pinned test trio restores+builds clean; fresh clones clean on Linux+Windows; validate 0 fatal; self-test 391/391
> **Review:** rounds 2, candidates a5daf42 52a4218 -- `adversarial` approve · `consistency` approve (round-1 needs-attention on the exec bit, fixed) · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s1.md
> **CRUD:** applicable | provisioners wrote the SDK tree and read it back via SHA512 verify plus dotnet --info/--list-sdks; repo files written and read back via git status and fresh clones on both OSes
> **Duration:** 17
> **Implementer:** Muse Code (Meta Muse Spark)

## 2. Solution Scaffold with One-Command Build

Why this section exists: the scaffold is the first thing that compiles. One command, no IDE required, so CI and humans build the same bytes.

**Needs:** Windows host (build/test)

- [ ] `src/IntelligentNotepad.slnx` holds the stub WinUI 3 app (`net10.0-windows10.0.19041.0`) plus the neutral `Notepad.Core`, `Notepad.Acp`, and `Notepad.Agents` libraries, and `dotnet build` compiles it all. Done when: the build is green from Linux and the stub launches on Windows 11.
- [ ] `docs/build.md` gives the single build command and its prerequisites. Done when: following it on a clean machine produces the stub.
- [ ] The stub reports its own version and toolchain in an About surface or log line, with the commit stamped via `SourceRevisionId`. Done when: the provenance of a binary is answerable from the binary.
- [ ] Build outputs land under per-project `bin/` and `obj/` (gitignored) and publish output under `dist/` (gitignored), never beside sources. Done when: `git status` is clean after a full build.
- [ ] Commit: `"workspace: scaffold solution with one-command build"`

**Test checkpoint:** `dotnet build` exits 0 from a Linux checkout and the stub window launches on Windows; `git status` shows no build outputs. Cheaper substitute that fails: a solution that builds only inside the IDE on the author's machine.

## 3. CI on Linux and Windows Runners

Why this section exists: without CI the toolchain pin rots and "works on my machine" becomes the build system.

- [ ] `.github/workflows/build.yml` (or the chosen CI) runs the §2 build plus the neutral test suites on a Linux runner, and the full build plus UI suites on a Windows runner, for every push to `main`. Done when: a push shows green runs on both.
- [ ] CI uploads the built stub as an artifact. Done when: the binary is downloadable from the run.
- [ ] CI fails the run when the build fails, with the log naming the failing step. Done when: a deliberately broken commit (reverted immediately) shows red for the right reason.
- [ ] The workflow pins its runner images and action versions, with the SDK version governed by `global.json`. Done when: no `latest` floats the build.
- [ ] Commit: `"workspace: run the build on Linux and Windows"`

**Test checkpoint:** Push a commit and read both runs: green on good code, red-with-cause on a deliberately broken probe commit. Cheaper substitute that fails: a workflow that exists but never ran, or UI suites running anywhere but a Windows runner.

## 4. Warning and Analysis Gates

Why this section exists: warnings are defects with seniority. Gate them at zero from the first compile so the count never has a legacy tail.

- [ ] The build treats warnings as errors (`TreatWarningsAsErrors` plus `EnforceCodeStyleInBuild` in `Directory.Build.props`, steward pattern) for project code. Done when: an unused-variable probe fails the build.
- [ ] Roslyn analysis (`AnalysisLevel` latest) runs in CI with the committed `.editorconfig` ruleset. Done when: the ruleset file is in the repo and CI runs it.
- [ ] Third-party and generated code are excluded by path, not by blanket suppression. Done when: the exclusion list names paths.
- [ ] Analysis findings block the build; the doc records how to run the same analysis locally. Done when: a probe finding fails CI and the local command reproduces it.
- [ ] Commit: `"workspace: gate warnings and static analysis"`

**Test checkpoint:** An unused-variable probe fails the build and a probe analysis finding fails CI; both reproduce locally with documented commands. Cheaper substitute that fails: warnings counted in a dashboard nobody reads.

## 5. Test Wiring and First Smoke Test

Why this section exists: the test command must exist before the first real test, so every later section has somewhere to put its proof.

- [ ] `dotnet test` runs the suite (empty-but-green counts today). Done when: the command exits 0 on a clean checkout.
- [ ] One smoke test asserts the neutral core constructs and reports its version. Done when: `dotnet test --filter Smoke` passes on Linux and fails if the version string is blanked.
- [ ] CI runs the test command after the build and fails the run on test failure. Done when: a deliberately failing probe test (reverted immediately) shows red.
- [ ] Test output (logs, captures) lands under `TestResults/` (gitignored) and never in the source tree. Done when: `git status` is clean after a full test run.
- [ ] Commit: `"workspace: wire dotnet test with a first smoke test"`

**Test checkpoint:** `dotnet test` exits 0; blanking the version string turns it red; CI mirrors both. Cheaper substitute that fails: a test project that builds but whose tests CI never runs.

## 6. Developer Bootstrap Doc

Why this section exists: the second developer (or a fresh agent session) should reach a green build without asking anyone anything.

**Groomed 2026-09-13:** Operator decision: script-first bootstrap; the doc explains, the script provisions.

**Needs:** Windows host (build/test)

- [ ] `docs/bootstrap.md` lists prerequisites with versions, install order, and the build and test commands. Done when: a cold reader reaches green without improvising.
- [ ] The doc records the OS boundary: `dotnet build` and neutral `dotnet test` run anywhere, while app launch, UI suites, captures, and packaging run on Windows. Done when: a Linux reader knows exactly which commands are theirs.
- [ ] The doc links the troubleshooting entries for the two most common bootstrap failures found while writing it. Done when: each entry was reproduced and fixed, not imagined.
- [ ] Bootstrap is script-first: a cold follow runs `tools/provision.sh` (Linux) or `tools/provision.ps1` (Windows) and reaches a green build with no manual installs, while `docs/bootstrap.md` explains what the script does. Done when: the script plus doc together pass the checkpoint with zero improvisation.
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
