---
schema_version: 1
id: repo-and-toolchain
domain: 00-workspace
status: active
title: "TODO-01 -- Repo and Toolchain"
track: W0
---

# TODO-01 -- Repo and Toolchain

> **Goal:** A clean checkout builds the app and runs the tests with one command each, on a pinned .NET toolchain, with CI proving the build plus launch smoke on Linux and Windows runners on every push. **Corrected 2026-09-17 (groom):** was "CI proving the same"; since 2026-09-17 CI proves build plus launch smoke only and the suites run locally on the dev box.

> [!IMPORTANT]
> **Current state:** The repo holds only `todo/`, `scripts/`, `docs/`, and root docs. No source tree, no solution, no CI. The first section that touches the .NET SDK decides the layout below; until then every path in this file is a proposal, not a fact.
>
> **Corrected 2026-09-17 (groom):** §§1-7 and §§9-11 have shipped since (layout and SDK pin, scaffold, CI, warning gates, test wiring, bootstrap doc, graph checks, panel enforcement plus follow-ups, lookahead removal); §8 moved to `docs/testing.md` 2026-09-14. Open: §12 only.
>
> **Filed 2026-09-17:** §13 (environment-gated ready queries). Open: §§12-13.

> **Filed 2026-09-18:** §14 (plan reviews with a second-family reviewer). Open: §§8, 14.

> **Filed 2026-09-18:** §15 (first plan-review residuals). Open: §§8, 15.

## Inputs

- [Windows App SDK and WinUI 3 docs for .NET](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/) -- WinUI 3 with .NET: SDK and workload requirements
- [`todo/README.md`](../README.md) -- the format this TODO's §7 gates in CI

## Outcome

- A clean checkout builds with one command and tests with one command, on Linux or Windows.
- CI on Linux and Windows runners builds every push to `main` and smoke-launches the app; the unit, UI, and protocol suites run locally on the dev box. **Corrected 2026-09-17 (groom):** was "builds and tests every push"; CI narrowed to build plus launch smoke 2026-09-17.
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
|   7   |   §7    | TODO graph checks in CI | §3 |  [x]   |
|   8   |   §8    | Conclave-PC input capability for automation | -- |  [ ]   |
|   9   |   §9    | Opus panel enforcement in the validator | §7 |  [x]   |
|  10   |   §10   | Opus panel rule hardening follow-ups | §9 |  [x]   |
|  11   |   §11   | Quote-end lookahead removal | §10 |  [x]   |
|  12   |   §12   | Repo-managed git hooks gating TODO edits | -- |  [x]   |
|  13   |   §13   | Environment-gated ready queries | §7 |  [x]   |
|  14   |   §14   | Plan reviews with a second-family reviewer | §9 |  [x]   |
|  15   |   §15   | First plan-review residuals | §14 |  [ ]   |

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

- [x] `src/ScratchPad.slnx` holds the stub WinUI 3 app (`net10.0-windows10.0.19041.0`, unpackaged) plus the neutral `Notepad.Core`, `Notepad.Acp`, and `Notepad.Agents` libraries (`net10.0`), with `src/Notepad.Neutral.slnf` filtering the neutral scope. Done when: `dotnet build` on the slnf is green from Linux, `dotnet build` on the slnx is green on Windows, and the stub launches on Windows 11. **Corrected 2026-09-13:** was "dotnet build compiles it all, green from Linux"; the XAML compiler cannot complete on Linux (spike: 1.8-line codegen absent with CS5001/CS0103, 2.4.0 fails WMC1006 on BCL resolution), so Linux builds the neutral filter and Windows builds all.
- [x] `docs/build.md` gives the single build command and its prerequisites. Done when: following it on a clean machine produces the stub. **Corrected 2026-09-13:** one command per OS (slnf on Linux, slnx on Windows); the doc names both plus the provision and runtime prerequisites.
- [x] The stub reports its own version and toolchain in an About surface or log line, with the commit stamped via `SourceRevisionId`. Done when: the provenance of a binary is answerable from the binary.
- [x] Build outputs land under per-project `bin/` and `obj/` (gitignored) and publish output under `dist/` (gitignored), never beside sources. Done when: `git status` is clean after a full build.
- [x] Commit: `"workspace: scaffold solution with one-command build"`

**Test checkpoint:** `dotnet build src/Notepad.Neutral.slnf` exits 0 on Linux; `dotnet build src/ScratchPad.slnx` exits 0 on Windows and the stub window launches with its versioned title observed; `git status` shows no build outputs. Cheaper substitute that fails: a solution that builds only inside the IDE on the author's machine. **Corrected 2026-09-13:** per-OS commands per the item-1 correction; was bare `dotnet build` green from Linux.

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
**Decided 2026-09-13:** `AnalysisMode All` (CA rules stay silent under the default mode; the probe proved CA1822/CA1823 need it). CA1515 excluded by path for `src/ScratchPad/*.xaml.cs` (the XAML compiler generates public partials, CS0262 proven). Cost of changing the mode: re-verify zero warnings plus the probe pair.

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

- -> XREF: D00 T01 §13 -- the environment gate extends these checks; the new query split and marker rule ride the same gates.

