---
schema_version: 1
id: operator-docs
domain: 00-workspace
status: active
title: "TODO-06 -- Operator Docs"
depends_on: []
track: W0
---

# TODO-06 -- Operator Docs

> **Goal:** The operator docs a clean clone follows stay true as the tree moves: every prerequisite, path, and command they name matches what the repo currently requires.

> [!IMPORTANT]
> **Current state:** `docs/bootstrap.md` carries the prerequisite table plus the setup steps, `docs/build.md` the build, clean, and launch commands. D00 T01 §41 made Python the only documented way to launch the stub and prune `Bin/` on Windows, but the prerequisite table still scopes Windows Python to the pre-commit TODO gate. This file's §1 audits the table for post-§41 accuracy. `docs/testing.md`'s Birth rule still names the fixed X/Y 10000 seed D00 T02 §18 replaced with a derived origin; §2 corrects it.

## Inputs

- [`docs/bootstrap.md`](../../docs/bootstrap.md) -- the prerequisite table plus setup steps §1 audits
- [`docs/build.md`](../../docs/build.md) -- the launch and clean commands that widened Python's role
- [§41 review record](../../docs/reviews/00-workspace/D00-T01-s41.md) -- round-5 advisory R5-F1 this file's §1 works off
- [`docs/testing.md`](../../docs/testing.md) -- the Birth rule paragraph §2 corrects
- [`tests/UI/UiLaunch.cs`](../../tests/UI/UiLaunch.cs) -- `SeedSettings` and `DeriveOffScreenOrigin`, the code §2 documents

## Outcome

- Every prerequisite-table row names every live consumer of its prerequisite.
- No setup step runs a command its row's prerequisite does not provide.
- The testing procedure's Birth rule states the derived off-screen origin the launch harness actually seeds.

**Adjacency:** all=not-applicable (operator-docs wording with no runtime behavior; the app surfaces the docs describe declare their own adjacency in their own files)

**Adjacency rationale:** This file changes doc prose only: prerequisite scope plus any understated rows the audit finds. Nothing executes at app runtime, stores user data, or gates an action, so no adjacency key applies.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Prerequisite scope audit | D00 T01 §41 |  [ ]   |
|   2   |   §2    | Birth rule states the derived origin | D00 T02 §18 |  [ ]   |

---

## 1. Prerequisite Scope Audit

Why this section exists: the §41 review's round-5 advisory found `docs/bootstrap.md:12` scoping Windows Python to the pre-commit TODO gate while §41's launcher and clean docs make Python the only documented launch and prune path. Below bar at round 5, so it files here instead of re-rounding. Audit the whole prerequisite table (both OSes) against the post-§41 operator paths and correct every understated row. **Corrected 2026-09-20:** the table is Windows-only since the 2026-09-19 operator decision (Linux lanes retired); audit the Windows rows. The cited `docs/bootstrap.md:12` line drifted under the rewrite; anchor by section header instead. -> XREF: D00 T01 §41 (filed from its round-5 review); -> SOURCE: panel-D00-T01-s41-round-5-R5-F1 (consistency advisory; transcribed in docs/reviews/00-workspace/D00-T01-s41.md); -> SOURCE: plan-review-D00-T01-s41-2026-09-19-t06 D00-T01-S41-PR1 D00-T01-S41-PR2 D00-T01-S41-PR21 (`gpt-5.6-sol` high over §41 plus §40 plus D00 T06 §1, 24 findings, 3 filed here in 2 items with PR1 plus PR2 sharing the pointer item, 8 filed at D00 T07 §1, 2 accepted in the §41 stamp run, 1 duplicate, 10 rejected with reasons in the §41 findings file).

- [ ] Every prerequisite-table row is audited against the post-§41 operator paths (launch, clean, hooks, builds, tests): each row names every live consumer with its required version and invocation. Done when: the audit names each row's consumers with file and stable anchor (section header or command name, not bare line numbers).
- [ ] Understated rows are corrected, starting with the Windows Python row gaining the launcher and clean consumers. Done when: no row omits a live consumer.
- [ ] §40 gains a dated pointer to §41: its shipped layout promises a `<tfm>` leg §41 removed, so one prose line names §41 as governing (no tick or evidence change), mirroring the §§1-2 pointers (PR1 PR2 D00-T01-S41-PR1 D00-T01-S41-PR2, shared item). This item is a joiner from the §41 plan review. Done when: the pointer reads with the §41 ref.
- [ ] A checked drift script maps live Python consumers to prerequisite-table rows: every `tools/*.py` the docs invoke appears in the table on its row, so the launcher/cleaner class cannot go undocumented again (PR21 D00-T01-S41-PR21). This item is a joiner from the §41 plan review. Done when: the script plus a CI leg ship with a fixture proving it fires on an unlisted consumer.
- [ ] Commit: `"workspace: audit prerequisite scope per §41 review"`

