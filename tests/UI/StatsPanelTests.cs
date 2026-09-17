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

// D01 T01 §14: the stats panel over the active tab's buffer. Opens on
// Ctrl+Shift+G (the menu trigger is deferred to D01 T02 §1); each open
// computes fresh and Refresh re-reads on demand, so typing never pays.
[Collection("UI tests")]
public sealed class StatsPanelTests
{
    const string FixtureText = "The cat sat. The cat slept. The cat ate.";

    [Fact]
    public void PanelListsFixtureExactStats()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            SetBoxText(window, FixtureText);
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var dialog = WaitForDialog(window, "StatsDialog");
            var sections = WaitForSections(dialog, 5, 7, 1);
            Assert.Equal(["The: 3", "cat: 3", "ate: 1", "sat: 1", "slept: 1"], sections.Top);
            Assert.Equal(
                ["Sentences: 3", "Mean length: 3.0", "Shortest: 3", "Longest: 3", "Short (1-10): 3", "Medium (11-25): 0", "Long (26+): 0"],
                sections.Sentences);
            Assert.Equal(["cat"], sections.Repeated);
            var frame = window.BoundingRectangle;
            var panel = dialog.BoundingRectangle;
            Assert.True(frame.Contains(panel), $"panel {panel} escapes window {frame}");
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            Thread.Sleep(500);
            Assert.Equal(1, CountDialogs(window));
            CloseDialog(window, dialog);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    [Fact]
    public void RefreshAndReopenRecompute()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            SetBoxText(window, "hello world");
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var first = WaitForDialog(window, "StatsDialog");
            Assert.Equal(["hello: 1", "world: 1"], WaitForSections(first, 2, 0, 0).Top);
            CloseDialog(window, first);
            SetBoxText(window, "one two three four");
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var second = WaitForDialog(window, "StatsDialog");
            string[] expected = ["four: 1", "one: 1", "three: 1", "two: 1"];
            Assert.Equal(expected, WaitForSections(second, 4, 0, 0).Top);
            var refresh = second.FindFirstDescendant(cf => cf.ByAutomationId("StatsRefreshButton"))?.AsButton();
            Assert.NotNull(refresh);
            refresh.Invoke();
            Assert.Equal(expected, WaitForSections(second, 4, 0, 0).Top);
            CloseDialog(window, second);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    [Fact]
    public void LongRepetitionListTruncatesWithTrailer()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            string text = string.Join(" ", Enumerable.Range(1, 60).SelectMany(i => Enumerable.Repeat($"w{i:000}", 3)));
            SetBoxText(window, text);
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var dialog = WaitForDialog(window, "StatsDialog");
            var sections = WaitForSections(dialog, 0, 0, 51);
            Assert.Equal(51, sections.Repeated.Count);
            Assert.Equal("w001", sections.Repeated[0]);
            Assert.Equal("w050", sections.Repeated[49]);
            Assert.Equal("+10 more", sections.Repeated[50]);
            CloseDialog(window, dialog);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    [Fact]
    public void EmptyTabsShowZeros()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal(1, WaitForTabCount(window, 1));
            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            Assert.Equal(0, WaitForTabCount(window, 0));
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var dialog = WaitForDialog(window, "StatsDialog");
            var sections = WaitForSections(dialog, 0, 7, 0);
            Assert.Empty(sections.Top);
            Assert.Equal(
                ["Sentences: 0", "Mean length: 0.0", "Shortest: 0", "Longest: 0", "Short (1-10): 0", "Medium (11-25): 0", "Long (26+): 0"],
                sections.Sentences);
            Assert.Empty(sections.Repeated);
            CloseDialog(window, dialog);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    // Values sit on the dialog's right edge, not beside their labels:
    // the Mean-length value's right edge must land within dialog padding
    // of the dialog frame (60 physical px covers 150% DPI plus margin).
    [Fact]
    public void ValuesAlignToDialogRightEdge()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            SetBoxText(window, FixtureText);
            Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            var dialog = WaitForDialog(window, "StatsDialog");
            _ = WaitForSections(dialog, 5, 7, 1);
            var value = dialog.FindFirstDescendant(cf => cf.ByName("3.0"));
            Assert.NotNull(value);
            double gap = dialog.BoundingRectangle.Right - value.BoundingRectangle.Right;
            Assert.True(gap >= 0 && gap <= 60, $"value right edge sits {gap:0}px from the dialog edge");
            CloseDialog(window, dialog);
        }
        finally
        {
            CloseApp(app, window);
            SessionData.Delete();
        }
    }

    // Plain StackPanels never materialize in the UIA tree (dump-proven:
    // the dialog flattens to title, headings, rows, buttons), so sections
    // slice by heading text in document order instead of AutomationId.
    static (List<string> Top, List<string> Sentences, List<string> Repeated) WaitForSections(
        AutomationElement dialog, int minTop, int minSentences, int minRepeated)
    {
        (List<string> Top, List<string> Sentences, List<string> Repeated) Read()
        {
            List<string> texts = dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text))
                .Select(text =>
                {
                    try
                    {
                        return text.Properties.Name.ValueOrDefault ?? string.Empty;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        return string.Empty;
                    }
                }).ToList();
            int topAt = texts.IndexOf("Top words");
            int sentAt = texts.IndexOf("Sentences");
            int repAt = texts.IndexOf("Repeated words");
            if (topAt < 0 || sentAt < 0 || repAt < 0 || !(topAt < sentAt && sentAt < repAt))
            {
                return ([], [], []);
            }

            return (
                Pair(texts[(topAt + 1)..sentAt]),
                Pair(texts[(sentAt + 1)..repAt]),
                texts[(repAt + 1)..]);
        }

        // Tabular sections render label/value TextBlock pairs in document
        // order; rejoin them into the asserted "label: value" rows.
        static List<string> Pair(List<string> cells)
        {
            List<string> rows = new(cells.Count / 2);
            for (int i = 0; i + 1 < cells.Count; i += 2)
            {
                rows.Add($"{cells[i]}: {cells[i + 1]}");
            }

            return rows;
        }

        // Floors plus stability: UIA strings can transiently deform while
        // providers settle (2026-09-15: one fused word in two runs), so the
        // read only counts when two consecutive reads agree.
        var deadline = DateTime.UtcNow.AddSeconds(10);
        var sections = Read();
        (List<string> Top, List<string> Sentences, List<string> Repeated) previous = ([], [], []);
        while (!Settled(sections, previous, minTop, minSentences, minRepeated) && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
            previous = sections;
            sections = Read();
        }

        return sections;
    }

    static bool Settled(
        (List<string> Top, List<string> Sentences, List<string> Repeated) current,
        (List<string> Top, List<string> Sentences, List<string> Repeated) previous,
        int minTop, int minSentences, int minRepeated)
    {
        return current.Top.Count >= minTop
            && current.Sentences.Count >= minSentences
            && current.Repeated.Count >= minRepeated
            && current.Top.SequenceEqual(previous.Top)
            && current.Sentences.SequenceEqual(previous.Sentences)
            && current.Repeated.SequenceEqual(previous.Repeated);
    }

    static void CloseDialog(Window window, AutomationElement dialog)
    {
        var close = dialog.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton();
        Assert.NotNull(close);
        close.Invoke();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (window.FindFirstDescendant(cf => cf.ByAutomationId("StatsDialog")) is not null && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
        }

        Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("StatsDialog")));
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

    static int CountDialogs(Window window) =>
        window.FindAllDescendants(cf => cf.ByAutomationId("StatsDialog")).Length;

    static TextBox ContentBox(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box;
    }

    // Programmatic sets propagate async into TextBox.Text while the panel
    // provider reads the live property, so verify the write before any
    // dialog opens on it (read back what was written).
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

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
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
