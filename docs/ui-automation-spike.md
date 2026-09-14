# UI Automation Driver Spike

Both required contenders were driven against the stub on 2026-09-14 (throwaway rigs outside the repo, pinned SDK 10.0.401, stub `IntelligentNotepad.exe` Debug build). Every number below is measured, not quoted.

## FlaUI (UIA3, in-process)

Packages `FlaUI.Core` and `FlaUI.UIA3`, version 5.0.0 (latest, February 2025), restored from NuGet with no install step and no server process. Launch plus window attach took 506 ms with the full versioned title read back; finding the `Intelligent Notepad stub` TextBlock by Name took 35 ms; a window screenshot took 198 ms and 106 KB, verified by eye to show the real window; a coordinate click took 177 ms with no crash; Close exited cleanly. Out-of-process UIA3 traverses our unpackaged WinUI 3 content with no `E_UNEXPECTED` at any island boundary, so the traversal risk reported against other WinUI 3 apps does not apply to our binary.

## WinAppDriver (WebDriver server)

Server 1.2.1, the latest stable, released November 2020 (only a 2021 release candidate since); the project is abandoned. The per-machine MSI install requires admin rights and failed without them; the spike extracted `WinAppDriver.exe` from the MSI instead. The current Appium client (8.4.0) cannot create sessions against the 2020 server (`Bad capabilities` on W3C capability prefixes), so the drive used the 4.4.0-era client, whose tree carries NU1904 critical-severity warnings (`System.Drawing.Common` 4.5.1) that our gates would reject. With that client: session plus launch 3755 ms, find by Name 262 ms, screenshot 282 ms and 177 KB, click 329 ms, close clean. Everything works, roughly seven times slower than FlaUI at session start, behind a separately managed server process.

## Third contender

None spiked. The candidate was an in-process AutomationPeer self-test harness (the fallback other WinUI 3 repos use when out-of-process UIA cannot traverse their content); it was not needed because FlaUI traverses ours, and it would test the app from inside rather than driving the real binary like a user.

## Decision

FlaUI wins: maintained, in-process, no install or server, fastest on every measured operation, and proven against our binary. Reversal cost is one file: the FlaUI surface in `tests/UI/` is `Application.Launch`, `UIA3Automation`, `GetMainWindow`, `FindFirstDescendant`, `CaptureToFile`, and `Close`, so switching drivers rewrites the drive helper, while `ResolveAppPath` and the CI test step stay. Reversal would additionally require a server lifecycle in CI and a pinned legacy client, which is why it lost.

## tests/UI and UISmoke

`tests/UI/` targets `net10.0-windows10.0.19041.0`, so it builds only on Windows and stays out of `src/Notepad.Neutral.slnf`; the full solution runs it. `UISmoke.StubWindowLaunchesShowsTitleAndCloses` launches the stub, asserts the title starts with `Intelligent Notepad (stub `, closes, and fails loud if the process survives. The app path resolves at build time: a `ResolveAppPath` target queries the app project's `GetTargetPath` into `apppath.txt`, and the test swaps the returned `.dll` for the apphost `.exe` (asserted to exist), because `GetTargetPath` names the managed assembly, not the launchable app. A failed drive saves `uismoke-failure.png` to the temp directory and prints the path. The attach timeout is 15 seconds for CI slowness. Selector convention: AutomationId or Name only, never ControlType conditions, which are flaky on headless server CI runners.

## Gaps

The stub has no Invoke-pattern control yet, so click coverage is coordinate-level until D01 lands real menus and buttons; click-on-real-control is re-proven by the parity suites (D06 T01 §3), and D01 must set AutomationIds on interactive controls for the selector convention above. Screenshot comparison against goldens needs the capture store (T02 §3) plus a comparison procedure owned by the parity suites (D06 T01 §3). The selector convention itself belongs in the test strategy (D06 T01 §1). Flakes, if CI shows any, quarantine by procedure (T02 §5, D06 T01 §6), never by deletion.
