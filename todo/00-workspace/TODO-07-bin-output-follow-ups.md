---
schema_version: 1
id: bin-output-follow-ups
domain: 00-workspace
status: active
title: "TODO-07 -- Bin Output Follow-Ups"
depends_on: []
track: W0
---

# TODO-07 -- Bin Output Follow-Ups

> **Goal:** The Bin-output machinery D00 T01 §41 shipped (guards, launcher, clean script, soak glob, smoke manifest) keeps hardening after its review: every filed residual ships with fixtures and review instead of rotting as a known gap.

> [!IMPORTANT]
> **Current state:** D00 T01 §41 shipped the TFM-less layout plus `tools/check-bin-layout.py` (stems, conformance), `tools/clean-bin.py`, `tools/launch.py`, the soak-glob proof, and the smoke manifest check. Its plan review returned 24 findings; 8 harden this machinery and home here as the first resident section.

## Inputs

- [`tools/check-bin-layout.py`](../../tools/check-bin-layout.py) -- the stems plus conformance guards §1 extends
- [`tools/clean-bin.py`](../../tools/clean-bin.py) -- the pruner §1 extends
- [`tools/launch.py`](../../tools/launch.py) -- the launcher §1 extends
- [§41 review record](../../docs/reviews/00-workspace/D00-T01-s41.md) -- the plan-review ledger this file's §1 works off

## Outcome

- Multi-TFM additions, Windows-only drift, stale migration legs, unsafe clean roots, and silent glob breakage all fail loudly instead of rotting.
- The launcher error names the build, and one operator command wraps build, run, and clean.

**Adjacency:** all=not-applicable (build-machinery follow-ups with no user-facing feature surface; the app surfaces the machinery ships declare their own adjacency in their own files)

**Adjacency rationale:** This file touches only build tooling: guard scripts, CI YAML, fixtures, and operator docs for the Bin layout. Nothing executes at app runtime or stores user data, so no adjacency key applies.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | Bin machinery follow-ups | D00 T01 §41 |  [ ]   |

---

## 1. Bin Machinery Follow-Ups

Why this section exists: the §41 plan review returned 24 findings and 8 of them harden the Bin-output machinery (guards, launcher, clean, soak glob, manifest, operator command), so they home here as the first resident file past the 55-section cap. -> XREF: D00 T01 §41 (filed from its plan review); -> SOURCE: plan-review-D00-T01-s41-2026-09-19-t07 D00-T01-S41-PR3 D00-T01-S41-PR6 D00-T01-S41-PR9 D00-T01-S41-PR10 D00-T01-S41-PR13 D00-T01-S41-PR15 D00-T01-S41-PR22 D00-T01-S41-PR24 (`gpt-5.6-sol` high over §41 plus §40 plus D00 T06 §1, 24 findings, 8 filed here, 3 filed at D00 T06 §1, 2 accepted in the §41 stamp run, 1 duplicate, 10 rejected with reasons in the §41 findings file).

**Groomed 2026-09-23:** Already in the repo: the only CI job runs on windows-2025 and carries both the conformance probe with fire proofs and the clean-bin fixture proof (`.github/workflows/build.yml:18,55-71`), so the Windows-conformance and clean-proof items close by citing a green run at implementation (grooming ticks nothing).

- [ ] Multi-targeted projects fire the guards: a `TargetFrameworks` (plural) presence fails the stems or conformance check instead of colliding silently under `AppendTargetFrameworkToOutputPath=false`, so a future second TFM cannot regress the single-TFM tree quietly (PR3 D00-T01-S41-PR3). This item is a joiner from the §41 plan review. Done when: the leg plus a fixture ships.
- [ ] Conformance runs on Windows CI as well as Linux: the evaluated-path plus no-bin probe executes on both runners, so OS-conditioned MSBuild properties and path-normalization drift surface (PR6 D00-T01-S41-PR6). This item is a joiner from the §41 plan review. Done when: the windows leg is green with its fire proofs. **Corrected 2026-09-19:** the Linux leg is retired (operator decision 2026-09-19: Windows-only CI); the windows job carries the probe plus fire proofs since the move, so this item re-proves rather than adds.
- [ ] Clean prunes stale TFM legs: `Bin/<Project>/<Configuration>/<tfm>/` dirs inside live projects are removed (live `<RID>` legs kept), clearing the exact residuals the migration created (PR9 D00-T01-S41-PR9). This item is a joiner from the §41 plan review. Done when: the leg plus a fixture ships.
- [ ] Clean refuses dangerous roots: `--bin-dir` outside a `Bin/`-shaped dir, path traversal, and junction escape fail loudly with `--dry-run` proving each, so the pruner cannot delete user data (PR10 D00-T01-S41-PR10, filed scoped to root/traversal/junction guards). This item is a joiner from the §41 plan review. Done when: the guards plus fixtures ship.
- [ ] The launcher error names the build: resolving an unbuilt exe prints the checked build command for the platform instead of bare `build first` (PR13 D00-T01-S41-PR13, filed scoped to the message; no auto-build). This item is a joiner from the §41 plan review. Done when: the message names the command on both OSes. **Corrected 2026-09-19:** Windows only (operator decision 2026-09-19: Windows-only CI and dev); the message names the Windows build command.
- [ ] The soak glob gains a maintained fixture: a CI check asserts the golden-failure glob's directory equals the evaluated UI `OutputPath`, so future workflow edits cannot silently break diagnostic collection (PR15 D00-T01-S41-PR15). This item is a joiner from the §41 plan review. Done when: the check plus a breaking fixture ships.
- [ ] Clean proves itself on Windows CI: the fixture proof runs on the windows job as well as linux, so the pruner is verified where junctions and case-insensitivity live (PR22 D00-T01-S41-PR22, filed for the Windows leg; version/invocation audit criteria folded into D00 T06 §1). This item is a joiner from the §41 plan review. Done when: the windows leg is green. **Corrected 2026-09-19:** the linux job is retired (operator decision 2026-09-19: Windows-only CI); the windows job carries the fixture proof since the move, so this item re-proves rather than adds.
- [ ] One operator command wraps build, run, and clean: a single entry point with diagnostics naming the selected configuration, RID, executable, and provenance, so operators never spell the `Bin/` topology (PR24 D00-T01-S41-PR24, premium). This item is a joiner from the §41 plan review. Done when: the command plus docs ship.
- [ ] Commit: `"workspace: follow up Bin machinery per §41 plan review"`

**Test checkpoint:** plural TFMs fire, both runners probe conformance, stale legs prune, dangerous roots refuse, the launcher error guides, the glob fixture guards, clean proves on Windows, and one command wraps the rest. Falsifiable by any silent pass on the above. **Corrected 2026-09-19:** the Windows runner probes conformance (operator decision 2026-09-19: the Linux leg is retired).

## Verification

- [ ] Guards fire on plural TFMs, stale legs refuse cleanly, and dangerous roots fail loud
- [ ] `python3 scripts/todo-graph.py validate` clean
