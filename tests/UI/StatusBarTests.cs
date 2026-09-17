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

// D01 T02 §4: the status strip shows live truth for the active tab
// (line/column, count, mode, zoom, line endings, encoding), the View
// toggle hides it and persists, and plain-text segments have no click
// path (probed stock negative). Segment asserts read UIA names, which
// carry stock's quirks verbatim (newline, leading spaces, bare Zoom).
[Collection("UI tests")]
public sealed class StatusBarTests
{
    [Fact]
    public void SegmentsShowLiveTruthForLoadedFile()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "counts.txt", "a\tb\r\ncde\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusCount", "8 characters");
                Assert.Equal("Line 1,\nColumn 1", SegmentName(window, "StatusLineColumn"));
                Assert.Equal("Plain text", SegmentName(window, "StatusMode"));
                Assert.Equal("Zoom", SegmentName(window, "StatusZoom"));
                Assert.Equal(" Windows (CRLF)", SegmentName(window, "StatusEol"));
                Assert.Equal(" UTF-8", SegmentName(window, "StatusEncoding"));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void KeystrokesAndCaretMovesUpdateStrip()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            ContentBox(window).Focus();
            Keyboard.Type("a");
            WaitForSegmentName(window, "StatusCount", "1 character");
            Keyboard.Press(VirtualKeyShort.ENTER);
            WaitForSegmentName(window, "StatusCount", "2 characters");
            WaitForSegmentName(window, "StatusLineColumn", "Line 2,\nColumn 1");
            UiInput.Press(window, VirtualKeyShort.HOME, withControl: true);
            WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 1");
            Keyboard.Press(VirtualKeyShort.RIGHT);
            WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 2");
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void TabSwitchUpdatesStrip()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "first.txt", "a\tb\r\ncde\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusCount", "8 characters");
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileNewTab");
                WaitForSegmentName(window, "StatusCount", "0 characters");
                UiInput.AppendText(ContentBox(window), "hello");
                WaitForSegmentName(window, "StatusCount", "5 characters");
                var items = TabItems(window);
                var target = items.FirstOrDefault(item => string.Equals(
                    item.Name,
                    TabAccessibilityName.For("first.txt", isDirty: false),
                    StringComparison.Ordinal));
                Assert.NotNull(target);
                var select = target.Patterns.SelectionItem.PatternOrDefault;
                Assert.NotNull(select);
                select.Select();
                WaitForSegmentName(window, "StatusCount", "8 characters");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void ToggleHidesBarAndPersistsAcrossRelaunch()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 1");
            ToggleStatusBar(window);
            WaitForStripAbsent(window);
            CloseApp(app, window);
        }
        finally
        {
            if (!app.HasExited)
            {
                CloseApp(app, window);
            }
        }

        nint fgBefore2 = UiForeground.Capture();
        using var relaunch = LaunchApp();
        using var automation2 = new UIA3Automation();
        var window2 = UiApp.Attach(relaunch, automation2, TimeSpan.FromSeconds(30));
        UiForeground.Background(window2, fgBefore2);
        Assert.NotNull(window2);
        try
        {
            WaitForStripAbsent(window2);
            ToggleStatusBar(window2);
            WaitForSegmentName(window2, "StatusLineColumn", "Line 1,\nColumn 1");
        }
        finally
        {
            CloseApp(relaunch, window2);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void StatusSegmentsHaveNoClickPath()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "clicks.txt", "a\tb\r\ncde\r\n");
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 1");
                string[] ids = ["StatusLineColumn", "StatusCount", "StatusZoom", "StatusEol", "StatusEncoding"];
                string[] before = ids.Select(id => SegmentName(window, id)).ToArray();
                foreach (string id in ids)
                {
                    Segment(window, id).Click();
                    Thread.Sleep(300);
                }

                Assert.Empty(window.ModalWindows);
                for (int i = 0; i < ids.Length; i++)
                {
                    Assert.Equal(before[i], SegmentName(window, ids[i]));
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void MarkdownTabShowsDisabledFormattedSwitch()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "doc.md", "# T\r\n\r\nbody\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var button = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("StatusModeButton")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(button);
                Assert.Equal("Formatted", button.Name);
                Assert.False(button.IsEnabled);
                var plain = window.FindFirstDescendant(cf => cf.ByAutomationId("StatusMode"));
                if (plain is not null)
                {
                    Assert.True(plain.IsOffscreen);
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void CrFileShowsMacintoshSegment()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "classic.txt", "aa\rbb\r");
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusCount", "6 characters");
                Assert.Equal(" Macintosh (CR)", SegmentName(window, "StatusEol"));
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void Utf16FileShowsEncodingSegment()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = Path.Combine(dir, "wide.txt");
            File.WriteAllText(file, "hi", System.Text.Encoding.Unicode);
            nint fgBefore = UiForeground.Capture();
            using var app = LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusEncoding", " UTF-16 LE");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            DeleteDir(dir);
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

        Assert.True(app.HasExited);
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

    static AutomationElement Segment(Window window, string id)
    {
        var el = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(el);
        return el;
    }

    static string SegmentName(Window window, string id) => Segment(window, id).Name ?? string.Empty;

    static void WaitForSegmentName(Window window, string id, string expected)
    {
        var actual = Retry.While(
            () => SegmentName(window, id),
            name => !string.Equals(name, expected, StringComparison.Ordinal),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.Equal(expected, actual);
    }

    static void WaitForStripAbsent(Window window)
    {
        var absent = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("StatusLineColumn")) is not null,
            present => present,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.False(absent);
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static void OpenMenu(Window window, string topId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        if (!MenuOpen(top))
        {
            top.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(600);
        }
    }

    static bool MenuOpen(AutomationElement top)
    {
        var expand = top.Patterns.ExpandCollapse.PatternOrDefault;
        if (expand is null)
        {
            return true;
        }

        var deadline = DateTime.UtcNow.AddSeconds(2);
        while (DateTime.UtcNow < deadline)
        {
            if (expand.ExpandCollapseState == FlaUI.Core.Definitions.ExpandCollapseState.Expanded)
            {
                return true;
            }

            Thread.Sleep(250);
        }

        return false;
    }

    static void ToggleStatusBar(Window window)
    {
        OpenMenu(window, "MenuView");
        var toggle = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuViewStatusBar"));
        Assert.NotNull(toggle);
        toggle.Patterns.Toggle.Pattern.Toggle();
        Thread.Sleep(500);
    }

}
