---
schema_version: 1
id: nightly-operator-control
domain: 00-workspace
status: draft
title: "TODO-09 -- Nightly Operator Control"
depends_on: []
track: W0
---

# TODO-09 -- Nightly Operator Control

> **Goal:** The nightly UI run stays out of the operator's way and thinks before it acts: it never fires chords another app owns, it yields the desktop the moment the operator is back at the PC, it can be paused, resumed, stopped, or skipped from a CLI, a toast, a tray icon, or a Claude skill, it plans each night from what changed and what is owed, and it ends with a triage that tells the operator what broke, why, and what to do next.

> [!IMPORTANT]
> **Current state:** Task `\ScratchPad\Nightly UI` (definition `tools/tasks/nightly-ui.xml`, daily 02:30, PT4H limit) runs `tools/NightlySupervisor.ps1`, which launches `tools/nightly.ps1` and tombstones hangs; `\ScratchPad\Nightly Foreground Single` (`tools/tasks/nightly-foreground-single.xml`, daily 02:05) runs one foreground test. `nightly.ps1` runs a fixed script every night (build, Run A, Run B, the `Category=Interactive` leg inside `SCRATCHPAD_INTERACTIVE_WINDOW` default `02:00-06:50`, then soak) whatever changed; its only awareness of the operator is `Get-WorkstationLocked` (logonui present). The only controls are the supervisor mutex `Global\ScratchPadNightlySupervisor` and the PT4H kill: there is no pause, stop, or skip, and the run keeps pressing keys and stealing foreground while the operator works. `Send-NightlyToast` (`tools/NightlyParse.ps1`) posts an informational toast with no actions. On 2026-09-24 the interactive leg's first tests `UI.AcceleratorTests.ChordCtrlShiftEOpensTemplates` (03:07:17) and `ChordCtrlShiftLOpensLock` failed `Assert.NotNull`: a `RegisterHotKey` probe on 2026-09-24 returned error 1409 (already registered) for exactly Ctrl+Shift+E and Ctrl+Shift+L, TickTick is in `captures-interactive/interactive-windows.txt` on 2026-09-22 and 2026-09-24, and the backgrounded chord press therefore opens TickTick instead of the app dialog. Morning reports carry counts and staged stubs but no diagnosis; `build/nightly/trend.md` shows mostly-red nights on repeating causes.

## Inputs

- [`tools/nightly.ps1`](../../tools/nightly.ps1) -- the governed run §§1-3 and §7 change (leg order, `Get-InInteractiveWindow`, `Test-LegBudget`, soak loop)
- [`tools/NightlySupervisor.ps1`](../../tools/NightlySupervisor.ps1) -- the outer watcher §2 teaches to honor stop requests without tombstoning
- [`tools/NightlyParse.ps1`](../../tools/NightlyParse.ps1) -- `Send-NightlyToast`, `Format-ToastXml`, `Classify-NightlyOutcome`, and the result schema §§1, 4, 7, 8 extend
- [`tests/UI/InteractiveFactAttribute.cs`](../../tests/UI/InteractiveFactAttribute.cs), [`tests/UI/UiInput.cs`](../../tests/UI/UiInput.cs), [`tests/UI/UiForeground.cs`](../../tests/UI/UiForeground.cs) -- the chord and foreground helpers §1 guards
- [`docs/testing.md`](../../docs/testing.md) and [`docs/soak-and-quarantine.md`](../../docs/soak-and-quarantine.md) -- the operator procedure every section documents into
- `build/nightly/2026-09-24-023008/` (ignored) -- the TickTick night: `interactive.trx`, `captures-interactive/interactive-windows.txt`
- -> XREF: D00 T02 §21 -- owns the accelerator audit's conflict matrix and focus-precondition asserts inside the app; this file owns conflicts with OTHER apps' global hotkeys at run time, and §1 consumes §21's per-press focus assert when it lands.
- -> XREF: D00 T02 §24 -- owns notify delivery follow-ups (recovery notices, dedupe); §4 adds action buttons to the same toast and must not fork its delivery path.

## Outcome

