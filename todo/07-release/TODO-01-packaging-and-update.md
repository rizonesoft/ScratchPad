---
schema_version: 1
id: packaging-and-update
domain: 07-release
status: draft
title: "TODO-01 -- Packaging and Update"
depends_on: ["winui-app-spine"]
track: R1
---

# TODO-01 -- Packaging and Update

> **Goal:** The app ships as a signed MSIX that installs and uninstalls cleanly, updates itself, and releases through a checklist that proves readiness.

> [!IMPORTANT]
> **Current state:** No packaging exists. The app builds per `D00 T01 §2`; this file turns the build into something a user can install.

## Inputs

- [`00-workspace/TODO-01-repo-and-toolchain.md`](../00-workspace/TODO-01-repo-and-toolchain.md) -- the build this file packages

## Outcome

- A signed MSIX installs, runs, and uninstalls cleanly on a stock Windows 11 machine.
- Updates arrive through a committed channel with rollback on failure.
- No release ships without the checklist proving green suites, clean audit, and current docs.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=not-applicable (update preference lives in D01 T02 §2); reporting=not-applicable (no reports in this file); notifications=applicable @ D07 T01 §3; permissions=not-applicable (install consent is platform UI); audit=not-applicable (release log is section 4, not a user audit trail); exchange=not-applicable (no import/export in this file); reverse=applicable @ D07 T01 §3

**Adjacency rationale:** Update notifications are the notifications; rollback is the reversal; the release log is project evidence, not a user-facing audit trail.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | MSIX package build | D00 T01 §2 |  [ ]   |
|   2   |   §2    | Clean-machine install test | §1 |  [ ]   |
|   3   |   §3    | Update channel with rollback | §2 |  [ ]   |
|   4   |   §4    | Release checklist | §3 |  [ ]   |
|   5   |   §5    | First signed release | §4 |  [ ]   |
|   6   |   §6    | Store and WinGet distribution | §1 |  [ ]   |

---

## 1. MSIX Package Build

Why this section exists: the package is the product as the user meets it. It builds in CI, signed, with the app's identity pinned.

**Groomed 2026-09-13:** Notepad audit: the x64 plus ARM64 architecture matrix is now explicit.

- [ ] CI builds a signed MSIX from the §-chosen packaging project. Done when: the artifact downloads from the run.
- [ ] Package identity (name, publisher, version from the build) is pinned and recorded. Done when: the identity doc exists.
- [ ] Capabilities requested are the minimum the app needs, each justified. Done when: the justification is written.
- [ ] The package builds for x64 and ARM64 as Notepad ships natively since v11.2204; the architecture matrix is recorded and each arch installs on its VM. Done when: both arch installs are driven. Source: https://www.xda-developers.com/windows-11-notepad-arm64-native-support-media-player-update/
- [ ] Commit: `"release: build the MSIX package"`

**Test checkpoint:** Signed MSIX artifact in CI with pinned identity and justified capabilities. Cheaper substitute that fails: a zip of the build folder.

## 2. Clean-Machine Install Test

Why this section exists: install must work where nothing of ours has ever been. The test proves it on a clean VM, automatically.

- [ ] Install on a clean Windows 11 VM succeeds with no prerequisites beyond the documented ones. Done when: the automated test passes.
- [ ] First launch after install opens to the expected state with no errors. Done when: the launch test passes.
- [ ] Uninstall removes the app, associations, and settings with nothing orphaned. Done when: the uninstall test passes.
- [ ] Commit: `"release: test clean-machine install"`

**Test checkpoint:** Install, launch, and uninstall tests green on a clean VM in CI. Cheaper substitute that fails: install tested on the dev machine.

## 3. Update Channel with Rollback

Why this section exists: updates must arrive and must be survivable. A failed update rolls back to a working app, never to a brick.

**Groomed 2026-09-13:** Notepad audit: the post-update What's New notes surface is now explicit.

- [ ] The update channel (store or self-hosted, chosen here) delivers updates with the choice recorded. Done when: the choice and its rationale are written.
- [ ] A failed or interrupted update rolls back to the previous working version. Done when: the rollback test passes.
- [ ] The user is notified of updates per the committed policy, never force-restarted mid-work. Done when: the policy is written and tested.
- [ ] Post-update What's New notes surface per the notification policy with a revisitable entry as captured. Done when: the notes and entry are driven. Source: https://blogs.windows.com/windows-insider/2026/01/21/notepad-and-paint-updates-begin-rolling-out-to-windows-insiders/
- [ ] Commit: `"release: ship updates with rollback"`

**Test checkpoint:** Update, rollback, and notification-policy tests green. Cheaper substitute that fails: updates that require a manual reinstall.

## 4. Release Checklist

Why this section exists: releases are proven, not declared. The checklist names every proof and blocks the release until each is green.

- [ ] `docs/release-checklist.md` requires: green suites, clean secret scan, current compatibility record, current docs, and clean install test. Done when: each item names its proof.
- [ ] The checklist runs as a CI gate on the release branch or tag. Done when: a probe gap blocks the release (reverted immediately).
- [ ] Each release records its checklist results with the version. Done when: the record format exists.
- [ ] Commit: `"release: add the release checklist"`

**Test checkpoint:** Checklist gates the release in CI; probe gap blocks. Cheaper substitute that fails: a checklist in a wiki nobody opens.

## 5. First Signed Release

Why this section exists: the first release proves the whole pipeline end to end, from tag to installed update.

- [ ] Tagging the release produces the signed MSIX through CI with no manual steps. Done when: the pipeline runs green from tag to artifact.
- [ ] The release passes the §4 checklist with results recorded. Done when: the record exists.
- [ ] Installing the release over the previous version updates cleanly with settings preserved. Done when: the upgrade test passes.
- [ ] Commit: `"release: ship the first signed release"`

**Test checkpoint:** Tag-to-artifact pipeline green; checklist record exists; upgrade preserves settings. Cheaper substitute that fails: a hand-built "release" binary.

## 6. Store and WinGet Distribution

Why this section exists: users install from the Store and WinGet. The channels are proven with a published package, not assumed from docs.

- [ ] The MSIX publishes to the Microsoft Store with the listing owned and the submission proven. Done when: the Store listing installs the app on a clean VM.
- [ ] A WinGet manifest publishes and `winget install` works from a clean VM. Done when: the install is driven.
- [ ] Store and WinGet versions stay in lockstep with releases through the §4 checklist. Done when: the checklist names the proof.
- [ ] Commit: `"release: distribute through Store and WinGet"`

**Test checkpoint:** Store and WinGet installs driven on clean VMs; version lockstep in the checklist. Cheaper substitute that fails: a release page download link called distribution.

## Verification

- [ ] `ctest --test-dir build --output-on-failure` green
- [ ] Checklist green with its record
- [ ] `python3 scripts/todo-graph.py validate` clean
