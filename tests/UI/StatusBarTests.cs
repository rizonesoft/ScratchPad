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
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "counts.txt", "a\tb\r\ncde\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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
        // Fenced (grandfather §8): keystroke handling IS the point (audit keyboard).
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            ContentBox(window).Focus();
            UiInput.Type(ContentBox(window), "a");
            WaitForSegmentName(window, "StatusCount", "1 character");
            UiInput.PressKey(window, VirtualKeyShort.ENTER);
            WaitForSegmentName(window, "StatusCount", "2 characters");
            WaitForSegmentName(window, "StatusLineColumn", "Line 2,\nColumn 1");
            UiInput.Press(window, VirtualKeyShort.HOME, withControl: true);
            WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 1");
            UiInput.PressKey(window, VirtualKeyShort.RIGHT);
            WaitForSegmentName(window, "StatusLineColumn", "Line 1,\nColumn 2");
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    // D01 T02 §9: characters follow every keystroke (stock segment),
    // while words and reading time land once per typing pause: a burst of
    // edits shows no intermediate word count, then the final one.
    [Fact]
    public void LiveWordsTrackTypingAfterEachPause()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            const string start = "The quick brown fox jumps over the lazy dog.";
            string file = SeedFile(dir, "words.txt", start);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusWords", "9 words, 1 min read");
                int before = ComputeCount(window);
                var box = ContentBox(window);
                var seen = new HashSet<string>(StringComparer.Ordinal);
                string text = start;
                for (int i = 0; i < 8; i++)
                {
                    text += $" w{i}";
                    box.Text = text;
                    WaitFast(window, "StatusCount", $"{text.Length} characters");
                    seen.Add(SegmentName(window, "StatusWords"));
                    Thread.Sleep(40);
                }

                Assert.Equal(["9 words, 1 min read"], seen.ToArray());
                WaitForSegmentName(window, "StatusWords", "17 words, 1 min read");
                Thread.Sleep(800);
                Assert.Equal(before + 1, ComputeCount(window));

                // Selection changes refresh the strip but are not edits:
                // toggling the selection every 100 ms for a second after
                // an edit must not postpone the count past its pause.
                text += " tail";
                box.Text = text;
                for (int i = 0; i < 10; i++)
                {
                    if (i % 2 == 0)
                    {
                        UiInput.SelectAllText(box);
                    }
                    else
                    {
                        UiInput.ClearSelection(box);
                    }

                    Thread.Sleep(100);
                }

                Assert.Equal("18 words, 1 min read", SegmentName(window, "StatusWords"));

                box.Text = string.Empty;
                WaitForSegmentName(window, "StatusWords", "0 words");
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

    // D01 T02 §9: the words segment never slows typing. Keystroke-to-
    // character-count latency on a 1 MiB document is measured with the
    // segment and without it (the SCRATCHPAD_TEST_NO_LIVE_WORDS seam),
    // with keystrokes paced past the debounce so word counts compute
    // between them; the medians must sit within 25 ms (a synchronous
    // count on the keystroke path measured +45 ms and fails).
    [Fact]
    public void LiveWordsNeverSlowTyping()
    {
        var body = new System.Text.StringBuilder();
        while (body.Length < 1024 * 1024)
        {
            body.Append("Writers watch length as they type and the strip keeps up. ");
        }

        double without = MedianKeystrokeMs(body.ToString(), liveWords: false, out _);
        double with = MedianKeystrokeMs(body.ToString(), liveWords: true, out string words);
        Assert.StartsWith(TextStats.Compute(body.ToString() + " k0 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15").TotalWords.ToString("N0", System.Globalization.CultureInfo.InvariantCulture) + " words", words, StringComparison.Ordinal);
        Console.WriteLine($"median keystroke latency: {with:F0} ms with live words, {without:F0} ms without");
        Assert.True(
            with <= without + 25,
            $"median keystroke latency {with:F0} ms with live words vs {without:F0} ms without");
    }

    static double MedianKeystrokeMs(string body, bool liveWords, out string finalWords)
    {
        string? prior = Environment.GetEnvironmentVariable("SCRATCHPAD_TEST_NO_LIVE_WORDS");
        Environment.SetEnvironmentVariable("SCRATCHPAD_TEST_NO_LIVE_WORDS", liveWords ? null : "1");
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "big.txt", body);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var box = ContentBox(window);
                string text = body;
                WaitForSegmentName(window, "StatusCount", StatusSegments.TotalText(StatusSegments.CountCharacters(text)));
                var samples = new List<double>();
                for (int i = 0; i < 16; i++)
                {
                    text += $" k{i}";
                    var clock = System.Diagnostics.Stopwatch.StartNew();
                    box.Text = text;
                    WaitFast(window, "StatusCount", StatusSegments.TotalText(StatusSegments.CountCharacters(text)));
                    samples.Add(clock.Elapsed.TotalMilliseconds);
                    Thread.Sleep(450);
                }

                samples.Sort();
                if (liveWords)
                {
                    Thread.Sleep(1500);
                }

                finalWords = liveWords ? SegmentName(window, "StatusWords") : string.Empty;
                return samples[samples.Count / 2];
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable("SCRATCHPAD_TEST_NO_LIVE_WORDS", prior);
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    // D01 T02 §7: the reading level computes on the click only, drops
    // back to its prompt on any edit or tab switch (never a stale score,
    // never a recompute nobody asked for), and an empty buffer says so.
    // Fixture grades are the Unit ReadabilityTests values.
    [Fact]
    public void ReadingLevelComputesOnlyOnClick()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "grade.txt", "Education improves opportunity. Reading matters.");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                WaitForSegmentName(window, "StatusCount", "48 characters");
                Thread.Sleep(1500);
                Assert.Equal("Reading level", SegmentName(window, "StatusReadingLevel"));

                Segment(window, "StatusReadingLevel").Patterns.Invoke.Pattern.Invoke();
                WaitForSegmentName(window, "StatusReadingLevel", "Grade 20.8");

                UiInput.AppendText(ContentBox(window), " More words here.");
                WaitForSegmentName(window, "StatusReadingLevel", "Reading level");
                Thread.Sleep(1500);
                Assert.Equal("Reading level", SegmentName(window, "StatusReadingLevel"));

                Segment(window, "StatusReadingLevel").Patterns.Invoke.Pattern.Invoke();
                WaitForSegmentName(window, "StatusReadingLevel", "Grade 12.0");

                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileNewTab");
                WaitForSegmentName(window, "StatusCount", "0 characters");
                WaitForSegmentName(window, "StatusReadingLevel", "Reading level");
                Segment(window, "StatusReadingLevel").Patterns.Invoke.Pattern.Invoke();
                WaitForSegmentName(window, "StatusReadingLevel", "No text to score");

                var target = TabItems(window).FirstOrDefault(item => (item.Name ?? string.Empty).Contains("grade.txt", StringComparison.Ordinal));
                Assert.NotNull(target);
                target.Patterns.SelectionItem.Pattern.Select();
                WaitForSegmentName(window, "StatusCount", "65 characters");
                WaitForSegmentName(window, "StatusReadingLevel", "Reading level");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            // The drive leaves a dirty tab, which the session keeps; a
            // later launch must not restore it.
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Fact]
    public void TabSwitchUpdatesStrip()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "first.txt", "a\tb\r\ncde\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
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
        using var relaunch = UiLaunch.LaunchApp();
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
        // Fenced (grandfather §8): the click IS the point; proves no-op (audit clicks).
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "clicks.txt", "a\tb\r\ncde\r\n");
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "doc.md", "# T\r\n\r\nbody\r\n");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = SeedFile(dir, "classic.txt", "aa\rbb\r");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        string dir = NewTempDir();
        try
        {
            string file = Path.Combine(dir, "wide.txt");
            File.WriteAllText(file, "hi", System.Text.Encoding.Unicode);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
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

    // The words segment's compute counter (published only under the
    // test-run marker): how many counts the window has run.
    static int ComputeCount(Window window)
    {
        string help = Segment(window, "StatusWords").HelpText ?? string.Empty;
        Assert.StartsWith("counts ", help, StringComparison.Ordinal);
        return int.Parse(help["counts ".Length..], System.Globalization.CultureInfo.InvariantCulture);
    }

    // Tight poll for timing-sensitive drives (D01 T02 §9): 10 ms steps,
    // so a measurement or a burst gap is not padded by the 250 ms poll.
    static void WaitFast(Window window, string id, string expected)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        string name = SegmentName(window, id);
        while (!string.Equals(name, expected, StringComparison.Ordinal) && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(10);
            name = SegmentName(window, id);
        }

        Assert.Equal(expected, name);
    }

    static void WaitForSegmentName(Window window, string id, string expected)
    {
        var actual = Retry.While(
            () => SegmentName(window, id),
            name => !string.Equals(name, expected, StringComparison.Ordinal),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result;
        Assert.Equal(expected, actual);
    }

    static void WaitForStripAbsent(Window window)
    {
        var absent = Retry.While(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("StatusLineColumn")) is not null,
            present => present,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result;
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
