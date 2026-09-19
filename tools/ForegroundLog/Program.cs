// Foreground log for the §8 uninterrupted gate: polls the foreground
// window every 250 ms and records each change as
// <utc-timestamp> <hwnd> <process> <title>. Alongside, a census snapshots
// every app HWND each poll (monitor, rect, iconic state), recording each
// HWND once at first sighting. Usage:
//   ForegroundLog <seconds> <logpath> [process-name-to-flag] [--expect-primary]
//   ForegroundLog launch <exe> [args]  (no-activate process start for probing)
// The gate is green when the app never held the foreground AND no app
// window rests on the primary monitor (exit 0); either condition fails
// loud (exit 1). Resting means seen visibly on the primary twice: birth
// flashes (visible ~200 ms between show and minimize) rarely span two
// polls, while genuinely resting windows persist. Placement is by rect
// intersection, so off-screen windows read "offscreen", never primary.
// Iconic, invisible, and zero-area HWNDs are recorded but excluded.
// --expect-primary inverts the placement assertion for the placement run
// (Category=Primary): green needs zero holds AND at least one window
// resting on the primary, proving the declared set really landed there.
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

if (args.Length > 0 && args[0] == "launch")
{
    return Launch(args.Skip(1).ToArray());
}

if (args.Length < 2 || !int.TryParse(args[0], out int seconds) || seconds <= 0)
{
    Console.Error.WriteLine("usage: ForegroundLog <seconds> <logpath> [process-name] [--expect-primary]");
    return 2;
}

string logPath = args[1];
bool expectPrimary = args.Contains("--expect-primary");
string flag = args.Length > 2 && args[2] != "--expect-primary" ? args[2] : "ScratchPad";
var deadline = DateTime.UtcNow.AddSeconds(seconds);
nint last = nint.Zero;
int flagged = 0;
var census = new Dictionary<nint, CensusEntry>();
var sightings = new Dictionary<nint, int>();
var primarySeen = new HashSet<nint>();
using var log = new StreamWriter(logPath, append: false, Encoding.UTF8);
while (DateTime.UtcNow < deadline)
{
    nint hwnd = Native.GetForegroundWindow();
    if (hwnd != last)
    {
        last = hwnd;
        string process = ProcessName(hwnd);
        string title = WindowTitle(hwnd);
        log.WriteLine($"{DateTime.UtcNow:O} {hwnd} {process} {title}");
        log.Flush();
        if (string.Equals(process, flag, StringComparison.OrdinalIgnoreCase))
        {
            flagged++;
        }
    }

    // Census rides every poll (250 ms), not a slower cadence: fast tests
    // show a window for ~1 s, and a 1 s cadence demonstrably misses them
    // (Run B probe: census=0 over two 2 s tests). EnumWindows each tick is
    // cheap next to the suite it watches.
    UpdateCensus(census, sightings, primarySeen, flag);
    Thread.Sleep(250);
}

foreach ((nint hwnd, CensusEntry entry) in census.OrderBy(pair => pair.Key))
{
    log.WriteLine($"CENSUS {hwnd} pid={entry.Pid} {entry.Monitor} {entry.Rect} iconic={entry.Iconic} visible={entry.Visible} {entry.Title}");
}

log.Flush();
bool placed = expectPrimary ? primarySeen.Count > 0 : primarySeen.Count == 0;
Console.WriteLine($"changes logged; flagged={flagged}; census={census.Count} primary={primarySeen.Count} expect={(expectPrimary ? "primary" : "secondary")}");
return flagged == 0 && placed ? 0 : 1;

