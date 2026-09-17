using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ScratchPad;

// The print failure notice, owned by D01 T02 §5: title "Notepad",
// OK-only, carrying the live printer detail (printer name plus the OS
// error text). Stock wording for print failures is unprobed; live detail
// over invented parity, per the §8 OpenMessages precedent.
internal sealed class PrintFailureDialog : ContentDialog
{
    public PrintFailureDialog(string detail)
    {
        AutomationProperties.SetAutomationId(this, "PrintFailureDialog");
        Title = "Notepad";
        Content = detail;
        CloseButtonText = "OK";
    }
}
