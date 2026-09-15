using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §8: cross-process launch drops. The redirect handshake itself is
// driven by the UI suite (second launch lands a tab in the first window);
// these pin the drop file mechanics.
public sealed class LaunchDropsTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "drops8-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    [Fact]
    public void FiledFilesDrainInOrderAndDelete()
    {
        LaunchDrops.Write(["C:\\a.txt"], dir);
        LaunchDrops.Write(["C:\\b.txt", "C:\\c.txt"], dir);
        IReadOnlyList<string> files = LaunchDrops.Drain(dir);
        Assert.Equal(3, files.Count);
        Assert.Contains("C:\\a.txt", files);
        Assert.Empty(Directory.GetFiles(dir));
        Assert.Empty(LaunchDrops.Drain(dir));
    }

    [Fact]
    public void BareLaunchFilesEmptyList()
    {
        LaunchDrops.Write([], dir);
        Assert.Empty(LaunchDrops.Drain(dir));
        Assert.Empty(Directory.GetFiles(dir));
    }

    [Fact]
    public void PoisonDropsDeleteUnread()
    {
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "bogus.json"), "{not json");
        Assert.Empty(LaunchDrops.Drain(dir));
        Assert.Empty(Directory.GetFiles(dir));
    }

    [Fact]
    public void MissingDirectoryDrainsEmpty()
    {
        Assert.Empty(LaunchDrops.Drain(Path.Combine(dir, "absent")));
    }
}
