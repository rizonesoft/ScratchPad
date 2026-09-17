using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ScratchPad;

// First-run and megaphone dialog. Content recorded from live Notepad 11.2607.14.0
// (D01 T01 §1): title "New in Notepad", four feature blurbs, "Start exploring".
internal sealed class WhatsNewDialog : ContentDialog
{
    public WhatsNewDialog()
    {
        AutomationProperties.SetAutomationId(this, "WhatsNewDialog");
        Title = "New in Notepad";
        PrimaryButtonText = "Start exploring";
        CloseButtonText = "Close";
        DefaultButton = ContentDialogButton.Primary;
        Content = new StackPanel
        {
            Spacing = 12,
            Children =
            {
                Blurb("Your essential text editor, elevated", "Rich formatting and smarter writing tools help enhance your notes."),
                Blurb("Smarter writing tools", "Make writing clearer, shorter, and easier to work with."),
                Blurb("Lightweight formatting", "Format your notes with Mark-down."),
                Blurb("Your essential text editor, elevated", "The Notepad that you know, with flexible formatting and a distraction-free space for quick edits and everyday notes."),
            },
        };
    }

    private static StackPanel Blurb(string heading, string body)
    {
        return new StackPanel
        {
            Children =
            {
                new TextBlock { Text = heading, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold },
                new TextBlock { Text = body, TextWrapping = TextWrapping.Wrap },
            },
        };
    }
}
