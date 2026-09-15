using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Notepad.Core;

namespace IntelligentNotepad;

public partial class App : Application
{
    private readonly List<Window> windows = new();

    // Crash-checkpoint debounce (D01 T01 §7): every content-box edit
    // restarts this one-shot; the tick checkpoints all live windows.
    private DispatcherQueueTimer? checkpointTimer;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // D01 T01 §6: continue mode reopens the recorded window set; fresh
        // mode, an empty session, or a corrupt one opens one clean window.
        ShellSettings settings = ShellSettings.Load();
        SessionData session = SessionData.Load();
        if (WhenStartsRouting.Route(settings.WhenStarts) == StartupMode.ContinueSession
            && session.Windows.Count > 0
            && !session.IsTrivial)
        {
            foreach (SessionWindow record in session.Windows)
            {
                AddWindow(record);
            }

            windows[Math.Clamp(session.ActiveWindow, 0, windows.Count - 1)].Activate();
        }
        else
        {
            NewWindow();
        }
    }

    // Window-opening mechanism, owned by D01 T01 §9. The first window of the
    // process restores geometry and may show first-run; later windows open
    // at the OS default cascade like stock's (probed offsets +261/-38,
    // +38/-38, +38/0: small, varying, same size). Invoked by Ctrl+Shift+N and,
    // at their time, the D01 T02 §1 File menu and §8 command line.
    public void NewWindow()
    {
        AddWindow(null);
    }

    private void AddWindow(SessionWindow? restore)
    {
        var window = new MainWindow(firstWindow: windows.Count == 0, restore: restore);
        windows.Add(window);
        window.Closed += (_, _) => windows.Remove(window);
        window.Activate();
    }

    // Session snapshot on window close (D01 T01 §6), called from
    // MainWindow.OnClosed while the closing window is still tracked.
    // Survivors-or-self: a non-last close records the surviving windows and
    // drops the closing one's tabs (probed s2merge: no merge, no resurrect);
    // the last close records the closing window, prompts never (probed
    // s2l1: quit snapshots everything silently). Fresh mode deletes the
    // session instead. Crash-continuous checkpointing arrives with §7.
    internal void SnapshotSession(MainWindow closing)
    {
        ArgumentNullException.ThrowIfNull(closing);
        if (WhenStartsRouting.Route(ShellSettings.Load().WhenStarts) == StartupMode.FreshWindow)
        {
            SessionData.Delete();
            return;
        }

        List<MainWindow> survivors = windows.OfType<MainWindow>()
            .Where(w => !ReferenceEquals(w, closing)).ToList();
        var data = new SessionData();
        if (survivors.Count > 0)
        {
            foreach (MainWindow survivor in survivors)
            {
                SessionWindow record = survivor.CaptureSessionWindow();
                if (record.Tabs.Count > 0)
                {
                    data.Windows.Add(record);
                }
            }

            data.ActiveWindow = data.Windows.Count == 0
                ? 0
                : Math.Clamp(SessionData.Load().ActiveWindow, 0, data.Windows.Count - 1);
        }
        else
        {
            SessionWindow record = closing.CaptureSessionWindow();
            if (record.Tabs.Count > 0)
            {
                data.Windows.Add(record);
            }

            data.ActiveWindow = 0;
        }

        if (data.IsTrivial)
        {
            SessionData.Delete();
            return;
        }

        data.Save();
    }

    // Called on every content-box edit (via MainWindow): restarts the
    // checkpoint one-shot. UI thread only, like all window traffic.
    internal void NotifyTabsEdited()
    {
        DispatcherQueue? queue = DispatcherQueue.GetForCurrentThread();
        if (queue is null)
        {
            return;
        }

        checkpointTimer ??= queue.CreateTimer();
        checkpointTimer.Interval = CrashCheckpoint.Debounce;
        checkpointTimer.IsRepeating = false;
        checkpointTimer.Tick -= CheckpointTick;
        checkpointTimer.Tick += CheckpointTick;
        checkpointTimer.Stop();
        checkpointTimer.Start();
    }

    private void CheckpointTick(DispatcherQueueTimer timer, object args)
    {
        CheckpointAll();
    }

    // Continuous crash checkpoint (D01 T01 §7): snapshots every live
    // window into session.json, the same file a quit writes, so a kill
    // relaunches through the §6 path with no offer or marker (stock
    // shows none). Policy follows CrashCheckpoint.Decide; writes are
    // atomic temp-plus-move like quits, so a mid-write kill leaves the
    // previous checkpoint or nothing (both restore clean).
    internal void CheckpointAll()
    {
        StartupMode mode = WhenStartsRouting.Route(ShellSettings.Load().WhenStarts);
        var data = new SessionData();
        foreach (MainWindow window in windows.OfType<MainWindow>())
        {
            SessionWindow record = window.CaptureSessionWindow();
            if (record.Tabs.Count > 0)
            {
                data.Windows.Add(record);
            }
        }

        switch (CrashCheckpoint.Decide(mode, data.IsTrivial, File.Exists(SessionData.FilePath)))
        {
            case CrashCheckpoint.Decision.Write:
                data.ActiveWindow = data.Windows.Count == 0
                    ? 0
                    : Math.Clamp(SessionData.Load().ActiveWindow, 0, data.Windows.Count - 1);
                data.Save();
                break;
            case CrashCheckpoint.Decision.Delete:
                SessionData.Delete();
                break;
            case CrashCheckpoint.Decision.Skip:
            default:
                break;
        }
    }
}
