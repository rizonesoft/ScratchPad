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
        // Cross-DPI rasterization noise (D00 T02 §6): goldens rendered at
        // 150% device DPI and downscaled differ from native-100% CI renders
        // at glyph edges with large per-channel deltas (measured 1128px and
        // 3414px on identical chrome, 2026-09-17). A 3x3 box blur on both
        // sides collapses that single-pixel noise (to 18px and 21px) while a
        // 10px layout shift still reads 1069px against the 500px threshold,
        // so delta 96 and 0.1% stand unchanged. The TenPixelShift probe below
        // guards this: if blur ever blinds a real shift, the probe goes green
        // and fails the suite.
        using var goldenSoft = BoxBlur(golden);
        using var freshSoft = BoxBlur(canonical);
        var left = (int)(tolerance.CanonicalWidth * tolerance.CropSideFraction);
        var top = (int)(tolerance.CanonicalHeight * tolerance.CropTopFraction);
        var right = tolerance.CanonicalWidth - (int)(tolerance.CanonicalWidth * tolerance.CropSideFraction);
        var bottom = tolerance.CanonicalHeight - (int)(tolerance.CanonicalHeight * tolerance.CropBottomFraction);

        var rect = new Rectangle(0, 0, canonical.Width, canonical.Height);
        var goldenData = goldenSoft.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var freshData = freshSoft.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
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
            goldenSoft.UnlockBits(goldenData);
            freshSoft.UnlockBits(freshData);
        }
    }

    internal static Bitmap BoxBlur(Bitmap source)
    {
        var rect = new Rectangle(0, 0, source.Width, source.Height);
        var data = source.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var length = data.Stride * data.Height;
            var src = new byte[length];
            Marshal.Copy(data.Scan0, src, 0, length);
            var dst = new byte[length];
            for (var y = 0; y < data.Height; y++)
            {
                var y0 = Math.Max(y - 1, 0);
                var y1 = Math.Min(y + 1, data.Height - 1);
                for (var x = 0; x < data.Width; x++)
                {
                    var x0 = Math.Max(x - 1, 0);
                    var x1 = Math.Min(x + 1, data.Width - 1);
                    var sum0 = 0;
                    var sum1 = 0;
                    var sum2 = 0;
                    var count = 0;
                    for (var yy = y0; yy <= y1; yy++)
                    {
                        for (var xx = x0; xx <= x1; xx++)
                        {
                            var off = yy * data.Stride + xx * 4;
                            sum0 += src[off];
                            sum1 += src[off + 1];
                            sum2 += src[off + 2];
                            count++;
                        }
                    }

                    var dout = y * data.Stride + x * 4;
                    dst[dout] = (byte)(sum0 / count);
                    dst[dout + 1] = (byte)(sum1 / count);
                    dst[dout + 2] = (byte)(sum2 / count);
                    dst[dout + 3] = src[y * data.Stride + x * 4 + 3];
                }
            }

            var blurred = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
            var outData = blurred.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try
            {
                Marshal.Copy(dst, 0, outData.Scan0, length);
            }
            finally
            {
                blurred.UnlockBits(outData);
            }

            return blurred;
        }
        finally
        {
            source.UnlockBits(data);
        }
    }
}
