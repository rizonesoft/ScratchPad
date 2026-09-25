using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace UI;

// Launch diagnostics, schema launch-diagnostics/2 (D00 T02 §18 item
// 7): one JSON record per UI launch attempt, appended to a daily
// JSONL file under the test output directory. Fields: schema (this
// constant), ts (UTC ISO-8601), test (calling file:member), args
// (redacted), pid (null when the launch threw), error (exception
// class plus first line, null on success), hwnd (first visible
// top-level window of the pid, null when none appears in the wait),
// hwndLineage (owner chain outward from the window, [] when none),
// bounds ([left,top,right,bottom] or null), monitor (device name of
// the bounds, "unknown" without a window), move (seeded-offscreen,
// explicit-kept, unseeded-defaults, headless, tool, shell, or
// launch-failed),
// seedX/seedY (the geometry the seed chose, 0/0 when unseeded). The
// move pairs seed to launch by call order (consumed once, reset
// after each launch); every UI test seeds before it launches, so
// the pairing is exact in-suite. Nulls are valid data (a forced
// failure quotes all seven fields with nulls plus the error), never
// missing fields: every record carries every key. Schema 2 (D00 T02
// §41 item 8) adds sweep: the app's sweep-log lines for the recorded
// window's birth (the sweep and any delayed pass: construction
// generation, attribution, reasons, and move readbacks), [] when the
// launch had no background birth or no window.
internal static class UiLaunchDiagnostics
{
    internal const string Schema = "launch-diagnostics/2";

    internal const string SweepLogVariable = "SCRATCHPAD_SWEEP_LOG";

