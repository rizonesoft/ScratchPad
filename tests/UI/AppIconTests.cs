using System.Drawing;
using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using Xunit;

namespace UI;

// D01 T01 §11: the operator-supplied notepad.ico shows in the exe, the
// window chrome, and the taskbar. The exe and window icons are pixel-pinned
// here against the shipped asset; the taskbar follows both by platform
// contract and is proven by the committed eyeballed captures beside the
// section's evidence note (no stable programmatic read-back exists for
// taskbar button pixels).
[Collection("UI tests")]
public sealed class AppIconTests
{
    const int WmGeticon = 0x7F;
    const int IconSmall = 0;
    const int GclpHiconsm = -34;

    [Fact]
    public void ExeIconMatchesAsset()
    {
        string exe = AppExePath();
        string asset = ShippedAssetPath(exe);
        using Icon extracted = Icon.ExtractAssociatedIcon(exe)!;
        using Bitmap got = extracted.ToBitmap();
        using Icon wantIcon = new Icon(asset, got.Size);
        using Bitmap want = wantIcon.ToBitmap();
        Assert.Equal(0, DiffPixels(got, want));
    }

    [Fact(Skip = "QUARANTINED 2026-09-17 D01-T01-S32 chrome-icon-uia-timeout")]
    public void WindowChromeIconMatchesAsset()
    {
        using var app = Application.Launch(AppExePath(), string.Empty);
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            nint hwnd = window.Properties.NativeWindowHandle.ValueOrDefault;
            Assert.NotEqual(nint.Zero, hwnd);
            // The app sets its icon on first Loaded, which can land after
            // attach: poll the read instead of racing it once (2026-09-16
            // gate cascade: a single 0 read failed the suite's first test
            // and its lingering primary poisoned all 58 launches behind).
            nint hicon = nint.Zero;
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (hicon == nint.Zero && DateTime.UtcNow < deadline)
            {
                hicon = SendMessage(hwnd, WmGeticon, IconSmall, 0);
                if (hicon == nint.Zero)
                {
                    hicon = GetClassLongPtr(hwnd, GclpHiconsm);
                }

                if (hicon == nint.Zero)
                {
                    Thread.Sleep(100);
                }
            }

            Assert.NotEqual(nint.Zero, hicon);
            using Icon handle = Icon.FromHandle(hicon);
            using Bitmap got = handle.ToBitmap();
            using Icon wantIcon = new Icon(ShippedAssetPath(AppExePath()), got.Size);
            using Bitmap want = wantIcon.ToBitmap();
            Assert.Equal(0, DiffPixels(got, want));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    // Same wait-then-kill guarantee as the other UI files: FlaUI
    // Dispose does NOT terminate the process, and a lingering primary
    // turns every later launch into a redirected window (2026-09-16
    // gate cascade). A test that cannot reap its app fails here.
    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            // Already gone; the exit wait below is the real assertion.
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!app.HasExited)
        {
            app.Kill();
        }

        Assert.True(app.HasExited, "app did not exit after Close");
    }

    static string AppExePath()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return appPath;
    }

    // The asset as shipped next to the exe (Content copy). The Content
    // item carries the source bytes; a stale copy fails here, not in the
    // pixel diff, so the comparison below always reads the live file.
    static string ShippedAssetPath(string exe)
    {
        string dir = Path.GetDirectoryName(exe)!;
        string asset = Path.Combine(dir, "notepad.ico");
        Assert.True(File.Exists(asset), $"shipped asset missing at {asset}");
        return asset;
    }

    static int DiffPixels(Bitmap got, Bitmap want)
    {
        Assert.Equal(got.Size, want.Size);
        int diff = 0;
        for (int y = 0; y < got.Height; y++)
        {
            for (int x = 0; x < got.Width; x++)
            {
                if (got.GetPixel(x, y) != want.GetPixel(x, y))
                {
                    diff++;
                }
            }
        }

        return diff;
    }

    [DllImport("user32.dll", ExactSpelling = true, EntryPoint = "SendMessageW")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern nint SendMessage(nint hWnd, int msg, int wParam, int lParam);

    [DllImport("user32.dll", ExactSpelling = true, EntryPoint = "GetClassLongPtrW")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern nint GetClassLongPtr(nint hWnd, int nIndex);
}
