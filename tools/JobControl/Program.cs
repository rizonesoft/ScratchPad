// Job-object leg containment for the §15 watchdog (D00 T02 §15 PR21,
// R3-F2, PR13): legs run out of process inside a named Windows Job
// Object, so kills reap exactly the leg's tree, abandoned handles kill
// stragglers at close, and dumps target exact PIDs. Verbs:
//   JobControl run --job <name> --out <log> --timeout <secs> [--dump <dir>] -- <exe> [args]
//   JobControl kill --job <name>
//   JobControl pids --job <name>
//   JobControl dump --pid <n> --out <file>
// Every verb prints one machine-readable JOBCTL line; exit 0 on success
// (even when the child failed: the code rides the line), exit 2 on tool
// error. A missing job reads as empty (killed=0, no pids), never an
// error: close-then-kill races resolve to nothing-left.
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

if (args.Length == 0)
{
    Console.Error.WriteLine("usage: JobControl <run|kill|pids|dump> ...");
    return 2;
}

return args[0] switch
{
    "run" => Run(args.Skip(1).ToArray()),
    "kill" => Kill(args.Skip(1).ToArray()),
    "pids" => Pids(args.Skip(1).ToArray()),
    "dump" => Dump(args.Skip(1).ToArray()),
    _ => Usage("unknown verb"),
};

static int Usage(string message)
{
    Console.Error.WriteLine($"JobControl: {message}");
    return 2;
}

static string? Flag(string[] rest, string name)
{
    // Flags stop at the `--` separator: the child's own arguments must
    // never satisfy the tool's parse (a suite arg shaped like a flag
    // would otherwise hijack the job name, log, or timeout). Both the
    // flag and its value must precede the separator.
    int end = Array.IndexOf(rest, "--");
    if (end < 0)
    {
        end = rest.Length;
    }

    for (int i = 0; i + 1 < end; i++)
    {
        if (rest[i] == name)
        {
            return rest[i + 1];
        }
    }

    return null;
}

static int Run(string[] rest)
{
    string? job = Flag(rest, "--job");
    string? log = Flag(rest, "--out");
    string? timeoutText = Flag(rest, "--timeout");
    string? dumpDir = Flag(rest, "--dump");
    int dash = Array.IndexOf(rest, "--");
    if (job is null || log is null || timeoutText is null || !int.TryParse(timeoutText, out int timeout) || timeout <= 0 || dash < 0 || dash + 1 >= rest.Length)
    {
        return Usage("run --job <name> --out <log> --timeout <secs> [--dump <dir>] -- <exe> [args]");
    }

    string exe = rest[dash + 1];
    string arguments = dash + 2 < rest.Length ? string.Join(" ", rest.Skip(dash + 2).Select(Quote)) : "";
    nint hJob = Native.CreateJobObject(nint.Zero, job);
    if (hJob == nint.Zero)
    {
        return Usage($"CreateJobObject failed ({Marshal.GetLastWin32Error()})");
    }

    try
    {
        var limits = new Native.JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            BasicLimitInformation = new Native.JOBOBJECT_BASIC_LIMIT_INFORMATION
            {
                LimitFlags = Native.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            },
        };
        int size = Marshal.SizeOf<Native.JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
        nint blob = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(limits, blob, false);
            if (!Native.SetInformationJobObject(hJob, Native.JobObjectExtendedLimitInformation, blob, (uint)size))
            {
                return Usage($"SetInformationJobObject failed ({Marshal.GetLastWin32Error()})");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }

        var inherit = new Native.SECURITY_ATTRIBUTES
        {
            nLength = Marshal.SizeOf<Native.SECURITY_ATTRIBUTES>(),
            lpSecurityDescriptor = nint.Zero,
            bInheritHandle = true,
        };
        nint hLog = Native.CreateFile(log, Native.GENERIC_WRITE, Native.FILE_SHARE_READ, ref inherit, Native.CREATE_ALWAYS, 0, nint.Zero);
        if (hLog == Native.INVALID_HANDLE_VALUE)
        {
            return Usage($"cannot open {log} ({Marshal.GetLastWin32Error()})");
        }

        nint hNul = Native.CreateFile("NUL", Native.GENERIC_READ, Native.FILE_SHARE_READ | Native.FILE_SHARE_WRITE, ref inherit, Native.OPEN_EXISTING, 0, nint.Zero);
        if (hNul == Native.INVALID_HANDLE_VALUE)
        {
            Native.CloseHandle(hLog);
            return Usage($"cannot open NUL ({Marshal.GetLastWin32Error()})");
        }

        try
        {
            var startup = new Native.STARTUPINFO();
            startup.cb = Marshal.SizeOf<Native.STARTUPINFO>();
            startup.dwFlags = Native.STARTF_USESTDHANDLES;
            startup.hStdOutput = hLog;
            startup.hStdError = hLog;
            startup.hStdInput = hNul;
            var command = new StringBuilder();
            command.Append(Quote(exe));
            if (arguments.Length > 0)
            {
                command.Append(' ').Append(arguments);
            }

            char[] commandChars = new char[command.Length + 1];
            command.CopyTo(0, commandChars, 0, command.Length);
            if (!Native.CreateProcess(null, commandChars, nint.Zero, nint.Zero, true, Native.CREATE_SUSPENDED | Native.CREATE_NEW_PROCESS_GROUP, nint.Zero, null, ref startup, out Native.PROCESS_INFORMATION child))
            {
                return Usage($"CreateProcess failed ({Marshal.GetLastWin32Error()})");
            }

            _ = Native.CloseHandle(hNul);
            try
            {
                // Assigned before the first resume, so no descendant can
                // escape between spawn and containment.
                if (!Native.AssignProcessToJobObject(hJob, child.hProcess))
                {
                    int error = Marshal.GetLastWin32Error();
                    try { Process.GetProcessById(child.dwProcessId).Kill(); } catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception) { }
                    return Usage($"AssignProcessToJobObject failed ({error})");
                }

                _ = Native.ResumeThread(child.hThread);
                int clamped = Math.Min(timeout, 86400);
                uint wait = Native.WaitForSingleObject(child.hProcess, (uint)(clamped * 1000));
                bool timedOut = wait == Native.WAIT_TIMEOUT;
                int dumped = 0;
                if (timedOut)
                {
                    // Dump before the kill (D00 T02 §15 PR13): the hung
                    // tree's state is the evidence; post-kill there is
                    // nothing left to dump. Best effort per PID.
                    if (dumpDir is not null)
                    {
                        Directory.CreateDirectory(dumpDir);
                        foreach (long frozen in JobPids(hJob))
                        {
                            if (DumpPid((int)frozen, Path.Combine(dumpDir, $"{frozen}.dmp")))
                            {
                                dumped++;
                            }
                        }
                    }

                    _ = Native.TerminateJobObject(hJob, 1);
                    _ = Native.WaitForSingleObject(child.hProcess, 30_000);
                }

                _ = Native.GetExitCodeProcess(child.hProcess, out uint code);
                Console.WriteLine($"JOBCTL code={(timedOut ? "TIMEOUT" : $"{code}")} timeout={(timedOut ? 1 : 0)} pid={child.dwProcessId} dumped={dumped}");
                return 0;
            }
            finally
            {
                Native.CloseHandle(child.hThread);
                Native.CloseHandle(child.hProcess);
            }
        }
        finally
        {
            Native.CloseHandle(hLog);
        }
    }
    finally
    {
        // Kill-on-close backstop: any handle abandonment reaps stragglers.
        Native.CloseHandle(hJob);
    }
}

