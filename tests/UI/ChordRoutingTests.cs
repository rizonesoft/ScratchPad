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
            // Expectations per surface come from the routing oracle in
            // docs/ui-input-audit.md (D00 T02 §36 item 4).
            var oracle = BindingManifest.SubTable(File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "docs", "ui-input-audit.md")), "Routing oracle", 6, out var parse);
            Assert.Empty(parse);
            int tabs = 1;

            // Editor.
            var box = ContentBox(window);
            box.Focus();
            Thread.Sleep(200);
            UiInput.PressKey(box, VirtualKeyShort.KEY_T, withControl: true);
            tabs = ExpectRouting(window, oracle, "editor", tabs);

            // Tab strip.
            var tab = TabItems(window)[0];
            tab.Focus();
            Thread.Sleep(200);
            UiInput.PressKey(tab, VirtualKeyShort.KEY_T, withControl: true);
            tabs = ExpectRouting(window, oracle, "tab strip", tabs);

            // Open menu, and the menu closes cleanly afterwards.
            var file = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
            Assert.NotNull(file);
            file.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(600);
            UiInput.PressKey(window, VirtualKeyShort.KEY_T, withControl: true);
            tabs = ExpectRouting(window, oracle, "open menu", tabs);
            UiInput.PressKey(window, VirtualKeyShort.ESCAPE);
            Thread.Sleep(400);

            // Modal dialog.
            UiInput.InvokeMenuItem(window, "MenuTools", "MenuToolsStats");
            var modal = Retry.WhileNull(
                () => window.FindFirstDescendant(cf => cf.ByAutomationId("StatsDialog")),
                TimeSpan.FromSeconds(10),
                TimeSpan.FromMilliseconds(250)).Result;
            Assert.NotNull(modal);
            UiInput.PressKey(modal, VirtualKeyShort.KEY_T, withControl: true);
            _ = ExpectRouting(window, oracle, "modal", tabs);
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

    // D00 T02 §36 item 4 (R1-F4): every live chord's routing is proved on
    // every surface against the oracle, not only Ctrl+T's. Observe mode
    // (DispatchLogScope) suppresses every bound command and logs each
    // dispatch, so each chord is pressed on the editor, a tab-strip item,
    // an open menu, and a modal dialog (What's New, shown at launch) with
    // no command's side effects, and the log says whether it reached its
    // command. Mismatches are collected so one run names them all.
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void EveryLiveChordRoutesPerTheOracle()
    {
        var oracle = BindingManifest.SubTable(File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "docs", "ui-input-audit.md")), "Routing oracle", 6, out var parse);
        Assert.Empty(parse);
        var live = oracle.Where(r => r[2] != "n/a").Select(r => (Chord: r[0], Command: System.Text.RegularExpressions.Regex.Match(r[1], "`([^`]+)`").Groups[1].Value)).ToList();
        Assert.NotEmpty(live);
        var mismatches = new List<string>();
        using var log = new DispatchLogScope();

        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using (var app = UiLaunch.LaunchApp())
        using (var automation = new UIA3Automation())
        {
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                window.Focus();
                Thread.Sleep(300);
                var box = ContentBox(window);
                foreach (var (chord, command) in live)
                {
                    box.Focus();
                    Thread.Sleep(150);
                    Observe(app, log, oracle, chord, command, "editor", () => PressChord(box, chord), mismatches);
                }

                foreach (var (chord, command) in live)
                {
                    var tab = TabItems(window)[0];
                    tab.Focus();
                    Thread.Sleep(150);
                    Observe(app, log, oracle, chord, command, "tab strip", () => PressChord(tab, chord), mismatches);
                }

                foreach (var (chord, command) in live)
                {
                    var file = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
                    Assert.NotNull(file);
                    if (file.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState != ExpandCollapseState.Expanded)
                    {
                        file.Patterns.Invoke.Pattern.Invoke();
                        Thread.Sleep(500);
                    }

                    Observe(app, log, oracle, chord, command, "open menu", () => PressChord(window, chord), mismatches);
                }

                var menu = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
                if (menu?.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState == ExpandCollapseState.Expanded)
                {
                    UiInput.PressKey(window, VirtualKeyShort.ESCAPE);
                }
            }
            finally
            {
                if (!app.HasExited)
                {
                    app.Kill();
                }
            }
        }

        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = false });
        using (var app = UiLaunch.LaunchApp())
        using (var automation = new UIA3Automation())
        {
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                window.Focus();
                var modal = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("WhatsNewDialog")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(modal);
                foreach (var (chord, command) in live)
                {
                    Observe(app, log, oracle, chord, command, "modal", () => PressChord(modal, chord), mismatches);
                }
            }
            finally
            {
                if (!app.HasExited)
                {
                    app.Kill();
                }
            }
        }

        Assert.Empty(mismatches);
    }

    static void Observe(FlaUI.Core.Application app, DispatchLogScope log, List<string[]> oracle, string chord, string command, string surface, Action press, List<string> mismatches)
    {
        _ = log.Next(TimeSpan.Zero);
        int windowsBefore = WindowCount(app);
        press();
        string[] fresh = log.Next(TimeSpan.FromMilliseconds(500));
        // A failed dispatch-log write ends the app (§36 R2-F2): lost
        // evidence fails here instead of reading as a suppressed chord.
        Assert.False(app.HasExited, $"the app exited after {chord} on {surface}: a dispatch-log write failed, so the routing evidence is lost");
        // Negative routing needs zero dispatch and unchanged state (D00 T02
        // §51 item 3), judged by the one rule the pure fixture pins.
        string want = BindingManifest.RoutingExpectation(oracle, chord, command, surface);
        string? problem = BindingMutation.RoutingProblem(chord, command, surface, want, fresh, windowsBefore, WindowCount(app));
        if (problem is not null)
        {
            mismatches.Add(problem);
        }
    }

    // The app's top-level window count, read from outside (§51 item 3).
    static int WindowCount(FlaUI.Core.Application app)
    {
        using var automation = new FlaUI.UIA3.UIA3Automation();
        return app.GetAllTopLevelWindows(automation).Length;
    }

    // Presses a declared chord (letters, digits, Tab) into a target.
    static void PressChord(FlaUI.Core.AutomationElements.AutomationElement target, string chord)
    {
        var (vk, mods) = BindingMutation.VirtualKeyOf(chord);
        var key = vk == 9 ? VirtualKeyShort.TAB : (VirtualKeyShort)vk;
        UiInput.PressKey(target, key, withControl: (mods & 1) != 0, withShift: (mods & 4) != 0, withAlt: (mods & 2) != 0);
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
        var installed = InstalledLayouts();
        bool preloaded = installed.Contains(GermanHkl());
        bool usPreloaded = installed.Contains(UsHkl());
        nint german = Native.LoadKeyboardLayoutW("00000407", KlfNoTellShell);
        Assert.NotEqual(0, german);
        nint us = Native.LoadKeyboardLayoutW("00000409", KlfNoTellShell);
        Assert.NotEqual(0, us);
        try
        {
            window.Focus();
            Thread.Sleep(300);

            // US English, Shift-dependent plus (layout matrix, D00 T02 §36
            // item 3): under layout 00000409, switched to and verified
            // (§36 R3-F2), Ctrl+Shift+OEM_PLUS reaches no command while zoom
            // ships disabled, so the editor text holds.
            SwitchLayout(hwnd, thread, us);
            var usBox = ContentBox(window);
            usBox.Focus();
            Thread.Sleep(200);
            string usBefore = usBox.Text ?? string.Empty;
            UiInput.PressKey(usBox, VirtualKeyShort.OEM_PLUS, withControl: true, withShift: true);
            Thread.Sleep(600);
            Assert.Equal(usBefore, usBox.Text ?? string.Empty);
            window.Focus();
            Thread.Sleep(200);
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

            // NumPad plus and minus (the zoom declarations bind VirtualKey
            // Add and Subtract, NumPad only; main-row parity is owed by
            // D02 T01 §5): with zoom still disabled the chords reach no
            // command, so the editor text and the tab count hold.
            string before = box.Text ?? string.Empty;
            UiInput.PressKey(box, VirtualKeyShort.ADD, withControl: true);
            UiInput.PressKey(box, VirtualKeyShort.SUBTRACT, withControl: true);
            Thread.Sleep(600);
            Assert.Equal(before, box.Text ?? string.Empty);
            Assert.Equal(3, TabItems(window).Count);

            // Labels under the layout: the displayed shortcut text is the
            // manifest's, unchanged from US English.
            Assert.Equal(BindingManifest.ExpectedLabel(BindingManifest.ParseChord("Ctrl+S")), MenuAccelerator(window, "MenuFile", null, "MenuFileSave"));
            Assert.Equal(BindingManifest.ExpectedLabel(BindingManifest.ParseChord("Ctrl+Add")), MenuAccelerator(window, "MenuView", "MenuViewZoom", "MenuViewZoomIn"));
            Assert.Equal(BindingManifest.ExpectedLabel(BindingManifest.ParseChord("Ctrl+Subtract")), MenuAccelerator(window, "MenuView", "MenuViewZoom", "MenuViewZoomOut"));
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

                if (!usPreloaded)
                {
                    _ = Native.UnloadKeyboardLayout(us);
                }

                if (!app.HasExited)
                {
                    app.Kill();
                }
            }
        }
    }

    // One Ctrl+T press's outcome against the oracle: execute adds a tab,
    // suppress leaves the count; returns the count now expected.
    static int ExpectRouting(Window window, List<string[]> oracle, string surface, int before)
    {
        string want = BindingManifest.RoutingExpectation(oracle, "Ctrl+T", "Tabs.NewTab", surface);
        Assert.True(want is "execute" or "suppress", $"the routing oracle has no Ctrl+T outcome on {surface} (read '{want}')");
        if (want == "execute")
        {
            Assert.Equal(before + 1, WaitForTabCount(window, before + 1));
            return before + 1;
        }

        Thread.Sleep(800);
        Assert.Equal(before, TabItems(window).Count);
        return before;
    }

    const uint KlfNoTellShell = 0x80;
    const uint WmInputLangChangeRequest = 0x0050;

    static nint GermanHkl() => unchecked((nint)0x04070407);

    static nint UsHkl() => unchecked((nint)0x04090409);

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

    // Opens the menu (and submenu) by Invoke, reads the item's displayed
    // shortcut text, and closes with Escape through the funnel.
    static string MenuAccelerator(Window window, string topId, string? subId, string itemId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        if (subId is not null)
        {
            var sub = Retry.WhileNull(() => window.FindFirstDescendant(cf => cf.ByAutomationId(subId)), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(250)).Result;
            Assert.NotNull(sub);
            sub.Patterns.ExpandCollapse.Pattern.Expand();
            Thread.Sleep(600);
        }

        var item = Retry.WhileNull(() => window.FindFirstDescendant(cf => cf.ByAutomationId(itemId)), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(item);
        string text = item.Properties.AcceleratorKey.ValueOrDefault ?? string.Empty;
        UiInput.PressKey(window, VirtualKeyShort.ESCAPE);
        if (subId is not null)
        {
            UiInput.PressKey(window, VirtualKeyShort.ESCAPE);
        }

        Thread.Sleep(400);
        return text;
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
