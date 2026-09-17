using System.Drawing;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// D01 T01 §1: the main window shell. Every test arranges the ShellSettings seam
// explicitly, because first-run and geometry behavior depend on it.
[Collection("UI tests")]
public sealed class MainWindowTests
{
    readonly ITestOutputHelper output;

    public MainWindowTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void ShellRegionsExistAndTitleFollowsConvention()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            Assert.Equal("Untitled - ScratchPad", window.Title);
            Assert.NotNull(FindById(window, "MenuRegion"));
            Assert.NotNull(FindById(window, "TabRegion"));
            Assert.NotNull(FindById(window, "EditorRegion"));
            Assert.NotNull(FindById(window, "StatusRegion"));
            Assert.NotNull(FindById(window, "WhatsNewButton"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void ShellMatchesGolden()
    {
        // UiCapture seeds the seam (no first-run, dark Mica) for determinism.
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        using var fresh = UiCapture.CaptureWindow(tolerance);
        using var golden = new Bitmap(Path.Combine(AppContext.BaseDirectory, "goldens", "main-window.png"));
        var result = GoldenComparer.Compare(golden, fresh, tolerance);
        output.WriteLine($"shell-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (!result.Match)
        {
            var freshPath = Path.Combine(AppContext.BaseDirectory, "golden-failure-shell.png");
            fresh.Save(freshPath);
            output.WriteLine($"failure artifact: {freshPath}");
        }

        Assert.True(result.Match, $"shell golden mismatch: {result.DifferentFraction:P3} different");
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void GeometryRestoresAcrossLaunches()
    {
        // Fenced: restored screen geometry IS the point, and off-screen
        // placement destroys its premise (D00 T02 §8).
        SeedSettings(new ShellSettings { WhatsNewSeen = true, X = 120, Y = 130, Width = 800, Height = 600 });
        using (var app = LaunchApp())
        {
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
            Assert.NotNull(window);
            // AppWindow geometry is physical pixels; read the rect DPI-aware to match.
            var previous = UiDpi.Enter();
            try
            {
                var rect = window.BoundingRectangle;
                output.WriteLine($"restored at {rect.X},{rect.Y} {rect.Width}x{rect.Height}");
                Assert.InRange(rect.X, 116, 124);
                Assert.InRange(rect.Y, 126, 134);
                Assert.InRange(rect.Width, 796, 804);
                Assert.InRange(rect.Height, 596, 604);
            }
            finally
            {
                UiDpi.Exit(previous);
                CloseApp(app, window);
            }
        }

        var saved = ShellSettings.Load();
        Assert.InRange(saved.X, 116, 124);
        Assert.InRange(saved.Width, 796, 804);
    }

    [Theory]
    [InlineData("light", 150)]
    [InlineData("dark", 100)]
    [InlineData("system", 100)]
    public void ThemesRenderWithMica(string theme, int brightnessBound)
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true, Theme = theme });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            Assert.Equal("Untitled - ScratchPad", window.Title);
            Assert.NotNull(FindById(window, "EditorRegion"));
            UiDpi.PinTopmost(window, true);
            try
            {
                PollThemeSide(window, theme, brightnessBound);
            }
            finally
            {
                UiDpi.PinTopmost(window, false);
            }
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    // Theme and Mica need frames to settle; poll for the expected side.
    void PollThemeSide(Window window, string theme, int brightnessBound)
    {
        bool expectLight = theme == "light";
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(10);
        int brightness = expectLight ? 0 : 255;
        string rgb = string.Empty;
        while (DateTime.UtcNow < deadline)
        {
            using var bitmap = UiCapture.PrintCapture(window);
            var center = bitmap.GetPixel(bitmap.Width / 2, bitmap.Height / 2);
            brightness = (center.R + center.G + center.B) / 3;
            rgb = $"RGB({center.R},{center.G},{center.B})";
            if (expectLight == brightness > brightnessBound)
            {
                break;
            }

            Thread.Sleep(250);
        }

        output.WriteLine($"theme {theme}: center {rgb} brightness {brightness}");
        if (expectLight)
        {
            Assert.True(brightness > brightnessBound, $"light theme too dark: {brightness}");
        }
        else
        {
            Assert.True(brightness < brightnessBound, $"{theme} theme too bright: {brightness}");
        }
    }

    [Fact]
    public void FirstRunShowsWhatsNewAndMegaphoneReopensIt()
    {
        if (File.Exists(ShellSettings.FilePath))
        {
            File.Delete(ShellSettings.FilePath);
        }

        SessionData.Delete();
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(15));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            var first = WaitForDialog(window, TimeSpan.FromSeconds(20));
            Assert.NotNull(first);
            Thread.Sleep(500);
            var start = first.FindFirstDescendant(cf => cf.ByName("Start exploring"))?.AsButton();
            Assert.NotNull(start);
            start.Invoke();
            Assert.True(WaitForGone(window, TimeSpan.FromSeconds(10)), "first-run dialog did not close");
            Assert.True(WaitForSeenFlag(TimeSpan.FromSeconds(5)), "first-run did not persist whatsnew.seen");

            FindById(window, "WhatsNewButton")?.AsButton().Invoke();
            var second = WaitForDialog(window, TimeSpan.FromSeconds(10));
            Assert.NotNull(second);
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static Application LaunchApp()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return Application.Launch(appPath);
    }

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        // Every close snapshots the session, so a seeded launch also starts
        // session-clean; otherwise the previous test's tabs would restore.
        SessionData.Delete();
    }

    static AutomationElement? FindById(AutomationElement window, string id)
    {
        // Window content loads async; a bare find races first paint.
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static AutomationElement? WaitForDialog(AutomationElement window, TimeSpan timeout)
    {
        // Raw finds here: FindById's own retry would multiply the wait.
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("WhatsNewDialog")),
            timeout,
            TimeSpan.FromMilliseconds(250)).Result;
    }

    // The seen flag saves on the dialog-dismiss continuation, which races this read.
    static bool WaitForSeenFlag(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (ShellSettings.Load().WhatsNewSeen)
            {
                return true;
            }

            Thread.Sleep(100);
        }

        return false;
    }

    static bool WaitForGone(AutomationElement window, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (window.FindFirstDescendant(cf => cf.ByAutomationId("WhatsNewDialog")) is null)
            {
                return true;
            }

            Thread.Sleep(250);
        }

        return false;
    }

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
}
