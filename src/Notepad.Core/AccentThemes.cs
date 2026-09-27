namespace Notepad.Core;

// Accent themes, owned by D01 T02 §10. "system" (the default) follows the
// Windows accent and overrides nothing; a built-in id names a palette the
// shell applies over the WinUI accent resources. Stock dark and light
// themes are unaffected: an accent recolors accent surfaces only.
public sealed record AccentColor(byte R, byte G, byte B)
{
    public string Hex => $"#{R:X2}{G:X2}{B:X2}";
}

public sealed record AccentTheme(string Id, string Name, AccentColor Color);

public static class AccentThemes
{
    public const string System = "system";

    // Default 2026-09-27: seven hues spread around the wheel at the
    // saturation and lightness of the Windows accent picker's own
    // swatches. Cost of changing: this list and its fixtures.
    public static IReadOnlyList<AccentTheme> BuiltIn { get; } =
    [
        new("ocean", "Ocean", new AccentColor(0x00, 0x63, 0xB1)),
        new("teal", "Teal", new AccentColor(0x00, 0x82, 0x7F)),
        new("forest", "Forest", new AccentColor(0x10, 0x7C, 0x10)),
        new("amber", "Amber", new AccentColor(0xCA, 0x50, 0x10)),
        new("rose", "Rose", new AccentColor(0xC3, 0x00, 0x52)),
        new("plum", "Plum", new AccentColor(0x88, 0x17, 0x98)),
        new("graphite", "Graphite", new AccentColor(0x5D, 0x5A, 0x58)),
    ];

    public static AccentTheme? Find(string? id) =>
        BuiltIn.FirstOrDefault(theme => string.Equals(theme.Id, id, StringComparison.Ordinal));

    // Unknown or missing ids read as the system accent, so a hand-edited
    // or older settings file never strands the app on a missing palette.
    public static string Normalize(string? id) => Find(id)?.Id ?? System;

    // The seven WinUI accent color keys for a base color: lighter steps
    // mix toward white, darker toward black, 20% per step.
    public static IReadOnlyDictionary<string, AccentColor> Shades(AccentColor baseColor)
    {
        ArgumentNullException.ThrowIfNull(baseColor);
        var white = new AccentColor(0xFF, 0xFF, 0xFF);
        var black = new AccentColor(0x00, 0x00, 0x00);
        return new Dictionary<string, AccentColor>(StringComparer.Ordinal)
        {
            ["SystemAccentColor"] = baseColor,
            ["SystemAccentColorLight1"] = Mix(baseColor, white, 0.2),
            ["SystemAccentColorLight2"] = Mix(baseColor, white, 0.4),
            ["SystemAccentColorLight3"] = Mix(baseColor, white, 0.6),
            ["SystemAccentColorDark1"] = Mix(baseColor, black, 0.2),
            ["SystemAccentColorDark2"] = Mix(baseColor, black, 0.4),
            ["SystemAccentColorDark3"] = Mix(baseColor, black, 0.6),
        };
    }

    public static AccentColor Mix(AccentColor from, AccentColor to, double amount)
    {
        ArgumentNullException.ThrowIfNull(from);
        ArgumentNullException.ThrowIfNull(to);
        double t = Math.Clamp(amount, 0.0, 1.0);
        return new AccentColor(Lerp(from.R, to.R, t), Lerp(from.G, to.G, t), Lerp(from.B, to.B, t));
    }

    private static byte Lerp(byte a, byte b, double t) =>
        (byte)Math.Round(a + ((b - a) * t), MidpointRounding.AwayFromZero);
}
