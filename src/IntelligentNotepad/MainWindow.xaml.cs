using System.Reflection;
using Microsoft.UI.Xaml;

namespace IntelligentNotepad;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        var version = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
        Title = $"Intelligent Notepad (stub {version}, {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription})";
    }
}
