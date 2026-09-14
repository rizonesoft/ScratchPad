using System.Drawing;
using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using Microsoft.Win32;

namespace UI;

// Deliberate duplication of the capture tool's flow: tests/UI cannot reference tools/,
// and the tool cannot reference tests/, so the DPI-aware capture routine lives in both.
internal static class UiCapture
{
    internal static Bitmap CaptureWindow(Tolerance tolerance)
    {
        // testhost.exe is DPI-unaware, which virtualizes every coordinate API differently;
        // PerMonitorV2 for this thread makes Move, Resize, rects, and capture agree.
        var previous = Dpi.Enter();
        try
        {
            return CaptureInner(tolerance);
        }
        finally
        {
            Dpi.Exit(previous);
        }
    }

    static Bitmap CaptureInner(Tolerance tolerance)
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        if (!File.Exists(appPath))
        {
            throw new InvalidOperationException($"stub missing at {appPath}");
        }

        using var app = Application.Launch(appPath);
        try
        {
            using var automation = new UIA3Automation();
            var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(15));
            if (window is null)
            {
                throw new InvalidOperationException("stub showed no main window");
            }

            var scale = DisplayScale();
            if (!Place(window, 50, 50, (int)Math.Round(tolerance.CanonicalWidth * scale), (int)Math.Round(tolerance.CanonicalHeight * scale)))
            {
                throw new InvalidOperationException("stub window refused placement");
            }
            var raw = Path.Combine(Path.GetTempPath(), $"golden-fresh-{Guid.NewGuid():N}.png");
            PinTopmost(window, true);
            Thread.Sleep(250);
            window.CaptureToFile(raw);
            PinTopmost(window, false);
            window.Close();
            Bitmap canonical;
            using (var shot = new Bitmap(raw))
            {
                canonical = GoldenComparer.Canonicalize(shot, tolerance.CanonicalWidth, tolerance.CanonicalHeight);
            }

            File.Delete(raw);
            return canonical;
        }
        finally
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (!app.HasExited && DateTime.UtcNow < deadline)
            {
                Thread.Sleep(100);
            }

            if (!app.HasExited)
            {
                app.Kill();
            }
        }
    }

    // Primary-display scale without DPI-awareness dependence. Assumes the captured
    // window opens on the primary display; multi-monitor mixed-DPI is out of scope.
    static double DisplayScale()
    {
        const int fallback = 96;
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop\WindowMetrics");
        var dpi = key?.GetValue("AppliedDPI") as int? ?? fallback;
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    // Foreground rights cannot be assumed (background launches fail SetForegroundWindow
    // silently), so captures pin the window topmost instead. Same pixels, no occlusion.
    static void PinTopmost(Window window, bool topmost)
    {
        const uint flags = 0x0002 | 0x0001 | 0x0010;
        NativeMethods.Pin(window.Properties.NativeWindowHandle.Value, topmost ? new nint(-1) : new nint(-2), flags);
    }

    // SetWindowPos directly, verified with one retry: mirrors the capture tool exactly.
    static bool Place(Window window, int x, int y, int width, int height)
    {
        const uint flags = 0x0004 | 0x0010;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            NativeMethods.Move(window.Properties.NativeWindowHandle.Value, x, y, width, height, flags);
            Thread.Sleep(500);
            var rect = window.BoundingRectangle;
            if (Math.Abs(rect.Width - width) <= 2 && Math.Abs(rect.Height - height) <= 2)
            {
                return true;
            }
        }

        return false;
    }

    static class Dpi
    {
        static readonly nint PerMonitorV2 = new(-4);

        internal static nint Enter() => NativeMethods.SetThreadContext(PerMonitorV2);

        internal static void Exit(nint previous)
        {
            if (previous != nint.Zero)
            {
                _ = NativeMethods.SetThreadContext(previous);
            }
        }
    }

    static class NativeMethods
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

        internal static void Pin(nint hwnd, nint insertAfter, uint flags)
        {
            _ = SetWindowPos(hwnd, insertAfter, 0, 0, 0, 0, flags);
        }

        internal static void Move(nint hwnd, int x, int y, int width, int height, uint flags)
        {
            _ = SetWindowPos(hwnd, 0, x, y, width, height, flags);
        }

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern nint SetThreadDpiAwarenessContext(nint dpiContext);

        internal static nint SetThreadContext(nint context) => SetThreadDpiAwarenessContext(context);
    }
}