- [x] CI runs `python3 scripts/todo-graph.py self-test` on every push touching `scripts/` or `todo/`. Done when: the run shows the case count and zero failures.
- [x] CI runs `python3 scripts/todo-graph.py validate` on the same pushes. Done when: a probe FATAL (reverted immediately) fails the run.
- [x] CI runs `python3 scripts/todo-graph.py plan --sync` followed by a clean-tree check (or `plan --check` once the JSON paths are committed), so a stale projection fails the run. Done when: a hand-flipped plan box fails the run.
- [x] The workflow triggers only on relevant paths so doc edits do not pay for graph checks. Done when: a docs-only push skips the job.
- [x] Commit: `"workspace: gate the TODO graph in CI"`

**Test checkpoint:** Probe commits prove each of the three checks fails the run for the right reason; all probes reverted. Cheaper substitute that fails: checks that run but whose failures do not fail the run.

> **Verified:** 2026-09-14 | §7 | plan-gates green (run 34793534551, 391 cases 0 failed); self-test probe red 34793587854, validate probe red 34793710261 with FATALs named, projection probe red 34793805213, each reverted to green; docs-only push ran no plan-gates job; validate 0 fatal; self-test 391/391
> **Review:** round 1, candidates ba504d2 d51bbf5 7adbd7c d18932b bbaf5c6 f18b59d 7c2b739 294ec5e -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s7.md
> **CRUD:** applicable | CI wrote step conclusions (read back via run/job/step APIs); probes wrote red runs (read back via failed step names and log lines); docs-only push wrote no run (read back via empty run list)
> **Duration:** 12
> **Implementer:** Muse Code (Meta Muse Spark)

## 8. Conclave-PC Input Capability for Automation

> **Moved:** 2026-09-14 to docs/testing.md (operator instruction: Conclave-PC VM testing retired; input capability proven by the local host suite instead, UI 18/18 with zero skips).

Why this section exists: the shared VM refuses both input interception (`SetWindowsHookEx` fails Win32 error 5, which crashed the app until the degrade fix) and synthetic input (`SendInput` fails Win32 error 5 even from high-integrity processes on the Default desktop, failing 6 UI tests), with only Windows Defender installed. The suite's real-input drives cannot run there until the denying mechanism is identified and the narrowest host change applied.

**Needs:** Windows host (build/test)

- [ ] ~~Found 2026-09-14: identify the mechanism refusing `SetWindowsHookEx` (`src/ScratchPad/MiddleClickHook.cs`) and `SendInput` (`tests/UI/TabBarTests.cs` `Press`) on Conclave-PC: Defender ASR or exploit-protection rule, GPO, or hardening agent, with the exact rule named. Done when: the denying rule is named with its configuration path.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Apply the narrowest host change (a scoped exclusion or single-rule exception, never a blanket disable) and record it in `docs/testing.md`. Done when: the hook probe succeeds and `dotnet test tests/UI --filter ThreeTabsSwitchAndClose` passes on Conclave-PC.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] ~~Re-run the full UI suite on Conclave-PC and confirm the input failures plus the hook skip clear with no new failures. Done when: `dotnet test tests/UI` shows 18/18 on the VM.~~ Moved 2026-09-14 to docs/testing.md.
- [ ] Commit: `"workspace: enable input capability on Conclave-PC"`

**Test checkpoint:** Hook probe true, `SendInput` injects, full UI suite green on the VM; the host change recorded and minimal. Cheaper substitute that fails: disabling real-time protection host-wide instead of the narrow exclusion.

## 9. Opus Panel Enforcement in the Validator

> **Started:** 2026-09-17T11:09:48Z

Why this section exists: `review-todo-section` requires lens verdicts from the headless Opus panel, but a skill sentence alone cannot stop an agent from stamping without running it. The validator already owns stamp rules, so the panel requirement lands there as a FATAL class: a stamp whose findings lack Opus verdicts reads as evidence while verifying nothing. Hooks that auto-run the panel are out of scope by design (minutes and dollars inside a commit hook, needs auth, fragile); the rule enforces the record, which defeats forgetfulness, not forgery.

- [x] `stamp-no-opus-panel` lands in `SEVERITY_MAP` as FATAL with its `todo/README.md` table row in the same position (the self-test compares map and table row-for-row). Done when: both edits exist and the map/table test passes. Done: class appended last in both, map/table test green.
- [x] `todo-validate.py` gains the rule: a section in `verified_sections` stamped after 2026-09-17 must name a findings file in its `Review:` line (`Raw findings: <path>`) that exists and carries an `Opus panel` heading plus all four lens verdicts (`adversarial`, `consistency`, `integration`, `record`, each with `approve`/`needs-attention`/`advisory`); stamps on or before 2026-09-17 are grandfathered by date (the rule postdates them, §6 included). Done when: the rule fires on a fresh violator and stays silent on the live tree. Done: rule 16 in `todo-validate.py` (findings path from `Review:`, existence, `Opus panel` heading, four lens verdicts in-section); live tree silent at 0 fatal. Live drives (temp edits, reverted clean): §13 re-dated post-cutoff stays silent against its real paneled findings; same stamp with the findings path removed fires 1 fatal.
- [x] Self-test fixtures plus cases cover the rule: missing findings file, present file without the panel heading, panel heading with a missing lens verdict, pre-cutoff stamp without a panel (passes), a clean panel (passes), both multi-round directions (stale-clean fires, stale-gap silent), a fenced panel quote (passes), a level-5 tail after the panel (fires), and a level-5 panel heading (passes). Done when: each case asserts and the suite count is quoted. Done: 12 cases (class severity + 6 firing shapes + 5 silences), per-line assertions, fixtures unlinked after.
- [x] `self-test` green at the new count, the count in `AGENTS.md` updated to match, and live-tree `validate` still 0 fatal. Done when: all three are quoted. Done: 405 cases 0 failed; AGENTS.md says 405; live `validate` 0 fatal 0 warnings.
- [x] Commit: `"workspace: enforce Opus panel evidence in the validator"`

