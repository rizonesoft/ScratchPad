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
|   2   |   §2    | Solution scaffold with one-command build | §1 |  [x]   |
|   3   |   §3    | CI on Linux and Windows runners | §2 |  [x]   |
|   4   |   §4    | Warning and analysis gates | §2 |  [x]   |
|   5   |   §5    | Test wiring and first smoke test | §2 |  [x]   |
|   6   |   §6    | Developer bootstrap doc | §1 |  [x]   |
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

> **Started:** 2026-09-13T21:32:35Z

Why this section exists: the scaffold is the first thing that compiles. One command, no IDE required, so CI and humans build the same bytes.

**Needs:** Windows host (build/test)

**Decided 2026-09-13:** unpackaged stub (`WindowsPackageType=None`); MSIX stays D07 T01 §1. Framework-dependent: the host carries WindowsAppRuntime 2.x and `docs/build.md` records the runtime prerequisite.
**Decided 2026-09-13:** stub version 0.0.0+sha (D07 owns release versions); TargetPlatformMinVersion 10.0.17763.0 per the Microsoft template. Provision dirs become `.tools/dotnet-<rid>` so both SDKs coexist in one checkout (§1's per-OS checkpoint unaffected; the shipped §1 body stays untouched).

- [x] `src/IntelligentNotepad.slnx` holds the stub WinUI 3 app (`net10.0-windows10.0.19041.0`, unpackaged) plus the neutral `Notepad.Core`, `Notepad.Acp`, and `Notepad.Agents` libraries (`net10.0`), with `src/Notepad.Neutral.slnf` filtering the neutral scope. Done when: `dotnet build` on the slnf is green from Linux, `dotnet build` on the slnx is green on Windows, and the stub launches on Windows 11. **Corrected 2026-09-13:** was "dotnet build compiles it all, green from Linux"; the XAML compiler cannot complete on Linux (spike: 1.8-line codegen absent with CS5001/CS0103, 2.4.0 fails WMC1006 on BCL resolution), so Linux builds the neutral filter and Windows builds all.
- [x] `docs/build.md` gives the single build command and its prerequisites. Done when: following it on a clean machine produces the stub. **Corrected 2026-09-13:** one command per OS (slnf on Linux, slnx on Windows); the doc names both plus the provision and runtime prerequisites.
- [x] The stub reports its own version and toolchain in an About surface or log line, with the commit stamped via `SourceRevisionId`. Done when: the provenance of a binary is answerable from the binary.
- [x] Build outputs land under per-project `bin/` and `obj/` (gitignored) and publish output under `dist/` (gitignored), never beside sources. Done when: `git status` is clean after a full build.
- [x] Commit: `"workspace: scaffold solution with one-command build"`

**Test checkpoint:** `dotnet build src/Notepad.Neutral.slnf` exits 0 on Linux; `dotnet build src/IntelligentNotepad.slnx` exits 0 on Windows and the stub window launches with its versioned title observed; `git status` shows no build outputs. Cheaper substitute that fails: a solution that builds only inside the IDE on the author's machine. **Corrected 2026-09-13:** per-OS commands per the item-1 correction; was bare `dotnet build` green from Linux.

> **Verified:** 2026-09-13 | §2 | slnf green on Linux (0w/0e); slnx green on Windows (0w/0e); stub launched, versioned title + HWND observed; ProductVersion 0.0.0+sha from the binary; fresh clones clean both OSes; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidate 46319af -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s2.md
> **CRUD:** applicable | builds wrote bin/obj trees (read back via dll presence plus launch) and the lockfile (read back via restore); launch wrote a window (read back via title plus handle)
> **Duration:** 19
> **Implementer:** Muse Code (Meta Muse Spark)

## 3. CI on Linux and Windows Runners

> **Started:** 2026-09-13T21:51:25Z

Why this section exists: without CI the toolchain pin rots and "works on my machine" becomes the build system.

**Decided 2026-09-13:** GitHub Actions (repo-native; public repo, free minutes both OSes). Runners `ubuntu-24.04` + `windows-2025`; actions pinned to SHAs. No `setup-dotnet`: jobs run the §1 provisioners so `global.json` governs the SDK. Cost of changing CI: rewrite the workflow and re-probe green/red.

- [x] `.github/workflows/build.yml` runs the §2 neutral-filter build on a Linux runner and the full §2 solution build on a Windows runner, for every push to `main`. Done when: a push shows green runs on both. **Corrected 2026-09-13:** was "§2 build plus the neutral test suites" and "full build plus UI suites"; neither suite exists (§5 and T02 §2 are open and §3 depends only on §2), so this workflow runs the builds now and §5/T02 §2 extend it with their own probe evidence.
- [x] CI uploads the built stub as an artifact. Done when: the binary is downloadable from the run.
- [x] CI fails the run when the build fails, with the log naming the failing step. Done when: a deliberately broken commit (reverted immediately) shows red for the right reason.
- [x] The workflow pins its runner images and action versions, with the SDK version governed by `global.json`. Done when: no `latest` floats the build.
- [x] Commit: `"workspace: run the build on Linux and Windows"`

**Test checkpoint:** Push the workflow and read both runs: green on good code with the stub artifact downloadable, red-with-cause on a deliberately broken probe commit (reverted immediately), green again after the revert. Cheaper substitute that fails: a workflow that exists but never ran. **Corrected 2026-09-13:** dropped the UI-suites clause (no UI suites exist; T02 §2 owns them on Windows runners).

> **Verified:** 2026-09-13 | §3 | run 34785141981 green both jobs with stub artifact downloaded (exe+dll+XAML); run 34785638088 red both jobs with MSB4025 naming file+line; run 34786154222 green after revert; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates ef12eb3 6fb4909 e858133 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s3.md
> **CRUD:** applicable | pushes wrote CI runs (read back via run conclusions, logs, and artifact download); probe wrote a failure (read back via MSB4025 in both Build steps)
> **Duration:** 34
> **Implementer:** Muse Code (Meta Muse Spark)

## 4. Warning and Analysis Gates

> **Started:** 2026-09-13T22:25:30Z

Why this section exists: warnings are defects with seniority. Gate them at zero from the first compile so the count never has a legacy tail.

**Decided 2026-09-13:** `Directory.Build.props` and `.editorconfig` live at root so future `tests/` projects inherit the gates. `AnalysisLevel latest` resolves inside the pinned SDK, so the rule set does not float.
**Decided 2026-09-13:** `AnalysisMode All` (CA rules stay silent under the default mode; the probe proved CA1822/CA1823 need it). CA1515 excluded by path for `src/IntelligentNotepad/*.xaml.cs` (the XAML compiler generates public partials, CS0262 proven). Cost of changing the mode: re-verify zero warnings plus the probe pair.

- [x] The build treats warnings as errors (`TreatWarningsAsErrors` plus `EnforceCodeStyleInBuild` in `Directory.Build.props`, steward pattern) for project code. Done when: an unused-variable probe fails the build.
- [x] Roslyn analysis (`AnalysisLevel` latest) runs in CI with the committed `.editorconfig` ruleset. Done when: the ruleset file is in the repo and CI runs it.
- [x] Third-party and generated code are excluded by path, not by blanket suppression. Done when: the exclusion list names paths.
- [x] Analysis findings block the build; the doc records how to run the same analysis locally. Done when: a probe finding fails CI and the local command reproduces it.
- [x] Commit: `"workspace: gate warnings and static analysis"`

**Test checkpoint:** An unused-variable probe fails the build and a probe analysis finding fails CI; both reproduce locally with documented commands. Cheaper substitute that fails: warnings counted in a dashboard nobody reads.

> **Verified:** 2026-09-13 | §4 | gates green locally both OSes (0 warnings); run 34787039263 green both jobs; probe run 34787733488 red both jobs with CS0169+CA1822+CA1823 named, reproduced locally; run 34788413405 green after revert; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates f5482ca f554b05 2e8a38f -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s4.md
> **CRUD:** applicable | gates wrote props+ruleset (read back via warning-free builds); probe wrote violations (read back via named diagnostics locally and in CI)
> **Duration:** 50
> **Implementer:** Muse Code (Meta Muse Spark)

## 5. Test Wiring and First Smoke Test

> **Started:** 2026-09-13T23:16:01Z

Why this section exists: the test command must exist before the first real test, so every later section has somewhere to put its proof.

**Decided 2026-09-13:** smoke lives in `tests/Smoke/` (T02 §1 owns `tests/Unit/` separately); added to slnx and slnf. Core seeds `NotepadCore.Version` from the assembly stamp and fails loud on null (no fallback masking). `Version 0.0.0` centralized in `Directory.Build.props` (app-local removed). Default console logger; `TestResults/` ignore pre-verified by probe.
**Decided 2026-09-13:** xunit v2 line (2.9.3 + runner 2.8.2 + Test.Sdk 17.14.1), reversing the §1 v3 default: v3+MTP discovers zero tests on SDK 10.0.401 (proven on our project and xunit's own template), VSTest passes first try. T02 §1 re-evaluates v3/MTP.

- [x] `dotnet test` runs the suite (empty-but-green counts today). Done when: the command exits 0 on a clean checkout.
- [x] One smoke test asserts the neutral core constructs and reports its version. Done when: `dotnet test --filter Smoke` passes on Linux and fails if the version string is blanked.
- [x] CI runs the test command after the build and fails the run on test failure. Done when: a deliberately failing probe test (reverted immediately) shows red.
- [x] Test output (logs, captures) lands under `TestResults/` (gitignored) and never in the source tree. Done when: `git status` is clean after a full test run.
- [x] Commit: `"workspace: wire dotnet test with a first smoke test"`

**Test checkpoint:** `dotnet test` exits 0; blanking the version string turns it red; CI mirrors both. Cheaper substitute that fails: a test project that builds but whose tests CI never runs.

> **Verified:** 2026-09-14 | §5 | suite 1/1 green both OSes locally and in CI (run 34790029058); --filter Smoke passes; blanked version red locally; probe run 34790728911 red both jobs with test named; run 34791418524 green after revert; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates a7f6fce 805ce64 c317b8a -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s5.md
> **CRUD:** applicable | test runs wrote results (read back via Passed/Failed counts); probe wrote a failure (read back via named test in both CI logs); blank-check wrote red locally
> **Duration:** 62
> **Implementer:** Muse Code (Meta Muse Spark)

## 6. Developer Bootstrap Doc

> **Started:** 2026-09-14T00:18:32Z

Why this section exists: the second developer (or a fresh agent session) should reach a green build without asking anyone anything.

**Groomed 2026-09-13:** Operator decision: script-first bootstrap; the doc explains, the script provisions.

**Needs:** Windows host (build/test)

- [x] `docs/bootstrap.md` lists prerequisites with versions, install order, and the build and test commands. Done when: a cold reader reaches green without improvising.
- [x] The doc records the OS boundary: the neutral scope (`dotnet build`/`dotnet test` on `src/Notepad.Neutral.slnf`) runs anywhere, while the full solution build, app launch, UI suites, captures, and packaging run on Windows. Done when: a Linux reader knows exactly which commands are theirs. **Corrected 2026-09-14:** was "`dotnet build` runs anywhere"; §2 proved the XAML compiler is Windows-only, so Linux builds the neutral filter (see the §2 correction).
- [x] The doc links the troubleshooting entries for the two most common bootstrap failures found while writing it. Done when: each entry was reproduced and fixed, not imagined.
- [x] Bootstrap is script-first: a cold follow runs `tools/provision.sh` (Linux) or `tools/provision.ps1` (Windows) and reaches a green build with no manual installs, while `docs/bootstrap.md` explains what the script does. Done when: the script plus doc together pass the checkpoint with zero improvisation.
- [x] Commit: `"workspace: write the developer bootstrap doc"`

**Test checkpoint:** A cold follow of the doc on a clean machine reaches a green build and test run. Falsifiable by any step that does not work as written.

> **Verified:** 2026-09-14 | §6 | doc cold-followed green on Linux (0 warnings, Passed 1/1) and Windows (0 warnings, Passed 1/1, stub launch title observed); env-failure entries reproduced verbatim on both OSes; run 34792965135 green both jobs on the push; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidate ef2e014 -- `adversarial` advisory (cold machines had step-1 prereqs preinstalled; bare metal follows the documented vendor installers) · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s6.md
> **CRUD:** not applicable | doc-only section; cold follows wrote build and test outputs outside the repo (read back via warning counts, test counts, window title)
> **Duration:** 22
> **Implementer:** Muse Code (Meta Muse Spark)

## 7. TODO Graph Checks in CI

> **Started:** 2026-09-14T00:41:00Z

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