static int Kill(string[] rest)
{
    string? job = Flag(rest, "--job");
    if (job is null)
    {
        return Usage("kill --job <name>");
    }

    nint hJob = Native.OpenJobObject(Native.JOB_OBJECT_TERMINATE | Native.JOB_OBJECT_QUERY, false, job);
    if (hJob == nint.Zero)
    {
        // Already closed (or never created): nothing left to kill.
        Console.WriteLine("JOBCTL killed=0 pids=");
        return 0;
    }

    try
    {
        long[] before = JobPids(hJob);
        if (!Native.TerminateJobObject(hJob, 1))
        {
            return Usage($"TerminateJobObject failed ({Marshal.GetLastWin32Error()})");
        }

        Console.WriteLine($"JOBCTL killed={before.Length} pids={string.Join(",", before)}");
        return 0;
    }
    finally
    {
        Native.CloseHandle(hJob);
    }
}

static int Pids(string[] rest)
{
    string? job = Flag(rest, "--job");
    if (job is null)
    {
        return Usage("pids --job <name>");
    }

    nint hJob = Native.OpenJobObject(Native.JOB_OBJECT_QUERY, false, job);
    if (hJob == nint.Zero)
    {
        Console.WriteLine("JOBCTL pids=");
        return 0;
    }

    try
    {
        Console.WriteLine($"JOBCTL pids={string.Join(",", JobPids(hJob))}");
        return 0;
    }
    finally
    {
        Native.CloseHandle(hJob);
    }
}

static int Dump(string[] rest)
{
    string? pidText = Flag(rest, "--pid");
    string? log = Flag(rest, "--out");
    if (pidText is null || log is null || !int.TryParse(pidText, out int pid))
    {
        return Usage("dump --pid <n> --out <file>");
    }

    if (!DumpPid(pid, log))
    {
        return Usage($"dump of {pid} failed ({Marshal.GetLastWin32Error()})");
    }

    Console.WriteLine($"JOBCTL dump={log} bytes={new FileInfo(log).Length}");
    return 0;
}

