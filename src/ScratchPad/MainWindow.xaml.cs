using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Notepad.Core;
using Windows.Foundation;
using Windows.Graphics;
using Windows.System;
using WinRT.Interop;

namespace ScratchPad;

public sealed partial class MainWindow : Window, IDisposable
{
    private const string AppName = "ScratchPad";


    private readonly TabModel tabs = new();

    private TabBar? tabBar;
    private Image? titleIconRef;
    private bool titleIconScaleHooked;
    private string titleIconAsset = string.Empty;

    // D01 T02 §4: the status strip plus the box it currently follows.
    // Caret moves do not change Text, so the active box needs its own
    // SelectionChanged hook, re-hung on every tab switch.
    private StatusBar? statusBar;
    private TextBox? hookedBox;
    bool statsDialogOpen;
    bool snapshotsDialogOpen;
    bool templatesDialogOpen;
    bool exportDialogOpen;
    bool lockDialogOpen;

    private MiddleClickHook? middleClick;

    // This construction's sibling-sweep snapshot (D00 T02 §34): only this
    // window's sweep may consume it. A field initializer runs before the
    // base Window constructor (§41 item 9), so helpers the framework
    // creates while constructing the base are this birth's, never
    // preexisting.
    private readonly SiblingSnapshot? siblingSnapshot = SiblingPin.NoteTarget();

    private bool closed;

    // firstWindow selects first-launch behavior: only the first window of the
    // process restores persisted geometry and may show first-run (D01 T01
    // §9); later windows open at the OS default cascade like stock's.
    private readonly bool firstWindow;

    // Tabs restored over missing files, owed the lazy "Cannot find" notice
    // on first activation (D01 T01 §6). Once per tab instance.
    private readonly HashSet<Guid> missingNotice = new();

    // Background-test support (D00 T02 §8): WS_EX_NOACTIVATE so the window
    // can never take the foreground mid-test (menu Invoke and dialog shows
    // activate otherwise). UIA patterns dispatch on no-activate windows
    // (spiked for no-activate shows; this makes the state persistent).
    // WinUI Activate forces the foreground past the style, so background
    // launches never call it: they paint off-screen and the suite places
    // them on the suite display (D00 T02 §18).
    internal void NoActivateForBackground()
    {
        nint hwnd = WindowNative.GetWindowHandle(this);
        if (hwnd == nint.Zero)
        {
            return;
        }

        const int exStyle = -20;
        const nint noActivate = 0x08000000;
        _ = NativeMethods.SetWindowLong(hwnd, exStyle, NativeMethods.GetWindowLong(hwnd, exStyle) | noActivate);
        const uint noMoveSizeZOrderActivateFrameChanged = 0x0037;
        _ = NativeMethods.SetWindowPos(hwnd, nint.Zero, 0, 0, 0, 0, noMoveSizeZOrderActivateFrameChanged);
        if ((NativeMethods.GetWindowLong(hwnd, exStyle) & noActivate) != noActivate)
        {
            throw new InvalidOperationException("background launch could not set WS_EX_NOACTIVATE; refusing a foreground-capable test window");
        }
    }

    // Single rule for unseeded background births (D00 T02 §18): the
    // untouched 50,50 default is not a placement, so it maps to an
    // off-screen origin. PinBirth, RestoreGeometry, and the sibling target
    // share it: the pin and the framework state must agree, or a post-show
    // layout pushes the HWND back to the default (probed 2026-09-23: an
    // unseeded main drifted to (50,50) mid-run and the placement log kept
    // it). Explicit seeds stay as written.
    static (int X, int Y) BirthOrigin(ShellSettings live, int width, int height)
    {
        var untouched = new ShellSettings();
        // Background-only mapping (D00 T02 §18 R3-F1): foreground
        // first windows keep stored geometry as written, so fresh
        // profiles land on-screen. The flag reads fresh per call
        // (tests flip it; no cache).
        if (live.X == untouched.X && live.Y == untouched.Y
            && Environment.GetEnvironmentVariable("SCRATCHPAD_BACKGROUND") == "1")
        {
            return NativeMethods.OffScreenOrigin(width, height);
        }

        return (live.X, live.Y);
    }

    // Background births (D00 T02 §18): the window paints off-screen,
    // never minimized: the minimized park slot plus the restore slide
    // photographed start frames on the primary (probed 2026-09-23),
    // and no per-HWND transition switch covers that slide. The
    // position pin below is best effort (ShowOffScreenForBackground
    // re-moves synchronously, and the suite placement is
    // load-bearing); the sibling sweep is not: helpers born before
    // the main park at the framework default on the primary unless
    // swept here. Later windows keep the stock cascade only for an
    // on-screen explicit seed (the Primary placement set); unseeded
    // maps off-screen first, so backgrounded seconds pin. Returns
    // whether the pin landed (the caller only moves pinned windows).
    internal bool PinBirthBeforeShow()
    {
        nint hwnd = WindowNative.GetWindowHandle(this);
        if (hwnd == nint.Zero)
        {
            return false;
        }

        ShellSettings live = SettingsStore.Shared.Current;
        int width = Math.Max(100, live.Width);
        int height = Math.Max(100, live.Height);
        (int x, int y) = BirthOrigin(live, width, height);
        if (!firstWindow && !NativeMethods.OutsideVirtualScreen(x, y, width, height))
        {
            return false;
        }

        const uint noZOrderNoActivate = 0x0004 | 0x0010;
        if (!NativeMethods.SetWindowPos(hwnd, nint.Zero, x, y, width, height, noZOrderNoActivate))
        {
            throw new InvalidOperationException($"background launch could not pin the birth rect; refusing an unpinned test window (win32 {Marshal.GetLastWin32Error()})");
        }

        // Siblings born before the main (helpers arrive during the
        // constructor) never surface on their own: sweep once here, where
        // the main pin just landed.
        SiblingPin.Sweep(hwnd, siblingSnapshot);
        SiblingPin.PlantLateHelperForTest(hwnd);
        return true;
    }

