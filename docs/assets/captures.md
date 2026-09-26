# Screenshot provenance

Every image under `docs/assets/` is a real capture of the shipped app, never a mockup (D00 T03 §1). Each row names what a second operator needs to reproduce it.

## README hero (light and dark)

| File | Size (px) | SHA-256 (first 16) | Theme |
| --- | --- | --- | --- |
| `readme-hero.png` | 1382 x 851 | 8e4d7affc3fbd196 | light (the README's default hero, a copy of the light shot) |
| `readme-hero-light.png` | 1382 x 851 | 8e4d7affc3fbd196 | light |
| `readme-hero-dark.png` | 1382 x 851 | d638fd80cac9e789 | dark |

- Captured: 2026-09-26 18:57 +02:00 at app commit `444aa412cd623bdc31f51c1f1639544af58fb3ca`; recaptured 19:03 +02:00 at `d47393c333a4ed23a01653f9b52afc293ee87627` (the capture script's exclusive-store guard) with byte-identical results, so the shots reproduce.
- Host: the operator's Windows 11 dev box (host key `fec14402`, OS 10.0.26200.0), interactive desktop session.
- App commit: `d47393c333a4ed23a01653f9b52afc293ee87627` (app sources unchanged since `444aa41`), built from a fresh clone at that commit (its `Bin/` empty before the build).
- Build configuration: Debug, repo-local SDK (`.tools/dotnet-win-x64`).
- Command: `powershell -ExecutionPolicy Bypass -File tools\capture-readme.ps1 -Commit d47393c333a4ed23a01653f9b52afc293ee87627` (it refuses while any ScratchPad instance runs, because it seeds the shared settings store).
- What the script does: builds the clone, seeds a two-tab session (`release-notes.md` active, `groceries.txt`) in a 1400 x 860 DIP window with word wrap and the status bar on, launches once per theme in background mode (`SCRATCHPAD_BACKGROUND=1`, off-screen, no foreground steal), captures with `PrintWindow` (full content) from a per-monitor DPI-aware thread, crops to the visible frame, and refuses a shot under 1280 px wide or with no luminance spread. The operator's settings and session files are backed up first and restored after (verified byte-identical for this capture).

## Agent panel

`readme-agent-panel-light.png` and `readme-agent-panel-dark.png` are owed by D00 T03 §5 once D05 T01 §3 renders the panel; nothing here stands in for them.
