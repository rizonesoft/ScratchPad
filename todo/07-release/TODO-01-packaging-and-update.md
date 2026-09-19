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
- -> XREF: D01 T01 §11 -- the app icon asset this package consumes for its visuals

## Outcome

- A signed MSIX installs, runs, and uninstalls cleanly on a stock Windows 11 machine.
- A signed Inno Setup exe installs, runs, and uninstalls cleanly for users outside the Store path.
- Updates arrive through a committed channel with rollback on failure.
- No release ships without the checklist proving green suites, clean audit, and current docs.
- Versions derive from release tags at build time; no hand-edited version string ships.
- Product identity (copyright, publisher, logo, links) renders from one registry.
- Help content builds from the user guide with checked links and a surface map.
- The published guide and the F1 link switch land after the first signed release.

**Adjacency:** list=not-applicable (no lists in this file); document=not-applicable (no printed output in this file); settings=not-applicable (update preference lives in D01 T02 §2); reporting=not-applicable (no reports in this file); notifications=applicable @ D07 T01 §3; permissions=not-applicable (install consent is platform UI); audit=not-applicable (release log is section 4, not a user audit trail); exchange=not-applicable (no import/export in this file); reverse=applicable @ D07 T01 §3

**Adjacency rationale:** Update notifications are the notifications; rollback is the reversal; the release log is project evidence, not a user-facing audit trail.

## Implementation Order

| Order | Section | Deliverable | Depends On | Status |
| :---: | :-----: | ----------- | ---------- | :----: |
|   1   |   §1    | MSIX package build | D00 T01 §2, §9, §10, §11 |  [ ]   |
|   2   |   §2    | Clean-machine install test | §1 |  [ ]   |
|   3   |   §3    | Update channel with rollback | §2 |  [ ]   |
|   4   |   §4    | Release checklist | §3 |  [ ]   |
|   5   |   §5    | First signed release | §4 |  [ ]   |
|   6   |   §6    | Store and WinGet distribution | §1 |  [ ]   |
|   7   |   §7    | Share target registration | §1, D01 T01 §24 |  [ ]   |
|   8   |   §8    | Inno Setup installer and distribution | §1 |  [ ]   |
|   9   |   §9    | Dynamic version scheme | D00 T01 §2 |  [ ]   |
|  10   |   §10   | Product identity registry | -- |  [ ]   |
|  11   |   §11   | Help content pipeline | -- |  [ ]   |
|  12   |   §12   | Guide web publishing and link switch | §5 |  [ ]   |

---

## 1. MSIX Package Build

Why this section exists: the package is the product as the user meets it. It builds in CI, signed, with the app's identity pinned.

**Groomed 2026-09-13:** Notepad audit: the x64 plus ARM64 architecture matrix is now explicit.

- -> XREF: D01 T02 §13 -- the rename this packaging pins (exe, AppId, ProgId, URL scheme); §13 lands first so identity is final.

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
- [ ] A failed or interrupted update produces a rollback to the previous working version. Done when: the rollback test passes.
- [ ] The user is notified of updates per the committed policy, never force-restarted mid-work. Done when: the policy is written and tested.
- [ ] Post-update What's New notes surface per the notification policy with a revisitable entry as captured. Done when: the notes and entry are driven. Source: https://blogs.windows.com/windows-insider/2026/01/21/notepad-and-paint-updates-begin-rolling-out-to-windows-insiders/
- [ ] Commit: `"release: ship updates with rollback"`

**Test checkpoint:** Update, rollback, and notification-policy tests green. Cheaper substitute that fails: updates that require a manual reinstall.

## 4. Release Checklist

Why this section exists: releases are proven, not declared. The checklist names every proof and blocks the release until each is green. -> SOURCE: operator-finding-2026-09-19-release-acceptance (required list omitted update/rollback proof and an explicit docs-present leg; filed 2026-09-19).

- [ ] `docs/release-checklist.md` requires: green suites, clean secret scan, current compatibility record, current docs with help content shipped (§11) and guide links resolved (§12), clean install test, and update/rollback proof (§3 tests green on the candidate). Done when: each item names its proof.
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

## 7. Share Target Registration

Why this section exists: the share contract needs package identity, which only exists here. Split from D01 T01 §24 by phase-1 run 2: registration lives here, the receive path stays there.

**Fidelity:** new build, no baseline (OS integration, judged on its own contract).

**Job:** The user can share text from other apps into ours. Consumer: the OS share sheet, which lists us; the receive path (D01 T01 §24), which takes the text.

