using FlaUI.Core;
using FlaUI.UIA3;
using Xunit;

namespace UI;

public sealed class UISmoke
{
    [Fact]
    public void StubWindowLaunchesShowsTitleAndCloses()
    {
        var appPath = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "apppath.txt")).Trim();
        if (appPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            appPath = Path.ChangeExtension(appPath, ".exe");
        }

        Assert.True(File.Exists(appPath), $"stub missing at {appPath}");

        using var app = Application.Launch(appPath);
        using var automation = new UIA3Automation();
        var window = app.GetMainWindow(automation, TimeSpan.FromSeconds(15));
        try
        {
            var title = window?.Title ?? string.Empty;
            Assert.StartsWith("Intelligent Notepad (stub ", title, StringComparison.Ordinal);
            window?.Close();
        }
        catch when (window is not null)
        {
            var shot = Path.Combine(Path.GetTempPath(), "uismoke-failure.png");
            window.CaptureToFile(shot);
            Console.WriteLine($"UISmoke failure screenshot: {shot}");
            throw;
        }
        finally
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (!app.HasExited && DateTime.UtcNow < deadline)
            {
                Thread.Sleep(100);
            }

            if (!app.HasExited)
            {
                app.Kill();
            }
        }

        Assert.True(app.HasExited, "stub did not exit after Close");
    }
}
