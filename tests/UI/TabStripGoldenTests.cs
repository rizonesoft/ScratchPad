using FlaUI.Core.AutomationElements;
using Notepad.Core;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// One of the three surface goldens the design contract keeps
// (docs/design-contract.md): the tab strip with a second tab open. It
// guards ScratchPad's own look against an unintended change; it is not a
// comparison with Windows Notepad.
[Collection("UI tests")]
public sealed class TabStripGoldenTests
{
    readonly ITestOutputHelper output;

    public TabStripGoldenTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    [Trait(UiGolden.TraitName, UiGolden.TraitValue)]
    public void TabStripMatchesGolden()
    {
        var fresh = new ShellSettings { WhatsNewSeen = true, Theme = "dark", WhenStarts = WhenStartsRouting.Fresh };
        using var shot = UiCapture.CaptureState(UiGolden.Tolerance(), NewTab, new CaptureSetup(fresh));
        UiGolden.AssertMatches(shot, "tab-strip", output);
    }

    static void NewTab(Window window)
    {
        UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileNewTab");
        Assert.Equal(2, MenuBarTests.WaitForTabCount(window, 2));
        Thread.Sleep(300);
    }
}
