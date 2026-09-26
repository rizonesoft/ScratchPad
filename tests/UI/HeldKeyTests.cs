using System.Runtime.InteropServices;
using System.Text.Json;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §51 items 6, 7, 10, 12: the physical held-key proof, owed as
// its own night debt (D00-T02-S51-N1) instead of riding §36's run. A held
// one-shot chord dispatches once and a release and re-press dispatches
// again; a Shift-dependent Plus held with Ctrl reaches no command while
// zoom is disabled; a menu opening mid-chord stops the hold's repeats from
// reaching the window. Fenced: every case presses physical keys, so they
// run in the quiet window.
[Collection("UI tests")]
public sealed class HeldKeyTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void HeldCtrlTOpensOneTab()
    {
        WithWindow((app, automation, window) =>
        {
            int before = TabItems(window).Count;
            UiInput.HoldChord(window, VirtualKeyShort.KEY_T, withControl: true, repeats: 6);
            Assert.Equal(before + 1, WaitForTabCount(window, before + 1));
            Thread.Sleep(500);
            Assert.True(TabItems(window).Count == before + 1, $"a held Ctrl+T (7 key-downs) opened {TabItems(window).Count - before} tabs, not one (one-shot class, docs/ui-input-audit.md Held-key repeat classes)");
        });
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ReleaseAndRepressOpensSecondTab()
    {
        WithWindow((app, automation, window) =>
        {
            int before = TabItems(window).Count;
            UiInput.HoldChord(window, VirtualKeyShort.KEY_T, withControl: true, repeats: 3);
            UiInput.HoldChord(window, VirtualKeyShort.KEY_T, withControl: true, repeats: 3);
            Assert.Equal(before + 2, WaitForTabCount(window, before + 2));
        });
    }

    // §51 item 12: a Shift-dependent Plus during a hold. Zoom in is
    // disabled until its owner lands (the binding table), so the chord
    // reaches no command: the tab count and the title are unchanged and
    // the app is alive.
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ShiftDependentPlusDuringAHoldReachesNothingWhileZoomIsDisabled()
    {
        WithWindow((app, automation, window) =>
        {
            int before = TabItems(window).Count;
            string title = window.Title;
            UiInput.HoldChord(window, VirtualKeyShort.OEM_PLUS, withControl: true, repeats: 3, withShift: true);
            Thread.Sleep(500);
            Assert.False(app.HasExited, "the app exited after a held Ctrl+Shift+Plus");
            Assert.Equal(before, TabItems(window).Count);
            Assert.Equal(title, window.Title);
        });
    }

    // §51 item 12: a menu opening mid-chord. The first key-down of a held
    // Ctrl+T opens one tab; the File menu then opens while the chord is
    // held, and the hold's repeats reach nothing (the routing oracle's open
    // menu surface suppresses Ctrl+T, and a one-shot repeat never
    // dispatches).
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void MenuOpeningMidChordStopsTheHold()
    {
        WithWindow((app, automation, window) =>
        {
            int before = TabItems(window).Count;
            var menu = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuFile"));
            Assert.NotNull(menu);
            UiInput.HoldChord(window, VirtualKeyShort.KEY_T, withControl: true, repeats: 4, midHold: () =>
            {
                Thread.Sleep(300);
                menu.Patterns.Invoke.Pattern.Invoke();
                Thread.Sleep(300);
            });
            Thread.Sleep(500);
            Assert.True(TabItems(window).Count == before + 1, $"a menu opening mid-chord left {TabItems(window).Count - before} new tab(s), not the one the first key-down opened");
        });
    }

    // §51 item 9: a clipboard change is an enablement transition. Paste
    // is documented disabled until its owner lands, so it reads disabled
    // after the clipboard gains text. Fenced: it writes the system
    // clipboard, which the operator owns in the day.
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ClipboardChangeReadsTheDocumentedEnablement()
    {
        WithWindow((app, automation, window) =>
        {
            Assert.True(SetClipboardText("scratchpad clipboard transition"), "the clipboard could not be written");
            var edit = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEdit"));
            Assert.NotNull(edit);
            edit.Patterns.Invoke.Pattern.Invoke();
            var paste = Retry.WhileNull(() => window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEditPaste")), TimeSpan.FromSeconds(5)).Result;
            Assert.NotNull(paste);
            Assert.False(paste.IsEnabled, "Paste is documented disabled until its owner lands, but reads enabled after a clipboard change");
        });
    }

    static void WithWindow(Action<Application, UIA3Automation, Window> body)
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            body(app, automation, window);
        }
        finally
        {
            foreach (var w in app.GetAllTopLevelWindows(automation))
            {
                try
                {
                    w.Close();
                }
                catch (Exception ex) when (ex is InvalidOperationException or TimeoutException)
                {
                }
            }

            if (!app.HasExited)
            {
                app.Kill();
            }
        }
    }

    internal static List<AutomationElement> TabItems(Window window) =>
        [.. window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem))];

    static int WaitForTabCount(Window window, int expected) =>
        Retry.While(() => TabItems(window).Count, count => count != expected, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result;

    static bool SetClipboardText(string text)
    {
        if (!Native.OpenClipboard(0))
        {
            return false;
        }

        try
        {
            _ = Native.EmptyClipboard();
            byte[] bytes = System.Text.Encoding.Unicode.GetBytes(text + "\0");
            nint mem = Native.GlobalAlloc(0x0002, (nuint)bytes.Length);
            if (mem == 0)
            {
                return false;
            }

            nint at = Native.GlobalLock(mem);
            Marshal.Copy(bytes, 0, at, bytes.Length);
            _ = Native.GlobalUnlock(mem);
            if (Native.SetClipboardData(13, mem) == 0)
            {
                _ = Native.GlobalFree(mem);
                return false;
            }

            return true;
        }
        finally
        {
            _ = Native.CloseClipboard();
        }
    }

    static class Native
    {
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool OpenClipboard(nint owner);

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CloseClipboard();

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EmptyClipboard();

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern nint SetClipboardData(uint format, nint memory);

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern nint GlobalAlloc(uint flags, nuint bytes);

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern nint GlobalLock(nint memory);

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GlobalUnlock(nint memory);

        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern nint GlobalFree(nint memory);
    }
}