void UpdateCensus(Dictionary<nint, CensusEntry> census, Dictionary<nint, int> sightings, HashSet<nint> primarySeen, string flag)
{
    var monitors = new List<(Native.Rect Rect, bool Primary)>();
    Native.EnumDisplayMonitors(
        nint.Zero,
        nint.Zero,
        (nint mon, nint dc, ref Native.Rect rc, nint data) =>
        {
            var info = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>() };
            if (Native.GetMonitorInfo(mon, ref info))
            {
                monitors.Add((info.Monitor, (info.Flags & 1) == 1));
            }

            return true;
        },
        nint.Zero);

    Native.EnumWindows(
        (hwnd, unused) =>
        {
            _ = unused;
            _ = Native.GetWindowThreadProcessId(hwnd, out uint pid);
            string process;
            try
            {
                process = Process.GetProcessById((int)pid).ProcessName;
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
            {
                return true;
            }

            if (!string.Equals(process, flag, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            bool iconic = Native.IsIconic(hwnd);
            bool visible = Native.IsWindowVisible(hwnd);
            string monitor = "iconic";
            string rect = "iconic";
            if (!iconic)
            {
                _ = Native.GetWindowRect(hwnd, out Native.Rect bounds);
                rect = $"{bounds.Left},{bounds.Top},{bounds.Right - bounds.Left}x{bounds.Bottom - bounds.Top}";
                bool onPrimary = false;
                bool onAny = false;
                foreach ((Native.Rect region, bool primary) in monitors)
                {
                    if (Intersects(bounds, region))
                    {
                        onAny = true;
                        onPrimary |= primary;
                    }
                }

                monitor = !onAny ? "offscreen" : onPrimary ? "primary" : "secondary";
                int area = Math.Max(0, bounds.Right - bounds.Left) * Math.Max(0, bounds.Bottom - bounds.Top);
                if (onPrimary && visible && area > 0)
                {
                    // Persistence: a window rests on the primary only when
                    // seen there twice. Birth flashes (visible for ~200 ms
                    // between show and minimize) rarely span two polls;
                    // genuinely resting windows persist.
                    sightings[hwnd] = sightings.TryGetValue(hwnd, out int seen) ? seen + 1 : 1;
                    if (sightings[hwnd] >= 2)
                    {
                        primarySeen.Add(hwnd);
                    }
                }
            }

            census.TryAdd(hwnd, new CensusEntry((int)pid, monitor, rect, iconic, visible, WindowTitle(hwnd)));
            return true;
        },
        nint.Zero);
}

static bool Intersects(Native.Rect a, Native.Rect b) =>
    a.Left < b.Right && b.Left < a.Right && a.Top < b.Bottom && b.Top < a.Bottom;

static string ProcessName(nint hwnd)
{
    _ = Native.GetWindowThreadProcessId(hwnd, out uint pid);
    try
    {
        return Process.GetProcessById((int)pid).ProcessName;
    }
    catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
    {
        return "?";
    }
}

static string WindowTitle(nint hwnd)
{
    var buffer = new char[256];
    int length = Native.GetWindowText(hwnd, buffer, buffer.Length);
    return length == 0 ? string.Empty : new string(buffer, 0, length);
}

static int Launch(string[] rest)
{
    if (rest.Length < 1)
    {
        Console.Error.WriteLine("usage: ForegroundLog launch <exe> [args]");
        return 2;
    }

    nint before = Native.GetForegroundWindow();
    var startup = new Native.StartupInfo();
    startup.Cb = (uint)Marshal.SizeOf<Native.StartupInfo>();
    startup.Flags = 0x00000001;
    startup.ShowWindow = 4; // SW_SHOWNOACTIVATE
    bool ok = Native.CreateProcess(
        null,
        $"\"{rest[0]}\" {(rest.Length > 1 ? rest[1] : string.Empty)}",
        nint.Zero, nint.Zero, false, 0, nint.Zero, null,
        ref startup, out Native.ProcessInfo info);
    if (!ok)
    {
        Console.Error.WriteLine($"CreateProcess failed: {Marshal.GetLastWin32Error()}");
        return 1;
    }

    Thread.Sleep(3000);
    nint after = Native.GetForegroundWindow();
    Console.WriteLine($"pid={info.ProcessId} foreground-unchanged={before == after}");
    Native.CloseHandle(info.Process);
    Native.CloseHandle(info.Thread);
    return before == after ? 0 : 1;
}

static class Native
{
    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern int GetWindowText(nint hWnd, char[] text, int maxCount);

    internal delegate bool EnumWindowsProc(nint hWnd, nint lParam);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetWindowRect(nint hWnd, out Rect rect);

    internal delegate bool MonitorEnumProc(nint hMonitor, nint hdc, ref Rect rect, nint data);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumDisplayMonitors(nint hdc, nint clip, MonitorEnumProc callback, nint data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct MonitorInfo
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetMonitorInfo(nint hMonitor, ref MonitorInfo info);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsIconic(nint hWnd);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindowVisible(nint hWnd);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct StartupInfo
    {
        public uint Cb;
        public string Reserved;
        public string Desktop;
        public string Title;
        public uint X;
        public uint Y;
        public uint XSize;
        public uint YSize;
        public uint XCountChars;
        public uint YCountChars;
        public uint FillAttribute;
        public uint Flags;
        public short ShowWindow;
        public short CbReserved2;
        public nint LpReserved2;
        public nint StdInput;
        public nint StdOutput;
        public nint StdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct ProcessInfo
    {
        public nint Process;
        public nint Thread;
        public uint ProcessId;
        public uint ThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CreateProcess(
        string? application, string commandLine,
        nint processAttributes, nint threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint creationFlags,
        nint environment, string? directory,
        ref StartupInfo startup, out ProcessInfo info);

    [DllImport("kernel32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(nint handle);
}

sealed record CensusEntry(int Pid, string Monitor, string Rect, bool Iconic, bool Visible, string Title);
