using System.Globalization;
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

// D01 T01 §17: new-from-template picker. Opens on Ctrl+Shift+E (the menu
// trigger is deferred to D01 T02 §1); choosing a template opens a new tab
// with {title} and {date} expanded, and customs persist as .txt files.
[Collection("UI tests")]
public sealed class TemplateTests
{
    [Fact]
    public void PickerListsBuiltInsAndUsesMeetingNotes()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(1, WaitForTabCount(window, 1));
                Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "TemplatesDialog");
                Assert.NotNull(WaitForUse(dialog, "Blank note"));
                Assert.NotNull(WaitForUse(dialog, "Meeting notes"));
                Assert.NotNull(WaitForUse(dialog, "Daily journal"));
                SetTitle(dialog, "Standup");
                InvokeUse(dialog, "Meeting notes");
                Assert.Equal(2, WaitForTabCount(window, 2));
                string today = DateOnly.FromDateTime(DateTime.Now).ToString("d", CultureInfo.CurrentCulture);
                string expected = $"# Standup\n{today}\n\nAttendees:\n\nNotes:\n\nAction items:\n";
                Assert.Equal(expected, WaitForBoxText(window, expected));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            CleanTemplates();
        }
    }

    [Fact]
    public void DailyJournalOpensExpanded()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "TemplatesDialog");
                var frame = window.BoundingRectangle;
                var panel = dialog.BoundingRectangle;
                Assert.True(frame.Contains(panel), $"panel {panel} escapes window {frame}");
                SetTitle(dialog, "ignored");
                InvokeUse(dialog, "Daily journal");
                Assert.Equal(2, WaitForTabCount(window, 2));
                string today = DateOnly.FromDateTime(DateTime.Now).ToString("d", CultureInfo.CurrentCulture);
                Assert.Equal($"# {today}\n\n## Highlights\n\n", WaitForBoxText(window, $"# {today}\n\n## Highlights\n\n"));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            CleanTemplates();
        }
    }

    [Fact]
    public void BlankNoteOpensCleanEmptyTab()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "TemplatesDialog");
                InvokeUse(dialog, "Blank note");
                Assert.Equal(2, WaitForTabCount(window, 2));
                Assert.Equal(string.Empty, WaitForBoxText(window, string.Empty));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            CleanTemplates();
        }
    }

    [Fact]
    public void SaveCurrentPersistsAcrossRelaunch()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using (var app = LaunchApp())
            {
                using var automation = new UIA3Automation();
                var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
                Assert.NotNull(window);
                try
                {
                    SetBoxText(window, "retro body {title}");
                    Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                    var dialog = WaitForDialog(window, "TemplatesDialog");
                    SaveCurrent(dialog, "retro");
                    Assert.NotNull(WaitForUse(dialog, "retro"));
                    Assert.Equal("retro body {title}", new TemplateStore(TemplatesDir()).ListCustom()[0].Body);
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
                    Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                    var dialog = WaitForDialog(window, "TemplatesDialog");
                    Assert.NotNull(WaitForUse(dialog, "retro"));
                    SetTitle(dialog, "R2");
                    InvokeUse(dialog, "retro");
                    Assert.Equal("retro body R2", WaitForBoxText(window, "retro body R2"));
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
            CleanTemplates();
        }
    }

    [Fact]
    public void UnknownBracesStayLiteralInRoom()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                SetBoxText(window, "{title} {unknown}");
                Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "TemplatesDialog");
                SaveCurrent(dialog, "braces");
                SetTitle(dialog, "T");
                InvokeUse(dialog, "braces");
                Assert.Equal("T {unknown}", WaitForBoxText(window, "T {unknown}"));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            CleanTemplates();
        }
    }

    [Fact]
    public void EmptyTitleDisablesSave()
    {
        CleanTemplates();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "TemplatesDialog");
                var save = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SaveTemplateButton"))?.AsButton();
                Assert.NotNull(save);
                Assert.False(save.IsEnabled);
                SetTitle(dialog, "x");
                var enabled = Retry.WhileNull(
                    () =>
                    {
                        var candidate = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SaveTemplateButton"))?.AsButton();
                        return candidate is not null && candidate.IsEnabled ? candidate : null;
                    },
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(enabled);
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
            CleanTemplates();
        }
    }

    static void SetTitle(AutomationElement dialog, string title)
    {
        var box = dialog.FindFirstDescendant(cf => cf.ByAutomationId("TemplateTitleBox"))?.AsTextBox();
        Assert.NotNull(box);
        box.Text = title;
    }

    static void SaveCurrent(AutomationElement dialog, string name)
    {
        SetTitle(dialog, name);
        var save = Retry.WhileNull(
            () =>
            {
                var candidate = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SaveTemplateButton"))?.AsButton();
                return candidate is not null && candidate.IsEnabled ? candidate : null;
            },
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(save);
        save.Invoke();
        Assert.NotNull(WaitForUse(dialog, name));
    }

    static AutomationElement? WaitForUse(AutomationElement dialog, string name)
    {
        return Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByName($"Use {name}")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static void InvokeUse(AutomationElement dialog, string name)
    {
        var button = WaitForUse(dialog, name);
        Assert.NotNull(button);
        button.AsButton().Invoke();
    }

    static void CloseDialog(Window window, AutomationElement dialog)
    {
        var close = dialog.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (window.FindFirstDescendant(cf => cf.ByAutomationId("TemplatesDialog")) is not null && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
        }

        Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("TemplatesDialog")));
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

    static string TemplatesDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ScratchPad", "templates");
    }

    static void CleanTemplates()
    {
        try
        {
            if (Directory.Exists(TemplatesDir()))
            {
                Directory.Delete(TemplatesDir(), true);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
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

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        SessionData.Delete();
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