// D00 T02 §51 item 7: the parity capture behind the held-key repeat
// classes, owed as night debt D00-T02-S51-N2. It runs tools/CaptureBaseline
// held-keys against stock Notepad (a foreground tool, so fenced) through
// the sanctioned tool launcher and requires the table's classes to match
// what stock Notepad does: a held Ctrl+T opens one tab, and a held
// Ctrl+Tab and a held Ctrl+Plus step once per key-down.
[Collection("UI tests")]
public sealed class HeldKeyParityTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void StockNotepadHeldKeyClassesMatchTheTable()
    {
        string root = BindingManifestTests.RepoRoot();
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH") is { Length: > 0 } host && File.Exists(host) ? host : Path.Combine(root, ".tools", "dotnet-win-x64", "dotnet.exe");
        string outFile = Path.Combine(Path.GetTempPath(), $"scratchpad-held-keys-{Guid.NewGuid():N}.json");
        var (exit, output) = UiLaunch.RunToolCaptured(dotnet, $"run --project \"{Path.Combine(root, "tools", "CaptureBaseline", "CaptureBaseline.csproj")}\" -- held-keys \"{outFile}\"", TimeSpan.FromMinutes(5));
        Assert.True(exit == 0 && File.Exists(outFile), $"the stock held-key capture failed (exit {exit}): {output}");
        using var doc = JsonDocument.Parse(File.ReadAllText(outFile));
        int oneShot = doc.RootElement.GetProperty("oneShot").GetProperty("dispatches").GetInt32();
        int steps = doc.RootElement.GetProperty("tabCycle").GetProperty("steps").GetInt32();
        int Pct(string p) => int.Parse(doc.RootElement.GetProperty("zoom").GetProperty(p).GetString()!.TrimEnd('%'), System.Globalization.CultureInfo.InvariantCulture);
        var classes = BindingManifest.SubTable(File.ReadAllText(Path.Combine(root, "docs", "ui-input-audit.md")), "Held-key repeat classes", 4, out var parse);
        Assert.Empty(parse);
        string ClassOf(string command) => classes.Single(r => r[1].Contains($"`{command}`", StringComparison.Ordinal))[2];
        Assert.Equal(oneShot == 1 ? "one-shot" : "repeatable", ClassOf("Tabs.NewTab"));
        Assert.Equal(steps == 4 ? "repeatable" : "one-shot", ClassOf("Tabs.CycleNext"));
        Assert.Equal(Pct("after") - Pct("before") >= 40 ? "repeatable" : "one-shot", ClassOf("MenuViewZoomIn"));
    }
}
