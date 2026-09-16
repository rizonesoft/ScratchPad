namespace Notepad.Core;

// Jump-list feed as plannable data, owned by D01 T01 §8. Pins (oldest
// first, as stored) fill the Pinned category; MRU recents minus pins fill
// Recent, each capped at RecentFiles.MaxCount. Missing files are kept (the
// §8 missing offer answers them on launch; the feed does no IO). Dedupe is
// case-insensitive: Windows paths. The app-side service commits this feed
// through ICustomDestinationList only when it changes, so user-removed
// items survive until the feed moves (residual: a feed change re-adds a
// removed item; honoring removals costs GetRemovedItems plus shell-item
// path extraction).
public sealed record JumpListItem(string Title, string Arguments, string Category);

public static class JumpListFeed
{
    public const string PinnedCategory = "Pinned";

    public const string RecentCategory = "Recent";

    public const string TasksCategory = "Tasks";

    // The static new-note task, defined here as data but committed by the
    // service, not Build(): the feed is user-data-driven (fingerprinted),
    // the task never changes (D01 T01 §25).
    public static readonly JumpListItem NewNoteTask = new("New note", LaunchArgs.NewNoteFlag, TasksCategory);

    public static IReadOnlyList<JumpListItem> Build(IList<string>? pinned, IList<string>? recent)
    {
        var items = new List<JumpListItem>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in pinned ?? Enumerable.Empty<string>())
        {
            if (items.Count >= RecentFiles.MaxCount || !seen.Add(path))
            {
                continue;
            }

            items.Add(new JumpListItem(Path.GetFileName(path), Quote(path), PinnedCategory));
        }

        int recentCount = 0;
        foreach (string path in recent ?? Enumerable.Empty<string>())
        {
            if (recentCount >= RecentFiles.MaxCount || !seen.Add(path))
            {
                continue;
            }

            recentCount++;
            items.Add(new JumpListItem(Path.GetFileName(path), Quote(path), RecentCategory));
        }

        return items;
    }

    // Change fingerprint for commit-on-change: the service stores it in
    // settings and skips the COM commit while it matches.
    public static string Fingerprint(IEnumerable<JumpListItem> items) =>
        string.Join("\n", items.Select(item => item.Category + "|" + item.Title + "|" + item.Arguments));

    static string Quote(string path) => "\"" + path + "\"";
}
