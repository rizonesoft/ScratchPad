using System.Drawing;
using System.Drawing.Imaging;
using System.Text.Json;

namespace UI;

// Foreground-leak bundle, schema leak-bundle/1 (D00 T02 §18 item 9):
// a directly actionable report for the next leak. Keys: schema, ts,
// test, launchRef ({ts, pid} joined to the item-7 record by pid,
// null when no record matches), hwnd, lineage (owner chain,
// numeric only), bounds, transitions (two timestamped rect samples
// 250 ms apart), monitor, dpi, screenshot (relative path or null),
// args (redacted), title (truncated plus redacted), eventSlices
// (gate EVENT lines for this hwnd, newest 50, [] without a gate
// log). Privacy, redaction, size-cap, and retention rules:
// arguments pass the item-7 redactor; titles truncate to 64 chars
// then redact; screenshots stay under the ignored test-output tree
// (never uploaded) and scale to 1600 px; no memory dumps are ever
// captured; event slices cap at 50 lines; lineage carries numbers
// only; bundle date-dirs older than 30 days prune on capture.
internal static class UiLeakBundle
{
    internal const string Schema = "leak-bundle/1";
    internal const int MaxTitleChars = 64;
    internal const int MaxEventLines = 50;
    internal const int MaxShotPixels = 1600;
    internal const int RetentionDays = 30;

    static readonly System.Text.Json.JsonSerializerOptions Indented = new() { WriteIndented = true };

    internal static string ScrubTitle(string title)
    {
        string cut = title.Length > MaxTitleChars ? title[..MaxTitleChars] : title;
        return UiLaunchDiagnostics.RedactArgs(cut);
    }

    internal static (int Width, int Height) ScaleToCap(int width, int height)
    {
        if (width <= MaxShotPixels && height <= MaxShotPixels)
        {
            return (width, height);
        }

        double scale = (double)MaxShotPixels / Math.Max(width, height);
        return (Math.Max(1, (int)(width * scale)), Math.Max(1, (int)(height * scale)));
    }

    internal static void PruneOldBundles(string bundlesRoot, int retentionDays = RetentionDays)
    {
        if (!Directory.Exists(bundlesRoot))
        {
            return;
        }

        foreach (string dir in Directory.EnumerateDirectories(bundlesRoot))
        {
            string name = Path.GetFileName(dir);
            if (DateTime.TryParseExact(name, "yyyyMMdd", null, System.Globalization.DateTimeStyles.None, out DateTime day)
                && (DateTime.UtcNow.Date - day).TotalDays > retentionDays)
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }

    internal static string Capture(int pid, nint hwnd, string testId, string args, string? gateLogPath = null)
    {
        string day = DateTime.UtcNow.ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture);
        string bundlesRoot = Path.Combine(AppContext.BaseDirectory, "launch-diagnostics", "bundles");
        PruneOldBundles(bundlesRoot);
        string clock = DateTime.UtcNow.ToString("HHmmss", System.Globalization.CultureInfo.InvariantCulture);
        string dir = Path.Combine(bundlesRoot, day, $"{Sanitize(testId)}-{clock}");
        Directory.CreateDirectory(dir);

        int[]? bounds = hwnd == nint.Zero ? null : UiLaunchDiagnostics.WindowRect(hwnd);
        bool visible = hwnd != nint.Zero && UiLaunchDiagnostics.IsVisible(hwnd);
        string firstTs = DateTime.UtcNow.ToString("o");
        Thread.Sleep(250);
        int[]? bounds2 = hwnd == nint.Zero ? null : UiLaunchDiagnostics.WindowRect(hwnd);
        bool visible2 = hwnd != nint.Zero && UiLaunchDiagnostics.IsVisible(hwnd);
        string secondTs = DateTime.UtcNow.ToString("o");

        string? shot = bounds is not null && visible ? Screenshot(dir, bounds) : null;
        var record = new Dictionary<string, object?>
        {
            ["schema"] = Schema,
            ["ts"] = DateTime.UtcNow.ToString("o"),
            ["test"] = testId,
            ["launchRef"] = LaunchRef(pid),
            ["hwnd"] = hwnd == nint.Zero ? null : (object)hwnd.ToInt64(),
            ["lineage"] = hwnd == nint.Zero ? [] : UiLaunchDiagnostics.OwnerLineage(hwnd),
            ["bounds"] = bounds,
            ["transitions"] = new object[]
            {
                new Dictionary<string, object?> { ["ts"] = firstTs, ["rect"] = bounds, ["visible"] = visible },
                new Dictionary<string, object?> { ["ts"] = secondTs, ["rect"] = bounds2, ["visible"] = visible2 },
            },
            ["monitor"] = hwnd == nint.Zero ? "unknown" : UiLaunchDiagnostics.MonitorOf(hwnd),
            ["dpi"] = hwnd == nint.Zero ? null : (object)UiLaunchDiagnostics.DpiOf(hwnd),
            ["screenshot"] = shot,
            ["args"] = UiLaunchDiagnostics.RedactArgs(args),
            ["title"] = hwnd == nint.Zero ? string.Empty : ScrubTitle(UiLaunchDiagnostics.RawTitle(hwnd)),
            ["eventSlices"] = gateLogPath is null ? [] : EventSlices(gateLogPath, hwnd, pid),
        };
        string path = Path.Combine(dir, "bundle.json");
        File.WriteAllText(path, JsonSerializer.Serialize(record, Indented));
        return path;
    }

