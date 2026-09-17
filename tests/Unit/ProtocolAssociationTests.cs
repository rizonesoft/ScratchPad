using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §26: protocol link parsing and registration plans. The live
// registry cycle is driven by the UI suite through the verbs.
public sealed class ProtocolAssociationTests
{
    [Fact]
    public void EncodedAbsolutePathParses()
    {
        Assert.Equal("C:/docs/a b.txt", ProtocolAssociation.TryParseLink("scratchpad://C%3A/docs/a%20b.txt"));
    }

    [Fact]
    public void BackslashPathParses()
    {
        Assert.Equal(@"C:\x\y.txt", ProtocolAssociation.TryParseLink(@"scratchpad://C:\x\y.txt"));
    }

    [Fact]
    public void SchemeMatchesCaseInsensitively()
    {
        Assert.Equal("C:/x.txt", ProtocolAssociation.TryParseLink("SCRATCHPAD://C:/x.txt"));
    }

    [Theory]
    [InlineData("scratchpad://C:/x.txt/", "C:/x.txt")]
    [InlineData("scratchpad://C%3A%5Cx.txt%5C", @"C:\x.txt")]
    public void ShellTrailingSlashIsTrimmed(string link, string expected)
    {
        Assert.Equal(expected, ProtocolAssociation.TryParseLink(link));
    }

    [Theory]
    [InlineData("scratchpad://")]
    [InlineData("scratchpad://relative/x.txt")]
    [InlineData("scratchpad://%ZZ")]
    [InlineData("http://example.com/x.txt")]
    [InlineData("note.txt")]
    public void NonLinksReturnNull(string arg)
    {
        Assert.Null(ProtocolAssociation.TryParseLink(arg));
    }

    [Fact]
    public void RegisterPlanWritesSchemeMarkerAndCommand()
    {
        var writes = ProtocolAssociation.PlanRegister(@"C:\app\note.exe").ToList();
        Assert.Contains(writes, w => w.KeyPath == ProtocolAssociation.SchemeKey && string.IsNullOrEmpty(w.ValueName) && w.Value == ProtocolAssociation.Description);
        Assert.Contains(writes, w => w.KeyPath == ProtocolAssociation.SchemeKey && w.ValueName == "URL Protocol");
        Assert.Contains(
            writes,
            w => w.KeyPath == ProtocolAssociation.SchemeKey + @"\shell\open\command" && w.Value == "\"C:\\app\\note.exe\" \"%1\"");
    }

    [Fact]
    public void ReleaseRestoresPriorForeignClaim()
    {
        var (sets, _, deleteTree) = ProtocolAssociation.PlanRelease(ProtocolAssociation.Description, true, "URL:Foreign", "\"C:\\f.exe\" \"%1\"");
        Assert.False(deleteTree);
        Assert.Contains(sets, s => s.KeyPath == ProtocolAssociation.SchemeKey && s.Value == "URL:Foreign");
        Assert.Contains(sets, s => s.KeyPath == ProtocolAssociation.SchemeKey + @"\shell\open\command" && s.Value == "\"C:\\f.exe\" \"%1\"");
    }

    [Fact]
    public void ReleaseDeletesOursWhenNoPrior()
    {
        var (_, _, deleteTree) = ProtocolAssociation.PlanRelease(ProtocolAssociation.Description, false, null, null);
        Assert.True(deleteTree);
    }

    [Fact]
    public void ReleaseLeavesForeignClaimsAlone()
    {
        var (sets, _, deleteTree) = ProtocolAssociation.PlanRelease("URL:Foreign", false, null, null);
        Assert.Empty(sets);
        Assert.False(deleteTree);
    }
}
