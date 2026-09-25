using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §28 item 7: the launch capture seam is test-only by
// construction and a failing capture write reports instead of vanishing.
public sealed class LaunchCaptureTests
{
    static Func<string, string?> Env(string? capture, string? marker) =>
        name => name == LaunchCapture.CaptureVariable ? capture : name == LaunchCapture.RunMarkerVariable ? marker : null;

    [Fact]
    public void SeamActivatesOnlyWithTheCaptureAndTheRunMarker()
    {
        Assert.Equal("c.txt", LaunchCapture.ActivePath(Env("c.txt", "1")));
        Assert.Null(LaunchCapture.ActivePath(Env("c.txt", null)));
        Assert.Null(LaunchCapture.ActivePath(Env("c.txt", "0")));
        Assert.Null(LaunchCapture.ActivePath(Env("c.txt", "true")));
        Assert.Null(LaunchCapture.ActivePath(Env(null, "1")));
        Assert.Null(LaunchCapture.ActivePath(Env("  ", "1")));
    }

    [Fact]
    public void RecordAppendsOneLinePerUri()
    {
        string path = Path.Combine(Path.GetTempPath(), $"launch-capture-{Guid.NewGuid():N}.txt");
        try
        {
            Assert.Null(LaunchCapture.Record(path, new Uri("https://www.bing.com/search?q=a")));
            Assert.Null(LaunchCapture.Record(path, new Uri("https://www.bing.com/search?q=b")));
            Assert.Equal(["https://www.bing.com/search?q=a", "https://www.bing.com/search?q=b"], File.ReadAllLines(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void FailingWriteReportsInsteadOfVanishing()
    {
        string? failure = LaunchCapture.Record("x.txt", new Uri("https://www.bing.com/search"), (_, _) => throw new IOException("disk gone"));
        Assert.NotNull(failure);
        Assert.Contains("launch capture failed", failure, StringComparison.Ordinal);
        Assert.Contains("disk gone", failure, StringComparison.Ordinal);
        string? missingDir = LaunchCapture.Record(Path.Combine(Path.GetTempPath(), $"no-such-{Guid.NewGuid():N}", "c.txt"), new Uri("https://www.bing.com/search"));
        Assert.NotNull(missingDir);
    }
}
