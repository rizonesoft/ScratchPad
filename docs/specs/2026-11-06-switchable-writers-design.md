# Switchable writers and independent campaign runtimes

Operator: 2026-11-06. Claude Code and Codex can each execute ScratchPad work, with one active writer. The required reviewer replaces the Opus gate: Claude uses Codex GPT-6 Astra; Codex uses Google Antigravity Gemini 4 Argon. Neither uses Claude as reviewer. Plan and initial adversarial passes are medium, follow-up rounds are low, and completion is medium and last. No reviewer exceeds medium.

## Owning layers

Review routing and scheduling belong to `.conclave/reviewers.toml` and `scripts/review-dispatch.py`. Writer permissions and execution workflow belong to AGENTS.md and harness-local skills. Run liveness belongs to separate Claude and Codex campaign scripts, hook configurations, and ignored runtime state. No runtime imports, state files, or scheduler jobs cross harnesses. A small cross-harness ownership interlock is permitted solely to prevent concurrent writers.

## Reference evidence

Steward has the requested completion-last schedule and Antigravity effort mapping. Recto has session-bound stop protection, generation-bound heartbeat ownership, run-specific closeout, and a three-strike no-progress breaker. Reference repositories remain read-only. ScratchPad has no existing campaign guard to preserve.

## Runtime mechanics

Each harness owns its campaign state, lock, generation, heartbeat, run file identity and stall counts. Lifecycle commands acquire, inspect, heartbeat, and end an explicit run. Stop hooks continue only the owning session while its run is active. Operator pause and interrupt override continuation. Another session and all reviewers are unaffected. A terminal run marker applies only to its run id. Progress is source and run evidence, excluding bookkeeping-only edits. Three unchanged stops park the run for operator recovery; a heartbeat cannot resurrect it.

Claude uses its session Cron tools. Codex uses its own hidden local heartbeat process and the installed `codex queue --thread ... --message ... --resume` capability. Messages are generation-bound and consumed by the original session; no second writer is launched. Queue failure or warning is recorded as degraded, never successful resumption. Native Codex Stop, Interrupt and SessionEnd hooks provide continuation and cancellation. Hook activation requires the host's native trust review; tests cannot substitute for that trust.

## Verification

Port the standalone Steward dispatcher with its focused suites, preserving historical evidence semantics and adding a hard runtime medium ceiling. Exercise real Argon low and medium invocations. Test both campaign runtimes with temporary repositories: single ownership, stale generation, wrong session, pause, completion, stall, bookkeeping, review wait and heartbeat failures. Verify hook payload/output shapes and wiring. Run independent Argon reviews; no returned review means no approval.

## Defaults and reversal

Use Steward's cap of eight low rounds and stop clean before completion. Reversal is a policy and script change; no application data migration is involved. No campaign starts merely because the machinery is installed.

## Reviewed lifecycle details

The only shared primitive is the OS file lock `build/writer-ownership.lock`; its handle is released on process death and never deleted to steal ownership. Each independent runtime atomically replaces its own `build/<harness>-campaign/state.json` after acquiring that lock. It reads the opposing state only to reject acquisition while the other writer is active. An abandoned active run requires the operator to end it by its recorded session id before handoff; there is no stale-time automatic writer takeover. Tests cover cross-harness refusal and handoff.

The dispatcher records its PID, owning session id and deadline in `build/<writer>-campaign/reviews/<pid>-<unique-id>.json`, removes the mark on exit, and bounds the reviewer timeout. Stop and heartbeat ignore only a live same-session review with an unexpired mark. This wait neither increments the stall counter nor queues duplicate work. Stale or unrelated marks do not suppress continuation.

Operator resume uses `acquire` after an ended, paused, parked, degraded or stalled run, creating a new generation, run id and zeroed stall count. `status` reads back that state. End the preceding run before switching harnesses. New generations invalidate queued heartbeats. No restart is automatic after a pause or stall.

Codex's worker records its PID plus the native session owner's PID and process creation identity. Every tick checks ownership, generation and owner identity. Owner death or PID reuse pauses the run without queueing; end, interrupt or stall makes it exit. A queue operation is bounded at thirty seconds; normal exit is within ten seconds and in-flight exit within forty. A message unconsumed for two intervals degrades the run. Restart a dead worker only for a still-active generation and the same verified owner process.

Progress hashes HEAD plus the sorted tracked and untracked nonignored file paths and contents, including deleted-file markers. `build/` is excluded. In the current run file only lines beginning `- bookkeeping:` are excluded. The other evidence, including review artifacts and TODO stamps, counts. Tests distinguish bookkeeping from substantive evidence and prove pause while the interlock is held.
