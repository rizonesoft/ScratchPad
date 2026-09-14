using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Microsoft.Win32;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

// Captures baseline surfaces for resources/baseline/. Usage:
//   CaptureBaseline notepad <outdir> [--width N --height N]
//     stock Windows 11 Notepad; safe alongside a running Notepad (captures only the window it opens)
//   CaptureBaseline stub <exe> <outdir> [--element NAME] [--width N --height N]
//     our app window, or one element by Name
// Sizes are logical pixels at 96 DPI; the tool scales by the window's real DPI and
// downscales the capture back to canonical size, so goldens match across DPI settings.
if (args.Length < 2)
{
    Console.WriteLine("usage: CaptureBaseline notepad <outdir> [--width N --height N]");
    Console.WriteLine("       CaptureBaseline stub <exe> <outdir> [--element NAME] [--width N --height N]");
    return 2;
}

var width = Flag(args, "--width", 800);
var height = Flag(args, "--height", 600);
var element = Value(args, "--element");

return args[0] switch
{
    "notepad" => CaptureNotepad(args[1], width, height),
    "stub" when args.Length >= 3 => CaptureStub(args[1], args[2], element, width, height),
    _ => 2,
};

static int Flag(string[] args, string name, int fallback)
{
    var raw = Value(args, name);
    return raw is null ? fallback : int.Parse(raw, CultureInfo.InvariantCulture);
}

static string? Value(string[] args, string name)
{
    var at = Array.IndexOf(args, name);
    return at >= 0 && at + 1 < args.Length ? args[at + 1] : null;
}

static int CaptureNotepad(string outdir, int width, int height)
{
    Directory.CreateDirectory(outdir);
    using var automation = new UIA3Automation();
    var before = NotepadWindows(automation);
    using (Process.Start("notepad.exe"))
    {
    }

    var hwnd = WaitForNewWindow(automation, before, TimeSpan.FromSeconds(15));
    if (hwnd == IntPtr.Zero)
    {
        Console.WriteLine("no new Notepad window appeared (the launch may have joined an existing window as a tab)");
        return 1;
    }

    var window = automation.FromHandle(hwnd).AsWindow();
    if (!Prepare(window, width, height))
    {
        return 1;
    }

    Shoot(window, Path.Combine(outdir, "notepad-main.png"), width, height);

    using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
    {
        Keyboard.Press(VirtualKeyShort.KEY_T);
    }

    Thread.Sleep(500);
    Shoot(window, Path.Combine(outdir, "notepad-tabs.png"), width, height);

    var file = Retry.WhileNull(() => window.FindFirstDescendant(cf => cf.ByName("File")), TimeSpan.FromSeconds(5)).Result;
    if (file is null)
    {
        Console.WriteLine("no File menu");
        return 1;
    }

    file.Click();
    Thread.Sleep(500);
    Shoot(window, Path.Combine(outdir, "notepad-menu-file.png"), width, height);
    Keyboard.Press(VirtualKeyShort.ESCAPE);
    Thread.Sleep(250);

    var settings = Retry.WhileNull(() => window.FindFirstDescendant(cf => cf.ByName("Settings")), TimeSpan.FromSeconds(5)).Result;
    if (settings is null)
    {
        Console.WriteLine("no Settings control");
        return 1;
    }

    settings.Click();
    Thread.Sleep(1000);
    Shoot(window, Path.Combine(outdir, "notepad-settings.png"), width, height);
    window.Close();
    Console.WriteLine("captured main, tabs, menu-file, settings");
    return 0;
}

static HashSet<IntPtr> NotepadWindows(UIA3Automation automation)
{
    var pids = Process.GetProcessesByName("Notepad").Select(p => p.Id).ToHashSet();
    return automation.GetDesktop().FindAllChildren().Where(w => pids.Contains(w.Properties.ProcessId)).Select(w => w.Properties.NativeWindowHandle.Value).ToHashSet();
}

static IntPtr WaitForNewWindow(UIA3Automation automation, HashSet<IntPtr> before, TimeSpan timeout)
{
    var deadline = DateTime.UtcNow + timeout;
    while (DateTime.UtcNow < deadline)
    {
        var fresh = NotepadWindows(automation).FirstOrDefault(h => !before.Contains(h));
        if (fresh != IntPtr.Zero)
        {
            return fresh;
        }

        Thread.Sleep(250);
    }

    return IntPtr.Zero;
}

