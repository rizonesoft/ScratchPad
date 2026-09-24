using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;
using WinRT.Interop;
using Windows.System;

namespace ScratchPad;

// Menu command host, owned by D01 T02 §1. Implements IMenuHost by routing
// every live item to its engine: file flows through the §4/§5 engines and
// dialogs, recents through the §6 list, Bing through the launcher, Tools
// through the existing Show* panels.
[System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1515", Justification = "Partial of the public WinUI window type; accessibility is fixed by the XAML code-behind half.")]
sealed partial class MainWindow : IMenuHost
{
    void IMenuHost.NewTab() => tabBar?.NewTab();

    void IMenuHost.NewWindow() => OpenNewWindow();

    async Task IMenuHost.OpenAsync()
    {
        FileDialogs.Choice? choice = FileDialogs.ShowOpen(
            WindowNative.GetWindowHandle(this),
            OpenDialogDefaults.EncodingOptions);
        if (choice is null)
        {
            return;
        }

        await OpenPickedAsync(choice.Path, choice.EncodingName, offerCreate: true).ConfigureAwait(true);
    }

    async Task IMenuHost.OpenRecentAsync(string path) => await OpenPickedAsync(path, null, offerCreate: false).ConfigureAwait(true);

    async Task OpenPickedAsync(string path, string? forcedEncoding, bool offerCreate)
    {
        if (Directory.Exists(path))
        {
            return;
        }

        if (!File.Exists(path))
        {
            // Typed names get the §8 create offer; recents reference
            // existing files, so a vanishing recent reports NotFound
            // (default: the stock missing-recent path is unprobed).
            if (offerCreate)
            {
                await OfferCreateAsync(path).ConfigureAwait(true);
            }
            else
            {
                await ShowFailureAsync(OpenFailure.NotFound).ConfigureAwait(true);
            }

            return;
        }

        if (IsLockedFile(path))
        {
            await UnlockAndOpenAsync(path).ConfigureAwait(true);
            return;
        }

        var options = new OpenOptions(OpenOptions.DefaultMaxBytes, LogTimestamp.Format(DateTime.Now))
        {
            ForcedEncoding = forcedEncoding,
        };
        OpenResult result = await FileOpen.OpenFileAsync(path, options).ConfigureAwait(true);
        switch (result)
        {
            case OpenSuccess opened:
                OpenDetected(path, opened);
                break;
            case OpenFailureResult failed:
                await ShowFailureAsync(failed.Failure, failed.Detail).ConfigureAwait(true);
                break;
        }
    }

    async Task IMenuHost.SaveAsync()
    {
        Tab? active = tabs.ActiveTab;
        if (active is null || tabBar is null)
        {
            return;
        }

        if (active.IsLocked)
        {
            await RelockTabAsync(active).ConfigureAwait(true);
            return;
        }

        if (active.FilePath is null)
        {
            await SaveAsForTabAsync(active).ConfigureAwait(true);
            return;
        }

        string text = tabBar.ContentFor(active).Text ?? string.Empty;
        var spec = new SaveSpec(active.Encoding, active.HasBom, active.LineEnding);
        switch (FileSave.SaveFile(active.FilePath, text, spec))
        {
            case SaveSuccess:
                active.ApplySave(active.FilePath, spec);
                break;
            case SaveRedirect:
                await SaveAsForTabAsync(active).ConfigureAwait(true);
                break;
            case SaveFailed failed:
                await ShowSaveFailureAsync(failed.Detail).ConfigureAwait(true);
                break;
        }
    }

    async Task IMenuHost.SaveAsAsync()
    {
        if (tabs.ActiveTab is Tab active)
        {
            await SaveAsForTabAsync(active).ConfigureAwait(true);
        }
    }

    // True when a save landed (false on cancel); doubles as TabBar's
    // close-save outlet for untitled and redirected tabs.
    async Task<bool> SaveAsForTabAsync(Tab tab)
    {
        if (tabBar is null)
        {
            return false;
        }

        string prefill = tab.FilePath is null
            ? SaveDialogDefaults.FileNameFor(tabBar.ContentFor(tab).Text ?? string.Empty)
            : Path.GetFileName(tab.FilePath);
        while (true)
        {
            FileDialogs.Choice? choice = FileDialogs.ShowSave(
                WindowNative.GetWindowHandle(this),
                prefill,
                SaveDialogDefaults.OfferedEncodings,
                tab.Encoding);
            if (choice?.EncodingName is null)
            {
                return false;
            }

            // The chosen name wins: an explicit UTF-8-with-BOM sets the BOM,
            // re-picking the tab encoding keeps its flag, anything else
            // clears it (default: stock's BOM carry rule is unprobed).
            bool hasBom = choice.EncodingName == FileOpen.Utf8BomName
                || (choice.EncodingName == tab.Encoding && tab.HasBom);
            string text = tabBar.ContentFor(tab).Text ?? string.Empty;
            var spec = new SaveSpec(choice.EncodingName, hasBom, tab.LineEnding);
            switch (FileSave.SaveFile(choice.Path, text, spec))
            {
                case SaveSuccess:
                    tab.ApplySave(choice.Path, spec);
                    return true;
                case SaveRedirect:
                    prefill = Path.GetFileName(choice.Path);
                    continue;
                case SaveFailed failed:
                    await ShowSaveFailureAsync(failed.Detail).ConfigureAwait(true);
                    return false;
            }
        }
    }

    async Task IMenuHost.SaveAllAsync()
    {
        if (tabBar is null)
        {
            return;
        }

        // Locked tabs re-lock through the dialog before the engine runs:
        // the neutral walk would otherwise write their plaintext. Cancel
        // skips that tab and continues, mirroring the engine's cancel rule.
        foreach (Tab tab in tabs.Tabs.Where(t => t.IsLocked && t.IsDirty).ToList())
        {
            await RelockTabAsync(tab).ConfigureAwait(true);
        }

        // Failures record and continue (the §5 default); tabs stay dirty,
        // which is the visible record, so no summary dialog appears.
        FileSave.SaveAll(
            tabs,
            tab => tabBar.ContentFor(tab).Text ?? string.Empty,
            tab =>
            {
                FileDialogs.Choice? choice = FileDialogs.ShowSave(
                    WindowNative.GetWindowHandle(this),
                    tab.FilePath is null
                        ? SaveDialogDefaults.FileNameFor(tabBar.ContentFor(tab).Text ?? string.Empty)
                        : Path.GetFileName(tab.FilePath),
                    SaveDialogDefaults.OfferedEncodings,
                    tab.Encoding);
                if (choice?.EncodingName is null)
                {
                    return null;
                }

                bool hasBom = choice.EncodingName == FileOpen.Utf8BomName
                    || (choice.EncodingName == tab.Encoding && tab.HasBom);
                return new SaveAsChoice(choice.Path, choice.EncodingName, hasBom, tab.LineEnding);
            });
    }

    async Task RelockTabAsync(Tab tab)
    {
        if (tabBar is null || tab.FilePath is null)
        {
            return;
        }

        XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
        if (root is null)
        {
            return;
        }

        string text = tabBar.ContentFor(tab).Text ?? string.Empty;
        var dialog = new LockDialog(tab.FilePath, password => NoteCrypto.RelockOrThrow(tab, text, password))
        {
            XamlRoot = root,
        };
        await dialog.ShowAsync();
    }

    async Task ShowSaveFailureAsync(string detail)
    {
        XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
        if (root is null)
        {
            return;
        }

        var dialog = new SaveFailureDialog(detail) { XamlRoot = root };
        await dialog.ShowAsync();
    }

    void IMenuHost.ShowPageSetup()
    {
        PrintService.ShowPageSetup(WindowNative.GetWindowHandle(this));
    }

    async Task IMenuHost.PrintAsync()
    {
        Tab? active = tabs.ActiveTab;
        if (active is null || tabBar is null)
        {
            return;
        }

        string text = tabBar.ContentFor(active).Text ?? string.Empty;
        string name = active.FilePath is null
            ? "Untitled"
            : System.IO.Path.GetFileName(active.FilePath);
        // Runs on the UI thread: the OS print dialog is modal here, and
        // the print follows inline (stock blocks the same way).
        PrintService.PrintOutcome outcome = PrintService.PrintInteractive(
            WindowNative.GetWindowHandle(this), text, name, SettingsStore.Shared.Current);
        if (!outcome.Printed && outcome.Error is not null)
        {
            XamlRoot? root = await WaitForXamlRootAsync().ConfigureAwait(true);
            if (root is null)
            {
                return;
            }

            var dialog = new PrintFailureDialog(outcome.Error) { XamlRoot = root };
            await dialog.ShowAsync();
        }
    }

    void IMenuHost.CloseTab() => tabBar?.RequestCloseActive();

    void IMenuHost.CloseWindow() => Close();

    void IMenuHost.Exit() => Close();

    IReadOnlyList<string> IMenuHost.RecentFiles()
    {
        try
        {
            return SettingsStore.Shared.Current.RecentFiles;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    void IMenuHost.ClearRecents()
    {
        try
        {
            SettingsStore.Shared.Update(fresh => RecentFiles.Clear(fresh.RecentFiles));
            App.RefreshJumpList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    void IMenuHost.SearchBing() => LaunchBing(BingSearch.SearchUrl(ActiveSelection()));

    void IMenuHost.ShowFontSettings() => ShowFontSettings();

    void IMenuHost.DefineBing() => LaunchBing(BingSearch.DefineUrl(ActiveSelection()));

    // Test seam (D00 T02 §21 item 4): with SCRATCHPAD_TEST_LAUNCH_CAPTURE
    // naming a file, the URI is appended there and no browser opens, so
    // the UI suite pins both Bing commands end to end without escaping
    // the app. Unset (every real launch), the launcher runs as before.
    static void LaunchBing(Uri url)
    {
        string? capture = Environment.GetEnvironmentVariable("SCRATCHPAD_TEST_LAUNCH_CAPTURE");
        if (!string.IsNullOrEmpty(capture))
        {
            try
            {
                File.AppendAllText(capture, url.AbsoluteUri + "\n");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
            }

            return;
        }

        _ = Launcher.LaunchUriAsync(url);
    }

    string? ActiveSelection()
    {
        if (tabs.ActiveTab is not Tab active || tabBar is null)
        {
            return null;
        }

        return tabBar.ContentFor(active).SelectedText;
    }

    async Task IMenuHost.ShowStatsAsync() => await ShowStatsPanelAsync().ConfigureAwait(true);

    async Task IMenuHost.ShowSnapshotsAsync() => await ShowSnapshotsPanelAsync().ConfigureAwait(true);

    async Task IMenuHost.ShowTemplatesAsync() => await ShowTemplatesPanelAsync().ConfigureAwait(true);

    async Task IMenuHost.ShowExportAsync() => await ShowExportPanelAsync().ConfigureAwait(true);

    async Task IMenuHost.LockFileAsync() => await ShowLockPanelAsync().ConfigureAwait(true);
}
