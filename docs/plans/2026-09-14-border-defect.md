# Border Defect Plan: Drive-Only Window Border on Conclave-PC

## Goal

Explain the wrong window border the operator sees on Conclave-PC only while the UI suite drives the app, fix it at the root cause when it is an app bug, and prove normal use and Mica rendering are unchanged.

## Success Criteria

- The defect is reproduced in a session-framebuffer capture taken during a drive, or proven to be an RDP transport artifact with a clean framebuffer capture as evidence.
- When the defect is an app bug, the fix is the minimal edit the diagnosis names, with no overlay, mask, per-host special case, or Mica removal.
- Normal use is proven unchanged: a parked manual window captures identical chrome before and after, and the theme matrix plus the shell golden stay green.
- A maintained regression test asserts the corrected border and passes on Conclave-PC and in CI.
- D01 T01 §10 ships through the normal review stamp.

## Context And Current Facts

- Operator report: the app window border renders wrong on Conclave-PC, evident only while the UI suite drives the app; a parked manual window looks correct. The defect has never been captured: five headless GDI captures across RDP and console sessions all returned pure black, and the in-repo golden shows rounded corners with no visible border defect.
- The golden suite is structurally blind to borders. `resources/baseline/tolerance.json` crops the top 8 percent, both sides 2 percent, and the bottom 3 percent before comparison, and `tests/UI/GoldenComparer.cs` applies those crops, so the window border, titlebar, caption buttons, and rounded corners sit outside the compared region on every run. `ShellMatchesGolden` and `FreshCaptureMatchesGolden` can pass while any border defect hides.
- Driven windows differ from a parked manual window in exactly these ways: per-test `SeedSettings` (theme forced to light, dark, or system; geometry; first-run flags), `UiCapture.Place` resizing to canonical size at 50,50 via `SetWindowPos`, `PinTopmost` toggled around pixel reads and real-input drives, rapid launch and kill cycles, and FlaUI launches from the test host process. Relevant code: `tests/UI/TabBarTests.cs` (`SeedSettings`, `LaunchApp`), `tests/UI/UiCapture.cs` (`Place`, `PinTopmost`, `CaptureWindow`), `tests/UI/MainWindowTests.cs` (`ThemesRenderWithMica`, `ShellMatchesGolden`).
- The app frame stack: `MicaBackdrop` as `Window.SystemBackdrop`, `ExtendsContentIntoTitleBar = true`, no presenter override, caption drag rects via `AppWindow.TitleBar.SetDragRectangles`. Mica per-theme rendering is proven by the center-pixel poll in `ThemesRenderWithMica`. Relevant code: `src/IntelligentNotepad/MainWindow.xaml`, `src/IntelligentNotepad/MainWindow.xaml.cs`.
- VM baseline drive before the restart: 10 passed, 7 failed, 1 skipped (the hook test) out of 18 UI tests in 48 seconds. The 7 failure names were lost when the VM rebooted mid-rerun; the quiet-verbosity log on the guest disk holds no per-test names.
- VM state now: reachable over agent SSH, session 2 Conclave Active over RDP with the operator attached, console session at its logon screen. GDI capture in-session works only while a viewer stays visibly attached; minimized RDP or a viewerless console reads black. The parked pre-restart instance is gone with the reboot.
- Tracking: the defect is filed as D01 T01 §10 (commit `158cb87`, pushed); the plan projection is current at 15 of 107 sections.
- The operator ran the app directly on the VM, was prompted for the Desktop Runtime, and installed it: `C:\Program Files\dotnet` now carries `Microsoft.WindowsDesktop.App 10.0.12`, exactly matching the provisioned SDK's runtime, so direct runs and driven runs resolve the same framework with no version skew.

## Constraints And Non-goals

- No fix may remove or degrade Mica, and no fix may change what a normal (undriven) window renders. Both are gated explicitly in the validation plan.
- No code change before the defect is reproduced in a capture. Diagnosis from the one-line report alone is forbidden by §10 item 1.
- Non-goals: a permanent headless display for the VM beyond the viewer-attached capture procedure §10 item 1 already requires; the mouse-hook host-policy question, which is a separate thread with its own evidence (Win32 error 5); the 7 unnamed VM failures except to triage whether they are border-related, with anything unrelated filed separately.

## Key Decisions

- D1: Diagnose first, fix second. The drive-only signature admits app, harness, and transport causes, and each wants a different fix. Rejected: editing frame code against hypotheses without a reproducing capture.
- D2: The framebuffer capture taken during a viewer-attached drive is the arbiter between app bug and RDP transport artifact. GDI reads the session framebuffer, which RDP transport encoding cannot touch, so a clean capture beside a visibly wrong RDP view proves transport, and a wrong capture proves app or harness. Rejected: operator eyeballing alone, which cannot separate the two.
- D3: Bisect driven-vs-manual differences one variable at a time (theme, size, topmost, foreground state, single test vs full suite) instead of guessing from the frame code. Each variable maps to one test run with a falsifying capture. Rejected: a code-first audit of WinUI border APIs, which cannot explain a drive-only signature.
- D4: The regression test is a dedicated border-geometry test in `tests/UI/MainWindowTests.cs` (corner rounding plus border stroke sampled from capture edges), not a widening of the golden crop policy. The crops exist to exclude caption buttons and theme chrome; narrowing them would destabilize the golden for reasons unrelated to this defect. Rejected: changing `tolerance.json` crops.
- D5: One commit carries the §10 fix with its test and docs, per the repo one-section-one-commit rule. Investigation phases commit nothing. Rejected: splitting diagnosis scaffolding into its own commit; throwaway guest scripts stay on the guest.
- D6: Mica and normal-use gates are blocking, not advisory: the theme matrix, the shell golden, a parked-manual before/after capture pair, and CI green. Rejected: verifying the fix on the VM drive alone.

