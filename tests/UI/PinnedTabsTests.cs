using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §13: pinned tabs. Double-click toggles the pin (the context menu
// keeps its stock items); pins skip bulk closes, persist across relaunch,
// and feed ShellSettings.PinnedFiles for pathed tabs.
[Collection("UI tests")]
public sealed class PinnedTabsTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void DoubleClickTogglesPinGlyph()
    {
        // Fenced (grandfather §8): double-click IS the point; no pattern path pins a tab (audit clicks).
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(2, WaitForTabCount(window, 2));
            TabItemAt(window, 1).DoubleClick();
            Assert.NotNull(WaitForPin(window, 1));
            TabItemAt(window, 1).DoubleClick();
            Assert.True(WaitForPinGone(window, 1, TimeSpan.FromSeconds(10)));
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void PinsSurviveRelaunch()
    {
        // Fenced (grandfather §8): pin setup needs the cursor (audit clicks).
        string dir = NewTempDir();
        string file = Path.Combine(dir, "persist13.txt");
        File.WriteAllText(file, "pin me");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        try
        {
            using (var app = LaunchAppWithArgs($"\"{file}\""))
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 1, TabAccessibilityName.For("persist13.txt", isDirty: false));
                    TabItemAt(window, 1).DoubleClick();
                    Assert.Contains(file, WaitForPinnedFiles(file));
                    Assert.NotNull(WaitForPin(window, 1));
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 1, TabAccessibilityName.For("persist13.txt", isDirty: false));
                    Assert.NotNull(WaitForPin(window, 1));
                }
                finally
                {
                    CloseApp(app, window);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            ShellSettings fresh = ShellSettings.Load();
            fresh.PinnedFiles.Clear();
            fresh.Save();
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void CloseOthersSkipsPinned()
    {
        // Fenced (grandfather §8): pin setup plus context menu need the cursor (audit clicks).
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string a = SeedFile(dir, "a13.txt");
            string b = SeedFile(dir, "b13.txt");
            string c = SeedFile(dir, "c13.txt");
            using var app = LaunchAppWithArgs($"\"{a}\" \"{b}\" \"{c}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(4, WaitForTabCount(window, 4));
                TabItemAt(window, 3).DoubleClick();
                Assert.NotNull(WaitForPin(window, 3));
                TabItemAt(window, 1).RightClick();
                var closeOthers = WaitForMenuItem(window, "Close other tabs");
                Assert.NotNull(closeOthers);
                closeOthers.Invoke();
                Assert.Equal(2, WaitForTabCount(window, 2));
                Assert.Equal(TabAccessibilityName.For("a13.txt", isDirty: false), TabItemAt(window, 0).Name);
                Assert.Equal(TabAccessibilityName.For("c13.txt", isDirty: false), TabItemAt(window, 1).Name);
                Assert.NotNull(WaitForPin(window, 1));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            ShellSettings fresh = ShellSettings.Load();
            fresh.PinnedFiles.Clear();
            fresh.Save();
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void CloseRightSkipsPinned()
    {
        // Fenced (grandfather §8): pin setup plus context menu need the cursor (audit clicks).
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string a = SeedFile(dir, "a13.txt");
            string b = SeedFile(dir, "b13.txt");
            string c = SeedFile(dir, "c13.txt");
            using var app = LaunchAppWithArgs($"\"{a}\" \"{b}\" \"{c}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(4, WaitForTabCount(window, 4));
                TabItemAt(window, 2).DoubleClick();
                Assert.NotNull(WaitForPin(window, 2));
                TabItemAt(window, 1).RightClick();
                var closeRight = WaitForMenuItem(window, "Close tabs to the right");
                Assert.NotNull(closeRight);
                closeRight.Invoke();
                Assert.Equal(3, WaitForTabCount(window, 3));
                Assert.Equal(TabAccessibilityName.For("Untitled", isDirty: false), TabItemAt(window, 0).Name);
                Assert.Equal(TabAccessibilityName.For("a13.txt", isDirty: false), TabItemAt(window, 1).Name);
                Assert.Equal(TabAccessibilityName.For("b13.txt", isDirty: false), TabItemAt(window, 2).Name);
                Assert.NotNull(WaitForPin(window, 2));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            ShellSettings fresh = ShellSettings.Load();
            fresh.PinnedFiles.Clear();
            fresh.Save();
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void SingleCloseStillClosesPinned()
    {
        // Fenced (grandfather §8): pin setup needs the cursor (audit clicks).
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string a = SeedFile(dir, "a13.txt");
            string b = SeedFile(dir, "b13.txt");
            string c = SeedFile(dir, "c13.txt");
            using var app = LaunchAppWithArgs($"\"{a}\" \"{b}\" \"{c}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(4, WaitForTabCount(window, 4));
                TabItemAt(window, 2).DoubleClick();
                Assert.NotNull(WaitForPin(window, 2));
                Assert.Contains(b, WaitForPinnedFiles(b));
                SelectTab(window, 2);
                UiInput.Press(window, VirtualKeyShort.KEY_W, withControl: true);
                Assert.Equal(3, WaitForTabCount(window, 3));
                Assert.Equal(TabAccessibilityName.For("Untitled", isDirty: false), TabItemAt(window, 0).Name);
                Assert.Equal(TabAccessibilityName.For("a13.txt", isDirty: false), TabItemAt(window, 1).Name);
                Assert.Equal(TabAccessibilityName.For("c13.txt", isDirty: false), TabItemAt(window, 2).Name);
                // Review round 1: the feed mirrors live pin state, so the
                // closed tab's entry goes with it (no orphan jump pin).
                Assert.True(WaitForPinnedFilesGone(b));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            ShellSettings fresh = ShellSettings.Load();
            fresh.PinnedFiles.Clear();
            fresh.Save();
            DeleteDir(dir);
        }
    }

    static string SeedFile(string dir, string name)
    {
        string path = Path.Combine(dir, name);
        File.WriteAllText(path, "pin thirteen");
        return path;
    }

    static void SelectTab(Window window, int index)
    {
        var pattern = TabItemAt(window, index).Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static AutomationElement TabItemAt(Window window, int index)
    {
        var items = Retry.While(
            () => TabItems(window),
            found => found.Count <= index,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result ?? [];
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        return items[index];
    }

    static void WaitForTabName(Window window, int index, string expected)
    {
        string? NameAt()
        {
            var found = TabItems(window);
            return found.Count > index ? found[index].Name : null;
        }

        var result = Retry.While(
            NameAt,
            name => name != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result;
        Assert.Equal(expected, result);
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
    }

    // The settings write proves the toggle ran even if the glyph never
    // renders, which separates gesture failures from render failures.
    static List<string> WaitForPinnedFiles(string path)
    {
        var result = Retry.While(
            () => ShellSettings.Load().PinnedFiles,
            pinned => !pinned.Contains(path),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(result);
        return result;
    }

    static bool WaitForPinnedFilesGone(string path)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            if (!ShellSettings.Load().PinnedFiles.Contains(path))
            {
                return true;
            }

            Thread.Sleep(250);
        }

        return false;
    }

    static AutomationElement WaitForPin(Window window, int index)
    {
        AutomationElement? Pin()
        {
            var found = TabItems(window);
            return found.Count > index
                ? found[index].FindFirstDescendant(cf => cf.ByName("Pinned"))
                : null;
        }

        var result = Retry.WhileNull(
            Pin,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(result);
        return result;
    }

    static bool WaitForPinGone(Window window, int index, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            var items = TabItems(window);
            if (items.Count <= index
                || items[index].FindFirstDescendant(cf => cf.ByName("Pinned")) is null)
            {
                return true;
            }

            Thread.Sleep(250);
        }

        return false;
    }

    static MenuItem? WaitForMenuItem(Window window, string name) =>
        Retry.WhileNull(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).FirstOrDefault(item => item.Name == name)?.AsMenuItem(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;


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

    static Application LaunchApp() => Application.Launch(AppExePath());

    static Application LaunchAppWithArgs(string args) => Application.Launch(AppExePath(), args);

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        SessionData.Delete();
    }

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
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
