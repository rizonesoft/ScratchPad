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

// D01 T01 §20: backup on save. No new surface (the file list is the
// surface): every save keeps the pre-save bytes in a timestamped sibling
// first, capped at five with oldest-first rotation.
[Collection("UI tests")]
public sealed class BackupTests
{
    [Fact]
    public void SaveWritesSiblingWithPreSaveBytes()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "bak20.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "edited");
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                AnswerPrompt(window, "Save");
                Assert.Equal(1, WaitForTabCount(window, 1));
                string sibling = Assert.Single(FileSave.BackupSiblings(file));
                Assert.Equal("original\n", File.ReadAllText(sibling).Replace("\r\n", "\n", StringComparison.Ordinal));
                Assert.Equal("edited", File.ReadAllText(file).Replace("\r\n", "\n", StringComparison.Ordinal));
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
    public void RotationEvictsOldestSeededSibling()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "bak20.txt", "current\n");
            var seeded = new List<string>();
            for (int i = 0; i < FileSave.MaxBackups; i++)
            {
                string sibling = Path.Combine(dir, $"bak20.txt.2020010{i + 1}-000000000.bak");
                File.WriteAllText(sibling, $"seed{i}\n");
                File.SetCreationTimeUtc(sibling, new DateTime(2020, 1, i + 1, 0, 0, 0, DateTimeKind.Utc));
                seeded.Add(sibling);
            }

            string foreign = Path.Combine(dir, "bak20.txt.old.bak");
            File.WriteAllText(foreign, "mine\n");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "edited");
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                AnswerPrompt(window, "Save");
                Assert.Equal(1, WaitForTabCount(window, 1));
            }
            finally
            {
                CloseApp(app, window);
            }

            IReadOnlyList<string> siblings = FileSave.BackupSiblings(file);
            Assert.Equal(FileSave.MaxBackups, siblings.Count);
            Assert.DoesNotContain(seeded[0], siblings);
            Assert.Contains(seeded[4], siblings);
            Assert.Equal("mine\n", File.ReadAllText(foreign));
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FailedSaveStillWritesSibling()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "bak20.txt", "original\n");
            File.SetAttributes(file, FileAttributes.ReadOnly);
            try
            {
                nint fgBefore = UiForeground.Capture();
                using var app = LaunchAppWithArgs($"\"{file}\"");
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    SelectTab(window, 1);
                    SetBoxText(window, "edited");
                    UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                    AnswerPrompt(window, "Save");
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    string sibling = Assert.Single(WaitForSiblings(file, 1));
                    Assert.Equal("original\n", File.ReadAllText(sibling).Replace("\r\n", "\n", StringComparison.Ordinal));
                    Assert.Equal("original\n", File.ReadAllText(file).Replace("\r\n", "\n", StringComparison.Ordinal));
                }
                finally
                {
                    CloseApp(app, window);
                }
            }
            finally
            {
                File.SetAttributes(file, FileAttributes.Normal);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // The close-save runs fire-and-forget after the prompt dismisses, and a
    // failed save keeps the tab count unchanged, so the count assert cannot
    // synchronize: poll for the sibling instead.
    static IReadOnlyList<string> WaitForSiblings(string file, int expected)
    {
        IReadOnlyList<string> siblings = [];
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            siblings = FileSave.BackupSiblings(file);
            if (siblings.Count == expected)
            {
                return siblings;
            }

            Thread.Sleep(100);
        }

        return siblings;
    }

    static void AnswerPrompt(Window window, string button)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
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
        var items = window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();
        Assert.True(items.Count > index, $"tab list holds {items.Count} items, index {index} wanted");
        var pattern = items[index].Patterns.SelectionItem.PatternOrDefault;
        Assert.NotNull(pattern);
        pattern.Select();
        Thread.Sleep(150);
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

    static void SetBoxText(Window window, string text)
    {
        ContentBox(window).Text = text;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            if (string.Equals(ContentBox(window).Text, text, StringComparison.Ordinal))
            {
                return;
            }

            Thread.Sleep(100);
        }

        Assert.Equal(text, ContentBox(window).Text);
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList().Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
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

    static string SeedFile(string dir, string name, string content)
    {
        string path = Path.Combine(dir, name);
        File.WriteAllText(path, content);
        return path;
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
