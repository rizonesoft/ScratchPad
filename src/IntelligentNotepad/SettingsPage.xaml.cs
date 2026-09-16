using System.Globalization;
using System.Reflection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notepad.Core;

namespace IntelligentNotepad;

// Settings page, owned by D01 T02 §3. Every bound control writes through
// SettingsStore.Update (the store stays the only writer); the page
// re-reads on the store's Changed event so a sibling window's change
// reflects live. Disabled cards belong to their recorded owners and are
// never touched here. Option labels are stock-verbatim (probed
// 2026-09-16, stock 11.2607.14.0); the store keeps its normalized values.
internal sealed partial class SettingsPage : UserControl
{
    static readonly string[] FontStyles = ["Regular", "Italic", "Bold", "Bold Italic"];

    static readonly int[] FontSizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72];

    static readonly (string Label, string Value)[] OpeningOptions =
    [
        ("Open in a new tab", OpenInRouting.NewTab),
        ("Open in a new window", OpenInRouting.NewWindow),
    ];

    static readonly (string Label, string Value)[] WhenStartsOptions =
    [
        ("Continue previous session", WhenStartsRouting.Continue),
        ("Start new session and discard unsaved changes", WhenStartsRouting.Fresh),
    ];

    static readonly (string Label, string Value)[] ThemeOptions =
    [
        ("Light", "light"),
        ("Dark", "dark"),
        ("Use system setting", "system"),
    ];

    bool suspend;

    public SettingsPage()
    {
        InitializeComponent();
        suspend = true;
        try
        {
            foreach (string family in InstalledFamilies())
            {
                FontFamilyCombo.Items.Add(family);
            }

            foreach (string style in FontStyles)
            {
                FontStyleCombo.Items.Add(style);
            }

            foreach (int size in FontSizes)
            {
                FontSizeCombo.Items.Add(size.ToString(CultureInfo.InvariantCulture));
            }

            foreach ((string label, _) in OpeningOptions)
            {
                OpeningCombo.Items.Add(label);
            }

            AboutVersion.Text = AppVersion();
            RefreshFromStore();
        }
        finally
        {
            suspend = false;
        }

        SettingsStore.Shared.Changed += OnStoreChanged;
        Unloaded += (_, _) => SettingsStore.Shared.Changed -= OnStoreChanged;
    }

    // Edit > Font lands here: the Font card opens and scrolls into view.
    public void JumpToFont()
    {
        FontCard.IsExpanded = true;
        FontCard.StartBringIntoView();
    }

    static List<string> InstalledFamilies()
    {
        try
        {
            return System.Drawing.FontFamily.Families
                .Select(family => family.Name)
                .OrderBy(name => name, StringComparer.Ordinal)
                .ToList();
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.ExternalException)
        {
            // GDI+ failed to enumerate (broken font setup): the page still
            // opens with the default family rather than taking settings down.
            return ["Consolas"];
        }
    }

    static string AppVersion()
    {
        // The number belongs to the release packaging work (D07 T01 §1
        // pins identity); this page displays whatever the assembly says.
        return Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0.0";
    }

    void OnStoreChanged(object? sender, EventArgs e)
    {
        DispatcherQueue.TryEnqueue(RefreshFromStore);
    }

    void RefreshFromStore()
    {
        suspend = true;
        try
        {
            ShellSettings current = SettingsStore.Shared.Current;
            CheckRadio(ThemeLight, ThemeDark, ThemeSystem, ThemeOptions, current.Theme);
            SelectCombo(FontFamilyCombo, current.FontFamily);
            SelectCombo(FontStyleCombo, current.FontStyle);
            SelectCombo(FontSizeCombo, current.FontSize.ToString(CultureInfo.InvariantCulture));
            UpdateFontPreview();
            WordWrapToggle.IsOn = current.WordWrap;
            SelectCombo(OpeningCombo, OpeningOptions.FirstOrDefault(o => o.Value == current.OpenIn).Label);
            CheckRadio(WhenStartsContinue, WhenStartsFresh, null, WhenStartsOptions, current.WhenStarts);
        }
        finally
        {
            suspend = false;
        }
    }

    // Every combo shows the truth: a stored value outside the list is
    // appended rather than hidden (a custom or migrated value stays
    // visible and selectable).
    static void SelectCombo(ComboBox combo, string? value)
    {
        if (value is null)
        {
            combo.SelectedItem = null;
            return;
        }

        if (!combo.Items.Contains(value))
        {
            combo.Items.Add(value);
        }

        combo.SelectedItem = value;
    }

    static void CheckRadio(RadioButton first, RadioButton second, RadioButton? third,
        (string Label, string Value)[] options, string value)
    {
        RadioButton[] buttons = third is null ? [first, second] : [first, second, third];
        for (int i = 0; i < buttons.Length; i++)
        {
            buttons[i].IsChecked = options[i].Value == value;
        }
    }

    void UpdateFontPreview()
    {
        ShellSettings current = SettingsStore.Shared.Current;
        FontPreview.FontFamily = new Microsoft.UI.Xaml.Media.FontFamily(current.FontFamily);
        FontPreview.FontSize = current.FontSize;
        FontPreview.FontStyle = current.FontStyle.Contains("Italic", StringComparison.Ordinal)
            ? Windows.UI.Text.FontStyle.Italic
            : Windows.UI.Text.FontStyle.Normal;
        FontPreview.FontWeight = current.FontStyle.Contains("Bold", StringComparison.Ordinal)
            ? Microsoft.UI.Text.FontWeights.Bold
            : Microsoft.UI.Text.FontWeights.Normal;
    }

    void ThemeRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (suspend || sender is not RadioButton radio || radio.IsChecked != true)
        {
            return;
        }

        string value = radio == ThemeLight ? "light" : radio == ThemeDark ? "dark" : "system";
        SettingsStore.Shared.Update(current => current.Theme = value);
    }

    void FontCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (suspend || sender is not ComboBox combo || combo.SelectedItem is not string selected)
        {
            return;
        }

        if (combo == FontFamilyCombo)
        {
            SettingsStore.Shared.Update(current => current.FontFamily = selected);
        }
        else if (combo == FontStyleCombo)
        {
            SettingsStore.Shared.Update(current => current.FontStyle = selected);
        }
        else if (int.TryParse(selected, NumberStyles.Integer, CultureInfo.InvariantCulture, out int size))
        {
            SettingsStore.Shared.Update(current => current.FontSize = size);
        }
    }

    void WordWrapToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (suspend || sender is not ToggleSwitch toggle)
        {
            return;
        }

        bool isOn = toggle.IsOn;
        SettingsStore.Shared.Update(current => current.WordWrap = isOn);
    }

    void OpeningCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (suspend || OpeningCombo.SelectedItem is not string selected)
        {
            return;
        }

        string value = OpeningOptions.FirstOrDefault(o => o.Label == selected).Value ?? OpenInRouting.NewTab;
        SettingsStore.Shared.Update(current => current.OpenIn = value);
    }

    void WhenStartsRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (suspend || sender is not RadioButton radio || radio.IsChecked != true)
        {
            return;
        }

        string value = radio == WhenStartsContinue ? WhenStartsRouting.Continue : WhenStartsRouting.Fresh;
        SettingsStore.Shared.Update(current => current.WhenStarts = value);
    }
}