**Test checkpoint:** `python3 scripts/todo-graph.py self-test` green at the new quoted count; a fixture stamp dated after the cutoff without panel evidence fails `validate` with a FATAL naming the section. Cheaper substitute that fails: an untested rule, or a grandfather clause that also swallows fresh stamps.

- -> XREF: D00 T01 §10 -- round-5 panel residuals (unheaded-prose verdicts, unbalanced fence, fence-only fixture) filed there

> **Verified:** 2026-09-17 | §9 | self-test 405/405 (12 panel cases, each mutation-proven); live validate 0 fatal 0 warnings; 5 Opus panel rounds over candidates 6de1d9a f405c7a 8ea92aa b922ded 2305e87 with zero needs-attention at close; live drives (post-cutoff paneled stamp silent, unpointed stamp 1 fatal) reverted clean
> **Review:** round 5 (FINAL), candidates 6de1d9a f405c7a 8ea92aa b922ded 2305e87 -- `adversarial` advisory · `consistency` advisory · `integration` approve · `record` advisory. Leftovers filed at D00 T01 §10. Raw findings: docs/reviews/00-workspace/D00-T01-s9.md
> **CRUD:** applicable | self-test wrote fixture files under a temp root (unlinked after, read back via per-line case assertions); live drives wrote temp stamp edits (reverted clean, read back via validate output); filing wrote §10 plus its plan row (read back via plan --check current)
> **Duration:** 28
> **Implementer:** Muse Code (Meta Muse Spark)

## 10. Opus Panel Rule Hardening Follow-ups

> **Started:** 2026-09-17T11:38:40Z

Why this section exists: the round-5 Opus panel on §9 (final round, all lenses advisory or better) left three residual notes on the `stamp-no-opus-panel` rule that are coverage, not defects, and the heading-scan unit had been patched in three consecutive rounds, so the skill's stop-and-re-think clause routed them here instead of a fourth patch. -> XREF: D00 T01 §9 (filed from its round-5 panel); -> SOURCE: Opus panel round 5 on candidate `2305e87`, transcribed in `docs/reviews/00-workspace/D00-T01-s9.md`.

