using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §24 (neutral half): shared text opens a tab, empty shares decline.
// Registration plus sheet presence live at D07 T01 §7.
public sealed class ShareReceiverTests
{
    [Fact]
    public void SharedTextOpensAnUntitledTabWithTheText()
    {
        var model = new TabModel();
        Tab? tab = ShareReceiver.Receive(model, "shared words");
        Assert.NotNull(tab);
        Assert.True(tab.IsUntitled);
        Assert.Equal("shared words", tab.FirstLine);
        Assert.True(tab.IsDirty);
        Assert.Same(tab, model.ActiveTab);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void EmptyShareDeclinesWithoutATab(string? text)
    {
        var model = new TabModel();
        Assert.Null(ShareReceiver.Receive(model, text));
        Assert.Empty(model.Tabs);
    }
}
