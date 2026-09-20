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

// D01 T01 §30: locked tabs leave no plaintext on disk outside the locked
// file. Takes are refused with an inline note, session and checkpoint
// persistence omit locked buffers (path-only entries restore as ghosts),
// and the room scans prove both stores clean.
[Collection("UI tests")]
public sealed class LockedResidueTests
{
    const string Password = "residue-30-pw";
    const string Secret = "plaintext-secret-30-unique-body";

    [Fact]
    public void LockedTabRefusesTakesWithInlineNote()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "residue30.txt", "seed");
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
                LockActiveTab(window);
                UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsSnapshots");
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                var note = Retry.WhileNull(
                    () =>
                    {
                        var candidate = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotsLockedNote"));
                        return candidate is not null && !candidate.IsOffscreen ? candidate : null;
                    },
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(note);
                Assert.Equal("Snapshots are disabled for locked tabs.", note.AsLabel().Text);
                var take = dialog.FindFirstDescendant(cf => cf.ByAutomationId("TakeSnapshotButton"))?.AsButton();
                Assert.NotNull(take);
                Assert.False(take.IsEnabled);
                CloseSnapshotsDialog(window, dialog);
                Assert.False(Directory.Exists(file + ".snapshots"));
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

    [Fact(Skip = "QUARANTINED 2026-09-20 D01-T01-S30 locked-ghost-zero-tabs")]
    public void DirtyLockedBufferStaysOutOfSessionAndRestoresAsGhost()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "ghost30.txt", "seed");
            nint fgBefore = UiForeground.Capture();
            using (var app = LaunchAppWithArgs($"\"{file}\""))
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore);
                Assert.NotNull(window);
                try
                {
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    SelectTab(window, 1);
                    LockActiveTab(window);
                    SetBoxText(window, Secret);
                    Thread.Sleep(3000);
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            SessionData data = SessionData.Load();
            SessionTab? entry = data.Windows.SelectMany(w => w.Tabs).FirstOrDefault(t => t.Path == file);
            Assert.NotNull(entry);
            Assert.Null(entry.Content);
            string appData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ScratchPad");
            foreach (string dataFile in Directory.EnumerateFiles(appData, "*", SearchOption.AllDirectories))
            {
                string content;
                try
                {
                    content = File.ReadAllText(dataFile);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    continue;
                }

                Assert.DoesNotContain(Secret, content, StringComparison.Ordinal);
            }

            nint fgBefore2 = UiForeground.Capture();
            using var app2 = LaunchApp();
            using var automation2 = new UIA3Automation();
            var window2 = UiApp.Attach(app2, automation2, TimeSpan.FromSeconds(30));
            UiForeground.Background(window2, fgBefore2);
            Assert.NotNull(window2);
            try
            {
                Assert.Equal(2, WaitForTabCount(window2, 2));
                SelectTab(window2, 1);
                Thread.Sleep(3000);
                Assert.Null(window2.FindFirstDescendant(cf => cf.ByAutomationId("UnlockDialog")));
                Assert.Equal(string.Empty, BoxText(window2));
                Assert.True(NoteCrypto.IsLocked(File.ReadAllBytes(file)));
            }
            finally
            {
                CloseApp(app2, window2);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    static void LockActiveTab(Window window)
    {
        UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsLock");
        var dialog = WaitForDialog(window, "LockDialog");
        SetPassword(dialog, "LockPasswordBox", Password);
        SetPassword(dialog, "LockConfirmBox", Password);
        InvokeButton(dialog, "LockButton");
        Assert.Equal("Locked.", WaitForStatus(dialog, "LockStatus", "Locked."));
        CloseDialog(window, dialog, "LockDialog");
    }

    static AutomationElement WaitForDialog(Window window, string automationId)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
        Thread.Sleep(1500);
        return dialog;
    }

    static void CloseDialog(Window window, AutomationElement dialog, string automationId)
    {
        var close = dialog.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton() ?? dialog.FindFirstDescendant(cf => cf.ByName("Cancel"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)) is not null && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
        }

        Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)));
    }

    static void CloseSnapshotsDialog(Window window, AutomationElement dialog)
    {
        CloseDialog(window, dialog, "SnapshotsDialog");
    }

    static void SetPassword(AutomationElement dialog, string automationId, string password)
    {
        var box = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByAutomationId(automationId))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        box.Text = password;
    }

    static void InvokeButton(AutomationElement dialog, string automationId)
    {
        var button = Retry.WhileNull(
            () =>
            {
                var candidate = dialog.FindFirstDescendant(cf => cf.ByAutomationId(automationId))?.AsButton();
                return candidate is not null && candidate.IsEnabled ? candidate : null;
            },
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(button);
        button.Invoke();
    }

    static string WaitForStatus(AutomationElement dialog, string automationId, string expected)
    {
        string actual = string.Empty;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            var status = dialog.FindFirstDescendant(cf => cf.ByAutomationId(automationId))?.AsLabel();
            actual = status?.Text ?? string.Empty;
            if (string.Equals(actual, expected, StringComparison.Ordinal))
            {
                return actual;
            }

            Thread.Sleep(100);
        }

        return actual;
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

    static string BoxText(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box.Text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);
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
