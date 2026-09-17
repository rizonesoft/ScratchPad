using System.Drawing;
using Xunit;
using Xunit.Abstractions;

namespace UI;

[Collection("UI tests")]
public sealed class GoldenComparisonTests
{
    readonly ITestOutputHelper output;

    public GoldenComparisonTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void FreshCaptureMatchesGolden()
    {
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        using var fresh = UiCapture.CaptureWindow(tolerance);
        using var golden = new Bitmap(Path.Combine(AppContext.BaseDirectory, "goldens", "main-window.png"));
        var result = GoldenComparer.Compare(golden, fresh, tolerance);
        output.WriteLine($"fresh-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (!result.Match)
        {
            SaveFailureArtifacts(fresh, result, "fresh");
        }

        Assert.True(result.Match, $"golden mismatch: {result.DifferentFraction:P3} different ({result.DifferentPixels}/{result.TotalPixels})");
    }

    [Fact]
    public void TenPixelShiftFailsComparison()
    {
        // Shift sensitivity is a comparer property, so the probe runs on the
        // content-rich stock capture: the §1 shell golden is legitimately sparse
        // (empty regions its owners fill later) and a 10px shift hides in it.
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        using var stock = new Bitmap(Path.Combine(AppContext.BaseDirectory, "goldens", "stock-main.png"));
        using var shifted = GoldenComparer.ShiftRight(stock, 10);
        var result = GoldenComparer.Compare(stock, shifted, tolerance);
        output.WriteLine($"shifted-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (result.Match)
        {
            SaveFailureArtifacts(shifted, result, "shift");
        }

        Assert.False(result.Match, $"10px shift passed unexpectedly at {result.DifferentFraction:P3} different");
    }

    [Fact]
    public void OnePixelEdgeWobblePassesComparison()
    {
        // Pins the §6 normalization: a 1px rasterization wobble (the shape
        // of cross-DPI glyph noise) must match, while TenPixelShift below
        // still fails. Two solid bars offset by 1px differ in 2 edge columns
        // x 579 compared rows = 1158 raw pixels (red without the blur), which
        // the 3x3 soften collapses to zero.
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        using var left = new Bitmap(tolerance.CanonicalWidth, tolerance.CanonicalHeight);
        using var right = new Bitmap(tolerance.CanonicalWidth, tolerance.CanonicalHeight);
        using (var g = Graphics.FromImage(left))
        {
            g.Clear(Color.FromArgb(45, 45, 45));
            g.FillRectangle(Brushes.White, 400, 0, 100, tolerance.CanonicalHeight);
        }

        using (var g = Graphics.FromImage(right))
        {
            g.Clear(Color.FromArgb(45, 45, 45));
            g.FillRectangle(Brushes.White, 401, 0, 100, tolerance.CanonicalHeight);
        }

        var result = GoldenComparer.Compare(left, right, tolerance);
        output.WriteLine($"wobble-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        Assert.True(result.Match, $"1px wobble failed unexpectedly at {result.DifferentFraction:P3} different");
    }

    void SaveFailureArtifacts(Bitmap image, ComparisonResult result, string name)
    {
        var freshPath = Path.Combine(AppContext.BaseDirectory, $"golden-failure-{name}.png");
        image.Save(freshPath);
        using var diff = GoldenComparer.RenderDiff(image, result);
        var diffPath = Path.Combine(AppContext.BaseDirectory, $"golden-failure-{name}-diff.png");
        diff.Save(diffPath);
        output.WriteLine($"failure artifacts: {freshPath} {diffPath}");
    }
}
