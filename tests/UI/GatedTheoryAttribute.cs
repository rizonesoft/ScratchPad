using Xunit;

namespace UI;

// Discovery-listing rule for gated Theories (D00 T02 §37 item 3). A
// Theory whose attribute sets Skip lists as one skipped case instead of
// its rows, so a capability or window gate evaluated at discovery made
// identical binaries list different populations on different hosts.
// Every gated Theory derives from this base and sets its gate through
// Gate: while listing (SCRATCHPAD_DISCOVERY_LISTING=1, set with the
// Interactive force by the population discovery,
// Invoke-WithForcedDiscovery in tools/NightlyParse.ps1) the gate is
// lifted and every row lists; at run time the gate applies as before.
// DiscoveryListingTests enforces that no other Theory attribute exists.
abstract class GatedTheoryAttribute : TheoryAttribute
{
    internal const string ListingVariable = "SCRATCHPAD_DISCOVERY_LISTING";

    internal static bool Listing => Environment.GetEnvironmentVariable(ListingVariable) == "1";

    protected void Gate(string? skip)
    {
        if (!Listing)
        {
            Skip = skip;
        }
    }
}
