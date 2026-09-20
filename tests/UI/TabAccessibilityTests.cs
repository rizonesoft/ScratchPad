using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §28: tab UIA names carry the stock dirty/clean suffixes. The
// expectations below are literal stock punctuation (the independent pin;
// the migrated suite asserts through TabAccessibilityName.For).
[Collection("UI tests")]
public sealed class TabAccessibilityTests
{
    [Fact]
    public void TabNamesCarryStockSuffixes()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "acc28.txt");
        File.WriteAllText(file, "seed");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 0, "Untitled. Unmodified.");
                WaitForTabName(window, 1, "acc28.txt. Unmodified.");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void SuffixFlipsLiveWithDirty()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "flip28.txt");
        File.WriteAllText(file, "seed");
        SeedFresh();
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                ContentBox(window).Text = "edited";
                WaitForTabName(window, 1, "flip28.txt. Modified.");
                // Saved tabs latch dirty until a save (NotifyEdited); no
                // in-place save trigger exists in Phase 1 (menus own it),
                // so the clean flip goes through close-plus-save and the
                // relaunch reopens the saved bytes clean.
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                AnswerPrompt(window, "Save");
                // Dismissal is not completion: poll the landed bytes.
                var landed = Retry.While(
                    () => { try { return File.ReadAllText(file); } catch (IOException) { return null; } },
                    text => text != "edited",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result;
                Assert.Equal("edited", landed);
                Assert.Equal(1, WaitForTabCount(window, 1));
                using var second = UiLaunch.LaunchAppWithArgs($"\"{file}\"", drainLaunchDrops: true);
                Assert.True(WaitForExit(second, TimeSpan.FromSeconds(10)), "redirected launch did not exit");
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, "flip28.txt. Unmodified.");
                Assert.Empty(LaunchDrops.Drain());
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
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


    static void AnswerPrompt(Window window, string button)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
        var btn = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName(button)))?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(btn);
        btn.Invoke();
        var gone = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")) is not null,
            stillThere => stillThere,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.False(gone);
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
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
    }

    static void SeedFresh() => UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh }, drainLaunchDrops: true);

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
