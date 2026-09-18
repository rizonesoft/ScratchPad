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
// UIA, menu Invoke, and ValuePattern all dispatch there (spiked), the
// operator's primary screen and focus stay untouched, and PrintWindow
// still captures for goldens.
internal static class UiForeground
{
    internal static nint Capture() => Native.GetForegroundWindow();

    internal static void Background(Window? window, nint before)
    {
        PlaceForBackground(window);
        Restore(before);
    }

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

        (int x, int y) = SuiteDisplayOrigin();
        nint hwnd = window.Properties.NativeWindowHandle.Value;
        Native.SetWindowPos(hwnd, nint.Zero, x, y, 900, 650, 0x0010);
        Show(window);
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
    // driving: menu Invoke does not dispatch while minimized).
    internal static void Show(Window? window)
    {
        if (window is null)
        {
            return;
        }

        _ = Native.ShowWindow(window.Properties.NativeWindowHandle.Value, 4);
        Thread.Sleep(250);
    }

    internal static void Restore(nint hwnd)
    {
        if (hwnd == nint.Zero || Native.GetForegroundWindow() == hwnd)
        {
            return;
        }

        _ = Native.SetForegroundWindow(hwnd);
        Thread.Sleep(250);
        if (Native.GetForegroundWindow() != hwnd)
        {
            Debug.WriteLine($"UiForeground: restore refused for {hwnd}");
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

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(nint hWnd, nint after, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindow(nint hWnd, int cmdShow);
    }
}