    // Shows a backgrounded window visible but never minimized (D00 T02
    // §18): WinUI quits hidden-only apps (probed 2026-09-23: clean
    // exit 0 with no shown window), so the window must paint
    // somewhere, and minimized would resurrect the park slot plus the
    // restore slide. The show-move pair below runs in one tick at the
    // pinned target: the rect never rests on the primary (a
    // nanosecond transient, below the gate's hook floor). Not pinned
    // (stock cascade) shows wherever the OS puts it and never moves.
    internal void ShowOffScreenForBackground(bool pinned)
    {
        nint hwnd = WindowNative.GetWindowHandle(this);
        if (hwnd == nint.Zero)
        {
            throw new InvalidOperationException("background launch could not show: no window handle before first show");
        }

        const int showNoActivate = 4;
        _ = NativeMethods.ShowWindow(hwnd, showNoActivate);
        if (!pinned)
        {
            return;
        }

        ShellSettings live = SettingsStore.Shared.Current;
        int width = Math.Max(100, live.Width);
        int height = Math.Max(100, live.Height);
        (int x, int y) = BirthOrigin(live, width, height);
        const uint noZOrderNoActivate = 0x0004 | 0x0010;
        _ = NativeMethods.SetWindowPos(hwnd, nint.Zero, x, y, width, height, noZOrderNoActivate);

        // The delayed placement pass (D00 T02 §41 item 4): helpers born
        // after the sweep (during the show) are decided once more when the
        // UI thread next idles. Helpers born after that pass are runtime
        // popups, owned separately (the documented bound).
        _ = DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => SiblingPin.Late(hwnd));
    }

    static class NativeMethods
    {

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetWindowLong(nint hWnd, int nIndex);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindow(nint hWnd, int cmdShow);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint SetWindowLong(nint hWnd, int nIndex, nint dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(nint hWnd, nint after, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetSystemMetrics(int index);

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        internal delegate bool EnumWindowsProc(nint hWnd, nint lParam);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

        [DllImport("kernel32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetAncestor(nint hWnd, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SetPropW", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetProp(nint hWnd, string name, nint data);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetPropW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint GetProp(nint hWnd, string name);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(nint hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateWindowExW", SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern nint CreateWindowEx(uint exStyle, string className, string windowName, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DestroyWindow(nint hWnd);

        [DllImport("user32.dll")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(nint hWnd, out Rect rect);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetClassNameW")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetClassName(nint hwnd, char[] className, int maxCount);

        internal static string ClassName(nint hwnd)
        {
            var buffer = new char[256];
            int length = GetClassName(hwnd, buffer, buffer.Length);
            return length <= 0 ? "?" : new string(buffer, 0, length);
        }

        internal static bool OutsideVirtualScreen(int x, int y, int width, int height)
        {
            const int smX = 76;
            const int smY = 77;
            const int smCx = 78;
            const int smCy = 79;
            int vx = GetSystemMetrics(smX);
            int vy = GetSystemMetrics(smY);
            long right = (long)x + width;
            long bottom = (long)y + height;
            long screenRight = (long)vx + GetSystemMetrics(smCx);
            long screenBottom = (long)vy + GetSystemMetrics(smCy);
            bool intersects = x < screenRight && vx < right && y < screenBottom && vy < bottom;
            return !intersects;
        }

        // Whole window just past the virtual screen's right edge, or above
        // it when that point does not fit in an int.
        internal static (int X, int Y) OffScreenOrigin(int width, int height)
        {
            long right = (long)GetSystemMetrics(76) + GetSystemMetrics(78);
            int top = GetSystemMetrics(77);
            if (right <= int.MaxValue - width)
            {
                return ((int)right, top);
            }

            long above = (long)top - height;
            if (above < int.MinValue)
            {
                // Fail-closed (D00 T02 §18 C-C1): no on-screen
                // fallback exists, mirroring the suite-side throw.
                // Unreachable for rect screens (pinching both axes
                // needs a width past int range), so a throw here
                // names a broken screen read, never a real layout.
                throw new InvalidOperationException(
                    $"no off-screen birth for virtual origin ({GetSystemMetrics(76)},{top}) window {width}x{height}");
            }

            return (GetSystemMetrics(76), (int)above);
        }
    }

    // Background births (D00 T02 §18): helper top-levels (IME hosts,
    // the GDI hook window) are parked by the framework at its default
    // spot on the primary. A CREATESTRUCT rewrite does not survive:
    // probed 2026-09-23, the creation hook fired and rewrote correctly,
    // but the framework re-parked within a millisecond of creation. A
    // post-creation WinEvent hook cannot close it either: in-context
    // install fails without a module handle (same probe: 1428 on every
    // scope), and an out-of-context self-hook races the gate it serves
    // (the gate registers first, so it always queries first). So the pin
    // is a single synchronous sweep: at main-pin time, every non-main
    // top-level of this process moves to the noted seed, before any
    // out-of-context observer queries. The sweep cannot see child windows
    // (the input sink is one: it never appears in EnumWindows), and it
    // cannot cover late runtime popups; the gate excludes children by
    // construction instead (see ForegroundLog), and runtime popups are
    // owned separately. Mains are excluded by class: the suite positions
    // mains legitimately after attach, and yanking them would break
    // tests. Siblings always park off-screen, even under an on-screen
    // Primary seed: only mains take on-screen seeds. Background launches
    // only.
    static class SiblingPin
    {
        // WinUI top-level class. A rename breaks Primary loudly: swept
        // mains would dodge the suite's on-screen plant.
        const string MainClass = "WinUIDesktopWin32WindowClass";

        static int targetX;
        static int targetY;

        // The ownership mark (§41 item 2): a window property carrying the
        // generation of the snapshot that saw the window.
        const string MarkProperty = "ScratchPad.SiblingMark";

        // The claim mark (§41 R1-F2): the generation of the construction
        // that claimed the window, so a claim survives only on its window.
        const string ClaimProperty = "ScratchPad.SiblingClaim";

        // The last sweep, kept for its delayed pass (§41 item 4).
        // Keyed by main (§41 R1-F4), so a second construction never drops
        // the first one's pending delayed pass.
        static readonly Dictionary<nint, (SiblingSnapshot Snapshot, HashSet<nint> Decided)> PendingLate = [];

        // The planted late helper (a test seam, §41 item 4 fixture).
        static nint plantedLateHelper;

        // The construction in flight (D00 T02 §26, §34 item 4): taken when
        // the constructor begins and consumed once by its sweep, so a failed
        // or overlapping construction never lends its snapshot to the next
        // birth; a sweep with no fresh snapshot pins nothing.
        static readonly SiblingSnapshotSlot Pending = new();

        internal static SiblingSnapshot NoteTarget()
        {
            // Every window seen now is marked with this snapshot's
            // generation (§41 item 2), so a handle reused by a new window
            // later reads unmarked; a window that refused the mark reads
            // ambiguous at the sweep.
            List<nint> seen = [.. ProcessTopLevels().Select(w => w.Handle)];
            SiblingSnapshot token = Pending.Begin(SiblingSelection.Begin(seen, NativeMethods.GetCurrentThreadId(), gen => seen.Where(h => NativeMethods.SetProp(h, MarkProperty, (nint)gen)).ToList()));
            ShellSettings live = SettingsStore.Shared.Current;
            int width = Math.Max(100, live.Width);
            int height = Math.Max(100, live.Height);
            if (!NativeMethods.OutsideVirtualScreen(live.X, live.Y, width, height))
            {
                (targetX, targetY) = NativeMethods.OffScreenOrigin(width, height);
                return token;
            }

            (targetX, targetY) = BirthOrigin(live, width, height);
            return token;
        }

        static List<SiblingTopLevel> ProcessTopLevels()
        {
            uint pid = (uint)Environment.ProcessId;
            var found = new List<SiblingTopLevel>();
            _ = NativeMethods.EnumWindows((hwnd, unused) =>
            {
                _ = unused;
                uint thread = NativeMethods.GetWindowThreadProcessId(hwnd, out uint windowPid);
                if (windowPid == pid)
                {
                    found.Add(Read(hwnd, thread));
                }

                return true;
            }, nint.Zero);
            return found;
        }

        // One window read fresh: its root owner, thread, class, and mark;
        // unreadable when the owner query fails (destroyed mid-read).
        static SiblingTopLevel Read(nint hwnd, uint thread)
        {
            nint rootOwner = NativeMethods.GetAncestor(hwnd, 3);
            string cls = NativeMethods.ClassName(hwnd);
            return new SiblingTopLevel(hwnd, rootOwner, thread, cls == MainClass, (long)NativeMethods.GetProp(hwnd, MarkProperty), thread != 0 && rootOwner != 0, cls, (long)NativeMethods.GetProp(hwnd, ClaimProperty));
        }

        static SiblingTopLevel? ReadNow(nint hwnd)
        {
            if (!NativeMethods.IsWindow(hwnd))
            {
                return null;
            }

            uint thread = NativeMethods.GetWindowThreadProcessId(hwnd, out uint windowPid);
            return windowPid == (uint)Environment.ProcessId ? Read(hwnd, thread) : null;
        }

        // Pins only the constructor-born helpers of the window being born
        // (D00 T02 §26, §34): SiblingSelection skips windows that existed
        // before its construction began, windows another main owns, windows
        // another thread created, and mains. Under the test-run marker the
        // decision is appended to SCRATCHPAD_SWEEP_LOG, so the UI suite reads
        // which handles the sweep chose instead of inferring it from moves.
        internal static void Sweep(nint main, SiblingSnapshot? token)
        {
            SiblingSnapshot? snapshot = Pending.Take(token);
            Pending.Release((h, gen) => NativeMethods.IsWindow(h) && (long)NativeMethods.GetProp(h, ClaimProperty) == gen);
            List<SiblingTopLevel> windows = ProcessTopLevels();
            IReadOnlyList<SiblingDecision> decisions = SiblingSelection.Decide(windows, snapshot, main, Pending.Claims);
            var (final, pinnedAt) = PinDecided(main, windows, decisions);
            long generation = snapshot?.Generation ?? 0;
            if (snapshot is not null)
            {
                // This construction claims its main and every helper it
                // pinned (§41 item 1).
                ClaimAll(generation, final.Where(d => d.Reason == SiblingSelection.Pin).Select(d => d.Handle).Append(main));
                PendingLate[main] = (snapshot, final.Select(d => d.Handle).ToHashSet());
            }

            LogSweep(SiblingSelection.Describe(main, targetX, targetY, final, pinnedAt, "sweep", generation));
        }

        // Pins each selected window after revalidating it (§41 item 5): a
        // handle destroyed, reused, or re-owned between the selection and
        // its move is skipped with the revalidation's reason.
        static (List<SiblingDecision> Final, Dictionary<nint, (int X, int Y)> PinnedAt) PinDecided(nint main, List<SiblingTopLevel> windows, IReadOnlyList<SiblingDecision> decisions)
        {
            var byHandle = windows.ToDictionary(w => w.Handle);
            var final = new List<SiblingDecision>();
            var pinnedAt = new Dictionary<nint, (int X, int Y)>();
            foreach (SiblingDecision d in decisions)
            {
                if (d.Reason != SiblingSelection.Pin)
                {
                    final.Add(d);
                    continue;
                }

                string check = SiblingSelection.Revalidate(byHandle[d.Handle], ReadNow(d.Handle), main);
                if (check != SiblingSelection.Pin)
                {
                    final.Add(d with { Reason = check });
                    continue;
                }

                PinSibling(d.Handle);
                if (NativeMethods.GetWindowRect(d.Handle, out NativeMethods.Rect at))
                {
                    pinnedAt[d.Handle] = (at.Left, at.Top);
                }

                final.Add(d);
            }

            return (final, pinnedAt);
        }

        // The delayed pass (§41 item 4): windows born after the sweep, read
        // once more on the first UI-thread idle after the show.
        internal static void Late(nint main)
        {
            if (!PendingLate.Remove(main, out var last))
            {
                return;
            }

            List<SiblingTopLevel> windows = ProcessTopLevels();
            IReadOnlyList<SiblingDecision> decisions = SiblingSelection.DecideLate(windows, last.Snapshot, main, last.Decided, Pending.Claims, Pending.BegunSince(last.Snapshot));
            var (final, pinnedAt) = PinDecided(main, windows, decisions);
            ClaimAll(last.Snapshot.Generation, final.Where(d => d.Reason == SiblingSelection.Pin).Select(d => d.Handle));
            LogSweep(SiblingSelection.Describe(main, targetX, targetY, final, pinnedAt, "sweep-late", last.Snapshot.Generation));
        }

        // Records the claims and stamps each window with its claim mark.
        static void ClaimAll(long generation, IEnumerable<nint> handles)
        {
            var list = handles.ToList();
            foreach (nint h in list)
            {
                _ = NativeMethods.SetProp(h, ClaimProperty, (nint)generation);
            }

            Pending.Claim(generation, list);
        }

        // Test seam (§41 item 4): under the run marker plus
        // SCRATCHPAD_TEST_LATE_HELPER=1, one hidden unowned popup is created
        // on the UI thread right after the sweep, at an on-screen spot, so
        // the UI suite can prove the delayed pass parks it. Its handle is
        // logged; it is destroyed with the process.
        internal static void PlantLateHelperForTest(nint main)
        {
            if (plantedLateHelper != nint.Zero
                || Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable) != "1"
                || Environment.GetEnvironmentVariable("SCRATCHPAD_TEST_LATE_HELPER") != "1")
            {
                return;
            }

            const uint popup = 0x80000000;
            plantedLateHelper = NativeMethods.CreateWindowEx(0, "STATIC", "late helper", popup, 100, 100, 50, 50, nint.Zero, nint.Zero, nint.Zero, nint.Zero);
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            LogSweep($"planted late-helper main=0x{((long)main).ToString("X", inv)} handle=0x{((long)plantedLateHelper).ToString("X", inv)}");
        }

        static void LogSweep(string line)
        {
            string? log = Environment.GetEnvironmentVariable("SCRATCHPAD_SWEEP_LOG");
            if (string.IsNullOrWhiteSpace(log) || Environment.GetEnvironmentVariable(LaunchCapture.RunMarkerVariable) != "1")
            {
                return;
            }

            try
            {
                File.AppendAllText(log, line + "\n");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Diagnostics only: the sweep already ran; the UI test
                // reading the log fails loud on a missing line.
            }
        }

        static void PinSibling(nint hwnd)
        {
            if (NativeMethods.ClassName(hwnd) == MainClass)
            {
                return;
            }

            if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.Rect bounds)
                && bounds.Left == targetX && bounds.Top == targetY)
            {
                return;
            }

            const uint noSizeNoZOrderNoActivate = 0x0001 | 0x0004 | 0x0010;
            _ = NativeMethods.SetWindowPos(hwnd, nint.Zero, targetX, targetY, 0, 0, noSizeNoZOrderNoActivate);
        }
    }

    public MainWindow(bool firstWindow, SessionWindow? restore = null)
    {
        this.firstWindow = firstWindow;
        InitializeComponent();
        Title = WindowTitle.Format("Untitled", false, AppName);
        ExtendsContentIntoTitleBar = true;
        tabBar = new TabBar { Model = tabs };
        tabBar.SaveAsFallbackAsync = SaveAsForTabAsync;
        tabBar.ReportSaveFailureAsync = ShowSaveFailureAsync;
        WireFileDrops();
        // Crash checkpoint feed (D01 T01 §7): every box edit restarts
        // the App debounce, so a kill restores seconds-old buffers.
        tabBar.TabsEdited += (_, _) =>
        {
            if (Application.Current is App app)
            {
                app.NotifyTabsEdited();
            }

            RefreshStatusBar();
        };
        // D01 T01 §13: pin toggles re-commit the jump list (pins feed it).
        tabBar.PinToggled += (_, _) => App.RefreshJumpList();

        // The HWND is not valid in the constructor; installing here silently
        // subclasses nothing. First activation owns the install.
        Activated += OnFirstActivated;
        // D01 T02 §14: the extended chrome draws no caption glyph, so a
        // raster of the shipped asset pins left of the tab strip in our own
        // row (stock placement per the §14 Fidelity capture). The image takes
        // no input, keeping tab gestures intact; drag rectangles map through
        // TabRegion at the UpdateDragRects call site. Decode state rides
        // ItemStatus so the UI drive proves the glyph rendered, not merely
        // that a 16-DIP box exists. Name is the only other automation
        // property set; ItemStatus transitions are observable to UIA
        // clients that ask.
        // (Raw view would hide the icon from AT entirely, but measured:
        // both UIA drives failed to find it with Raw set and passed after
        // the revert, so control view it is.)
        var titleIcon = new Image
        {
            Width = 16,
            Height = 16,
            Margin = new Thickness(12, 0, 4, 0),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
            IsHitTestVisible = false,
        };
        AutomationProperties.SetAutomationId(titleIcon, "TitleBarIcon");
        AutomationProperties.SetName(titleIcon, "Application icon");
        AutomationProperties.SetItemStatus(titleIcon, "loading");
        titleIcon.Loaded += (_, _) =>
        {
            SelectTitleIconAsset();
            if (!titleIconScaleHooked && titleIcon.XamlRoot is XamlRoot xamlRoot)
            {
                titleIconScaleHooked = true;
                xamlRoot.Changed += (_, _) => SelectTitleIconAsset();
            }
        };
        titleIcon.ImageOpened += (_, _) => AutomationProperties.SetItemStatus(titleIcon, "loaded");
        titleIcon.ImageFailed += (_, e) => AutomationProperties.SetItemStatus(titleIcon, "failed: " + e.ErrorMessage);
        titleIconRef = titleIcon;
        var tabRow = new Grid();
        tabRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        tabRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(titleIcon, 0);
        Grid.SetColumn(tabBar, 1);
        tabRow.Children.Add(titleIcon);
        tabRow.Children.Add(tabBar);
        TabRegion.Content = tabRow;
        MenuRegion.Bind(this);
        // D01 T02 §3: the settings page is live, so Edit > Font enables.
        MenuRegion.SetEnabled("MenuEditFont", true);

        // D01 T02 §5: the print engine is live, so Page Setup and Print enable.
        MenuRegion.SetEnabled("MenuFilePageSetup", true);
        MenuRegion.SetEnabled("MenuFilePrint", true);

        // D01 T02 §4: the status strip lives in the shell's fourth row;
        // the View toggle enables here and the store owns its state.
        statusBar = new StatusBar();
        StatusRegion.Content = statusBar;
        MenuRegion.SetEnabled("MenuViewStatusBar", true);
        MenuRegion.SetStatusBarChecked(SettingsStore.Shared.Current.ShowStatusBar);
        ApplyStatusVisibility();
        // D01 T02 §3: theme changes (and any sibling-window update) apply
        // live; the handler only reads, never writes back.
        SettingsStore.Shared.Changed += OnSettingsChanged;
        // Layout passes also fire during teardown, when transforms and the
        // AppWindow are half-disconnected; touching them stows a crash
        // (0xC000027B). The closed flag parks this handler for those passes.
        tabBar.LayoutUpdated += (_, _) =>
        {
            if (closed)
            {
                return;
            }

            tabBar.ShrinkTabsToFit();
            UpdateDragRects();
            UpdateMiddleClickStrip();
        };
        tabs.PropertyChanged += Tabs_PropertyChanged;
        tabs.Tabs.CollectionChanged += Tabs_CollectionChanged;
        StartReloadWatching();
        if (restore is null)
        {
            tabs.NewTab();
        }
        else
        {
            RestoreSessionWindow(restore);
        }
        if (Content is FrameworkElement root)
        {
            ApplyTheme();
            AddTabAccelerators(root, tabBar);
            // D01 T02 §1: the menu bar owns Ctrl+Shift+N/G/H/E/X/L through
            // its own accelerators; the pre-menu AddAccel bindings lived
            // here and would double-fire beside it.
            // Loaded, not Activated: first-run must show even when the window
            // opens behind others (CI launches never take the foreground).
            root.Loaded += OnFirstLoaded;
        }

        // Restored sessions skip geometry: stock reopens session windows at
        // its default positions, never where they were (two clean negatives).
        if (firstWindow && restore is null)
        {
            RestoreGeometry();
        }

        Closed += OnClosed;
    }

    // Ctrl+Shift+N, recorded live from Notepad (D01 T01 §9): a same-size
    // window at the OS cascade with one untitled tab.
    private static void OpenNewWindow()
    {
        if (Application.Current is App app)
        {
            app.NewWindow();
        }
    }

    // Tab shortcuts, recorded live from Notepad (D01 T01 §3): Ctrl+T new,
    // Ctrl+W close, Ctrl+Tab / Ctrl+Shift+Tab cycle, Ctrl+1..8 positional,
    // Ctrl+9 last, Ctrl+Shift+T reopen. Main number row only; NumPad parity
    // is unprobed. Attached to the root so they fire from any focus.
    private static void AddTabAccelerators(UIElement scope, TabBar bar)
    {
        if (TestMutation.Active(Environment.GetEnvironmentVariable) is not null)
        {
            mutationBar = new WeakReference<TabBar>(bar);
        }
        AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control, bar.NewTab);
        // D01 T02 §1: Ctrl+W belongs to File > Close tab now.
        AddAccel(scope, VirtualKey.Tab, VirtualKeyModifiers.Control, bar.CycleNext);
        AddAccel(scope, VirtualKey.Tab, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, bar.CyclePrevious);
        AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, bar.ReopenLast);
        for (int number = 1; number <= 9; number++)
        {
            int captured = number;
            AddAccel(scope, (VirtualKey)(0x30 + captured), VirtualKeyModifiers.Control, () => bar.GotoNumber(captured));
        }
    }

    // The binding mutation seam for the programmatic tab accelerators (D00
    // T02 §36 items 1 and 4): a targeted accelerator runs a different tab
    // command instead (a new tab; the next tab when it is Ctrl+T itself),
    // and observe mode runs nothing and logs the dispatch. The bar is the
    // last window's (child mutation runs drive one window), held weakly and
    // only while the seam is armed, so a production run keeps no static
    // reference to any window's controls (§36 R3-F3).
    private static WeakReference<TabBar>? mutationBar;

    private static TabBar? Bar() => mutationBar is not null && mutationBar.TryGetTarget(out TabBar? bar) ? bar : null;

    private static bool MutationHandled(VirtualKey key, VirtualKeyModifiers modifiers)
    {
        string target = TestMutation.Key((int)key, (int)modifiers);
        switch (TestMutation.For(target, Environment.GetEnvironmentVariable))
        {
            case MutationEffect.Swap:
                if (key == VirtualKey.T && modifiers == VirtualKeyModifiers.Control)
                {
                    Bar()?.CycleNext();
                }
                else
                {
                    Bar()?.NewTab();
                }

                return true;
            case MutationEffect.Observe:
                TestMutation.RecordOrFail(target, Environment.GetEnvironmentVariable);
                return true;
            default:
                return false;
        }
    }

    private static void AddAccel(UIElement scope, VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accel = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accel.Invoked += (_, args) =>
        {
            if (!MutationHandled(key, modifiers))
            {
                action();
            }

            args.Handled = true;
        };
        scope.KeyboardAccelerators.Add(accel);
    }

    private void Tabs_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(TabModel.ActiveTab))
        {
            ShowActiveTab();
            UpdateTitle();
            _ = CheckPendingReloadsAsync();
            // The lazy missing notice: owed once per restored-missing tab, on
            // first activation (stock shows it then, never at restore). If the
            // tree is not visual yet the flag stays for the next activation.
            if (tabs.ActiveTab is Tab now && now.FilePath is not null
                && missingNotice.Contains(now.Id) && !File.Exists(now.FilePath))
            {
                _ = ShowMissingNoticeAsync(now);
            }
        }
    }

    private async Task ShowMissingNoticeAsync(Tab tab)
    {
        if (tab.FilePath is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        missingNotice.Remove(tab.Id);
        try
        {
            var dialog = new MissingFileDialog(tab.FilePath) { XamlRoot = xamlRoot };
            await dialog.ShowAsync();
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            // The tree died between the check and the show (window closed
            // under the notice). Once-semantics already consumed; no retry.
            Debug.WriteLine($"Missing notice skipped: {ex.Message}");
        }
    }

    // Rebuilds this window's tabs from a session record (D01 T01 §6), in
    // order with the recorded active tab, contents, and carets. Clean file
    // tabs reload from disk; dirty and untitled tabs take the recorded
    // buffer; missing files resurrect as empty tabs owed the lazy notice.
    private void RestoreSessionWindow(SessionWindow record)
    {
        ArgumentNullException.ThrowIfNull(record);
        if (tabBar is null)
        {
            tabs.NewTab();
            return;
        }

        foreach (SessionTab saved in record.Tabs)
        {
            if (saved.Path is not null && saved.Content is null)
            {
                RestoreCleanFileTab(saved);
            }
            else
            {
                RestoreBufferTab(saved);
            }
        }

        if (tabs.Tabs.Count == 0)
        {
            tabs.NewTab();
        }
        else
        {
            tabs.ActiveTab = tabs.Tabs[Math.Clamp(record.Active, 0, tabs.Tabs.Count - 1)];
        }
    }

    private void RestoreCleanFileTab(SessionTab saved)
    {
        string path = saved.Path!;
        if (TryDetectFile(path) is not DetectedFile detected)
        {
            // Flag after activating: the build-time activation must not raise
            // the notice; only the final active tab (or a later click) does.
            var ghost = new Tab { FilePath = path, IsPinned = saved.IsPinned };
            tabs.Tabs.Add(ghost);
            tabs.ActiveTab = ghost;
            missingNotice.Add(ghost.Id);
            return;
        }

        Tab tab = tabs.OpenTab(path, detected);
        tab.IsPinned = saved.IsPinned;
        tabBar!.SetBoxText(tab, detected.Text);
        // Explicit: programmatic Text sets on pre-show boxes do not reliably
        // raise TextChanged (observed: restored untitled tabs kept a clean
        // model under filled boxes), so restore notifies directly instead of
        // depending on the event. Duplicate calls are safe (same content).
        tab.NotifyEdited(detected.Text);
        tab.MarkSaved();
        tabBar!.SetSelectionStart(tab, saved.Caret);
    }

    private void RestoreBufferTab(SessionTab saved)
    {
        string content = saved.Content ?? string.Empty;
        Tab tab;
        if (saved.Path is null)
        {
            tab = tabs.NewTab();
            tab.IsPinned = saved.IsPinned;
        }
        else
        {
            tab = new Tab
            {
                FilePath = saved.Path,
                Encoding = saved.Encoding,
                HasBom = saved.HasBom,
                LineEnding = saved.LineEnding,
                IsPinned = saved.IsPinned,
            };
            tabs.Tabs.Add(tab);
            tabs.ActiveTab = tab;
            if (!File.Exists(saved.Path))
            {
                missingNotice.Add(tab.Id);
            }
        }

        TextBox box = tabBar!.SetBoxText(tab, content);
        // Explicit for the same pre-show reason as the clean-file path: the
        // model must match the filled box even if TextChanged never fires.
        tab.NotifyEdited(content);
        box.SelectionStart = Math.Min(Math.Max(0, saved.Caret), box.Text.Length);
    }

    // Sync open for restore: the window appears with its tabs, like stock.
    // NotFound (including Exists-then-deleted races) means missing; other
    // failures degrade to an empty kept tab with no notice, recoverable via
    // reopen once §8/T02 land (recorded default; cost: a failure notice).
    static DetectedFile? TryDetectFile(string path)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > int.MaxValue)
            {
                return null;
            }

            if (IsLockedFile(path))
            {
                // D01 T01 §19: locked files restore as ghosts (no password
                // at startup); the ghost sits quiet since the file exists.
                return null;
            }

            return FileOpen.Detect(File.ReadAllBytes(path));
        }
        catch (Exception ex) when (FileOpen.MapFailure(ex) is not null)
        {
            return null;
        }
        catch (OutOfMemoryException)
        {
            // A giant file must degrade to a ghost tab, never brick launch:
            // the session persists, so a throw here would crash every start.
            return null;
        }
    }

    // The session record for this window's live tabs, read by App on close.
    internal SessionWindow CaptureSessionWindow()
    {
        var snapshots = new List<TabSnapshot>(tabs.Tabs.Count);
        foreach (Tab tab in tabs.Tabs)
        {
            string? content = null;
            int caret = 0;
            if (tabBar is not null)
            {
                TextBox box = tabBar.ContentFor(tab);
                content = box.Text;
                caret = box.SelectionStart;
            }

            snapshots.Add(new TabSnapshot(
                tab.FilePath, content, caret, tab.IsDirty, tab.Encoding, tab.HasBom, tab.LineEnding, tab.IsPinned, tab.IsLocked));
        }

        int active = tabs.ActiveTab is null ? 0 : tabs.Tabs.IndexOf(tabs.ActiveTab);
        return SessionCapture.CaptureWindow(snapshots, active, File.Exists);
    }

    private void Tabs_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems is not null)
        {
            foreach (Tab tab in e.OldItems)
            {
                tab.PropertyChanged -= ActiveTab_PropertyChanged;
                missingNotice.Remove(tab.Id);
                // Recents record tab closes only (probed s2m1). Window teardown
                // removes no tabs, so closes-with-the-window stay unrecorded,
                // like stock. Merged onto fresh settings like geometry: every
                // window tab-closes against the same file.
                if (tab.FilePath is not null)
                {
                    SettingsStore.Shared.Update(fresh => RecentFiles.NoteClosed(fresh.RecentFiles, tab.FilePath));
                    App.RefreshJumpList();
                    MenuRegion.RefreshRecents();
                }
            }
        }

        if (e.NewItems is not null)
        {
            foreach (Tab tab in e.NewItems)
            {
                tab.PropertyChanged += ActiveTab_PropertyChanged;
            }
        }

        RefreshStatusBar();
    }

    private void ActiveTab_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is Tab tab && ReferenceEquals(tab, tabs.ActiveTab)
            && e.PropertyName is nameof(Tab.DisplayName) or nameof(Tab.IsDirty))
        {
            UpdateTitle();
        }

        // D01 T02 §4: encoding, line endings, and renames (mode follows
        // the path suffix) all re-render the strip.
        if (sender is Tab changed && ReferenceEquals(changed, tabs.ActiveTab)
            && e.PropertyName is nameof(Tab.DisplayName) or nameof(Tab.Encoding) or nameof(Tab.LineEnding))
        {
            RefreshStatusBar();
        }
    }

    private void ShowActiveTab()
    {
        EditorRegion.Content = tabs.ActiveTab is Tab active && tabBar is not null
            ? tabBar.ContentFor(active)
            : null;
        HookActiveBox();
        RefreshStatusBar();
    }

    // D01 T02 §4: follows the active box's caret. Unhooks the old box
    // first so a closed tab never updates the strip behind the new one.
    private void HookActiveBox()
    {
        if (hookedBox is not null)
        {
            hookedBox.SelectionChanged -= ActiveBox_SelectionChanged;
            hookedBox = null;
        }

        if (tabs.ActiveTab is Tab active && tabBar is not null)
        {
            hookedBox = tabBar.ContentFor(active);
            hookedBox.SelectionChanged += ActiveBox_SelectionChanged;
        }
    }

    private void ActiveBox_SelectionChanged(object sender, RoutedEventArgs e) => RefreshStatusBar();

    // D01 T02 §4: re-renders the strip from the active tab. Null tab
    // shows the empty defaults (stock has no zero-tab state to match).
    private void RefreshStatusBar()
    {
        if (statusBar is null)
        {
            return;
        }

        if (tabs.ActiveTab is not Tab active || tabBar is null)
        {
            statusBar.Show(StatusView.Empty(SettingsStore.Shared.Current.ZoomDefault));
            return;
        }

        TextBox box = tabBar.ContentFor(active);
        statusBar.Show(StatusView.Compute(
            box.Text,
            box.SelectionStart,
            box.SelectionStart,
            box.SelectionLength,
            active.Encoding,
            active.LineEnding,
            SettingsStore.Shared.Current.ZoomDefault,
            StatusSegments.IsMarkdownFile(active.FilePath)));
    }

    // D01 T02 §4: the toggle collapses the strip and its 32-DIP row
    // together, so the editor grows like stock (a bare Visibility flip
    // would leave a gap).
    private void ApplyStatusVisibility()
    {
        bool visible = SettingsStore.Shared.Current.ShowStatusBar;
        StatusRegion.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        StatusRow.Height = new GridLength(visible ? 32 : 0);
    }

    public void SetStatusBarVisible(bool visible)
    {
        SettingsStore.Shared.Update(fresh => fresh.ShowStatusBar = visible);
    }

    // D01 T01 §14: the stats panel over the active tab's buffer (empty
    // when no tab is active, so the trigger stays always-enabled). Each
    // open constructs a fresh controller: compute lands on open and never
    // while typing, and Refresh re-reads on demand.
    internal async Task ShowStatsPanelAsync()
    {
        // Review round 1: never stack two dialogs (a second ShowAsync
        // throws); the modal usually swallows the repeat press, so the
        // flag is belt-and-braces and the single-dialog drive below is
        // the observable contract.
        if (statsDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        statsDialogOpen = true;
        try
        {
            var dialog = new StatsDialog(new ActiveTabTextProvider(ActiveTabText)) { XamlRoot = xamlRoot };
            await dialog.ShowAsync();
        }
        finally
        {
            statsDialogOpen = false;
        }
    }

    string ActiveTabText()
    {
        if (tabs.ActiveTab is not Tab active || tabBar is null)
        {
            return string.Empty;
        }

        return tabBar.ContentFor(active).Text ?? string.Empty;
    }

    // D01 T01 §16: named local versions over the active tab. The dialog
    // takes through SnapshotStore and restores through FileOpen detection;
    // MainWindow only injects the buffer, the dirty flag, the save path
    // (§5 engine plus ApplySave, mirroring the §7 save branch), and the §7
    // prompt name.
    internal async Task ShowSnapshotsPanelAsync()
    {
        if (snapshotsDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        snapshotsDialogOpen = true;
        try
        {
            Tab? active = tabs.ActiveTab;
            SaveSpec spec = active is null
                ? new SaveSpec("UTF-8", false, "CRLF")
                : new SaveSpec(active.Encoding, active.HasBom, active.LineEnding);
            var dialog = new SnapshotsDialog(
                active?.FilePath,
                active?.IsLocked == true,
                ActiveTabText,
                () => active?.IsDirty == true,
                spec,
                text => SaveSnapshotBuffer(active, text),
                restored =>
                {
                    if (active is not null && tabBar is not null)
                    {
                        tabBar.SetBoxText(active, restored);
                    }
                },
                () => active is null ? "Untitled.txt" : TabBar.PromptName(active),
                () => ShowSnapshotsPanelAsync())
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            snapshotsDialogOpen = false;
        }
    }

    // D01 T01 §17: new-from-template picker over the §2 tab flow. The dialog
    // expands the chosen template; MainWindow only opens the new tab with
    // the expanded body (mirroring the restore fill path) and roots the
    // custom store at the settings seam.
    internal async Task ShowTemplatesPanelAsync()
    {
        if (templatesDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        templatesDialogOpen = true;
        try
        {
            string directory = Path.Combine(Notepad.Core.AppDataDir.Root, "templates");
            var dialog = new TemplatesDialog(new TemplateStore(directory), ActiveTabText, UseTemplate)
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            templatesDialogOpen = false;
        }
    }

    void UseTemplate(string expanded)
    {
        if (tabBar is null)
        {
            return;
        }

        Tab tab = tabs.NewTab();
        tabBar.SetBoxText(tab, expanded);
        // Explicit like the restore fill path: pre-show boxes do not
        // reliably raise TextChanged, so the model is notified directly.
        // Blank bodies stay clean (untitled tabs are dirty exactly when
        // they hold content); every other template opens dirty.
        tab.NotifyEdited(expanded);
    }

    // D01 T01 §18: export across formats beside the source file. The dialog
    // converts the live buffer through the shared FormatConverter and
    // writes through the §5 file writer; MainWindow only maps the format
    // to converted text plus destination.
    internal async Task ShowExportPanelAsync()
    {
        if (exportDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        exportDialogOpen = true;
        try
        {
            Tab? active = tabs.ActiveTab;
            var dialog = new ExportDialog(active?.FilePath, (format, baseName) => ExportBuffer(active, format, baseName))
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            exportDialogOpen = false;
        }
    }

    string ExportBuffer(Tab? tab, ExportFormat format, string baseName)
    {
        if (tab?.FilePath is null)
        {
            throw new ArgumentException("Save the file before exporting.", nameof(tab));
        }

        if (string.IsNullOrWhiteSpace(baseName))
        {
            throw new ArgumentException("Export name must not be empty.", nameof(baseName));
        }

        string text = ActiveTabText();
        string converted = format switch
        {
            ExportFormat.Markdown => FormatConverter.ToMarkdown(text),
            ExportFormat.Html => FormatConverter.ToHtmlDocument(baseName, text),
            ExportFormat.PlainText => FormatConverter.ToPlainText(text),
            _ => throw new ArgumentOutOfRangeException(nameof(format)),
        };
        string fileName = baseName + FormatConverter.ExtensionFor(format);
        string destination = Path.Combine(Path.GetDirectoryName(tab.FilePath)!, fileName);
        var spec = new SaveSpec("UTF-8", false, "CRLF");
        return FileSave.SaveFile(destination, converted, spec) switch
        {
            SaveSuccess => fileName,
            SaveRedirect redirect => throw new IOException($"Export redirected: {redirect.Detail}"),
            SaveFailed failed => throw new IOException($"Export failed: {failed.Detail}"),
            _ => throw new IOException("Export failed."),
        };
    }

    // D01 T01 §19: lock the active tab's file with a password. The dialog
    // collects the password; NoteCrypto.Relock (the single-homed re-lock)
    // encodes, locks, and commits, marking the tab locked and clean.
    internal async Task ShowLockPanelAsync()
    {
        if (lockDialogOpen || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        lockDialogOpen = true;
        try
        {
            Tab? active = tabs.ActiveTab;
            var dialog = new LockDialog(active?.FilePath, password => LockActiveTab(active, password))
            {
                XamlRoot = xamlRoot,
            };
            await dialog.ShowAsync();
        }
        finally
        {
            lockDialogOpen = false;
        }
    }

    void LockActiveTab(Tab? tab, string password)
    {
        if (tab?.FilePath is null)
        {
            throw new ArgumentException("Save the file before locking.", nameof(tab));
        }

        NoteCrypto.RelockOrThrow(tab, ActiveTabText(), password);
    }

    static SaveResult SaveSnapshotBuffer(Tab? tab, string text)
    {
        if (tab?.FilePath is null)
        {
            return new SaveFailed("No file path.");
        }

        if (tab.IsLocked)
        {
            // D01 T01 §19: the restore-save branch cannot prompt for a
            // password (sync seam), so it fails safe: the restore aborts
            // with buffer and disk untouched, per the §16 failure rule.
            return new SaveFailed("File is locked.");
        }

        var spec = new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding);
        SaveResult result = FileSave.SaveFile(tab.FilePath, text, spec);
        if (result is SaveSuccess)
        {
            tab.ApplySave(tab.FilePath, spec);
        }

        return result;
    }

    // The hook reports physical client pixels; the strip hit-tests DIP.
    private bool OnMiddleDown(Point physical)
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return false;
        }

        double scale = xamlRoot.RasterizationScale;
        return tabBar.TryCloseTabAt(new Point(physical.X / scale, physical.Y / scale));
    }

    private void UpdateTitle()
    {
        Title = tabs.ActiveTab?.WindowTitle(AppName) ?? WindowTitle.Format("Untitled", false, AppName);
    }

    // Explicit drag rectangles instead of SetTitleBar: the whole-strip drag
    // region swallowed right-clicks into the system menu, so the tab context
    // menu never opened. Only the empty strip right of the tabs (and left of
    // the caption buttons) drags; tabs and the add button stay fully
    // interactive. Insets and drag rects are physical pixels; XAML measures
    // DIP, converted by the rasterization scale.
    private RectInt32 lastDragRect;

    private bool hasDragRect;

    private double lastTopGap;

    // D01 T02 §14: native frame per display scale, re-selected when the
    // window moves across monitors so a 200% display never upscales
    // the 16px source.
    private void SelectTitleIconAsset()
    {
        if (closed || titleIconRef is null)
        {
            return;
        }

        double scale = titleIconRef.XamlRoot?.RasterizationScale ?? 1;
        string asset = scale >= 1.5 ? "titlebar-icon-32.png" : "titlebar-icon-16.png";
        if (asset == titleIconAsset)
        {
            return;
        }

        titleIconAsset = asset;
        titleIconRef.Source = new BitmapImage(new Uri($"ms-appx:///{asset}"));
    }

    private void UpdateDragRects()
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        double scale = xamlRoot.RasterizationScale;
        double leftDip = AppWindow.TitleBar.LeftInset / scale;
        double captionDip = AppWindow.TitleBar.RightInset / scale;
        tabBar.SetCaptionInset(captionDip);
        // D01 T02 §14: TabStripContentRight is TabBar-local, but the drag
        // rectangles are window-space. Before the title icon the TabBar
        // filled TabRegion so both agreed; now the icon column offsets the
        // TabBar origin, and using local x would start the drag rect inside
        // the tab content (over the add button, swallowing its clicks into
        // caption drag). Map through TabRegion instead.
        double tabBarLeft;
        try
        {
            tabBarLeft = tabBar.TransformToVisual(TabRegion).TransformPoint(new Point(0, 0)).X;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return;
        }

        double contentRight = Math.Max(leftDip, tabBarLeft + tabBar.TabStripContentRight());
        double stripWidth = TabRegion.ActualWidth;
        double stripHeight = TabRegion.ActualHeight;
        var rect = new RectInt32(
            (int)Math.Round(contentRight * scale),
            0,
            (int)Math.Round(Math.Max(0, stripWidth - captionDip - contentRight) * scale),
            (int)Math.Round(stripHeight * scale));
        double topGap = tabBar.TabStripContentTop();
        RectInt32[] rects = [rect];
        if (topGap > 0.5 && contentRight > leftDip + 0.5)
        {
            rects = [rect, new RectInt32(
                (int)Math.Round(leftDip * scale),
                0,
                (int)Math.Round((contentRight - leftDip) * scale),
                (int)Math.Round(topGap * scale))];
        }

        if (!hasDragRect || !rect.Equals(lastDragRect) || Math.Abs(topGap - lastTopGap) > 0.5)
        {
            hasDragRect = true;
            lastDragRect = rect;
            lastTopGap = topGap;
            AppWindow.TitleBar.SetDragRectangles(rects);
        }
    }

    public void Dispose()
    {
        SettingsStore.Shared.Changed -= OnSettingsChanged;
        if (hookedBox is not null)
        {
            hookedBox.SelectionChanged -= ActiveBox_SelectionChanged;
            hookedBox = null;
        }

        middleClick?.Dispose();
    }

    private void OnFirstActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnFirstActivated;
        InstallMiddleClickHook();
    }

    // Loaded fires even when activation never does (CI launches never take
    // the foreground), so it backstops the install; whichever fires first wins.
    // A host can refuse the hook outright (Conclave-PC policy fails
    // SetWindowsHookEx): middle-click-to-close degrades away instead of
    // taking the app down, and the UI suite skips that test there.
    private void InstallMiddleClickHook()
    {
        if (middleClick is not null)
        {
            return;
        }

        try
        {
            middleClick = new MiddleClickHook(WindowNative.GetWindowHandle(this), OnMiddleDown, DispatcherQueue);
        }
        catch (InvalidOperationException ex)
        {
            Debug.WriteLine($"Middle-click hook unavailable: {ex.Message}");
        }
    }

    // Every layout pass refreshes the hook's cached tab bounds, so its
    // callback hit-tests from data and never reenters XAML mid-input.
    private void UpdateMiddleClickStrip()
    {
        if (tabBar is null || Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        middleClick?.UpdateTabs(tabBar.TabHitRects(), xamlRoot.RasterizationScale);
    }

    private void RestoreGeometry()
    {
        ShellSettings live = SettingsStore.Shared.Current;
        int width = Math.Max(100, live.Width);
        int height = Math.Max(100, live.Height);
        (int x, int y) = BirthOrigin(live, width, height);
        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    void OnSettingsChanged(object? sender, EventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            ApplyTheme();

            // D01 T02 §4: the toggle and the zoom default live in the
            // store, so every settings change re-applies the strip and
            // re-syncs the menu check (another window may have flipped it).
            MenuRegion.SetStatusBarChecked(SettingsStore.Shared.Current.ShowStatusBar);
            ApplyStatusVisibility();
            RefreshStatusBar();
        });
    }

    void ApplyTheme()
    {
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = SettingsStore.Shared.Current.Theme switch
            {
                "light" => ElementTheme.Light,
                "dark" => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
        }
    }

    // D01 T02 §3: settings overlay plus the Edit > Font jump target.
    void SettingsButton_Click(object sender, RoutedEventArgs e) => ShowSettings();

    void SettingsBackButton_Click(object sender, RoutedEventArgs e) => HideSettings();

    void ShowSettings()
    {
        SettingsRegion.Visibility = Visibility.Visible;
    }

    void HideSettings()
    {
        SettingsRegion.Visibility = Visibility.Collapsed;
    }

    internal void ShowFontSettings()
    {
        ShowSettings();
        SettingsView.JumpToFont();
    }

    private void OnFirstLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement root)
        {
            root.Loaded -= OnFirstLoaded;
        }

        // D01 T01 §11: window chrome icon. Loaded, not the constructor: the
        // HWND is invalid there, and not first-activation: background launches
        // never activate. The exe icon (ApplicationIcon) covers the taskbar.
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "notepad.ico"));
        InstallMiddleClickHook();
        if (SettingsStore.Shared.Current.WhatsNewSeen || !firstWindow)
        {
            return;
        }

        DispatcherQueue.TryEnqueue(async () =>
        {
            // The notice runs first and resumes on the UI thread
            // (ConfigureAwait(true)): the dialogs need the UI thread, while
            // the trailing Update is a file write that runs anywhere.
            await ShowCorruptSettingsNoticeAsync().ConfigureAwait(true);
            await ShowWhatsNewAsync().ConfigureAwait(false);
            SettingsStore.Shared.Update(fresh => fresh.WhatsNewSeen = true);
        });
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        closed = true;
        StopReloadWatching();

        // No close prompt here, by probe, not by omission (D01 T01 §7):
        // stock closes windows with dirty tabs silently for one tab and
        // for many (both probed with zero dialogs), preserving everything
        // for session restore. The prompt matrix is tab-close only. The
        // session snapshot runs first: App sees the closing window plus
        // its survivors and applies the survivors-or-self rule.
        if (Application.Current is App app)
        {
            app.SnapshotSession(this);
        }

        // Geometry writes through the shared store: every window mutates
        // the same live object, so a sibling's newer flag (notably
        // WhatsNewSeen) can no longer be clobbered by a stale snapshot.
        // Last-closed still wins the geometry.
        Dispose();
        PointInt32 position = AppWindow.Position;
        SizeInt32 size = AppWindow.Size;
        SettingsStore.Shared.Update(fresh =>
        {
            fresh.X = position.X;
            fresh.Y = position.Y;
            fresh.Width = size.Width;
            fresh.Height = size.Height;
        });
    }

    private async void WhatsNewButton_Click(object sender, RoutedEventArgs e)
    {
        await ShowWhatsNewAsync().ConfigureAwait(false);
    }

    private async Task ShowWhatsNewAsync()
    {
        if (Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        var dialog = new WhatsNewDialog { XamlRoot = xamlRoot };
        await dialog.ShowAsync();
    }

    // D01 T02 §2: the store reset to defaults on a corrupt file, so the
    // first window says so once at startup. Runs inside the first-window
    // gate above, before the whatsnew dialog so the reset is explained
    // before anything else; must run on the UI thread (see call site).
    private async Task ShowCorruptSettingsNoticeAsync()
    {
        if (!SettingsStore.Shared.WasResetFromCorrupt)
        {
            return;
        }

        if (Content?.XamlRoot is not XamlRoot xamlRoot)
        {
            return;
        }

        var dialog = new CorruptSettingsDialog { XamlRoot = xamlRoot };
        await dialog.ShowAsync();
    }
}
