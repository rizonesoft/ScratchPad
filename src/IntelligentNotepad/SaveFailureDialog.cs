using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace IntelligentNotepad;

// The file-save failure notice, owned by D01 T02 §1, reporting §5's
// unmapped failures (the OS message, title "Notepad" per the dialog-title
// precedent), OK-only. Stock's exact save-error wording is unprobed;
// the detail carries the failure.
internal sealed class SaveFailureDialog : ContentDialog
{
    public SaveFailureDialog(string detail)
    {
        AutomationProperties.SetAutomationId(this, "SaveFailureDialog");
        Title = "Notepad";
        Content = detail;
        CloseButtonText = "OK";
    }
}
