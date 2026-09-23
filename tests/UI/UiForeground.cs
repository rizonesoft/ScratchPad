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
// window is ever activated and none paints at the birth spot (placement
// lands before the show, D00 T02 §18), and PrintWindow still captures
// for goldens.
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

        // Placement before show (D00 T02 §18): SetWindowPos on a
        // minimized window is silently ignored (spiked twice), so the
        // old show-then-move restored at the birth spot and flashed
        // there for the move latency. The §8 census excused the
        // millisecond transient via the seen-twice rule, but the §18
        // event stream photographs it (probed 2026-09-23: 237x39 at
        // physical (0,2049) on first-window mains). SetWindowPlacement
        // moves the never-minimized window to the suite display
        // (placement, not a restore, so no slide) and the show lands
        // there; no frame paints at the birth spot. Size stays 900x650,
        // the show-then-move size.
        // Thread awareness (UiDpi pattern): testhost is DPI-unaware, so
        // coordinates go through physical pixels explicitly.
        nint previous = UiDpi.Enter();
        try
        {
            (int x, int y) = SuiteDisplayOrigin();
            nint hwnd = window.Properties.NativeWindowHandle.Value;
            var placement = new Native.WindowPlacement
            {
                Length = Marshal.SizeOf<Native.WindowPlacement>(),
                Flags = 0,
                ShowCmd = 4,
                NormalPosition = new Native.Rect { Left = x, Top = y, Right = x + PlacementWidth, Bottom = y + PlacementHeight },
            };
            if (!Native.SetWindowPlacement(hwnd, ref placement))
            {
                throw new InvalidOperationException($"UiForeground: SetWindowPlacement failed for {hwnd} (Win32 error {Marshal.GetLastWin32Error()})");
            }

            Show(window);
            Thread.Sleep(250);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    internal sealed record SuiteDisplay(bool Primary, Rectangle Bounds, Rectangle WorkingArea);

    // Placement size shared with Show (D00 T02 §18 R2-F2): the
    // single-monitor derivation needs the window rect to clear the
    // screen, and Show places exactly this size.
    internal const int PlacementWidth = 900;
    internal const int PlacementHeight = 650;

    internal static (int X, int Y) PickSuiteOrigin(IEnumerable<SuiteDisplay> displays)
    {
        List<SuiteDisplay> list = displays.ToList();
        SuiteDisplay? second = list.Where(d => !d.Primary).OrderByDescending(d => d.Bounds.Width * d.Bounds.Height).FirstOrDefault();
        if (second is null)
        {
            // Single monitor (D00 T02 §18 R2-F2): derive past the
            // primary's own edges instead of the fixed 10000 point,
            // which a sufficiently large display could contain.
            SuiteDisplay primary = list.First(d => d.Primary);
            var screen = new UiLaunch.ScreenBounds(primary.Bounds.X, primary.Bounds.Y, primary.Bounds.Width, primary.Bounds.Height);
            return UiLaunch.DeriveOffScreenOrigin(screen, PlacementWidth, PlacementHeight);
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

        [StructLayout(LayoutKind.Sequential)]
        internal struct Point
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct WindowPlacement
        {
            public int Length;
            public int Flags;
            public int ShowCmd;
            public Point MinPosition;
            public Point MaxPosition;
            public Rect NormalPosition;
        }

        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPlacement(nint hWnd, ref WindowPlacement placement);
    }
}
