using System.Drawing;
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
using Xunit.Abstractions;

namespace UI;

// D01 T02 §3: the settings page. Every drive seeds the settings file,
// launches the real app, and proves store writes plus the rendered
// behavior. Store reads are the source of truth, never UIA toggle state:
// first-read ToggleState lies (probed 2026-09-16).
[Collection("UI tests")]
public sealed class SettingsPageTests
{
    readonly ITestOutputHelper output;

    public SettingsPageTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void GearOpensSettingsAndBackReturns()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                var back = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsBackButton")),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(back);
                InvokeOrClick(back);
                var gone = Retry.While(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsHeading")),
                    el => el is not null,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250));
                Assert.Null(gone.Result);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void ThemeEachOptionAppliesLive()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true, Theme = "dark" });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                ExpandCard(window, "SettingsCardAppTheme");
                using var dark = CaptureShot(window);
                ToggleById(window, "SettingsThemeLight");
                WaitForStore(s => s.Theme == "light", "theme light");
                Thread.Sleep(2000);
                using var light = CaptureShot(window);
                double changed = DiffFraction(dark, light);
                output.WriteLine($"theme dark-to-light: {changed:P2} pixels changed");
                Assert.True(changed > 0.05, $"theme flip re-rendered only {changed:P2}");
                ToggleById(window, "SettingsThemeDark");
                WaitForStore(s => s.Theme == "dark", "theme dark");
                ToggleById(window, "SettingsThemeSystem");
                WaitForStore(s => s.Theme == "system", "theme system");
                ToggleById(window, "SettingsThemeDark");
                WaitForStore(s => s.Theme == "dark", "theme restored");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void FontEachChoiceWritesStore()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                ExpandCard(window, "SettingsCardFont");
                string family = PickFamily(window);
                SelectComboOption(window, "SettingsFontFamily", family);
                WaitForStore(s => s.FontFamily == family, $"family {family}");
                SelectComboOption(window, "SettingsFontFamily", "Consolas");
                WaitForStore(s => s.FontFamily == "Consolas", "family Consolas");
                foreach (string style in new[] { "Regular", "Italic", "Bold", "Bold Italic" })
                {
                    SelectComboOption(window, "SettingsFontStyle", style);
                    WaitForStore(s => s.FontStyle == style, $"style {style}");
                }

                foreach (int size in new[] { 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72 })
                {
                    SelectComboOption(window, "SettingsFontSize", size.ToString(CultureInfo.InvariantCulture));
                    WaitForStore(s => s.FontSize == size, $"size {size}");
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void WordWrapToggleWritesStore()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true, WordWrap = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                ToggleById(window, "SettingsWordWrapToggle");
                WaitForStore(s => !s.WordWrap, "wrap off");
                ToggleById(window, "SettingsWordWrapToggle");
                WaitForStore(s => s.WordWrap, "wrap on");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void OpeningEachOptionWritesStore()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                SelectComboOption(window, "SettingsOpeningFiles", "Open in a new window");
                WaitForStore(s => s.OpenIn == "new-window", "open in new window");
                SelectComboOption(window, "SettingsOpeningFiles", "Open in a new tab");
                WaitForStore(s => s.OpenIn == "new-tab", "open in a new tab");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void WhenStartsEachOptionWritesStore()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                ExpandCard(window, "SettingsCardWhenStarts");
                ToggleById(window, "SettingsWhenStartsFresh");
                WaitForStore(s => s.WhenStarts == "fresh", "starts fresh");
                ToggleById(window, "SettingsWhenStartsContinue");
                WaitForStore(s => s.WhenStarts == "continue", "starts continue");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void DisabledCardsStayDisabled()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                foreach (string id in new[]
                {
                    "SettingsFormattingToggle",
                    "SettingsRecentFilesToggle",
                    "SettingsCardSpellCheck",
                    "SettingsAutocorrectToggle",
                    "SettingsWritingToolsToggle",
                })
                {
                    var control = Retry.WhileNull(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
                        TimeSpan.FromSeconds(5),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.NotNull(control);
                    Assert.False(control.IsEnabled, $"{id} is enabled with no owner");
                }
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void SettingsPageHasNoReset()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                // Scan the whole window: the overlay Grid carries no UIA peer
                // (WinUI exposes no peer for a bare Grid), and no menu name
                // contains "reset" ("Restore default zoom" does not match).
                var hits = new List<string>();
                foreach (var el in window.FindAllDescendants())
                {
                    string name;
                    try
                    {
                        name = el.Properties.Name.ValueOrDefault ?? string.Empty;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        continue;
                    }

                    if (name.Contains("reset", StringComparison.OrdinalIgnoreCase))
                    {
                        hits.Add(name);
                    }
                }

                Assert.Empty(hits);
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void EditFontMenuJumpsToSettings()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                window.Focus();
                Thread.Sleep(150);
                DismissMenu();
                var top = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEdit"));
                Assert.NotNull(top);
                top.Patterns.Invoke.Pattern.Invoke();
                Thread.Sleep(600);
                var font = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEditFont")),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(font);
                Assert.True(font.IsEnabled, "Edit > Font still disabled");
                InvokeOrClick(font);
                OpenSettingsWait(window);
                var expanded = Retry.While(
                    () =>
                    {
                        var card = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsCardFont"));
                        if (card is null || !card.Patterns.ExpandCollapse.IsSupported)
                        {
                            return false;
                        }

                        return card.Patterns.ExpandCollapse.Pattern.ExpandCollapseState
                            == ExpandCollapseState.Expanded;
                    },
                    open => !open,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250));
                Assert.True(expanded.Result, "Font card never expanded");
                var onscreen = Retry.While(
                    () =>
                    {
                        var card = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsCardFont"));
                        try
                        {
                            return card?.IsOffscreen ?? true;
                        }
                        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                        {
                            return true;
                        }
                    },
                    off => off,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250));
                Assert.False(onscreen.Result, "Font card never scrolled into view");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void AboutShowsNameAndVersion()
    {
        string settingsPath = SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            SessionData.Delete();
            using var app = LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                OpenSettings(window);
                var name = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsAboutName"));
                Assert.NotNull(name);
                Assert.Equal("Intelligent Notepad", name.Properties.Name.ValueOrDefault);
                var version = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsAboutVersion"));
                Assert.NotNull(version);
                Assert.True(
                    Version.TryParse(version.Properties.Name.ValueOrDefault, out _),
                    $"about version is not a version: [{version.Properties.Name.ValueOrDefault}]");
            }
            finally
            {
                CloseApp(app, window);
            }
        }
        finally
        {
            CleanSettings(settingsPath);
        }
    }

    [Fact]
    public void SettingsCaptureMatchesGolden()
    {
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        string goldenPath = Path.Combine(AppContext.BaseDirectory, "goldens", "settings-page.png");
        using var fresh = UiCapture.CaptureSettings(tolerance);
        if (!File.Exists(goldenPath))
        {
            string saved = Path.Combine(AppContext.BaseDirectory, "settings-page-fresh.png");
            fresh.Save(saved);
            Assert.Fail($"golden missing; fresh capture saved at {saved} for eyeball review");
        }

        using var golden = new Bitmap(goldenPath);
        var result = GoldenComparer.Compare(golden, fresh, tolerance);
        output.WriteLine($"fresh-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (!result.Match)
        {
            string freshPath = Path.Combine(AppContext.BaseDirectory, "golden-failure-settings.png");
            fresh.Save(freshPath);
            using var diff = GoldenComparer.RenderDiff(fresh, result);
            string diffPath = Path.Combine(AppContext.BaseDirectory, "golden-failure-settings-diff.png");
            diff.Save(diffPath);
            output.WriteLine($"failure artifacts: {freshPath} {diffPath}");
        }

        Assert.True(result.Match, $"golden mismatch: {result.DifferentFraction:P3} different ({result.DifferentPixels}/{result.TotalPixels})");
    }

    static string SeedSettings(ShellSettings settings)
    {
        string path = ShellSettings.FilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        settings.Save();
        return path;
    }

    static void CleanSettings(string path)
    {
        SessionData.Delete();
        try
        {
            File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    static void WaitForStore(Func<ShellSettings, bool> condition, string what)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            if (condition(ShellSettings.Load()))
            {
                return;
            }

            Thread.Sleep(100);
        }

        Assert.True(condition(ShellSettings.Load()), $"store never reached: {what}");
    }

    static void OpenSettings(Window window)
    {
        InvokeById(window, "SettingsButton");
        OpenSettingsWait(window);
    }

    static void OpenSettingsWait(Window window)
    {
        var heading = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsHeading")),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(heading);
    }

    static void InvokeById(Window window, string id)
    {
        var el = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(el);
        InvokeOrClick(el);
        Thread.Sleep(300);
    }

    static void ToggleById(Window window, string id)
    {
        var el = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(el);
        // Toggles expose Toggle, radios expose SelectionItem, buttons
        // Invoke: walk the chain so one helper drives all three without
        // the mouse (offscreen clicks have no clickable point).
        if (el.Patterns.Toggle.IsSupported)
        {
            el.Patterns.Toggle.Pattern.Toggle();
        }
        else if (el.Patterns.SelectionItem.IsSupported)
        {
            el.Patterns.SelectionItem.Pattern.Select();
        }
        else
        {
            InvokeOrClick(el);
        }

        Thread.Sleep(300);
    }

    static void ExpandCard(Window window, string cardId)
    {
        var card = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(cardId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(card);
        Assert.True(card.Patterns.ExpandCollapse.IsSupported, $"{cardId} has no expander");
        card.Patterns.ExpandCollapse.Pattern.Expand();
        Thread.Sleep(400);
    }

    static void SelectComboOption(Window window, string comboId, string option)
    {
        var combo = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(comboId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(combo);
        Assert.True(combo.Patterns.ExpandCollapse.IsSupported, $"{comboId} has no expander");
        combo.Patterns.ExpandCollapse.Pattern.Expand();
        Thread.Sleep(400);
        var item = Retry.WhileNull(
            () => window.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem))
                .FirstOrDefault(li =>
                {
                    try
                    {
                        return li.Properties.Name.ValueOrDefault == option;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        return false;
                    }
                }),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(item);
        if (item.Patterns.SelectionItem.IsSupported)
        {
            item.Patterns.SelectionItem.Pattern.Select();
        }
        else
        {
            item.Patterns.Invoke.Pattern.Invoke();
        }

        Thread.Sleep(300);
    }

    static string PickFamily(Window window)
    {
        // Arial ships on every Windows; fall back to whatever the box lists.
        var combo = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsFontFamily"));
        Assert.NotNull(combo);
        combo.Patterns.ExpandCollapse.Pattern.Expand();
        Thread.Sleep(400);
        try
        {
            var names = window.FindAllDescendants(cf => cf.ByControlType(ControlType.ListItem))
                .Select(li =>
                {
                    try
                    {
                        return li.Properties.Name.ValueOrDefault ?? string.Empty;
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
                    {
                        return string.Empty;
                    }
                })
                .Where(n => n.Length > 0)
                .Distinct()
                .ToList();
            if (names.Contains("Arial", StringComparer.Ordinal))
            {
                return "Arial";
            }

            string current = ShellSettings.Load().FontFamily;
            return names.First(n => n != current);
        }
        finally
        {
            Keyboard.Press(VirtualKeyShort.ESCAPE);
            Thread.Sleep(300);
        }
    }

    static Bitmap CaptureShot(Window window)
    {
        // In-memory capture: CaptureToFile holds the file open past return
        // (read-back races a lock), while Capture hands over a Bitmap.
        return window.Capture();
    }

    static double DiffFraction(Bitmap a, Bitmap b)
    {
        Assert.Equal(a.Width, b.Width);
        Assert.Equal(a.Height, b.Height);
        int different = 0;
        int total = 0;
        for (int y = 0; y < a.Height; y += 4)
        {
            for (int x = 0; x < a.Width; x += 4)
            {
                total++;
                Color pa = a.GetPixel(x, y);
                Color pb = b.GetPixel(x, y);
                if (Math.Abs(pa.R - pb.R) > 96 || Math.Abs(pa.G - pb.G) > 96 || Math.Abs(pa.B - pb.B) > 96)
                {
                    different++;
                }
            }
        }

        return (double)different / total;
    }

    static void DismissMenu()
    {
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(350);
    }

    static void InvokeOrClick(AutomationElement item)
    {
        if (item.Patterns.Invoke.IsSupported)
        {
            item.Patterns.Invoke.Pattern.Invoke();
        }
        else
        {
            item.Click();
        }
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
