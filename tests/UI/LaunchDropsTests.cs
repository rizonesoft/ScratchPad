using FlaUI.Core;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 5: LaunchDrops behavior at the launch seam. The
// default preserves filed drops for the app to drain on Activated;
// the opt-in drains synchronously before the launch or seed, exactly
// once (a second drain finds nothing).
[Collection("UI tests")]
public sealed class LaunchDropsTests
{
    [Fact]
    public void DefaultSeedPreservesDrops()
    {
        LaunchDrops.Write(["preserve-me.txt"]);
        try
        {
            UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
            Assert.Equal(["preserve-me.txt"], LaunchDrops.Drain());
        }
        finally
        {
            LaunchDrops.Drain();
        }
    }

    [Fact]
    public void OptInSeedDrainsExactlyOnce()
    {
        LaunchDrops.Write(["drain-me.txt"]);
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true }, drainLaunchDrops: true);
        Assert.Empty(Directory.GetFiles(LaunchDrops.DirectoryPath, "*.json"));
        Assert.Empty(LaunchDrops.Drain());
    }

    [Fact]
    public void OptInLaunchDrainsBeforeActivation()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        LaunchDrops.Write(["launch-drain-me.txt"]);
        nint fgBefore = UiForeground.Capture();
        using var app = UiLaunch.LaunchAppWithArgs(string.Empty, drainLaunchDrops: true);
        Assert.Empty(Directory.GetFiles(LaunchDrops.DirectoryPath, "*.json"));
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            UiForeground.Background(window, fgBefore);
        }
        finally
        {
            CloseAll(app, automation);
            LaunchDrops.Drain();
        }
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
