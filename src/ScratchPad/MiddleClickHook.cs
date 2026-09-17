using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Windows.Foundation;

namespace ScratchPad;

// Intercepts middle-button presses for the tab strip's probed
// middle-click-to-close. Two quieter doors were tried first and proven shut:
// WinUI raises no PointerPressed for the middle button (press logging: left
// and right log, middle never arrives), and a window-proc subclass on all six
// of the window's HWNDs sees no POINTER or legacy middle message at all, yet
// the TabView still strips its own containers on down+up without raising
// TabCloseRequested and without touching the model. The island input stack
// delivers the gesture below window messaging, so this sits lower still: a
// low-level mouse hook, which the system calls on the installing (UI) thread
// for every mouse event process-wide. The callback stays off XAML: it
// hit-tests the cursor against cached tab bounds (refreshed every layout
// pass) and swallows only a down over a tab plus its paired up, queueing the
// close through the normal prompted path. Everything else passes through, so
// editor middle-click auto-scroll keeps working for D02. Installed by
// MainWindow once the HWND exists (first activation/loaded), which owns the
// HWND. Multi-window (§9) routes by root ancestor; single-window for now.
internal sealed class MiddleClickHook : IDisposable
{
    const int WH_MOUSE_LL = 14;

    const uint WM_MBUTTONDOWN = 0x0207;

    const uint WM_MBUTTONUP = 0x0208;

    const uint GA_ROOT = 2;

    readonly nint top;

    readonly Func<Point, bool> onMiddleDown;

    readonly DispatcherQueue queue;

    readonly HookProc proc;

    readonly nint hook;

    readonly List<Rect> tabRects = new();

    double scale = 1;

    bool swallowed;

    bool disposed;

    internal MiddleClickHook(nint window, Func<Point, bool> onMiddleDown, DispatcherQueue queue)
    {
        top = window;
        this.onMiddleDown = onMiddleDown;
        this.queue = queue;
        proc = HookCallback;
        hook = NativeMethods.SetWindowsHookEx(WH_MOUSE_LL, proc, NativeMethods.GetModuleHandle(null), 0);
        if (hook == 0)
        {
            throw new InvalidOperationException($"SetWindowsHookEx failed with error {Marshal.GetLastWin32Error()}.");
        }
    }

    ~MiddleClickHook()
    {
        Dispose(false);
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    void Dispose(bool disposing)
    {
        if (!disposed)
        {
            disposed = true;
            _ = NativeMethods.UnhookWindowsHookEx(hook);
            if (disposing)
            {
                tabRects.Clear();
            }
        }
    }

    // Refreshed from MainWindow's LayoutUpdated: tab bounds in window DIP
    // plus the rasterization scale, so the hook callback never touches XAML.
    internal void UpdateTabs(IReadOnlyList<Rect> dipRects, double rasterizationScale)
    {
        tabRects.Clear();
        tabRects.AddRange(dipRects);
        scale = rasterizationScale;
    }

    nint HookCallback(int code, nint wParam, nint lParam)
    {
        if (code >= 0)
        {
            if (wParam == (nint)WM_MBUTTONDOWN)
            {
                var screen = Marshal.PtrToStructure<NativePoint>(lParam);
                if (TrySwallowDown(screen))
                {
                    return 1;
                }
            }
            else if (wParam == (nint)WM_MBUTTONUP && swallowed)
            {
                swallowed = false;
                return 1;
            }
        }

        return NativeMethods.CallNextHookEx(hook, code, wParam, lParam);
    }

    // Runs on the UI thread (low-level hooks marshal to the installer), but
    // keeps to p/invoke plus arithmetic: the close itself is queued through
    // the normal path, and a miss returns to the chain untouched.
    bool TrySwallowDown(NativePoint screen)
    {
        nint hit = NativeMethods.WindowFromPoint(screen);
        if (hit == 0 || NativeMethods.GetAncestor(hit, GA_ROOT) != top)
        {
            return false;
        }

        var client = screen;
        _ = NativeMethods.ScreenToClient(top, ref client);
        var dip = new Point(client.X / scale, client.Y / scale);
        foreach (Rect rect in tabRects)
        {
            if (rect.Contains(dip))
            {
                swallowed = true;
                var physical = new Point(client.X, client.Y);
                _ = queue.TryEnqueue(() => onMiddleDown(physical));
                return true;
            }
        }

        return false;
    }

    delegate nint HookProc(int code, nint wParam, nint lParam);

    // The head of MSLLHOOKSTRUCT; the fields past the point are unread.
    [StructLayout(LayoutKind.Sequential)]
    struct NativePoint
    {
        internal int X;

        internal int Y;
    }

    static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint SetWindowsHookEx(int idHook, HookProc lpfn, nint hMod, int dwThreadId);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool UnhookWindowsHookEx(nint hhk);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint CallNextHookEx(nint hhk, int nCode, nint wParam, nint lParam);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint WindowFromPoint(NativePoint point);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetAncestor(nint hWnd, uint gaFlags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern bool ScreenToClient(nint hWnd, ref NativePoint point);

        [DllImport("kernel32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetModuleHandle([MarshalAs(UnmanagedType.LPWStr)] string? moduleName);
    }
}
