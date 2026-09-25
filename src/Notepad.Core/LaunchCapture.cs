namespace Notepad.Core;

// Launch capture seam (D00 T02 §21 item 4, hardened by D00 T02 §28
// item 7). The UI suite pins the Bing commands end to end by capturing
// the URI instead of opening a browser. The seam is test-only by
// construction: it activates only when the capture variable names a
// file AND the test-run marker is exactly "1", so a stray capture
// variable in a real user's environment launches the browser as usual.
// A capture that cannot be written is reported, never swallowed, so a
// test cannot read "no launch" when the seam itself failed.
public static class LaunchCapture
{
    public const string CaptureVariable = "SCRATCHPAD_TEST_LAUNCH_CAPTURE";
    public const string RunMarkerVariable = "SCRATCHPAD_TEST_RUN";

    // The capture file when the seam is active, else null (launch normally).
    public static string? ActivePath(Func<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);
        string? path = environment(CaptureVariable);
        return !string.IsNullOrWhiteSpace(path) && string.Equals(environment(RunMarkerVariable), "1", StringComparison.Ordinal)
            ? path
            : null;
    }

    // Appends the URI as one line. Returns null on success, else the
    // failure text the caller must surface.
    public static string? Record(string path, Uri url, Action<string, string>? append = null)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(url);
        append ??= File.AppendAllText;
        try
        {
            append(path, url.AbsoluteUri + "\n");
            return null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return $"launch capture failed: could not write {path} ({ex.GetType().Name}: {ex.Message}); the URI was neither captured nor launched";
        }
    }
}
