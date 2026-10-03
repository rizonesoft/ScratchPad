using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;

namespace UI;

// Physical pointer moves (D00 T12 §2). testhost is DPI-unaware, so a
// clickable point read outside a PerMonitorV2 context arrives
// virtualized and the real cursor lands up-left of its target on a
// scaled display (at 150% the 2026-10-03 hover drive sat at 140,417
// while the swatch was at about 208,628, so no hover fired). Every real
// cursor move reads its point and sets the cursor inside one
// PerMonitorV2 context here; buttons and the wheel ride FlaUI's
// coordinate-free Mouse.Down/Up/Scroll. The source guard
// (UiPointerGuardTests) keeps raw cursor moves out of the suite.
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

    static void Set(Point point)
    {
        if (!NativeMethods.SetCursorPos(point.X, point.Y))
        {
            throw new InvalidOperationException($"UiPointer: SetCursorPos({point.X},{point.Y}) failed (Win32 error {Marshal.GetLastWin32Error()})");
        }
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
    }
}
