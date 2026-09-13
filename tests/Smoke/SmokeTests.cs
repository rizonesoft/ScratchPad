using Notepad.Core;
using Xunit;

namespace Smoke;

public sealed class SmokeTests
{
    [Fact]
    public void CoreConstructsAndReportsVersion()
    {
        var core = new NotepadCore();

        Assert.Empty(core.Version); // PROBE: inverted for the §5 red-run check
    }
}
