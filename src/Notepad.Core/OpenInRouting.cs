namespace Notepad.Core;

// "Opening files" routing, owned by D01 T01 §9. Stock values (probed
// 2026-09-15, capture
// `notepad-open-in-setting-n11.2607.14.0-win25h2.png`): "Open in a new tab"
// (selected) and "Open in a new window", normalized to "new-tab" and
// "new-window" in ShellSettings.OpenIn. Unknown values route to the active
// window (stay, never spray windows). D01 T01 §8 (command line) and D01 T02
// §1 (File menu) call Route at their time; end-to-end honor is driven
// there. This section proves the mode value and the routing.
public enum OpenTarget
{
    ActiveWindowNewTab,
    NewWindow,
}

public static class OpenInRouting
{
    public const string NewTab = "new-tab";

    public const string NewWindow = "new-window";

    public static OpenTarget Route(string? openIn) => openIn switch
    {
        NewWindow => OpenTarget.NewWindow,
        _ => OpenTarget.ActiveWindowNewTab,
    };
}
