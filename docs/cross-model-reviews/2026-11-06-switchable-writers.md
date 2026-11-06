# Switchable writer infrastructure review

Bootstrap review of the infrastructure change, not a TODO section verification stamp. Reviews used the pinned Antigravity route through the dispatcher Python API on bounded source snapshots while replacing the legacy dispatcher. No canonical section review cycle, candidate commit binding, or native hook activation is claimed by this record. Future section cycles use the CLI and its committed policy lineage.

## Sources and verification

Read-only reference inspection covered Steward review scheduling, Recto campaign mechanics, and JMR Online at `/home/derickpayne/projects/jmr-online` (Codex adapter and independent campaign state). Runtime choices are local to ScratchPad; no reference repository or global configuration was changed.

Focused verification: review suite 95 tests, OK with 3 inherited integration skips (companion TODO kit absent and platform-specific cases); campaign suite 22 tests, OK; subsequent policy suite 23 tests, OK; Antigravity command suite 6 tests, OK. Routing check: 8 routed agents, 0 problems. TODO graph: 0 fatal. Derived plan current. Both runtime ready probes succeeded on the real graph for plan and phase 0.

Native hook trust and real idle-thread delivery remain activation checks for the operator. No campaign was armed. The live scoped Antigravity permission probe successfully executed `git status --short` without denied actions. Earlier headless permission refusals were diagnosed and now produce no approval; a per-invocation permission file grants only anchored read-only Git forms and denies file edits.

## Finding dispositions

- Plan review: specified interlock, review wait, recovery, process identity, teardown, progress fingerprint, paths and acceptance checks in the design and plan.
- Claude runtime pause race: reproduced by a regression test, fixed in both independently owned runtimes, and approved in the low follow-up. Cancellation is honored by the atomic save and checked before Stop continuation.
- Claude crash recovery: intentional operator end by recorded session id; its Cron dies with the session. No unattended cross-session takeover is allowed.
- Dispatcher live ceiling, contradictory severity, missing writer metadata, consumed-pass preflight and concurrent review markers: verified and fixed with focused regression coverage.
- Historical Claude pin replay: parsing historical evidence remains allowed; launching Claude is refused in review(), proven by the existing regression. Historical optional schedule schema remains readable; the committed pin and RepositoryPin tests require the new completion-last policy.

## Captured reviewer evidence

### plan-snapshot

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `ffec04c259b680d279b21a7e65e706f0dfe54dc5d8773a97ee428dab6e7c3d61`.

### `plan` Lens Verdict: Gaps Identified

