using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §21 item 4: both Bing commands pinned end to end through the
// launcher seam (SCRATCHPAD_TEST_LAUNCH_CAPTURE): the menu command runs
// in the real app on a background window, the URI it would launch lands
// in a capture file, and no browser opens because the capture branch
// returns before Launcher.LaunchUriAsync. Escaping rides a selection
// carrying space, ampersand, equals, hash, and a non-ASCII letter.
[Collection("UI tests")]
public sealed class BingLaunchTests
{
    const string Selection = "a b&c=d #é";

    [Theory]
    [InlineData("MenuEditSearchBing", false)]
    [InlineData("MenuEditDefineBing", true)]
    public void BingCommandLaunchesItsEscapedUriWithoutABrowser(string itemId, bool define)
    {
        using var seam = new LaunchCaptureScope();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            var box = ContentBox(window);
            UiInput.AppendText(box, Selection);
            UiInput.SelectAllText(box);
            UiInput.InvokeMenuItem(window, "MenuEdit", itemId);
            string want = (define ? BingSearch.DefineUrl(Selection) : BingSearch.SearchUrl(Selection)).AbsoluteUri;
            Assert.Equal([want], seam.WaitForCapture(TimeSpan.FromSeconds(1)));
            Assert.Contains("%26c%3Dd%20%23%C3%A9", want, StringComparison.Ordinal);
        }
        finally
        {
            KillApp(app);
        }
    }

    // D00 T02 §28 item 7: a capture the app cannot write surfaces as the
    // LaunchCaptureFailedDialog naming the path, never a silent no-op.
    [Fact]
    public void FailingCaptureWriteReportsInTheWindow()
    {
        string unwritable = Path.Combine(Path.GetTempPath(), $"scratchpad-no-dir-{Guid.NewGuid():N}", "capture.txt");
        using var seam = new LaunchCaptureScope(unwritable);
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.InvokeMenuItem(window, "MenuEdit", "MenuEditSearchBing");
            var dialog = Retry.WhileNull(
                () => window.FindFirstDescendant(cf => cf.ByAutomationId("LaunchCaptureFailedDialog")),
                TimeSpan.FromSeconds(10),
                TimeSpan.FromMilliseconds(250)).Result;
            Assert.NotNull(dialog);
            string text = string.Join(" ", dialog.FindAllDescendants().Select(e => e.Properties.Name.ValueOrDefault ?? string.Empty));
            Assert.Contains("launch capture failed", text, StringComparison.Ordinal);
            Assert.Contains("capture.txt", text, StringComparison.Ordinal);
            Assert.Empty(seam.Lines());
        }
        finally
        {
            KillApp(app);
        }
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

    // The buffer is dirty by design; a kill skips the save prompt.
    static void KillApp(Application app)
    {
        if (!app.HasExited)
        {
            app.Kill();
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        Assert.True(app.HasExited, "app did not exit after Kill");
    }
}
