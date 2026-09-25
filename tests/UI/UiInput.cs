using System.Runtime.InteropServices;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace UI;

// Single input funnel for the UI suite (D00 T02 §8). Pattern methods drive
// background windows without touching focus or the cursor; Press,
// PressKey, and Type are the physical core reserved for fenced
// interactive tests (trait Category=Interactive), the only callers
// allowed to activate windows. Every physical key goes through Send
// (D00 T02 §21): immediately before it, the foreground's root-owner
// window must be the target's own window and the UIA-focused element
// must belong to the app under test, or nothing is sent and the test
// fails loud naming the thief; after it (even when the send throws), no
// modifier may stay down. A keystroke that would land in another app
// (a global hotkey owner, a stolen foreground) or in the app's other
// window never escapes. Since D00 T02 §28 the precondition also binds
// the press to its focus target (the element itself or, for a window
// target, anything inside that window), refuses to press while the
// operator holds a modifier (the funnel never releases a key it did not
// press), and splits every press into key-down and key-up: focus lost
// between them still sends the key-up, then aborts loud.
internal static class UiInput
{
    // Foreground probe: (root-owner HWND, owning pid). The root owner
    // folds an owned dialog or popup onto the window that owns it, so a
    // press into the app's own modal still binds to the app window while
    // a second app window (or another app) does not. Swappable so the
    // focus-loss mutations are provable without sending real keys.
    internal static Func<(nint Root, int Pid)> ForegroundProbe = RealForeground;

    // How long the precondition may take to settle after a Focus call.
    internal static TimeSpan PreconditionWait = TimeSpan.FromSeconds(1);

    // Physical shortcut press for fenced tests only. Default-suite tests
    // must use the pattern methods below instead.
    internal static void Press(Window window, VirtualKeyShort key, bool withControl, bool withShift = false, bool withAlt = false)
    {
        ArgumentNullException.ThrowIfNull(window);
        window.Focus();
        Thread.Sleep(150);
        Send(window, key, withControl, withShift, withAlt);
        Thread.Sleep(250);
    }

    // Physical key into whatever the caller already focused inside the
    // app (a dialog field, a list item, an open menu). The precondition
    // binds the press to the target's own window, not just the process.
    internal static void PressKey(AutomationElement target, VirtualKeyShort key, bool withControl = false, bool withShift = false, bool withAlt = false)
    {
        ArgumentNullException.ThrowIfNull(target);
        Send(target, key, withControl, withShift, withAlt);
    }

    // Ctrl+mouse-wheel through the funnel (D00 T02 §36 item 8): the same
    // precondition as a key press (foreground root, focus target, no held
    // modifier), the cursor moved over the target, Ctrl down and up as an
    // injected chord, and no modifier left behind. Fenced like Press: it
    // moves the real cursor.
    internal static void Wheel(AutomationElement target, int clicks, bool withControl)
    {
        ArgumentNullException.ThrowIfNull(target);
        WheelChecked(
            target.Properties.ProcessId.Value,
            ExpectedRoot(target),
            ForegroundProbe,
            () => ReadFocus(target),
            withControl,
            Keyboard.Press,
            Keyboard.Release,
            () =>
            {
                Mouse.MoveTo(target.GetClickablePoint());
                Mouse.Scroll(clicks);
            },
            () => ModifiersReleased(AllModifiers));
    }

    // The checked wheel core, pure over its probes and senders.
    internal static void WheelChecked(
        int expectedPid,
        nint expectedRoot,
        Func<(nint Root, int Pid)> foreground,
        Func<FocusRead> focus,
        bool withControl,
        Action<VirtualKeyShort> press,
        Action<VirtualKeyShort> release,
        Action scroll,
        Func<bool> noModifierHeld)
    {
        ArgumentNullException.ThrowIfNull(press);
        ArgumentNullException.ThrowIfNull(release);
        ArgumentNullException.ThrowIfNull(scroll);
        List<VirtualKeyShort> mods = withControl ? [VirtualKeyShort.CONTROL] : [];
        var injected = new List<VirtualKeyShort>();
        var everInjected = new HashSet<VirtualKeyShort>();
        SendChecked(
            expectedPid,
            expectedRoot,
            foreground,
            focus,
            () =>
            {
                ChordDown(mods, k => { press(k); everInjected.Add(k); }, injected);
                scroll();
            },
            () => ChordUp(injected, release),
            noModifierHeld,
            () => everInjected.Count == 0 || ModifiersReleased(mods.Where(everInjected.Contains)),
            () => ReleaseModifiers(mods.Where(everInjected.Contains)));
    }