1. **P2 — Underspecified Cross-Harness Ownership Interlock**: The spec permits "a small cross-harness ownership interlock... solely to prevent concurrent writers" while simultaneously prohibiting shared runtime state files (`No runtime imports, state files, or scheduler jobs cross harnesses`). Neither the spec nor the plan defines the interlock's storage path, schema, atomic acquisition mechanism, stale-lock recovery (e.g., if a writer crashes without running `end` or `SessionEnd`), or refusal behavior when the opposing harness attempts to acquire a run. Nor is the cross-harness interlock listed in the temporary-repository test matrix.
2. **P2 — Unbounded / Undefined "Review Wait" State**: The verification section lists `review wait` as a tested scenario, and stop hooks count "three unchanged stops" before parking a run. However, the runtime mechanics never define a `review_wait` state or transition: how a session enters/exits review wait during long-running external `independent-review` calls (Astra/Argon), whether stops or heartbeats during an active review are exempted from the three-strike stall counter, or how a stuck review times out.
3. **P2 — Missing Operator Recovery Path from Parked (`stalled`) State**: The spec states that "Three unchanged stops park the run for operator recovery; a heartbeat cannot resurrect it," and mentions "Operator pause and interrupt override continuation." It omits the explicit lifecycle command or state transition (`resume`, `unpark`, or `acquire --force`) required for the operator to recover a parked or paused run, how that command resets the strike counter or advances the generation, and how persistence read-back verifies the recovered state.
4. **P2 — Missing Codex Hidden Heartbeat Process Teardown and Orphan Recovery**: Codex relies on "its own hidden local heartbeat process." The design does not specify how this background process is tracked (e.g., PID/generation validation), how it is reliably terminated on `end`, `Interrupt`, `SessionEnd`, or 3-strike park, or how an orphaned heartbeat process is prevented from continuing to invoke `codex queue --resume` after an abnormal session crash.
5. **P3 — Missing Exact File Targets and Acceptance Criteria (`Done when:`) in Plan**: `docs/plans/2026-11-06-switchable-writers.md` consists only of five high-level summary bullets. It omits the exact target file paths (e.g., script names, hook config paths, `.conclave/reviewers.toml`, `.agents/` / `.claude/` / `.codex/` skill mirrors, `docs/writer-campaigns.md`), exact CLI subcommands/flags, and falsifiable `Done when:` criteria per step.
6. **P3 — Ambiguous Progress vs. Bookkeeping Boundary**: Progress is defined as "source and run evidence, excluding bookkeeping-only edits," without specifying the exact path allowlist/denylist or git-tree fingerprint calculation that distinguishes valid progress (such as `docs/cross-model-reviews/` artifacts or `todo/` stamps) from ignored bookkeeping.

HIGHEST: P2
PLAN: gaps
OVERALL: needs-attention

### codexguard

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `aba4d564c4f9ece3e3fa320c64bf0e3d995a6b1c9f47eb3cdf1ac358cb9deda6`.

Reviewed [scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py) against the scope requirements:

