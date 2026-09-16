using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// Named local versions dialog, owned by D01 T01 §16. Code-built ContentDialog
// following SavePromptDialog (default WinUI styling, ListView-free: at most
// ten rows render as restore buttons). Take captures the live buffer through
// the injected reader; restore decodes stored bytes through FileOpen
// detection and replaces the buffer. Restore prompts sequentially: the
// versions dialog hides while the §7 prompt shows (never stacked) and
// reshows on Cancel or save failure; a successful restore leaves it open.
internal sealed class SnapshotsDialog : ContentDialog
{
    readonly string? filePath;
    readonly Func<string> readText;
    readonly Func<bool> isDirty;
    readonly SaveSpec spec;
    readonly Func<string, SaveResult> saveText;
    readonly Action<string> applyText;
    readonly Func<string> promptName;

    readonly TextBox nameBox;
    readonly Button takeButton;
    readonly StackPanel versions;
    readonly TextBlock error;

    public SnapshotsDialog(
        string? filePath,
        Func<string> readText,
        Func<bool> isDirty,
        SaveSpec spec,
        Func<string, SaveResult> saveText,
        Action<string> applyText,
        Func<string> promptName)
    {
        ArgumentNullException.ThrowIfNull(readText);
        ArgumentNullException.ThrowIfNull(isDirty);
        ArgumentNullException.ThrowIfNull(spec);
        ArgumentNullException.ThrowIfNull(saveText);
        ArgumentNullException.ThrowIfNull(applyText);
        ArgumentNullException.ThrowIfNull(promptName);
        this.filePath = filePath;
        this.readText = readText;
        this.isDirty = isDirty;
        this.spec = spec;
        this.saveText = saveText;
        this.applyText = applyText;
        this.promptName = promptName;
        AutomationProperties.SetAutomationId(this, "SnapshotsDialog");
        Title = "Snapshots";
        CloseButtonText = "Close";
        nameBox = new TextBox { PlaceholderText = "Snapshot name", MaxLength = SnapshotStore.MaxNameLength };
        AutomationProperties.SetAutomationId(nameBox, "SnapshotNameBox");
        takeButton = new Button { Content = "Take snapshot", Margin = new Thickness(0, 8, 0, 0) };
        AutomationProperties.SetAutomationId(takeButton, "TakeSnapshotButton");
        versions = new StackPanel();
        AutomationProperties.SetAutomationId(versions, "SnapshotsList");
        error = new TextBlock();
        AutomationProperties.SetAutomationId(error, "SnapshotError");
        if (filePath is null)
        {
            var note = new TextBlock { Text = "Save the file before taking snapshots." };
            AutomationProperties.SetAutomationId(note, "SnapshotsSaveFirst");
            Content = note;
            return;
        }

        nameBox.Text = SnapshotStore.SuggestName(DateTime.UtcNow);
        nameBox.TextChanged += (_, _) => RefreshTakeEnabled();
        takeButton.Click += (_, _) => Take();
        var retention = new TextBlock
        {
            Text = $"Keeps the last {SnapshotStore.MaxSnapshots} versions.",
            Margin = new Thickness(0, 8, 0, 4),
        };
        Content = new StackPanel
        {
            Children = { nameBox, takeButton, retention, versions, error },
        };
        RefreshList();
        RefreshTakeEnabled();
    }

    void Take()
    {
        if (filePath is null)
        {
            return;
        }

        try
        {
            SnapshotStore.Take(filePath, nameBox.Text.Trim(), readText(), spec);
            nameBox.Text = SnapshotStore.SuggestName(DateTime.UtcNow);
            ShowError(null);
            RefreshList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            ShowError(ex.Message);
        }

        RefreshTakeEnabled();
    }

    void RefreshTakeEnabled()
    {
        if (filePath is null)
        {
            takeButton.IsEnabled = false;
            return;
        }

        string name = nameBox.Text.Trim();
        takeButton.IsEnabled = name.Length > 0
            && !SnapshotStore.List(filePath).Any(entry => string.Equals(entry.Name, name, StringComparison.OrdinalIgnoreCase));
    }

    void RefreshList()
    {
        versions.Children.Clear();
        if (filePath is null)
        {
            return;
        }

        foreach (SnapshotEntry entry in SnapshotStore.List(filePath))
        {
            var restore = new Button
            {
                Content = $"{entry.Name} - {entry.CreatedUtc:yyyy-MM-dd HH:mm} - {entry.Bytes} B",
                HorizontalAlignment = HorizontalAlignment.Stretch,
                Margin = new Thickness(0, 2, 0, 2),
            };
            AutomationProperties.SetName(restore, $"Restore {entry.Name}");
            int id = entry.Id;
            restore.Click += (_, _) => _ = RestoreAsync(id);
            versions.Children.Add(restore);
        }
    }

    async Task RestoreAsync(int id)
    {
        if (filePath is null || XamlRoot is null)
        {
            return;
        }

        byte[] bytes;
        try
        {
            bytes = SnapshotStore.ReadBytes(filePath, id);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            ShowError(ex.Message);
            return;
        }

        string text = FileOpen.Detect(bytes).Text;
        if (!isDirty())
        {
            applyText(text);
            return;
        }

        Hide();
        ContentDialogResult answer = await new SavePromptDialog(promptName()) { XamlRoot = XamlRoot }.ShowAsync();
        if (answer == ContentDialogResult.Primary)
        {
            if (saveText(readText()) is not SaveSuccess)
            {
                await ShowAsync();
                return;
            }

            applyText(text);
            await ShowAsync();
            return;
        }

        if (answer == ContentDialogResult.Secondary)
        {
            applyText(text);
            await ShowAsync();
            return;
        }

        await ShowAsync();
    }

    void ShowError(string? message)
    {
        error.Text = message ?? string.Empty;
    }
}
