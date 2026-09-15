using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §6: session snapshot rules, recent-files behavior, the startup
// preference, and the session file round-trip. Paths use forward slashes:
// valid on Windows, and GetFileName-compatible on Linux CI.
public sealed class SessionStoreTests
{
    static TabSnapshot Snap(
        string? path,
        string? content,
        int caret,
        bool dirty) => new(path, content, caret, dirty, "UTF-8", false, "CRLF");

    [Fact]
    public void CaptureKeepsCleanFileTabsAsPaths()
    {
        var window = SessionCapture.CaptureWindow(
            [Snap("/tmp/notes/a.txt", "alpha", 3, false)],
            0,
            _ => true);

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Equal("/tmp/notes/a.txt", tab.Path);
        Assert.Null(tab.Content);
        Assert.Equal(3, tab.Caret);
        Assert.Equal(0, window.Active);
    }

    [Fact]
    public void CaptureKeepsDirtyBuffersWithContent()
    {
        var window = SessionCapture.CaptureWindow(
            [Snap("/tmp/notes/a.txt", "alphaZ", 6, true)],
            0,
            _ => true);

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Equal("/tmp/notes/a.txt", tab.Path);
        Assert.Equal("alphaZ", tab.Content);
        Assert.Equal(6, tab.Caret);
    }

    [Fact]
    public void CaptureKeepsUntitledBuffers()
    {
        var window = SessionCapture.CaptureWindow(
            [Snap(null, "unsaved work", 4, true)],
            0,
            _ => true);

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Null(tab.Path);
        Assert.Equal("unsaved work", tab.Content);
        Assert.Equal(4, tab.Caret);
    }

    [Fact]
    public void CaptureKeepsEmptyUntitledTabs()
    {
        var window = SessionCapture.CaptureWindow(
            [Snap(null, "", 0, false)],
            0,
            _ => true);

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Null(tab.Path);
        Assert.Equal(string.Empty, tab.Content);
    }

    [Fact]
    public void CaptureDropsCleanTabsOverMissingFiles()
    {
        var window = SessionCapture.CaptureWindow(
            [
                Snap("/tmp/notes/gone.txt", "", 0, false),
                Snap("/tmp/notes/here.txt", "stays", 2, false),
            ],
            1,
            path => path.EndsWith("here.txt", StringComparison.Ordinal));

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Equal("/tmp/notes/here.txt", tab.Path);
        Assert.Equal(0, window.Active);
    }

    [Fact]
    public void CaptureKeepsDirtyTabsOverMissingFiles()
    {
        // User data first: a dirty buffer survives even when its file was
        // deleted out from under it (unprobed in stock; the clean-missing
        // drop is the probed half).
        var window = SessionCapture.CaptureWindow(
            [Snap("/tmp/notes/gone.txt", "doomed edits", 5, true)],
            0,
            _ => false);

        SessionTab tab = Assert.Single(window.Tabs);
        Assert.Equal("/tmp/notes/gone.txt", tab.Path);
        Assert.Equal("doomed edits", tab.Content);
    }

    [Fact]
    public void CaptureRemapsActiveAcrossDrops()
    {
        var window = SessionCapture.CaptureWindow(
            [
                Snap("/tmp/notes/gone.txt", "", 0, false),
                Snap("/tmp/notes/a.txt", "a", 1, false),
                Snap("/tmp/notes/b.txt", "b", 1, false),
            ],
            2,
            path => !path.EndsWith("gone.txt", StringComparison.Ordinal));

        Assert.Equal(2, window.Tabs.Count);
        Assert.Equal(1, window.Active);
    }

    [Fact]
    public void CaptureClampsActiveAndCaret()
    {
        var window = SessionCapture.CaptureWindow(
            [Snap(null, "x", -9, true)],
            7,
            _ => true);

        Assert.Equal(0, window.Active);
        Assert.Equal(0, Assert.Single(window.Tabs).Caret);
    }

    [Fact]
    public void RecentCloseMovesToFront()
    {
        var recents = new List<string> { "/tmp/b.txt", "/tmp/a.txt" };
        RecentFiles.NoteClosed(recents, "/tmp/a.txt");
        Assert.Equal(["/tmp/a.txt", "/tmp/b.txt"], recents);
    }

    [Fact]
    public void RecentCloseDedupesCaseInsensitively()
    {
        var recents = new List<string> { "/tmp/Notes/A.TXT" };
        RecentFiles.NoteClosed(recents, "/tmp/notes/a.txt");
        Assert.Equal(["/tmp/notes/a.txt"], recents);
    }

    [Fact]
    public void RecentCloseTruncatesToTen()
    {
        var recents = new List<string>();
        for (int i = 1; i <= 12; i++)
        {
            RecentFiles.NoteClosed(recents, $"/tmp/f{i:00}.txt");
        }

        Assert.Equal(RecentFiles.MaxCount, recents.Count);
        Assert.Equal("/tmp/f12.txt", recents[0]);
        Assert.Equal("/tmp/f03.txt", recents[^1]);
        Assert.DoesNotContain("/tmp/f01.txt", recents);
        Assert.DoesNotContain("/tmp/f02.txt", recents);
    }

