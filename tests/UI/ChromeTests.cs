using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §27: tab-strip chrome geometry. A full strip parks the add button
// left of the caption buttons (probed overlap: the add center sat 67 DIP
// inside the caption zone, tucked under maximize), and the zero-tab strip
// centers the add button (probed top-hugged, 17px above strip center).
[Collection("UI tests")]
public sealed class ChromeTests
{
    [Fact]
    public void FullStripParksAddButtonLeftOfCaption()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Continue });
        var tabs = new List<SessionTab>();
        for (int i = 0; i < 12; i++)
        {
            tabs.Add(new SessionTab { Content = $"dirty {i}", Caret = 0 });
        }

        new SessionData { Windows = [new SessionWindow { Tabs = tabs }] }.Save();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal(12, WaitForTabCount(window, 12));
            double addRight = 0;
            double minLeft = 0;
            var settled = Retry.While(
                () =>
                {
                    var add = FindButton(window, "Add New Tab");
                    var min = FindButton(window, "Minimize");
                    if (add is null || min is null)
                    {
                        return false;
                    }

                    addRight = add.BoundingRectangle.Right;
                    minLeft = min.BoundingRectangle.Left;
                    return addRight <= minLeft;
                },
                settled => !settled,
                TimeSpan.FromSeconds(10),
                TimeSpan.FromMilliseconds(250));
            Assert.True(settled.Result, $"add right {addRight} overlaps caption at {minLeft}");
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void ZeroTabsCentersAddButton()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            Assert.Equal(1, WaitForTabCount(window, 1));
            Press(window, VirtualKeyShort.KEY_W, withControl: true);
            Assert.Equal(0, WaitForTabCount(window, 0));
            double delta = 0;
            var centered = Retry.While(
                () =>
                {
                    var add = FindButton(window, "Add New Tab");
                    var region = FindById(window, "TabRegion");
                    if (add is null || region is null)
                    {
                        return false;
                    }

                    delta = Math.Abs(add.BoundingRectangle.Center().Y - region.BoundingRectangle.Center().Y);
                    return delta <= 8;
                },
                centered => !centered,
                TimeSpan.FromSeconds(10),
                TimeSpan.FromMilliseconds(250));
            Assert.True(centered.Result, $"add off strip center by {delta}px");
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250));
        return result.Result;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static void Press(Window window, VirtualKeyShort key, bool withControl)
    {
        window.Focus();
        Thread.Sleep(150);
        using (Keyboard.Pressing(VirtualKeyShort.CONTROL))
        {
            Keyboard.Press(key);
        }

        Thread.Sleep(250);
    }

    static Application LaunchApp()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"app missing at {appPath}");
        return Application.Launch(appPath);
    }

    static void SeedSettings(ShellSettings settings)
    {
        settings.Save();
        SessionData.Delete();
    }

    static AutomationElement? FindById(AutomationElement window, string id)
    {
        return Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId(id)),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static Button? FindButton(AutomationElement scope, string name)
    {
        return Retry.WhileNull(
            () => scope.FindAllDescendants(cf => cf.ByControlType(ControlType.Button)).FirstOrDefault(button => button.Name == name)?.AsButton(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
    }

    static void CloseApp(Application app, Window? window)
    {
        try
        {
            window?.Close();
        }
        catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
        {
            // Already gone; the exit wait below is the real assertion.
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!app.HasExited)
        {
            app.Kill();
        }

        Assert.True(app.HasExited, "app did not exit after Close");
    }
}