    internal static string NewSweepLogPath()
    {
        string dir = Path.Combine(Path.GetDirectoryName(LogPath())!, "sweep");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, $"{Guid.NewGuid():N}.log");
    }

    static readonly TimeSpan HwndWait = TimeSpan.FromSeconds(2);

    static readonly Regex SecretValue = new(
        """(?i)(password|passwd|pwd|token|secret|api[-_]?key|\bauth\b|bearer)([\s:=]+)("[^"]*"|'[^']*'|[^\s]+)""",
        RegexOptions.Compiled);

    internal static string LogPath() => Path.Combine(
        AppContext.BaseDirectory,
        "launch-diagnostics",
        "launches-" + DateTime.UtcNow.ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture) + ".jsonl");

    internal static string RedactArgs(string args) => SecretValue.Replace(args, "$1$2***");

    // Launch-log retention (D00 T02 §18 C-A1): daily launches
    // files prune past 30 days, mirroring the bundle retention
    // (same data types, same rule).
    internal static void PruneOldLaunches(string diagnosticsRoot, int retentionDays = 30)
    {
        if (!Directory.Exists(diagnosticsRoot))
        {
            return;
        }

        // Per-launch sweep logs a record kept (its delayed pass had not
        // logged, §41 R3-F3) clear after a day.
        string sweepDir = Path.Combine(diagnosticsRoot, "sweep");
        if (Directory.Exists(sweepDir))
        {
            foreach (string stale in Directory.EnumerateFiles(sweepDir, "*.log").Where(f => (DateTime.UtcNow - File.GetLastWriteTimeUtc(f)).TotalDays > 1))
            {
                try
                {
                    File.Delete(stale);
                }
                catch (IOException)
                {
                    // Best effort.
                }
            }
        }

        foreach (string file in Directory.EnumerateFiles(diagnosticsRoot, "launches-*.jsonl"))
        {
            string name = Path.GetFileNameWithoutExtension(file);
            if (name.Length > "launches-".Length
                && DateTime.TryParseExact(
                    name["launches-".Length..],
                    "yyyyMMdd",
                    null,
                    System.Globalization.DateTimeStyles.None,
                    out DateTime day)
                && (DateTime.UtcNow.Date - day).TotalDays > retentionDays)
            {
                try
                {
                    File.Delete(file);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    // Best-effort retention; a locked file waits for
                    // the next launch instead of breaking this one.
                }
            }
        }
    }

    internal static void Record(
        string testId,
        string args,
        int? pid,
        string? error,
        string move,
        int seedX,
        int seedY,
        bool expectWindow = true,
        string? sweepLog = null,
        bool ownsSweepLog = false)
    {
        PruneOldLaunches(Path.GetDirectoryName(LogPath())!);
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
            ["sweep"] = SweepLines(sweepLog, hwnd, ownsSweepLog),
        };
        // Correlation and completeness (D00 T02 §48 item 7): the record
        // quotes the generation its own lines carry and states the sweep
        // outcome, so concurrent launches never borrow each other's lines.
        var summary = SweepSummary((string[])record["sweep"]!, hwnd);
        record["generation"] = summary.Generation;
        record["sweepOutcome"] = summary.Outcome;
        string path = LogPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.AppendAllText(path, JsonSerializer.Serialize(record) + Environment.NewLine);
    }

    // The sweep lines for one birth (§41 item 8): waits up to the window
    // bound for the birth's sweep line, then returns every line naming
    // that main. A per-launch log is deleted once read.
    static string[] SweepLines(string? path, nint main, bool owns)
    {
        // Only background births sweep, so a foreground launch waits for
        // nothing.
        bool background = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable) == "1";
        if (path is null || main == nint.Zero || !background)
        {
            if (owns && path is not null)
            {
                try
                {
                    File.Delete(path);
                }
                catch (IOException)
                {
                    // Best effort.
                }
            }

            return [];
        }

        // The birth's sweep line and its delayed pass (R3-F3): the record
        // waits, bounded, for both; a missing delayed pass is named, and its
        // log is kept (the pass may still append; the prune clears it).
        string prefix = $" main=0x{(long)main:X} ";
        string[] found = [];
        var deadline = DateTime.UtcNow + HwndWait + HwndWait;
        bool late = false;
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                found = File.Exists(path) ? [.. File.ReadAllLines(path).Where(l => l.StartsWith("sweep", StringComparison.Ordinal) && l.Contains(prefix, StringComparison.Ordinal))] : [];
            }
            catch (IOException)
            {
                found = [];
            }

            late = found.Any(l => l.StartsWith("sweep-late ", StringComparison.Ordinal));
            if (late)
            {
                break;
            }

            Thread.Sleep(100);
        }

        if (found.Length > 0 && !late)
        {
            return [.. found, $"sweep-late main=0x{(long)main:X} missing: the delayed pass had not logged within {(HwndWait + HwndWait).TotalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)} s of the launch"];
        }

        if (owns)
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
                // Best effort: a later sweep-late line may still be writing.
            }
        }

        return found;
    }

    // One record's sweep summary (D00 T02 §48 item 7): only lines naming
    // this main count; the generation is theirs (null when none, or
    // "conflict" when they disagree); the outcome is complete (a sweep
    // and its delayed pass), late-missing, log-missing (no line for a
    // background birth), truncated (a line the parser cannot read), or
    // none (no background birth).
    internal static (object? Generation, string Outcome) SweepSummary(string[] lines, nint main)
    {
        if (main == nint.Zero || Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable) != "1")
        {
            return (null, lines.Length == 0 ? "none" : "unexpected-lines");
        }

        string prefix = $" main=0x{(long)main:X} ";
        var mine = lines.Where(l => l.Contains(prefix, StringComparison.Ordinal)).ToList();
        if (mine.Count == 0)
        {
            return (null, "log-missing");
        }

        var gens = new HashSet<long>();
        foreach (string l in mine)
        {
            var m = Regex.Match(l, @" gen=(\d+) ");
            if (m.Success)
            {
                gens.Add(long.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture));
            }
            else if (!l.Contains(" missing:", StringComparison.Ordinal))
            {
                return (null, "truncated");
            }
        }

        object? gen = gens.Count == 1 ? gens.First() : gens.Count == 0 ? null : "conflict";
        bool late = mine.Any(l => l.StartsWith("sweep-late ", StringComparison.Ordinal) && !l.Contains(" missing:", StringComparison.Ordinal));
        return (gen, late ? "complete" : "late-missing");
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
