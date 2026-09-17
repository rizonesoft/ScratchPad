using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ScratchPad;

// The corrupt-store notice, owned by D01 T02 §2. When the settings file
// exists but does not parse (or claims a future schema version), the
// store resets to defaults and the first window shows this once at
// startup. Wording is ours (honest-non-parity: stock has no such notice).
internal sealed class CorruptSettingsDialog : ContentDialog
{
    public CorruptSettingsDialog()
    {
        AutomationProperties.SetAutomationId(this, "CorruptSettingsDialog");
        Title = "Notepad";
        Content = "Your settings file was unreadable, so default settings were restored.";
        CloseButtonText = "OK";
    }
}
