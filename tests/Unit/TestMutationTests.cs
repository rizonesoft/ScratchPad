using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §36 items 1 and 4: the binding mutation seam is test-only by
// construction, like the launch capture; a named target swaps, `*`
// observes, and the observe log reports a failed write.
public sealed class TestMutationTests
{
    static Func<string, string?> Env(string? target, string? marker, string? log = null) =>
        name => name == TestMutation.Variable ? target
            : name == LaunchCapture.RunMarkerVariable ? marker
            : name == TestMutation.DispatchLogVariable ? log
            : null;

    [Fact]
    public void SeamActivatesOnlyWithTheTargetAndTheRunMarker()
    {
        Assert.Equal("MenuFileNewTab", TestMutation.Active(Env("MenuFileNewTab", "1")));
        Assert.Null(TestMutation.Active(Env("MenuFileNewTab", null)));
        Assert.Null(TestMutation.Active(Env("MenuFileNewTab", "true")));
        Assert.Null(TestMutation.Active(Env(null, "1")));
        Assert.Null(TestMutation.Active(Env(" ", "1")));
    }

    [Fact]
    public void ANamedTargetSwapsOnlyItselfAndStarObservesEverything()
    {
        Assert.Equal(MutationEffect.Swap, TestMutation.For("MenuFileNewTab", Env("MenuFileNewTab", "1")));
        Assert.Equal(MutationEffect.None, TestMutation.For("MenuFileOpen", Env("MenuFileNewTab", "1")));
        Assert.Equal(MutationEffect.None, TestMutation.For("MenuFileNewTab", Env("MenuFileNewTab", "0")));
        Assert.Equal("vk:84:1", TestMutation.Key(84, 1));
        Assert.Equal(MutationEffect.Swap, TestMutation.For(TestMutation.Key(84, 1), Env("vk:84:1", "1")));
        Assert.Equal(MutationEffect.Observe, TestMutation.For("MenuFileOpen", Env("*", "1")));
        Assert.Equal(MutationEffect.None, TestMutation.For("MenuFileOpen", Env("*", null)));
    }

    [Fact]
    public void ObserveLogAppendsOneLineAndReportsFailure()
    {
        var lines = new List<string>();
        Assert.Null(TestMutation.Record("MenuFileOpen", Env("*", "1", "d.log"), (_, text) => lines.Add(text)));
        Assert.Equal(["MenuFileOpen\n"], lines);
        Assert.Contains("dispatch log unset", TestMutation.Record("MenuFileOpen", Env("*", "1")), StringComparison.Ordinal);
        Assert.Contains("dispatch log failed", TestMutation.Record("MenuFileOpen", Env("*", "1", "d.log"), (_, _) => throw new IOException("disk")), StringComparison.Ordinal);
    }
}
