using System.Runtime.InteropServices;
using Xunit;

namespace UI;

// The app degrades past a refused low-level mouse hook (Conclave-PC policy
// fails SetWindowsHookEx), so the middle-click test probes the same API
// from the test process and skips honestly where the box cannot install
// hooks. CI and dev boxes install fine, so the suite stays identical there.
internal static class UiHooks
{
    const int WH_MOUSE_LL = 14;

    internal static void SkipWhenUnavailable()
    {
        HookProc proc = static (code, wParam, lParam) => NativeMethods.CallNextHookEx(nint.Zero, code, wParam, lParam);
        nint hook = NativeMethods.SetWindowsHookEx(WH_MOUSE_LL, proc, NativeMethods.GetModuleHandle(null), 0);
        if (hook != nint.Zero)
        {
            _ = NativeMethods.UnhookWindowsHookEx(hook);
            return;
        }

        Assert.Skip($"Low-level mouse hooks are unavailable on this host (Win32 error {Marshal.GetLastWin32Error()}).");
    }

    delegate nint HookProc(int code, nint wParam, nint lParam);

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

        [DllImport("kernel32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetModuleHandle([MarshalAs(UnmanagedType.LPWStr)] string? moduleName);
    }
}
