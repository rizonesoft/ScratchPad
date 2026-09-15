using System.Runtime.InteropServices;
using Notepad.Core;
using Windows.UI.StartScreen;
using WinJumpListItem = Windows.UI.StartScreen.JumpListItem;

namespace IntelligentNotepad;

// Jump-list publisher, owned by D01 T01 §8. The classic
// ICustomDestinationList builder coclass is unregistered on current
// Windows (probed 2026-09-15: every registered destination class fails
// QI), so this commits the JumpListFeed through the WinRT JumpList API,
// which works unpackaged (spike-proven). Commits run only when the feed
// fingerprint moves, and failures never crash startup: the taskbar
// read-back drive is the proof a commit landed.
internal static class JumpListService
{
    public const string AppId = "Rizonesoft.IntelligentNotepad";

    static bool appIdSet;

    public static void EnsureAppId()
    {
        if (appIdSet)
        {
            return;
        }

        appIdSet = true;
        SetCurrentProcessExplicitAppUserModelID(AppId);
    }

    // Commits the feed when it differs from the stored fingerprint.
    // Returns true when a commit landed; API failures return false.
    public static bool RefreshIfChanged(ShellSettings settings, string exePath)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        EnsureAppId();
        IReadOnlyList<Notepad.Core.JumpListItem> feed = JumpListFeed.Build(settings.PinnedFiles, settings.RecentFiles);
        string fingerprint = JumpListFeed.Fingerprint(feed);
        if (string.Equals(fingerprint, settings.JumpListHash, StringComparison.Ordinal))
        {
            return false;
        }

        try
        {
            Commit(feed, exePath);
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or UnauthorizedAccessException)
        {
            System.Diagnostics.Debug.WriteLine($"Jump list commit failed: {ex.Message}");
            return false;
        }

        settings.JumpListHash = fingerprint;
        settings.Save();
        return true;
    }

    static void Commit(IReadOnlyList<Notepad.Core.JumpListItem> feed, string exePath)
    {
        JumpList list = JumpList.LoadCurrentAsync().AsTask().GetAwaiter().GetResult();
        list.Items.Clear();
        foreach (Notepad.Core.JumpListItem item in feed)
        {
            WinJumpListItem entry = WinJumpListItem.CreateWithArguments(item.Arguments, item.Title);
            entry.GroupName = item.Category;
            list.Items.Add(entry);
        }

        list.SaveAsync().AsTask().GetAwaiter().GetResult();
    }

    [DllImport("shell32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern void SetCurrentProcessExplicitAppUserModelID(string appId);
}
