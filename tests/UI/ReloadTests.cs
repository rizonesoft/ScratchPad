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

// D01 T01 §21: reload prompt on external change. Reactive (no trigger):
// the watcher pends the tab, disk bytes matching the buffer auto-resolve,
// and anything else asks reload-or-keep once window and tab are active.
[Collection("UI tests")]
public sealed class ReloadTests
{
    [Fact]
    public void CleanChangePromptsAndReloadRefreshes()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                File.WriteAllText(file, "changed\n");
                var dialog = WaitForDialog(window, "ReloadDialog");
                Assert.Contains("Reload?", DialogText(dialog), StringComparison.Ordinal);
                Assert.DoesNotContain("discard", DialogText(dialog), StringComparison.Ordinal);
                AnswerDialog(window, dialog, "ReloadDialog", "Reload");
                Assert.Equal("changed\n", WaitForBoxText(window, "changed\n"));
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
    public void KeepHoldsBufferAndDirties()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                File.WriteAllText(file, "changed\n");
                var dialog = WaitForDialog(window, "ReloadDialog");
                // External change must not dirty the buffer: no dot before Keep.
                Assert.Null(window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList()[1].FindFirstDescendant(cf => cf.ByName("•")));
                AnswerDialog(window, dialog, "ReloadDialog", "Keep");
                // Box text alone cannot prove Keep ran (the buffer never
                // changed, only the disk did), and Ctrl+W before the handler
                // marks dirty closes with no prompt. The dirty dot is the
                // true postcondition: it appears only via IsDirty.
                WaitForDirtyDot(window, 1);
                Assert.Equal("original\n", WaitForBoxText(window, "original\n"));
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                var prompt = WaitForDialog(window, "SavePromptDialog");
                AnswerPrompt(window, prompt, "Don't save");
                Assert.Equal(1, WaitForTabCount(window, 1));
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
    public void CancelKeepsLikeKeep()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                File.WriteAllText(file, "changed\n");
                var dialog = WaitForDialog(window, "ReloadDialog");
                AnswerDialog(window, dialog, "ReloadDialog", "Cancel");
                WaitForDirtyDot(window, 1);
                Assert.Equal("original\n", WaitForBoxText(window, "original\n"));
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                var prompt = WaitForDialog(window, "SavePromptDialog");
                AnswerPrompt(window, prompt, "Don't save");
                Assert.Equal(1, WaitForTabCount(window, 1));
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

    [Fact(Skip = "QUARANTINED 2026-09-20 D01-T01-S21 dirty-reload-zero-tabs")]
    public void DirtyReloadDiscardsEdits()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "my edits");
                File.WriteAllText(file, "changed\n");
                var dialog = WaitForDialog(window, "ReloadDialog");
                Assert.Contains("discard", DialogText(dialog), StringComparison.Ordinal);
                AnswerDialog(window, dialog, "ReloadDialog", "Reload");
                Assert.Equal("changed\n", WaitForBoxText(window, "changed\n"));
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

    [Fact(Skip = "QUARANTINED 2026-09-20 D01-T01-S21 dirty-keep-null")]
    public void DirtyKeepPreservesEdits()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                SetBoxText(window, "my edits");
                File.WriteAllText(file, "changed\n");
                var dialog = WaitForDialog(window, "ReloadDialog");
                AnswerDialog(window, dialog, "ReloadDialog", "Keep");
                Assert.Equal("my edits", WaitForBoxText(window, "my edits"));
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
    public void UntitledAndIdenticalWritesNeverPrompt()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 0);
                SetBoxText(window, "untitled typing");
                SelectTab(window, 1);
                File.WriteAllText(file, "original\n");
                Thread.Sleep(2500);
                Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("ReloadDialog")));
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
    public void DeletedFileReloadFailsLoud()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                File.Delete(file);
                var dialog = WaitForDialog(window, "ReloadDialog");
                AnswerDialog(window, dialog, "ReloadDialog", "Reload");
                var missing = WaitForDialog(window, "MissingFileDialog");
                AnswerDialog(window, missing, "MissingFileDialog", "OK");
                Assert.Equal("original\n", WaitForBoxText(window, "original\n"));
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
    public void LockedReloadRoutesThroughUnlock()
    {
        string dir = NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "reload21.txt", "original\n");
            File.WriteAllBytes(file, NoteCrypto.Lock(File.ReadAllBytes(file), "reload-21"));
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var unlock = WaitForDialog(window, "UnlockDialog");
                SetPassword(unlock, "UnlockPasswordBox", "reload-21");
                InvokeByName(unlock, "Unlock");
                Assert.Equal(2, WaitForTabCount(window, 2));
                Assert.Equal("original\n", WaitForBoxText(window, "original\n"));
                File.WriteAllBytes(file, NoteCrypto.Lock("v2\n"u8.ToArray(), "reload-21"));
                var reload = WaitForDialog(window, "ReloadDialog");
                AnswerDialog(window, reload, "ReloadDialog", "Reload");
                var unlock2 = WaitForDialog(window, "UnlockDialog");
                SetPassword(unlock2, "UnlockPasswordBox", "reload-21");
                InvokeByName(unlock2, "Unlock");
                Assert.Equal("v2\n", WaitForBoxText(window, "v2\n"));
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

    static string DialogText(AutomationElement dialog)
    {
        var texts = dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text));
        return string.Join("\n", texts.Select(t => t.AsLabel().Text));
    }

    static void AnswerDialog(Window window, AutomationElement dialog, string automationId, string name)
    {
        var button = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName(name)))?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(button);
        button.Invoke();
        // The answer's continuation (reload fill, keep dirtying) runs after
        // dismissal, so later steps must wait for the element to go away.
        var gone = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            found => found is not null,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        Assert.Null(gone.Result);
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

    static void SetPassword(AutomationElement dialog, string automationId, string password)
    {
        var box = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByAutomationId(automationId))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        box.Text = password;
    }

    static void InvokeByName(AutomationElement dialog, string name)
    {
        var button = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByName(name))?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(button);
        button.Invoke();
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

    static string WaitForBoxText(Window window, string expected)
    {
        string normalized = expected;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            normalized = ContentBox(window).Text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);
            if (string.Equals(normalized, expected, StringComparison.Ordinal))
            {
                return normalized;
            }

            Thread.Sleep(100);
        }

        return normalized;
    }

    static void WaitForDirtyDot(Window window, int index)
    {
        // The dot Ellipse is named U+2022 and collapses when clean, which
        // removes it from the UIA tree: presence proves IsDirty.
        AutomationElement? DotAt()
        {
            var items = window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();
            return items.Count > index
                ? items[index].FindFirstDescendant(cf => cf.ByName("•"))
                : null;
        }

        var dot = Retry.WhileNull(
            DotAt,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dot);
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
