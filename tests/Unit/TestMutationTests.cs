using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §36 item 1: the binding mutation seam is test-only by
// construction, like the launch capture.
public sealed class TestMutationTests
{
    static Func<string, string?> Env(string? target, string? marker) =>
        name => name == TestMutation.Variable ? target : name == LaunchCapture.RunMarkerVariable ? marker : null;

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
    public void SuppressesOnlyTheNamedTarget()
    {
        Assert.True(TestMutation.Suppresses("MenuFileNewTab", Env("MenuFileNewTab", "1")));
        Assert.False(TestMutation.Suppresses("MenuFileOpen", Env("MenuFileNewTab", "1")));
        Assert.False(TestMutation.Suppresses("MenuFileNewTab", Env("MenuFileNewTab", "0")));
        Assert.Equal("vk:84:1", TestMutation.Key(84, 1));
        Assert.True(TestMutation.Suppresses(TestMutation.Key(84, 1), Env("vk:84:1", "1")));
    }
}
