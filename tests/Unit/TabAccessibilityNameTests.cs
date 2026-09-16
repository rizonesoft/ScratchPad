using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §28 (neutral half): UIA name punctuation. Live dirty-tracking
// rides IsDirty-to-RefreshHeader; both punctuation halves are live-proven.
public sealed class TabAccessibilityNameTests
{
    [Fact]
    public void DirtyTabsCarryModifiedSuffix()
    {
        Assert.Equal("Notes. Modified.", TabAccessibilityName.For("Notes", isDirty: true));
    }

    [Fact]
    public void CleanTabsCarryUnmodifiedSuffix()
    {
        Assert.Equal("Notes. Unmodified.", TabAccessibilityName.For("Notes", isDirty: false));
    }
}