**Treatment:** The package declares `windows.shareTarget`; activation routes the shared text into §24's receive. Cheaper substitute that fails the checkpoint: registration that launches a blank window.

**Chrome:** No new surface; the share sheet is the surface.

**Needs:** Windows host (build/test)

- [ ] The package declares the share-target extension. Done when: the manifest names it.
- [ ] The app appears in the share sheet. Done when: driven on a packaged install.
- [ ] Shared text routes to D01 T01 §24's receive path. Done when: the activation is driven end to end.
- [ ] Commit: `"release: register the share target"`

**Test checkpoint:** declaration, sheet presence, and routed receive are all driven in the room. Cheaper substitute that fails: a target that eats shares silently.

## 8. Inno Setup Installer and Distribution

Why this section exists: MSIX plus Store plus WinGet (§§1-6) covers the managed path, but some machines refuse it (Store policy, no WinGet, offline media). A signed Inno Setup exe gives those users a direct-download install with the same identity, built from the same CI tag. Toolchain pin: Inno Setup 6.7.3, operator-provisioned 2026-09-18; CI installs this exact version, never latest. Additive by operator direction 2026-09-18: MSIX stays the primary artifact and §§1-7 stand unchanged; if Inno ever replaces MSIX instead, §§1/5/6 plus the D00 T01 §2 and D01 T01 §11 identity references need rework. WinGet stays §6's: this section distributes through the release page only. -> XREF: D07 T01 §1 (the pinned identity this installer reuses: exe, AppId, ProgId, URL scheme, associations).

- [ ] An Inno Setup script (`installer/ScratchPad.iss`) builds `ScratchPadSetup.exe` from the CI build output with the app id and version stamped from the §1 identity record. Done when: the script plus the version-stamping step exist and a local Windows build produces the exe.
- [ ] The setup installs and uninstalls cleanly reusing the §1 identity: exe name, AppId, ProgId, URL scheme, and the D01 association verbs register on install and remove on uninstall. Done when: install plus uninstall are driven on a clean VM with association checks green.
- [ ] The setup exe is signed under the §1 certificate story with SHA-256 checksums published beside the artifact. Done when: the signature verifies on a stock machine and the checksum file ships with the release.
- [ ] CI builds the setup exe on the release tag and attaches it to the release page draft. Done when: the artifact downloads from the run and the draft carries it with checksums.
- [ ] First launch after setup install opens to the expected state with settings working and no errors. Done when: the launch test passes on the clean VM.
- [ ] Commit: `"release: ship the Inno Setup installer"`

**Test checkpoint:** Signed setup exe artifact in CI with §1 identity; clean-VM install, launch, and uninstall green; checksums published on the release draft. Cheaper substitute that fails: an unsigned exe on a release page.

## 9. Dynamic Version Scheme

Why this section exists: the only version source is the release tag. A tag-derived versioner computes SemVer from the tag plus height at build time, so releasing is tagging and no hand-edited version string can drift between the assembly, the About panel, the installer, and the feed. The stub `0.0.0` default (D00 T01 §2) retires to tagless local builds only. Operator-confirmed 2026-09-19: the scheme stays as filed.

- [ ] `docs/release-versioning.md` records the scheme: tag shape `vMAJOR.MINOR.PATCH`, SemVer with height plus sha past the tag, Win32 four-part file version with the CI run number as fourth part, channel rule (tag on main reads stable, everything else reads preview), tagless local builds read `0.0.0-preview+<sha>`. Done when: every rule above is stated with an example string each.
- [ ] A tag-derived versioner (MinVer, version pinned with lockfile) wires into `Directory.Build.props` so assembly, file, and informational versions stamp from the tag at build time. Done when: a build under a synthetic tag reports that tag from the binary and an untagged build reports the preview shape.
- [ ] `NotepadCore.Version` keeps seeding from the assembly stamp with no second source; no hardcoded version string remains under `src/` or `tests/`. Done when: the blanked-stamp probe still fails loud and the version-literal grep is quoted clean.
- [ ] A version-agreement test binds every stamped surface that exists now (assembly, file version, `NotepadCore.Version`) and names the late binders (§1 installer identity, §3 feed version) as skipped-until-landed with owner refs. Done when: `dotnet test --filter Version` is green and a mismatched-stamp probe is red.
- [ ] Commit: `"release: derive versions from tags"`

**Test checkpoint:** A synthetic-tag build reports the tag end to end (binary, core, agreement test); an untagged build reports the preview shape; no literal version ships. Cheaper substitute that fails: a version constant edited per release.

## 10. Product Identity Registry

