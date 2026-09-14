namespace Notepad.Core;

// Window title composition, recorded from live Notepad 11.2607.14.0 (D01 T01 §1):
// clean untitled "Untitled - Notepad", dirty untitled "*Untitled - Notepad",
// dirty file "*Implementation.txt - Notepad", dirty content-named "*hello - Notepad".
// Rule: a dirty marker "*" prefixes the display name, then " - " plus the app name.
// The display-name rule for untitled tabs is D01 T01 §2's; this composes, it does not name.
public static class WindowTitle
{
    public static string Format(string displayName, bool dirty, string appName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);
        ArgumentException.ThrowIfNullOrWhiteSpace(appName);
        return dirty ? $"*{displayName} - {appName}" : $"{displayName} - {appName}";
    }
}
