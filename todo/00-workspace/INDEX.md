# 00 Workspace

> **Phase 0**

Repo, .NET toolchain, CI, this TODO system, and the test backbone every later domain builds on. Nothing here ships to users; everything later depends on it being boring and green.

## TODOs

| TODO | Title | Status |
| ---- | ----- | :----: |
| [TODO-02](./TODO-02-test-backbone.md) | Test Backbone | active |
| [TODO-03](./TODO-03-readme-and-github.md) | README and GitHub Repo Face | draft |
| [TODO-04](./TODO-04-panel-rule-follow-ups.md) | Panel Rule Follow-Ups | active |

## Completed

| TODO | Title | Completed |
| ---- | ----- | :-------: |
| [TODO-01](./TODO-01-repo-and-toolchain.md) | Repo and Toolchain | 2026-09-14 |

## In scope

- Repo layout, pinned .NET SDK, one-command build
- CI on Linux and Windows runners with warning and analysis gates
- This TODO system's own CI checks (`validate`, `plan --check`)
- Unit-test project, UI automation driver, golden captures, ACP loopback fixture

## Out of scope

- The app itself (01, 02, 05)
- Protocol and agent work (03, 04)
- Test strategy content, which is 06-quality's; this domain builds the backbone it runs on
- Packaging and release (07-release)

---

Format spec: [../README.md](../README.md) · Root index: [../TODO-00-INDEX.md](../TODO-00-INDEX.md)