Why this section exists: the product's legal and brand strings live in exactly one machine-readable place. The About panel (D01 T02 §17), the installers (§§1, 8), and the headers below all render from it, so identity can never disagree with itself. The app name is final (D01 T02 §13 shipped); this section owns everything around it. Operator-confirmed 2026-09-19: GPL-3.0-or-later (SPDX `GPL-3.0-or-later`).

- [ ] `resources/brand/identity.json` carries the product name, publisher `Rizonetech (Pty) Ltd`, copyright `© [build-year] Rizonetech (Pty) Ltd. All rights reserved` with the build-year substitution rule, and the operator-confirmed link slots: project home `https://rizonesoft.com`, corporate `https://rizonetech.com`, GitHub `https://github.com/rizonesoft/`, X `https://x.com/DerickPayneDev`, repository `https://github.com/rizonesoft/ScratchPad`, support (confirmed at build time). Done when: the file parses, every slot holds an `https://` URL, and a malformed-URL probe is red.
- [ ] The brand assets verify: `resources/rizonesoft-logo-dark.svg`, `resources/rizonesoft-logo-light.svg`, and their PNG mates exist with the registry recording the About cap of 48px tall (auto width, about 172px at the wordmark ratio); the social icons `resources/brand/github-mark.svg` and `resources/brand/x-logo.svg` are sourced from the official brand kits or Simple Icons with their license noted in the registry. Done when: a presence test names every file and the cap, and a missing-asset probe is red.
- [ ] `docs/product-identity.md` records the rules the JSON cannot carry: the 48px About cap with its reason (small lockup, operator direction 2026-09-19), the About row list for D01 T02 §17 (copyright, publisher, project plus corporate plus social links with brand icons, logo placement; the version row stays as D01 T02 §3 shipped it), and the source-header template (copyright line, SPDX `GPL-3.0-or-later`, and the standard "version 3 or any later version" grant line). Done when: each rule names its consumer section.
- [ ] Every code file under `src/` and `tests/` carries the header and a check fails headerless files. Done when: the tree is quoted clean after the mechanical pass and a headerless-file probe is red.
- [ ] Commit: `"release: add the product identity registry"`

**Test checkpoint:** Registry parses with confirmed URLs and verified assets; header check green with a red probe; the About row list is complete for D01 T02 §17. Cheaper substitute that fails: strings pasted per surface.

## 11. Help Content Pipeline

Why this section exists: the per-section `docs/user-guide/` pages are the help source, and this section turns them into shippable offline help. Operator direction 2026-09-19 picked browser-based local HTML over an in-app viewer (parity-pure: no new chrome) with F1 context help (D01 T01 §33) opening it. Web publishing is deferred to §12; in-app only for v1.

- [ ] A build step renders `docs/user-guide/*.md` to HTML under the package content dir with a pinned Markdown renderer. Done when: every guide page renders with stable anchors and a missing-page probe is red.
- [ ] A surface map binds surface ids to page plus anchor with a help-home default for unmapped surfaces. Done when: the map validates against the rendered TOC and an unknown-surface probe reads the default.
- [ ] A link check verifies internal links plus anchors and the well-formedness of §10 registry URLs. Done when: the check is green and a broken-link plus broken-anchor probe pair is red.
- [ ] Read base resolves from config with the local package path as default, so §12 flips to web without regenerating content. Done when: a base-override probe renders web URLs from identical content.
- [ ] Commit: `"release: build help content from the guide"`

**Test checkpoint:** Every guide page renders with a validated map and checked links; the base override proves the §12 switch needs no content change. Cheaper substitute that fails: HTML hand-written beside the guide.

## 12. Guide Web Publishing and Link Switch

Why this section exists: this is the remembered afterwards. Operator direction 2026-09-19 defers web publishing past v1; when it lands, F1 and the help links open the published pages instead of the local HTML. The §5 dependency parks this row until the first signed release ships.

- [ ] The guide HTML publishes to the rizonesoft.com docs path by a mechanism decided at build (CI deploy or operator upload, operator-confirmed). Done when: published pages match the packaged HTML content with the web base.
- [ ] The read base flips to the web default with local fallback when offline. Done when: F1 opens web URLs and a forced-offline probe falls back to local.
- [ ] Commit: `"release: publish the guide and switch help links to web"`

**Test checkpoint:** Published pages match packaged content; F1 reads web online and local offline. Cheaper substitute that fails: web pages without the base flip, or the flip without fallback.

## Verification

- [ ] `dotnet test` green
- [ ] Checklist green with its record
- [ ] `python3 scripts/todo-graph.py validate` clean
