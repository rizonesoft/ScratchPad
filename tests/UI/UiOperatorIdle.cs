using System.Globalization;
using System.Runtime.InteropServices;

namespace UI;

// Operator-idle gate for foreground tests (operator decision 2026-10-14):
// a forced Interactive run happens in the daytime, scoped to one feature,
// so before any fenced test takes the keyboard and mouse the run waits
// until the operator has left the input alone for SCRATCHPAD_IDLE_SECONDS
// (default 60; 0 disables). If that never happens within
// SCRATCHPAD_IDLE_MAX_WAIT_SECONDS (default 900) the fenced tests report
// Skipped as operator-active, and the gate records them Night-owed. The
// wait runs once per test host, at discovery, before any test starts;
// listing (SCRATCHPAD_DISCOVERY_LISTING=1) never waits.
internal static class UiOperatorIdle
{
    internal const string IdleVariable = "SCRATCHPAD_IDLE_SECONDS";
    internal const string MaxWaitVariable = "SCRATCHPAD_IDLE_MAX_WAIT_SECONDS";
    internal static readonly TimeSpan DefaultIdle = TimeSpan.FromSeconds(60);
    internal static readonly TimeSpan DefaultMaxWait = TimeSpan.FromSeconds(900);

    static readonly Lazy<string?> Verdict = new(() =>
        WaitForIdle(
            IdleTime,
            ReadSeconds(Environment.GetEnvironmentVariable(IdleVariable), DefaultIdle),
            ReadSeconds(Environment.GetEnvironmentVariable(MaxWaitVariable), DefaultMaxWait),
            Thread.Sleep));

    internal static string? SkipUnlessIdle() => GatedTheoryAttribute.Listing ? null : Verdict.Value;

    // Sleeps exactly until the idle threshold could be met (never past the
    // max wait), then re-reads: input in between restarts the count.
    internal static string? WaitForIdle(Func<TimeSpan?> idleProbe, TimeSpan required, TimeSpan maxWait, Action<TimeSpan> sleep)
    {
        ArgumentNullException.ThrowIfNull(idleProbe);
        ArgumentNullException.ThrowIfNull(sleep);
        if (required <= TimeSpan.Zero)
        {
            return null;
        }

        TimeSpan waited = TimeSpan.Zero;
        while (true)
        {
            TimeSpan? idle = idleProbe();
            if (idle is null)
            {
                return "Operator idle time is unreadable (GetLastInputInfo failed); fenced tests never run blind. Record them Night-owed.";
            }

            if (idle.Value >= required)
            {
                return null;
            }

            TimeSpan left = maxWait - waited;
            if (left <= TimeSpan.Zero)
            {
                return $"Operator active: no {required.TotalSeconds:0}s without input within {maxWait.TotalSeconds:0}s ({IdleVariable}, {MaxWaitVariable}). Record the fenced tests Night-owed.";
            }

            TimeSpan step = required - idle.Value;
            if (step > left)
            {
                step = left;
            }

            sleep(step);
            waited += step;
        }
    }

    internal static TimeSpan ReadSeconds(string? value, TimeSpan fallback) =>
        int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int seconds) && seconds >= 0
            ? TimeSpan.FromSeconds(seconds)
            : fallback;

    static TimeSpan? IdleTime()
    {
        var info = new Native.LastInputInfo { Size = (uint)Marshal.SizeOf<Native.LastInputInfo>() };
        if (!Native.GetLastInputInfo(ref info))
        {
            return null;
        }

        // Both counters are milliseconds since boot on the same 32-bit
        // clock, so unsigned subtraction survives the 49.7-day wrap.
        return TimeSpan.FromMilliseconds(unchecked((uint)Environment.TickCount - info.Time));
    }

    static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct LastInputInfo
        {
            internal uint Size;
            internal uint Time;
        }

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetLastInputInfo(ref LastInputInfo info);
    }
}