static int CaptureStub(string exe, string outdir, string? element, int width, int height)
{
    if (!File.Exists(exe))
    {
        Console.WriteLine($"missing exe: {exe}");
        return 1;
    }

    Directory.CreateDirectory(outdir);
    using var app = Application.Launch(exe);
    using var automation = new UIA3Automation();
    try
    {
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(15));
        if (window is null)
        {
            Console.WriteLine("no main window");
            return 1;
        }

        if (element is null)
        {
            if (!Prepare(window, width, height))
            {
                return 1;
            }

            Shoot(window, Path.Combine(outdir, "stub-window.png"), width, height);
        }
        else
        {
            var target = window.FindFirstDescendant(cf => cf.ByName(element));
            if (target is null)
            {
                Console.WriteLine($"no element named {element}");
                return 1;
            }

            target.CaptureToFile(Path.Combine(outdir, "stub-content.png"));
        }

        Console.WriteLine("captured stub");
        return 0;
    }
    finally
    {
        if (!app.HasExited)
        {
            app.Kill();
        }
    }
}

static bool Prepare(Window window, int width, int height)
{
    try
    {
        if (!window.Patterns.Transform.IsSupported)
        {
            Console.WriteLine("window refused Resize");
            return false;
        }

        var scale = Native.DisplayScale();
        if (!Native.Place(window, 50, 50, (int)Math.Round(width * scale), (int)Math.Round(height * scale)))
        {
            Console.WriteLine("window refused placement");
            return false;
        }

        var rect = window.BoundingRectangle;
        Console.WriteLine($"rect={rect.X},{rect.Y},{rect.Width},{rect.Height} topmost={Native.IsTopmost(window)}");
        return true;
    }
    catch (Exception ex) when (ex is InvalidOperationException || ex is NotSupportedException)
    {
        Console.WriteLine("window refused Resize");
        return false;
    }
}

static void Shoot(Window window, string path, int width, int height)
{
    var raw = Path.ChangeExtension(path, ".raw.png");
    Native.PinTopmost(window, true);
    Thread.Sleep(250);
    var rect = window.BoundingRectangle;
    Console.WriteLine($"shoot rect={rect.X},{rect.Y},{rect.Width},{rect.Height} topmost={Native.IsTopmost(window)}");
    window.CaptureToFile(raw);
    Native.PinTopmost(window, false);
    using (var image = new Bitmap(raw))
    using (var canonical = new Bitmap(width, height))
    {
        using (var g = Graphics.FromImage(canonical))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(image, 0, 0, width, height);
        }

        canonical.Save(path, ImageFormat.Png);
    }

    File.Delete(raw);
}

static class Native
{
    // Primary-display scale without DPI-awareness dependence. Assumes the captured
    // window opens on the primary display; multi-monitor mixed-DPI is out of scope.
    internal static double DisplayScale()
    {
        const int fallback = 96;
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop\WindowMetrics");
        var dpi = key?.GetValue("AppliedDPI") as int? ?? fallback;
        return dpi <= 0 ? 1.0 : dpi / 96.0;
    }

    // Foreground rights cannot be assumed (background launches fail SetForegroundWindow
    // silently), so captures pin the window topmost instead. Same pixels, no occlusion.
    internal static void PinTopmost(Window window, bool topmost)
    {
        const uint flags = 0x0002 | 0x0001 | 0x0010;
        NativeMethods.Pin(window.Properties.NativeWindowHandle.Value, topmost ? new nint(-1) : new nint(-2), flags);
    }

    // SetWindowPos directly: some providers (stock Notepad) ignore UIA TransformPattern
    // resizes or restore a persisted size asynchronously, so place, verify, retry once.
    internal static bool Place(Window window, int x, int y, int width, int height)
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

    internal static bool IsTopmost(Window window)
    {
        const int exStyle = -20;
        const long topmostBit = 0x00000008;
        return (NativeMethods.GetWindowLong(window.Properties.NativeWindowHandle.Value, exStyle) & topmostBit) != 0;
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

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern long GetWindowLongPtr(nint hWnd, int nIndex);

        internal static long GetWindowLong(nint hwnd, int index) => GetWindowLongPtr(hwnd, index);
    }
}
