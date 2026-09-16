using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Notepad.Core;

namespace IntelligentNotepad;

// Command-line launch, single-instance redirect, and headless verbs, owned
// by D01 T01 §8. Stock 11.2607.14.0 is single-instance with activation
// routing (probed 2026-09-15: second launches join the live process):
// bare launches open a new window, file launches open tabs in the live
// window (deduped), all per the OpenIn mode. Verbs (/register, /unregister)
// and print flags run in the launching process and exit without windows.
// The redirect signal carries no payload unpackaged (probed: files never
// arrive), so secondaries file absolute paths (rooted against their own
// cwd) as launch drops and the primary drains them on Activated.
[System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1515", Justification = "Partial of the public WinUI application type; accessibility is fixed by the XAML code-behind half.")]
partial class App
{
    const string SingleInstanceKey = "IntelligentNotepad-main";

    // Headless entry: association verbs answer through the registrar seam
    // D07's installer shares; print requests hit the T02 §5 seam (silent
    // interim default, declared in §8 box 7) and exit print-then-close
    // shaped. Returns the process exit code.
    internal static int RunHeadless(LaunchRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.RegisterAssociations)
        {
            return RunVerb(() => FileAssociationRegistrar.Register(ExePath()));
        }

        if (request.UnregisterAssociations)
        {
            return RunVerb(() => FileAssociationRegistrar.Unregister(Path.GetFileName(ExePath())));
        }

        if (request.RegisterProtocol)
        {
            return RunVerb(() => FileAssociationRegistrar.RegisterProtocol(ExePath()));
        }

        if (request.UnregisterProtocol)
        {
            return RunVerb(() => FileAssociationRegistrar.UnregisterProtocol());
        }

        if (request.IsPrint)
        {
            PrintSeam.Print(request.PrintFile!, request.PrintPrinter);
            return 0;
        }

        return 0;
    }

    static int RunVerb(Action verb)
    {
        try
        {
            verb();
            return 0;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or COMException)
        {
            Debug.WriteLine($"Association verb failed: {ex.Message}");
            return 1;
        }
    }

    static string ExePath() => Environment.ProcessPath ?? throw new InvalidOperationException("No process path.");

    static async Task RedirectAndExitAsync(AppInstance main, IReadOnlyList<string> files, bool newNote)
    {
        try
        {
            LaunchDrops.Write(files, newNote: newNote);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Launch drop failed: {ex.Message}");
        }

        try
        {
            AppActivationArguments raw = AppInstance.GetCurrent().GetActivatedEventArgs();
            await main.RedirectActivationToAsync(raw).AsTask().ConfigureAwait(true);
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException)
        {
            Debug.WriteLine($"Activation redirect failed: {ex.Message}");
        }
        finally
        {
            Environment.Exit(0);
        }
    }

    void OnAppRedirected(object? sender, AppActivationArguments args)
    {
        if (args.Kind != ExtendedActivationKind.Launch)
        {
            return;
        }

        IReadOnlyList<LaunchDrop> drops = LaunchDrops.DrainAll();
        List<string> files = drops.SelectMany(drop => drop.Files).ToList();
        bool newNote = drops.Any(drop => drop.NewNote);
        DispatcherQueue? queue = DispatcherQueue.GetForCurrentThread() ?? windows.OfType<MainWindow>().FirstOrDefault()?.DispatcherQueue;
        if (queue is null)
        {
            return;
        }

        queue.TryEnqueue(() =>
        {
            if (files.Count == 0 && !newNote)
            {
                NewWindow();
                return;
            }

            _ = RouteRedirectAsync(files, newNote);
        });
    }

    // D01 T01 §25: redirected files route per the §9 mode, then the
    // new-note flag (if any) lands on the first window, active. The note
    // waits for the files so combined launches end on the note.
    async Task RouteRedirectAsync(List<string> files, bool newNote)
    {
        if (files.Count > 0)
        {
            await OpenFilesRoutedAsync(files).ConfigureAwait(true);
        }

        if (newNote)
        {
            (windows.OfType<MainWindow>().FirstOrDefault() ?? NewWindow()).EnsureFreshNote();
        }
    }

    // Routes redirected files per the §9 OpenIn mode (second launches
    // only; startup files take OpenIntoFirstWindowAsync below): new-tab
    // opens into the first window (single-window tests and the common
    // case; multi-window actives are untracked), new-window opens one
    // window holding only the files (default: stock multi-file mode
    // behavior is inferred from the single-file rule; cost one branch).
    // Routed-into-created consumes the spare: the window was made for
    // these files, so its initial tab goes once they land (stock opens
    // no spare Untitled beside them); routed-into-existing stays
    // additive and never touches the user's tabs. Never throws:
    // redirect file-open degrades to Debug output, never kills the app.
    async Task OpenFilesRoutedAsync(IReadOnlyList<string> files)
    {
        try
        {
            OpenTarget target = OpenInRouting.Route(ShellSettings.Load().OpenIn);
            MainWindow window;
            Tab? spare = null;
            if (target == OpenTarget.NewWindow)
            {
                window = NewWindow();
                spare = window.CaptureSpareCandidate();
            }
            else
            {
                window = windows.OfType<MainWindow>().FirstOrDefault() ?? NewWindow();
            }

            await window.OpenFilesAsync(files, offerCreate: true).ConfigureAwait(true);
            if (spare is not null)
            {
                await window.DropSpareUntitledAsync(spare).ConfigureAwait(true);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            Debug.WriteLine($"Routed open failed: {ex.Message}");
        }
    }

    // Startup files (fresh process, own command line) always open into
    // the launching window in both modes: the §9 mode decides tab vs
    // window relative to live windows, and a fresh process has none yet
    // (stock never opens a spare empty window beside requested files;
    // default, cost one branch). Never throws: startup file-open
    // degrades to Debug output rather than killing the app.
    async Task OpenIntoFirstWindowAsync(IReadOnlyList<string> files, bool newNote)
    {
        try
        {
            MainWindow window = windows.OfType<MainWindow>().FirstOrDefault() ?? NewWindow();
            await window.OpenFilesAsync(files, offerCreate: true).ConfigureAwait(true);
            if (newNote)
            {
                window.EnsureFreshNote();
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            Debug.WriteLine($"Startup open failed: {ex.Message}");
        }
    }

    internal static void RefreshJumpList()
    {
        string? exe = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(exe))
        {
            JumpListService.RefreshIfChanged(ShellSettings.Load(), exe);
        }
    }

}
