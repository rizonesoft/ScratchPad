using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §8: jump-list feed mapping. The COM commit lives in the app
// (Windows-only) and is driven by the UI suite; these pin the feed rules.
public sealed class JumpListFeedTests
{
    [Fact]
    public void PinsFillPinnedThenRecentsFillRecent()
    {
        IReadOnlyList<JumpListItem> items = JumpListFeed.Build(["C:\\p.txt"], ["C:\\r.txt"]);
        Assert.Equal(
            [
                new JumpListItem("p.txt", "\"C:\\p.txt\"", JumpListFeed.PinnedCategory),
                new JumpListItem("r.txt", "\"C:\\r.txt\"", JumpListFeed.RecentCategory),
            ],
            items);
    }

    [Fact]
    public void RecentsExcludePinsCaseInsensitively()
    {
        IReadOnlyList<JumpListItem> items = JumpListFeed.Build(["C:\\P.txt"], ["c:\\p.txt", "C:\\r.txt"]);
        Assert.Equal(
            [
                new JumpListItem("P.txt", "\"C:\\P.txt\"", JumpListFeed.PinnedCategory),
                new JumpListItem("r.txt", "\"C:\\r.txt\"", JumpListFeed.RecentCategory),
            ],
            items);
    }

    [Fact]
    public void EachCategoryCapsAtMaxCount()
    {
        var pins = Enumerable.Range(0, 12).Select(i => $"C:\\p{i}.txt").ToList();
        var recents = Enumerable.Range(0, 12).Select(i => $"C:\\r{i}.txt").ToList();
        IReadOnlyList<JumpListItem> items = JumpListFeed.Build(pins, recents);
        Assert.Equal(RecentFiles.MaxCount, items.Count(item => item.Category == JumpListFeed.PinnedCategory));
        Assert.Equal(RecentFiles.MaxCount, items.Count(item => item.Category == JumpListFeed.RecentCategory));
    }

    [Fact]
    public void MissingFilesAreKept()
    {
        IReadOnlyList<JumpListItem> items = JumpListFeed.Build(null, ["C:\\nope-missing-xyz.txt"]);
        Assert.Single(items);
    }

    [Fact]
    public void FingerprintChangesWithContent()
    {
        IReadOnlyList<JumpListItem> a = JumpListFeed.Build(["C:\\p.txt"], null);
        IReadOnlyList<JumpListItem> b = JumpListFeed.Build(["C:\\q.txt"], null);
        Assert.NotEqual(JumpListFeed.Fingerprint(a), JumpListFeed.Fingerprint(b));
        Assert.Equal(JumpListFeed.Fingerprint(a), JumpListFeed.Fingerprint(JumpListFeed.Build(["C:\\p.txt"], null)));
    }

    [Fact]
    public void NewNoteTaskCarriesTheFlag()
    {
        Assert.Equal("New note", JumpListFeed.NewNoteTask.Title);
        Assert.Equal(LaunchArgs.NewNoteFlag, JumpListFeed.NewNoteTask.Arguments);
        Assert.Equal(JumpListFeed.TasksCategory, JumpListFeed.NewNoteTask.Category);
    }

    [Fact]
    public void BuildExcludesTheStaticTask()
    {
        IReadOnlyList<JumpListItem> items = JumpListFeed.Build(null, null);
        Assert.Empty(items);
    }
}
