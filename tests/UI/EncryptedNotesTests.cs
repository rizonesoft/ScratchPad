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

// D01 T01 §19: password file locking. Lock opens on Ctrl+Shift+L (the menu
// trigger is deferred to D01 T02 §1); unlock rides the open path, and saves
// of locked tabs re-lock instead of writing plaintext.
[Collection("UI tests")]
public sealed class EncryptedNotesTests
{
    const string SeedBody = "Secret body\nsecond line\n";

    [Fact]
    public void LockUnlockRoundTripsExactBytes()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "lock19.txt", SeedBody);
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
                    UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsLock");
                    var dialog = WaitForDialog(window, "LockDialog");
                    SetPassword(dialog, "LockPasswordBox", "pw19-room");
                    SetPassword(dialog, "LockConfirmBox", "pw19-room");
                    InvokeButton(dialog, "LockButton");
                    Assert.Equal("Locked.", WaitForStatus(dialog, "LockStatus", "Locked."));
                    byte[] locked = File.ReadAllBytes(file);
                    Assert.True(NoteCrypto.IsLocked(locked));
                    Assert.False(ContainsSequence(locked, "Secret body"u8.ToArray()));
                    CloseDialog(window, dialog, "LockDialog");
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            nint fgBefore2 = UiForeground.Capture();
            using (var app = LaunchAppWithArgs($"\"{file}\""))
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore2);
                Assert.NotNull(window);
                try
                {
                    var dialog = WaitForDialog(window, "UnlockDialog");
                    SetPassword(dialog, "UnlockPasswordBox", "pw19-room");
                    InvokeUnlock(dialog);
                    Assert.Equal(2, WaitForTabCount(window, 2));
                    Assert.Equal(SeedBody, BoxText(window));
                    Assert.True(NoteCrypto.IsLocked(File.ReadAllBytes(file)));
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
            DeleteDir(dir);
        }
    }

    [Fact]
    public void WrongPasswordFailsLoudWithNothingRendered()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "lock19.txt", SeedBody);
            byte[] before = NoteCrypto.Lock(File.ReadAllBytes(file), "right-19");
            File.WriteAllBytes(file, before);
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var dialog = WaitForDialog(window, "UnlockDialog");
                SetPassword(dialog, "UnlockPasswordBox", "wrong-19");
                InvokeUnlock(dialog);
                Assert.Equal("Wrong password. Nothing was opened.", WaitForStatus(dialog, "UnlockError", "Wrong password. Nothing was opened."));
                Assert.Equal(1, WaitForTabCount(window, 1));
                Assert.Equal(before, File.ReadAllBytes(file));
                CloseDialog(window, dialog, "UnlockDialog");
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
    public void RelockOnCloseSaveKeepsCiphertext()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "lock19.txt", SeedBody);
            File.WriteAllBytes(file, NoteCrypto.Lock(File.ReadAllBytes(file), "relock-19"));
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var unlock = WaitForDialog(window, "UnlockDialog");
                SetPassword(unlock, "UnlockPasswordBox", "relock-19");
                InvokeUnlock(unlock);
                Assert.Equal(2, WaitForTabCount(window, 2));
                SetBoxText(window, "edited after unlock");
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                AnswerPrompt(window, "Save");
                var relock = WaitForDialog(window, "LockDialog");
                SetPassword(relock, "LockPasswordBox", "relock-19");
                SetPassword(relock, "LockConfirmBox", "relock-19");
                InvokeButton(relock, "LockButton");
                Assert.Equal("Locked.", WaitForStatus(relock, "LockStatus", "Locked."));
                CloseDialog(window, relock, "LockDialog");
                Assert.Equal(1, WaitForTabCount(window, 1));
                byte[] locked = File.ReadAllBytes(file);
                Assert.True(NoteCrypto.IsLocked(locked));
                Assert.Equal("edited after unlock", FileOpen.Detect(NoteCrypto.Unlock(locked, "relock-19")).Text);
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
    public void PasswordNeverReachesDisk()
    {
        const string password = "diskcheck-19-unique-s3cret";
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "lock19.txt", SeedBody);
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
                    UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsLock");
                    var dialog = WaitForDialog(window, "LockDialog");
                    SetPassword(dialog, "LockPasswordBox", password);
                    SetPassword(dialog, "LockConfirmBox", password);
                    InvokeButton(dialog, "LockButton");
                    Assert.Equal("Locked.", WaitForStatus(dialog, "LockStatus", "Locked."));
                    CloseDialog(window, dialog, "LockDialog");
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

            nint fgBefore2 = UiForeground.Capture();
            using (var app = LaunchAppWithArgs($"\"{file}\""))
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                UiForeground.Background(window, fgBefore2);
                Assert.NotNull(window);
                try
                {
                    var dialog = WaitForDialog(window, "UnlockDialog");
                    SetPassword(dialog, "UnlockPasswordBox", password);
                    InvokeUnlock(dialog);
                    Assert.Equal(2, WaitForTabCount(window, 2));
                }
                finally
                {
                    CloseApp(app, window);
                }
            }

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

                Assert.DoesNotContain(password, content, StringComparison.Ordinal);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void RestoreGhostsLockedFile()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "lock19.txt", SeedBody);
            File.WriteAllBytes(file, NoteCrypto.Lock(File.ReadAllBytes(file), "ghost-19"));
            new SessionData
            {
                Windows = [new SessionWindow { Tabs = [new SessionTab { Path = file, Caret = 0 }] }],
            }.Save();
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                Thread.Sleep(3000);
                Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("UnlockDialog")));
                Assert.Equal(string.Empty, BoxText(window));
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
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsLock");
                var dialog = WaitForDialog(window, "LockDialog");
                Assert.NotNull(dialog.FindFirstDescendant(cf => cf.ByAutomationId("LockSaveFirst")));
                Assert.Null(dialog.FindFirstDescendant(cf => cf.ByAutomationId("LockButton")));
                CloseDialog(window, dialog, "LockDialog");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    static bool ContainsSequence(byte[] haystack, byte[] needle)
    {
        for (int i = 0; i + needle.Length <= haystack.Length; i++)
        {
            if (haystack.AsSpan(i, needle.Length).SequenceEqual(needle))
            {
                return true;
            }
        }

        return false;
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

    static void InvokeUnlock(AutomationElement dialog)
    {
        var button = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByName("Unlock"))?.AsButton(),
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