- A chord test whose chord another process holds globally reports skipped with the holder named, never red, and never presses the chord; TickTick no longer opens at night.
- Keyboard or mouse activity during a run parks it at the next safe point with no further keystrokes or focus changes; it resumes after a quiet period, or stands down with the unexecuted work owed as night debt when the window closes.
- `tools/nightly-ctl.ps1 status|pause|resume|stop|skip-tonight|disable|enable` controls a live or upcoming run, and the toast buttons, tray icon, and `/nightly` Claude skill drive the same control channel.
- Each night plans itself: an unchanged HEAD since the last green runs a short confirmation set, new commits select their touched tests plus owed debt, failures rerun once to separate flake from regression, and soak stops early on a deterministic repeat.
- Every morning report opens with a triage block (per-failure class, comparison to prior nights, diagnosis, next action) produced by headless Claude, with a deterministic fallback when Claude is unavailable.

**Adjacency:** all=not-applicable (operator tooling around the nightly test run: scripts, a tray helper, a Claude skill, and docs; nothing ships in the app, stores user data, or reaches app users)

**Adjacency rationale:** Every artifact here runs on the operator's box around the test harness: PowerShell scripts under `tools/`, a small tray helper, the scheduled task XML, a skill under `.claude/skills/`, and docs. The app binary, its settings store, and its user-facing surfaces are untouched, so none of the nine adjacency keys applies. The one app-adjacent contact, tests pressing chords, changes only test gating.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Hotkey-conflict preflight and environment-blocked outcome | -- |  [ ]   |
|   2   |   §2    | Control channel and nightly-ctl CLI | -- |  [ ]   |
|   3   |   §3    | Operator-presence yield | §2 |  [ ]   |
|   4   |   §4    | Toast action buttons | §2 |  [ ]   |
|   5   |   §5    | Tray status and control icon | §2, §3 |  [ ]   |
|   6   |   §6    | Nightly Claude skill | §2 |  [ ]   |
|   7   |   §7    | Adaptive run planning | §1, §2 |  [ ]   |
|   8   |   §8    | Claude triage in the morning report | §7 |  [ ]   |

---

## 1. Hotkey-Conflict Preflight and Environment-Blocked Outcome

Why this section exists: Windows delivers a globally registered hotkey to its registrant before any window sees it, so a chord test whose chord another app holds cannot pass and, worse, drives that app. On 2026-09-24 Ctrl+Shift+E and Ctrl+Shift+L were held (RegisterHotKey error 1409) and TickTick opened during the interactive leg while `ChordCtrlShiftEOpensTemplates` and `ChordCtrlShiftLOpensLock` failed. The fix detects and skips with a named reason; it must never close, kill, or reconfigure a user app, and it must not weaken the D00 T02 §8 fence-with-proof rule: a blocked chord owes its proof as night debt, it is not waived. Default taken: the probe is register-then-unregister on a hidden message window; cost of changing it is a per-app hotkey registry, which Windows does not expose. -> SOURCE: plan-review-D00-T02-s21-2026-09-24-d00t09s1 D00-T02-S21-PR9 D00-T02-S21-PR10 D00-T02-S21-PR11 D00-T02-S21-PR12 D00-T02-S21-PR13 (probe policy, preflight gap, input forms, privacy, and debt dedupe from the D00 T02 §21 plan review).

**Needs:** Windows host (build/test)

- -> XREF: D00 T02 §22 -- the preflight's holder list names foreground windows, so it consumes §22's failure-capture policy (title redaction for windows the run does not own, secret scan) rather than its own.

