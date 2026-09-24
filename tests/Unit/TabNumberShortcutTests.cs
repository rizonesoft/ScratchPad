using Notepad.Core;
using Xunit;

namespace Unit;

// D00 T02 §21 item 3: number-shortcut edges. Physical dispatch of each
// chord is proven by the Interactive chord tests; the mapping they reach
// is pinned here without focus.
public sealed class TabNumberShortcutTests
{
    [Theory]
    [InlineData(1, 3, 0)]
    [InlineData(3, 3, 2)]
    [InlineData(8, 8, 7)]
    [InlineData(9, 3, 2)]
    [InlineData(9, 1, 0)]
    public void NumbersSelectPositionallyAndNineSelectsLast(int number, int count, int index)
    {
        Assert.Equal(index, TabModel.NumberShortcutIndex(number, count));
    }

    [Theory]
    [InlineData(4, 3)]
    [InlineData(8, 7)]
    [InlineData(2, 1)]
    public void TooFewTabsIsANoOp(int number, int count)
    {
        Assert.Null(TabModel.NumberShortcutIndex(number, count));
        var model = ModelWith(count, active: 0);
        Tab before = model.ActiveTab!;
        Assert.False(model.GotoNumber(number));
        Assert.Same(before, model.ActiveTab);
    }

    [Fact]
    public void MoreThanNineTabsKeepsEightPositionalAndNineLast()
    {
        var model = ModelWith(12, active: 0);
        Assert.True(model.GotoNumber(8));
        Assert.Same(model.Tabs[7], model.ActiveTab);
        Assert.True(model.GotoNumber(9));
        Assert.Same(model.Tabs[11], model.ActiveTab);
        Assert.Equal(11, TabModel.NumberShortcutIndex(9, 12));
    }

    [Fact]
    public void SelectedTabReuseChangesNothing()
    {
        var model = ModelWith(4, active: 2);
        int raised = 0;
        model.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(TabModel.ActiveTab))
            {
                raised++;
            }
        };
        Assert.False(model.GotoNumber(3));
        Assert.Same(model.Tabs[2], model.ActiveTab);
        Assert.Equal(0, raised);
    }

    [Fact]
    public void NineOnTheLastTabIsReuse()
    {
        var model = ModelWith(5, active: 4);
        Assert.False(model.GotoNumber(9));
        Assert.Same(model.Tabs[4], model.ActiveTab);
    }

    [Theory]
    [InlineData(0, 3)]
    [InlineData(10, 3)]
    [InlineData(1, 0)]
    [InlineData(9, 0)]
    public void OutOfDomainNumbersAndEmptyModelsAreNoOps(int number, int count)
    {
        Assert.Null(TabModel.NumberShortcutIndex(number, count));
        Assert.False(new TabModel().GotoNumber(number));
    }

    static TabModel ModelWith(int count, int active)
    {
        var model = new TabModel();
        for (int i = 0; i < count; i++)
        {
            model.NewTab();
        }

        model.ActiveTab = model.Tabs[active];
        return model;
    }
}
