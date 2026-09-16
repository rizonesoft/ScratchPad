using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T02 §2 item 2: a corrupt settings file resets to defaults with a
// visible notice. The store behavior is unit-pinned (SettingsStoreTests);
// this drive proves the startup notice end to end. A corrupt file also
// trips first-run, so the whatsnew dialog follows the notice.
[Collection("UI tests")]
public sealed class SettingsStoreNoticeTests
{
    [Fact]
    public void CorruptSettingsShowsNoticeAndRestoresDefaults()
    {
        string settingsPath = ShellSettings.FilePath;
        try
        {
            SessionData.Delete();
            Directory.CreateDirectory(Path.GetDirectoryName(settingsPath)!);
            File.WriteAllText(settingsPath, "{not json!!!");
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                var notice = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("CorruptSettingsDialog")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(notice);
                string text = Retry.While(
                    () => DialogText(notice),
                    current => string.IsNullOrEmpty(current),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result ?? string.Empty;
                Assert.Contains("default settings", text, StringComparison.Ordinal);
                DismissDialog(window, "CorruptSettingsDialog", "OK");
                DismissDialog(window, "WhatsNewDialog", "Close");
                Assert.Equal(1, WaitForTabCount(window, 1));
                ShellSettings restored = ShellSettings.Load();
                Assert.Equal("system", restored.Theme);
                Assert.Equal("Consolas", restored.FontFamily);
                Assert.Equal(1, restored.Version);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                File.Delete(settingsPath);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

    static void DismissDialog(Window window, string dialogId, string button)
    {
        var dialog = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(dialog);
        var close = dialog.FindFirstDescendant(cf => cf.ByControlType(ControlType.Button).And(cf.ByName(button)));
        Assert.NotNull(close);
        close.AsButton().Invoke();
        var gone = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)),
            el => el is not null,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        Assert.Null(gone.Result);
    }

    static string DialogText(AutomationElement dialog)
    {
        return string.Join(
            "\n",
            dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
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
                })
                .Where(text => text.Length > 0));
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList().Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
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

    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException or System.Runtime.InteropServices.COMException)
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
