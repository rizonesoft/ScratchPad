using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace ScratchPad;

// The file-open failure notice, owned by D01 T01 §8, rendering the §4
// OpenMessages strings (stock-verbatim missing/locked wording, live OS
// detail for unreadable, honest-non-parity over-limit text): title
// "Notepad", OK-only. First rendered here for the command-line and drop
// entry points; the D01 T02 §1 Open trigger reuses this dialog.
internal sealed class OpenFailureDialog : ContentDialog
{
    public OpenFailureDialog(OpenFailure failure, string? detail = null)
    {
        AutomationProperties.SetAutomationId(this, "OpenFailureDialog");
        Title = OpenMessages.DialogTitle;
        Content = OpenMessages.MessageFor(failure, detail);
        CloseButtonText = "OK";
    }
}
