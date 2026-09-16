namespace Notepad.Core;

// UIA tab names, owned by D01 T01 §28. Stock names carry ". Modified." /
// ". Unmodified." suffixes (run-1 recon, both halves live-proven: the
// Modified half in §22, the Unmodified half by the §28 probe). TabBar
// calls this one place instead of formatting names itself.
public static class TabAccessibilityName
{
    public static string For(string displayName, bool isDirty)
    {
        ArgumentNullException.ThrowIfNull(displayName);
        return isDirty ? $"{displayName}. Modified." : $"{displayName}. Unmodified.";
    }
}
