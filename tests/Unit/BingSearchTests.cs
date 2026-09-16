using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §1 item 7: Bing handoff URL forms. The launch itself is never
// driven (it would open the operator's browser); the builder is pinned.
public sealed class BingSearchTests
{
    [Fact]
    public void SearchUrlEncodesSelection()
    {
        Assert.Equal(
            new Uri("https://www.bing.com/search?q=hello%20world"),
            BingSearch.SearchUrl("hello world"));
    }

    [Fact]
    public void SearchUrlTrimsAndHandlesEmpty()
    {
        Assert.Equal(new Uri("https://www.bing.com/search"), BingSearch.SearchUrl(null));
        Assert.Equal(new Uri("https://www.bing.com/search"), BingSearch.SearchUrl("   "));
        Assert.Equal(new Uri("https://www.bing.com/search?q=x"), BingSearch.SearchUrl("  x  "));
    }

    [Fact]
    public void DefineUrlPrefixesDefine()
    {
        Assert.Equal(
            new Uri("https://www.bing.com/search?q=define%20serendipity"),
            BingSearch.DefineUrl("serendipity"));
    }

    [Fact]
    public void DefineUrlHandlesEmpty()
    {
        Assert.Equal(new Uri("https://www.bing.com/search"), BingSearch.DefineUrl(null));
        Assert.Equal(new Uri("https://www.bing.com/search"), BingSearch.DefineUrl(string.Empty));
    }
}
