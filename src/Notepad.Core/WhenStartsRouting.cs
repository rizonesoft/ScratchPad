namespace Notepad.Core;

// "When Notepad starts" preference, owned by D01 T01 §6. Stock values
// (probed 2026-09-15, capture
// `notepad-when-starts-n11.2607.14.0-win25h2.png`): "Continue previous
// session" (selected) and "Start new session and discard unsaved changes",
// normalized to "continue" and "fresh" in ShellSettings.WhenStarts. The
// fresh-install default is "continue": eight independent setup guides
// concur that stock selects Continue previous session out of the box, and
// the stock capture shows it selected. Unknown values continue (restore,
// never strand a session). D01 T02 §2 renders the radios; end-to-end honor
// is driven here (both modes) and there.
public enum StartupMode
{
    ContinueSession,
    FreshWindow,
}

public static class WhenStartsRouting
{
    public const string Continue = "continue";

    public const string Fresh = "fresh";

    public static StartupMode Route(string? whenStarts) => whenStarts switch
    {
        Fresh => StartupMode.FreshWindow,
        _ => StartupMode.ContinueSession,
    };
}
