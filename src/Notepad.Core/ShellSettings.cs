using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

namespace Notepad.Core;

// Local persistence seam for shell state, owned by D01 T01 §1 and adopted
// by the D01 T02 §2 settings store: the store reads these keys (same
// file, same names) and owns the only write (Save delegates to
// SettingsStore.WriteSnapshot). Key list, consumers, defaults, and default
// sources live in docs/settings-schema.md, which replaces the sketch that
// used to sit here.
public sealed class ShellSettings
{
    public int X { get; set; } = 50;

    public int Y { get; set; } = 50;

    public int Width { get; set; } = 900;

    public int Height { get; set; } = 650;

    public string Theme { get; set; } = "system";

    // Store schema version, owned by D01 T02 §2. Absent (0) means the
    // unversioned file §2 inherited; 1 is current. Migration stamps the
    // version and carries every key forward unchanged.
    public int Version { get; set; }

    // Editor font, owned by D01 T02 §2, consumed by §3 and D02 T01.
    // Defaults recorded from stock 11.2607.14.0 (settings-page UIA dump
    // plus documented reset guides): Consolas / Regular / 11.
    public string FontFamily { get; set; } = "Consolas";

    public string FontStyle { get; set; } = "Regular";

    public int FontSize { get; set; } = 11;

    // Word wrap on by default (stock settings capture); consumed by D02.
    public bool WordWrap { get; set; } = true;

    // Status bar visible by default (stock view-menu capture shows it
    // checked); consumed by D01 T02 §4.
    public bool ShowStatusBar { get; set; } = true;

    // Default zoom percent for fresh tabs, owned by D01 T02 §2. Stock
    // exposes no zoom setting; 100 is a recorded default (cost: one int).
    // Consumed by D02 T01 §5.
    public int ZoomDefault { get; set; } = 100;

    // Stock "Opening files" value, normalized through OpenInRouting: the
    // settings capture selects "Open in a new tab". The default matches the
    // capture; the fresh-install default is unconfirmed and costs one
    // string to change.
    public string OpenIn { get; set; } = OpenInRouting.NewTab;

    // Stock "When Notepad starts" value, normalized through
    // WhenStartsRouting. The default matches the fresh-install capture.
    public string WhenStarts { get; set; } = WhenStartsRouting.Continue;

    // Recent files, newest first, capped by RecentFiles.MaxCount. Appended
    // on tab close only (probed s2m1); the D01 T02 §1 submenu renders it.
    // JSON DTO: the setter serves deserialization; the List shape is the
    // reviewed settings format (same treatment as SessionData.Windows).
    [SuppressMessage("Design", "CA1002", Justification = "Settings JSON DTO; List is the reviewed store shape.")]
    [SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization.")]
    public List<string> RecentFiles { get; set; } = new();

    // Pinned files for the §8 jump list, oldest first, capped by
    // RecentFiles.MaxCount. Pins live here; the D01 T02 §1 recents submenu
    // renders the toggle that mutates them.
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1002", Justification = "Settings JSON DTO; List is the reviewed store shape.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization.")]
    public List<string> PinnedFiles { get; set; } = new();

    // Jump-list feed fingerprint, owned by D01 T01 §8: the service commits
    // only while the feed differs from this hash.
    public string JumpListHash { get; set; } = string.Empty;

    public bool WhatsNewSeen { get; set; }

    // Forward-compatibility bag, owned by D01 T02 §2: unknown JSON keys
    // (later AI settings and owners' keys) round-trip untouched instead of
    // dropping on the first save after an upgrade.
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1002", Justification = "System.Text.Json extension-data shape; Dictionary is the required type.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Usage", "CA2227", Justification = "Setter serves deserialization.")]
    [System.Text.Json.Serialization.JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtensionData { get; set; }

    public static string FilePath => Path.Combine(AppDataDir.Root, "settings.json");

    public static ShellSettings Load() => SettingsStore.LoadFrom(FilePath).Settings;

    public void Save() => SettingsStore.WriteSnapshot(this);
}

// Pinned-file list behavior, owned by D01 T01 §13. Pins are oldest-first
// (pin order), uncapped (the jump-list feed caps at render), and
// case-insensitive (Windows paths). Untitled tabs have no path and never
// enter the list; their pins live in session.json only.
public static class PinnedFiles
{
    public static void NotePinned(IList<string> pinned, string? path)
    {
        if (pinned is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        foreach (string existing in pinned)
        {
            if (string.Equals(existing, path, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        pinned.Add(path);
    }

    public static void NoteUnpinned(IList<string> pinned, string? path)
    {
        if (pinned is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        for (int i = pinned.Count - 1; i >= 0; i--)
        {
            if (string.Equals(pinned[i], path, StringComparison.OrdinalIgnoreCase))
            {
                pinned.RemoveAt(i);
            }
        }
    }
}

