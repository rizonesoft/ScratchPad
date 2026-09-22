// Foreground log for the §8 uninterrupted gate: polls the foreground
// window every 250 ms and records each change as
// <utc-timestamp> <hwnd> <process> <title>. Alongside, a census snapshots
// every app HWND each poll (monitor, rect, iconic state), recording each
// HWND at first sighting and upgrading to the latest non-iconic sighting
// so resting placement reads off the lines. A placement-event log
// (D00 T02 §18) records each flagged HWND's first visible bounds from
// EVENT_OBJECT_SHOW and EVENT_OBJECT_LOCATIONCHANGE, so a primary birth
// shorter than the poll still fails the gate. Usage:
//   ForegroundLog <seconds> <logpath> [process-name-to-flag] [--expect-primary]
//   ForegroundLog launch <exe> [args]  (no-activate process start for probing)
// The gate is green when the app never held the foreground AND the census
// and the event log agree (exit 0). Resting means seen visibly on the
// primary twice. The event log's first visible rect is the birth, even
// when that flash never spans two polls. Placement is by rect intersection,
// so off-screen windows read "offscreen", never primary. Iconic, invisible,
// and zero-area HWNDs are recorded but excluded from the primary assertion.
// Agreement: every placed census window has an event, and the two reports
// agree on whether that window is a primary birth. An off-screen birth
// that later rests on a secondary monitor still agrees. --expect-primary
// inverts the run for Category=Primary: green needs zero holds AND both
// reports show at least one primary window.
using System.ComponentModel;
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
var monitors = new List<(Native.Rect Rect, bool Primary)>();
var openBirths = new Dictionary<nint, EventEntry>();
var closedBirths = new List<(nint Hwnd, EventEntry Entry)>();
var processNames = new Dictionary<uint, string>();
int birthSeq = 0;
Native.WinEventProc onEvent = (hook, eventType, hwnd, idObject, idChild, threadId, time) =>
{
    _ = hook;
    _ = threadId;
    _ = time;
    if (hwnd == nint.Zero)
    {
        return;
    }

    // Destroy retires the open birth so a reused HWND can record again,
    // and the retired line still counts as a birth the poll may have missed.
    if (eventType == Native.EventObjectDestroy)
    {
        if (openBirths.Remove(hwnd, out EventEntry? retired) && retired is not null)
        {
            closedBirths.Add((hwnd, retired));
        }

        return;
    }

    if (idObject != 0 || idChild != 0 || openBirths.ContainsKey(hwnd))
    {
        return;
    }

    try
    {
        _ = Native.GetWindowThreadProcessId(hwnd, out uint pid);
        if (!processNames.TryGetValue(pid, out string? process))
        {
            try
            {
                process = Process.GetProcessById((int)pid).ProcessName;
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
            {
                return;
            }

            processNames[pid] = process;
        }

        if (!string.Equals(process, flag, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        // Cloaked HWNDs (thumbnails, hidden system hosts) report visible
        // and a rect, but they are not a paint. Recording them marked the
        // bottom edge of the primary as a birth.
        if (Native.IsCloaked(hwnd))
        {
            return;
        }

        // Invisible non-iconic location events fire while WinUI is creating
        // the HWND, before the birth move. Those rects are not a paint.
        // A minimized window's restore rect is the birth the show already
        // applied, so record that when the visible moment was missed.
        Native.Rect bounds;
        if (!Native.IsWindowVisible(hwnd))
        {
            if (!Native.IsIconic(hwnd) || !Native.TryNormalRect(hwnd, out bounds))
            {
                return;
            }
        }
        else if (Native.IsIconic(hwnd))
        {
            if (!Native.TryNormalRect(hwnd, out bounds))
            {
                return;
            }
        }
        else if (!Native.GetWindowRect(hwnd, out bounds))
        {
            return;
        }

        int width = bounds.Right - bounds.Left;
        int height = bounds.Bottom - bounds.Top;
        if (width <= 0 || height <= 0)
        {
            return;
        }

        string kind = eventType == Native.EventObjectShow ? "show" : "location";
        openBirths[hwnd] = new EventEntry(birthSeq++, (int)pid, Classify(bounds, monitors), $"{bounds.Left},{bounds.Top},{width}x{height}", kind, WindowTitle(hwnd));
    }
    catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or Win32Exception)
    {
        // A window can die between the event and the rect query. The next
        // event for a live HWND still records; a dead one has no birth.
    }
};
EventHook.Proc = onEvent;
using var log = new StreamWriter(logPath, append: false, Encoding.UTF8);
nint showHook = Native.SetWinEventHook(Native.EventObjectShow, Native.EventObjectShow, nint.Zero, onEvent, 0, 0, Native.WinEventOutOfContext | Native.WinEventSkipOwnProcess);
nint destroyHook = Native.SetWinEventHook(Native.EventObjectDestroy, Native.EventObjectDestroy, nint.Zero, onEvent, 0, 0, Native.WinEventOutOfContext | Native.WinEventSkipOwnProcess);
nint moveHook = Native.SetWinEventHook(Native.EventObjectLocationChange, Native.EventObjectLocationChange, nint.Zero, onEvent, 0, 0, Native.WinEventOutOfContext | Native.WinEventSkipOwnProcess);
try
{
    while (DateTime.UtcNow < deadline)
    {
        RefreshMonitors(monitors);
        var slice = DateTime.UtcNow.AddMilliseconds(250);
        while (DateTime.UtcNow < slice && DateTime.UtcNow < deadline)
        {
            if (!Native.PeekMessage(out Native.Msg msg, nint.Zero, 0, 0, Native.PmRemove))
            {
                Thread.Sleep(15);
                continue;
            }

            _ = Native.TranslateMessage(ref msg);
            _ = Native.DispatchMessage(ref msg);
        }

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
        UpdateCensus(census, sightings, primarySeen, flag, monitors);
    }
}
finally
{
    if (showHook != nint.Zero)
    {
        _ = Native.UnhookWinEvent(showHook);
    }

    if (destroyHook != nint.Zero)
    {
        _ = Native.UnhookWinEvent(destroyHook);
    }

    if (moveHook != nint.Zero)
    {
        _ = Native.UnhookWinEvent(moveHook);
    }
}

var events = new List<(nint Hwnd, EventEntry Entry)>(closedBirths);
foreach ((nint hwnd, EventEntry entry) in openBirths)
{
    events.Add((hwnd, entry));
}

events.Sort((a, b) =>
{
    int byHwnd = a.Hwnd.CompareTo(b.Hwnd);
    return byHwnd != 0 ? byHwnd : a.Entry.Seq.CompareTo(b.Entry.Seq);
});
int eventPrimary = 0;
foreach ((nint hwnd, EventEntry entry) in events)
{
    if (entry.Monitor == "primary")
    {
        eventPrimary++;
    }

    log.WriteLine($"EVENT {hwnd} pid={entry.Pid} {entry.Monitor} {entry.Rect} {entry.Kind} {entry.Title}");
}

int uncovered = 0;
int mismatch = 0;
foreach ((nint hwnd, CensusEntry entry) in census)
{
    if (!Placed(entry))
    {
        continue;
    }

    (nint Hwnd, EventEntry Entry) match = events.LastOrDefault(item => item.Hwnd == hwnd);
    if (match.Entry is null)
    {
        uncovered++;
        continue;
    }

    // The suite moves windows after birth, so off-screen and secondary
    // are the same answer: not a primary birth. Primary on only one side
    // is the flash the poll can miss, or a resting leak the event missed.
    if ((match.Entry.Monitor == "primary") != (entry.Monitor == "primary"))
    {
        mismatch++;
    }
}

foreach ((nint hwnd, CensusEntry entry) in census.OrderBy(pair => pair.Key))
{
    log.WriteLine($"CENSUS {hwnd} pid={entry.Pid} {entry.Monitor} {entry.Rect} iconic={entry.Iconic} visible={entry.Visible} {entry.Title}");
}

log.Flush();
bool censusAgrees = expectPrimary ? primarySeen.Count > 0 : primarySeen.Count == 0;
bool eventAgrees = expectPrimary ? eventPrimary > 0 : eventPrimary == 0;
bool streamsAgree = uncovered == 0 && mismatch == 0 && censusAgrees && eventAgrees;
Console.WriteLine($"changes logged; flagged={flagged}; census={census.Count} primary={primarySeen.Count} events={events.Count} event-primary={eventPrimary} uncovered={uncovered} mismatch={mismatch} expect={(expectPrimary ? "primary" : "secondary")}");
return flagged == 0 && streamsAgree ? 0 : 1;

void RefreshMonitors(List<(Native.Rect Rect, bool Primary)> monitors)
{
    monitors.Clear();
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
}

static string Classify(Native.Rect bounds, List<(Native.Rect Rect, bool Primary)> monitors)
{
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

    return !onAny ? "offscreen" : onPrimary ? "primary" : "secondary";
}

static bool Placed(CensusEntry entry) => !entry.Iconic && entry.Visible && entry.Area > 0;

void UpdateCensus(Dictionary<nint, CensusEntry> census, Dictionary<nint, int> sightings, HashSet<nint> primarySeen, string flag, List<(Native.Rect Rect, bool Primary)> monitors)
{
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
            int area = 0;
            if (!iconic)
            {
                _ = Native.GetWindowRect(hwnd, out Native.Rect bounds);
                rect = $"{bounds.Left},{bounds.Top},{bounds.Right - bounds.Left}x{bounds.Bottom - bounds.Top}";
                monitor = Classify(bounds, monitors);
                area = Math.Max(0, bounds.Right - bounds.Left) * Math.Max(0, bounds.Bottom - bounds.Top);
                if (monitor == "primary" && visible && area > 0)
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

            // Resting state wins: backgrounded windows are born minimized,
            // so first-sighting-only lines would read iconic forever and
            // carry no placement. Non-iconic sightings overwrite; never-shown
            // windows keep their iconic birth record.
            var entry = new CensusEntry((int)pid, monitor, rect, iconic, visible, WindowTitle(hwnd), area);
            if (iconic)
            {
                census.TryAdd(hwnd, entry);
            }
            else
            {
                census[hwnd] = entry;
            }

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

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct WindowPlacement
    {
        public int Length;
        public int Flags;
        public int ShowCmd;
        public Point MinPosition;
        public Point MaxPosition;
        public Rect NormalPosition;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetWindowPlacement(nint hWnd, ref WindowPlacement placement);

    internal static bool TryNormalRect(nint hwnd, out Rect rect)
    {
        rect = default;
        var placement = new WindowPlacement { Length = Marshal.SizeOf<WindowPlacement>() };
        if (!GetWindowPlacement(hwnd, ref placement))
        {
            return false;
        }

        rect = placement.NormalPosition;
        // Iconic coordinates sit at -32000. That is not a birth rect.
        if (rect.Left <= -32000 || rect.Top <= -32000)
        {
            return false;
        }

        return rect.Right > rect.Left && rect.Bottom > rect.Top;
    }

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

    // DWMWA_CLOAKED: non-zero means the window is not painted.
    [DllImport("dwmapi.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out int value, int size);

    internal static bool IsCloaked(nint hwnd)
    {
        int cloaked = 0;
        int hr = DwmGetWindowAttribute(hwnd, 14, out cloaked, sizeof(int));
        return hr == 0 && cloaked != 0;
    }

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

    internal const uint EventObjectDestroy = 0x8001;
    internal const uint EventObjectShow = 0x8002;
    internal const uint EventObjectLocationChange = 0x800B;
    internal const uint WinEventOutOfContext = 0x0000;
    internal const uint WinEventSkipOwnProcess = 0x0002;
    internal const uint PmRemove = 0x0001;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    internal delegate void WinEventProc(
        nint hook, uint eventType, nint hwnd, int idObject, int idChild, uint eventThread, uint eventTime);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint SetWinEventHook(
        uint eventMin, uint eventMax, nint module, WinEventProc callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWinEvent(nint hook);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Msg
    {
        public nint Hwnd;
        public uint Message;
        public nint WParam;
        public nint LParam;
        public uint Time;
        public int PtX;
        public int PtY;
    }

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PeekMessage(out Msg msg, nint hwnd, uint filterMin, uint filterMax, uint remove);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TranslateMessage(ref Msg msg);

    [DllImport("user32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint DispatchMessage(ref Msg msg);
}

// The hook delegate is passed to native code. A static root keeps the GC
// from collecting it while the hooks are installed.
static class EventHook
{
    internal static Native.WinEventProc? Proc;
}

sealed record CensusEntry(int Pid, string Monitor, string Rect, bool Iconic, bool Visible, string Title, int Area);

sealed record EventEntry(int Seq, int Pid, string Monitor, string Rect, string Kind, string Title);
