using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// One golden per Notepad reference surface (operator decision 2026-10-14):
// each test drives our app, focus-free, to the state a stock capture under
// resources/baseline/ shows, and compares it with the golden the parity
// review approved (docs/parity-review.md records each verdict, including
// the surfaces with no test here and why).
[Collection("UI tests")]
public sealed class ParityGoldenTests
{
    readonly ITestOutputHelper output;

    public ParityGoldenTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    static ShellSettings Fresh(string theme = "dark") => new() { WhatsNewSeen = true, Theme = theme, WhenStarts = WhenStartsRouting.Fresh };

    static ShellSettings Continue() => new() { WhatsNewSeen = true, Theme = "dark", WhenStarts = WhenStartsRouting.Continue };

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void MainLightMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => WaitFor(w, "MenuEdit"), new CaptureSetup(Fresh("light")));
        UiGolden.AssertMatches(shot, "parity-main-light", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void TabsMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), NewTab, new CaptureSetup(Fresh()));
        UiGolden.AssertMatches(shot, "parity-tabs", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void FirstLineTruncateMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => Type(w, new string('y', 40)), new CaptureSetup(Fresh()));
        UiGolden.AssertMatches(shot, "parity-firstline-truncate", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void SettingsLightMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), OpenSettings, new CaptureSetup(Fresh("light")));
        UiGolden.AssertMatches(shot, "parity-settings-light", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void WhenStartsMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(
            UiGolden.Tolerance(),
            w =>
            {
                OpenSettings(w);
                Expand(w, "SettingsCardWhenStarts");
            },
            new CaptureSetup(Continue()));
        UiGolden.AssertMatches(shot, "parity-when-starts", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void OpenInSettingMatchesGolden()
    {
        using var shot = UiCapture.CaptureState(
            UiGolden.Tolerance(),
            w =>
            {
                OpenSettings(w);
                var combo = Find(w, "SettingsOpeningFiles");
                combo.Patterns.ScrollItem.PatternOrDefault?.ScrollIntoView();
                Thread.Sleep(500);
            },
            new CaptureSetup(Fresh()));
        UiGolden.AssertMatches(shot, "parity-open-in-setting", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void StatusCrMatchesGolden()
    {
        string dir = MenuBarTests.NewTempDir();
        try
        {
            string file = MenuBarTests.SeedFile(dir, "status-cr.txt", "aa\rbb\r");
            using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => WaitForName(w, "StatusCount", "6 characters"), new CaptureSetup(Fresh(), Args: $"\"{file}\""));
            UiGolden.AssertMatches(shot, "parity-status-cr", output);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void StatusMarkdownFormattedMatchesGolden()
    {
        string dir = MenuBarTests.NewTempDir();
        try
        {
            string file = MenuBarTests.SeedFile(dir, "doc.md", "# Head");
            using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => WaitFor(w, "StatusModeButton"), new CaptureSetup(Fresh(), Args: $"\"{file}\""));
            UiGolden.AssertMatches(shot, "parity-status-md-formatted", output);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void StatusBarOffMatchesGolden()
    {
        var settings = Fresh();
        settings.ShowStatusBar = false;
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => WaitFor(w, "MenuEdit"), new CaptureSetup(settings));
        UiGolden.AssertMatches(shot, "parity-status-toggle-off", output);
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void SessionRestoredMatchesGolden()
    {
        string dir = MenuBarTests.NewTempDir();
        try
        {
            string first = MenuBarTests.SeedFile(dir, "alpha.txt", "alpha one\r\nalpha two");
            string second = MenuBarTests.SeedFile(dir, "beta.txt", "beta");
            var session = new SessionData
            {
                Windows =
                [
                    new SessionWindow
                    {
                        Tabs =
                        [
                            new SessionTab { Path = first, Caret = 3 },
                            new SessionTab { Path = second, Caret = 1 },
                            new SessionTab { Content = "alpha one\r\nalpha two\r\nalpha three\r\nalpha four\r\nalpha five", Caret = 52 },
                        ],
                        Active = 2,
                    },
                ],
            };
            using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), w => Assert.Equal(3, MenuBarTests.WaitForTabCount(w, 3)), new CaptureSetup(Continue(), session));
            UiGolden.AssertMatches(shot, "parity-session-restored", output);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // The app may hold a file for a moment after close; a leftover
            // temp folder is harmless, a failed golden over it is not.
        }
    }

    static void NewTab(Window window)
    {
        UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileNewTab");
        Assert.Equal(2, MenuBarTests.WaitForTabCount(window, 2));
        Thread.Sleep(300);
    }

    static void Type(Window window, string text)
    {
        MenuBarTests.SetBoxText(window, text);
        Thread.Sleep(500);
    }

    static void OpenSettings(Window window)
    {
        Find(window, "SettingsButton").Patterns.Invoke.Pattern.Invoke();
        WaitFor(window, "SettingsHeading");
    }

    static void Expand(Window window, string id)
    {
        Find(window, id).Patterns.ExpandCollapse.Pattern.Expand();
        Thread.Sleep(500);
    }

    static AutomationElement Find(Window window, string automationId)
    {
        var found = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(found);
        return found;
    }

    static void WaitFor(Window window, string automationId)
    {
        _ = Find(window, automationId);
        Thread.Sleep(500);
    }

    static void WaitForName(Window window, string automationId, string name)
    {
        var element = Find(window, automationId);
        Retry.WhileFalse(() => element.Name == name, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250));
        Thread.Sleep(300);
    }
}