- [x] An incomplete panel followed by unheaded prose still draws its missing verdicts from that prose (measured: bare `Filed leftovers: integration approve, record approve` line after a two-lens panel stays silent; same when the leftover heading hides inside a fence, since the strip removes the terminator). Re-think the unit (prose-boundary verdict search or explicit panel-end marker) rather than patching the scan a fourth time. Done when: the chosen shape is recorded with its cost, fixtures lock both directions, and the suite count is quoted. Done: boundary moved from the slice to the line (per-lens line-anchored regex, marker run required, same-line); cost recorded (verdict lines must open within 3 leading spaces with `**`, backtick, quote, or list dash: bare markerless, 4-space-indented, and table-cell verdict mentions no longer count; no live findings use those shapes); §12 fixture fires naming both lenses; skill and README state the marker rule. Round-1 record: quoted headings are not structure (a fenced heading neither terminates nor displaces, symmetric with the §9 strip rationale), so marker-shaped verdicts after a fenced heading are compliant verdicts: §15 (fenced heading plus bare prose) fires, §16 (fenced heading plus marker verdicts) stays silent. Round-2: `_`/`~` dropped from the marker class for an exact doc match (§20 locks the rejection); `_`/`~`-led lines accepted before round 1, rejected after; `+` bullets never counted. Suite 418/418.
- [x] An unbalanced fence swallows the rest of the file, so an unterminated fence before a complete panel misreports as `carry no Opus panel section`. Done when: the failure names the real defect (unbalanced fence with its line) or the strip tolerates it, with a fixture locking the behavior. Done: opener line tracked, unbalanced files FATAL naming the fence line; §13 fixture locks the message. Round-1: char-plus-length tracking per CommonMark close rules (a shorter or other-char run inside a fence is content); §17 locks the four-backtick nesting idiom. Round-2: closes additionally require no info string (a ```text line inside is content, never a close; §18), and 4-space-indented markers are indented code, never fences (§19). Round-3: blockquote prefixes do not hide fences (only detection sees the unquoted line; §21), and a backtick in a backtick-fence info string makes the line a paragraph (tilde info unrestricted; §22). Round-4: closes must match the opener's quote depth (§23), and a quote that ends (no same-depth close ahead) ends its fence via lookahead, with lazy lines kept as content (§24); fence-shape analysis factored into one helper shared by the scan and the lookahead.
- [x] The fence-only direction is unfixtured: `90-panel-fenced.md` proves a fenced quote cannot displace a real panel, but no fixture proves a fenced quote alone cannot satisfy the rule (probed manually: fires correctly today). Done when: a fence-only findings fixture plus its case assert the FATAL, and the check name no longer over-claims. Done: §14 fence-only fixture fires `carry no Opus panel section`; §9 check renamed to the displaces direction it covers. Panel-check predicates hardened to `§N ` (trailing space) so two-digit sections cannot cross-match.
- [x] Commit: `"workspace: harden Opus panel rule per round-5 notes"`

**Test checkpoint:** `python3 scripts/todo-graph.py self-test` green at the new quoted count with a case per residual; each new fixture is mutation-proven, measured revert to failures: §17/§18/§19/§20/§21/§22/§23/§24 fail exactly their case under their own fix's revert; shared machinery fails together (anchored-to-substring reverts to §12/§15/§20; unbalanced-flag removal to §13/§23; strip tracking removal with the flag kept to §9/§13/§14/§16/§17/§18/§21/§23). Cheaper substitute that fails: a fourth scan patch without the re-think, or fixtures that pass vacuously.

- -> XREF: D00 T01 §11 -- round-5 leftovers (quote-end lookahead removal, lazy-comment correction, README alignment) filed there

> **Verified:** 2026-09-17 | §10 | self-test 418/418 (13 new panel cases §§12-24, full 11-mutation battery measured); live validate 0 fatal 0 warnings; 5 Opus panel rounds over candidates f8740c2 7f7fcfa 9c4dc55 fe5e6cc b6c858b closing with one needs-attention filed, not patched, per max-5; live panels re-probed passing under the anchored regex; self-application drive (post-cutoff §9 stamp) silent, reverted clean
> **Review:** round 5 (FINAL), candidates f8740c2 7f7fcfa 9c4dc55 fe5e6cc b6c858b -- `adversarial` needs-attention · `consistency` advisory · `integration` advisory · `record` approve. Leftovers filed at D00 T01 §11. Raw findings: docs/reviews/00-workspace/D00-T01-s10.md
> **CRUD:** applicable | self-test wrote fixture files under a temp root (unlinked after, read back via per-line case assertions); mutation battery wrote temp rule edits (restored exact, read back via failure sets and byte compare); filing wrote §11 plus its plan row (read back via plan --check current)
> **Duration:** 44
> **Implementer:** Muse Code (Meta Muse Spark)

## 11. Quote-End Lookahead Removal

> **Started:** 2026-09-17T12:20:37Z

Why this section exists: the round-5 Opus panel on §10 (final round, max 5 reached) left one needs-attention: the quote-end lookahead scans the whole remainder for a same-depth close, so a later quoted fence retroactively swallows the lines between (false FATAL on a §24 shape plus a later quoted block; fail-open swallowing a round-2 panel so stale round-1 verdicts read as the record). The same round's consistency lens supplies the fix direction: CommonMark laziness never applies to fenced-code content, so an unquoted non-blank line after a quoted fence always ends quote and fence, and the lookahead branch (plus its lazy comment) should be deleted, not bounded. -> XREF: D00 T01 §10 (filed from its round-5 panel); -> SOURCE: Opus-panel-D00-T01-s10-round-5 (candidate `b6c858b`, round-5 adversarial/consistency/integration verdicts; transcribed in `docs/reviews/00-workspace/D00-T01-s10.md`).

- [x] Delete the quote-end lookahead: an unquoted non-blank line below the open fence's quote depth always closes the fence (no ahead scan). Done when: §24 still passes unmodified, new fixtures lock both round-5 probe shapes (§24 shape plus a later balanced quoted block stays silent; round-2 heading after a quoted fence fires naming the missing lenses), and the mutation map in the checkpoint is re-measured. Done: branch deleted (unconditional close with the laziness rationale in the comment); §24 passes unmodified; §25 silent and §26 firing as specified. Round-1: §27 locks the forward window (same-depth close one line after the early-close point must not resurrect the fence). Round-3 measure: pre-deletion code fails §25/§26/§27/§28; a 2-line bound fails exactly §27 and §28.
- [x] Correct the record the lookahead left behind: the lazy-content comment in `todo-validate.py`, and the unconditional "an ended quote ends its fence" in `todo/README.md` (the skill already states the no-close-ahead condition; after deletion both state the unconditional rule truthfully). Done when: comment and both docs describe the same rule and no probe distinguishes them. Done: lazy comment replaced with the no-laziness rule; skill condition removed so both docs state the unconditional rule; README was already unconditional and is now true. Round-3: blank clause added to both docs (a blank line ends the quote, so quoted fences stay blank-free).
- [x] Round-2 review feedback: a blank line ends a quoted fence (CommonMark 0.31.2 section 5.1, example 228), so the blank-line exemption was a fail-open (quoted verdicts after a re-closed quoted fence satisfied the rule). Done when: the exemption is deleted with §28 locking the probe shape, and the round-2 record notes (item-2 Done claim, §27 title) are corrected. Done: condition simplified to bare depth comparison (unquoted fences keep blank content via 0 < 0 false); §28 fires naming line 8; item-2 claim re-verified by the probe; §27 renamed to the forward window it locks.
- [x] Commit: `"workspace: remove quote-end lookahead from panel rule"`

**Test checkpoint:** `python3 scripts/todo-graph.py self-test` green at 422/422; the two round-5 adversarial probe shapes are fixtures (§25 silent, §26 firing) with cases, plus §27 locking the forward window and §28 the blank rule; refreshed mutation map, every line re-measured this round: §17/§18/§19/§20/§22/§23/§28 fail exactly their case under their own fix's revert; shared machinery fails together (anchored-to-substring to §12/§15/§20; unbalanced-flag removal to §13/§23/§27/§28; quote handling removal to §21/§27/§28; strip tracking removal with the flag kept to §9/§13/§14/§16/§17/§18/§21/§23/§27/§28; lookahead restored to §25/§26/§27/§28; early-close block dropped to §24/§25/§26/§27/§28). Cheaper substitute that fails: bounding the lookahead window instead of deleting the branch (a 2-line bound fails exactly §27 and §28).

> **Verified:** 2026-09-17 | §11 | self-test 422/422 (4 new panel cases §§25-28, full 13-mutation battery measured); live validate 0 fatal 0 warnings; 5 Opus panel rounds over candidates 3375f2f f847d09 0aaab16 77016ec ba9be18 closing with all four lenses approve and zero leftovers; blank-line rebuttal overturned by spec citation and fixed with §28 in the same round
> **Review:** round 5 (FINAL), candidates 3375f2f f847d09 0aaab16 77016ec ba9be18 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. No leftovers. Raw findings: docs/reviews/00-workspace/D00-T01-s11.md
> **CRUD:** applicable | self-test wrote fixture files under a temp root (unlinked after, read back via per-line case assertions); mutation battery wrote temp rule edits (restored exact, read back via failure sets and byte compare); blank-line probe wrote a temp TODO plus findings (removed after, read back via rule silence)
> **Duration:** 29
> **Implementer:** Muse Code (Meta Muse Spark)

## 12. Repo-Managed Git Hooks Gating TODO Edits

> **Started:** 2026-09-17T23:13:52Z

Why this section exists: no git hooks are installed in this clone (only `.git/hooks/*.sample`), so a validator FATAL reached `main` in `871bde8` and was fixed after the fact in `2916e66`. CI plan-gates backstops pushes, but trunk pushes land before any gate runs. Committed hooks close the hole for every clone.

- -> SOURCE: fatal-on-main-871bde8 (Needs-line prose tripped the closed-list FATAL; landed and fixed seconds apart with no local gate) **Corrected 2026-09-17 (§12 validation):** filed as "4 minutes apart"; committer times are 19:46:24/19:46:46 +0200, 22 seconds apart.

**Decided 2026-09-17 (§12 review R1):** the hook validates staged content in a temp index checkout, not the worktree: a worktree-reading gate passes staged FATALs (measured) and blocks clean commits on unstaged dirt (measured). Path-limited `git commit <paths>` is covered too: `--include` presents the listed worktree files in a temporary index (`GIT_INDEX_FILE`, measured), which the hook reads like any index, and a refusal discards it with no residue (measured T4). CI plan-gates stays the push-time backstop. Cost of changing the scope: rewrite the hook's extraction plus both probe directions.

**Decided 2026-09-17 (§12 review R2):** provisioner wiring failure warns and the install still exits 0: the SDK install is the provisioner's job and must not fail over an auxiliary gate, and tarball checkouts or missing git cannot wire by definition; the warning names the miss and the bootstrap one-time step is the repair. Cost of changing to fail-closed: one branch per provisioner plus re-proof.

- [x] A committed hooks dir (plus `core.hooksPath` wiring documented in the toolchain setup) runs `validate` on pre-commit and blocks the commit on FATAL. Done when: a FATAL fixture commit is refused locally. Done: `tools/githooks/pre-commit` (100755, LF-pinned in .gitattributes) validates the staged tree in a temp index checkout and refuses when red; `provision.sh`/`provision.ps1` wire `core.hooksPath` up front for new clones (script-first per §6); staged FATAL refused (exit 1), unstaged FATAL no longer blocks a clean staged commit, path-limited commits covered via the temporary index (measured T4 refused); a wiring failure warns and exits 0 (Decided).
- [x] The setup docs name the one-time step for existing clones. Done when: the step is followed cold from the docs. Done: `docs/bootstrap.md` "Git hooks" section plus the Windows Python 3 prereq row; step followed cold in a Linux clone (staged FATAL refused) and end to end on Windows via git.exe (fixture refused, clean commit passes).
- [x] Commit: `"workspace: gate TODO edits with repo hooks"` Ship `01fb330`; fix-forwards `d4e1f9c` (self-review), `2fa3f30` (round-1 lenses), `5a8a2a2` (round-2 lenses).

**Test checkpoint:** FATAL fixture refused locally; setup step followed cold. Cheaper substitute that fails: hooks documented but installing nothing.

> **Verified:** 2026-09-17 | §12 | staged FATAL refused exit 1 (Linux T1, Windows W1 via git.exe); clean staged commits pass (T2 with warning, T3 0s silent, W2); path-limited refused via the temp index (T4, GIT_INDEX_FILE measured); autocrlf=true checkout od LF; assert step positive plus pin/index-removal negatives; self-test 422/422, validate 0 fatal, plan current
> **Review:** rounds 1-3, candidates 01fb330 d4e1f9c 2fa3f30 5a8a2a2 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` advisory (candidate list completed in this stamp). Raw findings: docs/reviews/00-workspace/D00-T01-s12.md
> **CRUD:** applicable | hook plus provisioners plus workflow plus docs written and read back via execution (snippet runs, interop git.exe and PowerShell runs, CI provision steps green); fixtures planted and reverted byte-identical (cmp) with scratch clones removed after each probe
> **Duration:** 44
> **Implementer:** Muse Code (Meta Muse Spark)

## 13. Environment-Gated Ready Queries

> **Started:** 2026-09-17T23:59:32Z

Why this section exists: `query ready` answers dependency readiness only, so an environment-blocked section (display session, spooler visibility, credentials, API keys) shows ready in every context and burns a park cycle each run. D01 T02 §15 is the standing instance: dependency-ready, unrunnable without a display session.

- -> XREF: D00 T01 §7 -- the graph checks this feature extends; the new query split and marker rule ride the same gates.
- -> XREF: D01 T02 §15 -- the first gated consumer; its display-session requirement is the feature's proving instance.

- [x] The marker is decided (a new line plus closed vocabulary, or a `Needs:` extension with reasons; `Needs:` is taken by the host closed list, so a bare reuse collides) and recorded in `todo/README.md` with the full value list. Done when: the format doc carries the line spec and every value's meaning. Done: new `**Requires:**` line (values plus required reason) with vocabulary table ({display-session} with meaning and detector), query semantics, and grandfathering in `todo/README.md`; Tooling line updated.
- [x] `query ready` splits output into runnable-now versus runnable-elsewhere from the marker plus the runner's context (local context by default, explicit context flag for planning), with the split explained per row. Done when: `query ready` in this context parks §15 with its requirement named, and in a display context lists it runnable. Done: split live (12 now, 1 elsewhere locally with §15's requirement named; `--context display-session` lists 13 runnable including §15); `resolve` prints the local verdict.
- [x] The validator gates the marker (unknown values FATAL, shipped sections grandfathered or marked with reasons) with self-test cases proving the rule plus the split. Done when: self-test grows by the new cases, all green, and the live tree validates silent. Done: requires-unknown plus requires-no-reason FATALs live (two rules, three message texts, four FATAL lines on the gamma fixture); self-test 446 green (422 before; +24: 1 legacy-empty, 5 parser, 7 validator, 5 detector, 6 split); live tree silent.
- [x] The known environmentally-gated open sections are marked, §15 first with its display-session requirement, each requirement named from evidence. Done when: every mark cites the measurement that convicted it. Done: §15 marked display-session citing the run-5 deferral measurement; survey of all 13 ready rows plus run-file deferrals found no other evidenced marks (sole mark).
- [x] `process-plan` and `process-phase` offer only runnable-now rows in the current context (runnable-elsewhere rows stay visible, never offered). Done when: both skill docs carry the rule. Done: process-plan defines ready as runnable-now (offer runnable-now only, elsewhere visible never started, re-run not trust); process-phase treats a runnable-elsewhere `resolve` verdict as a leftover whatever the exit code (verified: §15 resolves exit 0 with "missing here: display-session").
- [x] Commit: `"workspace: gate ready queries on environment"`

**Test checkpoint:** Marker spec in the format doc; split proven in both contexts; self-test green with the new cases; live tree silent; known sections marked with cited evidence; skills offer runnable-now only. Cheaper substitute that fails: a comment convention no query reads.

> **Verified:** 2026-09-18 | §13 | split live (12 runnable now, 1 elsewhere locally with §15 named; --context display-session lists 13); resolve prints the missing-here verdict; requires-unknown plus requires-no-reason FATALs live; Phase 1 first_ready moved §15 to §5; skills hold elsewhere rows back at select, start, and authoring; self-test 446/446 (+24 cases); live validate 0 fatal 0 warnings; plan current
> **Review:** rounds 1-5 (FINAL), candidates 21c53b2 ceae321 5c29b83 3b0653b 2a697a4 3f922ce 9a20476 -- `adversarial` approve · `consistency` advisory (blank-line separation, fixed post-panel in 9a20476) · `integration` advisory (authoring prompts, fixed post-panel in 9a20476) · `record` approve. No leftovers. Raw findings: docs/reviews/00-workspace/D00-T01-s13.md
> **CRUD:** applicable | self-test wrote the gamma fixture under a temp root (unlinked after, read back via case assertions); live typo and no-values probes reverted clean (read back via query output); skills and docs wrote prose (read back via grep sweeps)
> **Duration:** 45
> **Implementer:** Muse Code (Meta Muse Spark)

## 14. Plan Reviews with a Second-Family Reviewer

> **Started:** 2026-09-18T10:05:29Z

Why this section exists: the Opus panel gates what a section built, but no lens asks whether the plan around it is complete (a missing print function, a settings card no section themes, a protocol behavior no test locks). One second-family round per stamped section catches those plan gaps while the context is hot, and its feedback lands as tracked work through `add-todo`, never as inline scope creep. **Added 2026-09-18 (validation):** the mirror rung belongs here too: an unreachable Opus panel stalls a run that a second family could unblock, so the panel fails silent onto `gpt-5.6-sol` with the record naming the family honestly.

- -> XREF: D00 T01 §9 -- the Opus panel this plan review complements; the panel gates the build, the plan review audits the plan.

- [x] `review-todo-section` gains a plan-review step: after the stamp, one round over the section plus its Depends and XREF neighbors asking for gaps, inconsistencies, faults, improvements, and premium wins, with the feedback synthesized into `add-todo` filings (micro/small items, new sections, new domains) by the implementing session, never applied blind. Done when: the skill names the timing (post-stamp, advisory, never blocks), the scope (section plus connected sections), and the filing route. Done: `### Plan review` lands between step 7 and audit stance with timing, scope, and the `add-todo` filing route.
- [x] The reviewer is one `gpt-5.6-sol` round at high reasoning effort through the codex runner in read-only sandbox, with the section text plus neighbor sections inline. Done when: the skill pins the exact command shape and the model name reads `gpt-5.6-sol` (lowercase; the uppercase variant fails model resolution, probed 2026-09-18). Done: command block plus lowercase note land in the plan-review section.
- [x] Runner failure fails silent onto an Opus high-effort round: any nonzero exit, auth failure, or model-resolution failure runs the headless panel command once with `--effort high` over the same prompt, and if that also fails the outage is recorded in the findings file and the run continues. Done when: the skill names both fallback rungs and the record-the-outage rule, and a forced failure (bogus model name) is observed to reach the Opus rung. Done: both rungs plus the record-and-continue rule land in the plan-review section; forced failure observed (`gpt-9.9-nope` fails 400 model-not-supported) with the Opus-high rung returning the echo.
- [x] The Opus panel fails silent onto `gpt-5.6-sol`: when the headless panel command is unreachable (no CLI, auth failure, model error), the same four lenses run once through the codex runner (`gpt-5.6-sol`, medium effort, read-only) over the same prompt instead of stopping the run, matching the panel's pinned effort; if both families fail, the run stops with no stamp. Done when: the skill replaces the stop-and-say-so rule with the fallback rung, a GPT-run panel never carries an `Opus panel` heading (the record names the family honestly), and the validator accepts a `GPT panel` fallback record carrying all four lens verdicts plus the Opus outage note, with self-test cases locking both the accept and the reject shapes. **Added 2026-09-18 (validation):** the GPT-medium command shape is echo-probed and quoted like the item-5 probes, and the AGENTS.md self-test count is synced to the new total (sibling §§9-11 convention). Done: stop-and-say-so replaced with the GPT-medium rung plus the honest-record shape (`GPT panel` heading, four verdicts, `Opus outage` line, last of either family governs); validator accepts the fallback record (README row extended); self-test grows 8 cases (§§29-36: clean accept, missing-note reject, missing-lens reject, GPT-last silence, fenced-GPT reject, Opus-last fire, GPT terminator, defective-GPT-last fire) green at 454; GPT-medium probe `runner-ok`; AGENTS.md synced to 454; live drives (scratch GPT record silent, note removed fires 1, mixed shapes both directions) reverted clean. **Corrected 2026-09-18 (review R1):** filed as Opus-governs; the round-1 adversarial lens showed that contradicts last-wins and leaves a last GPT section unvalidated, so precedence is last-panel-of-either-family with §32 flipped and §§34-35 added.
- [x] Both runners are smoke-probed with a verbatim-echo prompt before the skill lands. Done when: the `gpt-5.6-sol` high probe and the Opus high probe each return the echo, quoted in the commit or findings. Done: GPT-high `runner-ok` (morning probe, pre-skill), Opus-high `runner-ok` (this build), both quoted in the commit body.
- [x] Commit: `"workspace: add second-family plan reviews"`

**Test checkpoint:** Skill carries the plan-review timing, scope, reviewer, and fallback chain plus the panel's mirror rung with its honest-record shape; the GPT-high, Opus-high, and GPT-medium probes are quoted passing; a forced runner failure is observed to reach the Opus rung; self-test is green at the new quoted count with the GPT-panel accept and reject cases; live-tree `validate` stays silent. **Corrected 2026-09-18 (validation):** filed covering only the plan-review chain; the panel chain, validator cases, and count are item-4 work the checkpoint must also gate. Cheaper substitute that fails: a second-family round with no fallback, which blocks the run on every runner outage.

> **Verified:** 2026-09-18 | §14 | skill carries the plan-review step (post-stamp advisory, section-plus-neighbors scope, `add-todo` route), the GPT-high reviewer pin with the lowercase probe note, both fallback chains, and the panel mirror rung with the `Plan review` record heading; probes quoted (GPT-high, Opus-high, GPT-medium `runner-ok`; bogus-model 400 reaching the Opus rung); validator takes the GPT fallback record (4 verdicts plus outage note, last of either family governs); self-test 454/454 (+8 §§29-36, §32 flipped with reason, §36 mutation-proven); live validate 0 fatal; live drives A-D reverted clean
> **Review:** rounds 1-3, candidates 5eaef41 2bf7f1f bb801bf -- `adversarial` approve (R1 needs-attention on Opus-governs fixed with last-wins plus §§34-35; R2 advisory on §36 coverage fixed) · `consistency` approve · `integration` approve (R1 advisory on the plan-review heading fixed) · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T01-s14.md
> **CRUD:** applicable | self-test wrote panel fixtures under a temp root (unlinked after, read back via per-line case assertions); live drives wrote temp Review re-points plus a scratch findings file (reverted clean, scratch deleted, read back via validate output); runner probes wrote nothing (verbatim-echo, read-only); skill and doc edits read back via grep
> **Duration:** 14
> **Implementer:** Muse Code (Meta Muse Spark)

## 15. First Plan-Review Residuals

> **Started:** 2026-09-18T10:23:26Z

Why this section exists: the first live plan review (§14 plus §9, `gpt-5.6-sol` high) returned 15 findings; 10 survive synthesis and none has an owner, since every review-loop section is stamped. They cluster into auditability (completion marker, input manifest, finding ledger, health report), honesty (degraded-path label, evidence citation), scope (reverse dependents), and failure handling (hung runners, safety exception). -> XREF: D00 T01 §14 (filed from its first live plan review); -> SOURCE: plan-review-D00-T01-s14-2026-09-18 (`gpt-5.6-sol` high over §14 plus §9, 15 findings, 10 filed here, 5 rejected with reasons in the §14 findings file).

- [x] Stamps carry the plan review's completion: a `Plan review:` line naming the filings or `no findings`, enforced by the validator for stamps after the rule lands. Done when: the skill mandates the line, the validator fires without it, and self-test locks both shapes. **Corrected 2026-09-18 (validation):** the review runs after panel-close and the marker rides the stamp commit (a literal post-stamp review cannot stamp its own marker without amending); the skill's "post-stamp" wording is corrected to that timing, and stamps dated 2026-09-18 or earlier are grandfathered (§14 stays silent). Done: `stamp-no-plan-review` FATAL lands last in the map and README with rule 17 (post-2026-09-18 stamps must carry the marker; undated fail closed); parser captures the `Plan review:` stamp kind; skill mandates the line with after-panel-close timing; self-test gains TODO-07 (fire, silence, cutoff-silence) plus the class check; live drive (scratch post-cutoff stamp fires 1) reverted clean.
- [x] A fallback-run plan review is recorded as same-family: when the Opus rung (not GPT) runs the review, the record says so and drops the second-family claim. Done when: the skill carries the sentence. Done: sentence lands in the plan-review fallback paragraph.
- [x] Review scope adds direct reverse dependents: sections whose Depends On names the section ride inline with prerequisites and neighbors. Done when: the skill names the scope and the lookup method (query or grep) is quoted working. Done: scope plus grep method land; lookup quoted (grep finds §15's Depends row on §14).
- [x] Hung runners fail into the fallback: each runner command carries a timeout, and expiry counts as runner failure. Done when: the skill names both timeouts and a forced hang is observed to reach the next rung. Done: `timeout 600` on the panel command and `timeout 900` on the plan-review command with the 124-falls-through rule (defaults; one number to change); forced hang observed (`timeout 2 sleep 30` exits 124).
- [x] A clean round still writes its record: zero findings lands as an explicit no-findings note, never as silence. Done when: the skill says so with the no-findings shape quoted (live proof rides the first clean review, which this section cannot schedule). Done: sentence plus quoted shape land (marker `no findings` plus the PR0 ledger line).
- [x] Filed findings cite their evidence: every plan-review filing carries the finding's source lines plus a SOURCE key before `add-todo` accepts it. Done when: the skill points at the add-todo evidence rules. Done: sentence lands in the plan-review section.
- [x] Advisory never blocks except when it must: a finding that invalidates safety, data integrity, or the stamp reopens the section through review-todo-section audit stance. Done when: the skill names the exception and the route. Done: sentence lands closing the plan-review section.
- [ ] The record carries the input manifest: which sections rode inline, at what byte count. Done when: the skill mandates the manifest line and §15's own plan review carries the first one.
- [ ] Findings get IDs and dispositions: accepted, filed, duplicate, rejected, deferred, each with its reason. Done when: the ledger shape is specified as grep-able rows (`- [PRn] [critical|major|minor] <finding> -> <disposition> <target-or-reason>`) and §15's own plan review uses it. **Corrected 2026-09-18 (validation):** filed without a shape, which leaves item 10 nothing mechanical to parse; severity rides inline so the query can find criticals.
- [x] A plan-health query reports reviewed sections, uncovered dependents, fallback usage, outages, and unresolved critical findings. Done when: `query plan-health` runs and its output is quoted. **Corrected 2026-09-18 (validation):** dimensions are mechanical: marker presence (reviewed/unreviewed), `## GPT panel` headings (fallback usage), `Opus outage` lines (outages), unmarked reverse dependents of marked sections (uncovered), ledger rows with critical severity not dispositioned `filed` (unresolved criticals). Done: the query lands with all five dimensions plus 5 self-test presence checks; live output quoted in the commit body (0 marked, 0 unmarked post-cutoff, 0 uncovered, 0 fallback files, 1 outage-note file, 0 criticals); Tooling lines in README and AGENTS.md name it.
- [x] Commit: `"workspace: harden plan reviews per first live round"`

**Test checkpoint:** Validator fires on a stamp without the marker; skill carries the scope, timeout, record, exception, manifest, and ledger rules; the plan-health query is quoted; §15's own plan review exercises the new rules. **Corrected 2026-09-18 (validation):** filed pointing at an unscheduled "next" review; §15's own post-panel review is the verifier. Cheaper substitute that fails: prose rules no review follows.

## Verification

- [x] Clean-machine build and test both green from the docs alone. Evidence: §6 cold follows on Linux (0 warnings, Passed 1/1) and Windows (0 warnings, Passed 1/1, stub launch title observed), zero improvisation.
- [x] CI green on `main` with all gates enforcing. Evidence: build run 34793972371 success both jobs and plan-gates run 34793972372 success on the §7 stamp commit.
- [x] `python3 scripts/todo-graph.py validate` clean. Evidence: `19 todos, 106 sections -- 0 fatal, 0 warning(s), 19 adjacency advisory` (all pre-existing kinds) at closeout.
