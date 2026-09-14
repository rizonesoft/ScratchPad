using System.Diagnostics.CodeAnalysis;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace UI;

[SuppressMessage("Performance", "CA1812", Justification = "Instantiated by System.Text.Json deserialization.")]
internal sealed record Tolerance(int CanonicalWidth, int CanonicalHeight, double CropTopFraction, double CropSideFraction, double CropBottomFraction, int PerPixelDelta, double MaxDifferentFraction);

internal sealed record ComparisonResult(bool Match, double DifferentFraction, int DifferentPixels, int TotalPixels, bool[] DifferentMap, int MapWidth, int MapHeight, int MapLeft, int MapTop);

internal static class GoldenComparer
{
    static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    internal static Tolerance Load(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<Tolerance>(json, JsonOptions)!;
    }

    internal static Bitmap Canonicalize(Bitmap source, int width, int height)
    {
        var canonical = new Bitmap(width, height);
        using (var g = Graphics.FromImage(canonical))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(source, 0, 0, width, height);
        }

        return canonical;
    }

    internal static Bitmap RenderDiff(Bitmap fresh, ComparisonResult result)
    {
        var diff = new Bitmap(fresh);
        for (var y = 0; y < result.MapHeight; y++)
        {
            for (var x = 0; x < result.MapWidth; x++)
            {
                if (result.DifferentMap[y * result.MapWidth + x])
                {
                    diff.SetPixel(result.MapLeft + x, result.MapTop + y, Color.Red);
                }
            }
        }

        return diff;
    }

    internal static Bitmap ShiftRight(Bitmap source, int pixels)
    {
        // Rect overloads with GraphicsUnit.Pixel throughout: the DrawImage point
        // overloads scale by bitmap DPI (96 vs 144 here), silently shrinking the blit.
        var shifted = new Bitmap(source.Width, source.Height);
        using (var g = Graphics.FromImage(shifted))
        {
            g.DrawImage(source, new Rectangle(pixels, 0, source.Width, source.Height), new Rectangle(0, 0, source.Width, source.Height), GraphicsUnit.Pixel);
            using var edge = source.Clone(new Rectangle(0, 0, 1, source.Height), source.PixelFormat);
            g.DrawImage(edge, new Rectangle(0, 0, pixels, source.Height));
        }

        return shifted;
    }

    internal static ComparisonResult Compare(Bitmap golden, Bitmap fresh, Tolerance tolerance)
    {
        if (golden.Width != tolerance.CanonicalWidth || golden.Height != tolerance.CanonicalHeight)
        {
            throw new InvalidOperationException($"golden is {golden.Width}x{golden.Height}, expected canonical {tolerance.CanonicalWidth}x{tolerance.CanonicalHeight}");
        }

        using var canonical = Canonicalize(fresh, tolerance.CanonicalWidth, tolerance.CanonicalHeight);
        var left = (int)(tolerance.CanonicalWidth * tolerance.CropSideFraction);
        var top = (int)(tolerance.CanonicalHeight * tolerance.CropTopFraction);
        var right = tolerance.CanonicalWidth - (int)(tolerance.CanonicalWidth * tolerance.CropSideFraction);
        var bottom = tolerance.CanonicalHeight - (int)(tolerance.CanonicalHeight * tolerance.CropBottomFraction);

        var rect = new Rectangle(0, 0, canonical.Width, canonical.Height);
        var goldenData = golden.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var freshData = canonical.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var length = goldenData.Stride * goldenData.Height;
            var goldenBytes = new byte[length];
            var freshBytes = new byte[length];
            Marshal.Copy(goldenData.Scan0, goldenBytes, 0, length);
            Marshal.Copy(freshData.Scan0, freshBytes, 0, length);
            var different = 0;
            var total = 0;
            var map = new bool[(right - left) * (bottom - top)];
            for (var y = top; y < bottom; y++)
            {
                for (var x = left; x < right; x++)
                {
                    var offset = y * goldenData.Stride + x * 4;
                    var delta = 0;
                    for (var c = 0; c < 3; c++)
                    {
                        var d = Math.Abs(goldenBytes[offset + c] - freshBytes[offset + c]);
                        if (d > delta)
                        {
                            delta = d;
                        }
                    }

                    total++;
                    if (delta > tolerance.PerPixelDelta)
                    {
                        different++;
                        map[(y - top) * (right - left) + (x - left)] = true;
                    }
                }
            }

            var fraction = total == 0 ? 1.0 : (double)different / total;
            return new ComparisonResult(fraction <= tolerance.MaxDifferentFraction, fraction, different, total, map, right - left, bottom - top, left, top);
        }
        finally
        {
            golden.UnlockBits(goldenData);
            canonical.UnlockBits(freshData);
        }
    }
}
