using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Notepad.Core;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace ScratchPad;

// Accent themes, owned by D01 T02 §10. WinUI resolves accent brushes
// inside XamlControlsResources, where app- or element-level keys cannot
// shadow them at runtime, so the accent recolors the brush instances
// themselves: on first use every SolidColorBrush in the app's Light and
// Dark theme dictionaries (recursively, HighContrast excluded) whose key
// names an accent resource (contains "Accent") and whose color equals one
// of the seven live Windows accent shades is recorded with its original
// color and shade. The key test keeps a neutral brush that happens to
// share an accent shade's color out; control brushes such as the checked
// radio fill are aliases of the accent brush instances, so they follow. A built-in accent sets each recorded brush to
// the same shade of its palette (keeping the brush's alpha); "system"
// restores the originals. The brushes are shared, so every window
// repaints at once. Previews apply without touching the store;
// EndPreview restores the stored accent.
//
// Default 2026-09-27: the originals are the Windows accent read at first
// use; a Windows accent change mid-session shows after a restart while a
// custom accent was ever applied. Cost of changing: re-read UISettings on
// its ColorValuesChanged event and re-record.
internal static class AccentService
{
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

    static List<(SolidColorBrush Brush, Color Original, string Shade)>? targets;
    static string applied = AccentThemes.System;

    public static string Current => applied;

    // Brushes recolored by the current accent (diagnostics and tests).
    public static int TargetCount => targets?.Count ?? 0;

    public static void Apply(string? id)
    {
        string target = AccentThemes.Normalize(id);
        if (string.Equals(target, applied, StringComparison.Ordinal))
        {
            return;
        }

        targets ??= Discover();
        IReadOnlyDictionary<string, AccentColor>? shades =
            AccentThemes.Find(target) is AccentTheme accent ? AccentThemes.Shades(accent.Color) : null;
        foreach ((SolidColorBrush brush, Color original, string shade) in targets)
        {
            brush.Color = shades is null
                ? original
                : Color.FromArgb(original.A, shades[shade].R, shades[shade].G, shades[shade].B);
        }

        applied = target;
    }

    public static void Preview(string id) => Apply(id);

    public static void EndPreview() => Apply(SettingsStore.Shared.Current.Accent);

    static List<(SolidColorBrush, Color, string)> Discover()
    {
        var settings = new UISettings();
        var byColor = new Dictionary<uint, string>();
        foreach ((UIColorType type, string shade) in SystemShades)
        {
            Color c = settings.GetColorValue(type);
            byColor.TryAdd(Rgb(c), shade);
        }

        var found = new List<(SolidColorBrush, Color, string)>();
        var seen = new HashSet<SolidColorBrush>(ReferenceEqualityComparer.Instance);
        Walk(Application.Current.Resources, byColor, found, seen);
        return found;
    }

    static void Walk(
        ResourceDictionary dictionary,
        Dictionary<uint, string> byColor,
        List<(SolidColorBrush, Color, string)> found,
        HashSet<SolidColorBrush> seen)
    {
        foreach ((object key, object value) in dictionary)
        {
            if (key is string name
                && name.Contains("Accent", StringComparison.Ordinal)
                && value is SolidColorBrush brush
                && byColor.TryGetValue(Rgb(brush.Color), out string? shade)
                && seen.Add(brush))
            {
                found.Add((brush, brush.Color, shade));
            }
        }

        foreach ((object key, object value) in dictionary.ThemeDictionaries)
        {
            if (value is ResourceDictionary theme && !string.Equals(key as string, "HighContrast", StringComparison.Ordinal))
            {
                Walk(theme, byColor, found, seen);
            }
        }

        foreach (ResourceDictionary merged in dictionary.MergedDictionaries)
        {
            Walk(merged, byColor, found, seen);
        }
    }

    static uint Rgb(Color c) => ((uint)c.R << 16) | ((uint)c.G << 8) | c.B;
}
