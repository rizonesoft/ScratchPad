using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Notepad.Core;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace ScratchPad;

// Accent themes, owned by D01 T02 §10. WinUI resolves accent brushes
// inside XamlControlsResources, where app- or element-level keys cannot
// shadow them at runtime, so the accent recolors the brush instances
// themselves. Ownership is explicit: ShadeMap names each supported accent
// brush key and the semantic shade it carries in each theme (WinUI's
// mapping: dark fills use Light2, dark text Light3; light fills Dark1,
// light text Dark2/Dark3). Discovery records a key only when its brush
// currently shows the live Windows color for that shade, so a key whose
// meaning differs on some WinUI version is skipped, never guessed.
// Control brushes (the checked radio fill, the toggle on-fill) are
// aliases of these instances, so they follow. A built-in accent sets
// each recorded brush to its shade of the palette (keeping alpha);
// "system" sets the current Windows color for that shade. When Windows
// changes its accent, the Windows colors are re-read and the current
// choice re-applied, so "system" keeps following Windows. HighContrast
// dictionaries are never touched.
internal static class AccentService
{
    // Theme dictionary kind -> accent brush key -> shade key.
    static readonly Dictionary<string, Dictionary<string, string>> ShadeMap = new(StringComparer.Ordinal)
    {
        ["Dark"] = new(StringComparer.Ordinal)
        {
            ["AccentFillColorDefaultBrush"] = "SystemAccentColorLight2",
            ["AccentFillColorSecondaryBrush"] = "SystemAccentColorLight2",
            ["AccentFillColorTertiaryBrush"] = "SystemAccentColorLight2",
            ["AccentTextFillColorPrimaryBrush"] = "SystemAccentColorLight3",
            ["AccentTextFillColorSecondaryBrush"] = "SystemAccentColorLight3",
            ["AccentTextFillColorTertiaryBrush"] = "SystemAccentColorLight2",
        },
        ["Light"] = new(StringComparer.Ordinal)
        {
            ["AccentFillColorDefaultBrush"] = "SystemAccentColorDark1",
            ["AccentFillColorSecondaryBrush"] = "SystemAccentColorDark1",
            ["AccentFillColorTertiaryBrush"] = "SystemAccentColorDark1",
            ["AccentTextFillColorPrimaryBrush"] = "SystemAccentColorDark2",
            ["AccentTextFillColorSecondaryBrush"] = "SystemAccentColorDark3",
            ["AccentTextFillColorTertiaryBrush"] = "SystemAccentColorDark1",
        },
    };

    static readonly (UIColorType Type, string Shade)[] SystemShades =
    [
        (UIColorType.Accent, "SystemAccentColor"),
        (UIColorType.AccentLight1, "SystemAccentColorLight1"),
        (UIColorType.AccentLight2, "SystemAccentColorLight2"),
        (UIColorType.AccentLight3, "SystemAccentColorLight3"),
        (UIColorType.AccentDark1, "SystemAccentColorDark1"),
        (UIColorType.AccentDark2, "SystemAccentColorDark2"),
        (UIColorType.AccentDark3, "SystemAccentColorDark3"),
    ];

    static List<(SolidColorBrush Brush, string Shade)>? targets;
    static Dictionary<string, Color> system = new(StringComparer.Ordinal);
    static UISettings? uiSettings;
    static DispatcherQueue? queue;
    static string applied = AccentThemes.System;

    public static string Current => applied;

    // Brushes the accent owns (diagnostics and tests).
    public static int TargetCount => targets?.Count ?? 0;

    public static void Apply(string? id)
    {
        string target = AccentThemes.Normalize(id);
        if (string.Equals(target, applied, StringComparison.Ordinal))
        {
            return;
        }

        EnsureDiscovered();
        applied = target;
        Recolor();
    }

    public static void Preview(string id) => Apply(id);

    public static void EndPreview() => Apply(SettingsStore.Shared.Current.Accent);

    static void EnsureDiscovered()
    {
        if (targets is not null)
        {
            return;
        }

        queue = DispatcherQueue.GetForCurrentThread();
        uiSettings = new UISettings();
        system = ReadSystem(uiSettings);
        targets = [];
        Walk(Application.Current.Resources, null, targets);
        uiSettings.ColorValuesChanged += OnSystemColorsChanged;
    }

    // Raised off the UI thread when Windows changes its colors: re-read the
    // Windows accent and re-apply the current choice on the UI thread (a
    // WinUI refresh of the accent brushes would otherwise leave a custom
    // accent overwritten, or "system" pinned to the old accent).
    static void OnSystemColorsChanged(UISettings sender, object args)
    {
        Dictionary<string, Color> fresh = ReadSystem(sender);
        queue?.TryEnqueue(() =>
        {
            system = fresh;
            Recolor();
        });
    }

    static void Recolor()
    {
        if (targets is null)
        {
            return;
        }

        IReadOnlyDictionary<string, AccentColor>? shades =
            AccentThemes.Find(applied) is AccentTheme accent ? AccentThemes.Shades(accent.Color) : null;
        foreach ((SolidColorBrush brush, string shade) in targets)
        {
            byte alpha = brush.Color.A;
            if (shades is not null)
            {
                brush.Color = Color.FromArgb(alpha, shades[shade].R, shades[shade].G, shades[shade].B);
            }
            else if (system.TryGetValue(shade, out Color windows))
            {
                brush.Color = Color.FromArgb(alpha, windows.R, windows.G, windows.B);
            }
        }
    }

    static Dictionary<string, Color> ReadSystem(UISettings settings)
    {
        var colors = new Dictionary<string, Color>(StringComparer.Ordinal);
        foreach ((UIColorType type, string shade) in SystemShades)
        {
            colors[shade] = settings.GetColorValue(type);
        }

        return colors;
    }

    // kind is null outside theme dictionaries, "Dark" for the Default and
    // Dark theme dictionaries, "Light" for Light; HighContrast is skipped.
    static void Walk(ResourceDictionary dictionary, string? kind, List<(SolidColorBrush, string)> found)
    {
        if (kind is not null && ShadeMap.TryGetValue(kind, out Dictionary<string, string>? map))
        {
            foreach ((string key, string shade) in map)
            {
                if (dictionary.TryGetValue(key, out object? value)
                    && value is SolidColorBrush brush
                    && system.TryGetValue(shade, out Color windows)
                    && brush.Color.R == windows.R && brush.Color.G == windows.G && brush.Color.B == windows.B
                    && !found.Exists(t => ReferenceEquals(t.Item1, brush)))
                {
                    found.Add((brush, shade));
                }
            }
        }

        foreach ((object key, object value) in dictionary.ThemeDictionaries)
        {
            string? childKind = (key as string) switch
            {
                "Default" or "Dark" => "Dark",
                "Light" => "Light",
                _ => null,
            };
            if (childKind is not null && value is ResourceDictionary theme)
            {
                Walk(theme, childKind, found);
            }
        }

        foreach (ResourceDictionary merged in dictionary.MergedDictionaries)
        {
            Walk(merged, kind, found);
        }
    }
}
