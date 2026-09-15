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

// D01 T01 §7: the tab-close prompt matrix (Save writes bytes and closes on
// pathed tabs, keeps untitled tabs dirty with nothing written; Don't-save
// discards; Cancel keeps exactly), silent window close with full restore,
// and silent kill recovery with files untouched.
[Collection("UI tests")]
public sealed class DirtyPromptTests
{
    [Fact]
    public void SaveOnPathedDirtyTabWritesBytesAndCloses()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "save7.txt");
        File.WriteAllText(file, "base seven");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Content = "edited séven", Caret = 12 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    WaitForTabName(window, 0, "save7.txt");
                    Assert.Equal("edited séven", BoxText(window));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var dialog = WaitForPrompt(window);
                    Assert.Contains(file, PromptText(dialog), StringComparison.Ordinal);
                    AnswerPrompt(window, dialog, "Save");
                    Assert.Equal(0, WaitForTabCount(window, 0));
                    Assert.Equal("edited séven", File.ReadAllText(file));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void DontSaveDiscardsAndCloses()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "drop7.txt");
        File.WriteAllText(file, "base drop");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Content = "edited drop", Caret = 5 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var dialog = WaitForPrompt(window);
                    Assert.Contains(file, PromptText(dialog), StringComparison.Ordinal);
                    AnswerPrompt(window, dialog, "Don't save");
                    Assert.Equal(0, WaitForTabCount(window, 0));
                    Assert.Equal("base drop", File.ReadAllText(file));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void CancelKeepsTabExactly()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "keep7.txt");
        File.WriteAllText(file, "base keep");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Content = "edited keep", Caret = 4 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    Assert.Equal("edited keep", BoxText(window));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var dialog = WaitForPrompt(window);
                    AnswerPrompt(window, dialog, "Cancel");
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    WaitForTabName(window, 0, "keep7.txt");
                    Assert.Equal("edited keep", BoxText(window));
                    Assert.Equal("base keep", File.ReadAllText(file));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var again = WaitForPrompt(window);
                    AnswerPrompt(window, again, "Don't save");
                    Assert.Equal(0, WaitForTabCount(window, 0));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void WindowCloseWithDirtyTabsIsSilentAndRestores()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "win7.txt");
        File.WriteAllText(file, "base win");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows =
            [
                new SessionWindow
                {
                    Active = 1,
                    Tabs =
                    [
                        new SessionTab { Path = file, Content = "edited win", Caret = 2 },
                        new SessionTab { Content = "unsaved win", Caret = 5 },
                    ],
                },
            ],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                Assert.Equal(2, WaitForTabCount(window, 2));
                window.Close();
                var deadline = DateTime.UtcNow.AddSeconds(3);
                while (DateTime.UtcNow < deadline)
                {
                    int modals = 0;
                    try
                    {
                        modals = window.ModalWindows.Length;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        break;
                    }

                    Assert.Equal(0, modals);
                    Thread.Sleep(250);
                }

                CloseAll(app, automation);
                Assert.True(app.HasExited);
            }

            Assert.Equal("base win", File.ReadAllText(file));
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 0, "win7.txt");
                    WaitForTabName(window, 1, "unsaved win");
                    SelectTab(window, 0);
                    Assert.Equal("edited win", BoxText(window));
                    SelectTab(window, 1);
                    Assert.Equal("unsaved win", BoxText(window));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var dialog = WaitForPrompt(window);
                    AnswerPrompt(window, dialog, "Cancel");
                    Assert.Equal(2, WaitForTabCount(window, 2));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            Assert.Equal("base win", File.ReadAllText(file));
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void KillRecoversBuffersSilentlyWithFilesUntouched()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "crash7.txt");
        File.WriteAllText(file, "base crash");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Caret = 0 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                Assert.Equal(1, WaitForTabCount(window, 1));
                Assert.Equal("base crash", BoxText(window));
                ContentBox(window).Focus();
                Keyboard.Type("K7A");
                Press(window, VirtualKeyShort.KEY_T, withControl: true);
                Assert.Equal(2, WaitForTabCount(window, 2));
                ContentBox(window).Focus();
                Keyboard.Type("K7B");
                var checkpointed = Retry.While(
                    () => CheckpointHas("K7A", "K7B"),
                    done => !done,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.True(checkpointed, "crash checkpoint never landed in session.json");
                app.Kill();
                var deadline = DateTime.UtcNow.AddSeconds(10);
                while (!app.HasExited && DateTime.UtcNow < deadline)
                {
                    Thread.Sleep(100);
                }

                Assert.True(app.HasExited);
            }

            Assert.Equal("base crash", File.ReadAllText(file));
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    WaitForTabName(window, 0, "crash7.txt");
                    WaitForTabName(window, 1, "K7B");
                    SelectTab(window, 0);
                    Assert.Contains("K7A", BoxText(window), StringComparison.Ordinal);
                    SelectTab(window, 1);
                    Assert.Equal("K7B", BoxText(window));
                    Assert.Empty(window.ModalWindows);
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }

            Assert.Equal("base crash", File.ReadAllText(file));
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void FreshTypingDeletesStaleSession()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "stale7.txt");
        File.WriteAllText(file, "base stale");
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Content = "STALE7", Caret = 3 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    Assert.Equal("Untitled", TabItemAt(window, 0).Name);
                    ContentBox(window).Focus();
                    Keyboard.Type("F7");
                    var deleted = Retry.While(
                        () => File.Exists(SessionData.FilePath),
                        exists => exists,
                        TimeSpan.FromSeconds(10),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.False(deleted, "stale session.json survived fresh typing");
                    Assert.Equal("F7", BoxText(window));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void UntitledSaveKeepsTabDirtyWithNothingWritten()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Content = "unsaved seven", Caret = 3 }] }],
        }.Save();
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    WaitForTabName(window, 0, "unsaved seven");
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var dialog = WaitForPrompt(window);
                    Assert.Contains("unsaved seven.txt", PromptText(dialog), StringComparison.Ordinal);
                    AnswerPrompt(window, dialog, "Save");
                    Assert.Equal(1, WaitForTabCount(window, 1));
                    Assert.Equal("unsaved seven", BoxText(window));
                    Assert.Empty(Directory.GetFiles(dir));
                    Press(window, VirtualKeyShort.KEY_W, withControl: true);
                    var again = WaitForPrompt(window);
                    AnswerPrompt(window, again, "Don't save");
                    Assert.Equal(0, WaitForTabCount(window, 0));
                }
                finally
                {
                    CloseAll(app, automation);
                }
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    static bool CheckpointHas(string first, string second)
    {
        try
        {
            return File.Exists(SessionData.FilePath)
                && File.ReadAllText(SessionData.FilePath).Contains(first, StringComparison.Ordinal)
                && File.ReadAllText(SessionData.FilePath).Contains(second, StringComparison.Ordinal);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    static AutomationElement WaitForPrompt(Window window)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
        return dialog;
    }

    static string PromptText(AutomationElement dialog)
    {
        var texts = dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
            .Select(el =>
            {
                try
                {
                    return el.Properties.Name.ValueOrDefault ?? string.Empty;
                }
                catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                {
                    return string.Empty;
                }
            });
        return string.Join(" // ", texts);
    }

    static void AnswerPrompt(Window window, AutomationElement dialog, string button)
    {
        var btn = dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName(button)));
        Assert.NotNull(btn);
        btn.AsButton().Invoke();
        var gone = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
            found => found is not null,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250));
        Assert.Null(gone.Result);
    }

    static void SelectTab(Window window, int index)
    {
        var pattern = TabItemAt(window, index).Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
    }

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
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
        SessionData.Delete();
    }

    static void Press(Window window, VirtualKeyShort key, bool withControl, bool withShift = false)
    {
        window.Focus();
        Thread.Sleep(150);
        if (withShift)
        {
            using (Keyboard.Pressing(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT))
            {
                Keyboard.Press(key);
            }
        }
        else if (withControl)
        {
            using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
            {
                Keyboard.Press(key);
            }
        }
        else
        {
            Keyboard.Press(key);
        }

        Thread.Sleep(250);
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

    static string BoxText(Window window) => ContentBox(window).Text ?? string.Empty;

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

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
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
