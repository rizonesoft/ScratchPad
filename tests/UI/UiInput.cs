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
// (D00 T02 §21): immediately before it, the foreground window and the
// UIA-focused element must belong to the app under test, or nothing is
// sent and the test fails loud naming the thief; after it, no modifier
// may stay down. A keystroke that would land in another app (a global
// hotkey owner, a stolen foreground) never escapes.
internal static class UiInput
{
    // Foreground probe: (root HWND, owning pid). Swappable so the
    // focus-loss mutation is provable without sending real keys.
    internal static Func<(nint Hwnd, int Pid)> ForegroundProbe = RealForeground;

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
    // still binds the press to the app's process.
    internal static void PressKey(AutomationElement target, VirtualKeyShort key, bool withControl = false, bool withShift = false, bool withAlt = false)
    {
        ArgumentNullException.ThrowIfNull(target);
        Send(target, key, withControl, withShift, withAlt);
    }

    // Physical typing into a focused element of the app.
    internal static void Type(AutomationElement target, string text)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentNullException.ThrowIfNull(text);
        SendChecked(
            target.Properties.ProcessId.Value,
            ForegroundProbe,
            () => FocusedPid(target),
            () => Keyboard.Type(text),
            ModifiersReleased,
            ReleaseModifiers);
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

    // The checked core. Pure over its probes so tests can plant a
    // focus loss or a stuck modifier and prove no key escapes.
    internal static void SendChecked(
        int expectedPid,
        Func<(nint Hwnd, int Pid)> foreground,
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
        var deadline = DateTime.UtcNow + PreconditionWait;
        (nint Hwnd, int Pid) fg;
        int? focus;
        while (true)
        {
            fg = foreground();
            focus = focusedPid();
            if (fg.Hwnd != 0 && fg.Pid == expectedPid && focus == expectedPid)
            {
                break;
            }

            if (DateTime.UtcNow >= deadline)
            {
                throw new InvalidOperationException(
                    $"input precondition failed, key not sent: foreground HWND 0x{fg.Hwnd:X} belongs to pid {fg.Pid} "
                    + $"({ProcessName(fg.Pid)}), focused element pid {focus?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "none"}, "
                    + $"app pid {expectedPid}");
            }

            Thread.Sleep(50);
        }

        send();
        if (!modifiersReleased())
        {
            releaseModifiers();
            throw new InvalidOperationException("input cleanup failed: a modifier stayed down after the press (released now)");
        }
    }

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

    static (nint Hwnd, int Pid) RealForeground()
    {
        nint fg = Native.GetForegroundWindow();
        nint root = fg == 0 ? 0 : Native.GetAncestor(fg, 2);
        _ = Native.GetWindowThreadProcessId(root == 0 ? fg : root, out uint pid);
        return (root == 0 ? fg : root, (int)pid);
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
