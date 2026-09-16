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

// D01 T01 §18: export across formats. Opens on Ctrl+Shift+X (the menu
// trigger is deferred to D01 T02 §1); each format button converts the live
// buffer through the shared FormatConverter and writes beside the source.
[Collection("UI tests")]
public sealed class ExportTests
{
    const string SeedBody = "# Title\n\n*em* and **strong** with `code`.\n\n- alpha\n- beta\n\n[docs](https://x.test)\n";

    [Fact]
    public void ExportMarkdownWritesConvertedFile()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "export18.md", SeedBody);
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Press(window, VirtualKeyShort.KEY_X, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "ExportDialog");
                Assert.Equal("export18-export", NameBoxText(dialog));
                InvokeExport(dialog, "Export Markdown");
                Assert.Equal("Exported export18-export.md.", WaitForStatus(dialog, "Exported export18-export.md."));
                string buffer = BoxText(window);
                string expected = FormatConverter.ToMarkdown(buffer).Replace("\n", "\r\n", StringComparison.Ordinal);
                Assert.Equal(expected, File.ReadAllText(Path.Combine(dir, "export18-export.md")));
                Assert.Equal(SeedBody, File.ReadAllText(file));
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
    public void ExportHtmlRendersStructure()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "export18.md", SeedBody);
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Press(window, VirtualKeyShort.KEY_X, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "ExportDialog");
                InvokeExport(dialog, "Export HTML");
                Assert.Equal("Exported export18-export.html.", WaitForStatus(dialog, "Exported export18-export.html."));
                string buffer = BoxText(window);
                string expected = FormatConverter.ToHtmlDocument("export18-export", buffer).Replace("\n", "\r\n", StringComparison.Ordinal);
                string written = File.ReadAllText(Path.Combine(dir, "export18-export.html"));
                Assert.Equal(expected, written);
                Assert.Contains("<h1>Title</h1>", written, StringComparison.Ordinal);
                Assert.Contains("<ul>", written, StringComparison.Ordinal);
                Assert.Contains("<title>export18-export</title>", written, StringComparison.Ordinal);
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
    public void ExportPlainStripsMarkers()
    {
        string dir = NewTempDir();
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = SeedFile(dir, "export18.md", SeedBody);
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                SelectTab(window, 1);
                Press(window, VirtualKeyShort.KEY_X, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "ExportDialog");
                InvokeExport(dialog, "Export Plain Text");
                Assert.Equal("Exported export18-export.txt.", WaitForStatus(dialog, "Exported export18-export.txt."));
                string buffer = BoxText(window);
                string expected = FormatConverter.ToPlainText(buffer).Replace("\n", "\r\n", StringComparison.Ordinal);
                string written = File.ReadAllText(Path.Combine(dir, "export18-export.txt"));
                Assert.Equal(expected, written);
                Assert.DoesNotContain("# Title", written, StringComparison.Ordinal);
                Assert.Contains("docs (https://x.test)", written, StringComparison.Ordinal);
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
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                Press(window, VirtualKeyShort.KEY_X, withControl: true, withShift: true);
                var dialog = WaitForDialog(window, "ExportDialog");
                Assert.NotNull(dialog.FindFirstDescendant(cf => cf.ByAutomationId("ExportSaveFirst")));
                Assert.Null(dialog.FindFirstDescendant(cf => cf.ByName("Export Markdown")));
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
        }
    }

    static string NameBoxText(AutomationElement dialog)
    {
        var box = dialog.FindFirstDescendant(cf => cf.ByAutomationId("ExportNameBox"))?.AsTextBox();
        Assert.NotNull(box);
        return box.Text;
    }

    static void InvokeExport(AutomationElement dialog, string name)
    {
        var button = Retry.WhileNull(
            () => dialog.FindFirstDescendant(cf => cf.ByName(name)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(button);
        button.AsButton().Invoke();
    }

    static string WaitForStatus(AutomationElement dialog, string expected)
    {
        string actual = string.Empty;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            var status = dialog.FindFirstDescendant(cf => cf.ByAutomationId("ExportStatus"))?.AsLabel();
            actual = status?.Text ?? string.Empty;
            if (string.Equals(actual, expected, StringComparison.Ordinal))
            {
                return actual;
            }

            Thread.Sleep(100);
        }

        return actual;
    }

    static void CloseDialog(Window window, AutomationElement dialog)
    {
        var close = dialog.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (window.FindFirstDescendant(cf => cf.ByAutomationId("ExportDialog")) is not null && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
        }

        Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("ExportDialog")));
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
