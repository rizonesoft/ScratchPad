using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;

namespace UI;

// Physical pointer moves (D00 T12 §2). Three faults made the
// 2026-10-03 hover drive miss: testhost is DPI-unaware, so a point read
// outside PerMonitorV2 arrives virtualized and the cursor lands up-left
// of its target at 150%; SetCursorPos alone is no input event; and a
// cursor already parked on the target makes no enter transition. Every
// real cursor move here reads in one PerMonitorV2 context, moves by
// injected input, and proves the pixel; Hover approaches from outside.
// Buttons and the wheel ride FlaUI's coordinate-free Mouse.Down/Up/Scroll.
// The source guard (UiPointerGuardTests) keeps raw moves out of the suite.
internal static partial class UiPointer
{
    // The element's clickable point in physical pixels.
    internal static Point ClickablePoint(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        nint previous = UiDpi.Enter();
        try
        {
            return element.GetClickablePoint();
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // The element's bounding rectangle in physical pixels.
    internal static Rectangle Bounds(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        nint previous = UiDpi.Enter();
        try
        {
            return element.BoundingRectangle;
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // Reads the element's clickable point and moves the cursor there in
    // one PerMonitorV2 context; returns the physical point used.
    internal static Point MoveTo(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        nint previous = UiDpi.Enter();
        try
        {
            Point point = element.GetClickablePoint();
            Set(point);
            return point;
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // Hovers an element: approaches from a point just left of its bounds,
    // then lands on its clickable point, so the element sees a real
    // enter transition. A move to where the cursor already sits makes
    // no motion, and an element born under a stationary cursor raises no
    // PointerEntered (2026-10-03: reruns left the cursor parked on the
    // swatch, and the next run's hover never fired).
    internal static Point Hover(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        nint previous = UiDpi.Enter();
        try
        {
            Rectangle bounds = element.BoundingRectangle;
            Point target = element.GetClickablePoint();
            Set(new Point(bounds.Left - 12, target.Y));
            Thread.Sleep(150);
            Set(target);
            return target;
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // Moves the cursor to a physical point (one from ClickablePoint).
    internal static void MoveTo(Point physical)
    {
        nint previous = UiDpi.Enter();
        try
        {
            Set(physical);
        }
        finally
        {
            UiDpi.Exit(previous);
        }
    }

    // Straight-line travel between two physical points: `steps` moves,
    // `delayMs` apart, ending exactly on `to`.
    internal static void Travel(Point from, Point to, int steps, int delayMs)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(steps, 1);
        for (int step = 1; step <= steps; step++)
        {
            MoveTo(new Point(
                ((from.X * (steps - step)) + (to.X * step)) / steps,
                ((from.Y * (steps - step)) + (to.Y * step)) / steps));
            Thread.Sleep(delayMs);
        }
    }

    // Moves by injected input, then pins and proves the exact pixel.
    // SetCursorPos alone generates no input event, so a WinUI element
    // never sees PointerEntered from it (2026-10-03: the cursor sat on
    // the swatch and no hover fired; clicks worked only because
    // mouse_event buttons are input). An absolute SendInput move over
    // the virtual desktop is the event a real mouse makes; the follow-up
    // SetCursorPos corrects the normalized-coordinate rounding.
    static void Set(Point point)
    {
        const uint move = 0x0001;
        const uint absolute = 0x8000;
        const uint virtualDesk = 0x4000;
        int vx = NativeMethods.GetSystemMetrics(76);
        int vy = NativeMethods.GetSystemMetrics(77);
        int vw = Math.Max(2, NativeMethods.GetSystemMetrics(78));
        int vh = Math.Max(2, NativeMethods.GetSystemMetrics(79));
        var input = new NativeInput
        {
            Type = 0,
            Mouse = new NativeMouseInput
            {
                Dx = (int)Math.Round((point.X - vx) * 65535.0 / (vw - 1)),
                Dy = (int)Math.Round((point.Y - vy) * 65535.0 / (vh - 1)),
                Flags = move | absolute | virtualDesk,
            },
        };
        if (NativeMethods.SendInput(1, [input], Marshal.SizeOf<NativeInput>()) != 1)
        {
            throw new InvalidOperationException($"UiPointer: SendInput move to {point.X},{point.Y} failed (Win32 error {Marshal.GetLastWin32Error()})");
        }

        if (!NativeMethods.SetCursorPos(point.X, point.Y))
        {
            throw new InvalidOperationException($"UiPointer: SetCursorPos({point.X},{point.Y}) failed (Win32 error {Marshal.GetLastWin32Error()})");
        }

        if (!NativeMethods.GetCursorPos(out NativePoint landed) || landed.X != point.X || landed.Y != point.Y)
        {
            throw new InvalidOperationException($"UiPointer: cursor at {landed.X},{landed.Y}, wanted {point.X},{point.Y}");
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct NativeMouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }

    // INPUT with the mouse arm. MOUSEINPUT is the widest union member
    // (32 bytes on x64, aligned after the 4-byte type), so this
    // sequential layout is the full 40-byte INPUT SendInput expects.
    [StructLayout(LayoutKind.Sequential)]
    struct NativeInput
    {
        public uint Type;
        public NativeMouseInput Mouse;
    }

    // Raw cursor moves outside this file, as `<path>:<line>: <text>`.
    // Comment lines are skipped; any code line naming a raw move counts.
    internal static IReadOnlyList<string> FindRawMoves(string source, string path)
    {
        ArgumentNullException.ThrowIfNull(source);
        var hits = new List<string>();
        string[] lines = source.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].TrimEnd('\r');
            if (line.TrimStart().StartsWith("//", StringComparison.Ordinal))
            {
                continue;
            }

            if (RawMove().IsMatch(line))
            {
                hits.Add($"{path}:{i + 1}: {line.Trim()}");
            }
        }

        return hits;
    }

    [GeneratedRegex(@"\bMouse\s*\.\s*(MoveTo\s*\(|Position\s*=(?!=))|\bSetCursorPos\s*\(")]
    private static partial Regex RawMove();

    static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool GetCursorPos(out NativePoint point);

        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint SendInput(uint count, NativeInput[] inputs, int size);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetSystemMetrics(int index);
    }
}
