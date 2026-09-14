using Notepad.Core;
using Xunit;

namespace Unit;

public sealed class FrameworkTests
{
    [Fact]
    public void NeutralLibraryReferenceResolves()
    {
        var core = new NotepadCore();

        Assert.NotEmpty(core.Version);
    }

    [Fact]
    public void TrivialPureFunctionPasses()
    {
        Assert.Equal(4, Add(2, 2));
    }

    private static int Add(int left, int right) => left + right;
}
