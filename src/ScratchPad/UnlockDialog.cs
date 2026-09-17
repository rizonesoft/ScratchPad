using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace ScratchPad;

// Unlock prompt, owned by D01 T01 §19. Code-built ContentDialog: the file
// name, a password box, and Unlock/Cancel. A wrong password surfaces inline
// and the dialog stays for a retry (the primary click is cancelled, so no
// partial render can escape); only a successful unlock dismisses. The
// password never leaves this dialog except into the callback.
internal sealed class UnlockDialog : ContentDialog
{
    readonly Action<string> unlock;

    readonly PasswordBox passwordBox;
    readonly TextBlock error;

    public UnlockDialog(string promptName, Action<string> unlock)
    {
        ArgumentNullException.ThrowIfNull(promptName);
        ArgumentNullException.ThrowIfNull(unlock);
        this.unlock = unlock;
        AutomationProperties.SetAutomationId(this, "UnlockDialog");
        Title = "Unlock file";
        PrimaryButtonText = "Unlock";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;
        passwordBox = new PasswordBox { PlaceholderText = "Password" };
        AutomationProperties.SetAutomationId(passwordBox, "UnlockPasswordBox");
        error = new TextBlock();
        AutomationProperties.SetAutomationId(error, "UnlockError");
        var info = new TextBlock { Text = $"Enter the password for {promptName}." };
        Content = new StackPanel
        {
            Children = { info, passwordBox, error },
        };
        PrimaryButtonClick += (_, args) =>
        {
            try
            {
                unlock(passwordBox.Password);
                passwordBox.Password = string.Empty;
                return;
            }
            catch (WrongPasswordException)
            {
                // Falls through to the wrong-password error below.
            }
            catch (InvalidDataException ex)
            {
                error.Text = ex.Message;
                args.Cancel = true;
                return;
            }

            error.Text = "Wrong password. Nothing was opened.";
            args.Cancel = true;
        };
    }
}
