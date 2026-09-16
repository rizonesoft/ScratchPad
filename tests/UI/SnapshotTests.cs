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

// D01 T01 §16: named local versions beside the file. Opens on Ctrl+Shift+H
// (the menu trigger is deferred to D01 T02 §1); takes capture the live
// buffer byte-identically, restores replace it with a §7 prompt on dirty.
[Collection("UI tests")]
public sealed class SnapshotTests
{
    [Fact]
    public void TakeStoresBytesAndListsVersion()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "snap16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "version one");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                Assert.NotNull(WaitForRestore(dialog, "v1"));
                Assert.Equal("version one", FileOpen.Detect(SnapshotStore.ReadBytes(file, 1)).Text);
                var frame = window.BoundingRectangle;
                var panel = dialog.BoundingRectangle;
                Assert.True(frame.Contains(panel), $"panel {panel} escapes window {frame}");
                CloseDialog(window, dialog);
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
    public void RestoreOnCleanBufferSkipsPrompt()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "clean16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                InvokeRestore(dialog, "v1");
                Thread.Sleep(1000);
                Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("SavePromptDialog")));
                Assert.Equal("seed", ContentBox(window).Text);
                CloseDialog(window, dialog);
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
    public void RestoreDontSaveReplacesBuffer()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "dont16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "version one");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                CloseDialog(window, dialog);
                SetBoxText(window, "version two");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                dialog = WaitForDialog(window, "SnapshotsDialog");
                InvokeRestore(dialog, "v1");
                AnswerPrompt(window, "Don't save");
                dialog = WaitForDialog(window, "SnapshotsDialog");
                Assert.Equal("version one", ContentBox(window).Text);
                CloseDialog(window, dialog);
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
    public void RestoreCancelKeepsBuffer()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "cancel16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "version one");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                CloseDialog(window, dialog);
                SetBoxText(window, "version two");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                dialog = WaitForDialog(window, "SnapshotsDialog");
                InvokeRestore(dialog, "v1");
                AnswerPrompt(window, "Cancel");
                dialog = WaitForDialog(window, "SnapshotsDialog");
                Assert.Equal("version two", ContentBox(window).Text);
                CloseDialog(window, dialog);
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
    public void RestoreSaveWritesThenRestores()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "save16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "version one");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                CloseDialog(window, dialog);
                SetBoxText(window, "version two");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                dialog = WaitForDialog(window, "SnapshotsDialog");
                InvokeRestore(dialog, "v1");
                AnswerPrompt(window, "Save");
                dialog = WaitForDialog(window, "SnapshotsDialog");
                Assert.Equal("version one", ContentBox(window).Text);
                Assert.Equal("version two", File.ReadAllText(file));
                CloseDialog(window, dialog);
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
    public void RestoreSaveFailureAbortsWithWorkPreserved()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "locked16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "version one");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                TakeSnapshot(dialog, "v1");
                CloseDialog(window, dialog);
                SetBoxText(window, "version two");
                File.SetAttributes(file, FileAttributes.ReadOnly);
                try
                {
                    Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                    dialog = WaitForDialog(window, "SnapshotsDialog");
                    InvokeRestore(dialog, "v1");
                    AnswerPrompt(window, "Save");
                    dialog = WaitForDialog(window, "SnapshotsDialog");
                    Assert.Equal("version two", ContentBox(window).Text);
                    Assert.Equal("seed", File.ReadAllText(file));
                    CloseDialog(window, dialog);
                }
                finally
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                }
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
    public void RetentionEvictsOldestPastTen()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "keep16.txt", "seed");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "versioned");
                Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "SnapshotsDialog");
                for (int i = 1; i <= 11; i++)
                {
                    TakeSnapshot(dialog, $"s{i:00}");
                }

                Assert.Equal(10, RestoreNames(dialog).Count);
                Assert.DoesNotContain("s01", RestoreNames(dialog));
                Assert.Contains("s11", RestoreNames(dialog));
                Assert.False(File.Exists(Path.Combine(file + ".snapshots", "snap-0001.bin")));
                CloseDialog(window, dialog);
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
    public void UntitledShowsSaveFirstNote()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
            var dialog = WaitForDialog(window, "SnapshotsDialog");
            Assert.NotNull(dialog.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotsSaveFirst")));
            Assert.Null(dialog.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotNameBox")));
            CloseDialog(window, dialog);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    static void TakeSnapshot(AutomationElement dialog, string name)
    {
        var box = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotNameBox"))?.AsTextBox();
        Assert.NotNull(box);
        box.Text = name;
        var take = Retry.WhileNull(
            () =>
            {
                var candidate = dialog.FindFirstDescendant(cf => cf.ByAutomationId("TakeSnapshotButton"))?.AsButton();
                return candidate is not null && candidate.IsEnabled ? candidate : null;
            },
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(take);
        take.Invoke();
        Assert.NotNull(WaitForRestore(dialog, name));
    }

    static AutomationElement? WaitForRestore(AutomationElement dialog, string name)
    {
        return Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByName($"Restore {name}")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static void InvokeRestore(AutomationElement dialog, string name)
    {
        var button = WaitForRestore(dialog, name);
        Assert.NotNull(button);
        button.AsButton().Invoke();
    }

    static List<string> RestoreNames(AutomationElement dialog)
    {
        const string prefix = "Restore ";
        List<string> names = [];
        foreach (AutomationElement button in dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Button)))
        {
            string name;
            try
            {
                name = button.Properties.Name.ValueOrDefault ?? string.Empty;
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                continue;
            }

            if (name.StartsWith(prefix, StringComparison.Ordinal))
            {
                names.Add(name[prefix.Length..]);
            }
        }

        return names;
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

    static void CloseDialog(Window window, AutomationElement dialog)
    {
        var close = dialog.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (window.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotsDialog")) is not null && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
        }

        Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("SnapshotsDialog")));
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