static bool DumpPid(int pid, string log)
{
    nint hProcess = Native.OpenProcess(Native.PROCESS_QUERY_INFORMATION | Native.PROCESS_VM_READ, false, (uint)pid);
    if (hProcess == nint.Zero)
    {
        return false;
    }

    try
    {
        var noInherit = new Native.SECURITY_ATTRIBUTES
        {
            nLength = Marshal.SizeOf<Native.SECURITY_ATTRIBUTES>(),
            lpSecurityDescriptor = nint.Zero,
            bInheritHandle = false,
        };
        nint hFile = Native.CreateFile(log, Native.GENERIC_WRITE, 0, ref noInherit, Native.CREATE_ALWAYS, 0, nint.Zero);
        if (hFile == Native.INVALID_HANDLE_VALUE)
        {
            return false;
        }

        try
        {
            return Native.MiniDumpWriteDump(hProcess, (uint)pid, hFile, 0, nint.Zero, nint.Zero, nint.Zero);
        }
        finally
        {
            _ = Native.CloseHandle(hFile);
        }
    }
    finally
    {
        _ = Native.CloseHandle(hProcess);
    }
}

static long[] JobPids(nint hJob)
{
    // Variable-length list: oversize the buffer, then read the count.
    const int capacity = 1024;
    int size = 8 + (capacity * 8);
    nint blob = Marshal.AllocHGlobal(size);
    try
    {
        if (!Native.QueryInformationJobObject(hJob, Native.JobObjectBasicProcessIdList, blob, (uint)size, out _))
        {
            return [];
        }

        int count = Marshal.ReadInt32(blob, 4);
        var pids = new List<long>(Math.Min(count, capacity));
        for (int i = 0; i < Math.Min(count, capacity); i++)
        {
            pids.Add(Marshal.ReadInt64(blob, 8 + (i * 8)));
        }

        return [.. pids];
    }
    finally
    {
        Marshal.FreeHGlobal(blob);
    }
}

static string Quote(string value)
{
    if (!value.Any(char.IsWhiteSpace) && !value.Contains('"', StringComparison.Ordinal))
    {
        return value;
    }

    return "\"" + value.Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";
}

internal static class Native
{
    internal const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    internal const int JobObjectExtendedLimitInformation = 9;
    internal const int JobObjectBasicProcessIdList = 3;
    internal const uint JOB_OBJECT_TERMINATE = 0x0008;
    internal const uint JOB_OBJECT_QUERY = 0x0004;
    internal const uint GENERIC_WRITE = 0x40000000;
    internal const uint GENERIC_READ = 0x80000000;
    internal const uint FILE_SHARE_READ = 0x00000001;
    internal const uint FILE_SHARE_WRITE = 0x00000002;
    internal const uint CREATE_ALWAYS = 2;
    internal const uint OPEN_EXISTING = 3;
    internal const nint INVALID_HANDLE_VALUE = -1;
    internal const uint STARTF_USESTDHANDLES = 0x100;
    internal const uint CREATE_SUSPENDED = 0x4;
    internal const uint CREATE_NEW_PROCESS_GROUP = 0x200;
    internal const int STD_INPUT_HANDLE = -10;
    internal const uint WAIT_TIMEOUT = 0x102;
    internal const uint PROCESS_QUERY_INFORMATION = 0x0400;
    internal const uint PROCESS_VM_READ = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    internal struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public nuint MinimumWorkingSetSize;
        public nuint MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public nuint Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public nuint ProcessMemoryLimit;
        public nuint JobMemoryLimit;
        public nuint PeakProcessMemoryUsed;
        public nuint PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public nint lpReserved2;
        public nint hStdInput;
        public nint hStdOutput;
        public nint hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROCESS_INFORMATION
    {
        public nint hProcess;
        public nint hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct SECURITY_ATTRIBUTES
    {
        public int nLength;
        public nint lpSecurityDescriptor;
        public bool bInheritHandle;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint CreateJobObject(nint attrs, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetInformationJobObject(nint hJob, int infoClass, nint info, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AssignProcessToJobObject(nint hJob, nint hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TerminateJobObject(nint hJob, uint code);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint OpenJobObject(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool QueryInformationJobObject(nint hJob, int infoClass, nint info, uint size, out uint returned);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(nint handle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint CreateFile(string name, uint access, uint share, ref SECURITY_ATTRIBUTES security, uint disposition, uint flags, nint template);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CreateProcess(string? app, char[] command, nint processAttrs, nint threadAttrs, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint flags, nint env, string? dir, ref STARTUPINFO startup, out PROCESS_INFORMATION info);

    [DllImport("kernel32.dll")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern uint ResumeThread(nint hThread);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern uint WaitForSingleObject(nint handle, uint millis);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetExitCodeProcess(nint hProcess, out uint code);

    [DllImport("kernel32.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    internal static extern nint OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);

    [DllImport("Dbghelp.dll", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool MiniDumpWriteDump(nint hProcess, uint pid, nint hFile, uint dumpType, nint expParam, nint userStream, nint callback);
}
