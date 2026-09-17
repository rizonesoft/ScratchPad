// Foreground log for the §8 uninterrupted gate: polls the foreground
// window every 250 ms and records each change as
// <utc-timestamp> <hwnd> <process> <title>. The default suite passes the
// gate when no line names the app under test. Usage:
//   ForegroundLog <seconds> <logpath> [process-name-to-flag]
//   ForegroundLog launch <exe> [args]  (no-activate process start for probing)
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

if (args.Length > 0 && args[0] == "launch")
{
    return Launch(args.Skip(1).ToArray());
}

if (args.Length < 2 || !int.TryParse(args[0], out int seconds) || seconds <= 0)
{
    Console.Error.WriteLine("usage: ForegroundLog <seconds> <logpath> [process-name]");
    return 2;
}

string logPath = args[1];
string flag = args.Length > 2 ? args[2] : "ScratchPad";
var deadline = DateTime.UtcNow.AddSeconds(seconds);
nint last = nint.Zero;
int flagged = 0;
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

    Thread.Sleep(250);
}

Console.WriteLine($"changes logged; flagged={flagged}");
return flagged == 0 ? 0 : 1;

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
