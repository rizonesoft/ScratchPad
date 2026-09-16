using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// Lock dialog, owned by D01 T01 §19. Code-built ContentDialog following
// ExportDialog (default WinUI styling). Password plus confirm must match
// and be non-empty; the injected callback relocks through NoteCrypto and
// throws with the failure detail, which surfaces inline. Untitled tabs get
// a save-first note instead. The password never leaves this dialog except
// into the callback, which holds it only for the key derivation.
internal sealed class LockDialog : ContentDialog
{
    readonly string? filePath;
    readonly Action<string> lockWith;

    readonly PasswordBox passwordBox;
    readonly PasswordBox confirmBox;
    readonly Button lockButton;
    readonly TextBlock status;

    public LockDialog(string? filePath, Action<string> lockWith)
    {
        ArgumentNullException.ThrowIfNull(lockWith);
        this.filePath = filePath;
        this.lockWith = lockWith;
        AutomationProperties.SetAutomationId(this, "LockDialog");
        Title = "Lock file";
        CloseButtonText = "Close";
        passwordBox = new PasswordBox { PlaceholderText = "Password" };
        AutomationProperties.SetAutomationId(passwordBox, "LockPasswordBox");
        confirmBox = new PasswordBox { PlaceholderText = "Confirm password", Margin = new Thickness(0, 8, 0, 0) };
        AutomationProperties.SetAutomationId(confirmBox, "LockConfirmBox");
        lockButton = new Button { Content = "Lock", Margin = new Thickness(0, 8, 0, 0) };
        AutomationProperties.SetAutomationId(lockButton, "LockButton");
        status = new TextBlock();
        AutomationProperties.SetAutomationId(status, "LockStatus");
        if (filePath is null)
        {
            var note = new TextBlock { Text = "Save the file before locking." };
            AutomationProperties.SetAutomationId(note, "LockSaveFirst");
            Content = note;
            return;
        }

        passwordBox.PasswordChanged += (_, _) => RefreshLockEnabled();
        confirmBox.PasswordChanged += (_, _) => RefreshLockEnabled();
        lockButton.Click += (_, _) => Lock();
        Content = new StackPanel
        {
            Children = { passwordBox, confirmBox, lockButton, status },
        };
        RefreshLockEnabled();
    }

    void Lock()
    {
        if (filePath is null)
        {
            return;
        }

        try
        {
            lockWith(passwordBox.Password);
            status.Text = "Locked.";
            passwordBox.Password = string.Empty;
            confirmBox.Password = string.Empty;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            status.Text = ex.Message;
        }

        RefreshLockEnabled();
    }

    void RefreshLockEnabled()
    {
        if (filePath is null)
        {
            return;
        }

        lockButton.IsEnabled = passwordBox.Password.Length > 0
            && passwordBox.Password == confirmBox.Password;
    }
}
