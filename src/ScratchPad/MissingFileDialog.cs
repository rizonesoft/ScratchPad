using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ScratchPad;

// The missing-file notice, owned by D01 T01 §6. Wording recorded live from
// stock Notepad 11.2607.14.0 (capture
// `notepad-missing-notice-n11.2607.14.0-win25h2.png`): title "Notepad",
// "Cannot find the {full-path} file.", OK. Stock fires it lazily when the
// resurrected tab is activated, and the tab survives OK; the next snapshot
// drops it. Title matches SavePromptDialog's stock-exact "Notepad".
internal sealed class MissingFileDialog : ContentDialog
{
    public MissingFileDialog(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        AutomationProperties.SetAutomationId(this, "MissingFileDialog");
        Title = "Notepad";
        Content = $"Cannot find the {path} file.";
        CloseButtonText = "OK";
    }
}
