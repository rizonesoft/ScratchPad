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
|   7   |   §7    | CI evidence capture pipeline | D01 T02 §14 |  [ ]   |

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
> **Review:** round 1, candidates 6fdfda3 b505081 -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve · `source-defect` approve. Raw findings: docs/reviews/00-workspace/D00-T02-s4.md
> **CRUD:** applicable | prompt turns wrote responses plus notifications (read back via chunk text, stopReason, sessionId); faults wrote garbage/timeouts/delays (read back via skip count, TimeoutException, completion); violations wrote errors plus exits (read back via codes 2/-32601/-32602 and stderr); mutation wrote a red test (read back, then green on revert)
> **Duration:** 38
> **Implementer:** Muse Code (Meta Muse Spark)

## 5. Soak and Quarantine Procedure

> **Started:** 2026-09-14T05:08:00Z

Why this section exists: UI and protocol tests flake. Without a procedure, flakes get deleted and coverage silently shrinks.

- [x] `docs/soak-and-quarantine.md` defines the nightly soak (what runs, how long, where results go). Done when: the soak ran once and its log is linked.
- [x] Quarantine moves a flaky test to a named list with its failure signature and owner, and the suite stays green without it. Done when: the list exists with its fields, even if empty.
- [x] A quarantined test owes a fix or a removal decision within a committed window. Done when: the window and the escalation are written.
- [x] Deleting a test without a recorded decision fails review. Done when: the rule is written in the procedure.
- [x] Commit: `"workspace: add soak and quarantine procedure"`

**Test checkpoint:** A deliberately flaky probe test is quarantined by the procedure, the suite stays green, and the probe is then removed with its decision recorded. Cheaper substitute that fails: a retry loop that hides the flake.

> **Verified:** 2026-09-14 | §5 | Soak workflow plus procedure doc; soak green twice by dispatch (runs 34808621885, 34809456063; 22 passed, 0 failed each) with run links in the doc; probe lifecycle proven locally (pass/fail/fail/fail/fail/pass same binary, quarantined suite green 2+1 skipped twice, removed with decision row); red-repeat swallow fixed in 77aff94 with shell-construct proof; validate 0 fatal; self-test 391/391
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
> **Review:** round 1, candidate 7e0283d + record ticks -- `adversarial` approve · `consistency` approve · `integration` approve · `record` approve (source-defect/design not owed). Raw findings: docs/reviews/00-workspace/D00-T02-s6.md
> **CRUD:** applicable | CI runs wrote conclusions plus artifacts (read back via success, suite counts, artifact names); golden artifacts wrote PNGs (read back via md5, pixels, PIL comparer replica to exact CI counts); registry wrote HideFileExt flips (read back via 6/6 reproductions, restored to 0); comparer wrote blurred diffs (read back via wobble pin green and shift probe red); suites wrote passes (read back via Passed/Failed counts on both OSes)
> **Duration:** 61
> **Implementer:** Muse Code (Meta Muse Spark)

## 7. CI Evidence Capture Pipeline

> **Started:** 2026-09-17T13:58:00Z

Why this section exists: eyeball-evidence crops (D01 T02 §14 item 4 is the first) cannot be taken from a window-station-less session: screen reads return black and input is dead, measured on Venom-PC (golden fresh byte-identical to a black frame, `CopyFromScreen` invalid handle). CI windows runners have displays, so the pipeline captures there: a windows-job step runs `tools/CaptureBaseline` against the built exe and uploads the PNG as an artifact, and the evidence procedure (download, eyeball checklist, commit naming) lands in `resources/baseline/README.md`. -> XREF: D01 T02 §14 (first consumer; its item 4 is deferred here); -> SOURCE: CI-evidence-gap-2026-09-17 (Venom-PC headless session, black captures, D01 T02 §14 item 4 blocked).

- -> XREF: D01 T02 §16 -- filed from this section's pipeline run (MenuBarTests flakes blocked the first artifact).
- -> XREF: D01 T01 §32 -- filed from this section's pipeline run (AppIcon plus Launch flakes on the round-2 run).

