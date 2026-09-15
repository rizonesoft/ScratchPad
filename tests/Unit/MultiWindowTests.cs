using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §9 (neutral half): open-in default and routing plus per-window
// isolation. Window creation and the live isolation drive are UI
// (tests/UI/MultiWindowTests.cs). Tear-out is struck: stock has none, so no
// detach routing exists to test.
public sealed class MultiWindowTests
{
    [Fact]
    public void OpenInDefaultsToNewTab()
    {
        Assert.Equal(OpenInRouting.NewTab, new ShellSettings().OpenIn);
    }

    [Fact]
    public void OpenInRoutesBothModesAndDefaultsUnknownToActiveWindow()
    {
        Assert.Equal(OpenTarget.ActiveWindowNewTab, OpenInRouting.Route(OpenInRouting.NewTab));
        Assert.Equal(OpenTarget.NewWindow, OpenInRouting.Route(OpenInRouting.NewWindow));
        Assert.Equal(OpenTarget.ActiveWindowNewTab, OpenInRouting.Route("bogus"));
        Assert.Equal(OpenTarget.ActiveWindowNewTab, OpenInRouting.Route(null));
        Assert.Equal(OpenTarget.ActiveWindowNewTab, OpenInRouting.Route(string.Empty));
    }

    [Fact]
    public void WindowsKeepSeparateTabsDirtyAndClosedStacks()
    {
        var first = new TabModel();
        var second = new TabModel();
        Tab edited = first.NewTab();
        edited.FilePath = "/tmp/notes/a.txt";
        edited.NotifyEdited("changed");
        first.CloseTab(edited, "changed", 7, discardUnsaved: false);

        Assert.Empty(second.Tabs);
        Assert.Empty(second.Closed);
        Assert.Null(second.ActiveTab);

        Tab clean = second.NewTab();
        Assert.False(clean.IsDirty);
        Assert.Single(first.Closed);
    }
}
