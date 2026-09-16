using System.Globalization;
using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §17 (neutral half): variable expansion plus custom persistence.
// The picker dialog is app UI (bedtime).
public sealed class TemplateTests
{
    [Fact]
    public void ExpandFillsDateAndTitle()
    {
        var date = new DateOnly(2026, 9, 14);
        string expanded = Templates.Expand("# {title}\n{date}\n", "Standup", date);
        Assert.Equal("# Standup\n" + date.ToString("d", CultureInfo.CurrentCulture) + "\n", expanded);
    }

    [Fact]
    public void ExpandTreatsEmptyTitleAsUntitledAndKeepsUnknownBraces()
    {
        string expanded = Templates.Expand("{title} {unknown}", string.Empty, new DateOnly(2026, 9, 14));
        Assert.StartsWith(TabDisplayName.Untitled + " ", expanded, StringComparison.Ordinal);
        Assert.Contains("{unknown}", expanded, StringComparison.Ordinal);
    }

    [Fact]
    public void BuiltInsExpandWithoutKnownVariablesLeft()
    {
        Assert.Equal(3, Templates.BuiltIn.Count);
        foreach (NoteTemplate template in Templates.BuiltIn)
        {
            string expanded = Templates.Expand(template.Body, "T", new DateOnly(2026, 9, 14));
            Assert.DoesNotContain("{title}", expanded, StringComparison.Ordinal);
            Assert.DoesNotContain("{date}", expanded, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void CustomTemplatesPersistAcrossStoreInstances()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        try
        {
            var first = new TemplateStore(dir);
            Assert.Empty(first.ListCustom());
            first.SaveCustom("Retro: Q3?", "# {title}");
            NoteTemplate saved = Assert.Single(new TemplateStore(dir).ListCustom());
            Assert.Equal("Retro_ Q3_", saved.Name);
            Assert.Equal("# {title}", saved.Body);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void SaveCustomRejectsEmptyName()
    {
        var store = new TemplateStore(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")));
        Assert.Throws<ArgumentException>(() => store.SaveCustom(string.Empty, "body"));
    }
}
