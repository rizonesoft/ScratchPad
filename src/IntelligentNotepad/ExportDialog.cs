using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// Export dialog, owned by D01 T01 §18. Code-built ContentDialog following
// TemplatesDialog (default WinUI styling, one button per format). The base
// name box holds the destination file name without extension; each format
// button converts the live buffer through the injected exporter and writes
// beside the source file. Untitled tabs get a save-first note instead.
internal sealed class ExportDialog : ContentDialog
{
    readonly string? filePath;
    readonly Func<ExportFormat, string, string> exportText;

    readonly TextBox nameBox;
    readonly TextBlock status;

    public ExportDialog(string? filePath, Func<ExportFormat, string, string> exportText)
    {
        ArgumentNullException.ThrowIfNull(exportText);
        this.filePath = filePath;
        this.exportText = exportText;
        AutomationProperties.SetAutomationId(this, "ExportDialog");
        Title = "Export";
        CloseButtonText = "Close";
        status = new TextBlock();
        AutomationProperties.SetAutomationId(status, "ExportStatus");
        if (filePath is null)
        {
            var note = new TextBlock { Text = "Save the file before exporting." };
            AutomationProperties.SetAutomationId(note, "ExportSaveFirst");
            Content = note;
            nameBox = new TextBox();
            return;
        }

        nameBox = new TextBox { Text = Path.GetFileNameWithoutExtension(filePath) + "-export" };
        AutomationProperties.SetAutomationId(nameBox, "ExportNameBox");
        nameBox.TextChanged += (_, _) => RefreshExportEnabled();
        var markdown = FormatButton(ExportFormat.Markdown, "Export Markdown");
        var html = FormatButton(ExportFormat.Html, "Export HTML");
        var plain = FormatButton(ExportFormat.PlainText, "Export Plain Text");
        Content = new StackPanel
        {
            Children = { nameBox, markdown, html, plain, status },
        };
        RefreshExportEnabled();
    }

    Button FormatButton(ExportFormat format, string label)
    {
        var button = new Button
        {
            Content = label,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 2, 0, 2),
        };
        AutomationProperties.SetName(button, label);
        button.Click += (_, _) => Export(format);
        return button;
    }

    void Export(ExportFormat format)
    {
        if (filePath is null)
        {
            return;
        }

        try
        {
            string written = exportText(format, nameBox.Text.Trim());
            status.Text = $"Exported {written}.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            status.Text = ex.Message;
        }
    }

    void RefreshExportEnabled()
    {
        if (filePath is null)
        {
            return;
        }

        bool enabled = nameBox.Text.Trim().Length > 0;
        foreach (var child in ((StackPanel)Content).Children)
        {
            if (child is Button button)
            {
                button.IsEnabled = enabled;
            }
        }
    }
}
