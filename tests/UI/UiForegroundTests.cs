using System.Drawing;
using Xunit;

namespace UI;

public sealed class UiForegroundTests
{
    [Fact]
    public void TwoMonitorBoxUsesSecondaryWorkingArea()
    {
        var displays = new[]
        {
            new UiForeground.SuiteDisplay(true, new Rectangle(0, 0, 2560, 1440), new Rectangle(0, 0, 2560, 1400)),
            new UiForeground.SuiteDisplay(false, new Rectangle(-1920, 1080, 1920, 1080), new Rectangle(-1920, 1080, 1920, 1040)),
        };
        Assert.Equal((-1920, 1080), UiForeground.PickSuiteOrigin(displays));
    }

    [Fact]
    public void SingleMonitorFallsBackOffscreen()
    {
        var displays = new[]
        {
            new UiForeground.SuiteDisplay(true, new Rectangle(0, 0, 2560, 1440), new Rectangle(0, 0, 2560, 1400)),
        };
        Assert.Equal((10000, 10000), UiForeground.PickSuiteOrigin(displays));
    }

    [Fact]
    public void LargestSecondaryWins()
    {
        var displays = new[]
        {
            new UiForeground.SuiteDisplay(true, new Rectangle(0, 0, 2560, 1440), new Rectangle(0, 0, 2560, 1400)),
            new UiForeground.SuiteDisplay(false, new Rectangle(2560, 0, 1280, 720), new Rectangle(2560, 0, 1280, 680)),
            new UiForeground.SuiteDisplay(false, new Rectangle(-1920, 1080, 1920, 1080), new Rectangle(-1920, 1080, 1920, 1040)),
        };
        Assert.Equal((-1920, 1080), UiForeground.PickSuiteOrigin(displays));
    }
}