- **One active writer & independent runtime state:** `acquire` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L84-L106)) serializes via `ownership_lock` (`build/writer-ownership.lock`), verifies `build/claude-campaign/state.json` is not `active`, and stores Codex state independently under `build/codex-campaign/state.json` with no Claude runtime imports.
- **Generation-bound heartbeat:** `acquire` mints a UUID `generation`; `heartbeat` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L232-L249)) and `hook` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L190-L196)) validate `(session, generation)` via `matches` and block stale `SCRATCHPAD_HEARTBEAT` prompts.
- **User pause and owner-process death:** `Interrupt` and `SessionEnd` create `paused-<generation>` without waiting on `ownership_lock` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L183-L187)), which `read` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L24-L29)) immediately reflects as `status: 'paused'`. `start_worker` and `worker_tick` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L252-L303)) bind the watchdog to `(owner_pid, owner_identity)` using process creation time and transition the campaign to `paused` (`owner-process-ended`) if the owner process exits or its PID is recycled.
- **Bounded stall breaker:** `Stop` handling in `hook` ([scripts/codex_campaign.py](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py#L209-L217)) hashes repository state via `fingerprint` (excluding `build/` and `- bookkeeping:` lines in `run_file`) and transitions to `stalled` (`no-progress`) once `blocks > 3` consecutive identical fingerprints occur.

No defects found in `scripts/codex_campaign.py`.

HIGHEST: none
OVERALL: approve

### claudeguard

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `afa6ff73b16ad94ea6e178b588743e3f51e461fcaa6ed60fa955a450fb7ac77b`.

### Findings

1. **P2 — Pause sentinel is check-before-lock and never persisted to `state.json`, allowing overwrite on concurrent `Stop` (`scripts/claude_campaign.py:194-200`, `24-29`, `230`)**
   - **Location:** `hook()` lines 194-199 (`if kind in ('Interrupt', 'SessionEnd'): ... (state_path(root).parent / ('paused-' + state['generation'])).touch(); return {}`) and `Stop` branch lines 211-232.
   - **Reproduction:**
     1. A slow `Stop` hook enters `with ownership_lock(root):`, calls `state = read(root)` at line 201 (`status == 'active'`), and spends several seconds inside `runnable()` or `fingerprint()`.
     2. While `Stop` holds the lock, `Interrupt` or `SessionEnd` runs lines 194-199 without acquiring `ownership_lock`, creates `paused-<generation>`, and returns immediately without updating `state.json`.
     3. `Stop` finishes `fingerprint()` and calls `save(root, state)` at line 230 (or `save(root, state)` at line 232 after setting `status` to `'parked'`/`'stalled'`/`'ended'`).
     4. If `Stop` returned `'decision': 'block'` at line 231, `state.json` still has `status: 'active'` on disk (masked only when read through `read()`), and if `Stop` transitioned to `'parked'` or `'stalled'`, the pause sentinel is ignored thereafter because `read()` only checks `paused-<generation>` when `state.get('status') == 'active'` (line 26). Furthermore, `acquire()` for the other harness (`codex`) inspects raw `json.loads(other.read_text()).get('status') == 'active'` directly rather than calling `read()`, so a paused Claude session whose `state.json` still says `'active'` on disk blocks Codex from acquiring ownership (`line 82`).

2. **P2 — Cross-harness active check in `acquire()` ignores `paused-<generation>` sentinel (`scripts/claude_campaign.py:81-83`)**
   - **Location:** `acquire()` lines 81-83.
   - **Reproduction:**
     1. When an `Interrupt` or `SessionEnd` event fires on the active harness, `hook()` touches `paused-<generation>` and returns without modifying `state.json` (`lines 194-199`).
     2. `state.json` on disk still contains `"status": "active"`.
     3. When the other harness tries to `acquire()`, lines 81-83 read `state.json` raw (`json.loads(other.read_text(encoding='utf-8')).get('status') == 'active'`) without checking for `paused-<generation>`.
     4. The new harness is falsely rejected with ` ValueError('... owns the tree; end that run before switching')` even though the previous run was paused by `Interrupt` or `SessionEnd`.

3. **P3 — No owner-process liveness check on `state['session']` / `worker_pid` in `claude_campaign.py` (`scripts/claude_campaign.py:87`, `158-174`)**
   - **Location:** `acquire()` line 87 (`worker_pid=None`) and `read()` / `matches()` / `heartbeat()`.
   - **Reproduction:**
     1. `acquire()` initializes `worker_pid=None` and never records the owning Claude process PID, nor do `matches()`, `read()`, or `heartbeat()` verify `alive(...)` on an owner PID.
     2. If the owning Claude process dies unexpectedly without delivering `SessionEnd`, `state.json` remains `status: 'active'` indefinitely, preventing both same-harness and cross-harness `acquire()` until manual cleanup or `end` with the dead session ID.

HIGHEST: P2
OVERALL: needs-attention

### dispatcher1

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `549a5d83af1ae470055501d272614d6d47cf57e7ce1b3fb0357ac4e282df37f6`.

### Review of `scripts/review-dispatch.py` (Part 1 of 3, lines 1–295)

#### Findings

1. **[P2] Live reviewer pin allows effort above `medium` and does not require the `completion_order = "last"` schedule (`scripts/review-dispatch.py:34`, `scripts/review-dispatch.py:89`, `scripts/review-dispatch.py:106-112`, `scripts/review-dispatch.py:143-159`)**
   - **Problem:** The requirements mandate medium/low/medium-last reviews with no effort above `medium`. However:
     - `EFFORTS` (`line 34`) permits `"high"` and `"xhigh"` for `codex` (and `"high"`, `"xhigh"`, `"max"` for `claude`).
     - In `load_pin` (`line 89`), even when `live=True` and `schedule.completion_order == "last"`, a `[reviewers.<name>]` entry for `codex` with `effort = "high"` or `"xhigh"` is accepted without refusal.
     - In `load_pin` (`lines 106-112`) and `check_schedule` (`lines 147-159`), `[schedule]` and `completion_order = "last"` are optional even when `live=True`. A live `.conclave/reviewers.toml` omitting `[schedule]` or `completion_order = "last"` passes `load_pin()` / `--check-pin` while configuring `"high"` or `"xhigh"` step efforts.
   - **Reproduction:** Set `effort = "high"` on the live `codex` reviewer in `.conclave/reviewers.toml` (with `completion_order = "last"`), or omit `completion_order = "last"` and set `plan = { effort = "high", lenses = ["plan"] }`, then invoke `load_pin()` / `--check-pin`. Both succeed instead of raising `Refused`.

2. **[P2] `record_policy` bypasses `NEVER_REVIEWS` for committed `completion_order = "last"` policies (`scripts/review-dispatch.py:50`, `scripts/review-dispatch.py:94-97`, `scripts/review-dispatch.py:229-236`)**
   - **Problem:** `load_pin(data=result.stdout)` sets `live = (data is None)` to `False`, which skips the `NEVER_REVIEWS` check at `lines 94-97`. If a current-policy record (`completion_order = "last"`, non-legacy `policy` SHA) points to a commit whose `.conclave/reviewers.toml` routes to `cli = "claude"`, `record_policy` accepts it instead of refusing Claude as a reviewer under current policy.
   - **Reproduction:** Call `record_policy` on a findings record with `policy = "<sha>"` where `<sha>:.conclave/reviewers.toml` has `completion_order = "last"` and a reviewer with `cli = "claude"`. `load_pin(data=...)` returns the pin without raising `Refused`.

3. **[P2] `clean()` ignores `HIGHEST: P1/P2` lines with trailing text, allowing contradictory declarations to pass as clean (`scripts/review-dispatch.py:169-180`)**
   - **Problem:** `HIGHEST` (`line 169`) matches `^\s*HIGHEST:\s*(P[123])\b` (allowing trailing commentary on the line), whereas `clean()` (`line 179`) matches `^\s*HIGHEST:\s*(P[123]|none)\s*$` (requiring end-of-line immediately after the token). A review containing `HIGHEST: P1 — race condition` in the body and `HIGHEST: none` at the end has ` len(declarations) == 1` in `clean()`, returning `True` despite the contradictory `P1` declaration.
   - **Reproduction:** Call `clean("HIGHEST: P1 - data race\nHIGHEST: none\nOVERALL: approve")`. It returns `True` instead of `False`.

4. **[P3] `validate_current_record` raises `KeyError` instead of `Refused` when an entry lacks `"writer"` (`scripts/review-dispatch.py:254-255`)**
   - **Problem:** `validate_current_record` indexes `e["writer"]` directly before checking whether `"writer"` is present on the parsed entry dict, causing an unhandled `KeyError` traceback rather than `Refused` on malformed record entries.
   - **Reproduction:** Call `validate_current_record(pin, {"plans": [{"_line": 1}], "rounds": [], "completions": []})` with a `completion_order = "last"` pin; `e["writer"]` raises `KeyError`.

HIGHEST: P2
OVERALL: needs-attention

### dispatcher2

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `3fe1a8fd4a5ab38d7ab93bb5aef711511a19480f3f11091bbfa806915a6fa7de`.

Reviewed the supplied `scripts/review-dispatch.py` part 2 of 3 source (lines 351–607) against the scoped requirements:

- **No Claude reviewer & effort ceiling (`low` / `medium` only):** `review()` (lines 494–510) refuses any reviewer whose CLI is in `NEVER_REVIEWS`, resolves `models_by_effort` for `agy`, rejects any `selected_effort` outside `("low", "medium")`, and verifies that `agy` models start with `gemini-` and end with `-{selected_effort}`.
- **Scheduled lenses & shim safety:** `lens_block()` (lines 357–366), `command()` (lines 404–418), and `review()` (lines 511–535) write the lens-augmented prompt to `tmp / "prompt.md"` before constructing the command so `.cmd`/`.bat` shims and long prompts receive the full scheduled instructions via file pointer without `cmd.exe` argument injection.
- **Executable resolution & process isolation:** `find_cli()` and `fully_qualified()` (lines 372–401) restrict lookup to fully qualified `PATH` entries and `PATHEXT` candidates, avoiding working-directory hijacking on Windows. `run()`, `kill_tree()`, and `remove_scratch()` (lines 421–480) enforce `timeout` and `MAX_OUTPUT_BYTES` limits and clean up the process tree and scratch directory.
- **Envelope & integrity helpers:** `atomic_write()`, `raw_lines()`, `canonical()`, and `digest()` (lines 568–605) preserve byte-accurate review content across LF/CRLF checkouts.

No concrete defects found in this slice.

HIGHEST: none
OVERALL: approve

### dispatcher3

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `184e5353a0424067aac780b67a3c4afb16880aa9b71f698b078ca763b386743e`.

### Findings

1. **P2 — `record_completion` blocks retry after an unreturned round when a legacy/earlier returned completion review already exists (`scripts/review-dispatch.py`, line 825)**
   - **Location:** `scripts/review-dispatch.py` line 825 (`record_completion`) and lines 932–949 (`main`).
   - **Problem:** Under legacy policies (where `completion_order != "last"`), a findings file can legitimately already contain a returned `## Completion review` before all rounds or passes finish. Even under `completion_order == "last"`, `record_completion` checks `if any(returned_pass(kind, entry) for entry in found[key]): raise Unrecorded(...)`. However, in `main()` (line 915), `existing_findings` and `check_sequence` run before the reviewer executes, while `record_completion` runs *after* `review()` completes. If another process or an earlier legacy pass already recorded a returned `kind` pass (when `completion_order != "last"`, `check_sequence` is skipped at line 912), `main()` runs the full external LLM review before `record_completion` refuses to record it at line 825. More importantly, for legacy pins without `completion_order == "last"`, `main()` does not validate `existing_findings` before running `--kind completion` or `--kind plan` (lines 928–937 only pre-read `args.record` when `args.kind == "round"`). If `args.record` is unreadable or already holds a returned completion/plan pass under a legacy pin, `review()` runs and spends a full review invocation before `record_completion` raises `Unrecorded` at line 821 or 825.
   - **Reproduction:** With a pin where `completion_order` is not `"last"`, run `review-dispatch.py --writer codex --prompt p.md --kind completion --candidate <40-hex> --record bad.md` where `bad.md` either has a malformed heading or already has a returned `## Completion review`. `main()` skips lines 912–937, executes `review()` in full, and only then fails in `record_completion()` with exit code 2.

2. **P3 — Campaign review marker `build/<writer>-campaign/review.json` can overwrite or unlink a concurrent invocation's marker (`scripts/review-dispatch.py`, lines 942–950)**
   - **Location:** `scripts/review-dispatch.py` lines 942–950.
   - **Problem:** When `CODEX_THREAD_ID` or `CLAUDE_CODE_SESSION_ID` is set, `main()` writes `ROOT / "build" / f"{args.writer}-campaign" / "review.json"` with `{"session": session, "pid": os.getpid(), "deadline": ...}` and unconditionally deletes `marker.unlink(missing_ok=True)` in the `finally` block without verifying that the file still belongs to `os.getpid()`. If two `review-dispatch.py` processes for the same writer overlap (for instance, a timed-out or backgrounded dispatch racing a new dispatch, or a preflight failure in a second invocation while the first is still running), the second process overwrites `review.json` and, upon exiting early (or finishing first), unlinks `review.json` while the other review process is still actively running, stripping its heartbeat/stall-breaker exemption.
   - **Reproduction:** Start a long review with `CODEX_THREAD_ID=s1`. While it is inside `review()`, invoke a second `review-dispatch.py` with `CODEX_THREAD_ID=s1` that fails inside `review()` (or finishes quickly). Its `finally` block unlinks `build/codex-campaign/review.json`, leaving the first process without a review marker.

HIGHEST: P2
OVERALL: needs-attention

### guard-followup

Model: `gemini-4-argon-low`. Effort: `low`. Execution: `returned`. Snapshot SHA-256: `4e2ff50c5caf8dd150e42d41730f9c6f8df05ca88ef349ed5052bbaa8e3e92d8`.

Verified the diffs in [`scripts/codex_campaign.py`](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py) and [`scripts/claude_campaign.py`](file:///R:/GitHub/ScratchPad/scripts/claude_campaign.py):

- `save` checks for `paused-<generation>` when `status != 'ended'` and forces `status='paused', pending=False`.
- `hook` on pause touches the cancellation marker, attempts to acquire `ownership_lock` and persist the paused state immediately, and re-verifies `matches(state, session)` after `save` before returning a block decision on Stop.
- Heartbeat checks `matches(state, session, generation)` after `save` before queuing a resume message.
- `review_wait` scans per-dispatcher `.json` markers under `reviews/` and validates session, deadline, and live PID.

No remaining concrete failures found.

HIGHEST: none
OVERALL: approve

### policy-followup

Model: `gemini-4-argon-low`. Effort: `low`. Execution: `returned`. Snapshot SHA-256: `42c790414e9e5e6da7bc84b0975e9ca5c0913b7187b2b74082079699ff4482e2`.

All five supplied findings are resolved by the diff:

1. **Live effort ceiling:** `load_pin` enforces `effort in ("low", "medium")` for `codex` reviewers, low/medium `gemini-*` models for `agy` reviewers, and `effort in ("low", "medium")` across all schedule steps (`plan`, `completion`, `rotation`, `escalation`, and `rounds`) when `live` is true.
2. **Contradictory `HIGHEST:` declarations:** `clean()` counts all `^\s*HIGHEST:` lines via `all_declarations` and requires `len(all_declarations) == len(declarations) == 1`, rejecting multiple or malformed `HIGHEST:` lines alongside a valid `P3`/`none` line.
3. **Malformed writer metadata:** `e.get("writer") not in WRITERS` is checked before `check_sequence` and `pin["routes"]` lookup, raising `Refused` instead of `KeyError` on missing or invalid writer fields.
4. **Consumed one-pass preflight:** When `one_pass and args.record` is set, preflight reads and validates existing findings before executing the review, raising `Unrecorded` if the file cannot be read back or already contains a returned pass for `args.kind`, unabhängig of `completion_order == "last"`.
5. **Concurrent campaign review markers:** Marker paths now isolate concurrent runs under `build/<writer>-campaign/reviews/<pid>-<uuid4>.json`.

No concrete remaining failures found in the supplied changes.

HIGHEST: none
OVERALL: approve

### Completion review

Model: `gemini-4-argon-medium`. Effort: `medium`. Execution: `returned`. Snapshot SHA-256: `bb57b4b173a6bc304ff1a3391681ccea493dac45f1f9ebacd285307ffa403747`.

### Completion Review: Switchable Writers and Independent Campaign Runtimes

#### Task Coverage Against [`docs/specs/2026-11-06-switchable-writers-design.md`](file:///R:/GitHub/ScratchPad/docs/specs/2026-11-06-switchable-writers-design.md)

1. **Review Routing, Pin, and Schedule Ceiling**
   - [`.conclave/reviewers.toml`](file:///R:/GitHub/ScratchPad/.conclave/reviewers.toml) defines `schema_version = 1`, routes `claude` (and `gemini`) to `astra` (`codex`, `gpt-6-astra`, `medium`) and `codex` to `argon` (`agy`, `gemini-4-argon-low` and `gemini-4-argon-medium`), sets `completion_order = "last"`, `max_low_rounds = 8`, medium `plan` and initial `adversarial` rounds, low `rotation` and `escalation` rounds, and medium `completion`.
   - [`.conclave/antigravity-review-settings.json`](file:///R:/GitHub/ScratchPad/.conclave/antigravity-review-settings.json) restricts Antigravity review invocations to read-only `git status`, `git rev-parse`, `git show`, and `git diff` commands while denying `write_file(*)` and `edit_file(*)`.
   - [`scripts/review-dispatch.py`](file:///R:/GitHub/ScratchPad/scripts/review-dispatch.py) (verified via `policy-followup` and 95/23 test runs) enforces the live medium effort ceiling across reviewer definitions and all schedule steps, validates `WRITERS` before route lookup, rejects contradictory or multiple `HIGHEST:` declarations in `clean()`, preflights one-pass records before invoking the reviewer, and writes concurrent-safe review wait markers under `build/<writer>-campaign/reviews/<pid>-<uuid4>.json`.

2. **Independent Campaign Runtimes and Cross-Harness Interlock**
   - [`scripts/claude_campaign.py`](file:///R:/GitHub/ScratchPad/scripts/claude_campaign.py) and [`scripts/codex_campaign.py`](file:///R:/GitHub/ScratchPad/scripts/codex_campaign.py) keep separate runtime trees (`build/claude-campaign/` and `build/codex-campaign/`) with zero cross-harness imports, sharing only `build/writer-ownership.lock` to reject concurrent writer acquisition.
   - Lifecycle semantics covered and verified in `guard-followup` and `test_campaign_runtime.py` (22 tests): single-owner acquisition, refusal when the opposing writer is active, explicit handoff/end before switching, generation-bound state, pause marker (`paused-<generation>`) persistence under `ownership_lock`, post-`save` `matches()` re-verification in `hook` and heartbeat before blocking Stop or queueing resume messages, three-strike no-progress breaker, progress hashing that excludes `build/` and `- bookkeeping:` lines while counting substantive edits/evidence, run-specific `Closeout run=<run_id>` and `PARKED <UTC> run=<run_id>` markers, live same-session review wait suppression, and Codex watchdog owner PID/creation-time validation and bounded queue timeouts.

3. **Documentation, Skills, and Harness Wiring**
   - [`docs/writer-campaigns.md`](file:///R:/GitHub/ScratchPad/docs/writer-campaigns.md) and [`.codex/skills/independent-review/SKILL.md`](file:///R:/GitHub/ScratchPad/.codex/skills/independent-review/SKILL.md) match the reviewed design contract, command shapes, heartbeat rules, breaker semantics, and hook trust requirements.
   - [`AGENTS.md`](file:///R:/GitHub/ScratchPad/AGENTS.md), [`CODEX.md`](file:///R:/GitHub/ScratchPad/CODEX.md), [`GEMINI.md`](file:///R:/GitHub/ScratchPad/GEMINI.md), harness skills, and hook configurations wire each writer to its own campaign script while preserving Claude `PreToolUse` routing (`agent_routing.py check`: 8 routed agents, 0 problems) and TODO graph integrity (`todo-graph.py validate` and `plan --check` clean).

#### Deployment and Activation Boundary

- Native Codex hook trust (`/hooks` approval of `.codex/hooks.json`) and end-to-end delivery into a live idle Codex thread require interactive operator activation on the host and are explicitly not claimed verified in this snapshot. This matches the documented boundary in [`docs/specs/2026-11-06-switchable-writers-design.md`](file:///R:/GitHub/ScratchPad/docs/specs/2026-11-06-switchable-writers-design.md) and [`docs/writer-campaigns.md`](file:///R:/GitHub/ScratchPad/docs/writer-campaigns.md).

#### Missing Implementation

- None identified. All design requirements and follow-up fixes are accounted for in the snapshot evidence.

COMPLETION: complete
