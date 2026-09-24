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
// window never escapes.
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
            () => FocusedPid(target),
            ch => Keyboard.Type(ch.ToString()),
            ModifiersReleased,
            ReleaseModifiers);
    }

    internal static void TypeChecked(
        int expectedPid,
        nint expectedRoot,
        string text,
        Func<(nint Root, int Pid)> foreground,
        Func<int?> focusedPid,
        Action<char> sendChar,
        Func<bool> modifiersReleased,
        Action releaseModifiers)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(sendChar);
        foreach (char ch in text)
        {
            SendChecked(expectedPid, expectedRoot, foreground, focusedPid, () => sendChar(ch), modifiersReleased, releaseModifiers);
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

        SendChecked(
            target.Properties.ProcessId.Value,
            ExpectedRoot(target),
            ForegroundProbe,
            () => FocusedPid(target),
            () =>
            {
                if (mods.Count > 0)
                {
                    using (Keyboard.Pressing(mods.ToArray()))
                    {
                        Keyboard.Press(key);
                    }
                }
                else
                {
                    Keyboard.Press(key);
                }
            },
            ModifiersReleased,
            ReleaseModifiers);
    }

    // The checked core. Pure over its probes so tests can plant a focus
    // loss, a same-process wrong window, a throwing sender, or a stuck
    // modifier and prove no key escapes and no modifier outlives the call.
    internal static void SendChecked(
        int expectedPid,
        nint expectedRoot,
        Func<(nint Root, int Pid)> foreground,
        Func<int?> focusedPid,
        Action send,
        Func<bool> modifiersReleased,
        Action releaseModifiers)
    {
        ArgumentNullException.ThrowIfNull(foreground);
        ArgumentNullException.ThrowIfNull(focusedPid);
        ArgumentNullException.ThrowIfNull(send);
        ArgumentNullException.ThrowIfNull(modifiersReleased);
        ArgumentNullException.ThrowIfNull(releaseModifiers);
        if (expectedRoot == 0)
        {
            throw new InvalidOperationException("input precondition failed, key not sent: the target's window identity did not resolve");
        }

        var deadline = DateTime.UtcNow + PreconditionWait;
        (nint Root, int Pid) fg;
        int? focus;
        while (true)
        {
            fg = foreground();
            focus = focusedPid();
            if (fg.Root == expectedRoot && fg.Pid == expectedPid && focus == expectedPid)
            {
                break;
            }

            if (DateTime.UtcNow >= deadline)
            {
                throw new InvalidOperationException(
                    $"input precondition failed, key not sent: foreground root 0x{fg.Root:X} belongs to pid {fg.Pid} "
                    + $"({ProcessName(fg.Pid)}), focused element pid {focus?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "none"}, "
                    + $"target window 0x{expectedRoot:X} in app pid {expectedPid}");
            }

            Thread.Sleep(50);
        }

        try
        {
            send();
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
    }

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

    static int? FocusedPid(AutomationElement target)
    {
        try
        {
            return target.Automation.FocusedElement()?.Properties.ProcessId.ValueOrDefault;
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            return null;
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

    static bool ModifiersReleased() =>
        (Native.GetAsyncKeyState(0x11) & 0x8000) == 0
        && (Native.GetAsyncKeyState(0x10) & 0x8000) == 0
        && (Native.GetAsyncKeyState(0x12) & 0x8000) == 0;

    static void ReleaseModifiers()
    {
        Keyboard.Release(VirtualKeyShort.CONTROL);
        Keyboard.Release(VirtualKeyShort.SHIFT);
        Keyboard.Release(VirtualKeyShort.ALT);
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
