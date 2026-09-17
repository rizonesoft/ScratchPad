using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §22: untitled tabs show the first line as their live default.
// The model rule (first-line/trim/35) is §2's shipped unit proof; these
// drives re-confirm it at the rendered surface.
[Collection("UI tests")]
public sealed class UntitledTitleTests
{
    [Fact]
    public void TypingFirstLineRenamesTab()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            WaitForTabName(window, 0, TabAccessibilityName.For("Untitled", isDirty: false));
            ContentBox(window).Text = "My first line\nsecond line";
            WaitForTabName(window, 0, TabAccessibilityName.For("My first line", isDirty: true));
            ContentBox(window).Text = "   \n";
            WaitForTabName(window, 0, TabAccessibilityName.For("Untitled", isDirty: true));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    [Fact]
    public void FirstLineTrimsAndTruncates()
    {
        SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using var app = LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            ContentBox(window).Text = "   spaced out   ";
            WaitForTabName(window, 0, TabAccessibilityName.For("spaced out", isDirty: true));
            string forty = new('y', 40);
            ContentBox(window).Text = forty;
            WaitForTabName(window, 0, TabAccessibilityName.For(forty[..35], isDirty: true));
        }
        finally
        {
            CloseApp(app, window);
        }
    }

    static TextBox ContentBox(Window window)
    {
        var box = FindById(window, "TabContentBox")?.AsTextBox();
        Assert.NotNull(box);
        return box;
    }

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static void WaitForTabName(Window window, int index, string expected)
    {
        string? NameAt()
        {
            var found = TabItems(window);
            return found.Count > index ? found[index].Name : null;
        }

        var result = Retry.While(
            NameAt,
            name => name != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.Equal(expected, result);
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
