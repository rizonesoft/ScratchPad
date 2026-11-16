# Design contract

Operator decision 2026-11-17. This page is the one place that says what ScratchPad should look like and how much visual checking the work owes. It wins over any older "exact parity" wording in a TODO section, a skill or a review prompt.

## What ScratchPad is

ScratchPad is a Windows 11 Notepad replacement with Claude Code and Codex inside. It keeps Notepad's behavior: the same menus, shortcuts, tabs, file handling, encodings, settings and status bar, so a Notepad user is at home at once. It is its own product with its own identity. It is not a pixel copy of Notepad and must never be mistaken for it on a taskbar.

## The design is accepted

The current look is approved as it stands: the shell, the tab strip, the menus, the status bar, the dialogs and the settings page, in dark and light theme. Work no longer chases pixel differences from Notepad.

- **Behavior follows Notepad.** A menu item, shortcut, dialog flow, default or file-handling rule matches Windows 11 Notepad unless a recorded decision says otherwise. The stock captures under `resources/baseline/stock/` and the notes in `docs/parity-review.md` are the reference for behavior and layout questions. They are not pixel targets.
- **New surfaces follow the app.** A new surface uses the shared styles its section names in `**Chrome:**`, WinUI 3 and Fluent defaults, the system accent, and works in both themes and at 100 to 200 percent scale. The AI surfaces add their own contract in `docs/ai-panel-contract.md` when `D05 T01 §1` writes it.
- **A `**Fidelity:**` line that names a stock capture** means "behave and lay out like this surface". It does not ask for a pixel match or a side-by-side verdict.

## Identity

The identity is direction A, "Scribble": the blue spiral pad, a hand-drawn scratch stroke in place of ruled lines, and an amber spark where the stroke ends, for the agents inside.

| Asset | File |
| ----- | ---- |
| App icon, 16 to 256 px | `resources/notepad.ico` (the path the project, the window code and `AppIconTests` name) |
| Title bar glyph | `resources/titlebar-icon-16.png`, `resources/titlebar-icon-32.png` |
| Icon masters | `resources/brand/scratchpad-icon.svg` (48 px and up), `resources/brand/scratchpad-icon-small.svg` (16 to 32 px) |
| Wordmark | `resources/brand/scratchpad-wordmark-light.svg` and `-dark.svg`, with PNG renders |
| README banner, 1280 by 320 | `resources/brand/readme-banner.svg` and `.png` |
| GitHub social preview, 1280 by 640 | `resources/brand/social-preview.svg` and `.png` |

Colors: pad blue `#2da4de` (the Rizonesoft blue) over `#74d3f8`, pad edge `#1576aa`, ink navy `#0f3247`, spark amber `#ffb629`. The wordmark is Nunito Black with its text outlined, so no font is needed to render it; "Scratch" takes the ink color and "Pad" the pad blue.

Rules: the icon keeps dark rings, the scratch stroke and the spark, so its outline differs from Windows Notepad's at every size. Never ship Microsoft's Notepad icon or a trace of it. After editing a master, run `python tools/build-brand-assets.py` (needs `resvg_py` and `pillow`) and commit the rasters with it.

## Visual checks

Visual tests stay, but few, quiet and aimed at our own look.

- **Three surface goldens** guard against an unintended change: the main window (`MainWindowTests.ShellMatchesGolden`, `main-window.png`), the tab strip (`TabStripGoldenTests`, `tab-strip.png`) and the settings page (`SettingsPageTests`, `settings-page.png`). They are focus-free and compare the app with its own approved capture under `resources/baseline/app/`.
- **When they run:** when a phase, a TODO file or a release closes (they are part of the focus-free full suite), and in the gate of a section that changes one of those three surfaces. Other section gates do not run them.
- **A section that changes something the user sees** saves one focus-free capture of it and looks at it for defects: clipping, misalignment, a wrong theme color, a missing control. It does not compare with stock Notepad, and it records no verdict in the commit.
- **A new golden** is added only for a new major surface, or when the operator asks. Refreshing one follows `resources/baseline/README.md`.
- **Still checked in every run that touches them:** the comparer's own tests (`GoldenComparisonTests`), the inventory (`GoldenInventoryTests`) and the icon tests (`AppIconTests`, `TitleBarIconTests`).

## What this replaced

Until 2026-11-17 the rule was exact parity: 14 golden tests over 12 goldens ran in every section gate, and every visible change needed a capture, a by-eye comparison beside stock Notepad and a verdict in the commit. The ten `parity-*` goldens and `ParityGoldenTests` were removed with this decision; `docs/parity-review.md` stays as the history of that review. Reversing the decision costs re-capturing those goldens and restoring the gate step.
