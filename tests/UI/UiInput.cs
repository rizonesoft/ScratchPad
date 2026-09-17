using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace UI;

// Single input funnel for the UI suite (D00 T02 §8). Pattern methods drive
// background windows without touching focus or the cursor; Press is the
// physical core reserved for fenced interactive tests (trait
// Category=Interactive), the only callers allowed to activate windows.
internal static class UiInput
{
    // Physical shortcut press for fenced tests only. Default-suite tests
    // must use the pattern methods below instead.
    internal static void Press(Window window, VirtualKeyShort key, bool withControl, bool withShift = false, bool withAlt = false)
    {
        ArgumentNullException.ThrowIfNull(window);
        window.Focus();
        Thread.Sleep(150);
        var mods = new List<VirtualKeyShort>();
        if (withControl)
        {
            mods.Add(VirtualKeyShort.CONTROL);
        }

        if (withShift)
        {
            mods.Add(VirtualKeyShort.SHIFT);
        }

        if (withAlt)
        {
            mods.Add(VirtualKeyShort.ALT);
        }

        if (mods.Count > 0)
        {
            using (Keyboard.Pressing(mods.ToArray()))
            {
                Keyboard.Press(key);
            }
        }
        else
        {
            Keyboard.Press(key);
        }

        Thread.Sleep(250);
    }

    // Appends text through ValuePattern: no focus, no keystrokes. For
    // dirtying documents and seeding content, not for testing typing.
    internal static void AppendText(TextBox box, string text)
    {
        ArgumentNullException.ThrowIfNull(box);
        ArgumentNullException.ThrowIfNull(text);
        box.Text = (box.Text ?? string.Empty) + text;
        Thread.Sleep(200);
    }

    // Invokes a menu item through UIA patterns on a background window: no
    // Focus (spiked 2026-09-17: Invoke dispatches unfocused) and no click
    // fallback. Items without Invoke support cannot run unfocused; their
    // tests stay fenced.
    internal static void InvokeMenuItem(Window window, string topId, string itemId)
    {
        ArgumentNullException.ThrowIfNull(window);
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Xunit.Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        var item = RetryFind(window, itemId);
        Xunit.Assert.NotNull(item);
        Xunit.Assert.True(item.Patterns.Invoke.IsSupported, $"menu item {itemId} has no Invoke pattern; its test cannot run unfocused");
        item.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(400);
    }

    // Selects all text through TextPattern: the focus-free Ctrl+A.
    internal static void SelectAllText(TextBox box)
    {
        ArgumentNullException.ThrowIfNull(box);
        var text = box.Patterns.Text.PatternOrDefault;
        Xunit.Assert.NotNull(text);
        text.DocumentRange.Select();
        Thread.Sleep(200);
    }

    // Collapses an expanded menu or combo: the focus-free Escape.
    internal static void Collapse(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        var expand = element.Patterns.ExpandCollapse.PatternOrDefault;
        Xunit.Assert.NotNull(expand);
        expand.Collapse();
        Thread.Sleep(200);
    }

    static AutomationElement? RetryFind(Window window, string automationId)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            var found = window.FindFirstDescendant(cf => cf.ByAutomationId(automationId));
            if (found is not null)
            {
                return found;
            }

            Thread.Sleep(250);
        }

        return null;
    }
}