- [ ] A `UiHotkeyProbe` helper in `tests/UI/` tries `RegisterHotKey` for a (modifiers, key) pair on a private message-only window and unregisters immediately, returning free, held (1409), or unknown (any other error). Done when: a unit fixture registers a chord itself, the probe reports held, and after release reports free. Cheaper substitute: a hardcoded list of known apps.
- [ ] The holder is named best-effort: the probe records the foreground-capable top-level windows listed at probe time (process name plus title) beside the verdict, labeled "suspected holders", since Windows does not expose the registrant. Done when: a held verdict quotes the window list.
- [ ] Every chord test that presses a modifier chord declares it once (attribute or a `UiInput.PressChecked` wrapper), and a held chord turns the test into `Skip` with reason `chord Ctrl+Shift+E held globally by another app (suspected: TickTick); not pressed`, before any key goes out. Done when: with Ctrl+Shift+E held by a fixture, `ChordCtrlShiftEOpensTemplates` reports skipped with that reason and zero keystrokes are sent (event log shows no press).
- [ ] A guard test fails when a test in `tests/UI` calls `UiInput.Press` with a modifier chord outside the checked path. Done when: a planted unchecked press fails the guard.
- [ ] `tools/nightly.ps1` runs a preflight before the interactive leg that probes every declared chord and writes `preflight.json` (chord, verdict, suspected holders) into the stamp dir. Done when: the 09-24-style box produces Ctrl+Shift+E and Ctrl+Shift+L held.
- [ ] The result schema gains `environment` outcomes: a test skipped for a held chord counts as `blocked-by-environment`, never red, never quarantine-bound, and stages a `Night-owed` row under D00 T02 §10 so its foreground proof stays owed. Done when: `Classify-NightlyOutcome` on a fixture with two blocked chords returns no red from them and the report stages both debt rows.
- [ ] The morning report and toast name the conflict with the fix the operator can apply: "Ctrl+Shift+E and Ctrl+Shift+L are held by another app (suspected TickTick); rebind them there to restore these tests". Done when: the fixture report quotes the line.
- [ ] `docs/testing.md` documents the preflight, the environment outcome, and that the harness never closes user apps. Done when: the paragraph reads.
- [ ] An `unknown` probe verdict never permits the press: it reports `blocked-by-environment` with the probe error retained and the proof owed, exactly like `held`. Done when: a fixture forcing a non-1409 error skips the test with the error quoted. (D00-T02-S21-PR9.)
- [ ] The register-then-unregister window before the press is documented as a limitation, and the D00 T02 §21 input funnel stays the backstop (a holder that appears after preflight steals foreground, so the per-press precondition refuses the key). Done when: `docs/testing.md` states the gap and a fixture holder registered after preflight is caught by the funnel. (D00-T02-S21-PR10.)
- [ ] Protection covers every physical input form the suite presses (modifier chords, bare F-keys such as F3 and F5, Delete, Escape), classified in one table that names which forms can be global hotkeys. Done when: the table reads and the probe list derives from the D00 T02 §21 binding manifest. (D00-T02-S21-PR11.)
- [ ] Suspected-holder evidence records process names only, never window titles, and `preflight.json` follows the D00 T02 §22 capture retention; attribution stays labeled suspected. Done when: a fixture report carries no title text. (D00-T02-S21-PR12.)
- [ ] Repeated environment blocks for the same chord dedupe onto one debt row with an occurrence count and escalate through the D00 T02 §19 due-date rule; the row closes only on a passing press on a named candidate. Done when: three blocked nights produce one row with count 3 and an OVERDUE escalation. (D00-T02-S21-PR13.)
- -> SOURCE: plan-review-D00-T02-s22-2026-09-25-d00t09s1 D00-T02-S22-PR13 D00-T02-S22-PR14 D00-T02-S22-PR15 D00-T02-S22-PR16 (title contradiction, skip enforcement, race bound, and per-test obligations from the D00 T02 §22 plan review)
- [ ] The suspected-holder item records process names only (the earlier "process name plus title" wording loses to the privacy item and the D00 T02 §22 title rule), and its fixture carries no title text. Done when: both items name process-only evidence. (D00-T02-S22-PR13.)
- [ ] A `blocked-by-environment` skip carries a structured reason code the D00 T02 §15 non-quarantine skip enforcement recognizes, so a legitimate block is never counted as a bare skip, with a schema compatibility fixture for §17 results. Done when: an enforcement fixture passes an environment skip and still reds a bare one. (D00-T02-S22-PR14.)
- [ ] The documented race limitation accounts for background hotkey delivery (a registrant can receive the hotkey without stealing foreground) and bounds what the D00 T02 §21 funnel can and cannot catch. Done when: the limitation paragraph names both cases. (D00-T02-S22-PR15.)
- [ ] Chord-level dedupe keeps every affected test and candidate requirement beneath the grouped row, so one passing press never clears an unrelated test's owed proof. Done when: a two-test fixture closes only the pressed test's obligation. (D00-T02-S22-PR16.)
- [ ] Commit: `"workspace: skip chords held by other apps' global hotkeys"`

