using System.Reflection;
using Xunit;

namespace UI;

// A capability-gated Theory for the listing fixture (D00 T02 §37 item
// 3): gated on SCRATCHPAD_FIXTURE_CAPABILITY, which no real host sets,
// so at run time it reports one CAPABILITY skip like PrinterFact does.
sealed class CapabilityFixtureTheoryAttribute : GatedTheoryAttribute
{
    internal const string Variable = "SCRATCHPAD_FIXTURE_CAPABILITY";

    public CapabilityFixtureTheoryAttribute()
    {
        Gate(Environment.GetEnvironmentVariable(Variable) == "1" ? null : "CAPABILITY: fixture capability absent (D00 T02 §37 discovery-listing fixture).");
    }
}

// D00 T02 §37 item 3: identical binaries list the same population with a
// capability present or absent, and every Theory gate goes through the
// listing rule. Focus-free: the child runs list tests, launching no app.
[Collection("UI tests")]
public sealed class DiscoveryListingTests
{
    [CapabilityFixtureTheory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    public void CapabilityGatedRows(int row) => Assert.InRange(row, 1, 3);

    [Fact]
    public void GatedTheoryListsIdenticallyWithAndWithoutTheCapability()
    {
        var present = ListFixtureRows(listing: true, capability: true);
        var absent = ListFixtureRows(listing: true, capability: false);
        Assert.Equal(3, present.Count);
        Assert.Equal(present, absent);
        // The control: without the listing rule the absent capability
        // collapses the rows, so the fixture really is gated.
        Assert.Single(ListFixtureRows(listing: false, capability: false));
    }

    [Fact]
    public void EveryTheoryAttributeIsAGatedTheory()
    {
        var plain = typeof(DiscoveryListingTests).Assembly.GetTypes()
            .Where(t => typeof(TheoryAttribute).IsAssignableFrom(t) && t != typeof(TheoryAttribute) && !typeof(GatedTheoryAttribute).IsAssignableFrom(t))
            .Select(t => t.Name)
            .ToList();
        Assert.True(plain.Count == 0, $"Theory attributes outside the listing rule (derive from GatedTheoryAttribute): {string.Join(", ", plain)}");
    }

    static List<string> ListFixtureRows(bool listing, bool capability)
    {
        var env = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [GatedTheoryAttribute.ListingVariable] = listing ? "1" : string.Empty,
            [CapabilityFixtureTheoryAttribute.Variable] = capability ? "1" : string.Empty,
        };
        var (exit, output) = UiLaunch.RunChildTest("FullyQualifiedName~DiscoveryListingTests.CapabilityGatedRows", env, TimeSpan.FromMinutes(2), "--list-tests");
        Assert.True(exit == 0, $"listing exited {exit}: {output}");
        return output.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n')
            .Select(l => l.Trim())
            .Where(l => l.StartsWith("UI.DiscoveryListingTests.CapabilityGatedRows", StringComparison.Ordinal))
            .Order(StringComparer.Ordinal)
            .ToList();
    }
}