## Recommended Approach

Reproduce the defect in a framebuffer capture during a viewer-attached drive, use that capture to separate app bug from RDP transport artifact, bisect the driven-vs-manual difference to one variable when it is real, fix at the root cause with Mica and normal use gated, and lock the border in with a dedicated regression test that the golden crops cannot see past. The operator's currently attached RDP session is the viewer Phase 1 needs; every capture run below requires it to stay open and un-minimized.

## Work Plan

- Phase 1: Reproduce with evidence. Re-run the UI suite on the guest at normal verbosity to recover the 7 failure names; during the drive, take in-session GDI captures (the proven `build/shot2.ps1` pattern) with the operator's RDP window visible; capture a parked manual window as the control under the same viewer. Owner: agent driving the guest; needs the operator attached.
- Phase 2: Separate app bug from transport. Compare the drive-time GDI captures against what the operator saw live: wrong in both means app or harness, clean capture with a wrong live view means RDP transport artifact. When it is transport, record the verdict with both artifacts and skip to Phase 5 (regression test plus docs); no app code changes.
- Phase 3: Bisect one variable at a time (only when Phase 2 shows a real defect). Ordered by cost: single failing test alone vs full suite (ordering and ghost frames); theme sweep with parked captures (forced dark, light, system vs system default); canonical size vs restored geometry (size-dependent frame math); topmost pinned vs unpinned during pixel reads; foreground vs background window (active vs inactive border). Each run ends in a capture that confirms or kills its hypothesis. Falsified hypotheses are recorded, not stacked into the fix.
- Phase 4: Fix at the root cause (only when Phase 3 names one). Apply the minimal edit the diagnosis names in the app sources; no overlay, mask, per-host branch, or Mica change. Re-capture on the guest with the viewer attached and confirm every differing border attribute from Phase 1 now matches stock.
- Phase 5: Lock it in. Add the border-geometry regression test to `tests/UI/MainWindowTests.cs`; record the viewer-attached VM capture procedure in `docs/testing.md`; run the full UI suite on Conclave-PC and the full solution in CI; commit fix, test, and docs once as the §10 unit; hand §10 to the review skill for its stamp.

## Validation Plan

- Phase 1 evidence: guest `dotnet test tests/UI --nologo -v n` log showing the 7 failure names; at least one non-black in-session GDI capture taken mid-drive showing our window; one parked-manual control capture; `golden-failure-*.png` artifacts collected from the guest `UI.dll` output directory when golden tests fail. Expected: the defect visible in a drive-time capture, absent in the control.
- Phase 2 verdict: side-by-side drive-time capture vs operator live report, recorded in the §10 work notes. Expected: a named verdict (app/harness or transport) with both artifacts cited.
- Phase 3 evidence: one capture per variable run with a written confirm-or-kill line per hypothesis. Commands: guest `dotnet test tests/UI --filter <SingleTest>` runs plus the GDI capture pattern; theme and size varied through `SeedSettings` and `UiCapture.Place` parameters. Expected: exactly one surviving variable (or none, which reopens Phase 2).
- Phase 4 gates (all blocking): fresh guest capture matches `resources/baseline/stock/notepad-main-n11.2607.14.0-win25h2.png` border attributes; `ThemesRenderWithMica` green for light, dark, and system on the guest; `ShellMatchesGolden` green; parked-manual before/after captures identical in chrome; full `dotnet test` green in CI on the fix commit.
- Phase 5 gates: new border regression test green on Conclave-PC and in CI; `python3 scripts/todo-graph.py validate` clean; `plan --check` clean; §10 stamped through `review-todo-section`.
- Highest-risk validation step: the Phase 1 drive-time capture, because every later phase depends on it and it needs the operator's viewer attached and un-minimized for the full run.

## Risks / Rollback

- The defect does not reproduce under the attached viewer (Heisenbug tied to minimization or timing). Mitigation: try minimized-viewer and console-without-viewer variants explicitly; if it reproduces only without a viewer, no GDI proof is possible and the verdict becomes behavioral (UIA geometry plus live report) with the evidence gap recorded.
- RDP disconnect mid-drive locks the session and fails input-dependent tests. Mitigation: the operator stays attached through each drive; on a lock, `tscon` the session back to console from agent SSH and re-run.
- The 7 failures are unrelated to the border (real-input misses, timing). Mitigation: triage by name in Phase 1; file unrelated failures separately instead of dragging them into §10.
- A frame fix regresses Mica or normal use. Mitigation: the Phase 4 gates are blocking, and the fix commit is one revertable unit on `main` (`git revert`), with CI proving the revert.
- Rollback: every phase except Phase 4 changes nothing tracked; Phase 4 is a single commit, revertible without touching §1 or the golden policy.

## Open Questions

- What exactly does the wrong border look like (thickness, color, radius, which sides, top titlebar vs outer frame)? The operator is the only witness and the repo holds no description. Phase 1 captures it directly, so a reply here is corroboration rather than a blocker; without one, the capture description in Phase 1 becomes the record.
