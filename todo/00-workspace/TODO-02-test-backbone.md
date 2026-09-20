---
schema_version: 1
id: test-backbone
domain: 00-workspace
status: active
title: "TODO-02 -- Test Backbone"
track: W0
---

# TODO-02 -- Test Backbone

> **Goal:** The harnesses every test in the project runs on: a unit-test project, a UI automation driver, a golden-capture store, an ACP loopback fixture, and a soak procedure.

> [!IMPORTANT]
> **Current state:** Only `D00 T01 §5`'s `dotnet test` wiring and smoke test exist. The framework is xUnit (operator stack decision); no UI driver exists, no captures exist. This file builds the backbone; `D06 T01` decides what runs on it.
>
> **Corrected 2026-09-17 (groom):** §§1-7 have shipped since (unit project, FlaUI driver spike, capture store, loopback fixture, soak procedure, golden determinism, CI evidence pipeline). Open: §8 only, in progress; since 2026-09-17 the suites it wires run locally on the dev box, not in CI.
>
> **Filed 2026-09-17:** §9 (nightly full-suite regression run). Open: §§8-9.
> **Filed 2026-09-19:** §10 (completion-first night-debt system). Open: §§8-10.
> **Filed 2026-09-19:** §11 (central launch helper with off-screen birth). Open: §§8-11.
> **Filed 2026-09-19:** §12 (accelerator binding coverage sweep). Open: §§8-12.

## Inputs

- [`00-workspace/TODO-01-repo-and-toolchain.md`](./TODO-01-repo-and-toolchain.md) -- §5's `dotnet test` wiring, which this file extends
- -> XREF: D06 T01 §1 -- the automated test strategy this backbone serves; the strategy names suites, this file names harnesses

## Outcome

- Unit, UI-automation, and protocol tests each have a harness wired into one `dotnet test` run.
- Golden captures for parity surfaces live in a committed store with a refresh procedure.
- A loopback ACP agent lets protocol tests run with no network and no API keys.
- Flaky tests are quarantined by procedure, never by deletion.

**Adjacency:** all=not-applicable (test harnesses with no user-facing feature surface; the suites that run on them belong to their own domains)

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Unit test project and framework | T01 §5 |  [x]   |
|   2   |   §2    | UI automation driver spike | T01 §5 |  [x]   |
|   3   |   §3    | Golden capture store and refresh | §2 |  [x]   |
|   4   |   §4    | ACP loopback fixture | §1 |  [x]   |
|   5   |   §5    | Soak and quarantine procedure | §1, §2 |  [x]   |
|   6   |   §6    | Golden comparison deterministic on CI | §3 |  [x]   |
|   7   |   §7    | CI evidence capture pipeline | D01 T02 §14 |  [x]   |
|   8   |   §8    | Focus-free UI suite conversion | §2 |  [x]   |
|   9   |   §9    | Nightly full-suite regression run | §8 |  [x]   |
|   10  |   §10   | Completion-first night-debt system | §8 |  [x]   |
|   11  |   §11   | Central launch helper with off-screen birth | §8, D00 T04 §6 |  [ ]   |
|   12  |   §12   | Accelerator binding coverage sweep | §8 |  [ ]   |
|   13  |   §13   | Backgrounding leak on the default leg | §8 |  [ ]   |
|   14  |   §14   | Run-level deadline for the governed run | §9 |  [ ]   |
|   15  |   §15   | Nightly enforcement and count hardening | §9 |  [ ]   |
|   16  |   §16   | Verify timer-fired completion and green | §9 |  [ ]   |
|   17  |   §17   | Nightly notify plus trend surface | §9 |  [ ]   |

---

## 1. Unit Test Project and Framework

> **Started:** 2026-09-14T01:00:00Z

Why this section exists: unit tests need a home and a framework before the first class lands, or the first class lands untested. UI-free code lives in `net10.0` libraries so these tests run on Linux; Windows-only code stays in the app project.

**Replatformed 2026-09-13:** xUnit on .NET 10, the steward stack; the neutral-library rule above is what lets this suite run anywhere.

