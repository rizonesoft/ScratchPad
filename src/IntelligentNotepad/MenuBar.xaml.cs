using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace IntelligentNotepad;

// Menu command host, owned by D01 T02 §1. MainWindow implements it; the
// menu calls it, never the engines directly. Async commands show dialogs.
internal interface IMenuHost
{
    void NewTab();
    void NewWindow();
    Task OpenAsync();
    Task SaveAsync();
    Task SaveAsAsync();
    Task SaveAllAsync();
    void CloseTab();
    void CloseWindow();
    void Exit();
    Task OpenRecentAsync(string path);
    IReadOnlyList<string> RecentFiles();
    void ClearRecents();
    void SearchBing();
    void DefineBing();
    void ShowFontSettings();
    Task ShowStatsAsync();
    Task ShowSnapshotsAsync();
    Task ShowTemplatesAsync();
    Task ShowExportAsync();
    Task LockFileAsync();
}

// Full Notepad menu bar, owned by D01 T02 §1. Structure lives in
// MenuBar.xaml (stock labels, order, separators, shortcuts); this file
// routes clicks to the host, rebuilds the Recent submenu, and exposes the
// MenuCommands registry pending-owner sections use to flip their items
// live on landing.
internal sealed partial class AppMenuBar : MenuBar
{
    readonly Dictionary<string, MenuFlyoutItemBase> commands = new(StringComparer.Ordinal);

    IMenuHost? host;

    public AppMenuBar()
    {
        InitializeComponent();
        Register(MenuFileNewTab);
        Register(MenuFileNewWindow);
        Register(MenuFileNewMarkdownTab);
        Register(MenuFileOpen);
        Register(MenuFileRecent);
        Register(MenuFileSave);
        Register(MenuFileSaveAs);
        Register(MenuFileSaveAll);
        Register(MenuFilePageSetup);
        Register(MenuFilePrint);
        Register(MenuFileCloseTab);
        Register(MenuFileCloseWindow);
        Register(MenuFileExit);
        Register(MenuEditUndo);
        Register(MenuEditCut);
        Register(MenuEditCopy);
        Register(MenuEditPaste);
        Register(MenuEditDelete);
        Register(MenuEditClearFormatting);
        Register(MenuEditSearchBing);
        Register(MenuEditDefineBing);
        Register(MenuEditFind);
        Register(MenuEditFindNext);
        Register(MenuEditFindPrevious);
        Register(MenuEditReplace);
        Register(MenuEditGoTo);
        Register(MenuEditSelectAll);
        Register(MenuEditTimeDate);
        Register(MenuEditFont);
        Register(MenuViewZoomIn);
        Register(MenuViewZoomOut);
        Register(MenuViewZoomRestore);
        Register(MenuViewStatusBar);
        Register(MenuViewWordWrap);
        Register(MenuViewMarkdownFormatted);
        Register(MenuViewMarkdownSyntax);
        Register(MenuToolsStats);
        Register(MenuToolsSnapshots);
        Register(MenuToolsTemplates);
        Register(MenuToolsExport);
        Register(MenuToolsLock);
    }

    public void Bind(IMenuHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
        RefreshRecents();
    }

    // Pending-owner enablement, owned by D01 T02 §1 item 2. Unknown ids
    // throw: a typo must fail loud at the owner's first drive, not ship
    // a silently dead item.
    public void SetEnabled(string automationId, bool enabled)
    {
        ArgumentNullException.ThrowIfNull(automationId);
        if (!commands.TryGetValue(automationId, out MenuFlyoutItemBase? item))
        {
            throw new ArgumentOutOfRangeException(nameof(automationId), automationId, "Unknown menu command.");
        }

        item.IsEnabled = enabled;
    }

    public void RefreshRecents()
    {
        if (host is null)
        {
            return;
        }

        MenuFileRecent.Items.Clear();
        IReadOnlyList<string> recents = host.RecentFiles();
        if (recents.Count == 0)
        {
            // Stock's empty state reads "No recent files" plus Clear list
            // (dumped 2026-09-16); the placeholder click no-ops.
            var none = new MenuFlyoutItem { Text = "No recent files" };
            AutomationProperties.SetAutomationId(none, "MenuFileRecentEmpty");
            MenuFileRecent.Items.Add(none);
        }
        else
        {
            foreach (string path in recents)
            {
                string captured = path;
                var entry = new MenuFlyoutItem { Text = Path.GetFileName(captured) };
                AutomationProperties.SetAutomationId(entry, "MenuFileRecentEntry");
                entry.Click += (_, _) => _ = host.OpenRecentAsync(captured);
                MenuFileRecent.Items.Add(entry);
            }

            MenuFileRecent.Items.Add(new MenuFlyoutSeparator());
        }

        var clear = new MenuFlyoutItem { Text = "Clear list" };
        AutomationProperties.SetAutomationId(clear, "MenuFileRecentClear");
        clear.Click += (_, _) =>
        {
            host.ClearRecents();
            RefreshRecents();
        };
        MenuFileRecent.Items.Add(clear);
    }

    void Register(MenuFlyoutItemBase item)
    {
        string id = AutomationProperties.GetAutomationId(item);
        commands[id] = item;
    }

    void OnFileNewTab(object sender, RoutedEventArgs e) => host?.NewTab();

    void OnFileNewWindow(object sender, RoutedEventArgs e) => host?.NewWindow();

    void OnFileOpen(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.OpenAsync();
        }
    }

    void OnFileSave(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.SaveAsync();
        }
    }

    void OnFileSaveAs(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.SaveAsAsync();
        }
    }

    void OnFileSaveAll(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.SaveAllAsync();
        }
    }

    void OnFileCloseTab(object sender, RoutedEventArgs e) => host?.CloseTab();

    void OnFileCloseWindow(object sender, RoutedEventArgs e) => host?.CloseWindow();

    void OnFileExit(object sender, RoutedEventArgs e) => host?.Exit();

    void OnEditSearchBing(object sender, RoutedEventArgs e) => host?.SearchBing();

    void OnEditFont(object sender, RoutedEventArgs e) => host?.ShowFontSettings();

    void OnEditDefineBing(object sender, RoutedEventArgs e) => host?.DefineBing();

    void OnToolsStats(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.ShowStatsAsync();
        }
    }

    void OnToolsSnapshots(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.ShowSnapshotsAsync();
        }
    }

    void OnToolsTemplates(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.ShowTemplatesAsync();
        }
    }

    void OnToolsExport(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.ShowExportAsync();
        }
    }

    void OnToolsLock(object sender, RoutedEventArgs e)
    {
        if (host is not null)
        {
            _ = host.LockFileAsync();
        }
    }
}
