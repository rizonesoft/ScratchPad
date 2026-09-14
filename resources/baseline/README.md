# Baseline Captures

Parity with Windows 11 Notepad is checkable only against captures. This store holds two kinds: `stock/` has reference screenshots of the real Notepad for human parity judgment (owned by D06 T01 §3), and `app/` has golden captures of our own surfaces that `tests/UI` compares against automatically. Every capture is canonical 800x600 logical pixels (physical size times the window DPI over 96, downscaled back), so goldens match across DPI settings. Captures assume dark app theme (CI sets it; check the capture machine matches) and must fit a 1024x768 runner screen. No capture lives outside this directory.

## Sources

Stock captures were taken from `Microsoft.WindowsNotepad` 11.2607.14.0 on Windows 11 25H2 at 150% DPI via `tools/CaptureBaseline` (FlaUI 5.0.0, `System.Drawing.Common` 10.0.12 for canonicalization): `notepad-main` (fresh window, one empty Untitled tab), `notepad-tabs` (same window with a second empty tab), `notepad-menu-file` (File menu open), `notepad-settings` (settings page, showing the source version). Window state is one empty window with no saved content; the tool opens its own window and never touches other Notepad windows. App goldens were taken from our stub the same way; `stub-window.png` shows the full window at canonical size.

## Capture procedure

Run `dotnet run --project tools/CaptureBaseline -- notepad resources/baseline/stock` for stock surfaces or `dotnet run --project tools/CaptureBaseline -- stub <path-to-IntelligentNotepad.exe> resources/baseline/app` for app goldens (Windows only, pinned SDK on the path). Rename stock captures with their source versions (`-<app>-n<notepad-version>-win<windows-version>.png`) and eyeball every capture before committing: the window must be foreground, unoccluded, and at canonical size. Custom sizes pass `--width`/`--height`, but the committed canonical size in `tolerance.json` is what the comparer uses, so keep them in sync.

## Tolerance policy

`tolerance.json` is the committed comparison contract: canonical dimensions, the relative crop that drops the version-carrying title bar (top 8%) and rounded-corner edges (2% sides, 3% bottom), the per-pixel channel delta that counts as different, and the maximum different-pixel fraction that still passes. Numbers were set by measurement on real CI pixels: at delta 96 the cross-DPI rasterization noise is 128 pixels (0.031%) while a 10px shift is 736 pixels (0.180%), so the 0.1% threshold clears noise by 3x and still catches the shift at nearly 2x margin. The delta sits between anti-aliasing fringe physics and content-change physics; low-contrast content below delta 96 needs its own policy. Change these numbers only with new measurements quoted in the committing review.

## Refresh procedure

After an intentional visual change: re-run the capture procedure, inspect the golden diff pixel by pixel (it must show exactly the intended change and nothing else), run `dotnet test tests/UI` to confirm the suite passes on the refreshed golden, then commit the golden with a message naming the change. Refreshing to make a failing suite pass without understanding the diff is forbidden: a surprising diff is a regression until proven otherwise. This procedure was first used for real to re-canonicalize the goldens at a new size; see the T02 §3 findings.
