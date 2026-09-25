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

    // D00 T02 §36 item 6: a sender failing after the second key-down
    // releases exactly the keys it injected, in reverse, and never the
    // key it failed on or a modifier the operator holds.
    [Fact]
    public void PartialSendReleasesExactlyTheInjectedKeys()
    {
        var chord = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT, FlaUI.Core.WindowsAPI.VirtualKeyShort.KEY_S };
        var injected = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        var released = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        int presses = 0;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(
                App,
                Target,
                () => (Target, App),
                Focus(App),
                () => UiInput.ChordDown(chord, k =>
                {
                    if (++presses == 3)
                    {
                        throw new InvalidOperationException("sender died");
                    }
                }, injected),
                () => UiInput.ChordUp(injected, released.Add),
                () => true,
                () => true,
                () => { }));
        Assert.Equal("sender died", ex.Message);
        Assert.Equal([FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT, FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL], released);
        Assert.DoesNotContain(FlaUI.Core.WindowsAPI.VirtualKeyShort.KEY_S, released);
        Assert.DoesNotContain(FlaUI.Core.WindowsAPI.VirtualKeyShort.ALT, released);
        Assert.Empty(injected);
    }

    // D00 T02 §43 item 3: a release that throws never stops the other
    // releases, and the failure names every key left down.
    [Fact]
    public void ThrowingReleaseNamesTheStuckKeyAndReleasesTheRest()
    {
        var injected = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT, FlaUI.Core.WindowsAPI.VirtualKeyShort.KEY_S };
        var released = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        var ex = Assert.Throws<InvalidOperationException>(() => UiInput.ChordUp(injected, k =>
        {
            if (k == FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT)
            {
                throw new InvalidOperationException("SendInput refused");
            }

            released.Add(k);
        }));
        Assert.Contains("key(s) left down", ex.Message, StringComparison.Ordinal);
        Assert.Contains("SHIFT (InvalidOperationException: SendInput refused)", ex.Message, StringComparison.Ordinal);
        Assert.Equal([FlaUI.Core.WindowsAPI.VirtualKeyShort.KEY_S, FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL], released);
        Assert.Empty(injected);
    }

    // D00 T02 §43 R1-F3: a cancelled release (the test's cancellation
    // reaching the sender) is owned like any other failure, and a pass past
    // its bound reports the keys it never attempted.
    [Fact]
    public void CancelledReleaseAndTheBoundReportEveryStuckKey()
    {
        var keys = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT };
        var released = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        var cancelled = Assert.Throws<InvalidOperationException>(() => UiInput.ChordUp(keys, k =>
        {
            if (k == FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT)
            {
                throw new OperationCanceledException("test cancelled");
            }

            released.Add(k);
        }));
        Assert.Contains("SHIFT (OperationCanceledException: test cancelled)", cancelled.Message, StringComparison.Ordinal);
        Assert.Equal([FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL], released);

        var slow = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT };
        int calls = 0;
        var ticks = new Queue<TimeSpan>([TimeSpan.Zero, TimeSpan.Zero, TimeSpan.FromSeconds(3)]);
        var bounded = Assert.Throws<InvalidOperationException>(() => UiInput.ChordUp(slow, _ => calls++, TimeSpan.FromSeconds(2), () => ticks.Dequeue()));
        Assert.Equal(1, calls);
        Assert.Contains("CONTROL (not attempted: the release pass passed its 2 s bound)", bounded.Message, StringComparison.Ordinal);
    }

    // D00 T02 §43 R2-F1: a release that blocks never holds the pass; it is
    // reported once the bound passes and the remaining keys still release.
    [Fact]
    public void BlockingReleaseIsReportedWithinTheBound()
    {
        var keys = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL, FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT };
        var released = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        using var never = new ManualResetEventSlim(false);
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var ex = Assert.Throws<InvalidOperationException>(() => UiInput.ChordUp(keys, k =>
        {
            if (k == FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT)
            {
                never.Wait(TimeSpan.FromSeconds(30));
                return;
            }

            lock (released)
            {
                released.Add(k);
            }
        }, TimeSpan.FromMilliseconds(300)));
        clock.Stop();
        never.Set();
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(5), $"the pass took {clock.Elapsed}");
        Assert.Contains("SHIFT (release did not return within the 0.3 s bound)", ex.Message, StringComparison.Ordinal);
        // A timed wait may return a hair before the bound, so CONTROL is
        // either reported as not attempted or given the sliver left and
        // released; it is never silently dropped.
        bool controlReleased;
        lock (released)
        {
            controlReleased = released.Contains(FlaUI.Core.WindowsAPI.VirtualKeyShort.CONTROL);
        }

        Assert.True(controlReleased || ex.Message.Contains("CONTROL (", StringComparison.Ordinal), ex.Message);
    }

    // D00 T02 §43 R3-F1: an attempt still queued when the pass gives up
    // never injects its key-up later.
    [Fact]
    public void AbandonedQueuedReleaseNeverInjectsLater()
    {
        var keys = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort> { FlaUI.Core.WindowsAPI.VirtualKeyShort.SHIFT };
        int calls = 0;
        Task? held = null;
        var ex = Assert.Throws<InvalidOperationException>(() => UiInput.ChordUp(keys, _ => calls++, TimeSpan.FromMilliseconds(50), null, action =>
        {
            held = new Task(action);
            return held;
        }));
        Assert.Contains("SHIFT (release did not return within", ex.Message, StringComparison.Ordinal);
        Assert.NotNull(held);
        held.RunSynchronously();
        Assert.Equal(0, calls);
    }

    // D00 T02 §43 R1-F3: the target window closing while the press
    // recovers from a failure still releases the keys and the modifiers.
    [Fact]
    public void WindowClosingDuringRecoveryStillReleases()
    {
        var mods = new Mods();
        int up = 0;
        bool alive = true;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.SendChecked(
                App,
                Target,
                () => (Target, App),
                Focus(App),
                () =>
                {
                    mods.Down = true;
                    alive = false;
                    throw new InvalidOperationException("window closed mid-press");
                },
                () =>
                {
                    up++;
                    mods.Down = false;
                },
                () => true,
                mods.AllUp,
                mods.Release,
                () => alive));
        Assert.Equal("window closed mid-press", ex.Message);
        Assert.Equal(1, up);
        Assert.False(mods.Down);
    }

    // D00 T02 §43 item 2: focus moving to another control inside the app
    // between Ctrl-down and the wheel is not an interruption; the wheel
    // still scrolls once (the cursor sits on the original target) between
    // Ctrl down and up. Focus leaving the app aborts loud after the release.
    [Fact]
    public void InAppFocusMoveBetweenCtrlAndWheelStillScrollsOnce()
    {
        var log = new List<string>();
        bool moved = false;
        UiInput.WheelChecked(App, Target, () => (Target, App), () => new UiInput.FocusRead(App, !moved), true, k => { log.Add($"down {k}"); moved = true; }, k => log.Add($"up {k}"), () => log.Add("scroll"), () => true);
        Assert.Equal(["down CONTROL", "scroll", "up CONTROL"], log);
        var outLog = new List<string>();
        bool left = false;
        var ex = Assert.Throws<InvalidOperationException>(() =>
            UiInput.WheelChecked(App, Target, () => left ? (0x200, Thief) : (Target, App), Focus(App), true, k => { outLog.Add($"down {k}"); left = true; }, k => outLog.Add($"up {k}"), () => outLog.Add("scroll"), () => true));
        Assert.Contains("chord interrupted between key-down and key-up", ex.Message, StringComparison.Ordinal);
        Assert.Equal("up CONTROL", outLog[^1]);
    }

    // D00 T02 §36 item 8: Ctrl+wheel binds to the target like a key press;
    // a planted focus loss scrolls nothing and presses no Ctrl.
    [Fact]
    public void WheelWithFocusLostScrollsNothing()
    {
        int scrolls = 0;
        var pressed = new List<FlaUI.Core.WindowsAPI.VirtualKeyShort>();
        WithShortWait(() =>
        {
            var ex = Assert.Throws<InvalidOperationException>(() =>
                UiInput.WheelChecked(App, Target, () => (0x200, Thief), Focus(App), true, pressed.Add, _ => { }, () => scrolls++, () => true));
            Assert.Contains("key not sent", ex.Message, StringComparison.Ordinal);
        });
        Assert.Equal(0, scrolls);
        Assert.Empty(pressed);
    }

    [Fact]
    public void WheelOnTargetScrollsOnceBetweenCtrlDownAndUp()
    {
        var log = new List<string>();
        UiInput.WheelChecked(App, Target, () => (Target, App), Focus(App), true, k => log.Add($"down {k}"), k => log.Add($"up {k}"), () => log.Add("scroll"), () => true);
        Assert.Equal(["down CONTROL", "scroll", "up CONTROL"], log);
    }
}
