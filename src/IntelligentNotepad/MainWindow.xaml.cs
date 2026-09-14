using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Notepad.Core;
using Windows.Graphics;

namespace IntelligentNotepad;

public sealed partial class MainWindow : Window
{
    private const string AppName = "Intelligent Notepad";

    private readonly ShellSettings settings = ShellSettings.Load();

    public MainWindow()
    {
        InitializeComponent();
        Title = WindowTitle.Format("Untitled", false, AppName);
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TabRegion);
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = settings.Theme switch
            {
                "light" => ElementTheme.Light,
                "dark" => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
            // Loaded, not Activated: first-run must show even when the window
            // opens behind others (CI launches never take the foreground).
            root.Loaded += OnFirstLoaded;
        }
        RestoreGeometry();
        Closed += OnClosed;
    }

    private void RestoreGeometry()
    {
        int width = Math.Max(100, settings.Width);
        int height = Math.Max(100, settings.Height);
        AppWindow.MoveAndResize(new RectInt32(settings.X, settings.Y, width, height));
    }

    private void OnFirstLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement root)
        {
            root.Loaded -= OnFirstLoaded;
        }

        if (settings.WhatsNewSeen)
        {
            return;
        }

        DispatcherQueue.TryEnqueue(async () =>
        {
            await ShowWhatsNewAsync().ConfigureAwait(false);
            settings.WhatsNewSeen = true;
            settings.Save();
        });
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        PointInt32 position = AppWindow.Position;
        SizeInt32 size = AppWindow.Size;
        settings.X = position.X;
        settings.Y = position.Y;
        settings.Width = size.Width;
        settings.Height = size.Height;
        settings.Save();
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
}
