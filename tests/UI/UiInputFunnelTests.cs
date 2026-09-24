using System.Text.RegularExpressions;
using Xunit;

namespace UI;

// D00 T02 §21 item 9: every physical key is bound to the target's own
// window immediately before it goes out, and no modifier outlives the
// press. The mutations plant a focus loss (foreground in another
// process, the app's other window, UIA focus elsewhere), a loss midway
// through typed text, a throwing sender, and a stuck modifier through
// the probes, so they prove the failure paths without sending a key.
public sealed class UiInputFunnelTests
{
    const int App = 4242;
    const int Thief = 777;
    const nint Target = 0x100;
    const nint OtherWindow = 0x300;

    [Fact]
    public void MatchingWindowAndFocusSendsOnce()
    {
        int sent = 0;
        UiInput.SendChecked(App, Target, () => (Target, App), () => App, () => sent++, () => true, () => { });
        Assert.Equal(1, sent);
    }

    [Fact]
    public void ForegroundLossFailsLoudAndSendsNothing()
    {
        int sent = 0;
        WithShortWait(() =>
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (0x200, Thief), () => App, () => sent++, () => true, () => { }));
            Assert.Contains("key not sent", ex.Message, StringComparison.Ordinal);
            Assert.Contains("pid 777", ex.Message, StringComparison.Ordinal);
        });
        Assert.Equal(0, sent);
    }

    [Fact]
    public void TheAppsOtherWindowFailsLoudAndSendsNothing()
    {
        int sent = 0;
        WithShortWait(() => Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(App, Target, () => (OtherWindow, App), () => App, () => sent++, () => true, () => { })));
        Assert.Equal(0, sent);
    }

    [Fact]
    public void FocusElsewhereOrUnresolvedIdentityFailsLoudAndSendsNothing()
    {
        int sent = 0;
        WithShortWait(() =>
        {
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (Target, App), () => Thief, () => sent++, () => true, () => { }));
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (0, App), () => App, () => sent++, () => true, () => { }));
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, 0, () => (0, App), () => App, () => sent++, () => true, () => { }));
        });
        Assert.Equal(0, sent);
    }

    [Fact]
    public void PreconditionSettlingWithinTheWaitStillSends()
    {
        int polls = 0;
        int sent = 0;
        UiInput.SendChecked(App, Target, () => ++polls < 3 ? (0x200, Thief) : (Target, App), () => App, () => sent++, () => true, () => { });
        Assert.Equal(1, sent);
    }

    [Fact]
    public void StuckModifierIsReleasedAndFailsLoud()
    {
        int released = 0;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(App, Target, () => (Target, App), () => App, () => { }, () => false, () => released++));
        Assert.Contains("modifier stayed down", ex.Message, StringComparison.Ordinal);
        Assert.Equal(1, released);
    }

    [Fact]
    public void ThrowingSenderStillReleasesModifiersAndKeepsItsFailure()
    {
        int released = 0;
        var ex = Assert.Throws<TimeoutException>(() =>
            UiInput.SendChecked(App, Target, () => (Target, App), () => App, () => throw new TimeoutException("injection died"), () => false, () => released++));
        Assert.Equal("injection died", ex.Message);
        Assert.Equal(1, released);
    }

    [Fact]
    public void FocusLossMidStringStopsTypingAtThatCharacter()
    {
        var typed = new List<char>();
        int probes = 0;
        WithShortWait(() => Assert.Throws<InvalidOperationException>(() =>
            UiInput.TypeChecked(App, Target, "abc", () => (Target, App), () => ++probes <= 1 ? App : Thief, typed.Add, () => true, () => { })));
        Assert.Equal(['a'], typed);
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

    static void WithShortWait(Action body)
    {
        var saved = UiInput.PreconditionWait;
        UiInput.PreconditionWait = TimeSpan.FromMilliseconds(120);
        try
        {
            body();
        }
        finally
        {
            UiInput.PreconditionWait = saved;
        }
    }
}
