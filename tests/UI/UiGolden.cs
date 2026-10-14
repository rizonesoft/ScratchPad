using System.Drawing;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// One comparison path for every golden test (operator decision 2026-10-14):
// a section's visual check against Notepad ends by committing its capture
// to resources/baseline/app/<name>.png, and the feature's test then calls
// AssertMatches with that name, so each one-off check becomes a permanent
// regression test. Every golden test carries [Trait(Visual, Golden)] and
// stays focus-free, so every section gate runs the whole set
// (GoldenInventoryTests pins both). The fresh capture always lands in
// build/visual/<name>.png for the eyeball check; failure artifacts keep the
// golden-failure-<name>.png names the soak workflow uploads.
internal static class UiGolden
{
    internal const string TraitName = "Visual";
    internal const string TraitValue = "Golden";

    internal static Tolerance Tolerance() => GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));

    internal static void AssertMatches(Bitmap fresh, string name, ITestOutputHelper output)
    {
        ArgumentNullException.ThrowIfNull(fresh);
        ArgumentNullException.ThrowIfNull(output);
        string visualDir = Path.Combine(BindingManifestTests.RepoRoot(), "build", "visual");
        Directory.CreateDirectory(visualDir);
        string capturePath = Path.Combine(visualDir, $"{name}.png");
        fresh.Save(capturePath);
        output.WriteLine($"capture: {capturePath}");

        string goldenPath = Path.Combine(AppContext.BaseDirectory, "goldens", $"{name}.png");
        Assert.True(File.Exists(goldenPath), $"golden {name}.png missing: compare {capturePath} with the stock Notepad capture, then commit it to resources/baseline/app/{name}.png");

        var tolerance = Tolerance();
        using var golden = new Bitmap(goldenPath);
        var result = GoldenComparer.Compare(golden, fresh, tolerance);
        output.WriteLine($"{name}-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (!result.Match)
        {
            string failPath = Path.Combine(AppContext.BaseDirectory, $"golden-failure-{name}.png");
            fresh.Save(failPath);
            using var diff = GoldenComparer.RenderDiff(fresh, result);
            string diffPath = Path.Combine(AppContext.BaseDirectory, $"golden-failure-{name}-diff.png");
            diff.Save(diffPath);
            output.WriteLine($"failure artifacts: {failPath} {diffPath}");
        }

        Assert.True(result.Match, $"{name} golden mismatch: {result.DifferentFraction:P3} different ({result.DifferentPixels}/{result.TotalPixels})");
    }
}
