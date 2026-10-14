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

    // Any state a feature's test can drive: setup seeds the launch
    // (settings, a session to restore, launch arguments), prepare runs on
    // the placed, backgrounded window before the shutter, like PrepareMain
    // above, and the shutter includes the app's own popups (menus, flyouts,
    // native dialogs) over the window, all focus-free.
    internal static Bitmap CaptureState(Tolerance tolerance, Action<Window> prepare, CaptureSetup? setup = null)
    {
        var previous = UiDpi.Enter();
        try
        {
            return CaptureInner(tolerance, prepare, setup, withPopups: true);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    static Bitmap CaptureInner(Tolerance tolerance, Action<Window>? prepare = null, CaptureSetup? setup = null, bool withPopups = false)
    {
        string appPath = UiLaunch.AppExePath();

        // Captures must be machine-independent: no first-run dialog, dark Mica
        // even on light-system machines. First-run has its own driven test.
        // WhenStarts defaults to Continue, so a session another test left
        // behind would restore its tabs into the frame: start from none.
        (setup?.Settings ?? new Notepad.Core.ShellSettings { WhatsNewSeen = true, Theme = "dark" }).Save();
        Notepad.Core.SessionData.Delete();
        setup?.Session?.Save();

        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchAppWithExe(appPath, setup?.Args ?? string.Empty);
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
            (int firstX, int firstY) = Origin(firstW, firstH, withPopups);
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
                (int secondX, int secondY) = Origin(secondW, secondH, withPopups);
                if (!Place(window, secondX, secondY, secondW, secondH))
                {
                    throw new InvalidOperationException("app window refused DPI-corrected placement");
                }

                scale = actual;
            }

            prepare?.Invoke(window);
            using var shot = withPopups ? Settled(() => PrintCaptureWithPopups(window)) : PrintCapture(window);
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

    // WinUI pulls an off-screen window's popups back onto the nearest
    // monitor. Past the right edge that clamp crushes a menu against the
    // edge and flips its submenus left; past the left edge the menus land
    // flush with the monitor's left edge and their submenus still open to
    // the right, so one shift (PrintCaptureWithPopups) restores the layout.
    static (int X, int Y) Origin(int width, int height, bool withPopups)
    {
        var screen = UiLaunch.ReadVirtualScreen();
        return withPopups ? (screen.X - width - 64, screen.Y) : UiLaunch.DeriveOffScreenOrigin(screen, width, height);
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

    // The main window plus every visible top-level window the app process
    // owns over it: WinUI menus and flyouts are separate popup HWNDs
    // (Microsoft.UI.Content.PopupWindowSiteBridge) and native dialogs are
    // #32770 windows, so a one-HWND PrintWindow misses both. Each is
    // printed off-screen like the main window and drawn at its offset,
    // bottom-most first.
    internal static Bitmap PrintCaptureWithPopups(Window window)
    {
        var previous = UiDpi.Enter();
        try
        {
            var main = window.BoundingRectangle;
            var canvas = PrintCapture(window);
            try
            {
                nint mainHwnd = window.Properties.NativeWindowHandle.Value;
                _ = NativePrint.GetWindowThreadProcessId(mainHwnd, out uint pid);
                var popups = new List<(nint Hwnd, NativePrint.Rect Rect)>();
                _ = NativePrint.EnumWindows(
                    (hwnd, _) =>
                    {
                        if (hwnd != mainHwnd
                            && NativePrint.IsWindowVisible(hwnd)
                            && NativePrint.GetWindowThreadProcessId(hwnd, out uint owner) != 0
                            && owner == pid
                            && NativePrint.GetWindowRect(hwnd, out var r)
                            && r.Right > r.Left && r.Bottom > r.Top
                            && (IsMenuPopup(hwnd) || (r.Right > main.Left && r.Left < main.Right && r.Bottom > main.Top && r.Top < main.Bottom)))
                        {
                            popups.Add((hwnd, r));
                        }

                        return true;
                    },
                    0);
                (int dx, int dy) = MenuShift(window, popups);
                using var g = Graphics.FromImage(canvas);
                for (int i = popups.Count - 1; i >= 0; i--)
                {
                    var (hwnd, r) = popups[i];
                    // 24bpp: PrintWindow leaves GDI alpha at 0, which an ARGB
                    // source would draw as fully transparent.
                    using var shot = new Bitmap(r.Right - r.Left, r.Bottom - r.Top, PixelFormat.Format24bppRgb);
                    using (var pg = Graphics.FromImage(shot))
                    {
                        nint hdc = pg.GetHdc();
                        try
                        {
                            const uint renderFullContent = 0x00000002;
                            _ = NativePrint.PrintWindow(hwnd, hdc, renderFullContent);
                        }
                        finally
                        {
                            pg.ReleaseHdc(hdc);
                        }
                    }

                    // A menu popup's window carries a transparent shadow margin
                    // that prints black: keep only the menu itself, and drop the
                    // pure-black corners its rounded border leaves in that rect.
                    var crop = new Rectangle(0, 0, shot.Width, shot.Height);
                    int x = r.Left - main.Left;
                    int y = r.Top - main.Top;
                    if (IsMenuPopup(hwnd))
                    {
                        var menu = window.Automation.FromHandle(hwnd).FindFirstDescendant(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.Menu));
                        if (menu is not null)
                        {
                            // A menu not laid out yet reports an empty rect:
                            // keep the whole popup rather than crop to nothing.
                            var b = menu.BoundingRectangle;
                            var inner = Rectangle.Intersect(crop, new Rectangle(b.Left - r.Left, b.Top - r.Top, b.Width, b.Height));
                            if (inner.Width > 0 && inner.Height > 0)
                            {
                                crop = inner;
                            }
                        }

                        x += dx;
                        y += dy;
                    }

                    using var piece = shot.Clone(crop, PixelFormat.Format32bppArgb);
                    if (IsMenuPopup(hwnd))
                    {
                        // Only menu popups print a black shadow margin; a native
                        // dialog's black text must stay opaque.
                        piece.MakeTransparent(Color.Black);
                    }
                    g.DrawImage(piece, x + crop.X, y + crop.Y);
                }

                return canvas;
            }
            catch
            {
                canvas.Dispose();
                throw;
            }
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // Flyouts and dialogs animate in (a menu slides about 12 px), so a
    // fixed sleep can freeze a mid-animation frame and the golden then
    // flakes: re-shoot until two frames 250 ms apart agree to within a few
    // pixels (a caret or focus visual may still blink), at most 12 tries.
    const int SettleTries = 12;

    static Bitmap Settled(Func<Bitmap> shoot)
    {
        var previous = shoot();
        try
        {
            for (int attempt = 0; attempt < SettleTries; attempt++)
            {
                Thread.Sleep(250);
                var next = shoot();
                int different = DifferentPixels(previous, next);
                previous.Dispose();
                previous = next;
                if (different <= 16)
                {
                    return previous;
                }
            }
        }
        catch
        {
            previous.Dispose();
            throw;
        }

        Console.WriteLine($"capture: never settled within {SettleTries} frames; the golden comparison judges the last one");
        return previous;
    }

    internal static int DifferentPixels(Bitmap a, Bitmap b)
    {
        ArgumentNullException.ThrowIfNull(a);
        ArgumentNullException.ThrowIfNull(b);
        if (a.Width != b.Width || a.Height != b.Height)
        {
            return int.MaxValue;
        }

        var rect = new Rectangle(0, 0, a.Width, a.Height);
        var da = a.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var db = b.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var pa = new int[a.Width * a.Height];
            var pb = new int[pa.Length];
            for (int y = 0; y < a.Height; y++)
            {
                Marshal.Copy(da.Scan0 + (y * da.Stride), pa, y * a.Width, a.Width);
                Marshal.Copy(db.Scan0 + (y * db.Stride), pb, y * a.Width, a.Width);
            }

            int different = 0;
            for (int i = 0; i < pa.Length; i++)
            {
                if ((pa[i] & 0xFFFFFF) != (pb[i] & 0xFFFFFF))
                {
                    different++;
                }
            }

            return different;
        }
        finally
        {
            a.UnlockBits(da);
            b.UnlockBits(db);
        }
    }

    static bool IsMenuPopup(nint hwnd)
    {
        var cls = new char[64];
        int length = NativePrint.GetClassName(hwnd, cls, cls.Length);
        return new string(cls, 0, Math.Max(0, length)) == "Microsoft.UI.Content.PopupWindowSiteBridge";
    }

    // Single-window captures only: it anchors on the first MenuRegion and
    // the leftmost menu popup of the whole process, so a second window or a
    // context menu left of the menu bar would pick the wrong anchor.
    // The shift that puts the open top-level menu flyout back under its
    // menu-bar item: the flyout's menu left-aligns with the expanded item
    // and starts at its bottom edge. The clamp can move popups on both
    // axes (a monitor lower than the virtual screen's top, measured
    // 2026-10-14). The top-level flyout is the leftmost menu popup
    // (submenus open to its right). No expanded item, or no menu in the
    // popup, means no shift.
    static (int Dx, int Dy) MenuShift(Window window, List<(nint Hwnd, NativePrint.Rect Rect)> popups)
    {
        var anchor = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuRegion"))?
            .FindAllChildren()
            .FirstOrDefault(m => m.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState.ValueOrDefault == FlaUI.Core.Definitions.ExpandCollapseState.Expanded);
        var top = popups.Where(p => IsMenuPopup(p.Hwnd)).OrderBy(p => p.Rect.Left).FirstOrDefault();
        if (anchor is null || top.Hwnd == 0)
        {
            return (0, 0);
        }

        var menu = window.Automation.FromHandle(top.Hwnd).FindFirstDescendant(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.Menu));
        return menu is null
            ? (0, 0)
            : (anchor.BoundingRectangle.Left - menu.BoundingRectangle.Left, anchor.BoundingRectangle.Bottom - menu.BoundingRectangle.Top);
    }

    static class NativePrint
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetClassName(nint hWnd, [Out] char[] className, int maxCount);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PrintWindow(nint hWnd, nint hdc, uint flags);

        internal delegate bool EnumWindowsProc(nint hwnd, nint lParam);

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(nint hWnd);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(nint hWnd, out Rect rect);
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

// The launch a golden's state needs: settings to seed (include
// WhatsNewSeen = true, or the first-run dialog joins the frame), a session
// to restore, and launch arguments (a quoted file path opens it as a tab).
internal sealed record CaptureSetup(Notepad.Core.ShellSettings? Settings = null, Notepad.Core.SessionData? Session = null, string Args = "");
