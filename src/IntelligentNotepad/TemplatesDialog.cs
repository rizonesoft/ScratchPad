using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// New-from-template picker, owned by D01 T01 §17. Code-built ContentDialog
// following SnapshotsDialog (default WinUI styling, rows as buttons).
// Choosing a template expands {title} from the title box and {date} to the
// locale short date of use, then opens it as a new untitled tab through the
// injected use callback. "Save current as template" stores the active tab's
// buffer under the title-box name, which is what makes customs user-made.
internal sealed class TemplatesDialog : ContentDialog
{
    readonly TemplateStore store;
    readonly Func<string> readText;
    readonly Action<string> useTemplate;

    readonly TextBox titleBox;
    readonly Button saveButton;
    readonly StackPanel customs;
    readonly TextBlock error;

    public TemplatesDialog(TemplateStore store, Func<string> readText, Action<string> useTemplate)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(readText);
        ArgumentNullException.ThrowIfNull(useTemplate);
        this.store = store;
        this.readText = readText;
        this.useTemplate = useTemplate;
        AutomationProperties.SetAutomationId(this, "TemplatesDialog");
        Title = "New from template";
        CloseButtonText = "Close";
        titleBox = new TextBox { PlaceholderText = "Title" };
        AutomationProperties.SetAutomationId(titleBox, "TemplateTitleBox");
        titleBox.TextChanged += (_, _) => RefreshSaveEnabled();
        var builtins = new StackPanel();
        AutomationProperties.SetAutomationId(builtins, "BuiltInTemplates");
        foreach (NoteTemplate template in Templates.BuiltIn)
        {
            builtins.Children.Add(UseButton(template));
        }

        customs = new StackPanel();
        AutomationProperties.SetAutomationId(customs, "CustomTemplates");
        saveButton = new Button { Content = "Save current as template", Margin = new Thickness(0, 8, 0, 0) };
        AutomationProperties.SetAutomationId(saveButton, "SaveTemplateButton");
        saveButton.Click += (_, _) => SaveCurrent();
        error = new TextBlock();
        AutomationProperties.SetAutomationId(error, "TemplateError");
        Content = new StackPanel
        {
            Children = { titleBox, builtins, customs, saveButton, error },
        };
        RefreshCustoms();
        RefreshSaveEnabled();
    }

    Button UseButton(NoteTemplate template)
    {
        var use = new Button
        {
            Content = template.Name,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 2, 0, 2),
        };
        AutomationProperties.SetName(use, $"Use {template.Name}");
        use.Click += (_, _) => Use(template);
        return use;
    }

    void Use(NoteTemplate template)
    {
        string expanded = Templates.Expand(template.Body, titleBox.Text.Trim(), DateOnly.FromDateTime(DateTime.Now));
        Hide();
        useTemplate(expanded);
    }

    void SaveCurrent()
    {
        try
        {
            store.SaveCustom(titleBox.Text.Trim(), readText());
            ShowError(null);
            RefreshCustoms();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            ShowError(ex.Message);
        }

        RefreshSaveEnabled();
    }

    void RefreshCustoms()
    {
        customs.Children.Clear();
        foreach (NoteTemplate template in store.ListCustom())
        {
            customs.Children.Add(UseButton(template));
        }
    }

    void RefreshSaveEnabled()
    {
        saveButton.IsEnabled = titleBox.Text.Trim().Length > 0;
    }

    void ShowError(string? message)
    {
        error.Text = message ?? string.Empty;
    }
}
