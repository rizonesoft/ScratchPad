using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace IntelligentNotepad;

// Reload prompt, owned by D01 T01 §21. Pure code-built ContentDialog: the
// caller switches on the result (Reload primary, Keep secondary, Cancel or
// dismiss keeps). Dirty text names the discarded edits explicitly.
internal sealed class ReloadDialog : ContentDialog
{
    public ReloadDialog(string fileName, bool isDirty)
    {
        ArgumentException.ThrowIfNullOrEmpty(fileName);
        AutomationProperties.SetAutomationId(this, "ReloadDialog");
        Title = "Reload file";
        Content = isDirty
            ? $"{fileName} changed on disk. Reload and discard your edits?"
            : $"{fileName} changed on disk. Reload?";
        PrimaryButtonText = "Reload";
        SecondaryButtonText = "Keep";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;
    }
}
