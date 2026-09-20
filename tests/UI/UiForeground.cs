using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using FlaUI.Core.AutomationElements;

namespace UI;

// Foreground capture/restore for uninterrupted runs (D00 T02 §8). The
// app self-activates at launch (WinUI overrides no-activate starts,
// spiked), so the default suite runs with SCRATCHPAD_BACKGROUND=1 (every
// window starts minimized, no-activate, no flash, no steal) and
// Background moves each window to the secondary monitor (off-screen on
// single-monitor boxes) and re-shows it no-activate before driving:
// UIA, menu Invoke, and ValuePattern all dispatch there (spiked), no
// window is ever activated and none dwells on the primary (a millisecond
// birth transient at the cascade, below the census poll, is excluded by
// the seen-twice rule), and PrintWindow still captures for goldens.
internal static class UiForeground
{
    internal static nint Capture() => Native.GetForegroundWindow();

    internal static void Background(Window? window, nint before)
    {
        PlaceForBackground(window);
        Restore(before, OwnHwnd(window));
    }

    // InPlace: for tests whose premise is app-chosen placement (restored
    // geometry, cascade offsets): moving them to the secondary destroys
    // what they assert. Shows the window no-activate where the app put it
    // and restores the prior foreground; never moves, never activates, so
    // it stays focus-free on whichever monitor that is. Callers carry
    // [Trait("Category", "Primary")] and run in the placement run, whose
    // census proves they rested on the primary (D00 T02 §8 item 7 revision).
    internal static void InPlace(Window? window, nint before)
    {
        if (window is null)
        {
            return;
        }

        Show(window);
        Thread.Sleep(250);
        Restore(before, OwnHwnd(window));
    }

    static nint OwnHwnd(Window? window) =>
        window?.Properties.NativeWindowHandle.Value ?? nint.Zero;

    // Moves a window to the suite display and shows it no-activate: the
    // secondary monitor when one exists (visible, so layout and UIA
    // containers behave exactly like foreground runs, but never
    // activated, so the operator's focus stays untouched), off-screen
    // otherwise. UIA, menu Invoke, and ValuePattern all dispatch there
    // (spiked). Second windows (minimized at birth under
    // SCRATCHPAD_BACKGROUND) need this before driving: minimized windows
    // do not reliably realize containers for late-added tabs.
    internal static void PlaceForBackground(Window? window)
    {
        if (window is null)
        {
            return;
        }

        // Show first, then move: SetWindowPos on a minimized window is
        // silently ignored (spiked twice: hidden-minimized ignores moves
        // exactly like minimized, so no pre-show ordering avoids the
        // restore), while a visible window obeys. The restore paints at
        // the birth cascade (50,50 on the primary), so the move fires
        // immediately with no settle between: the flash lasts the move
        // latency (milliseconds), and the settle sleep runs after the
        // window is already on the suite display. A 250 ms sleep sat
        // between show and move before R2 and dwelled 61 visible flashes
        // on the primary per full run (census-caught); sub-poll
        // transients are what the seen-twice rule exists to exclude.
        // Stays as the safety net under D00 T02 §11: seeded first
        // windows birth off-screen and never reach the cascade, but
        // redirect-created windows and direct launches still do, so
        // show-then-move with sleep-after-move keeps covering them.
        // Thread awareness (UiDpi pattern): testhost is DPI-unaware, so
        // coordinates go through physical pixels explicitly.
        nint previous = UiDpi.Enter();
        try
        {
            Show(window);
            (int x, int y) = SuiteDisplayOrigin();
            nint hwnd = window.Properties.NativeWindowHandle.Value;
            if (!Native.SetWindowPos(hwnd, nint.Zero, x, y, 900, 650, 0x0010))
            {
                throw new InvalidOperationException($"UiForeground: SetWindowPos failed for {hwnd} (Win32 error {Marshal.GetLastWin32Error()})");
            }

            Thread.Sleep(250);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    internal sealed record SuiteDisplay(bool Primary, Rectangle Bounds, Rectangle WorkingArea);

    internal static (int X, int Y) PickSuiteOrigin(IEnumerable<SuiteDisplay> displays)
    {
        SuiteDisplay? second = displays.Where(d => !d.Primary).OrderByDescending(d => d.Bounds.Width * d.Bounds.Height).FirstOrDefault();
        if (second is null)
        {
            return (10000, 10000);
        }

        return (second.WorkingArea.X, second.WorkingArea.Y);
    }

    internal static (int X, int Y) SuiteDisplayOrigin() =>
        PickSuiteOrigin(Screen.AllScreens.Select(s => new SuiteDisplay(s.Primary, s.Bounds, s.WorkingArea)));

    // Shows without activating (minimized-start windows need this before
    // driving: menu Invoke does not dispatch while minimized). No settle
    // sleep here: callers sleep after the window reaches its final
    // position, so no dwell happens at the birth cascade (R2).
    internal static void Show(Window? window)
    {
        if (window is null)
        {
            return;
        }

        _ = Native.ShowWindow(window.Properties.NativeWindowHandle.Value, 4);
    }

    // Restores the pre-test foreground only when the suite itself holds
    // it: if the operator navigated elsewhere mid-test, yanking focus back
    // to the stale window would interrupt them (probed 2026-09-19: a
    // background SetForegroundWindow succeeds on this box, so the guard is
    // load-bearing, not theoretical). A third window holding the foreground
    // stays put so the census flags the real steal loud.
    internal static void Restore(nint before, nint own)
    {
        if (before == nint.Zero)
        {
            return;
        }

        nint current = Native.GetForegroundWindow();
        if (current == before || current != own)
        {
            return;
        }

        _ = Native.SetForegroundWindow(before);
        Thread.Sleep(250);
        if (Native.GetForegroundWindow() != before)
        {
            Debug.WriteLine($"UiForeground: restore refused for {before}");
        }
    }

    static class Native
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetForegroundWindow();

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(nint hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(nint hWnd, nint after, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindow(nint hWnd, int cmdShow);
    }
}