- [x] The windows CI job captures the built app and uploads the PNG as an `evidence-capture` artifact on green builds (red builds already upload golden failures). Done when: a main run carries the artifact with a non-black 900x650 PNG. First use is this section's item 2, not a synthetic probe. Done: `build.yml` gains Capture evidence frame (default success() condition, so red builds skip it) plus Upload evidence capture; run 35230396785 carries `stub-window.png`, 900x650, extrema (12, 255), 28 KB. The first attempt went red on a `FileSaveAllWalksDirtyTabs` UIA-timeout flake (capture correctly skipped, no artifact); the `--failed` rerun of the same commit went green and uploaded. Round-2 (panel fixes: profile reset, WhatsNewSeen seed, CI black-frame assert): run 35234746568's first attempt went red on three more same-family flakes (`WindowChromeIconMatchesAsset` UIA timeout, `MissingFileOfferYesBindsTabAndSaveCreates` null dialog, `FileMenuLiveAcceleratorsWork` null element; capture correctly skipped), the rerun went green and uploaded a fresh frame (900x650, extrema (12, 255)) with the black-frame assert passing. All five flakes filed for quarantine (MenuBarTests trio in D01 T02 §16, AppIcon plus Launch pair in D01 T01 §32).
- [x] Eyeball evidence of the dressed tab row is committed. Done when: the chrome crop sits beside the D01 T01 §11 crops in `resources/baseline/app/`, captured via item 1's pipeline and eyeballed (glyph present left of the first tab, 16px, stock placement). Done: `resources/baseline/app/titlebar-icon-evidence.png` (320x110, box (8, 0, 328, 110); the left 8px carried see-through edge pixels of a background window, so the box starts inside the clean edge), first taken from run 35230396785 and eyeballed (glyph left of the tab, 16px, stock placement; border bleed handled by the x=8 inset). **Corrected 2026-09-17 (§7 panel round 1):** that frame restored the UI suite's leftover session (the suite drives the real profile and no reset preceded the capture), so the crop was re-taken from the fresh frame: `titlebar-icon-evidence.png` (320x110, box (8, 0, 328, 110) of run 35234746568's `stub-window.png`), eyeballed clean: glyph left of a clean Untitled tab, 16px, stock placement; frame foreground, canonical, window unoccluded, no bleed in the box. The "4 characters" dirty tab in the first frame was suite residue, confirmed by the fresh frame's "0 characters" clean tab: D01 T01 §31 (filed from the residue) is unfiled the same day, its address left vacant.
- [x] `resources/baseline/README.md` documents the evidence procedure: which artifact, the eyeball checklist (foreground, unoccluded, canonical size, intended pixels only), and the commit naming. Done when: item 2 is produced by following the procedure verbatim. Done: `## Evidence procedure` lands with artifact, download plus verify commands, crop step, checklist, and naming; item 2 followed those steps verbatim (same download, same verify one-liner, PIL crop, checklist eyeball, `-evidence.png` naming beside the §11 crops).
- [x] Commit: `"workspace: capture UI evidence on CI"`. Done: `bb2d879` (pipeline plus Started); the crop, procedure, and ticks ride the evidence commit, since the artifact can only come from a main run of the pipeline commit.

**Test checkpoint:** CI artifact present and non-black; §14 crop committed and eyeballed; a second section could follow the procedure without asking. Cheaper substitute that fails: an operator capture with no pipeline behind it.

## Verification

- [x] `dotnet test` green, all harnesses exercised. Evidence: build run 34810042091 success both jobs (Smoke 1/1, Unit 2/2, Protocol 8/8 on Linux and Windows, UI 3/3 on Windows) plus soak runs 34808621885 and 34809456063 success (22 passed, 0 failed each).
- [x] `python3 scripts/todo-graph.py validate` clean. Evidence: `19 todos, 106 sections -- 0 fatal, 0 warning(s), 19 adjacency advisory` (all pre-existing kinds) at closeout.