**Test checkpoint:** each prerequisite row lists its consumers and each setup command resolves to a provided prerequisite; falsifiable by any live consumer missing from its row or any step naming an unprovided command.

## 2. Birth Rule States the Derived Origin

> **Started:** 2026-10-03T09:59:31Z

Why this section exists: D00 T02 §18 replaced the fixed off-screen seed with an origin derived outside the virtual screen (`DeriveOffScreenOrigin` in `tests/UI/UiLaunch.cs`, a922f86), but the `docs/testing.md` Birth rule still says `UiLaunch.SeedSettings` seeds X/Y 10000, so an operator following the procedure expects a point the code no longer uses and cannot reason about negative-origin or stacked-monitor layouts. Found 2026-10-03 while reviewing D00-T02-S10-PR1 A2, whose rationale cites the same retired point. D00 T02 is at its 55-section cap, so the correction files here by subject.

- -> XREF: D00 T02 §18 -- owns the derived origin this section documents.
- -> SOURCE: reconcile-2026-10-03-birth-rule-drift (docs/testing.md Birth rule vs tests/UI/UiLaunch.cs DeriveOffScreenOrigin on 12b662c)

- [x] The Birth rule paragraph states the derived origin: `UiLaunch.SeedSettings` seeds a point outside the virtual screen derived from SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN, SM_CXVIRTUALSCREEN, and SM_CYVIRTUALSCREEN (never a fixed coordinate), under the same `SCRATCHPAD_BACKGROUND=1` and default-geometry conditions, and cites D00 T02 §18. Done when: the paragraph names the derivation, matches `DeriveOffScreenOrigin` as read on the candidate, and no fixed 10000 seed remains in `docs/testing.md`. Done: `docs/testing.md` Birth rule now names `UiLaunch.DeriveOffScreenOrigin` over the four SM_*VIRTUALSCREEN metrics with the code's side order (right edge, above, left, below, overflow skips) and cites D00 T02 §18; `grep -n "10000" docs/testing.md` prints nothing.
- [x] The rest of the Birth rule paragraph is read against the current `UiLaunch.cs` and `UiForeground.cs`, and any other claim D00 T02 §18 or later sections superseded is corrected in place with its owning section cited. Done when: every factual claim in the paragraph is quoted beside the code line that backs it in the review record. **Corrected 2026-10-03 (operator decision after the review hit its five-round cap on R5-C1):** was "correct every superseded claim in place"; restating ForegroundLog's recording and agreement rules in prose drifted on every round (popup rest-wins, off-screen skip, hook-loss tolerance, minimized restore rects), so the Birth rule and the foreground-proof paragraph now point at `tools/ForegroundLog/Program.cs` (header plus per-rule comments) as the authoritative gate spec instead of restating it. Done: the Primary count corrected (`every Primary test seeds an explicit on-primary rect`; GateCalibrationTests and UiLeakBundleTests joined the set), unseeded paths restated to birth off-screen through `MainWindow.BirthOrigin` (R2-C1), the safety net restated as placement before a no-activate show (R1-C1), the gate-semantics sentences at `docs/testing.md` lines 27 and 37 replaced by the pointer, and the explicit-geometry rule given its 50/50 exception (an explicit default-valued seed maps off-screen, pinned by `SeedPrecedenceTests`; plan review D00-T06-S2-PR4); every remaining claim sits beside its backing code line in the Claim table of `docs/reviews/00-workspace/D00-T06-s2.md`.
- [x] Commit: `"docs: state the derived off-screen origin in the birth rule"`

**Test checkpoint:** `grep -n "10000" docs/testing.md` prints nothing, the Birth rule paragraph reads beside `DeriveOffScreenOrigin` with every claim backed, and `python3 scripts/todo-graph.py validate` stays at 0 fatal. Cheaper substitute that fails: deleting the number without stating the derivation.

## Verification

- [ ] Prerequisite rows name every live consumer
- [ ] The Birth rule names the derived off-screen origin
- [ ] `python3 scripts/todo-graph.py validate` clean
