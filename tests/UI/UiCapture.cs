using System.Drawing;
using System.Drawing.Imaging;
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
        var previous = UiDpi.Enter();
        try
        {
            return CaptureInner(tolerance, PrepareMain);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    static void PrepareMain(Window window)
    {
        // The menu bar composes after placement: capturing immediately wins
        // a race and freezes a label-less frame (the Sept 15 golden caught
        // exactly that). Wait for the settled menus before the shutter.
        var deadline = DateTime.UtcNow.AddSeconds(10);
        AutomationElement? edit = null;
        while (edit is null && DateTime.UtcNow < deadline)
        {
            edit = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEdit"));
            if (edit is null)
            {
                Thread.Sleep(250);
            }
        }

        if (edit is null)
        {
            throw new InvalidOperationException("menu bar never composed");
        }

        Thread.Sleep(500);
    }

    internal static Bitmap CaptureSettings(Tolerance tolerance)
    {
        var previous = UiDpi.Enter();
        try
        {
            return CaptureInner(tolerance, PrepareSettings);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    static void PrepareSettings(Window window)
    {
        AutomationElement? gear = null;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (gear is null && DateTime.UtcNow < deadline)
        {
            gear = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsButton"));
            if (gear is null)
            {
                Thread.Sleep(250);
            }
        }

        if (gear is null)
        {
            throw new InvalidOperationException("settings gear missing");
        }

        if (gear.Patterns.Invoke.IsSupported)
        {
            gear.Patterns.Invoke.Pattern.Invoke();
        }
        else
        {
            gear.Click();
        }

        deadline = DateTime.UtcNow.AddSeconds(10);
        AutomationElement? heading = null;
        while (heading is null && DateTime.UtcNow < deadline)
        {
            heading = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsHeading"));
            if (heading is null)
            {
                Thread.Sleep(250);
            }
        }

        if (heading is null)
        {
            throw new InvalidOperationException("settings page never opened");
        }

        Thread.Sleep(500);
    }

    static Bitmap CaptureInner(Tolerance tolerance, Action<Window>? prepare = null)
    {
        string appPath = UiLaunch.AppExePath();

        // Captures must be machine-independent: no first-run dialog, dark Mica
        // even on light-system machines. First-run has its own driven test.
        new Notepad.Core.ShellSettings { WhatsNewSeen = true, Theme = "dark" }.Save();

        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchAppWithExe(appPath, string.Empty);
        try
        {
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
            if (window is null)
            {
                throw new InvalidOperationException("app showed no main window");
            }

            UiForeground.Background(window, fgBefore);

            var scale = DisplayScale();
            // Derived off-screen origins (D00 T02 §18 R2-F2 family):
            // the fixed 10000 point could sit on a sufficiently
            // large display, so golden captures derive past the
            // virtual screen like every other background window.
            int firstW = (int)Math.Round(tolerance.CanonicalWidth * scale);
            int firstH = (int)Math.Round(tolerance.CanonicalHeight * scale);
            (int firstX, int firstY) = UiLaunch.DeriveOffScreenOrigin(UiLaunch.ReadVirtualScreen(), firstW, firstH);
            if (!Place(window, firstX, firstY, firstW, firstH))
            {
                throw new InvalidOperationException("app window refused placement");
            }

            // The registry guess names the primary display, but backgrounded
            // windows live off-screen at 100%: sizing by the primary 150% lays
            // out 1350 effective px and the canonical downscale shrinks content
            // to 0.667x (measured Run A 2026-09-19: 690px fresh/shell,
            // 5905px settings). The window's own DPI context wins, so the
            // size is re-placed when the guess is wrong. Single-monitor boxes
            // read the primary DPI here and skip the second placement.
            var actual = WindowDpi(window) / 96.0;
            if (Math.Abs(actual - scale) > 0.001)
            {
                int secondW = (int)Math.Round(tolerance.CanonicalWidth * actual);
                int secondH = (int)Math.Round(tolerance.CanonicalHeight * actual);
                (int secondX, int secondY) = UiLaunch.DeriveOffScreenOrigin(UiLaunch.ReadVirtualScreen(), secondW, secondH);
                if (!Place(window, secondX, secondY, secondW, secondH))
                {
                    throw new InvalidOperationException("app window refused DPI-corrected placement");
                }

                scale = actual;
            }

            prepare?.Invoke(window);
            using var shot = PrintCapture(window);
            window.Close();
            // Scale and raw size pin the capture environment in the test
            // log (D00 T02 §6): cross-DPI rasterization noise is diagnosed
            // from these two numbers, not from guesses.
            Console.WriteLine($"capture: scale={scale} raw={shot.Width}x{shot.Height}");
            return GoldenComparer.Canonicalize(shot, tolerance.CanonicalWidth, tolerance.CanonicalHeight);
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

    // First-guess scale from the primary display without DPI-awareness
    // dependence. CaptureInner corrects it from the window's own DPI
    // context after placement; mixed-DPI capture is in scope since D00
    // T02 §8 (backgrounded windows render off-screen at 100%).
    static double DisplayScale()
    {
        const int fallback = 96;
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop\WindowMetrics");
        var dpi = key?.GetValue("AppliedDPI") as int? ?? fallback;
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    // The DPI context Windows assigned the window at its final position
    // (nearest monitor for off-screen windows), so the size math follows
    // the render context instead of the primary registry key. Falls back
    // to the guess on API failure (0): mis-sized beats unplaced.
    static uint WindowDpi(Window window)
    {
        var dpi = NativeMethods.GetDpiForWindow(window.Properties.NativeWindowHandle.Value);
        return dpi == 0 ? (uint)Math.Round(DisplayScale() * 96) : dpi;
    }

    // DWM-surface capture that works off-screen (spiked D00 T02 §8:
    // off-screen and on-screen PrintWindow renders are pixel-identical
    // at 28.3 mean red). DPI-aware internally: testhost is unaware, so
    // raw bounds would virtualize and clip the bitmap.
    internal static Bitmap PrintCapture(Window window)
    {
        var previous = UiDpi.Enter();
        try
        {
            var rect = window.BoundingRectangle;
            var capture = new Bitmap((int)rect.Width, (int)rect.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(capture))
            {
                nint hdc = g.GetHdc();
                try
                {
                    const uint renderFullContent = 0x00000002;
                    _ = NativePrint.PrintWindow(
                        window.Properties.NativeWindowHandle.Value, hdc, renderFullContent);
                }
                finally
                {
                    g.ReleaseHdc(hdc);
                }
            }

            return capture;
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    static class NativePrint
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PrintWindow(nint hWnd, nint hdc, uint flags);
    }

    static void PinTopmost(Window window, bool topmost) => UiDpi.PinTopmost(window, topmost);

    // SetWindowPos directly, verified with one retry: mirrors the capture tool exactly.
    // Shows no-activate before verifying: minimized-start windows (background
    // runs) report the minimized rect until shown, so a pre-show verify fails.
    static bool Place(Window window, int x, int y, int width, int height)
    {
        const uint flags = 0x0004 | 0x0010;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            NativeMethods.Move(window.Properties.NativeWindowHandle.Value, x, y, width, height, flags);
            UiForeground.Show(window);
            Thread.Sleep(500);
            var rect = window.BoundingRectangle;
            if (Math.Abs(rect.Width - width) <= 2 && Math.Abs(rect.Height - height) <= 2)
            {
                return true;
            }
        }

        return false;
    }

    static class NativeMethods
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

        internal static void Move(nint hwnd, int x, int y, int width, int height, uint flags)
        {
            _ = SetWindowPos(hwnd, 0, x, y, width, height, flags);
        }

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetDpiForWindow(nint hWnd);
    }
}
