using Microsoft.UI.Xaml;

namespace IntelligentNotepad;

public partial class App : Application
{
    private readonly List<Window> windows = new();

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        NewWindow();
    }

    // Window-opening mechanism, owned by D01 T01 §9. The first window of the
    // process restores geometry and may show first-run; later windows open
    // at the OS default cascade like stock's (probed offsets +261/-38,
    // +38/-38, +38/0: small, varying, same size). Invoked by Ctrl+Shift+N and,
    // at their time, the D01 T02 §1 File menu and §8 command line.
    public void NewWindow()
    {
        var window = new MainWindow(firstWindow: windows.Count == 0);
        windows.Add(window);
        window.Closed += (_, _) => windows.Remove(window);
        window.Activate();
    }
}