**Flag from T01 §5:** re-evaluate xUnit v3 with the MTP runner when standing up this suite: v3+MTP discovered zero tests on our stack (proven on our project and xUnit's own template, so v2 with VSTest shipped); record the re-evaluation verdict in `docs/testing.md` alongside item 1.

- [x] `tests/Unit/` hosts xUnit over the neutral libraries (the shop standard, proven in steward) with the choice recorded in `docs/testing.md`. Done when: the doc names the framework, its pinned versions, and why it won.
- [x] One passing test exercises the choice (a trivial pure function). Done when: `dotnet test tests/Unit` passes on Linux and fails when the assertion is inverted.
- [x] Test-only helpers live under `tests/Common/` so suites share fixtures without reaching into each other. Done when: the directory and its ownership rule exist.
- [x] CI runs the unit suite on every push. Done when: a deliberately failing probe test fails the run (reverted immediately).
- [x] Commit: `"workspace: add unit test project and framework"`

**Test checkpoint:** `dotnet test tests/Unit` green on Linux; inverted assertion red; CI mirrors both. Cheaper substitute that fails: a framework vendored but wired to nothing.

> **Verified:** 2026-09-14 | §1 | Unit 2/2 green locally on both OSes and in CI (run 34794828910); inverted assertion red locally; probe run 34795487610 red both jobs with the test named; run 34796097790 green after revert; v3/MTP re-evaluation reproduced zero-test discovery on the vendor template; validate 0 fatal; self-test 391/391
> **Retired:** 2026-09-19 | D00 T02 §1 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidates f0b847c 1468835 7629678 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s1.md
> **CRUD:** applicable | test runs wrote results (read back via Passed/Failed counts); probe wrote failures (read back via the named test in both CI logs); inverted check wrote red locally
> **Duration:** 45
> **Implementer:** Muse Code (Meta Muse Spark)

## 2. UI Automation Driver Spike

> **Started:** 2026-09-14T01:45:00Z

Why this section exists: "automatic and complete" testing of a WinUI app needs a driver that clicks the real UI. Spike the options before committing the suites to one.

**Needs:** Windows host (build/test)

- [x] `docs/ui-automation-spike.md` compares WinAppDriver and FlaUI (and any third contender) on our stub: launch, click, read text, screenshot. Done when: each contender has a measured verdict, not an opinion.
- [x] The spike picks one driver and records the decision with its cost of reversal. Done when: the doc names the winner and what switching would cost.
- [x] `tests/UI/` runs one passing drive of the stub window (launch, assert title, close) under the winner. Done when: the UISmoke drive passes on a Windows runner in CI.
- [x] The spike records what the driver cannot do (if anything), with each gap routed to a named D06 section. Done when: no silent gaps remain.
- [x] Commit: `"workspace: spike UI automation drivers and wire the winner"`

**Test checkpoint:** The UISmoke drive passes on a Windows runner in CI against the real stub window; the spike doc carries measured verdicts. Cheaper substitute that fails: a driver chosen by reputation with no drive of our binary.

> **Verified:** 2026-09-14 | §2 | FlaUI and WinAppDriver both measured on the stub (FlaUI 506 ms attach, island traversal works; WinAppDriver 3755 ms with admin/client costs); UISmoke green locally and in CI (run 34798097715, UI.dll 1/1) after the crash-dialog red run 34797312338; gaps routed to D06 T01 §1/§3, T02 §3/§5; validate 0 fatal; self-test 391/391
> **Retired:** 2026-09-19 | D00 T02 §2 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidates 749fe22 4eb476f 40d3373 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s2.md
> **CRUD:** applicable | spike drives wrote measurements and screenshots (read back via timings, byte counts, pixels); UISmoke wrote pass/fail plus a failure screenshot path (read back in CI logs)
> **Duration:** 41
> **Implementer:** Muse Code (Meta Muse Spark)

## 3. Golden Capture Store and Refresh

> **Started:** 2026-09-14T02:28:00Z

Why this section exists: parity with Windows 11 Notepad is checkable only against captures. The store makes "matches Notepad" a diff, not an opinion.

**Needs:** Windows host (build/test)

- [x] `resources/baseline/` holds the first captures (main window, tab bar, menus, settings) taken from stock Windows 11 Notepad with the capture procedure in `resources/baseline/README.md`. Done when: each capture names its source build.
- [x] `tests/UI/` compares the app's rendered surfaces against the captures with a committed tolerance policy. Done when: a deliberate 10px layout shift fails the comparison.
- [x] The refresh procedure re-captures after intentional changes and requires review of the diff. Done when: the procedure is written and was used once for real.
- [x] Captures are versioned beside the code they verify, so a checkout is self-consistent. Done when: no capture lives outside the repo.
- [x] Commit: `"workspace: add golden capture store and refresh"`

**Test checkpoint:** A deliberate layout shift fails the comparison; a reviewed refresh passes. Cheaper substitute that fails: screenshots in a chat thread instead of a committed store.

> **Verified:** 2026-09-14 | §3 | 4 stock captures (Notepad 11.2607.14.0) plus app golden with README procedure; comparison green in CI (run 34804426231, UI 3/3) with 10px shift failing (736px vs 410px budget, PIL cross-checked); refresh shakedown reviewed and green (run 34805175346); validate 0 fatal; self-test 391/391
> **Retired:** 2026-09-19 | D00 T02 §3 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidates bf39eb8 9501c57 4d459fd e9414bf 8d866b7 dbcd869 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s3.md
> **CRUD:** applicable | captures wrote pngs (read back via pixels and dims); comparisons wrote fractions plus failure artifacts (read back in CI logs and downloads); refresh wrote new goldens (reviewed pixel by pixel)
> **Duration:** 117
> **Implementer:** Muse Code (Meta Muse Spark)

## 4. ACP Loopback Fixture

> **Started:** 2026-09-14T04:28:00Z

Why this section exists: protocol tests must run with no network, no API keys, and no real agent. A loopback fixture speaks ACP back at the client deterministically.

- [x] `tests/Fixtures/AcpLoopback/` (a `net10.0` console app, spawned through the .NET host on either OS) implements a scripted fake agent over stdio: it answers `initialize`, `session/new`, and `session/prompt` from a script file. Done when: a test drives a full prompt turn against it on Linux.
- [x] The fixture can inject faults on demand (malformed JSON, dropped responses, slow streams). Done when: each fault has a test proving the client survives it.
- [x] The fixture validates every message it receives against the ACP schema and fails loudly on violations. Done when: a deliberately malformed client message fails the test.
- [x] `D03` sections consume this fixture rather than building their own fakes. Done when: the ownership is recorded here and referenced there.
- [x] Commit: `"workspace: add ACP loopback fixture"`

**Ownership:** D00 T02 §4 owns `tests/Fixtures/AcpLoopback/`; consumers are D03 T01 (transport lifecycle) and D03 T02 (client methods), which drive their tests against this fixture and extend it rather than building their own fakes.

**Test checkpoint:** A scripted prompt turn passes; each injected fault is survived; a malformed client message fails. Cheaper substitute that fails: tests that pass against a mock that accepts anything.

> **Verified:** 2026-09-14 | §4 | Loopback fixture plus Protocol suite (turn, 3 faults, 4 validation tests) green locally (Protocol 8/8) and in CI both jobs (run 34807778662, Protocol 8/8; run 34807053331 green at 7/7 before hardening); mutation probe (accepting fixture) red then green on revert; ownership recorded here with D03 T01/T02 back-refs; validate 0 fatal; self-test 391/391
> **Retired:** 2026-09-19 | D00 T02 §4 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidates 6fdfda3 b505081 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s4.md
> **CRUD:** applicable | prompt turns wrote responses plus notifications (read back via chunk text, stopReason, sessionId); faults wrote garbage/timeouts/delays (read back via skip count, TimeoutException, completion); violations wrote errors plus exits (read back via codes 2/-32601/-32602 and stderr); mutation wrote a red test (read back, then green on revert)
> **Duration:** 38
> **Implementer:** Muse Code (Meta Muse Spark)

## 5. Soak and Quarantine Procedure

> **Started:** 2026-09-14T05:08:00Z

Why this section exists: UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks.

- -> XREF: D00 T02 §9 -- flakes the nightly run surfaces quarantine by this procedure; soak stays the flake-hunting repeat loop, the nightly run stays the regression proof.
- -> XREF: D01 T01 §35 -- owns the fix-or-remove windows for the 7 09-20 night-triage quarantines (due 09-27).
- -> XREF: D00 T02 §14 -- run-level deadline this procedure's soak loop must respect.
- -> XREF: D00 T02 §10 -- night-debt collector whose reds stage quarantine-bound findings for triage under this procedure.

- [x] `docs/soak-and-quarantine.md` defines the nightly soak (what runs, how long, where results go). Done when: the soak ran once and its log is linked.
- [x] Quarantine moves a flaky test to a named list with its failure signature and owner, and the suite stays green without it. Done when: the list exists with its fields, even if empty.
- [x] A quarantined test owes a fix or a removal decision within a committed window. Done when: the window and the escalation are written.
- [x] Deleting a test without a recorded decision fails review. Done when: the rule is written in the procedure.
- [x] Commit: `"workspace: add soak and quarantine procedure"`

**Test checkpoint:** A deliberately flaky probe test is quarantined by the procedure, the suite stays green, and the probe is then removed with its decision recorded. Cheaper substitute that fails: a retry loop that hides the flake.

> **Verified:** 2026-09-14 | §5 | Soak workflow plus procedure doc; soak green twice by dispatch (runs 34808621885, 34809456063; 22 passed, 0 failed each) with run links in the doc; probe lifecycle proven locally (pass/fail/fail/fail/fail/pass same binary, quarantined suite green 2+1 skipped twice, removed with decision row); red-repeat swallow fixed in 77aff94 with shell-construct proof; validate 0 fatal; self-test 391/391
> **Retired:** 2026-09-19 | D00 T02 §5 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidates 549ff76 77aff94 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s5.md
> **CRUD:** applicable | probe wrote pass/fail outcomes (read back across six runs); quarantine wrote a skip (read back via Skipped count with suite green); soak wrote trx plus artifacts (read back via 22 Passed lines per run); removal wrote a decision row (read back in the doc)
> **Duration:** 24
> **Implementer:** Muse Code (Meta Muse Spark)

## 6. Golden Comparison Deterministic on CI

> **Started:** 2026-09-17T09:15:39Z

Why this section exists: the golden tests pass on the capture machine and fail on CI for identical code, so every Windows build is red and no push proves itself. **Corrected 2026-09-17:** main is red since run 35028328028 (`511c99a`, 2026-09-15 21:56 UTC), not since 35098508920; the `golden-failure-*.png` artifact signature starts at 35098508920 as stated. HEAD run 35201002875 (2026-09-17, `5165f4b`) carries three signatures, all green-at-stamp on Windows: (A) 16 Unit failures on Linux (`ProtocolAssociationTests`, `LaunchArgsTests`, `JumpListFeedTests` -- reproduced locally, platform-dependent `System.IO.Path` use on Windows-path strings in neutral Core code); (B) 3 golden-pixel failures on Windows (`FreshCaptureMatchesGolden` 0.225% vs 0.1% threshold, `ShellMatchesGolden`, `SettingsCaptureMatchesGolden`); (C) 6 UI-functional failures on Windows (five `MenuBarTests` file-dialog tests plus `FileMenuLiveAcceleratorsWork`; the 09-16 `DirtyPromptTests` failure did not recur on HEAD, flake evidence). Per item 8's fold-in rule this section owns all three: the checkpoint's green CI is unreachable otherwise. Since run 35098508920 (2026-09-16, `224998a`) the `build-windows` job fails at the Test step with `golden-failure-*.png` artifacts (79 KB at run 35100444585, 153 KB at run 35152942415), while the same commits passed the golden tests on Conclave-PC at stamp time (the D01 T02 §3 and §4 reviews quote the suites green). Measured 2026-09-17: the committed goldens are pixel-identical across refreshes inside the compared region yet mathematically flat (backdrop patch red channel mean 45.0, stdev 0.00, no Mica noise), i.e. captured without Mica rendering; `resources/baseline/tolerance.json` allows 0.1% (`maxDifferentFraction` 0.001, `perPixelDelta` 96, top 8% / sides 2% / bottom 3% cropped). A second signature sits in the same window: run 35082905551 (`b5ec3ac`) failed on Windows with NO golden artifacts, a functional failure of unnamed cause (job logs need repo admin rights; unauthenticated API reads return 403). Paths below assume the landed D01 T02 §13 rename (`src/ScratchPad.slnx`); pre-rename the solution is `src/IntelligentNotepad.slnx`.

- [x] Download `golden-failures-windows-x64` from run `35152942415` (operator step, needs auth) and record the failing test names plus each measured diff fraction against the 0.1% threshold in this section. Quoted (HEAD run 35201002875, threshold 0.1% = 500/500256px): `FreshCaptureMatchesGolden` 0.225% (1128/500256) vs main-window.png; `ShellMatchesGolden` 0.225% (same capture bytes, md5 4b893e43) vs main-window.png; `SettingsCaptureMatchesGolden` 0.682% (3414/500256) vs settings-page.png. Artifacts (5 PNGs, both runs): fresh, shell (byte-dup of fresh), settings, fresh-diff, settings-diff; no shell-diff (that test saves no diff). Done when: test names and diff numbers are quoted here. -> SOURCE: CI build runs 35098508920/35100444585/35152942415 (2026-09-16), golden-failure artifacts on Windows, identical code green on Conclave-PC at stamp time. **Corrected 2026-09-17:** HEAD run 35201002875 (2026-09-17, `5165f4b`) is the primary source now (25 failures: 16 Unit Linux, 3 golden, 6 UI-functional); the cited runs stay as supporting evidence. The download is executable in-session (`gh` authed), not an operator wait.
- [x] Name the single renderer difference between the CI fresh capture and the committed golden (Mica present/absent, font smoothing, DPI/scale resampling, DWM composition) with a side-by-side pixel measurement recorded in `docs/reviews/00-workspace/D00-T02-s6.md`. Done when: the difference is named with pixel evidence, not a guess. Named: cross-DPI rasterization noise (goldens rendered at 150% device DPI and downscaled; CI renders natively at 100%; glyph rasterization differs by DPI). Killed with pixel evidence: Mica (backdrop stdev 0.00 both sides), ClearType (inter-channel spread ~0 both sides), translation (shift search all worse), pure resample phase (roundtrip induces 0 diffs). Confirming: half-res collapse 15-18x, golden edges softer than fresh (1506 vs 898 soft px).
- [x] Fix the diagnosed golden cause at its root in `tests/UI/GoldenComparer.cs`, `tests/UI/UiCapture.cs`, or `resources/baseline/tolerance.json` (mask the unstable region, normalize the unstable rendering, or assert the rendering precondition before capture). Done when: the fix and the rejected alternatives are recorded with reasons. Done: 3x3 box blur both sides in `Compare` (noise 1128/3414 to 18/21px, shift still 1069px vs 500px threshold, delta and threshold unchanged) plus `capture: scale/raw` logging in `UiCapture`; rejected threshold raise (noise exceeds signal), 100% re-capture (moves the failure to dev boxes), half-res compare (weakens everything). Full record in the review file. New pin `OnePixelEdgeWobblePassesComparison` green with the `TenPixelShift` guard still red.
- [x] **Corrected 2026-09-17 (added):** Diagnose the UI-functional CI failures (track C: the five `MenuBarTests` file-dialog tests plus `FileMenuLiveAcceleratorsWork` red on HEAD run 35201002875): name each failing test's CI-vs-local difference with CI log evidence, reproduced on a Windows host where the logs underdetermine it. Fix at root in test or app code, whichever the diagnosis convicts, with the fix and rejected alternatives recorded with reasons. Done when: every track-C test passes on the Windows host and the diagnosis for each is quoted here or in the review file. Done: named cause is Explorer extension-hiding (CI `HideFileExt` 1 vs dev 0); all 6 reproduced locally by flipping that bit with CI-identical signatures (MenuBarTests 27/27 with hiding off). Root fix is environmental, so it landed in CI config rather than test/app code: `build.yml` sets `HideFileExt` 0 beside the theme keys (same precondition class), `docs/testing.md` documents both preconditions with verify commands. Rejected hiding-agnostic tests (weakens exact-name assertions). Full record in the review file.
- [x] **Corrected 2026-09-17 (added):** Fix the neutral-suite Linux failures (track A: `ProtocolAssociationTests`, `LaunchArgsTests`, `JumpListFeedTests`, 16 red on Linux CI since `511c99a`, reproduced locally): the tests encode Windows-path semantics and the code must match them on every OS, so replace the platform-dependent `System.IO.Path` use on Windows-path strings in `src/Notepad.Core` (`JumpListFeed`, `ProtocolAssociation`, `LaunchArgs`) with explicit Windows-path handling, and record the rule (neutral code never branches on the running OS for Windows-path strings) beside the fix. Done when: the full neutral scope passes on Linux with zero test edits, or every test edit is justified here as a wrong test rather than wrong code. Done: new `src/Notepad.Core/WindowsPath.cs` (IsRooted/GetFileName/Combine/Normalize with Windows BCL semantics, rule in its doc comment) wired into the three call sites; neutral scope green locally (Smoke 1/1, Unit 333 + 3 skipped, Protocol 35/35, 0 failed). Test edits (justified wrong tests): 7 `Path.Combine(WorkDir, X)` expectations in `LaunchArgsTests` became Windows-spelling literals -- Combine spells the join per the runner OS, so those expectations asserted Linux spellings on Linux while `OtherSchemesStayFileArgs` asserts the Windows spelling, jointly unsatisfiable on Linux by any OS-independent function; the contract is Windows paths on every OS. No other test files touched.
- [x] `resources/baseline/README.md` gains the environment precondition the diagnosis found, with its verification command. Done when: the doc states the precondition and how to check it. Done: Tolerance policy gains the cross-DPI note (blur absorbs ≤3px wobble by design, shifts ≥5px fail with measured floor 1px 0 / 2px 209 / 3px 450 / 5px 640 / 10px 1069 vs 500px threshold; every refresh records capture scale; AppliedDPI/96 verify command).
- [x] Re-prove the full UI suite on a Windows host and quote the next CI `build-windows` job green with zero golden-failure artifacts. Done when: both greens are quoted with the run id. **Corrected 2026-09-17:** also re-prove the neutral scope green on Linux locally and quote CI `build-linux` green: the section's Why ("no push proves itself") is false while either job is red. Done: Windows host `dotnet test src/ScratchPad.slnx` green (Smoke 1/1, Unit 336/336, Protocol 35/35, UI 166 + 1 pre-existing skip, 0 warnings); Linux neutral `dotnet test src/Notepad.Neutral.slnf` green (Smoke 1/1, Unit 333 + 3 skipped, Protocol 35/35); CI run 35208253143 (ship commit `7e0283d`) success both jobs with only the stub artifact, zero `golden-failures-windows-x64`.
- [x] Retire or name the `b5ec3ac` non-golden signature: re-run the current UI suite on Windows; green retires it as unreproduced (recorded here with cause unknown), red names the failing test and folds it into this section's fix. Done when: the signature is retired-with-record or named. Done (named, not retired): run 35082905551's Windows failures are exactly track C (all six dialog tests) plus the DirtyPrompt flake, and its Linux failures exactly track A (all 16) -- no separate signature exists. Goldens passed there only because §1-era chrome kept cross-DPI noise under threshold; §3/§4 chrome pushed it over. Both tracks are this section's fix (items 4-5); the item 7 runs prove them gone.
- [x] Commit: `"workspace: make CI suites green and deterministic"` (**Corrected 2026-09-17:** was `"workspace: make golden comparison deterministic on CI"`; the scope now covers all three red signatures per the fold-in rule.) Done: `7e0283d`, pushed; CI run 35208253143 green both jobs.

**Test checkpoint:** `dotnet test src/ScratchPad.slnx` green on a Windows host and the CI `build-windows` job green with no `golden-failures-windows-x64` artifact. Cheaper substitute that fails: raising `maxDifferentFraction` until CI passes without a named renderer cause. **Corrected 2026-09-17:** strengthened, not narrowed: the neutral scope must also be green on Linux locally, and CI `build-linux` must be green with the same run id. A red Linux job leaves the section's Why ("no push proves itself") false, so the checkpoint as written was insufficient for its own goal.

**Needs:** Windows host (build/test)

> **Verified:** 2026-09-17 | §6 | All 25 HEAD failures fixed at named roots: track A (WindowsPath helper, 3 call sites, 7 test literals) neutral green locally (Unit 333 + 3 skipped) and CI build-linux success; track B (3x3 comparer blur, delta/threshold unchanged) CI noise 1128/3414 to 18/21px with 10px shift still 1069px vs 500px threshold; track C (HideFileExt 0 CI step) all 6 dialog tests reproduced locally under hiding and green without. Windows host slnx green (Smoke 1/1, Unit 336/336, Protocol 35/35, UI 166 + 1 pre-existing skip, 0 warnings); CI run 35208253143 success both jobs with zero golden-failure artifacts; b5ec3ac named as tracks A+C; validate 0 fatal
> **Retired:** 2026-09-19 | D00 T02 §6 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** round 1, candidate 7e0283d + record ticks -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve (source-defect/design not owed). Raw findings: docs/reviews/00-workspace/D00-T02-s6.md
> **CRUD:** applicable | CI runs wrote conclusions plus artifacts (read back via success, suite counts, artifact names); golden artifacts wrote PNGs (read back via md5, pixels, PIL comparer replica to exact CI counts); registry wrote HideFileExt flips (read back via 6/6 reproductions, restored to 0); comparer wrote blurred diffs (read back via wobble pin green and shift probe red); suites wrote passes (read back via Passed/Failed counts on both OSes)
> **Duration:** 61
> **Implementer:** Muse Code (Meta Muse Spark)

## 7. CI Evidence Capture Pipeline

> **Started:** 2026-09-17T13:58:00Z

Why this section exists: eyeball-evidence crops (D01 T02 §14 item 4 is the first) cannot be taken from a window-station-less session: screen reads return black and input is dead, measured on Venom-PC (golden fresh byte-identical to a black frame, `CopyFromScreen` invalid handle). CI windows runners have displays, so the pipeline captures there: a windows-job step runs `tools/CaptureBaseline` against the built exe and uploads the PNG as an artifact, and the evidence procedure (download, eyeball checklist, commit naming) lands in `resources/baseline/README.md`. -> XREF: D01 T02 §14 (first consumer; its item 4 is deferred here); -> SOURCE: CI-evidence-gap-2026-09-17 (Venom-PC headless session, black captures, D01 T02 §14 item 4 blocked).

- -> XREF: D01 T02 §16 -- filed from this section's pipeline run (MenuBarTests flakes blocked the first artifact).
- -> XREF: D01 T01 §32 -- filed from this section's pipeline run (AppIcon plus Launch flakes on the round-2 run).
- -> XREF: D06 T01 §6 -- this section's round-4 run is filed there as the first mass-failure incident verdict.

- [x] The windows CI job captures the built app and uploads the PNG as an `evidence-capture` artifact on green builds (red builds already upload golden failures). Done when: a main run carries the artifact with a non-black 900x650 PNG. First use is this section's item 2, not a synthetic probe. Done: `build.yml` gains Capture evidence frame (default success() condition, so red builds skip it) plus Upload evidence capture; run 35230396785 carries `stub-window.png`, 900x650, extrema (12, 255), 28 KB. The first attempt went red on a `FileSaveAllWalksDirtyTabs` UIA-timeout flake (capture correctly skipped, no artifact); the `--failed` rerun of the same commit went green and uploaded. Round-2 (panel fixes: profile reset, WhatsNewSeen seed, CI black-frame assert): run 35234746568's first attempt went red on three more same-family flakes (`WindowChromeIconMatchesAsset` UIA timeout, `MissingFileOfferYesBindsTabAndSaveCreates` null dialog, `FileMenuLiveAcceleratorsWork` null element; capture correctly skipped), the rerun went green and uploaded a fresh frame (900x650, extrema (12, 255)) with the black-frame assert passing. Round-3 (size assert, orphan kill, `$appProfile` rename): run 35239792170 green with both asserts exercised. Round-4 (kill-then-wait race close, comment catch-up, run citation): run 35241743948 attempt 3 green (attempts 1-2 red-flagged 34 then 9 UI tests on identical binaries, proven environmental by the green third; the capture step never failed). All five flakes filed for quarantine (MenuBarTests trio in D01 T02 §16, AppIcon plus Launch pair in D01 T01 §32).
- [x] Eyeball evidence of the dressed tab row is committed. Done when: the chrome crop sits beside the D01 T01 §11 crops in `resources/baseline/app/`, captured via item 1's pipeline and eyeballed (glyph present left of the first tab, 16px, stock placement). Done: `resources/baseline/app/titlebar-icon-evidence.png` (320x110, box (8, 0, 328, 110); the left 8px carried see-through edge pixels of a background window, so the box starts inside the clean edge), first taken from run 35230396785 and eyeballed (glyph left of the tab, 16px, stock placement; border bleed handled by the x=8 inset). **Corrected 2026-09-17 (§7 panel round 1):** that frame restored the UI suite's leftover session (the suite drives the real profile and no reset preceded the capture), so the crop was re-taken from the fresh frame: `titlebar-icon-evidence.png` (320x110, box (8, 0, 328, 110) of run 35234746568's `stub-window.png`), eyeballed clean: glyph left of a clean Untitled tab, 16px, stock placement; frame foreground, canonical, window unoccluded, no bleed in the box. The "4 characters" dirty tab in the first frame was suite residue, confirmed by the fresh frame's "0 characters" clean tab: D01 T01 §31 (filed from the residue) is unfiled the same day, its address left vacant.
- [x] `resources/baseline/README.md` documents the evidence procedure: which artifact, the eyeball checklist (foreground, unoccluded, canonical size, intended pixels only), and the commit naming. Done when: item 2 is produced by following the procedure verbatim. Done: `## Evidence procedure` lands with artifact, download plus verify commands, crop step, checklist, and naming; item 2 followed those steps verbatim (same download, same verify one-liner, PIL crop, checklist eyeball, `-evidence.png` naming beside the §11 crops).
- [x] Commit: `"workspace: capture UI evidence on CI"`. Done: `bb2d879` (pipeline plus Started); the crop, procedure, and ticks ride the evidence commit, since the artifact can only come from a main run of the pipeline commit.

**Test checkpoint:** CI artifact present and non-black; §14 crop committed and eyeballed; a second section could follow the procedure without asking. Cheaper substitute that fails: an operator capture with no pipeline behind it.

> **Verified:** 2026-09-17 | §7 | CI evidence pipeline live and verified whole: green Windows builds reset the suite-driven profile, seed `WhatsNewSeen`, capture a canonical frame via `tools/CaptureBaseline stub`, and assert 900x650 plus non-black before uploading `evidence-capture` (red builds skip to golden failures); fresh frame from run 35234746568 (900x650, extrema (12, 255)); `titlebar-icon-evidence.png` (320x110, box (8, 0, 328, 110)) eyeballed clean beside the §11 crops, resolving the §14 deferral; README evidence procedure followed verbatim for the crop; ship run 35241743948 attempt 3 success both jobs with the capture step green (attempts 1-2: 34 then 9 UI reds on identical binaries, proven environmental by the green third; the capture step never failed)
> **Retired:** 2026-09-19 | D00 T02 §7 | predates plan-review lineage; exempt by the 2026-09-18 cutoff; record stands as shipped (D00 T01 §26)
> **Review:** rounds 1-4, candidates bb2d879 bcb6bb4 c07b2c6 91e6d46 98140ed 821f233 -- Opus panel `adversarial` approve · `consistency` advisory · `integration` approve · `record` advisory, all four round-4 advisories fixed in the stamp commit (comment mechanism wording, run-35241743948 citation, incident-note refresh, D06 T01 §6 XREF pair). Raw findings: docs/reviews/00-workspace/D00-T02-s7.md
> **CRUD:** applicable | CI runs wrote conclusions plus artifacts (read back via success, job conclusions, artifact names plus bytes); downloads wrote frames (read back via PIL size plus extrema, then eyeballed); crops wrote PNGs (read back via dims plus eyeball); reruns wrote attempts (read back via conclusions per attempt); filings wrote sections (read back via validate plus plan --check)
> **Duration:** 152
> **Implementer:** Muse Code (Meta Muse Spark)

## 8. Focus-Free UI Suite Conversion

> **Started:** 2026-09-17T18:41:31Z

Why this section exists: the UI suite cannot run while the operator works. Measured 2026-09-17: 112 focus-dependent input calls (`Keyboard.Press` 61, `Keyboard.Pressing` 34, `Keyboard.Type` 9, `Mouse.*` 8) that need the app in the foreground, **Corrected 2026-09-17 (§8 validation):** filed as 104, the keyboard subtotal; the 8 mouse calls bring it to 112. so a full run steals focus repeatedly and mistypes into operator windows on any timing slip. CI no longer runs UI tests (operator decision 2026-09-17: CI proves build plus launch smoke only), so the per-section regression gate must run on the dev box without interrupting it. -> SOURCE: focus-free-mandate-2026-09-17 (operator instruction: uninterrupted per-section full-suite runs on Venom-PC, plus the suite input audit of the same day).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §9 -- the nightly run executes this fence; the three tiers (Run A default, Run B Primary, Interactive collection) are that run's three legs. **Corrected 2026-09-20 (§9 plan review PR1):** was two tiers/halves.
- -> XREF: D00 T02 §10 -- completion-first hardening plus the collector that collects this section's Interactive debt.
- -> XREF: D00 T02 §11 -- central-launch plus off-screen-birth hardening filed from this section's Sol panel round 2.
- -> XREF: D00 T02 §12 -- accelerator binding coverage sweep filed from this section's Opus panel round 5.
- -> XREF: D00 T02 §13 -- backgrounding-leak diagnosis filed from the §9 task-run triage (gate primary=1 on both 09-20 runs).

- [x] Every `Keyboard.*` and `Mouse.*` call in `tests/UI/` is dispositioned to convert-to-pattern, fence-as-interactive, or keep-with-reason, recorded as an audit table. Done when: the table quotes all 112 calls with a disposition each. **Corrected 2026-09-17 (§8 validation):** filed as 104; re-derived 112. Done: `docs/ui-input-audit.md` quotes all 112 (final: 87 convert, 25 fence, 0 keep; **Corrected 2026-09-19 (§8 R5):** was 88/24, recount quoted). **Corrected 2026-09-17 (§8 item 2):** scope grew three more times during implementation: 22 cursor-moving `.Click()`/`.DoubleClick()`/`.RightClick()` sites (final: 1 convert, 17 fence, 4 keep-with-reason) plus 51 `.Focus()` sites (dispositioned by rule: dropped in default tests, kept in fenced tests) plus 2 raw `mouse_event` helpers (both fence), all appended to the same table with per-row corrections. Full inventory is 187 sites.
- [x] Convertibles move to UIA patterns (`ValuePattern`, `InvokePattern`, selection) behind one shared helper, and the converted tests stay green locally. Done when: the default trait-filtered run passes with zero focus-dependent calls outside the fenced set. **Corrected 2026-09-17 (§8 validation):** filed as unfiltered `dotnet test tests/UI`, which contradicts item 3's fence; the gate is the default run. Done: Run A green 2026-09-19 (default filter with `-e SCRATCHPAD_BACKGROUND=1`: 162 passed, 3 skipped, 0 failed, 9m29s, re-proofed after the R4 loop) with ForegroundLog clean (flagged=0, census 739, primary=0, exit 0); golden-capture DPI fix in `tests/UI/UiCapture.cs` (window-DPI re-placement via `GetDpiForWindow`: primary-registry 1.5x sizing laid out 1350 effective px off-screen at 100% and shrunk content to 0.667x, fresh/shell 690px plus settings 5905px vs 500px threshold) focused-proof 5/5 backgrounded; slnx builds 0 warnings 0 errors.
- [x] True-interactive tests (whose point is physical input: shortcuts, focus behavior) are fenced behind a trait excluded from the default run and runnable visibly on demand. Done when: the default run activates no window (proven by a foreground log) and the fenced set passes visibly. **Revision (operator 2026-09-19):** completion-first ships the fence with the visible pass as night debt (hardened by D00 T02 §10): Done-when now reads fenced plus skip-proof plus `Night-owed`, and the visible pass executes in the collector window. Done: 28 tests fenced behind `Category=Interactive` (Run A proves the default activates nothing); daytime fenced-filter run skips 28/28 in 35ms with the 02:00-06:50 reason quoted; Night-owed D00-T02-S8-N1 (28 Interactive, collector Nightly UI 02:30).
- [x] Spooler-dependent tests skip honestly when the context enumerates zero printers (test-side `InstalledPrinters` probe with a reason naming the blind context); no Interactive fence, since `/pt` runs headless with no window and no foreground. Print coverage never targets hardware (operator rule 2026-09-18: an earlier run spooled a page to the physical Canon): real-print tests run only against virtual (PDF/XPS) printers and skip otherwise. Done when: the print tests pass-or-skip in the default run from the agent context with zero pages to hardware. **Corrected 2026-09-17 (§8 item 2):** filed as a full-token wrapper; the `/IT` task context proved equally printer-blind (WSL-spawned and `/IT` both see zero via .NET while WMI sees 8), so no wrapper can print from the agent context, and fencing is wrong because headless prints never interrupt. The raw-`EnumPrinters`-returns-8 finding stays the future product fix path (test-side P/Invoke presence checks, or product-side raw enumeration), not this section. -> SOURCE: `EnumPrinters` probe 2026-09-17 (raw API count 8, .NET `InstalledPrinters` 0, medium integrity, session 1). Done: `PrinterFactAttribute` skips at discovery on zero printers (blind-context reason) and on a hardware default (names it; virtual is a PDF/XPS name match per the operator rule); this box (9 printers, Canon default): `PrintFlagPrintsThenCloses` skipped with the hardware reason quoted, `PrintToBogusPrinterExits2` passed, zero pages spooled.
- [x] `docs/testing.md` documents the uninterrupted gate: the exact default-run command, the fenced on-demand command, and what green means for each. Done when: a second section can follow it without asking. Done: `## Uninterrupted gate` lands with both commands, the ForegroundLog proof rule, and the audit link; stale CI-gates-tests lines corrected to build-plus-smoke.
- [x] Fenced Interactive tests self-skip outside the operator's foreground window (02:00-06:50 local) through one shared discovery-time gate, so a daytime full run cannot interrupt. Done when: boundary fixtures pin the window math, a trait-pairing guard fails any fenced test missing its gate, a daytime fenced-filter run skips every Interactive test with the window named, the nighttime full run executes them, and the window plus overrides are recorded in `docs/testing.md`. -> SOURCE: operator-schedule-2026-09-17 (bed 02:00, resumes 06:50; hard enforcement of the item-3 fence). **Revision (operator 2026-09-19):** the nighttime execution half is Night-owed D00-T02-S8-N1 under completion-first (D00 T02 §10 hardens); Done-when now proves the gate daytime and owes the night execution. Done: `tests/UI/UiQuietHours.cs` window math pinned by `tests/UI/QuietHoursTests.cs` boundary fixtures, `EveryGatedTestCarriesTheInteractiveTrait` pairing guard green in Run A, daytime fenced-filter run skips 28/28 with the 02:00-06:50 reason plus `SCRATCHPAD_INTERACTIVE_FORCE=1` override quoted from trx, window plus overrides recorded in `docs/testing.md`. Review fix: reverse guard `EveryInteractiveTraitCarriesAGate` (trait without gate would run unfiltered daytime): green 20/20 with the suite, red-proven against a temporary violator.
- [x] Suite display funnel: every app window the suite creates (first, second, redirect-created) routes through `UiForeground.Background` (secondary-monitor working area, off-screen fallback, `SetWindowPos` result checked loud). Done when: the launch-without-background query returns empty and picker unit tests cover multi, single, and largest-secondary layouts. Done: `SetWindowPos` throws loud with the Win32 error; the method-level attach-vs-`Background` query (fenced tests excluded by design) found 2 misses (`ShellLinkOpensTheFile`, `CaptureInner`), both routed through `Background`, query now 0 offenders; picker layouts covered by `UiForegroundTests` (multi, single, largest-secondary). **Revision (operator 2026-09-19):** testing everything on the secondary is counterproductive for multi-monitor, positioning, and DPI coverage (this box: 4K/150% primary plus 1080p/100% secondary), so the funnel gains an `InPlace` leg: declared primary-premise tests show no-activate where the app put them, carry `Category=Primary`, and prove placement in a separate census run. Focus-free is unchanged: neither leg activates. R3 fix: two mid-test second windows bypassed both legs (MultiWindowTests cascade plus close-preserve `WaitForWindowCount` picks); routed through `InPlace` (Primary cascade, no move so the premise holds, plus a placed-bounds tripwire after the vacuity probe showed UIA reports restore bounds) plus `PlaceForBackground` (default close-preserve); extended second-window query over test methods reports 20 enumerations, 0 offenders (fenced excluded, close/wait helpers out of scope). R4 fix: Category=Primary gated by `[PrimaryFact]` (runs only backgrounded or in-window/forced; unflagged daytime skips 2/2 in 5ms with the flag named) plus both pairing guards; MenuBarTests FileNewWindow second routed (`PlaceForBackground`); per-pick second-window query reports 13 picks, 0 offenders.
- [x] Background launch never activates (product): under `SCRATCHPAD_BACKGROUND=1` windows show no-activate with `WS_EX_NOACTIVATE` and `Activate` is never called. Done when: a single-test foreground probe shows zero holds and the app build stays 0 warnings. Done: single-test probe (`SingleFileLaunchOpensTab` backgrounded, 60s log) shows flagged=0, census primary=0, exit 0; app builds 0 warnings. Census needed a PerMonitorV2 manifest: without it DPI virtualization misreported the secondary window on primary.
- [x] The four missed tests background all their windows (`SecondLaunchRedirectsFileIntoFirst`, `BareSecondLaunchOpensNewWindow`, `OpenInNewWindowModeOpensSecondWindow` including its second window, `NewNoteRedirectOpensFreshTab`). Done when: all four pass backgrounded. Done: `BareSecondLaunchOpensNewWindow` was the only miss (enumerated second window never backgrounded); fixed with the per-window `Background` loop; 4/4 green backgrounded in 10s.
- [x] `OpenInNewWindowModeOpensSecondWindow` diagnosed (second window's tab name reads null backgrounded, passes foreground) and fixed at the root cause. Done when: green backgrounded and foreground with the cause quoted in the item. Done: cause is wrong-window pick, not a backgrounded read failure: both windows hold exactly one tab, so the most-tabs pick ties and falls back to enumeration (Z) order, which the background move reshuffles; fixed by hwnd identity (`Single(w => hwnd != firstHwnd)`, comment in `tests/UI/LaunchTests.cs`) plus `lastValueOnTimeout` on the window-count retry; foreground was already green (symptom baseline), backgrounded green in Run A.
- [x] Window census joins the gate: the foreground proof records every app HWND with monitor, rect, and iconic state, and the gate asserts zero suite windows on the primary monitor plus zero holds. Done when: a full default run log is quoted clean on both assertions. **Revision (operator 2026-09-19):** the gate splits into Run A (default set: zero holds plus zero primary) and Run B (`Category=Primary`: zero holds plus at least one window resting on primary, asserted by `--expect-primary`). Done-when now quotes both logs clean. Done: Run A `build/gate-final3.log` clean (flagged=0, census 739, primary=0, exit 0; suite 162 passed, 3 skipped, 0 failed; birth flashes collapsed 61 to 2 visible-primary transients after the sleep-after-move fix; lines upgraded to resting state, 145 resting-visible secondary/offscreen); Run B `build/gate-primary4.log` clean (flagged=0, census 11, primary=1, exit 0; suite 2/2 in 5s; seeded rest `primary 100,100,900x650`).
- [x] Fence-with-proof rule in `docs/testing.md`: a test is fenced only with a quoted background-fail plus foreground-pass pair. Done when: the rule is written and every fenced test cites its pair or a grandfather note. Done: rule written (`## Fence-with-proof rule`); all 28 remaining fenced tests cite (26 new grandfather notes citing audit section or mechanism, 2 pre-existing `// Fenced:` notes; the other 2 pre-existing fences moved to `Category=Primary` with cited pairs under the item 7 revision); citation sweep 0 missing.
- [x] System picker and dialog HWNDs land on the secondary monitor (enumeration/watcher) or their tests fence. Done when: the full-run census shows no dialog HWND on the primary monitor. Done: Run A census records every app HWND with monitor plus rect plus iconic state and asserts primary=0 across 739 census lines, so no dialog HWND rested on primary; no new fences owed. **Corrected 2026-09-19 (§8 R5):** was 746 (retired Run A); re-proof log quoted.
- [x] Commit: `"workspace: convert UI suite to focus-free input"`

**Test checkpoint:** The default `tests/UI` run passes locally while the operator's foreground window never changes (foreground log quoted); the placement run passes with its census on primary; the fenced set is fenced plus skip-proofed with its visible pass Night-owed to the collector (**Revision (operator 2026-09-19):** completion-first, hardened by D00 T02 §10; was "the fenced set passes in a visible on-demand run"). Cheaper substitute that fails: running the suite while the operator is away and calling it uninterrupted.

> **Review:** rounds 1-5 (FINAL), candidates dc2dbc7 6d1a8be 67f2f21 0242f52 14ccfb0 04a5a6a 67b88bc 3d7f658 -- `adversarial` approve (R1 steal, R2 flashes, R3 vacuity-claim, R4 Primary gate fixed; R5 approve) · `consistency` needs-attention (R5 accelerator filed D00 T02 §12; R1/R3/R4 docs fixed) · `integration` approve (R1 style, R3/R4 bypasses fixed; R5 approve) · `record` needs-attention (R5 tally plus quote typos corrected in this commit; R1/R2/R3/R4 record fixed). Raw findings: docs/reviews/00-workspace/D00-T02-s8.md
> **Plan review:** Sol high, 11 targets, 3 corrected in place (D00 T02 §9, D06 T01 §3, D06 T01 §4), 8 rejected with reasons, 0 filed (run 20260919-D00-T02-S8-gpt)
> **CRUD:** applicable | review read candidate diff plus contract plus corpus (no writes outside the candidate); implementation converted tests plus funnel plus gates (read back via Run A 162/3/0, Run B 2/2, skips, guards); filings opened D00 T02 §10/§11/§12 plus plan rows (read back via plan --check current)
**Night-owed:** D00-T02-S8-N1 (28 Interactive, collector Nightly UI 02:30, first collection due the coming window). Collected 27 of 28 2026-09-20 (evidence in §9's review file); closure owned by §10. **Corrected 2026-09-20 (§9 plan review PR2).**
> **Verified:** 2026-09-19 | §8 | Run A 162/3/0 flagged=0 primary=0 plus Run B 2/2 flagged=0 primary=1 plus skips 28/28 and 2/2 plus guards 22/22 plus slnx 0/0; Full panel (Sol R1-R2, Opus R3-R5) over 8 candidates, R5 below-bar only (accelerator filed §12, 2 typos corrected here); plan review 11 targets, 3 corrected, 8 rejected; Night-owed D00-T02-S8-N1 (28 Interactive, collector Nightly UI 02:30); validate 0 fatal.

## 9. Nightly Full-Suite Regression Run

> **Started:** 2026-09-20T01:09:18Z

Why this section exists: the fenced Interactive set has no owner, no schedule, and no record: per-section gates prove the background-safe default run, and nothing proves the whole. The nightly run closes that: one governed full-suite execution while the operator sleeps, with its evidence filed where the next morning finds it.

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §8 -- the fence this run executes; the three tiers (Run A default, Run B Primary, Interactive collection) are this run's three legs. **Corrected 2026-09-19 (§8 plan review):** was two halves; §8 shipped Run B plus completion-first debt.
- -> XREF: D00 T02 §5 -- flakes this run surfaces quarantine by that procedure; soak stays the flake-hunting repeat loop, this run stays the regression proof.
- -> XREF: D00 T02 §10 -- debt ledger plus collector plus morning report that this run executes.
- -> XREF: D01 T01 §34 -- filed from this section's night triage (pinned-tab close regressions, red both runs).
- -> XREF: D01 T02 §16 -- two flakes filed into its list from this section's night triage (FileOpen plus LiveItems).
- -> XREF: D00 T02 §13 -- backgrounding leak filed from this section's task-run triage (gate exit 1, primary=1).
- -> XREF: D01 T01 §35 -- owns the fix-or-remove windows for this section's 7 night-triage quarantines (due 09-27).
- -> XREF: D00 T02 §14 -- run-level deadline filed from this section's R4 review (worst-case legs exceed PT4H).
- -> XREF: D00 T02 §15 -- enforcement plus count hardening filed from this section's R5 review.
- -> XREF: D00 T02 §16 -- timer verification filed from this section's plan review (PR3, PR4, PR12).
- -> XREF: D00 T02 §17 -- notify plus trend surface filed from this section's plan review (PR32).

- [x] `docs/testing.md` carries the nightly procedure: trigger (nightly cron inside 02:00-06:50; operator bedtime call stays as manual backup), the three legs (Run A background-safe default with foreground-plus-census proof, Run B Primary with `--expect-primary`, then the Interactive collection run), and the pass/fail bar for each leg. Done when: a second operator can run it or read the cron without asking. **Corrected 2026-09-19 (§8 plan review):** was two halves. Done: "Nightly regression run" section (trigger task plus manual backup, three legs with commands, bars, log convention, report format, abort rules, pre-flight reap).
- [x] Nightly logs land under `build/nightly/YYYY-MM-DD-HHmmss-{default,primary,full}.log` (ignored scratch, never committed) with the suite scope and build-time HEAD recorded at the top. Done when: the convention is written and the first logs follow it. **Corrected 2026-09-19 (§8 plan review):** was `{default,full}`; Run B owns the primary log. **Corrected 2026-09-20 (R1):** was day-scoped; same-day runs overwrote and merged (report HEAD `a8127c7` against Run A log `7ec7495`), so each invocation owns its stamp directory. **Corrected 2026-09-20 (FL5):** was "section range"; the header carries the suite scope (a whole-tree run has no section range) — wording only. Done: convention in testing.md; first stamped logs from the FL2 proofs (`2026-09-20-054411-smoke.log`, dirs `2026-09-20-054325/` and `2026-09-20-054451/`). FL5 re-proof: `2026-09-20-061900-smoke.log` carries the scope-plus-HEAD header (smoke branch converted to Start-LegLog).
- [x] The morning report names per-tier counts (default, primary, interactive: passed, failed, skipped-with-reason) and files every failure as a finding in the owning file before the next section starts. Done when: the report format is written with one worked example, and the report lands at a fixed path the operator checks first. **Corrected 2026-09-19 (§8 plan review):** was per-half. Done: format in testing.md; `build/nightly/morning-2026-09-20.md` landed with per-leg counts; triage appended filings for all 11 failures (2 to D01 T01 §34, 2 to D01 T02 §16, 7 quarantine rows).
- [x] The Interactive tier collects inside the quiet-hours window with zero quiet-hours skips (citing the §8 gate proof, not re-owning it), closing open `Night-owed` debt per D00 T02 §10. Done when: the full log shows the interactive count executed. **Corrected 2026-09-19 (§8 plan review):** was "fenced half"; collection and debt named. Done: `interactive.trx` 28 total, 27 executed, 1 quarantine skip, zero quiet-hours skips; N1 27 of 28 collected (§10 owns the close).
- [x] The first governed run executes the procedure end to end on the cron (bedtime trigger stays as manual backup) and its evidence (all three logs plus the morning report) is quoted here. Done when: the log paths and the report are cited with their outcomes. **Corrected 2026-09-19 (§8 plan review):** was both logs. **Corrected 2026-09-20 (R1):** both re-run gate codes were blank, not exit 0; the re-run executed all three legs end to end on the manual backup trigger, and cron-path proof rides the demand-fired task run. **Corrected 2026-09-20 (FL2):** Run A restored to 545 passed (Smoke 1, Unit 346, Protocol 35, UI 163) after an FL1 over-correction to the UI-only report row. Done: re-run 03:20 (manual `-SkipSoak`, in-window): Run A 545 passed, 1 failed, 3 skipped, gate blank-code with verdict "flagged=0; census=743 primary=1 expect=secondary", test-seconds 621; Run B 2 passed, gate blank-code with verdict "flagged=0; census=11 primary=1 expect=primary", test-seconds 7; Interactive 24/3/1 of 28; archived at `build/nightly-rerun-2026-09-20/` (`2026-09-20-default.log`, `2026-09-20-primary.log`, `2026-09-20-full.log`, `morning-2026-09-20.md`). Task run 04:13:43 (demand-fired, full legs plus soak): Run A 540/0/9, gate exit 1 (primary=1, filed D00 T02 §13); Run B 2/0/0, gate exit 0; Interactive 24/2/2 (both in §34); soak 10/10 green; Last Result 1; archived at `build/nightly-taskrun-2026-09-20/` (same four names plus `2026-09-20/` trx and gate logs).
- [x] The nightly cron exists (recurring inside 02:00-06:50, operator-set 2026-09-18): Run A default with foreground-plus-census proof, Run B Primary with `--expect-primary`, then the Interactive collection, with abort and report rules stated. Done when: the cron fired once end to end or a dry run is quoted. **Corrected 2026-09-19 (§8 plan review):** was default-then-fenced. **Corrected 2026-09-20:** trigger boundaries read 2026-09-19, not 2026-09-18 (`\ScratchPad\Nightly UI` daily 02:30 local, action `tools\nightly.ps1`, 4h limit; sibling `\ScratchPad\Nightly Foreground Single` daily 02:05 runs one foreground test and stays out of this section's scope). Done: task verified live 2026-09-20 (absolute-path action, Start In repo root, Run As DerickPayne, daily 02:30, IgnoreNew, PT4H, WakeToRun, InteractiveToken); timer fire 02:30:01 (parent died mid-loop, cause unknown; mutex plus guard cover the class); demand-fired dry run 04:13:43 completed 05:38:07 (all legs plus soak plus report, Last Result 1: gate primary=1 plus 2 known §34 fails; both gate codes captured non-blank, proving the job capture in situ; logs plus report at `build/nightly-taskrun-2026-09-20/` (`2026-09-20-default.log`, `-primary.log`, `-full.log`, `morning-2026-09-20.md`, `2026-09-20/` trx)).
- [x] The guard cron never injects into a live turn: it skips every fire while a turn holds the token (resurrection of an idle session only, never keepalive of a live one). Done when: the cron is created with the skip-if-active flag and a live-turn fire is observed to skip without touching the turn. -> SOURCE: guard-killed-run-2026-09-18 (03:23 SAST heartbeat fired into a live turn, `inbox_delivery_anomaly deferred_token_held`, turn plus background suite run cancelled; session seq 12350-12372). Done: cron `7e89433d` (`*/10 2-6 * * *`, skip-if-active); no fire across the 04:00-04:30 slots while this turn held the token (`fire_count` frozen at 3, last fire the idle ~03:50 rule-2 exit); zero injections.
- [x] Commit: `"workspace: govern the nightly regression run"` (range `2e40b8d`..`cfb18e2` plus stamp; no single commit carries the message verbatim)

**Test checkpoint:** Procedure, log convention, and report format written; first governed run quoted with all three logs; Interactive tier collected in-window. Cheaper substitute that fails: an ad-hoc night run whose evidence lives in chat. **Corrected 2026-09-19 (§8 plan review):** was both logs plus fenced half.

> **Review:** rounds 1-5 (FINAL), candidates `2e40b8d` `7ec7495` `ce19202` `2fd0ea4` `31923a6` `1a6b781` `5a006c9` `2dd6a07` `cfb18e2` -- Sol R1 4x needs-attention over 10 findings (FL1 plus FL2: job timeouts, mutex, failing skips, stamp-scoped evidence, transcript skip merge, live task record, honest ticks, §13 filing); Sol R2 3 needs-attention plus 1 defended (FL3); Opus R3 4x needs-attention (FL4: 1800s caps, switch docs, svchost branch, §35 filing); Opus R4 blocking re-sign-off 3 needs-attention (FL5: F1 defended by experiment, §14 filed, soak doc synced, suite-scope wording); Opus R5 final 2 advisories filed §15 plus arithmetic fixed (FL6, panel closed). Raw findings: docs/reviews/00-workspace/D00-T02-s9.md
> **Plan review:** Sol tier, 32 targets, 2 corrected in place (D00 T02 §8 XREF, D00 T02 §8 N1), 28 filed (D00 T02 §13, D00 T02 §14, D00 T02 §15, D00 T02 §16, D00 T02 §17, D01 T01 §34, D01 T01 §35), 2 deferred with trigger (PR24, PR25: text lost to compaction, re-derive at next plan review) (run 20260920-D00-T02-S9-plan)
> **CRUD:** applicable | review read candidate diff plus contract plus corpus (no writes outside the candidate); implementation wrote procedure plus script plus docs plus filings (read back via re-run legs, task-run legs, gates, report, plan --check current); filings opened D00 T02 §13/§14/§15/§16/§17 plus D01 T01 §34/§35 (read back via validate clean)
> **Verified:** 2026-09-20 | §9 | re-run Run A 545/1/3 plus Run B 2/0/0 plus Interactive 24/3/1, task-run Run A 540/0/9 (gate primary=1 filed §13) plus Run B 2/0/0 plus Interactive 24/2/2 plus soak 10/10; Full panel (Sol R1-R2, Opus R3-R5) over 9 candidates, R5 advisories filed §15; plan review 32 targets, 28 filed, 2 corrected, 2 deferred; N1 27 of 28 collected (§10 owns the close); validate 0 fatal.

## 10. Completion-First Night-Debt System

> **Started:** 2026-09-20T04:52:13Z

Why this section exists: sections stall waiting for the 02:00-06:50 quiet window to prove focus-needing tests, so completion-first becomes the rule: a section ships its focus-free proofs, records Interactive skips as structured night debt, and flips the same session while the nightly collector closes the debt async, and runners plus reviewers plus the plan all know the rule so nothing parks on quiet time again. -> SOURCE: operator-completion-first-2026-09-19 (operator instruction 2026-09-19: never wait for quiet to test, review, stamp, or flip; ship what proves focus-free and skip the rest as debt; completion-first binds runners, reviewers, and the plan; workspace self-repair ends manual timer, hook, and workflow tweaks). Box facts the design rests on: Venom-PC never locks, the 4K 150% display is the always-attached primary, the 1080p 100% display is the secondary, so locked-box and missing-monitor are never debt causes.

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §8 -- the fence tiers this system collects; §8's stamp records the completion-first default this section hardens.
- -> XREF: D00 T02 §9 -- the nightly run executes the collector halves; the run-guard stays §9 item 7 and quarantine stays §5.
- -> XREF: D00 T02 §5 -- red collections stage quarantine-bound findings; the script stages, triage files under that procedure.

- [x] `todo/README.md` gains the completion-first rule: a section ships its focus-free proofs, records Interactive skips as `Night-owed`, and flips the same session; review and stamp never wait for quiet time. Done when: the rule names the stamp lines, the collector owner, and the only true flip blockers (red focus-free or Primary proofs, unmet Depends, missing baseline artifact, unreachable host, both review families down). **Corrected 2026-09-20 (§10 plan review `D00-T02-S10-PR1`):** was four blockers; red proofs omitted, contradicting items 7 and 8. Done: `Night-owed:` plus `Night-collected:` bullets under `## Stamps` and `### Completion-first: ship with night debt` with the collector plus blockers named.
- [x] `scripts/todo-graph.py` parses `Night-owed:` plus `Night-collected:` stamp lines and `query night-debt` lists open debt with debt id, section, count, age in nights, and last log, plus owning file plus trait filter for the collector (extension 2026-09-20: the collector resolves each id to its filter and appends to the owning file). Age defaults to the owning section's stamp date when the stamp carries no owed date (default 2026-09-20: N1 predates the format, so no stamped body is edited to backfill it); `--today` freezes age for tests. Done when: a fixture with one open plus one collected debt lists exactly the open row. Done: `night_debts()` plus `query night-debt` (file plus filter emitted); live N1 lists open age 1n; self-test fixture pins open-only listing.
- [x] `validate` treats open night debt as information, never FATAL: no gate vote, no row park, no stamp invalidation while debt sits uncollected. Done when: self-test pins a 5-night-old open debt validating clean. Done: no rule reads debt lines (parser is query-side only); self-test fixture (owed 2026-09-15, frozen today 2026-09-20) validates clean at 1184/1184.
- [x] `tools/nightly.ps1` becomes the collector: inside 02:00-06:50 it resolves each open debt id to its trait filter, runs the fenced set visibly, and writes logs under `build/nightly/` with suite scope plus HEAD at the top. **Corrected 2026-09-20:** was "section range"; §9 FL5 corrected the header to suite scope. A `-CollectDebt <id>` switch limits the Interactive leg to one debt's filter, composing with `-CheckOnly` for the dry run. Done when: a dry run against one debt id quotes its log path plus counts. Done: `-CollectDebt D00-T02-S8-N1 -CheckOnly` quotes `filter Category=Interactive owed 28` plus `log build/nightly/2026-09-20-070637-full.log trx build/nightly/2026-09-20-070637/interactive.trx`, exit 0; unknown id exits 2.
- [x] `tools/nightly.ps1` closes the loop: green collection appends `Night-collected:` (date, debt id, passed/failed/skipped, log path) to the owning section, red collection stages finding stubs (test, signature, owning-file hint) in the report Filings for the morning triage to file via `add-todo` and quarantine per the §5 procedure, and safety or data-integrity reds are marked for agent reopen through audit stance. **Corrected 2026-09-20:** was script-side filing plus quarantine plus reopen; scripts cannot run agent skills, so the §9 morning-triage procedure owns filing and the script owns staging. Done when: one green append plus one staged red are quoted (triage commits both; runs never commit). Done: scratch proof on a temp T02 copy quotes `appended: D00-T02-S8-N1` (readback exactly 1, line directly after the owed line), re-append skips as already-collected, unknown id skips as no-owed-line; staged stubs quote test-file hints (`tests/UI/PinnedTabsTests.cs`) plus `REOPEN-CANDIDATE` on the data-loss-shaped failure, `unknown` hint without crash. R1-F4/F5: superset-green stages for triage close with subset counts; census gate (totals equal owed) fails closed as collector bug. R2-F4: FQN-attributable subsets close with trx subset counts. Plan PR2 defended: N1 stays open (last collection red 24/2/2); closing now would fabricate evidence, and the close fires on the first green run with matching census. Plan `D00-T02-S10-PR4`: closure-safe skips are quarantine-declared only (proof transfers to the §35 window); capability or other skips hold the debt open; subsets close only fully executed.
- [x] The morning report gains per-debt entries: per-debt collected counts plus uncollected debt as information with its cause (box off or leg skipped, suite red, collector bug, filter not covered this run). **Corrected 2026-09-20:** was "the report lands at ..."; the path plus per-leg shape shipped with §9, so this item owns the debt entries only. **Corrected 2026-09-20 (§10 plan review `D00-T02-S10-PR3`):** was three causes; the collector also emits leg-skipped and narrowed-out. Done when: a worked example carries one collected plus one uncollected entry. Done: `## Night debt` section plus staged Filings in the report writer; testing.md collector paragraph plus worked example (one collected N1, one uncollected narrowed-out debt).
- [x] `docs/testing.md` documents the ship-with-debt gate: daytime default plus Primary green plus the Interactive skip count with its debt id is a complete gate, and the collector closes the debt async. Done when: a second section can follow it without asking. Done: `## Ship-with-debt gate (D00 T02 §10)` with the concrete four-part gate plus the never-park rule.
- [x] `AGENTS.md` gains completion-first under Working rules: runners do everything to 100% complete the section, tool, or feature in the shipping session, quiet time never parks work, and repeated manual workspace tweaks become owned automation. Done when: the rule reads as one paragraph under Working rules. Done: one completion-first paragraph under Working rules (ship plus debt plus flip, never-park, owned automation); `query night-debt` added to the Validation list.
- [x] The runner skills learn ship-with-debt (D00 T05 §1 owns the closeout-invocation lines in the same files; this item owns the never-park lines only, so the two never edit the same step). Done when: all four sub-steps below hold.
  1. `.claude/skills/process-todo-section/SKILL.md` ships with debt instead of waiting for quiet time. Done when: step 6 names the debt record plus the flip. Done: step 6 names the `Night-owed` record plus the same-session flip (never-park).
  2. `.claude/skills/review-todo-section/SKILL.md` stamps a debt-carrying candidate when the focus-free proofs are green. Done when: the guardrails name debt as stampable. Done: guardrail names debt stampable with the true flip blockers (never-park).
  3. `.claude/skills/process-phase/SKILL.md` never parks a ready row on quiet time. Done when: its scheduling step names never-park. Done: step 3 names never-park for ready rows (step 4 untouched for D00 T05 §1).
  4. `.claude/skills/process-plan/SKILL.md` never parks a ready phase on quiet time. Done when: its chaining step names never-park. Done: step 2 chaining names never-park (closeout untouched for D00 T05 §1); grep proves one never-park line in each of the four files.
- [x] `tools/provision.ps1` becomes self-healing: one idempotent command verifies plus repairs the scheduled tasks, git hooks, and CI workflows on Windows, and session start runs the verify half. Session start is the `process-plan` audit step invoking `provision.ps1 -Verify` (default 2026-09-20: no harness session hook exists in-repo, so run-start audit is the session-start surface; D00 T05 §1 owns closeout steps only, no collision). CI workflows are verify-only (existence plus Windows-only shape); content intent lives in git, so workflow drift reports as a fault, never auto-edits. Task definitions live in-repo for re-registration repair. Done when: a fresh checkout quotes every timer plus hook verified, and a deliberately broken hook is repaired by re-run. Done: `-Verify` (9 legs: 2 tasks, 2 hooks, 4 workflows, SDK) plus repair (hooks re-wire on unambiguous breakage, task re-enable plus XML re-register when missing, SDK re-provision on fault); fresh clone quotes timers green with hooks FAULT, repair run ends 9/9 green; miswired hooksPath repaired to 9/9; missing pre-commit and existing-other-dir report with the exact restore instead of running it (R2-F1: deletion may be user intent); workdir verifies against the exported XML so second clones verify the definition. Task XMLs exported live to `tools/tasks/` (UTF-16, matching the declaration).
- [x] `scripts/todo-graph.py` `query summary` surfaces open night debt beside blocked rows, so the operator digest is where the plan knows completion-first (the plan projection itself stays stamp-derived). Done when: summary quotes one open debt line from the fixture. Done: `night debt N open` line after blocked clearances (never in gate dims); live N1 line quoted; self-test pins the fixture line.
- [x] Commit: `"workspace: ship completion-first night-debt system"` (`41d0567` carries the message with a section-ref suffix; fix loops `7d0c501` `f5dc41e` `8d6686f` `87796e9` append)

**Test checkpoint:** `query night-debt` lists open debt only, a 5-night-old debt validates clean, the collector dry run quotes its log, the morning example names one uncollected cause, and all four skills name never-park. Cheaper substitute that fails: a debt list in chat with no query behind it.

> **Review:** rounds 1-3 (FINAL), candidates `41d0567` `7d0c501` `f5dc41e` `8d6686f` `87796e9` -- Sol R1 3x needs-attention over 6 findings (FL1: write race, coverage classes, census gate, XML hygiene, record IDs, tick); Sol R2 3x needs-attention over 6 findings (FL2: split repair, green-entry branches, UTF-16, subset attribution, clause matching, record IDs); Opus R3 sign-off 4x approve, panel closed. Raw findings: docs/reviews/00-workspace/D00-T02-s10.md
> **Plan review:** Sol high, 4 targets, 3 corrected in place (D00 T02 §10 items 1, 5, 6), 1 rejected (PR2: N1 closure needs a green run, closing now fabricates) (run 20260920-D00-T02-S10-gpt)
> **CRUD:** applicable | review read candidate diff plus contract plus corpus (no writes outside the candidate); implementation wrote graph query plus collector plus provision plus docs plus skill lines (read back via self-test, dry run, scratch proofs, verify legs, plan --check current); no new sections filed (all findings corrected in place or defended)
> **Verified:** 2026-09-20 | §10 | self-test 1184/1184; query night-debt lists N1 open only; dry run quotes filter plus log exit 0; scratch proofs green (append, staging, coverage, census, subset, split); provision 9/9 plus fresh-clone repair; Full panel (Sol R1-R2, Opus R3 sign-off) over 5 candidates; plan review 4 targets, 3 corrected, 1 rejected; validate 0 fatal.

## 11. Central Launch Helper With Off-Screen Birth

> **Started:** 2026-09-20T13:18:19Z

Why this section exists: every UI test file carries its own LaunchApp plus SeedSettings copies (21 plus 23 and counting), so background birth behavior cannot be set in one place, and §8 R2 measured 61 visible birth flashes on the primary per full run (250 ms dwell each, census-caught) because first windows restore at the 50,50 cascade before the funnel moves them. Centralizing the helpers lets background launches birth off-screen, which removes the flashes at the source instead of shrinking them. -> SOURCE: Sol-panel-D00-T02-s8-round-2 (R2 birth-flash family: 61 census-caught visible primary flashes per Run A; per-file helpers block central birth control). -> SOURCE: plan-review-D00-T01-s51-2026-09-20-t02 D00-T01-S51-PR11 (the §11 landing writes the PR1 superseding record, whose report needs the T04 §6 tuple fix first; edge encodes the order). -> XREF: D00 T01 §51 (plan-review marker files the ordering edge here).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §8 -- the funnel this hardens; filed from its Sol panel round 2.
- -> XREF: D00 T02 §13 -- leak diagnosis that may close when this funnel lands.

- [x] `tests/UI/UiLaunch.cs` (new) centralizes `LaunchApp`, `LaunchAppWithArgs`, `SeedSettings`, `SeedSettingsFile`, and `AppExePath` behind one helper, and every per-file copy (21 `LaunchApp` plus 23 `SeedSettings` at filing) delegates to it or is removed. Done when: definition greps for all five helpers return the one file. **Corrected 2026-09-20 (§11 validation):** was "both definitions"; the item centralizes four helpers, so all five greps must converge. **Corrected 2026-09-20 (§11 review R1):** was four helpers; the `SettingsPageTests` string-seed is a fifth seeding shape, and leaving it per-file bypassed off-screen birth for 10 launches, so it moved into `UiLaunch` with the same background rule. Variance recorded: 4 files drain `LaunchDrops` inside `LaunchAppWithArgs` plus `SeedSettings` (JumpListTask, Launch, ProtocolHandler, TabAccessibility); the central pair takes an opt-in flag (default off: draining at launch would hide drops a later assert owns), the rest delegate plain. Done: 73 per-file defs removed (21/23/1/13/15), call sites re-qualified with drain flags at the 4 files, `SettingsPageTests` string-seed moved into `UiLaunch` as `SeedSettingsFile` with the shared `SeedBackgroundGeometry` rule (R1 fix: the per-file copy bypassed off-screen birth); definition grep for the five helper names returns `UiLaunch.cs` only; build 0 warnings 0 errors. Migration note: the first migrator pass mis-skipped files (path-separator basename bug), misrouting drain flags and `SettingsPage` calls plus `UiLaunch` itself; caught by count reconciliation before the build, repaired by fixup plus restore, verified by diff review of all 4 drain files.
- [x] Background birth: the central helper seeds off-screen geometry (X/Y 10000) when `SCRATCHPAD_BACKGROUND=1` unless the caller set explicit geometry, so Primary premises survive. Done when: a backgrounded first window restores off-screen and Run A census shows zero visible-primary flashes while the Primary set still rests on primary. Done: Run A attempt 2 (`build/s11-runa-20260920-161048`) gate exit 0 `flagged=0; census=667 primary=0 expect=secondary` with 7 off-screen census births at 10000,10000 (`Untitled - ScratchPad` visible=True offscreen) plus suite 151 passed, 1 load-flake quarantined per the §5 procedure (`settings-corrupt-dialog-null`, green solo), 13 pre-existing skips; Run B (`build/s11-runb-20260920-162651`) gate exit 0 `primary=1 expect=primary` with trx 2/2 passed resting visibly on primary.
- [x] `tests/UI/UiForeground.cs` keeps show-then-move with sleep-after-move as the safety net for unseeded paths (redirect-created windows, direct launches), with its comment citing this section. Done when: the funnel tests pass unchanged. Done: safety-net comment cites §11; `UiForegroundTests` 3/3 pass.
- [x] `docs/testing.md` documents the birth rule (backgrounded launches birth off-screen, explicit geometry always wins). Done when: a second section can follow it without asking. Done: Birth rule section names the seed condition, the explicit-geometry win, the one-file home, and the funnel safety net.
- [x] PR1 superseding record at landing: the Why promises it but no item owned it, so this item does: re-review D00-T02-S10-PR1 against §10's shipped correction and write the A2 superseding record (outcome plus evidence plus review date) in `docs/reviews/00-workspace/D00-T02-s10.md`. Done when: the record validates and plan-health reports its outcome. **Added 2026-09-20 (§11 validation):** the SOURCE PR11 edge obligates the landing write; without an item it would ship on memory. Done: A2 line in `docs/reviews/00-workspace/D00-T02-s10.md` (`id A2; supersedes A1; outcome remediated`, evidence pre-landing HEAD `c62ff14` since the landing hash is unknowable at write time); `validate` 0 fatal 0 warnings; `plan-health --json` schema plan-health/7 reports the s10 critical `accepted_outcome remediated`.
- [ ] Commit: `"workspace: centralize UI launch with off-screen birth"`

**Test checkpoint:** Run A census shows zero visible-primary flashes, Run B still rests 2/2 on primary, the helper greps return one file, and the A2 record validates with its outcome reported. Cheaper substitute that fails: seeding X/Y by hand in 20-plus files.

## 12. Accelerator Binding Coverage Sweep

Why this section exists: conversion swaps physical key-means for pattern-means, so accelerator BINDINGS (key chord to command) lose their only exercise unless a test's point is the keys; R5 caught Ctrl+Shift+N at zero suite coverage with the converted cascade test name still asserting it. This section sweeps every binding for coverage and restores the missing ones as fenced tests. -> SOURCE: Opus-panel-D00-T02-s8-round-5 (R5 accelerator finding: converted test presses menu Invoke while named for Ctrl+Shift+N; no Shift+N press remains in the suite).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §8 -- the conversion that narrowed the coverage; filed from its Opus panel round 5.

- [ ] Sweep every accelerator binding the app declares (menu shortcuts, tab-bar number shortcuts, any Ctrl/Alt chords) against suite coverage and record the binding-to-test table in `docs/ui-input-audit.md`. Done when: each binding names its covering test or none, and Ctrl+Shift+N is listed as none.
- [ ] Each uncovered binding gains a fenced `Category=Interactive` test pressing the physical chord (or a written reason it cannot be physical), following the §8 fence rule with proof citations. Done when: the restored set passes in the collector window and daytime skips quote the window.
- [ ] Rename `CtrlShiftNOpensSecondWindowAtCascade` to what it asserts (menu-driven cascade placement, no keys) and update its pair comment; §8's stamped record keeps the old name as reviewed. Done when: no test name asserts keys it does not press (grep `Ctrl|Shift|Alt` in test names vs `UiInput.Press` call sites).
- [ ] Commit: `"workspace: sweep accelerator binding coverage"`

**Test checkpoint:** The sweep table is complete, the restored chord tests pass in-window, and the name-vs-press grep is clean. Cheaper substitute that fails: renaming the test without restoring the coverage.

## 13. Backgrounding Leak on the Default Leg

Why this section exists: the Run A gate counted a resting primary window on both governed 09-20 runs (re-run census 743, task-run census 696, both primary=1 with expect=secondary), while the 09-19 §8 proof was primary=0 clean. No commit touched tests/ or src/ between the §8 stamp and the re-run tree, so the working hypothesis is a nondeterministic leak rather than a code regression (environment, config, binaries, timing, or harness could still differ without a tests/ or src/ commit) (PR14): some backgrounded UI test rests a visible window on primary nondeterministically (or the single 09-19 proof was luck). Until the leaking test is identified and fixed or quarantined, the Run A leg stays red and the gate proof means nothing. -> SOURCE: gate-primary-2026-09-20 (re-run Run A gate blank-code with verdict "flagged=0; census=743 primary=1 expect=secondary", test-seconds 621; task-run Run A gate exit 1 with verdict "flagged=0; census=696 primary=1 expect=secondary", test-seconds 578; `git log fa2fc56..a8127c7 -- tests/ src/` empty). -> SOURCE: plan-review-D00-T02-s9-2026-09-20-s13 D00-T02-S9-PR14 D00-T02-S9-PR15 D00-T02-S9-PR16 D00-T02-S9-PR17 (wording, method, checkpoint, and ordering corrections from the §9 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §8 -- the fence whose backgrounding leaks; this section re-proofs its gate.
- -> XREF: D00 T02 §9 -- filed from its task-run triage (gate exit 1 on the cron-path run).
- -> XREF: D00 T02 §11 -- the central-launch funnel may fix the leak as a side effect; this section diagnoses first.

**Treatment:** This section's identification completes before §11's funnel lands; if §11 lands first, this section re-verifies the leak absent with the same census evidence instead of closing by assumption. (PR17.)

- [ ] The leaking test is identified by correlating `run-a.trx` per-test times against the gate census timestamps in `build/nightly-taskrun-2026-09-20/2026-09-20/gate-default.log`, naming the test plus the window it rested. Done when: the test name and its census lines are quoted.
- [ ] Each created HWND is instrumented with the active test identity so the leak attribution does not rest on approximate timestamps alone (PR15). Done when: the census names the test per window.
- [ ] The leak is fixed (backgrounded birth or explicit off-screen geometry on the leaking path) or the test is quarantined by the §5 procedure with its row. Done when: the fix commit or the Skip plus row is quoted.
- [ ] A governed Run A re-proofs the gate clean (exit 0, primary=0) with the verdict quoted. Done when: the gate line reads exit 0 with primary=0.
- [ ] Commit: `"workspace: plug the backgrounding leak on the default leg"`

**Test checkpoint:** Run A gate exit 0 with primary=0 on three consecutive governed runs; the leaking test named with its census evidence. Cheaper substitute that fails: a single green run, or re-running until green without identifying the leak. (PR16.)

## 14. Run-Level Deadline for the Governed Run

Why this section exists: every leg now has its own cap, but the run has no global deadline: worst case 1800 (Run A) + 300 (Run B) + 1800 (Interactive) + 10 x 1800 (soak) is 21900 s (about 6.1 hours), past the task PT4H limit and past the 06:50 window end, and the report lands only after the soak loops. One hung leg is affordable (normal full runs take ~85 minutes); eleven simultaneous hangs are absurd; but the catastrophe case currently dies by scheduler kill with no fixed-path record. This section bounds the whole run at the earliest of the PT4H limit and the 06:50 quiet-hours boundary, reserving time for cleanup and an atomic report (PR18). -> SOURCE: run-deadline-2026-09-20 (D00 T02 §9 R4 finding: worst-case cap arithmetic vs PT4H plus window end). -> SOURCE: plan-review-D00-T02-s9-2026-09-20-s14 D00-T02-S9-PR6 D00-T02-S9-PR11 D00-T02-S9-PR18 D00-T02-S9-PR19 D00-T02-S9-PR20 (deadline, verification, budget, retention, and session corrections from the §9 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §9 -- filed from its R4 review; this section hardens that run.
- -> XREF: D00 T02 §5 -- the soak loop this deadline must also bound.

- [ ] A run-level watchdog aborts the legs and lands the report before the PT4H limit in the all-hang catastrophe case. Done when: the mechanism plus its deadline math is written in `docs/testing.md` abort rules.
- [ ] The watchdog is implemented in `tools/nightly.ps1` (partial legs marked unproven, never green) with injectable short deadlines; the simulation verifies descendant-process termination, orphan-window cleanup, partial-log flushing, and atomic report publication (PR19). Done when: a simulated all-hang run lands its report before the deadline with all four verified.
- [ ] The three regression-leg verdicts publish before the soak loops, and soak consumes only remaining budget (PR20). Done when: a long night still lands the core verdict on time with soak marked budget-cut.
- [ ] Run evidence gains retention plus checksum rules outside ignored `build/` scratch (PR6). Done when: the rules are written and the 09-20 archives migrate under them.
- [ ] Locked-desktop, logged-out, sleeping, missed-start, and reboot behavior is defined for the `InteractiveToken` task (PR11). Done when: the matrix is written in `docs/testing.md`.
- [ ] Commit: `"workspace: bound the governed run with a deadline"`

**Test checkpoint:** Simulated all-hang run lands its report before the PT4H-equivalent deadline with unproven (never green) legs. Cheaper substitute that fails: per-leg caps alone, which sum past the limit.

## 15. Nightly Enforcement and Count Hardening

Why this section exists: the D00 T02 §9 R5 review left two advisories on the new enforcement plus report code. First, the Interactive quarantine-only check flags any skip without a QUARANTINED stamp, but capability skips (HookFact tests on hosts without low-level hooks) are legitimate non-quarantine skips that would red the leg with a misleading leak message. Second, the reported skip count comes from the merged name-line list while passed/failed come from the assembly sums, so a dropped line or cross-assembly name collision makes the cell contradict its own per-assembly breakdown (the summed `$s` is computed but never returned). Both are small, co-located, and filed together. -> SOURCE: r5-followups-2026-09-20 (R5-F1: `TabBarTests.cs:435` HookFact capability message vs `nightly.ps1:423,441`; R5-F2: unused `$s` at `nightly.ps1:266` vs count at `nightly.ps1:484`). -> SOURCE: plan-review-D00-T02-s9-2026-09-20-s15 D00-T02-S9-PR5 D00-T02-S9-PR7 D00-T02-S9-PR8 D00-T02-S9-PR9 D00-T02-S9-PR10 D00-T02-S9-PR13 D00-T02-S9-PR21 D00-T02-S9-PR22 D00-T02-S9-PR23 D00-T02-S9-PR30 D00-T02-S9-PR31 (report, enforcement, and evidence items from the §9 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §9 -- filed from its R5 review; hardens that candidate.

- [ ] Capability skips are allowlisted in `Get-NonQuarantineSkips` (HookFact message plus any enumerated capability skips), preferring structured skip classifications or stable reason codes over free-text matching (PR21; free text only as fallback), and the Interactive bar in `docs/testing.md` names the allowlist. Done when: the allowlist plus a scratch proof (capability skip passes, bare skip still flags) is quoted.
- [ ] The reported skip count is unified with the assembly sums (`$s` threaded through `Get-LegSummary`). Done when: the cell equals its breakdown on the archived task report.
- [ ] A smoke run is green on the hardened script. Done when: the smoke log plus exit code is quoted.
- [ ] A `latest` report pointer plus an archive-naming rule disambiguate same-day runs (PR5). Done when: the pointer resolves to the current stamp and the rule is written.
- [ ] Soak reports as a fourth phase (or gates out of the governed run) so a red soak cannot hide behind green legs (PR7). Done when: the report shows the soak verdict.
- [ ] Test, gate, enforcement, and infrastructure verdicts report separately (PR8). Done when: no single cell mixes them.
- [ ] Leg headers carry a build-once snapshot identity (commit, dirty state, binaries, config, tool versions) (PR9). Done when: two legs quote identical snapshots.
- [ ] Mutual exclusion across scheduled, manual, guard, and retry launches is tested (PR10). Done when: overlap attempts stand down in the matrix.
- [ ] Leg failures auto-capture screenshots, window metadata, dumps, and the failing test's event slice (PR13). Done when: a forced red shows captures attached.
- [ ] Parser fixtures cover assemblies, duplicate names, malformed TRX, and every skip class (PR22). Done when: the fixture suite is green.
- [ ] `passed + failed + skipped = total` is enforced per assembly and globally, failing closed on missing assemblies (PR23). Done when: a corrupted fixture reds.
- [ ] Overdue quarantine windows auto-fail with notification (PR30). Done when: an expired fixture window reds plus notifies.
- [ ] Repeated failures deduplicate into stable incident IDs retaining every occurrence (PR31). Done when: the report shows IDs with occurrence counts.
- [ ] Commit: `"workspace: harden nightly enforcement and counts"`

**Test checkpoint:** Capability skips pass enforcement, bare skips still flag, and the skip cell equals its breakdown. Cheaper substitute that fails: allowlisting by test name instead of skip reason.

## 16. Verify Timer-Fired Completion and Green

Why this section exists: the §9 evidence proves the demand-fired path (04:13:43 dry run, all legs plus soak), but no timer-fired run has completed end to end (the 02:30 parent died mid-loop), and the only completed task returned 1. Until a timer fire completes — and repeats, and runs green after the known reds resolve — scheduler-path reliability and regression-green are both unproven. -> SOURCE: plan-review-D00-T02-s9-2026-09-20-s16 D00-T02-S9-PR3 D00-T02-S9-PR4 D00-T02-S9-PR12 (timer completion, post-fix green, and repeat verification from the §9 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §9 -- verifies that run's scheduler path plus green.

- [ ] A timer-fired run completes end to end (all legs plus soak plus report). Done when: the morning report plus task history is quoted with the timer trigger.
- [ ] A second timer-fired run completes, proving recurrence rather than luck. Done when: two consecutive timer reports are quoted.
- [ ] A timer-fired run is green after D00 T02 §13, D01 T01 §34, and D01 T02 §16 resolve the known reds. Done when: the green report is quoted with the three resolutions named.
- [ ] Commit: `"workspace: verify timer-fired completion and green"`

**Test checkpoint:** Two consecutive timer-fired completions plus one post-fix green, all quoted. Cheaper substitute that fails: demand-fired runs standing in for the timer path.

## 17. Nightly Notify Plus Trend Surface

Why this section exists: the governed run's verdict currently sits in a local Markdown file the operator must remember to inspect, and per-night numbers (pass rates, durations, quarantine age, flake recurrence, gate verdicts) have no trend. A premium regression system notifies the morning and shows the slope. -> SOURCE: plan-review-D00-T02-s9-2026-09-20-s17 D00-T02-S9-PR32 (notify plus dashboard premium win from the §9 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §9 -- surfaces that run's verdict plus history.

- [ ] The morning notification fires after each governed run (pass rates, durations, reds with refs). Done when: a run's notification is quoted with its trigger.
- [ ] The trend surface tracks pass rates, durations, quarantine age, flake recurrence, and gate verdicts across nights. Done when: two nights render with the five series.
- [ ] Commit: `"workspace: notify plus trend the nightly run"`

**Test checkpoint:** Notification quoted plus two-night trend rendered. Cheaper substitute that fails: a second local file nobody opens.

## Verification

- [x] `dotnet test` green, all harnesses exercised. Evidence: build run 34810042091 success both jobs (Smoke 1/1, Unit 2/2, Protocol 8/8 on Linux and Windows, UI 3/3 on Windows) plus soak runs 34808621885 and 34809456063 success (22 passed, 0 failed each).
- [x] `python3 scripts/todo-graph.py validate` clean. Evidence: `19 todos, 106 sections -- 0 fatal, 0 warning(s), 19 adjacency advisory` (all pre-existing kinds) at closeout.
