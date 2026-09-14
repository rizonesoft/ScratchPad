using Notepad.Core;
using Xunit;

namespace Smoke;

public sealed class SmokeTests
{
    [Fact]
    public void CoreConstructsAndReportsVersion()
    {
        var core = new NotepadCore();

        Assert.NotEmpty(core.Version);
    }
}
