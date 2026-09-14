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
        using var golden = new Bitmap(Path.Combine(AppContext.BaseDirectory, "goldens", "stub-window.png"));
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
        var tolerance = GoldenComparer.Load(Path.Combine(AppContext.BaseDirectory, "tolerance.json"));
        using var fresh = UiCapture.CaptureWindow(tolerance);
        using var shifted = GoldenComparer.ShiftRight(fresh, 10);
        using var golden = new Bitmap(Path.Combine(AppContext.BaseDirectory, "goldens", "stub-window.png"));
        var result = GoldenComparer.Compare(golden, shifted, tolerance);
        output.WriteLine($"shifted-vs-golden: {result.DifferentFraction:P4} different ({result.DifferentPixels}/{result.TotalPixels}), threshold {tolerance.MaxDifferentFraction:P4}");
        if (result.Match)
        {
            SaveFailureArtifacts(shifted, result, "shift");
        }

        Assert.False(result.Match, $"10px shift passed unexpectedly at {result.DifferentFraction:P3} different");
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
