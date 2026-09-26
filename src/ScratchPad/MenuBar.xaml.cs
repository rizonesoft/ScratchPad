using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace ScratchPad;

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
    void ShowPageSetup();
    Task PrintAsync();
    void CloseTab();
    void CloseWindow();
    void Exit();
    Task OpenRecentAsync(string path);
    IReadOnlyList<string> RecentFiles();
    void ClearRecents();
    void SearchBing();
    void DefineBing();
    void ShowFontSettings();
    void SetStatusBarVisible(bool visible);
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

    // D01 T02 §4: syncs the View toggle's check to the store (startup
    // and any external settings change); user clicks flow back through
    // OnViewStatusBar.
    public void SetStatusBarChecked(bool visible)
    {
        MenuViewStatusBar.IsChecked = visible;
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

    // The binding mutation seam (D00 T02 §36 items 1 and 4): under a test
    // run that targets this item, its handler runs a different host member
    // instead (a new tab; a new window when the item is New tab itself), so
    // the covering chord test must fail; in observe mode every bound
    // handler runs nothing and logs its dispatch for the routing oracle.
    // Every bound handler checks it first (the binding manifest refuses one
    // that does not). A failed dispatch-log write ends the test-only process
    // (TestMutation.RecordOrFail), which the routing test detects.
    bool Mutated(string id)
    {
        // An auto-repeat of a one-shot command runs nothing (D00 T02 §43
        // item 4); the guard every bound handler already calls carries it.
        if (HeldChord.ShouldSkip(id))
        {
            return true;
        }

        switch (TestMutation.For(id, Environment.GetEnvironmentVariable))
        {
            case MutationEffect.Swap:
                TestMutation.RecordSwap(id, Environment.GetEnvironmentVariable);
                if (id == "MenuFileNewTab")
                {
                    host?.NewWindow();
                }
                else
                {
                    host?.NewTab();
                }

                // The substitute returned (D00 T02 §51 item 1).
                TestMutation.RecordSwapDone(id, Environment.GetEnvironmentVariable);
                return true;
            case MutationEffect.Observe:
                TestMutation.RecordOrFail(id, Environment.GetEnvironmentVariable);
                return true;
            default:
                return false;
        }
    }

    void Register(MenuFlyoutItemBase item)
    {
        string id = AutomationProperties.GetAutomationId(item);
        commands[id] = item;
        // Arming evidence for the mutation run (D00 T02 §51 item 11).
        TestMutation.RecordArmed(id, Environment.GetEnvironmentVariable);
    }

    void OnFileNewTab(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileNewTab"))
        {
            return;
        }

        host?.NewTab();
    }

    void OnFileNewWindow(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileNewWindow"))
        {
            return;
        }

        host?.NewWindow();
    }

    void OnFileOpen(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileOpen"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.OpenAsync();
        }
    }

    void OnFileSave(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileSave"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.SaveAsync();
        }
    }

    void OnFileSaveAs(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileSaveAs"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.SaveAsAsync();
        }
    }

    void OnFileSaveAll(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileSaveAll"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.SaveAllAsync();
        }
    }

    void OnFilePageSetup(object sender, RoutedEventArgs e) => host?.ShowPageSetup();

    void OnFilePrint(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFilePrint"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.PrintAsync();
        }
    }

    void OnFileCloseTab(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileCloseTab"))
        {
            return;
        }

        host?.CloseTab();
    }

    void OnFileCloseWindow(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuFileCloseWindow"))
        {
            return;
        }

        host?.CloseWindow();
    }

    void OnFileExit(object sender, RoutedEventArgs e) => host?.Exit();

    void OnEditSearchBing(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuEditSearchBing"))
        {
            return;
        }

        host?.SearchBing();
    }

    void OnEditFont(object sender, RoutedEventArgs e) => host?.ShowFontSettings();

    void OnEditDefineBing(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuEditDefineBing"))
        {
            return;
        }

        host?.DefineBing();
    }

    // D01 T02 §4: ToggleMenuFlyoutItem flips IsChecked before Click
    // fires, so the handler reads the new state straight off the item.
    void OnViewStatusBar(object sender, RoutedEventArgs e) => host?.SetStatusBarVisible(MenuViewStatusBar.IsChecked);

    void OnToolsStats(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuToolsStats"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.ShowStatsAsync();
        }
    }

    void OnToolsSnapshots(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuToolsSnapshots"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.ShowSnapshotsAsync();
        }
    }

    void OnToolsTemplates(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuToolsTemplates"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.ShowTemplatesAsync();
        }
    }

    void OnToolsExport(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuToolsExport"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.ShowExportAsync();
        }
    }

    void OnToolsLock(object sender, RoutedEventArgs e)
    {
        if (Mutated("MenuToolsLock"))
        {
            return;
        }

        if (host is not null)
        {
            _ = host.LockFileAsync();
        }
    }
}
