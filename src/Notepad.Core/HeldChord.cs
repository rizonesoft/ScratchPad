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

    // One counting definition (D00 T02 §51 item 8): every key event (a
    // first press or one auto-repeat) dispatches at most one bound command,
    // so a chord registered twice (two scopes, or two commands declaring
    // it) runs once per event. The event opens at the root's key-down and
    // closes behind it; a mouse invocation opens no event and always
    // dispatches.
    [ThreadStatic]
    static int eventSerial;

    [ThreadStatic]
    static int claimedSerial;

    [ThreadStatic]
    static bool eventOpen;

    // The flags live for one input message (R1-F1): `defer` queues their
    // reset behind the key event, so the accelerators that run for this
    // press read them and a later mouse click or a focus change never does.
    public static void NotePress(bool isRepeat, Action<Action> defer)
    {
        ArgumentNullException.ThrowIfNull(defer);
        repeating = isRepeat;
        eventSerial++;
        eventOpen = true;
        int serial = eventSerial;
        defer(() =>
        {
            if (eventSerial == serial)
            {
                eventOpen = false;
                repeating = false;
            }
        });
    }

    public static void NoteRelease() => repeating = false;

    // Focus loss, window deactivation, or a cancelled hold (D00 T02 §51
    // item 6): the hold ends, so the next key-down is a first press and
    // nothing stays suppressed or repeating.
    public static void Reset()
    {
        repeating = false;
        eventOpen = false;
    }

    // True when this dispatch is an auto-repeat of a one-shot command, so
    // the caller handles the key and runs nothing.
    public static bool Suppress(string command) => repeating && !Repeatable.Contains(command);

    // The guard every bound handler calls (§51 item 8): a one-shot
    // auto-repeat, or a second bound command in the same key event, runs
    // nothing; the first bound command of an event claims it.
    public static bool ShouldSkip(string command)
    {
        if (Suppress(command))
        {
            return true;
        }

        if (eventOpen)
        {
            if (claimedSerial == eventSerial)
            {
                return true;
            }

            claimedSerial = eventSerial;
        }

        return false;
    }

    // The documented count for an input sequence (§51 items 6 and 8), read
    // through the same rule the app runs: 'd' a key-down (a repeat when the
    // key is already held), 'u' a key-up, 'f' focus loss; each key-down
    // reaches `registrations` bound handlers.
    public static int Count(string command, string sequence, int registrations = 1)
    {
        ArgumentNullException.ThrowIfNull(sequence);
        int count = 0;
        bool held = false;
        var pending = new List<Action>();
        Reset();
        foreach (char c in sequence)
        {
            switch (c)
            {
                case 'd':
                    NotePress(held, pending.Add);
                    held = true;
                    for (int r = 0; r < registrations; r++)
                    {
                        if (!ShouldSkip(command))
                        {
                            count++;
                        }
                    }

                    foreach (Action a in pending)
                    {
                        a();
                    }

                    pending.Clear();
                    break;
                case 'u':
                    NoteRelease();
                    held = false;
                    break;
                case 'f':
                    Reset();
                    held = false;
                    break;
                default:
                    throw new ArgumentException($"unknown step '{c}' in {sequence}", nameof(sequence));
            }
        }

        Reset();
        return count;
    }

    // The documented count for a hold of `keyDowns` key-downs (the first
    // press plus its repeats): the fixture reads each class through the
    // same rule the app runs.
    public static int Dispatches(string command, int keyDowns) => Count(command, new string('d', keyDowns) + "u");
}
