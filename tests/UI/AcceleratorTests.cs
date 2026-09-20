using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §12 item 2: restored physical-chord coverage for the six
// enabled bindings the §8 conversion left at zero suite presses.
// Each test presses the chord and asserts the dispatch; shortcut
// dispatch IS the point, so all six are fenced Interactive. Each
// test ships in the shape its Fenced quotes were taken in (the N
// test unfunnelled, the dialog tests funnel-first); Press focuses
// either way, so the split is cosmetic.
[Collection("UI tests")]
public sealed class AcceleratorTests
{
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftNOpensSecondWindow()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Pair: backgrounded+forced fails (1 window, chord never dispatches
        // off-screen); foreground-forced passes (2 windows, 2 s). Collector
        // confirmation Night-owed D00-T02-S12-N1.
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Single(app.GetAllTopLevelWindows(automation));
            UiInput.Press(window, VirtualKeyShort.KEY_N, withControl: true, withShift: true);
            Assert.Equal(2, WaitForWindowCount(app, automation, 2));
        }
        finally
        {
            CloseAll(app, automation);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftGOpensStats()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Backgrounded+forced passes (StatsDialog opens in 1 s), so this
        // fence rests on interruption (Press steals the operator
        // foreground), not on background failure. Foreground confirmation
        // Night-owed D00-T02-S12-N1.
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            Assert.NotNull(WaitForDialog(window, "StatsDialog"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftHOpensSnapshots()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Backgrounded+forced passes (SnapshotsDialog opens), so this
        // fence rests on interruption (Press steals the operator
        // foreground), not on background failure. Foreground confirmation
        // Night-owed D00-T02-S12-N1.
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_H, withControl: true, withShift: true);
            Assert.NotNull(WaitForDialog(window, "SnapshotsDialog"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftEOpensTemplates()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Pair half: backgrounded+forced fails (TemplatesDialog null).
        // Foreground confirmation Night-owed D00-T02-S12-N1 (daytime
        // forced attempts void: a TickTick setup window held OS
        // foreground through the probe series).
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_E, withControl: true, withShift: true);
            Assert.NotNull(WaitForDialog(window, "TemplatesDialog"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftXOpensExport()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Backgrounded+forced passes (ExportDialog opens), so this
        // fence rests on interruption (Press steals the operator
        // foreground), not on background failure. Foreground confirmation
        // Night-owed D00-T02-S12-N1.
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_X, withControl: true, withShift: true);
            Assert.NotNull(WaitForDialog(window, "ExportDialog"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void ChordCtrlShiftLOpensLock()
    {
        // Fenced: physical chord dispatch IS the point (D00 T02 §12).
        // Pair half: backgrounded+forced fails (LockDialog null).
        // Foreground confirmation Night-owed D00-T02-S12-N1 (daytime
        // forced attempts void: a TickTick setup window held OS
        // foreground through the probe series).
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_L, withControl: true, withShift: true);
            Assert.NotNull(WaitForDialog(window, "LockDialog"));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static AutomationElement? WaitForDialog(Window window, string automationId)
    {
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static int WaitForWindowCount(Application app, UIA3Automation automation, int expected)
    {
        SpinWait.SpinUntil(
            () => app.GetAllTopLevelWindows(automation).Length == expected,
            TimeSpan.FromSeconds(10));
        return app.GetAllTopLevelWindows(automation).Length;
    }

    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException)
        {
        }

        try
        {
            if (!app.HasExited)
            {
                app.Close();
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException)
        {
        }
    }

    static void CloseAll(Application app, UIA3Automation automation)
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

        CloseApp(app, null);
    }
}
