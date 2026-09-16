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
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        if (!File.Exists(appPath))
        {
            throw new InvalidOperationException($"app missing at {appPath}");
        }

        // Captures must be machine-independent: no first-run dialog, dark Mica
        // even on light-system machines. First-run has its own driven test.
        new Notepad.Core.ShellSettings { WhatsNewSeen = true, Theme = "dark" }.Save();

        using var app = Application.Launch(appPath);
        try
        {
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
            if (window is null)
            {
                throw new InvalidOperationException("app showed no main window");
            }

            var scale = DisplayScale();
            if (!Place(window, 50, 50, (int)Math.Round(tolerance.CanonicalWidth * scale), (int)Math.Round(tolerance.CanonicalHeight * scale)))
            {
                throw new InvalidOperationException("app window refused placement");
            }

            prepare?.Invoke(window);
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

    static void PinTopmost(Window window, bool topmost) => UiDpi.PinTopmost(window, topmost);

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

    static class NativeMethods
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

        internal static void Move(nint hwnd, int x, int y, int width, int height, uint flags)
        {
            _ = SetWindowPos(hwnd, 0, x, y, width, height, flags);
        }
    }
}
