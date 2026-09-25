namespace Notepad.Core;

// Held keys versus duplicate delivery (D00 T02 §43 item 4). A held chord
// delivers one key-down and then auto-repeat key-downs until release; a
// command either repeats with the hold or dispatches once per physical
// press, by class:
//
// - Repeatable: zoom in and out (each repeat steps the zoom again) and tab
//   cycling (Ctrl+Tab, Ctrl+Shift+Tab: holding walks the tabs).
// - One-shot: every other bound command (a held Ctrl+T opens one tab, a
//   held Ctrl+S saves once).
//
// This is a recorded default (stock Notepad's held-key behavior is not
// captured yet); the cost of changing a command's class is one entry in
// Repeatable. The app notes each press's repeat flag at its root before
// accelerators run and clears it on release; mouse invocation carries no
// repeat and always dispatches.
public static class HeldChord
{
    // Menu items by AutomationId, programmatic accelerators by their
    // TestMutation.Key target (virtual key and modifier bits).
    public static readonly IReadOnlySet<string> Repeatable = new HashSet<string>(StringComparer.Ordinal)
    {
        "MenuViewZoomIn",
        "MenuViewZoomOut",
        TestMutation.Key(0x09, 1),
        TestMutation.Key(0x09, 1 | 4),
    };

    [ThreadStatic]
    static bool repeating;

    public static void NotePress(bool isRepeat) => repeating = isRepeat;

    public static void NoteRelease() => repeating = false;

    // True when this dispatch is an auto-repeat of a one-shot command, so
    // the caller handles the key and runs nothing.
    public static bool Suppress(string command) => repeating && !Repeatable.Contains(command);

    // The documented count for a hold of `keyDowns` key-downs (the first
    // press plus its repeats): the fixture reads each class through the
    // same rule the app runs.
    public static int Dispatches(string command, int keyDowns)
    {
        int count = 0;
        for (int i = 0; i < keyDowns; i++)
        {
            NotePress(i > 0);
            if (!Suppress(command))
            {
                count++;
            }
        }

        NoteRelease();
        return count;
    }
}