    [Fact]
    public void RecentCloseIgnoresBlankPaths()
    {
        var recents = new List<string> { "/tmp/a.txt" };
        RecentFiles.NoteClosed(recents, null);
        RecentFiles.NoteClosed(recents, "  ");
        Assert.Equal(["/tmp/a.txt"], recents);
    }

    [Fact]
    public void RecentClearEmpties()
    {
        var recents = new List<string> { "/tmp/a.txt", "/tmp/b.txt" };
        RecentFiles.Clear(recents);
        Assert.Empty(recents);
    }

    [Fact]
    public void WhenStartsDefaultsToContinue()
    {
        Assert.Equal(WhenStartsRouting.Continue, new ShellSettings().WhenStarts);
        Assert.Equal(StartupMode.ContinueSession, WhenStartsRouting.Route(new ShellSettings().WhenStarts));
    }

    [Theory]
    [InlineData("fresh", StartupMode.FreshWindow)]
    [InlineData("continue", StartupMode.ContinueSession)]
    [InlineData(null, StartupMode.ContinueSession)]
    [InlineData("", StartupMode.ContinueSession)]
    [InlineData("bogus", StartupMode.ContinueSession)]
    public void WhenStartsRoutesUnknownToContinue(string? value, StartupMode want)
    {
        Assert.Equal(want, WhenStartsRouting.Route(value));
    }

    [Fact]
    public void SessionRoundTripsThroughTempFile()
    {
        string path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "session.json");
        try
        {
            var data = new SessionData
            {
                ActiveWindow = 1,
                Windows =
                [
                    new SessionWindow
                    {
                        Active = 1,
                        Tabs =
                        [
                            new SessionTab { Path = "/tmp/a.txt", Caret = 2 },
                            new SessionTab { Content = "unsaved", Caret = 4 },
                        ],
                    },
                    new SessionWindow
                    {
                        Tabs = [new SessionTab { Path = "/tmp/b.txt", Content = "dirty", Caret = 1 }],
                    },
                ],
            };
            data.SaveTo(path);

            SessionData back = SessionData.LoadFrom(path);
            Assert.Equal(1, back.ActiveWindow);
            Assert.Equal(2, back.Windows.Count);
            Assert.Equal(1, back.Windows[0].Active);
            Assert.Equal("/tmp/a.txt", back.Windows[0].Tabs[0].Path);
            Assert.Null(back.Windows[0].Tabs[0].Content);
            Assert.Equal("unsaved", back.Windows[0].Tabs[1].Content);
            Assert.Equal("dirty", back.Windows[1].Tabs[0].Content);
            Assert.False(File.Exists(path + ".tmp"), "atomic-write temp file leaked");
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void TrivialSessionIsOneEmptyUntitledTab()
    {
        Assert.True(new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Content = "" }] }],
        }.IsTrivial);
        Assert.True(new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab()] }],
        }.IsTrivial);
        Assert.False(new SessionData().IsTrivial);
        Assert.False(new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Content = "x" }] }],
        }.IsTrivial);
        Assert.False(new SessionData
        {
            Windows = [new SessionWindow { Tabs = [new SessionTab { Path = "/tmp/a.txt" }] }],
        }.IsTrivial);
        Assert.False(new SessionData
        {
            Windows =
            [
                new SessionWindow { Tabs = [new SessionTab { Content = "" }] },
                new SessionWindow { Tabs = [new SessionTab { Content = "" }] },
            ],
        }.IsTrivial);
        Assert.False(new SessionData
        {
            Windows =
            [
                new SessionWindow
                {
                    Tabs = [new SessionTab { Path = "/tmp/a.txt" }, new SessionTab { Content = "" }],
                },
            ],
        }.IsTrivial);
    }

    [Fact]
    public void SessionLoadMissingFileYieldsEmpty()
    {
        SessionData data = SessionData.LoadFrom(
            Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "nope.json"));
        Assert.Empty(data.Windows);
    }

    [Fact]
    public void SessionLoadHostileJsonNullsLoadClean()
    {
        string path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(
                path,
                """{"Windows":[null,{"Tabs":[null,{"Path":"/tmp/a.txt","Encoding":null,"LineEnding":null}],"Active":5}],"ActiveWindow":-3}""");
            SessionData data = SessionData.LoadFrom(path);
            SessionWindow window = Assert.Single(data.Windows);
            SessionTab tab = Assert.Single(window.Tabs);
            Assert.Equal("/tmp/a.txt", tab.Path);
            Assert.Equal("UTF-8", tab.Encoding);
            Assert.Equal("CRLF", tab.LineEnding);
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }

    [Fact]
    public void SessionLoadCorruptFileYieldsEmpty()
    {
        string path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(path, "{not json");
            SessionData data = SessionData.LoadFrom(path);
            Assert.Empty(data.Windows);
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort cleanup; the test result does not depend on it.
            }
        }
    }
}
