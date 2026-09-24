using System.Text.RegularExpressions;
using Xunit;

namespace UI;

// D00 T02 §21 item 9: every physical key is bound to the app under test
// immediately before it goes out, and no modifier outlives the press.
// The mutations plant a focus loss (foreground or UIA focus in another
// process) and a stuck modifier through the probes, so they prove the
// failure paths without sending a real key.
public sealed class UiInputFunnelTests
{
    const int App = 4242;
    const int Thief = 777;

    [Fact]
    public void MatchingForegroundAndFocusSendsOnce()
    {
        int sent = 0;
        UiInput.SendChecked(App, () => (0x100, App), () => App, () => sent++, () => true, () => { });
        Assert.Equal(1, sent);
    }

    [Fact]
    public void ForegroundLossFailsLoudAndSendsNothing()
    {
        int sent = 0;
        var saved = UiInput.PreconditionWait;
        UiInput.PreconditionWait = TimeSpan.FromMilliseconds(120);
        try
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, () => (0x200, Thief), () => App, () => sent++, () => true, () => { }));
            Assert.Contains("key not sent", ex.Message, StringComparison.Ordinal);
            Assert.Contains("pid 777", ex.Message, StringComparison.Ordinal);
        }
        finally
        {
            UiInput.PreconditionWait = saved;
        }

        Assert.Equal(0, sent);
    }

    [Fact]
    public void FocusInAnotherProcessFailsLoudAndSendsNothing()
    {
        int sent = 0;
        var saved = UiInput.PreconditionWait;
        UiInput.PreconditionWait = TimeSpan.FromMilliseconds(120);
        try
        {
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, () => (0x100, App), () => Thief, () => sent++, () => true, () => { }));
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, () => (0, App), () => App, () => sent++, () => true, () => { }));
        }
        finally
        {
            UiInput.PreconditionWait = saved;
        }

        Assert.Equal(0, sent);
    }

    [Fact]
    public void PreconditionSettlingWithinTheWaitStillSends()
    {
        int polls = 0;
        int sent = 0;
        UiInput.SendChecked(App, () => ++polls < 3 ? (0x200, Thief) : (0x100, App), () => App, () => sent++, () => true, () => { });
        Assert.Equal(1, sent);
    }

    [Fact]
    public void StuckModifierIsReleasedAndFailsLoud()
    {
        int released = 0;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(App, () => (0x100, App), () => App, () => { }, () => false, () => released++));
        Assert.Contains("modifier stayed down", ex.Message, StringComparison.Ordinal);
        Assert.Equal(1, released);
    }

    // Raw FlaUI keyboard calls bypass the precondition, so only the
    // funnel may make them.
    [Fact]
    public void OnlyTheFunnelTouchesTheKeyboard()
    {
        string root = BindingManifestTests.RepoRoot();
        var offenders = Directory.EnumerateFiles(Path.Combine(root, "tests", "UI"), "*.cs", SearchOption.AllDirectories)
            .Where(f => Path.GetFileName(f) != "UiInput.cs" && Path.GetFileName(f) != "UiInputFunnelTests.cs")
            .Where(f => Regex.IsMatch(File.ReadAllText(f), "\\bKeyboard\\.(Press|Pressing|Type|Release|TypeSimultaneously)\\b"))
            .Select(f => Path.GetFileName(f))
            .ToList();
        Assert.Empty(offenders);
    }
}
