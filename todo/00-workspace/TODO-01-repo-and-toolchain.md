---
schema_version: 1
id: repo-and-toolchain
domain: 00-workspace
status: active
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
|   7   |   §7    | TODO graph checks in CI | §3 |  [x]   |
|   8   |   §8    | Conclave-PC input capability for automation | -- |  [ ]   |
|   9   |   §9    | Opus panel enforcement in the validator | §7 |  [x]   |
|  10   |   §10   | Opus panel rule hardening follow-ups | §9 |  [ ]   |
|  11   |   §11   | Quote-end lookahead removal | §10 |  [ ]   |

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

## 11. Quote-End Lookahead Removal

Why this section exists: the round-5 Opus panel on §10 (final round, max 5 reached) left one needs-attention: the quote-end lookahead scans the whole remainder for a same-depth close, so a later quoted fence retroactively swallows the lines between (false FATAL on a §24 shape plus a later quoted block; fail-open swallowing a round-2 panel so stale round-1 verdicts read as the record). The same round's consistency lens supplies the fix direction: CommonMark laziness never applies to fenced-code content, so an unquoted non-blank line after a quoted fence always ends quote and fence, and the lookahead branch (plus its lazy comment) should be deleted, not bounded. -> XREF: D00 T01 §10 (filed from its round-5 panel); -> SOURCE: Opus-panel-D00-T01-s10-round-5 (candidate `b6c858b`, NEW-13/14/15; transcribed in `docs/reviews/00-workspace/D00-T01-s10.md`).

- [ ] Delete the quote-end lookahead: an unquoted non-blank line below the open fence's quote depth always closes the fence (no ahead scan). Done when: §24 still passes unmodified, new fixtures lock both round-5 probe shapes (§24 shape plus a later balanced quoted block stays silent; round-2 heading after a quoted fence fires naming the missing lenses), and the mutation map in the checkpoint is re-measured.
- [ ] Correct the record the lookahead left behind: the lazy-content comment in `todo-validate.py`, and the unconditional "an ended quote ends its fence" in `todo/README.md` (the skill already states the no-close-ahead condition; after deletion both state the unconditional rule truthfully). Done when: comment and both docs describe the same rule and no probe distinguishes them.
- [ ] Commit: `"workspace: remove quote-end lookahead from panel rule"`

**Test checkpoint:** `python3 scripts/todo-graph.py self-test` green at the new quoted count; the two NEW-13 probe shapes are fixtures with cases; the §10 checkpoint mutation map is refreshed by measurement, not edited by reasoning. Cheaper substitute that fails: bounding the lookahead window instead of deleting the branch.

## Verification

- [x] Clean-machine build and test both green from the docs alone. Evidence: §6 cold follows on Linux (0 warnings, Passed 1/1) and Windows (0 warnings, Passed 1/1, stub launch title observed), zero improvisation.
- [x] CI green on `main` with all gates enforcing. Evidence: build run 34793972371 success both jobs and plan-gates run 34793972372 success on the §7 stamp commit.
- [x] `python3 scripts/todo-graph.py validate` clean. Evidence: `19 todos, 106 sections -- 0 fatal, 0 warning(s), 19 adjacency advisory` (all pre-existing kinds) at closeout.
