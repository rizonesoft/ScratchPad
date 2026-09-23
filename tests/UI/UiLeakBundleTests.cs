using System.Text.Json;
using Screen = System.Windows.Forms.Screen;
using FlaUI.Core;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 9: a forced leak quotes the full bundle, and the
// matrix rules (redaction, truncation, size cap, retention, slice
// cap, no dumps) pin individually.
[Collection("UI tests")]
public sealed class UiLeakBundleTests
{
    [PrimaryFact]
    [Trait("Category", "Primary")]
    public void ForcedLeakQuotesFullBundle()
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
            // Forced leak: explicit on-primary geometry in background
            // mode, shown no-activate so the window visibly rests on
            // the primary without ever taking the foreground.
            nint fgBefore = UiForeground.Capture();
            var primary = Screen.PrimaryScreen!.Bounds;
            UiLaunch.SeedSettings(new ShellSettings { X = primary.X + 100, Y = primary.Y + 100, WhatsNewSeen = true });
            using var app = UiLaunch.LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                UiForeground.InPlace(window, fgBefore);
                nint hwnd = window.Properties.NativeWindowHandle.Value;
                Assert.True(SpinVisible(hwnd, TimeSpan.FromSeconds(5)), "leak never showed");
                string path = UiLeakBundle.Capture(app.ProcessId, hwnd, "UiLeakBundleTests:ForcedLeak", "--token abc123");
                using var document = JsonDocument.Parse(File.ReadAllText(path));
                JsonElement bundle = document.RootElement;
                Assert.Equal("leak-bundle/1", bundle.GetProperty("schema").GetString());
                Assert.Equal(app.ProcessId, bundle.GetProperty("launchRef").GetProperty("pid").GetInt32());
                Assert.Equal(hwnd.ToInt64(), bundle.GetProperty("hwnd").GetInt64());
                Assert.Equal(hwnd.ToInt64(), bundle.GetProperty("lineage").EnumerateArray().First().GetInt64());
                Assert.Equal(4, bundle.GetProperty("bounds").EnumerateArray().Count());
                Assert.Equal(2, bundle.GetProperty("transitions").EnumerateArray().Count());
                Assert.NotEqual("unknown", bundle.GetProperty("monitor").GetString());
                Assert.True(bundle.GetProperty("dpi").GetUInt32() > 0);
                Assert.Equal("--token ***", bundle.GetProperty("args").GetString());
                Assert.True(bundle.GetProperty("title").GetString()!.Length <= 64);
                Assert.Empty(bundle.GetProperty("eventSlices").EnumerateArray());
                string? shot = bundle.GetProperty("screenshot").GetString();
                Assert.NotNull(shot);
                string shotPath = Path.Combine(Path.GetDirectoryName(path)!, shot);
                Assert.True(File.Exists(shotPath));
                byte[] magic = File.ReadAllBytes(shotPath).Take(4).ToArray();
                Assert.Equal([0x89, 0x50, 0x4E, 0x47], magic);
                Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.dmp"));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }

    [Fact]
    public void EventSlicesFillFromGateLog()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string log = Path.Combine(dir, "gate.log");
            var lines = new List<string> { "FORE FOREGROUND 99999 primary [10 10]" };
            for (int i = 0; i < 60; i++)
            {
                lines.Add($"EVENT 12345 pid=99999 primary [10 10 100 100] SHOW class=WinUIDesktopWin32WindowClass t{i}");
            }

            lines.Add("EVENT 777 pid=1 secondary [0 0 10 10] SHOW other");
            File.WriteAllLines(log, lines);
            string path = UiLeakBundle.Capture(99999, (nint)12345, "UiLeakBundleTests:Slices", string.Empty, log);
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            string[] slices = [.. document.RootElement.GetProperty("eventSlices").EnumerateArray().Select(e => e.GetString()!)];
            Assert.Equal(50, slices.Length);
            Assert.All(slices, line => Assert.Contains(" 12345 ", line, StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void EventSlicesScrubTitles()
    {
        // R2-F1: slice titles scrub like bundle titles while
        // hwnd, pid, bounds, and class stay actionable.
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string log = Path.Combine(dir, "gate.log");
            File.WriteAllLines(log, ["EVENT 12345 pid=99999 primary [10 10 100 100] SHOW class=WinUIDesktopWin32WindowClass --password hunter2 notes"]);
            string path = UiLeakBundle.Capture(99999, (nint)12345, "UiLeakBundleTests:Scrub", string.Empty, log);
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            string[] slices = [.. document.RootElement.GetProperty("eventSlices").EnumerateArray().Select(e => e.GetString()!)];
            string only = Assert.Single(slices);
            Assert.Contains(" 12345 ", only, StringComparison.Ordinal);
            Assert.Contains("class=WinUIDesktopWin32WindowClass", only, StringComparison.Ordinal);
            Assert.Contains("--password ***", only, StringComparison.Ordinal);
            Assert.DoesNotContain("hunter2", only, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void RetentionPrunesOldBundles()
    {
        string root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        string old = Path.Combine(root, DateTime.UtcNow.AddDays(-40).ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture));
        string fresh = Path.Combine(root, DateTime.UtcNow.ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture));
        Directory.CreateDirectory(old);
        Directory.CreateDirectory(fresh);
        try
        {
            UiLeakBundle.PruneOldBundles(root);
            Assert.False(Directory.Exists(old));
            Assert.True(Directory.Exists(fresh));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Theory]
    [InlineData(900, 650, 900, 650)]
    [InlineData(1600, 1600, 1600, 1600)]
    [InlineData(2000, 1000, 1600, 800)]
    [InlineData(1000, 2000, 800, 1600)]
    public void ScaleToCapPinsDimensions(int width, int height, int cappedWidth, int cappedHeight)
    {
        Assert.Equal((cappedWidth, cappedHeight), UiLeakBundle.ScaleToCap(width, height));
    }

    [Theory]
    [InlineData("plain title", "plain title")]
    [InlineData("login token=abc123 failed", "login token=*** failed")]
    public void ScrubTitleShapes(string title, string expected)
    {
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(expected);
        Assert.Equal(expected, UiLeakBundle.ScrubTitle(title));
    }

    [Fact]
    public void ScrubTitleTruncates()
    {
        Assert.Equal(64, UiLeakBundle.ScrubTitle(new string('t', 100)).Length);
    }

    static bool SpinVisible(nint hwnd, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (UiLaunchDiagnostics.IsVisible(hwnd))
            {
                return true;
            }

            Thread.Sleep(100);
        }

        return false;
    }

    static void CloseAll(Application app, UIA3Automation automation)
    {
        foreach (var window in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
            }
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
    }
}
