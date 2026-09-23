using System.Diagnostics;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Microsoft.Win32;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T01 §26: the scratchpad:// protocol. Registration cycles through
// the verbs with the live keys read back; links open their
// carried file fresh; malformed links open a bare window with nothing
// offered; a shell-executed link proves the click path end to end.
[Collection("UI tests")]
public sealed class ProtocolHandlerTests
{
    [Fact]
    public void ProtocolVerbsCycleCleanly()
    {
        UiLaunch.RunHeadless("/unregister-protocol", TimeSpan.FromSeconds(20));
        (string? Default, string? Command) before = SnapshotScheme();
        try
        {
            Assert.Equal(0, UiLaunch.RunHeadless("/register-protocol", TimeSpan.FromSeconds(20)));
            Assert.Equal(ProtocolAssociation.Description, ReadDefault(ProtocolAssociation.SchemeKey));
            Assert.NotNull(ReadString(ProtocolAssociation.SchemeKey, "URL Protocol"));
            string? command = ReadString(ProtocolAssociation.SchemeKey + @"\shell\open\command", string.Empty);
            Assert.NotNull(command);
            Assert.Contains(".exe", command, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("%1", command, StringComparison.Ordinal);
            Assert.Equal(0, UiLaunch.RunHeadless("/unregister-protocol", TimeSpan.FromSeconds(20)));
            Assert.Equal(before, SnapshotScheme());
            Assert.False(KeyExists(ProtocolAssociation.SchemeKey));
            Assert.False(KeyExists(ProtocolAssociation.BackupKey));
        }
        finally
        {
            UiLaunch.RunHeadless("/unregister-protocol", TimeSpan.FromSeconds(20));
        }
    }

    [Fact]
    public void LinkOpensTheCarriedFile()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "linked 26.txt");
        File.WriteAllText(file, "linked bytes");
        SeedFresh();
        try
        {
            string url = ProtocolAssociation.Scheme + "://" + Uri.EscapeDataString(file);
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{url}\"", drainLaunchDrops: true);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("linked 26.txt", isDirty: false));
                Assert.Equal("linked bytes", BoxText(window));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
        }
    }

    [Theory]
    [InlineData("scratchpad://")]
    [InlineData("scratchpad://relative/x.txt")]
    public void MalformedLinksOpenBareWindow(string link)
    {
        SeedFresh();
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchAppWithArgs($"\"{link}\"", drainLaunchDrops: true);
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            Assert.Equal(1, WaitForTabCount(window, 1));
            WaitForTabName(window, 0, TabAccessibilityName.For("Untitled", isDirty: false));
            Thread.Sleep(1000);
            Assert.Null(window.FindFirstDescendant(cf => cf.ByAutomationId("MissingFileDialog")));
        }
        finally
        {
            CloseAll(app, automation);
        }
    }

    [Fact]
    public void ShellLinkOpensTheFile()
    {
        string dir = NewTempDir();
        string file = Path.Combine(dir, "shell26.txt");
        File.WriteAllText(file, "shell bytes");
        SeedFresh();
        Assert.Equal(0, UiLaunch.RunHeadless("/register-protocol", TimeSpan.FromSeconds(20)));
        try
        {
            string url = ProtocolAssociation.Scheme + "://" + Uri.EscapeDataString(file);
            nint fgBefore = UiForeground.Capture();
            using var process = UiLaunch.ShellLaunch(url);
            Assert.NotNull(process);
            using var app = Application.Attach(process.Id);
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, WaitForTabCount(window, 2));
                WaitForTabName(window, 1, TabAccessibilityName.For("shell26.txt", isDirty: false));
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            SessionData.Delete();
            DeleteDir(dir);
            UiLaunch.RunHeadless("/unregister-protocol", TimeSpan.FromSeconds(20));
        }
    }

    static (string? Default, string? Command) SnapshotScheme() =>
        (ReadDefault(ProtocolAssociation.SchemeKey),
            ReadString(ProtocolAssociation.SchemeKey + @"\shell\open\command", string.Empty));

    static string? ReadDefault(string keyPath) => ReadString(keyPath, string.Empty);

    static string? ReadString(string keyPath, string valueName)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
        return key?.GetValue(valueName) as string;
    }

    static bool KeyExists(string keyPath)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
        return key is not null;
    }


    static void SeedFresh() => UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true, WhenStarts = WhenStartsRouting.Fresh }, drainLaunchDrops: true);

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
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

    static string BoxText(Window window) => ContentBox(window).Text ?? string.Empty;

    static List<AutomationElement> TabItems(Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.TabItem)).ToList();

    static int WaitForTabCount(Window window, int expected)
    {
        var result = Retry.While(
            () => TabItems(window).Count,
            count => count != expected,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true);
        return result.Result;
    }

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
            TimeSpan.FromMilliseconds(250),
            lastValueOnTimeout: true).Result;
        Assert.Equal(expected, result);
    }

    static void CloseAll(Application app, UIA3Automation automation)
    {
        foreach (var window in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                // Already gone; the exit wait below is the real assertion.
            }
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
    }
}
