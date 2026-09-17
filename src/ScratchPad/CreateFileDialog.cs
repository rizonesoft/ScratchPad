using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ScratchPad;

// The missing-file create offer, owned by D01 T01 §8. Wording recorded live
// from stock Notepad 11.2607.14.0 (three identical UIA observations
// 2026-09-15; dialog crop
// resources/baseline/stock/notepad-missing-offer-n11.2607.14.0-win25h2.png):
// title "Notepad", "Cannot find the {full-path} file." plus
// "Do you want to create a new file?", Yes / No. Yes is the default button
// (observed: Yes carries the accent in the crop). Yes opens an empty tab
// bound to the path with bytes written on save (declared default; stock Yes
// is unprobed); No skips the file and creates nothing, as probed.
internal sealed class CreateFileDialog : ContentDialog
{
    public CreateFileDialog(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        AutomationProperties.SetAutomationId(this, "CreateFileDialog");
        Title = "Notepad";
        Content = $"Cannot find the {path} file.\n\nDo you want to create a new file?";
        PrimaryButtonText = "Yes";
        SecondaryButtonText = "No";
        DefaultButton = ContentDialogButton.Primary;
    }
}
