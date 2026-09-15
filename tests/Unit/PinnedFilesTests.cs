using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §13: pinned-file list rules (the jump-list feed source).
public sealed class PinnedFilesTests
{
    [Fact]
    public void NotePinnedAppendsPath()
    {
        var pinned = new List<string>();

        PinnedFiles.NotePinned(pinned, "C:/notes/a.txt");

        Assert.Single(pinned);
        Assert.Equal("C:/notes/a.txt", pinned[0]);
    }

    [Fact]
    public void NotePinnedDedupesCaseInsensitively()
    {
        var pinned = new List<string> { "C:/notes/a.txt" };

        PinnedFiles.NotePinned(pinned, "c:/NOTES/a.txt");

        Assert.Single(pinned);
        Assert.Equal("C:/notes/a.txt", pinned[0]);
    }

    [Fact]
    public void NotePinnedIgnoresNullAndBlank()
    {
        var pinned = new List<string>();

        PinnedFiles.NotePinned(pinned, null);
        PinnedFiles.NotePinned(pinned, "  ");

        Assert.Empty(pinned);
    }

    [Fact]
    public void NoteUnpinnedRemovesMatches()
    {
        var pinned = new List<string> { "C:/notes/a.txt", "C:/notes/b.txt" };

        PinnedFiles.NoteUnpinned(pinned, "c:/notes/A.txt");

        Assert.Single(pinned);
        Assert.Equal("C:/notes/b.txt", pinned[0]);
    }

    [Fact]
    public void NoteUnpinnedIgnoresNullAndMissing()
    {
        var pinned = new List<string> { "C:/notes/a.txt" };

        PinnedFiles.NoteUnpinned(pinned, null);
        PinnedFiles.NoteUnpinned(pinned, "C:/notes/zzz.txt");

        Assert.Single(pinned);
        Assert.Equal("C:/notes/a.txt", pinned[0]);
    }
}
