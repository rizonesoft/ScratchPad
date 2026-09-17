using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §2: tab list model, dirty tracking, auto-naming, closed stack.
// Paths use forward slashes: valid on Windows, and GetFileName-compatible on Linux CI.
public sealed class TabModelTests
{
    [Fact]
    public void EditFlipsDirtyAndSaveClearsIt()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.FilePath = "/tmp/notes/a.txt";
        Assert.False(tab.IsDirty);

        tab.NotifyEdited("changed");
        Assert.True(tab.IsDirty);

        tab.MarkSaved();
        Assert.False(tab.IsDirty);
    }

    [Fact]
    public void UntitledDirtyTracksContentPresence()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        Assert.False(tab.IsDirty);

        tab.NotifyEdited("hello");
        Assert.True(tab.IsDirty);

        tab.NotifyEdited(string.Empty);
        Assert.False(tab.IsDirty);
    }

    [Fact]
    public void NoOpEditsLeaveDirtyAlone()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.MarkSaved();
        Assert.False(tab.IsDirty);

        tab.NotifyEdited(string.Empty);
        Assert.False(tab.IsDirty);

        tab.MarkClean();
        Assert.False(tab.IsDirty);
    }

    [Fact]
    public void UndoToSavePointClearsDirty()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.FilePath = "/tmp/notes/a.txt";
        tab.NotifyEdited("changed");
        Assert.True(tab.IsDirty);

        tab.MarkClean();
        Assert.False(tab.IsDirty);
    }

    [Fact]
    public void UntitledCarriesNoPathUntilSave()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        Assert.Null(tab.FilePath);
        Assert.True(tab.IsUntitled);
        Assert.Equal(SaveRequestOutcome.SaveAsRequired, tab.SaveRequest);

        tab.FilePath = "/tmp/notes/a.txt";
        Assert.False(tab.IsUntitled);
        Assert.Equal(SaveRequestOutcome.SaveToPath, tab.SaveRequest);
    }

    [Theory]
    [InlineData("", "Untitled")]
    [InlineData("   ", "Untitled")]
    [InlineData("hello", "hello")]
    [InlineData("   spaced out   ", "spaced out")]
    [InlineData("yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy")]
    [InlineData("yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy")]
    [InlineData("yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy")]
    public void AutoNameFollowsNotepadRule(string firstLine, string expected)
    {
        Assert.Equal(expected, TabDisplayName.FromContent(firstLine));
    }

    [Fact]
    public void UntitledShowsFirstLineOnly()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.NotifyEdited("first line\nsecond line");
        Assert.Equal("first line", tab.DisplayName);
    }

    [Fact]
    public void SavedTabShowsFileName()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.NotifyEdited("some content here");
        tab.FilePath = "/tmp/notes/Implementation.txt";
        tab.MarkSaved();
        Assert.Equal("Implementation.txt", tab.DisplayName);
        Assert.Equal("Implementation.txt - ScratchPad", tab.WindowTitle("ScratchPad"));
    }

    [Fact]
    public void WindowTitleUsesConvention()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        Assert.Equal("Untitled - ScratchPad", tab.WindowTitle("ScratchPad"));

        tab.NotifyEdited("hello");
        Assert.Equal("*hello - ScratchPad", tab.WindowTitle("ScratchPad"));
    }

    [Fact]
    public void TwoObserversSeeTheSameEvents()
    {
        var model = new TabModel();
        var first = new List<string>();
        var second = new List<string>();
        model.Tabs.CollectionChanged += (_, e) =>
        {
            first.Add($"list:{e.Action}");
            second.Add($"list:{e.Action}");
        };

        Tab tab = model.NewTab();
        tab.PropertyChanged += (_, e) =>
        {
            first.Add($"tab:{e.PropertyName}");
            second.Add($"tab:{e.PropertyName}");
        };
        tab.NotifyEdited("hello");
        tab.MarkSaved();

        Assert.NotEmpty(first);
        Assert.Equal(first, second);
        Assert.Contains(first, e => e.StartsWith("list:", StringComparison.Ordinal));
        Assert.Contains(first, e => e == "tab:IsDirty");
    }

    [Fact]
    public void CloseThenReopenRoundTripsSavedTab()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.FilePath = "/tmp/notes/a.txt";
        tab.Encoding = "UTF-8";
        tab.LineEnding = "CRLF";

        model.CloseTab(tab, content: null, caretOffset: 0, discardUnsaved: false);
        Assert.Empty(model.Tabs);

        Tab? back = model.ReopenLast();
        Assert.NotNull(back);
        Assert.Equal("/tmp/notes/a.txt", back.FilePath);
        Assert.False(back.IsDirty);
        Assert.Same(back, model.ActiveTab);
    }

    [Fact]
    public void CloseThenReopenRestoresUnsavedContent()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.NotifyEdited("unsaved work");

        model.CloseTab(tab, content: "unsaved work", caretOffset: 7, discardUnsaved: false);

        Tab? back = model.ReopenLast();
        Assert.NotNull(back);
        Assert.True(back.IsUntitled);
        Assert.Equal("unsaved work", back.DisplayName);
        Assert.True(back.IsDirty);
    }

    [Fact]
    public void EmptyUntitledCloseLeavesNoStackEntry()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();

        model.CloseTab(tab, content: string.Empty, caretOffset: 0, discardUnsaved: false);

        Assert.Empty(model.Closed);
        Assert.Null(model.ReopenLast());
    }

    [Fact]
    public void DiscardedCloseLeavesNoStackEntry()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.NotifyEdited("thrown away");

        model.CloseTab(tab, content: "thrown away", caretOffset: 0, discardUnsaved: true);

        Assert.Empty(model.Closed);
    }

    [Fact]
    public void ReopenIsLastInFirstOut()
    {
        var model = new TabModel();
        Tab first = model.NewTab();
        first.FilePath = "/tmp/notes/first.txt";
        Tab second = model.NewTab();
        second.FilePath = "/tmp/notes/second.txt";

        model.CloseTab(first, content: null, caretOffset: 0, discardUnsaved: false);
        model.CloseTab(second, content: null, caretOffset: 0, discardUnsaved: false);

        Assert.Equal("/tmp/notes/second.txt", model.ReopenLast()?.FilePath);
        Assert.Equal("/tmp/notes/first.txt", model.ReopenLast()?.FilePath);
        Assert.Null(model.ReopenLast());
    }

    [Fact]
    public void ClosingANonOpenTabIsANoOp()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        model.CloseTab(tab, content: null, caretOffset: 0, discardUnsaved: false);

        model.ActiveTab = tab;
        model.CloseTab(tab, content: null, caretOffset: 0, discardUnsaved: false);

        Assert.Empty(model.Tabs);
        Assert.Empty(model.Closed);
    }

    [Fact]
    public void ClosingActiveTabSelectsANeighbor()
    {
        var model = new TabModel();
        Tab first = model.NewTab();
        Tab second = model.NewTab();
        Assert.Same(second, model.ActiveTab);

        model.CloseTab(second, content: null, caretOffset: 0, discardUnsaved: false);

        Assert.Same(first, model.ActiveTab);
    }

    [Fact]
    public void ClosedEntryKeepsPathContentsAndCaret()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();
        tab.FilePath = "/tmp/notes/a.txt";
        tab.Encoding = "UTF-16 LE";
        tab.LineEnding = "LF";

        model.CloseTab(tab, content: "body", caretOffset: 3, discardUnsaved: false);

        ClosedTab entry = Assert.Single(model.Closed);
        Assert.Equal("/tmp/notes/a.txt", entry.FilePath);
        Assert.Equal("body", entry.Contents);
        Assert.Equal(3, entry.CaretOffset);
        Assert.Equal("UTF-16 LE", entry.Encoding);
        Assert.Equal("LF", entry.LineEnding);
    }

    [Fact]
    public void IsPinnedDefaultsFalseAndNotifies()
    {
        var model = new TabModel();
        Tab tab = model.NewTab();

        Assert.False(tab.IsPinned);

        string? seen = null;
        tab.PropertyChanged += (_, e) => seen = e.PropertyName;
        tab.IsPinned = true;

        Assert.Equal(nameof(Tab.IsPinned), seen);
    }
}
