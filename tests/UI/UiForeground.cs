using System.Diagnostics;
using System.Runtime.InteropServices;
using FlaUI.Core.AutomationElements;

namespace UI;

// Foreground capture/restore for uninterrupted runs (D00 T02 §8). The
// app self-activates at launch (WinUI overrides no-activate starts,
// spiked), so the default suite runs with SCRATCHPAD_BACKGROUND=1 (every
// window starts minimized, no flash, no steal) and Background moves each
// window off-screen and re-shows it no-activate before driving: UIA,
// menu Invoke, and ValuePattern all dispatch there (spiked), the
// operator's pixels and focus stay untouched, and PrintWindow still
// captures for goldens. Restore alone is the backstop for windows that
// must stay on-screen (golden captures).
internal static class UiForeground
{
    internal static nint Capture() => Native.GetForegroundWindow();

    internal static void Background(Window? window, nint before)
    {
        PlaceOffscreen(window);
        Restore(before);
    }

    // Moves a window off-screen and shows it no-activate: UIA, menu
    // Invoke, and ValuePattern all dispatch there (spiked), with no
    // pixels and no foreground steal. Second windows (minimized at
    // birth under SCRATCHPAD_BACKGROUND) need this before driving.
    internal static void PlaceOffscreen(Window? window)
    {
        if (window is null)
        {
            return;
        }

        nint hwnd = window.Properties.NativeWindowHandle.Value;
        Native.SetWindowPos(hwnd, nint.Zero, 10000, 10000, 900, 650, 0x0010);
        Show(window);
    }

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
