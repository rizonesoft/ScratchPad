using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace IntelligentNotepad;

// The dirty-tab close prompt, owned by D01 T01 §3 and reused by §7. Wording
// recorded live from Notepad 11.2607.14.0: title "Notepad", "Do you want to
// save changes to {name}?", Save / "Don't save" / Cancel. The {name} for an
// untitled tab is "{first-line}.txt" (single live observation: content FIRST
// prompted FIRST.txt while the tab itself showed FIRST); §7 re-verifies.
internal sealed class SavePromptDialog : ContentDialog
{
    public SavePromptDialog(string name)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        AutomationProperties.SetAutomationId(this, "SavePromptDialog");
        Title = "Notepad";
        Content = $"Do you want to save changes to {name}?";
        PrimaryButtonText = "Save";
        SecondaryButtonText = "Don't save";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;
    }
}
