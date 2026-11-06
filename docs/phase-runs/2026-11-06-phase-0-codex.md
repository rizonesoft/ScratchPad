# Phase 0 Codex plan run

Scope: whole implementation plan, beginning with phase 0.

Session: 01a1b25d-bfec-7463-a9a2-983dd224c90d. Writer: gpt-6-astra, medium.

Preflight: clean main at b2d7b46, six local commits ahead of origin/main; both guards inactive; graph validation 34 TODOs, 352 sections, zero fatal; plan current at 160/306; 22 runnable here; provisioning 9/9; reviewer pin check passed; codex queue supports resume. Native hook trust has not yet been independently verified.

First section: D00 T12 §3, element clicks in physical coordinates.

Plan review at 7f43a9f returned three P2 gaps and one P3 clarification. All four are addressed in the next contract candidate: explicit right-click API, refusal behavior and proof, full scoped test commands, and sanctioned guard forms. Native coordinate-free button presses are outside this coordinate guard and remain unchanged. Baseline UiPointerGuardTests: exit 0, 15 passed, 0 failed, 0 skipped (`build/d00-t12-s3-guard-baseline.log`).

Implementation evidence in progress: plan candidate `970d02e` approved by Argon medium with no gaps (`docs/cross-model-reviews/2026-11-06-d00-t12-s3-plan2.md`). All 21 direct element calls now route through physical-coordinate click helpers. The owning layer is `tests/UI/UiPointer.cs`; background or foreground-gate refusal occurs before movement. Source guard handles element, conditional, static-imported, and pointed mouse calls, preserving sanctioned coordinate-free forms and local helper calls.

Regression evidence: original guard baseline 15 passed; new click fixtures on the old implementation failed 10 of 13 tests as expected (`build/d00-t12-s3-guard-red.log`); current guard suite 40 passed, zero failed or skipped (`build/d00-t12-s3-guard-final.log`). Solution build passed with zero warnings and errors (`build/d00-t12-s3-build.log`). The scoped background run plus goldens passed 112 with three skips, zero failures (`build/d00-t12-s3-background.log`, TRX under `build/test-results/`). Skips are the existing save-prompt and locked-file quarantines and the virtual-printer capability requirement. System DPI was 144 (150%). Cursor snapshots differed, so this run does not prove cursor stability; a MenuBar-only repeat remains owed. The final guard-only changes were tested separately after that background run.

Read-only Sonnet research and routine diff review used `claude-sonnet-5-5` (reported runtime model). Verified and fixed its conditional/static-import and pointed LeftClick/LeftDoubleClick gaps. Its variable-button false-positive concern is outside the explicitly sanctioned literal forms; the current tree has none. Default helpers retain UIA-first paths and now fail before cursor movement if a pattern is unavailable; the default MenuBar and Settings tests passed. Native coordinate-free button helpers stay outside the approved DPI guard. The public-entrypoint refusal test asserts `InvalidOperationException`, so an earlier `ArgumentNullException` cannot satisfy it. Native PostToolUse activity was observed refreshing the campaign state; heartbeat delivery remains unproven. No reviewer is credited with independent approval except the pinned Argon route.

STOPPED 2026-11-06T20:11:21.257312+00:00 run=46290bdc6eae4a4bad23b85d5c003cbf operator reported repeated windows. Interactive run was cancelled; its shell 56548 and leaked test-owned ScratchPad process 61120 (parent testhost 27300) were stopped after identity checks. Campaign ended with operator-stop. No section stamp or completion claim; code and evidence remain for explicit resume.

Interactive failure evidence: after the idle gate opened, MissingFileOfferEnterAcceptsAsYes refused a key because WindowsTerminal held the foreground. WindowBirthLeavesAnOwnedDialogInPlace then timed out; later launches exited before attachment while a test-owned ScratchPad instance remained. Full log: build/d00-t12-s3-interactive.log. The first cancellation did not stop the shell or close the leaked application promptly; explicit process cleanup followed the operator report. Root cause and a safe rerun remain unresolved.

Operator follow-up authorizes correcting the harness so testing can finish without repeated windows. Read-only diagnosis confirms CloseAll UIA enumeration threw at line 985 before termination, while the runner continued tests. Resume starts with contract review and headless regression proof, followed by one physical case at a time.
