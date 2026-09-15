using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §7: crash-checkpoint policy. The debounce plus the App merge are
// driven end to end by the killed-process UI drive; these pin the branches.
public sealed class CrashCheckpointTests
{
    [Fact]
    public void ContinueNontrivialWrites()
    {
        Assert.Equal(
            CrashCheckpoint.Decision.Write,
            CrashCheckpoint.Decide(StartupMode.ContinueSession, trivial: false, fileExists: false));
        Assert.Equal(
            CrashCheckpoint.Decision.Write,
            CrashCheckpoint.Decide(StartupMode.ContinueSession, trivial: false, fileExists: true));
    }

    [Fact]
    public void ContinueTrivialDeletes()
    {
        Assert.Equal(
            CrashCheckpoint.Decision.Delete,
            CrashCheckpoint.Decide(StartupMode.ContinueSession, trivial: true, fileExists: true));
    }

    [Fact]
    public void FreshWithStaleFileDeletes()
    {
        Assert.Equal(
            CrashCheckpoint.Decision.Delete,
            CrashCheckpoint.Decide(StartupMode.FreshWindow, trivial: false, fileExists: true));
    }

    [Fact]
    public void FreshWithoutFileSkips()
    {
        Assert.Equal(
            CrashCheckpoint.Decision.Skip,
            CrashCheckpoint.Decide(StartupMode.FreshWindow, trivial: false, fileExists: false));
    }

    [Fact]
    public void DebounceIsTwoSeconds()
    {
        Assert.Equal(TimeSpan.FromSeconds(2), CrashCheckpoint.Debounce);
    }
}