**Test checkpoint:** With a fixture process holding Ctrl+Shift+E, run `dotnet test tests/UI/UI.csproj --filter FullyQualifiedName~ChordCtrlShiftEOpensTemplates`: it reports skipped naming the holder, the event capture shows no keystroke, and TickTick (or the fixture's window) does not activate; release the hold and the same test runs its press. Fails if any key is sent while held.

## 2. Control Channel and nightly-ctl CLI

Why this section exists: the run has no brakes. The operator needs to pause, resume, stop, skip tonight, and disable the nightly without killing processes by hand or editing the scheduled task. One control channel keeps every front end (CLI here, toast §4, tray §5, skill §6) honest: they all write the same request and read the same state. Stopping must still publish a report: a stop is an operator outcome, not a crash, so the supervisor must not tombstone it. Default taken: the channel is a JSON state file plus a named event under `build/nightly/control/`; cost of changing it is a named-pipe server, which needs a live listener the run does not otherwise have.

**Needs:** Windows host (build/test)

- [ ] `build/nightly/control/state.json` (written by the run, atomic) carries run identity, pid, phase, current leg and test, paused flag with reason, started/eta, and last heartbeat; `request.json` (written by front ends, atomic) carries one request (`pause`, `resume`, `stop`, `skip-tonight`) with who plus when. Done when: the schema is written in `docs/testing.md` with one example each.
- [ ] `tools/nightly.ps1` checks for a request at every safe point (between legs, between test assemblies, between soak iterations, and via a runsettings-free poll between interactive test classes) and never mid-press. Done when: a fixture request lands at each safe-point kind and is acknowledged in `state.json` within one safe point.
- [ ] Pause parks the run at the safe point (no test process alive, no windows of ours open), keeps the deadline clock honest by recording paused seconds, and resume continues from the next unit. Done when: a paused-then-resumed stub run completes with the same unit set and records paused time.
- [ ] Stop ends the run cleanly: kills the current contained step through JobControl, publishes the morning report with `Status: stopped by operator` and every unexecuted unit staged as night debt, and exits with a distinct code the supervisor relays without tombstoning. Done when: a stub stop publishes that report and the supervisor prints `fresh report stands`.
- [ ] Skip-tonight records a one-shot skip for the next scheduled start (a run launched under it writes a `skipped by operator` report and exits 0); disable and enable flip the two `\ScratchPad\Nightly*` tasks through `Disable-ScheduledTask` / `Enable-ScheduledTask` and report the state. Done when: skip-tonight suppresses exactly one fixture launch and disable/enable round-trips `Get-ScheduledTask` state.
- [ ] `tools/nightly-ctl.ps1 status|pause|resume|stop|skip-tonight|disable|enable` writes requests and waits (bounded) for acknowledgement, printing the resulting state; `status` prints phase, leg, test, paused, elapsed, next scheduled start, and skip/disabled flags. Done when: each verb quotes its output against a stub run.
- [ ] Requests are validated and single-use: a stale request (older than the run start) is ignored with a line in the report, and an unknown verb is refused. Done when: fixtures pin both.
- [ ] Commit: `"workspace: give the nightly a control channel and nightly-ctl"`

**Test checkpoint:** Start `tools/nightly.ps1` with `SCRATCHPAD_STUB_LEGS` set, run `tools/nightly-ctl.ps1 pause`, observe `status` report paused at a safe point, `resume`, then `stop`: the report reads `Status: stopped by operator` with staged debt and the supervisor does not tombstone. Fails if any verb goes unacknowledged or a stop produces a tombstone.

## 3. Operator-Presence Yield

Why this section exists: the operator decided (2026-09-24) that when they come back to the PC mid-run the nightly must get out of the way: no more keystrokes, no focus stealing, no windows popping. The run already knows about a locked box (`Get-WorkstationLocked`) but not about a present operator. Presence is read from `GetLastInputInfo`, filtered so the run's own synthetic input does not count as the operator. Operator decision 2026-09-24: 10 minutes (600 s) of quiet resumes, long enough to cover a coffee break without resuming under the operator; cost of changing it is one setting.

**Needs:** Windows host (build/test)

- [ ] A presence probe reads `GetLastInputInfo` idle time and distinguishes operator input from the run's own `SendInput` by marking injected input (`dwExtraInfo` tag in `UiInput`) and ignoring last-input changes inside a press window the harness owns. Done when: a fixture proves harness presses do not register as presence and a real key or mouse move does.
- [ ] Presence during a focus-using leg (interactive, UI soak, foreground-single) requests an automatic pause through the §2 channel with reason `operator present`; headless legs (unit, protocol) keep running. Done when: simulated presence mid-interactive parks the run and a headless leg in the same stub continues.
- [ ] While paused for presence, the run resumes after `SCRATCHPAD_PRESENCE_QUIET` seconds (default 600, operator decision 2026-09-24) of no operator input; an operator `resume` overrides immediately and an operator `pause` is never auto-resumed. Done when: fixtures pin auto-resume, manual override, and the manual-pause hold.
- [ ] When the interactive window end approaches while paused, the run stands down its focus legs with every unexecuted test staged as night debt, never red. Done when: a stub with the window closing mid-pause stages the remaining tests and publishes.
- [ ] The Foreground Single task gets the same guard: it defers with exit 2 when the operator was active in the last quiet period, exactly as it does for a locked box today. Done when: the task XML action checks presence and a fixture run defers.
- [ ] `docs/testing.md` documents presence yield, the quiet period, and the override. Done when: the paragraph reads.
- [ ] Commit: `"workspace: yield the nightly when the operator is present"`

**Test checkpoint:** During a stub interactive leg, move the mouse: within one safe point `nightly-ctl status` reads `paused (operator present)` and no further input events come from the harness; stay idle for the quiet period and the run resumes. Fails if a keystroke or foreground change lands after presence.

## 4. Toast Action Buttons

Why this section exists: the operator wants to control the run from the notification it already sends. Today `Send-NightlyToast` posts text only. A start toast with Pause, Stop, and Skip tonight buttons (and a paused toast with Resume) lets the operator act without a terminal. Toast buttons on a PowerShell-posted toast activate through a protocol handler, so this section registers a per-user `scratchpad-nightly:` protocol that calls `tools/nightly-ctl.ps1`. It must not fork D00 T02 §24's delivery path.

**Needs:** Windows host (build/test)

- [ ] `Format-ToastXml` accepts optional actions and emits `<actions>` with `activationType="protocol"` buttons targeting `scratchpad-nightly:<verb>?run=<id>`. Done when: a fixture renders valid toast XML with three buttons.
- [ ] A per-user protocol registration under `HKCU\Software\Classes\scratchpad-nightly` (installed and removed by `tools/nightly-ctl.ps1 install-handler|remove-handler`, and by `tools/provision.ps1`) routes to `nightly-ctl.ps1` with the verb and run id; the run id guards against acting on a later run. Done when: invoking the URI from `Start-Process` pauses a stub run and a stale run id is refused.
- [ ] The run posts a start toast (Pause, Stop, Skip rest of tonight) at launch, a paused toast (Resume, Stop) on any pause, and keeps the morning toast informational. Done when: the three toasts are captured from Notification Center history on a stub run.
- [ ] Commit: `"workspace: add control buttons to nightly toasts"`

**Test checkpoint:** On a stub run, click Pause on the start toast: `nightly-ctl status` reads paused; click Resume on the paused toast: it resumes. Fails if a button acts on a different run id or does nothing.

## 5. Tray Status and Control Icon

Why this section exists: the operator wants a glanceable signal that the nightly is live plus one-click control. A tray icon shows state (running, paused, stopped) with the current leg and test as its tooltip, and a menu for Pause/Resume, Stop, Skip tonight, Open report, and Open status. It is a thin front end over the §2 channel and reads the §3 presence state; it holds no run logic.

**Needs:** Windows host (build/test)

- [ ] A small tray helper (`tools/NightlyTray/`, WinForms `NotifyIcon` on the repo-local .NET SDK, or a PowerShell host if measurably reliable) starts with the run and exits when the run publishes, reading `state.json` on a short timer. Done when: the icon appears on a stub run and disappears after publication.
- [ ] Icon plus tooltip reflect running, paused (with reason), and stopped, and the menu issues §2 requests with the run id. Done when: each menu verb acts on a stub run and the icon updates within one poll.
- [ ] The helper never takes foreground and never shows a window on its own; Open report opens the morning report in the default editor only on click. Done when: a stub run with the helper shows no foreground change in the event capture.
- [ ] The helper builds in the solution under the existing warning gates and has a unit test over its state mapping. Done when: `dotnet build` is clean and the test passes.
- [ ] Commit: `"workspace: add a nightly tray icon"`

**Test checkpoint:** On a stub run the tray icon shows running, Pause from its menu flips it to paused and `nightly-ctl status` agrees, Stop publishes the stopped report and the icon exits. Fails if the icon lingers after publication or steals foreground.

## 6. Nightly Claude Skill

Why this section exists: the operator wants to say "pause the nightly" or "what did last night find" inside a Claude Code session. A `/nightly` skill wraps `tools/nightly-ctl.ps1` and reads the latest morning report plus triage, so the session never guesses at run state.

- [ ] `.claude/skills/nightly/SKILL.md` documents verbs (status, pause, resume, stop, skip-tonight, disable, enable, report) mapped to `tools/nightly-ctl.ps1` and the latest `build/nightly/morning-<day>.md`, with bounded output per the output-discipline rule. Done when: the skill lists in the session and each verb names its command.
- [ ] The skill confirms before `stop` and `disable` (destructive to tonight's coverage) and reports the resulting state verbatim. Done when: the skill text carries the confirmation rule.
- [ ] `report` summarizes the morning report's triage block (§8) and open night debt (`query night-debt`), never paraphrasing counts. Done when: a dry read over the 2026-09-24 report quotes its counts exactly.
- [ ] Commit: `"workspace: add the nightly Claude skill"`

**Test checkpoint:** In a session, `/nightly status` against a stub run prints the `nightly-ctl status` output, `/nightly pause` pauses it, and `/nightly report` quotes the latest report's counts. Fails if any verb reports state not read from the control channel.

## 7. Adaptive Run Planning

Why this section exists: every night runs the same full script regardless of what changed, so an unchanged tree burns four hours re-proving the same reds, a one-off flake reads as a regression, and soak keeps hammering a deterministic failure. The run should plan: what changed since the last green, what is owed, what failed last time, and what the environment preflight (§1) says it cannot prove tonight. The plan is written before any leg runs so the report can say what was chosen and why. It must not silently reduce coverage: anything the plan leaves out is either proven unchanged or staged as owed.

**Needs:** Windows host (build/test)

- [ ] A planner step writes `plan.json` (units chosen, reason per unit, units deferred with reason) before the first leg, from: HEAD vs the last green result's `commit`, `git diff --name-only` mapped to test projects and classes, open night debt (`query night-debt`), last night's failures, and `preflight.json`. Done when: fixtures pin the plan for unchanged HEAD, a src-only change, a tests-only change, and a blocked-chord night.
- [ ] Unchanged HEAD since the last green runs a confirmation set (build, Run B, owed debt, last failures) instead of the full legs, and a full run is forced weekly or on `-Force`. Done when: a fixture with matching HEAD chooses the short set and the weekly rule forces full on day 7.
- [ ] Each red test reruns once in isolation at the end of its leg; red-then-green classifies `flake` (quarantine-candidate per D00 T02 §5), red-then-red classifies `regression`. Done when: fixtures pin both classifications in the result JSON.
- [ ] Soak stops a suite early when the same test fails with the same normalized signature in two consecutive iterations, records `deterministic` with the signature, and spends the saved budget on the next suite. Done when: a stub soak with a planted deterministic failure stops at iteration 2 and the ledger reads `deterministic`.
- [ ] The report opens with the plan summary (what ran, what was skipped and why) and the trend marks planned-short nights distinctly from full nights. Done when: a short-night fixture report quotes the plan summary and `trend.md` labels it.
- [ ] Commit: `"workspace: plan each nightly from what changed and what is owed"`

**Test checkpoint:** Two stub nights on the same HEAD: the second chooses the confirmation set and says so in its plan summary; plant one flaky and one deterministic failure: the first classifies `flake`, the second `regression`, and soak stops the deterministic suite at iteration 2. Fails if a deferred unit is neither proven unchanged nor staged as owed.

## 8. Claude Triage in the Morning Report

Why this section exists: the morning report lists counts and staged stubs, and the operator still has to read trx files to learn what happened. At the end of the run, headless Claude reads the run's results, the plan, the preflight, captures, and the last several nights' results, and writes a triage block: per failure, its class (environment, regression, flake, infrastructure), what changed since it last passed, a diagnosis, and the next action (fix owner, rebind, quarantine, rerun). Claude reviews here as an analyst, not a writer of the repo: it edits nothing but the report block and never commits. When Claude is unavailable or times out, a deterministic triage from §7's classifications stands in, so the report never waits on it.

**Needs:** Windows host (build/test)
**Requires:** operator -- a signed-in Claude Code CLI on the nightly box for headless `claude -p`; credentials stay in the platform store and never enter the run's logs or report.

- -> XREF: D00 T02 §22 -- triage prompts are built from failure captures and the incident ledger, so they consume §22's capture policy and incident identity contract.

- [ ] A triage step runs `claude -p` with a bounded prompt built from `morning-<stamp>.result.json`, `plan.json`, `preflight.json`, failing test messages, and the last 7 nights' result JSON, under a hard timeout and a read-only tool allowlist. Done when: a fixture night produces a triage block and the step's wall clock stays inside its cap.
- [ ] The triage output is structured (JSON per failure: test, class, evidence, diagnosis, next action, confidence) and validated before it is rendered into the report; invalid output falls back to deterministic triage with a note. Done when: fixtures pin a valid render and an invalid-output fallback.
- [ ] Deterministic triage classifies from §1 environment outcomes, §7 rerun classes, and repeat-night signatures, and always renders when Claude does not. Done when: a no-CLI fixture renders the deterministic block.
- [ ] The triage block sits at the top of the morning report and its one-line summary rides the morning toast. Done when: the 2026-09-24-shaped fixture's block names the TickTick hotkey conflict as environment with the rebind action.
- [ ] Prompts and outputs are kept in the stamp dir and redacted per D00 T02 §22's capture policy when it lands; nothing is sent beyond the Claude CLI call. Done when: the stamp dir holds the prompt and response and `docs/testing.md` names them.
- -> SOURCE: plan-review-D00-T02-s22-2026-09-25-d00t09s8 D00-T02-S22-PR17 D00-T02-S22-PR18 D00-T02-S22-PR19 D00-T02-S22-PR21 (outbound redaction, isolation, grounding, and deadline from the D00 T02 §22 plan review)
- [ ] Outbound context is redacted by the D00 T02 §22 capture policy before the Claude call, and a failed redaction skips the call for deterministic triage. Done when: a planted secret in an input never reaches the prompt file. (D00-T02-S22-PR17.)
- [ ] Evidence is framed as untrusted input with the tool capability boundary enforced by the runner, and the runner (never the model) inserts validated output into the report. Done when: an evidence line carrying an instruction changes nothing but the quoted text. (D00-T02-S22-PR18.)
- [ ] Each diagnosis cites resolvable evidence references, separates observation from hypothesis, and may answer `unknown`. Done when: validation rejects an uncited diagnosis and accepts `unknown`. (D00-T02-S22-PR19.)
- [ ] Triage runs inside a fixed allocation of the publication deadline: deterministic triage publishes first and Claude enrichment is bounded, with descendants reaped at the bound. Done when: a hung-CLI fixture still publishes on time with the deterministic block. (D00-T02-S22-PR21.)
- [ ] Commit: `"workspace: triage the nightly with Claude in the morning report"`

**Test checkpoint:** Run the triage step over the retained 2026-09-24 result: the block classifies the two chord failures as environment (hotkey held) with a rebind action and the pinned-tab failures as regression pending rerun; rerun with the CLI hidden and the deterministic block renders. Fails if the report waits on Claude or a Claude failure reds the run.

## Verification

- [ ] `python3 scripts/todo-graph.py self-test` and `validate` clean
- [ ] One governed timer-fired night on the operator's box shows: no chord pressed while held, a presence pause and resume, a CLI pause and stop honored, the plan summary, and the triage block at the top of the report
- [ ] `docs/testing.md` covers preflight, control verbs, presence yield, toast and tray controls, the skill, planning, and triage
- [ ] `python3 scripts/todo-graph.py validate` clean