    static Dictionary<string, object?>? LaunchRef(int pid)
    {
        string log = UiLaunchDiagnostics.LogPath();
        if (!File.Exists(log))
        {
            return null;
        }

        foreach (string line in File.ReadLines(log).Reverse())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            using var document = JsonDocument.Parse(line);
            JsonElement root = document.RootElement;
            if (root.TryGetProperty("pid", out JsonElement id)
                && id.ValueKind == JsonValueKind.Number
                && id.GetInt32() == pid)
            {
                return new Dictionary<string, object?>
                {
                    ["ts"] = root.GetProperty("ts").GetString(),
                    ["pid"] = pid,
                };
            }
        }

        return null;
    }

    static string? Screenshot(string dir, int[] bounds)
    {
        int width = Math.Max(1, bounds[2] - bounds[0]);
        int height = Math.Max(1, bounds[3] - bounds[1]);
        (int w, int h) = ScaleToCap(width, height);
        try
        {
            using var full = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (var graphics = Graphics.FromImage(full))
            {
                graphics.CopyFromScreen(bounds[0], bounds[1], 0, 0, full.Size);
            }

            using var shot = w == width && h == height
                ? full
                : new Bitmap(full, new Size(w, h));
            string path = Path.Combine(dir, "leak.png");
            shot.Save(path, ImageFormat.Png);
            return "leak.png";
        }
        catch (Exception ex) when (ex is ArgumentException or System.ComponentModel.Win32Exception or OutOfMemoryException)
        {
            return null;
        }
    }

    static string[] EventSlices(string gateLogPath, nint hwnd, int pid)
    {
        if (!File.Exists(gateLogPath))
        {
            return [];
        }

        string token = $" {hwnd.ToInt64()} ";
        string pidToken = $"pid={pid}";
        var hits = new List<string>();
        foreach (string line in File.ReadLines(gateLogPath))
        {
            if (line.StartsWith("EVENT ", StringComparison.Ordinal)
                && (line.Contains(token, StringComparison.Ordinal) || line.Contains(pidToken, StringComparison.Ordinal)))
            {
                hits.Add(line);
            }
        }

        return [.. hits.TakeLast(MaxEventLines)];
    }

    static string Sanitize(string testId)
    {
        var clean = new string([.. testId.Select(c => char.IsLetterOrDigit(c) ? c : '-')]);
        return clean.Length > 80 ? clean[..80] : clean;
    }
}
