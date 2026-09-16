namespace Notepad.Core;

// Bing handoff URLs, owned by D01 T02 §1 item 7. Stock 11.2607.14.0
// carries Search with Bing and Define with Bing (both Ctrl+E); the URL
// forms below are recorded defaults (the click was never probed live
// because it opens the operator's browser): a selection searches it
// URL-encoded, no selection opens the bare search page. The app launches
// the URL in the default browser; tests pin the builder, never the launch.
public static class BingSearch
{
    public const string SearchBase = "https://www.bing.com/search";

    public static Uri SearchUrl(string? selection)
    {
        string query = string.IsNullOrWhiteSpace(selection) ? string.Empty : selection.Trim();
        return new Uri(query.Length == 0 ? SearchBase : SearchBase + "?q=" + Uri.EscapeDataString(query));
    }

    public static Uri DefineUrl(string? selection)
    {
        string query = string.IsNullOrWhiteSpace(selection) ? string.Empty : selection.Trim();
        return new Uri(query.Length == 0 ? SearchBase : SearchBase + "?q=" + Uri.EscapeDataString("define " + query));
    }
}