    // Physical typing into a focused element of the app, checked before
    // every character so a focus loss mid-string sends nothing further.
    internal static void Type(AutomationElement target, string text)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(text);
        TypeChecked(
            target.Properties.ProcessId.Value,
            ExpectedRoot(target),
            text,
            ForegroundProbe,
            () => ReadFocus(target),
            ch => Keyboard.Type(ch.ToString()),
            () => ModifiersReleased(AllModifiers),
            ch => ModifiersReleased(TypedModifiers(ch)),
            ch => ReleaseModifiers(TypedModifiers(ch)));
    }

    // The modifiers Keyboard.Type presses for one character: FlaUI maps a
    // character through VkKeyScan and holds the shift state its high byte
    // names (1 Shift, 2 Ctrl, 4 Alt); a character with no mapping goes
    // out as Unicode with no modifier. Only these are the funnel's own
    // for that character (§28 R2-F2).
    internal static VirtualKeyShort[] TypedModifiers(char ch) => TypedModifiers(Native.VkKeyScanW(ch), ch);

    internal static VirtualKeyShort[] TypedModifiers(short scan, char ch)
    {
        if (scan == -1 || ch > 0xFE)
        {
            return [];
        }

        int high = (scan >> 8) & 0xFF;
        var mods = new List<VirtualKeyShort>();
        if ((high & 1) != 0)
        {
            mods.Add(VirtualKeyShort.SHIFT);
        }

        if ((high & 2) != 0)
        {
            mods.Add(VirtualKeyShort.CONTROL);
        }

        if ((high & 4) != 0)
        {
            mods.Add(VirtualKeyShort.ALT);
        }

        return [.. mods];
    }

    internal static void TypeChecked(
        int expectedPid,
        nint expectedRoot,
        string text,
        Func<(nint Root, int Pid)> foreground,
        Func<FocusRead> focus,
        Action<char> sendChar,
        Func<bool> noModifierHeld,
        Func<char, bool> modifiersReleased,
        Action<char> releaseModifiers)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(sendChar);
        ArgumentNullException.ThrowIfNull(modifiersReleased);
        ArgumentNullException.ThrowIfNull(releaseModifiers);
        foreach (char ch in text)
        {
            // Keyboard.Type sends a character's down and up together, so
            // the key-up half is empty; cleanup covers only the modifiers
            // this character's injection uses.
            SendChecked(expectedPid, expectedRoot, foreground, focus, () => sendChar(ch), () => { }, noModifierHeld, () => modifiersReleased(ch), () => releaseModifiers(ch));
        }
    }

    static void Send(AutomationElement target, VirtualKeyShort key, bool withControl, bool withShift, bool withAlt)
    {
        var mods = new List<VirtualKeyShort>();
        if (withControl)
        {
            mods.Add(VirtualKeyShort.CONTROL);
        }

        if (withShift)
        {
            mods.Add(VirtualKeyShort.SHIFT);
        }

        if (withAlt)
        {
            mods.Add(VirtualKeyShort.ALT);
        }

        // Keyboard.Press is key-down only and Keyboard.Release key-up
        // only, so the chord is down (modifiers, then the key) and up
        // (the key, then the modifiers in reverse). Partial-send recovery
        // (D00 T02 §36 item 6): only keys whose key-down went out
        // are released, in reverse, so a sender failing mid-chord never
        // sends a key-up for a key the operator holds.
        var chord = new List<VirtualKeyShort>(mods) { key };
        var injected = new List<VirtualKeyShort>();
        var everInjected = new HashSet<VirtualKeyShort>();
        SendChecked(
            target.Properties.ProcessId.Value,
            ExpectedRoot(target),
            ForegroundProbe,
            () => ReadFocus(target),
            () => ChordDown(chord, k => { Keyboard.Press(k); everInjected.Add(k); }, injected),
            () => ChordUp(injected, Keyboard.Release),
            () => ModifiersReleased(AllModifiers),
            () => ModifiersReleased(mods.Where(everInjected.Contains)),
            () => ReleaseModifiers(mods.Where(everInjected.Contains)),
            () => Native.IsWindow(ExpectedRoot(target)));
    }

    // Presses each key in order and records it once its key-down went out;
    // a throwing press stops the chord with only the sent keys recorded.
    internal static void ChordDown(IReadOnlyList<VirtualKeyShort> keys, Action<VirtualKeyShort> press, List<VirtualKeyShort> injected)
    {
        ArgumentNullException.ThrowIfNull(keys);
        ArgumentNullException.ThrowIfNull(press);
        ArgumentNullException.ThrowIfNull(injected);
        foreach (var k in keys)
        {
            press(k);
            injected.Add(k);
        }
    }

    // Releases exactly the injected keys, last first, and forgets them.
    // Cleanup failures are owned (D00 T02 §43 item 3): a release that
    // throws never stops the others (each key gets its attempt, so a
    // bounded pass releases what it can), and the keys it could not
    // release are named in the failure, so a stuck key is reported, never
    // silent. The pass needs no window, so a target closing during
    // recovery changes nothing.
    internal static void ChordUp(List<VirtualKeyShort> injected, Action<VirtualKeyShort> release)
    {
        ArgumentNullException.ThrowIfNull(injected);
        ArgumentNullException.ThrowIfNull(release);
        var stuck = new List<string>();
        for (int i = injected.Count - 1; i >= 0; i--)
        {
            try
            {
                release(injected[i]);
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                stuck.Add($"{injected[i]} ({ex.GetType().Name}: {ex.Message})");
            }
        }

        injected.Clear();
        if (stuck.Count > 0)
        {
            throw new InvalidOperationException($"input cleanup failed: key(s) left down after their release threw: {string.Join(", ", stuck)}");
        }
    }

    // What the UIA focus probe read: the focused element's pid (null when
    // nothing resolved) and whether it is the press's focus target.
    internal readonly record struct FocusRead(int? Pid, bool OnTarget);

    // The checked core. Pure over its probes so tests can plant a focus
    // loss, a same-process wrong window, a wrong focused control, an
    // operator-held modifier, a focus change between key-down and
    // key-up, a throwing sender, or a stuck modifier, and prove no key
    // escapes, no key stays down, and no modifier the operator holds is
    // released.
    internal static void SendChecked(
        int expectedPid,
        nint expectedRoot,
        Func<(nint Root, int Pid)> foreground,
        Func<FocusRead> focus,
        Action keyDown,
        Action keyUp,
        Func<bool> noModifierHeld,
        Func<bool> modifiersReleased,
        Action releaseModifiers,
        Func<bool>? targetAlive = null)
    {
        ArgumentNullException.ThrowIfNull(foreground);
        ArgumentNullException.ThrowIfNull(focus);
        ArgumentNullException.ThrowIfNull(keyDown);
        ArgumentNullException.ThrowIfNull(keyUp);
        ArgumentNullException.ThrowIfNull(noModifierHeld);
        ArgumentNullException.ThrowIfNull(modifiersReleased);
        ArgumentNullException.ThrowIfNull(releaseModifiers);
        if (expectedRoot == 0)
        {
            throw new InvalidOperationException("input precondition failed, key not sent: the target's window identity did not resolve");
        }

        var deadline = DateTime.UtcNow + PreconditionWait;
        while (true)
        {
            var fg = foreground();
            var f = focus();
            bool held = !noModifierHeld();
            if (Bound(fg, f, expectedPid, expectedRoot) && !held)
            {
                break;
            }

            if (DateTime.UtcNow >= deadline)
            {
                // A modifier down before the press is the operator's (or
                // another tool's): the funnel reports it and never
                // releases it.
                throw new InvalidOperationException(
                    "input precondition failed, key not sent: " + (Bound(fg, f, expectedPid, expectedRoot)
                        ? "a modifier is already held (not the funnel's; left as it is)"
                        : Describe(fg, f, expectedPid, expectedRoot)));
            }

            Thread.Sleep(50);
        }

        // Past the precondition no modifier was down. Cleanup touches only
        // the funnel's own modifiers (the chord's, or every modifier for
        // typed text): one the operator presses mid-injection outside
        // that set is never released (§28 R1-F2).
        // Between key-down and key-up the press may legitimately move
        // focus inside the app (Ctrl+T focuses the new tab's editor,
        // Ctrl+Shift+N opens the app's second window), so the interruption
        // check is input ownership leaving the app process, not the
        // pre-press focus target (§28 R1-F4).
        string? interrupted = null;
        try
        {
            try
            {
                keyDown();
                var fg = foreground();
                var f = focus();
                // A press that closes the target window (Ctrl+W on the
                // last tab, Ctrl+Shift+W) hands input to another process
                // by design; only a departure while the window lives is
                // an interruption (§28 R3-F2).
                if ((fg.Pid != expectedPid || f.Pid != expectedPid) && (targetAlive?.Invoke() ?? true))
                {
                    interrupted = Describe(fg, f, expectedPid, expectedRoot);
                }
            }
            finally
            {
                // Always: a key left down outlives the test.
                keyUp();
            }
        }
        catch
        {
            // A sender that dies mid-chord must not leave a modifier down
            // for whatever the operator types next; the original failure
            // still propagates.
            if (!modifiersReleased())
            {
                releaseModifiers();
            }

            throw;
        }

        if (!modifiersReleased())
        {
            releaseModifiers();
            throw new InvalidOperationException("input cleanup failed: a modifier stayed down after the press (released now)");
        }

        if (interrupted is not null)
        {
            throw new InvalidOperationException($"chord interrupted between key-down and key-up, aborted after the key-up: {interrupted}");
        }
    }

    static bool Bound((nint Root, int Pid) fg, FocusRead f, int expectedPid, nint expectedRoot) =>
        fg.Root == expectedRoot && fg.Pid == expectedPid && f.Pid == expectedPid && f.OnTarget;

    static string Describe((nint Root, int Pid) fg, FocusRead f, int expectedPid, nint expectedRoot) =>
        $"foreground root 0x{fg.Root:X} belongs to pid {fg.Pid} ({ProcessName(fg.Pid)}), "
        + $"focused element pid {f.Pid?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "none"}"
        + (f.Pid == expectedPid && !f.OnTarget ? " (not the focus target)" : string.Empty)
        + $", target window 0x{expectedRoot:X} in app pid {expectedPid}";

    // The target's window identity: the nearest element with a native
    // window, folded to its root owner the same way the foreground is.
    static nint ExpectedRoot(AutomationElement target)
    {
        try
        {
            var walker = target.Automation.TreeWalkerFactory.GetControlViewWalker();
            AutomationElement? el = target;
            while (el is not null)
            {
                nint h = el.Properties.NativeWindowHandle.ValueOrDefault;
                if (h != 0)
                {
                    return Native.GetAncestor(h, GaRootOwner);
                }

                el = walker.GetParent(el);
            }
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            return 0;
        }

        return 0;
    }

    const uint GaRootOwner = 3;

    // The focus target: a window target accepts any focused element (the
    // foreground root check already binds the press to that window); an
    // element target (the editor, a named field, a modal) requires the
    // focused element to be the target or inside it.
    static FocusRead ReadFocus(AutomationElement target)
    {
        try
        {
            var focused = target.Automation.FocusedElement();
            if (focused is null)
            {
                return new FocusRead(null, false);
            }

            int pid = focused.Properties.ProcessId.ValueOrDefault;
            if (target is Window || target.ControlType == FlaUI.Core.Definitions.ControlType.Window)
            {
                return new FocusRead(pid, true);
            }

            var walker = target.Automation.TreeWalkerFactory.GetRawViewWalker();
            AutomationElement? el = focused;
            for (int depth = 0; el is not null && depth < 64; depth++)
            {
                if (el.Equals(target))
                {
                    return new FocusRead(pid, true);
                }

                el = walker.GetParent(el);
            }

            return new FocusRead(pid, false);
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            return new FocusRead(null, false);
        }
    }

    static string ProcessName(int pid)
    {
        try
        {
            using var p = System.Diagnostics.Process.GetProcessById(pid);
            return p.ProcessName;
        }
        catch (ArgumentException)
        {
            return "gone";
        }
        catch (InvalidOperationException)
        {
            return "gone";
        }
    }

    static (nint Root, int Pid) RealForeground()
    {
        nint fg = Native.GetForegroundWindow();
        nint root = fg == 0 ? 0 : Native.GetAncestor(fg, GaRootOwner);
        _ = Native.GetWindowThreadProcessId(root == 0 ? fg : root, out uint pid);
        return (root, (int)pid);
    }

    static readonly VirtualKeyShort[] AllModifiers = [VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.ALT];

    static bool ModifiersReleased(IEnumerable<VirtualKeyShort> keys) =>
        keys.All(k => (Native.GetAsyncKeyState((int)k) & 0x8000) == 0);

    static void ReleaseModifiers(IEnumerable<VirtualKeyShort> keys)
    {
        foreach (var k in keys)
        {
            if ((Native.GetAsyncKeyState((int)k) & 0x8000) != 0)
            {
                Keyboard.Release(k);
            }
        }
    }

    static class Native
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetForegroundWindow();

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetAncestor(nint hwnd, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern short VkKeyScanW(char ch);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(nint hwnd);
    }

    // Appends text through ValuePattern: no focus, no keystrokes. For
    // dirtying documents and seeding content, not for testing typing.
    internal static void AppendText(TextBox box, string text)
    {
        ArgumentNullException.ThrowIfNull(box);
        ArgumentNullException.ThrowIfNull(text);
        box.Text = (box.Text ?? string.Empty) + text;
        Thread.Sleep(200);
    }

    // Invokes a menu item through UIA patterns on a background window: no
    // Focus (spiked 2026-09-17: Invoke dispatches unfocused) and no click
    // fallback. Items without Invoke support cannot run unfocused; their
    // tests stay fenced.
    internal static void InvokeMenuItem(Window window, string topId, string itemId)
    {
        ArgumentNullException.ThrowIfNull(window);
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Xunit.Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        var item = RetryFind(window, itemId);
        Xunit.Assert.NotNull(item);
        Xunit.Assert.True(item.Patterns.Invoke.IsSupported, $"menu item {itemId} has no Invoke pattern; its test cannot run unfocused");
        item.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(400);
    }

    // Selects all text through TextPattern: the focus-free Ctrl+A.
    internal static void SelectAllText(TextBox box)
    {
        ArgumentNullException.ThrowIfNull(box);
        var text = box.Patterns.Text.PatternOrDefault;
        Xunit.Assert.NotNull(text);
        text.DocumentRange.Select();
        Thread.Sleep(200);
    }

    // Collapses an expanded menu or combo: the focus-free Escape.
    internal static void Collapse(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        var expand = element.Patterns.ExpandCollapse.PatternOrDefault;
        Xunit.Assert.NotNull(expand);
        expand.Collapse();
        Thread.Sleep(200);
    }

    static AutomationElement? RetryFind(Window window, string automationId)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            var found = window.FindFirstDescendant(cf => cf.ByAutomationId(automationId));
            if (found is not null)
            {
                return found;
            }

            Thread.Sleep(250);
        }

        return null;
    }
}
