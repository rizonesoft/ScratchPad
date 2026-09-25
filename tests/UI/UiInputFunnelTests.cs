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

    static Func<UiInput.FocusRead> Focus(int? pid, bool onTarget = true) => () => new UiInput.FocusRead(pid, onTarget);

    static readonly Action NoKeyUp = () => { };

    // A modifier probe that reads up until the key-down presses one.
    sealed class Mods
    {
        internal bool Down;
        internal int Released;

        internal bool AllUp() => !Down;

        internal void Release()
        {
            Released++;
            Down = false;
        }
    }

    [Fact]
    public void MatchingWindowAndFocusSendsOnce()
    {
        int down = 0;
        int up = 0;
        UiInput.SendChecked(App, Target, () => (Target, App), Focus(App), () => down++, () => up++, () => true, () => true, () => { });
        Assert.Equal(1, down);
        Assert.Equal(1, up);
    }

    [Fact]
    public void ForegroundLossFailsLoudAndSendsNothing()
    {
        int sent = 0;
        WithShortWait(() =>
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (0x200, Thief), Focus(App), () => sent++, () => sent++, () => true, () => true, () => { }));
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
            UiInput.SendChecked(App, Target, () => (OtherWindow, App), Focus(App), () => sent++, () => sent++, () => true, () => true, () => { })));
        Assert.Equal(0, sent);
    }

    [Fact]
    public void FocusElsewhereOrUnresolvedIdentityFailsLoudAndSendsNothing()
    {
        int sent = 0;
        WithShortWait(() =>
        {
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (Target, App), Focus(Thief), () => sent++, () => sent++, () => true, () => true, () => { }));
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (0, App), Focus(App), () => sent++, () => sent++, () => true, () => true, () => { }));
            Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, 0, () => (0, App), Focus(App), () => sent++, () => sent++, () => true, () => true, () => { }));
        });
        Assert.Equal(0, sent);
    }

    // D00 T02 §28 item 5: focus on another control of the right window
    // (the tab strip instead of the editor, a sibling field) fails the
    // precondition, so a test cannot pass by typing into the wrong one.
    [Fact]
    public void PlantedFocusOnTheWrongControlFailsThePrecondition()
    {
        int sent = 0;
        WithShortWait(() =>
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (Target, App), Focus(App, onTarget: false), () => sent++, () => sent++, () => true, () => true, () => { }));
            Assert.Contains("not the focus target", ex.Message, StringComparison.Ordinal);
        });
        Assert.Equal(0, sent);
    }

    [Fact]
    public void PreconditionSettlingWithinTheWaitStillSends()
    {
        int polls = 0;
        int sent = 0;
        UiInput.SendChecked(App, Target, () => ++polls < 3 ? (0x200, Thief) : (Target, App), Focus(App), () => sent++, NoKeyUp, () => true, () => true, () => { });
        Assert.Equal(1, sent);
    }

    [Fact]
    public void StuckModifierIsReleasedAndFailsLoud()
    {
        var mods = new Mods();
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(App, Target, () => (Target, App), Focus(App), () => mods.Down = true, NoKeyUp, () => true, mods.AllUp, mods.Release));
        Assert.Contains("modifier stayed down", ex.Message, StringComparison.Ordinal);
        Assert.Equal(1, mods.Released);
    }

    [Fact]
    public void ThrowingSenderStillSendsKeyUpReleasesModifiersAndKeepsItsFailure()
    {
        var mods = new Mods();
        int up = 0;
        var ex = Assert.Throws<TimeoutException>(() =>
            UiInput.SendChecked(App, Target, () => (Target, App), Focus(App), () =>
            {
                mods.Down = true;
                throw new TimeoutException("injection died");
            }, () => up++, () => true, mods.AllUp, mods.Release));
        Assert.Equal("injection died", ex.Message);
        Assert.Equal(1, up);
        Assert.Equal(1, mods.Released);
    }

    // D00 T02 §28 item 6: a modifier already down before the press is
    // the operator's. The funnel sends nothing and never releases it.
    [Fact]
    public void OperatorHeldModifierIsNeverReleased()
    {
        int sent = 0;
        int released = 0;
        WithShortWait(() =>
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.SendChecked(App, Target, () => (Target, App), Focus(App), () => sent++, () => sent++, () => false, () => true, () => released++));
            Assert.Contains("already held", ex.Message, StringComparison.Ordinal);
        });
        Assert.Equal(0, sent);
        Assert.Equal(0, released);
    }

    // §28 R1-F2: a modifier the operator presses during the injection,
    // outside the chord's own set, is left down; the funnel's own stuck
    // modifier is still released.
    [Fact]
    public void ModifierPressedMidInjectionOutsideTheChordIsNotReleased()
    {
        bool ctrlDown = false;
        bool operatorAlt = false;
        int released = 0;
        UiInput.SendChecked(
            App,
            Target,
            () => (Target, App),
            Focus(App),
            () => operatorAlt = true,
            NoKeyUp,
            () => !ctrlDown && !operatorAlt,
            () => !ctrlDown,
            () =>
            {
                released++;
                ctrlDown = false;
            });
        Assert.True(operatorAlt);
        Assert.Equal(0, released);
    }

    // §28 R1-F4: focus moving to another element or window of the app
    // between key-down and key-up is the command working (a new tab's
    // editor, the app's new window), not an interruption.
    [Fact]
    public void CommandMovingFocusInsideTheAppIsNotAnInterruption()
    {
        bool pressed = false;
        int up = 0;
        UiInput.SendChecked(
            App,
            Target,
            () => pressed ? (OtherWindow, App) : (Target, App),
            () => new UiInput.FocusRead(App, !pressed),
            () => pressed = true,
            () => up++,
            () => true,
            () => true,
            () => { });
        Assert.Equal(1, up);
    }

    // D00 T02 §28 item 6: focus moving between key-down and key-up still
    // sends the key-up (nothing stays down), releases the funnel's own
    // modifiers, and aborts loud instead of reporting a clean press.
    [Fact]
    public void FocusChangeBetweenKeyDownAndKeyUpAbortsCleanly()
    {
        var mods = new Mods();
        bool pressed = false;
        int up = 0;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(
                App,
                Target,
                () => pressed ? (0x200, Thief) : (Target, App),
                Focus(App),
                () =>
                {
                    mods.Down = true;
                    pressed = true;
                },
                () =>
                {
                    up++;
                    mods.Down = false;
                },
                () => true,
                mods.AllUp,
                mods.Release));
        Assert.Contains("chord interrupted between key-down and key-up", ex.Message, StringComparison.Ordinal);
        Assert.Contains("pid 777", ex.Message, StringComparison.Ordinal);
        Assert.Equal(1, up);
        Assert.False(mods.Down);
    }

    [Fact]
    public void FocusLossMidStringStopsTypingAtThatCharacter()
    {
        var typed = new List<char>();
        int probes = 0;
        WithShortWait(() => Assert.Throws<InvalidOperationException>(() =>
            UiInput.TypeChecked(App, Target, "abc", () => (Target, App), () => new UiInput.FocusRead(++probes <= 2 ? App : Thief, true), typed.Add, () => true, _ => true, _ => { })));
        Assert.Equal(['a'], typed);
    }

    // §28 R3-F2: a press that closes the target window hands input to
    // another process by design; with the window gone that is the command
    // working, while the same departure with the window alive aborts.
    [Fact]
    public void ClosingTheTargetWindowIsNotAnInterruption()
    {
        bool pressed = false;
        int up = 0;
        UiInput.SendChecked(App, Target, () => pressed ? (0x200, Thief) : (Target, App), () => new UiInput.FocusRead(pressed ? Thief : App, true),
            () => pressed = true, () => up++, () => true, () => true, () => { }, targetAlive: () => false);
        Assert.Equal(1, up);
        pressed = false;
        Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(App, Target, () => pressed ? (0x200, Thief) : (Target, App), () => new UiInput.FocusRead(pressed ? Thief : App, true),
                () => pressed = true, () => up++, () => true, () => true, () => { }, targetAlive: () => true));
        Assert.Equal(2, up);
    }

    // §28 R2-F2: typed text owns only the modifiers its character's
    // injection uses (VkKeyScan's shift state), so an operator's Alt
    // pressed while a plain letter is typed is never released.
    [Fact]
    public void TypedTextOwnsOnlyItsCharactersModifiers()
    {
        Assert.Empty(UiInput.TypedModifiers(0x0041, 'a'));
        Assert.Equal([FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT], UiInput.TypedModifiers(0x0141, 'A'));
        Assert.Equal([FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.ALT], UiInput.TypedModifiers(0x0651, '@'));
        Assert.Empty(UiInput.TypedModifiers(-1, 'x'));
        Assert.Empty(UiInput.TypedModifiers(0x0645, '\u20AC'));
        bool operatorAlt = false;
        int released = 0;
        var typed = new List<char>();
        UiInput.TypeChecked(
            App,
            Target,
            "a",
            () => (Target, App),
            Focus(App),
            ch =>
            {
                typed.Add(ch);
                operatorAlt = true;
            },
            () => !operatorAlt,
            _ => true,
            _ => released++);
        Assert.Equal(['a'], typed);
        Assert.Equal(0, released);
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
