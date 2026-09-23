using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace UI;

// Launch diagnostics, schema launch-diagnostics/1 (D00 T02 §18 item
// 7): one JSON record per UI launch attempt, appended to a daily
// JSONL file under the test output directory. Fields: schema (this
// constant), ts (UTC ISO-8601), test (calling file:member), args
// (redacted), pid (null when the launch threw), error (exception
// class plus first line, null on success), hwnd (first visible
// top-level window of the pid, null when none appears in the wait),
// hwndLineage (owner chain outward from the window, [] when none),
// bounds ([left,top,right,bottom] or null), monitor (device name of
// the bounds, "unknown" without a window), move (seeded-offscreen,
// explicit-kept, unseeded-defaults, headless, or launch-failed),
// seedX/seedY (the geometry the seed chose, 0/0 when unseeded). The
// move pairs seed to launch by call order (consumed once, reset
// after each launch); every UI test seeds before it launches, so
// the pairing is exact in-suite. Nulls are valid data (a forced
// failure quotes all seven fields with nulls plus the error), never
// missing fields: every record carries every key.
internal static class UiLaunchDiagnostics
{
    internal const string Schema = "launch-diagnostics/1";

    static readonly TimeSpan HwndWait = TimeSpan.FromSeconds(2);

    static readonly Regex SecretValue = new(
        """(?i)(password|passwd|pwd|token|secret|api[-_]?key|\bauth\b|bearer)([\s:=]+)("[^"]*"|'[^']*'|[^\s]+)""",
        RegexOptions.Compiled);

    internal static string LogPath() => Path.Combine(
        AppContext.BaseDirectory,
        "launch-diagnostics",
        "launches-" + DateTime.UtcNow.ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture) + ".jsonl");

    internal static string RedactArgs(string args) => SecretValue.Replace(args, "$1$2***");

    internal static void Record(
        string testId,
        string args,
        int? pid,
        string? error,
        string move,
        int seedX,
        int seedY,
        bool expectWindow = true)
    {
        nint hwnd = nint.Zero;
        int[]? bounds = null;
        long[] lineage = [];
        string monitor = "unknown";
        if (pid is not null && expectWindow)
        {
            hwnd = WaitFirstWindow(pid.Value, HwndWait);
            if (hwnd != nint.Zero)
            {
                bounds = WindowRect(hwnd);
                lineage = OwnerLineage(hwnd);
                monitor = MonitorOf(hwnd);
            }
        }

        var record = new Dictionary<string, object?>
        {
            ["schema"] = Schema,
            ["ts"] = DateTime.UtcNow.ToString("o"),
            ["test"] = testId,
            ["args"] = RedactArgs(args),
            ["pid"] = pid,
            ["error"] = error is null ? null : RedactArgs(error),
            ["hwnd"] = hwnd == nint.Zero ? null : (object)hwnd.ToInt64(),
            ["hwndLineage"] = lineage,
            ["bounds"] = bounds,
            ["monitor"] = monitor,
            ["move"] = move,
            ["seedX"] = seedX,
            ["seedY"] = seedY,
        };
        string path = LogPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.AppendAllText(path, JsonSerializer.Serialize(record) + Environment.NewLine);
    }

    internal static bool IsVisible(nint hwnd) => Native.IsWindowVisible(hwnd);

    internal static uint DpiOf(nint hwnd) => Native.GetDpiForWindow(hwnd);

    internal static string RawTitle(nint hwnd)
    {
        char[] text = new char[256];
        int written = Native.GetWindowText(hwnd, text, text.Length);
        return written > 0 ? new string(text, 0, Math.Min(written, text.Length)) : string.Empty;
    }

    static nint WaitFirstWindow(int pid, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            nint found = nint.Zero;
            Native.EnumWindows((hwnd, param) =>
            {
                _ = Native.GetWindowThreadProcessId(hwnd, out uint windowPid);
                if (windowPid == (uint)pid && Native.IsWindowVisible(hwnd))
                {
                    found = hwnd;
                    return false;
                }

                return true;
            }, nint.Zero);
            if (found != nint.Zero)
            {
                return found;
            }

            Thread.Sleep(100);
        }

        return nint.Zero;
    }

    internal static int[] WindowRect(nint hwnd)
    {
        var rect = new Rect();
        return Native.GetWindowRect(hwnd, ref rect)
            ? [rect.Left, rect.Top, rect.Right, rect.Bottom]
            : [0, 0, 0, 0];
    }

    internal static long[] OwnerLineage(nint hwnd)
    {
        var chain = new List<long> { hwnd.ToInt64() };
        nint owner = Native.GetWindow(hwnd, Native.GwOwner);
        while (owner != nint.Zero)
        {
            chain.Add(owner.ToInt64());
            owner = Native.GetWindow(owner, Native.GwOwner);
        }

        return [.. chain];
    }

    internal static string MonitorOf(nint hwnd)
    {
        nint monitor = Native.MonitorFromWindow(hwnd, Native.MonitorDefaultToNearest);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        return Native.GetMonitorInfo(monitor, ref info) ? info.DeviceName : "unknown";
    }

    [StructLayout(LayoutKind.Sequential)]
    struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MonitorInfo
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
    }

    static class Native
    {
        internal const uint GwOwner = 4;
        internal const uint MonitorDefaultToNearest = 2;

        internal delegate bool EnumWindowsProc(nint hwnd, nint param);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool EnumWindows(EnumWindowsProc callback, nint param);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint pid);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool IsWindowVisible(nint hwnd);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool GetWindowRect(nint hwnd, ref Rect rect);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetWindow(nint hwnd, uint command);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint MonitorFromWindow(nint hwnd, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetDpiForWindow(nint hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetWindowText(nint hwnd, char[] text, int capacity);
    }
}
