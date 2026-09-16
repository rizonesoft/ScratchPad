using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §18: fidelity fixtures pinning the shared converter. Structure,
// emphasis, and lists across all three outputs, plus the literal-fallback
// edge of the supported subset.
public sealed class FormatConverterTests
{
    [Fact]
    public void MarkdownIsLineBreakNormalizedIdentity()
    {
        Assert.Equal("# T\n\n- a\n", FormatConverter.ToMarkdown("# T\r\n\r\n- a\r\n"));
    }

    [Fact]
    public void HeadingsRenderAcrossFormats()
    {
        Assert.Equal("<h1>Title</h1>\n", FormatConverter.ToHtmlFragment("# Title\n"));
        Assert.Equal("<h3>Deep</h3>\n", FormatConverter.ToHtmlFragment("### Deep\n"));
        Assert.Equal("Title", FormatConverter.ToPlainText("# Title"));
        Assert.Equal("# Title", FormatConverter.ToMarkdown("# Title"));
    }

    [Fact]
    public void EmphasisAndStrongRender()
    {
        Assert.Equal("<p><em>em</em> and <strong>strong</strong></p>\n", FormatConverter.ToHtmlFragment("*em* and **strong**\n"));
        Assert.Equal("em and strong", FormatConverter.ToPlainText("*em* and **strong**"));
        Assert.Equal("<p><em>a <strong>c</strong> d</em></p>\n", FormatConverter.ToHtmlFragment("*a **c** d*\n"));
    }

    [Fact]
    public void UnmatchedMarkersAndUnderscoresStayLiteral()
    {
        Assert.Equal("<p>*open and **also open</p>\n", FormatConverter.ToHtmlFragment("*open and **also open\n"));
        Assert.Equal("*open and **also open", FormatConverter.ToPlainText("*open and **also open"));
        Assert.Equal("file_name stays", FormatConverter.ToPlainText("file_name stays"));
        Assert.Equal("<p>file_name stays</p>\n", FormatConverter.ToHtmlFragment("file_name stays\n"));
    }

    [Fact]
    public void CodeSpansRenderWithoutInnerParsing()
    {
        Assert.Equal("<p><code>*x*</code></p>\n", FormatConverter.ToHtmlFragment("`*x*`\n"));
        Assert.Equal("*x*", FormatConverter.ToPlainText("`*x*`"));
        Assert.Equal("<p>`open</p>\n", FormatConverter.ToHtmlFragment("`open\n"));
    }

    [Fact]
    public void LinksRenderWithImagePassthrough()
    {
        Assert.Equal("<p><a href=\"https://x.test\">text</a></p>\n", FormatConverter.ToHtmlFragment("[text](https://x.test)\n"));
        Assert.Equal("text (https://x.test)", FormatConverter.ToPlainText("[text](https://x.test)"));
        Assert.Equal("[text](https://x.test)", FormatConverter.ToMarkdown("[text](https://x.test)"));
        Assert.Equal("<p>![alt](u)</p>\n", FormatConverter.ToHtmlFragment("![alt](u)\n"));
    }

    [Fact]
    public void UnorderedListsRender()
    {
        Assert.Equal("<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n", FormatConverter.ToHtmlFragment("- a\n* b\n"));
        Assert.Equal("- a\n* b", FormatConverter.ToPlainText("- a\n* b"));
    }

    [Fact]
    public void OrderedListsPreserveNumbers()
    {
        Assert.Equal("<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n", FormatConverter.ToHtmlFragment("1. a\n3. b\n"));
        Assert.Equal("1. a\n3. b", FormatConverter.ToPlainText("1. a\n3. b"));
    }

    [Fact]
    public void ParagraphLinesJoinWithSoftBreaks()
    {
        Assert.Equal("<p>one\ntwo</p>\n", FormatConverter.ToHtmlFragment("one\ntwo\n"));
        Assert.Equal("<p>one</p>\n<p>two</p>\n", FormatConverter.ToHtmlFragment("one\n\ntwo\n"));
    }

    [Fact]
    public void OutOfSubsetPassesThrough()
    {
        Assert.Equal("<p>  - nested</p>\n", FormatConverter.ToHtmlFragment("  - nested\n"));
        Assert.Equal("<p>#nospace</p>\n", FormatConverter.ToHtmlFragment("#nospace\n"));
    }

    [Fact]
    public void HtmlDocumentShellIsPinned()
    {
        Assert.Equal(
            "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>T &amp; T</title>\n</head>\n<body>\n<p>x</p>\n</body>\n</html>\n",
            FormatConverter.ToHtmlDocument("T & T", "x\n"));
    }

    [Fact]
    public void HtmlEscapesSpecialChars()
    {
        Assert.Equal("<p>&lt;b&gt; &amp; &quot;q&quot;</p>\n", FormatConverter.ToHtmlFragment("<b> & \"q\"\n"));
    }

    [Fact]
    public void EmptyInputYieldsEmptyOutputs()
    {
        Assert.Equal(string.Empty, FormatConverter.ToMarkdown(string.Empty));
        Assert.Equal(string.Empty, FormatConverter.ToPlainText(string.Empty));
        Assert.Equal(string.Empty, FormatConverter.ToHtmlFragment(string.Empty));
    }
}
