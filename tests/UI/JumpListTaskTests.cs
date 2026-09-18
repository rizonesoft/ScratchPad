using System.Runtime.InteropServices;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Windows.UI.StartScreen;
using Xunit;

namespace UI;

// D01 T01 §25: jump-list tasks. The taskbar carries a static new-note
// task plus the §8 pin/recent feed; the task's flag opens (or selects)
// a fresh tab fresh or redirected, and feed arguments launch verbatim.
[Collection("UI tests")]
public sealed class JumpListTaskTests
{
    [Fact]
    public async Task TaskbarCarriesNewNotePinnedAndRecent()
    {
        string dir = NewTempDir();
        string pin = Path.Combine(dir, "pin25.txt");
        string rec = Path.Combine(dir, "rec25.txt");
        await File.WriteAllTextAsync(pin, "pinned");
        await File.WriteAllTextAsync(rec, "recent");
        var seeded = new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh };
        seeded.PinnedFiles.Add(pin);
        seeded.RecentFiles.Add(rec);
        SeedSettings(seeded);
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs(string.Empty);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                string expected = JumpListFeed.Fingerprint(JumpListFeed.Build(seeded.PinnedFiles, seeded.RecentFiles));
                string? hash = null;
                for (int i = 0; i < 40 && string.IsNullOrEmpty(hash); i++)
                {
                    hash = ShellSettings.Load().JumpListHash;
                    if (string.IsNullOrEmpty(hash))
                    {
                        await Task.Delay(250);
                    }
                }

                Assert.Equal(expected, hash);
                SetCurrentProcessExplicitAppUserModelID(AppUserModelId);
                JumpList? list = null;
                for (int i = 0; i < 40 && (list is null || list.Items.Count == 0); i++)
                {
                    list = await JumpList.LoadCurrentAsync();
                    if (list.Items.Count == 0)
                    {
                        await Task.Delay(250);
                    }
                }

                Assert.NotNull(list);
                var task = list.Items.SingleOrDefault(item => item.DisplayName == "New note");
                Assert.NotNull(task);
                Assert.Equal(LaunchArgs.NewNoteFlag, task.Arguments);
                Assert.Equal(JumpListFeed.TasksCategory, task.GroupName);
                Assert.NotNull(list.Items.SingleOrDefault(item => item.DisplayName == "pin25.txt"));
                Assert.NotNull(list.Items.SingleOrDefault(item => item.DisplayName == "rec25.txt"));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void NewNoteRedirectOpensFreshTab()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "note25.txt");
        File.WriteAllText(file, "primary");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var first = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(first, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                // Dirty the spare so no clean untitled tab satisfies the
                // note: the redirect must open one.
                SelectTab(window, 0);
                ContentBox(window).Text = "x";
                using var second = LaunchAppWithArgs(LaunchArgs.NewNoteFlag);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                Assert.Equal(3, WaitForTabCount(window, 3));
                WaitForTabName(window, 2, TabAccessibilityName.For("Untitled", isDirty: false));
                Assert.Equal(2, WaitForSelectedTab(window, 2));
                Assert.Empty(LaunchDrops.Drain());
            }
            finally
            {
                CloseAll(first, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void NewNoteFreshWithFileSelectsSpare()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "file25.txt");
        File.WriteAllText(file, "content");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\" {LaunchArgs.NewNoteFlag}");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("file25.txt", isDirty: false));
                Assert.Equal(0, WaitForSelectedTab(window, 0));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void PinTaskArgsOpenTheFile()
    {
        string dir = NewTempDir();
        string pin = Path.Combine(dir, "pinlaunch25.txt");
        File.WriteAllText(pin, "pinned launch");
        SeedFresh();
        try
        {
            // Verbatim feed arguments: this is the task-to-launch contract.
            string args = JumpListFeed.Build([pin], null).Single().Arguments;
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs(args);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("pinlaunch25.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void RecentTaskArgsOpenTheFile()
    {
        string dir = NewTempDir();
        string rec = Path.Combine(dir, "reclaunch25.txt");
        File.WriteAllText(rec, "recent launch");
        SeedFresh();
        try
        {
            string args = JumpListFeed.Build(null, [rec]).Single().Arguments;
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs(args);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("reclaunch25.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    const string AppUserModelId = "Rizonesoft.ScratchPad";

    [DllImport("shell32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern void SetCurrentProcessExplicitAppUserModelID(string appId);

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

    static Application LaunchAppWithArgs(string args)
    {
        LaunchDrops.Drain();
        return Application.Launch(AppExePath(), args);
    }

    static bool WaitForExit(Application app, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        return app.HasExited;
    }

    static void SeedFresh() => SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh });

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        SessionData.Delete();
        LaunchDrops.Drain();
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
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
    }

    static TextBox ContentBox(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static void SelectTab(Window window, int index)
    {
        var items = TabItems(window);
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        var pattern = items[index].Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
    }

    static int WaitForSelectedTab(Window window, int expected)
    {
        int SelectedNow()
        {
            var found = TabItems(window);
            for (int i = 0; i < found.Count; i++)
            {
                try
                {
                    if (found[i].Patterns.SelectionItem.PatternOrDefault?.IsSelected == true)
                    {
                        return i;
                    }
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return -1;
                }
            }

            return -1;
        }

        var result = Retry.While(
            SelectedNow,
            selected => selected != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
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
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.Equal(expected, result);
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
                // Already gone; the exit wait below is the real assertion.
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
