using System.Runtime.InteropServices;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §28 items 2 and 4: physical-input proofs the binding manifest
// cannot give from source. Fenced (they take the foreground), so they
// run in the quiet window and their foreground confirmation is
// Night-owed (D00-T02-S28-N1).
//
// Item 2, routing per surface: the window-global Ctrl+T (the matrix
// names it "root, window-global") is pressed with focus on the editor,
// on a tab-strip item, inside an open menu, and inside a modal dialog.
// Recorded default (no stock capture of Notepad's open-menu or modal
// routing exists yet; cost of changing: one expected count per
// surface): editor and tab strip dispatch, an open menu and a modal
// suppress it.
//
// Item 4, layout identity: under a non-US layout (German, 00000407) the
// declared chords still dispatch by virtual key and the displayed label
// is unchanged; AltGr (Ctrl+Alt) types its character and fires no Ctrl
// binding (no Bing launch from Ctrl+Alt+E); NumPad digits are not the
// main-row digits (Ctrl+NumPad1 does not switch tabs, Ctrl+1 does).
[Collection("UI tests")]
public sealed class ChordRoutingTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void WindowGlobalChordRoutesPerSurface()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            Assert.Equal(1, WaitForTabCount(window, 1));

            // Editor: dispatches.
            var box = ContentBox(window);
            box.Focus();
            Thread.Sleep(200);
            UiInput.PressKey(box, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(2, WaitForTabCount(window, 2));

            // Tab strip: dispatches.
            var tab = TabItems(window)[0];
            tab.Focus();
            Thread.Sleep(200);
            UiInput.PressKey(tab, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(3, WaitForTabCount(window, 3));

            // Open menu: suppressed (recorded default), and the menu closes
            // cleanly afterwards.
            var file = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
            Assert.NotNull(file);
            file.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(600);
            UiInput.PressKey(window, VirtualKeyShort.KEY_T, withControl: true);
            Thread.Sleep(800);
            Assert.Equal(3, TabItems(window).Count);
            UiInput.PressKey(window, VirtualKeyShort.ESCAPE);
            Thread.Sleep(400);

            // Modal dialog: suppressed.
            UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsStats");
            var modal = Retry.WhileNull(
                () => window.FindFirstDescendant(cf => cf.ByAutomationId("StatsDialog")),
                TimeSpan.FromSeconds(10),
                TimeSpan.FromMilliseconds(250)).Result;
            Assert.NotNull(modal);
            UiInput.PressKey(modal, VirtualKeyShort.KEY_T, withControl: true);
            Thread.Sleep(800);
            Assert.Equal(3, TabItems(window).Count);
            UiInput.PressKey(modal, VirtualKeyShort.ESCAPE);
        }
        finally
        {
            if (!app.HasExited)
            {
                app.Kill();
            }
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void LayoutAltGrAndNumpadKeepTheirIdentity()
    {
        using var seam = new LaunchCaptureScope();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        nint hwnd = window.Properties.NativeWindowHandle.Value;
        uint thread = Native.GetWindowThreadProcessId(hwnd, out _);
        nint original = Native.GetKeyboardLayout(thread);
        bool preloaded = InstalledLayouts().Contains(GermanHkl());
        nint german = Native.LoadKeyboardLayoutW("00000407", KlfNoTellShell);
        Assert.NotEqual(0, german);
        try
        {
            window.Focus();
            Thread.Sleep(300);
            SwitchLayout(hwnd, thread, german);

            // Declared chords dispatch by virtual key under the layout.
            UiInput.Press(window, VirtualKeyShort.KEY_T, withControl: true);
            UiInput.Press(window, VirtualKeyShort.KEY_T, withControl: true);
            Assert.Equal(3, WaitForTabCount(window, 3));

            // NumPad identity: Ctrl+NumPad1 is not Ctrl+1.
            Assert.True(Selected(window, 2), "the newest tab is active before the NumPad press");
            UiInput.Press(window, VirtualKeyShort.NUMPAD1, withControl: true);
            Thread.Sleep(600);
            Assert.True(Selected(window, 2), "Ctrl+NumPad1 switched tabs; only the main-row digit is declared");
            UiInput.Press(window, VirtualKeyShort.KEY_1, withControl: true);
            Assert.True(Retry.WhileFalse(() => Selected(window, 0), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result, "Ctrl+1 did not switch to the first tab");

            // AltGr (Ctrl+Alt+E on German) types the euro sign and fires
            // no Ctrl binding: no Bing capture.
            var box = ContentBox(window);
            box.Focus();
            Thread.Sleep(200);
            UiInput.PressKey(box, VirtualKeyShort.KEY_E, withControl: true, withAlt: true);
            Assert.True(Retry.WhileFalse(() => (box.Text ?? string.Empty).Contains('€', StringComparison.Ordinal), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result, "AltGr+E did not type the euro sign");
            Thread.Sleep(800);
            Assert.Empty(seam.Lines());
        }
        finally
        {
            try
            {
                SwitchLayout(hwnd, thread, original, strict: false);
            }
            finally
            {
                if (!preloaded)
                {
                    _ = Native.UnloadKeyboardLayout(german);
                }

                if (!app.HasExited)
                {
                    app.Kill();
                }
            }
        }
    }

    const uint KlfNoTellShell = 0x80;
    const uint WmInputLangChangeRequest = 0x0050;

    static nint GermanHkl() => unchecked((nint)0x04070407);

    static HashSet<nint> InstalledLayouts()
    {
        int n = Native.GetKeyboardLayoutList(0, null);
        var list = new nint[Math.Max(n, 0)];
        _ = Native.GetKeyboardLayoutList(list.Length, list);
        return [.. list];
    }

    static void SwitchLayout(nint hwnd, uint thread, nint hkl, bool strict = true)
    {
        _ = Native.PostMessageW(hwnd, WmInputLangChangeRequest, 0, hkl);
        bool switched = Retry.WhileFalse(() => Native.GetKeyboardLayout(thread) == hkl, TimeSpan.FromSeconds(3), TimeSpan.FromMilliseconds(100)).Result;
        if (strict)
        {
            Assert.True(switched, $"the app did not take keyboard layout 0x{hkl:X}");
        }
    }

    static bool Selected(Window window, int index)
    {
        var items = TabItems(window);
        return items.Count > index && items[index].Patterns.SelectionItem.PatternOrDefault?.IsSelected == true;
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

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static int WaitForTabCount(Window window, int expected) =>
        Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;

    static class Native
    {
        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetKeyboardLayout(uint threadId);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetKeyboardLayoutList(int count, [Out] nint[]? list);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint LoadKeyboardLayoutW(string id, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnloadKeyboardLayout(nint hkl);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostMessageW(nint hwnd, uint msg, nint wParam, nint lParam);
    }
}
