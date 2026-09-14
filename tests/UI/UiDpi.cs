using System.Runtime.InteropServices;

namespace UI;

// testhost.exe is DPI-unaware, which virtualizes every coordinate API differently;
// PerMonitorV2 for the calling thread makes rects and capture agree. Shared by
// UiCapture and the UI tests that read window geometry.
internal static class UiDpi
{
    static readonly nint PerMonitorV2 = new(-4);

    internal static nint Enter() => NativeMethods.SetThreadDpiAwarenessContext(PerMonitorV2);

    internal static void Exit(nint previous)
    {
        if (previous != nint.Zero)
        {
            _ = NativeMethods.SetThreadDpiAwarenessContext(previous);
        }
    }

    // Foreground rights cannot be assumed (background launches fail
    // SetForegroundWindow silently), so pixel reads pin the window topmost
    // instead. Same pixels, no occlusion.
    internal static void PinTopmost(FlaUI.Core.AutomationElements.AutomationElement window, bool topmost)
    {
        const uint flags = 0x0002 | 0x0001 | 0x0010;
        nint after = topmost ? new nint(-1) : new nint(-2);
        _ = NativeMethods.SetWindowPos(window.Properties.NativeWindowHandle.Value, after, 0, 0, 0, 0, flags);
    }

    static class NativeMethods
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint SetThreadDpiAwarenessContext(nint dpiContext);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);
    }
}
