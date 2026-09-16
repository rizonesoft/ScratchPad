namespace Notepad.Core;

// Share receive path, owned by D01 T01 §24. UI-free: the activation handler
// passes the shared text (or null when the share carries no text) and gets
// back the new tab, or null when the share declines. Registration lives at
// D07 T01 §7: only a packaged app can declare the share contract.
public static class ShareReceiver
{
    public static Tab? Receive(TabModel model, string? text)
    {
        ArgumentNullException.ThrowIfNull(model);
        if (string.IsNullOrEmpty(text))
        {
            return null;
        }

        Tab tab = model.NewTab();
        tab.NotifyEdited(text);
        return tab;
    }
}
