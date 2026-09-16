using System.Globalization;

namespace Notepad.Core;

// New-file templates, owned by D01 T01 §17. UI-free: the bodies, variable
// expansion, and the custom-template store live here; the picker dialog that
// lists them and prompts for the title is app UI.
public sealed record NoteTemplate(string Name, string Body);

public static class Templates
{
    public static IReadOnlyList<NoteTemplate> BuiltIn { get; } =
    [
        new("Blank note", string.Empty),
        new("Meeting notes", "# {title}\n{date}\n\nAttendees:\n\nNotes:\n\nAction items:\n"),
        new("Daily journal", "# {date}\n\n## Highlights\n\n"),
    ];

    // {date} is the locale short date, {title} the picker-supplied title
    // (empty means "Untitled", the tab convention). Unknown braces stay
    // literal so user text with braces survives expansion.
    public static string Expand(string body, string title, DateOnly date)
    {
        ArgumentNullException.ThrowIfNull(body);
        ArgumentNullException.ThrowIfNull(title);
        string resolved = title.Length == 0 ? TabDisplayName.Untitled : title;
        return body.Replace("{title}", resolved, StringComparison.Ordinal)
            .Replace("{date}", date.ToString("d", CultureInfo.CurrentCulture), StringComparison.Ordinal);
    }
}

// Custom templates as .txt files in a directory; the app passes
// %LocalAppData%/IntelligentNotepad/templates. Variables expand at use time,
// never at save time, so a saved custom stays a template.
public sealed class TemplateStore
{
    private readonly string directory;

    public TemplateStore(string directory)
    {
        ArgumentNullException.ThrowIfNull(directory);
        this.directory = directory;
    }

    public IReadOnlyList<NoteTemplate> ListCustom()
    {
        if (!Directory.Exists(directory))
        {
            return [];
        }

        var customs = new List<NoteTemplate>();
        foreach (string path in Directory.EnumerateFiles(directory, "*.txt"))
        {
            customs.Add(new NoteTemplate(Path.GetFileNameWithoutExtension(path), File.ReadAllText(path)));
        }

        return customs;
    }

    public void SaveCustom(string name, string body)
    {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(body);
        if (name.Length == 0)
        {
            throw new ArgumentException("Template name must not be empty.", nameof(name));
        }

        Directory.CreateDirectory(directory);
        string safe = string.Concat(name.Select(c => IsUnsafeNameChar(c) ? '_' : c));
        string temp = Path.Combine(directory, Guid.NewGuid() + ".tmp");
        File.WriteAllText(temp, body);
        File.Move(temp, Path.Combine(directory, safe + ".txt"), overwrite: true);
    }

    // Windows-only app: sanitize against the Windows invalid set even when
    // tests run on Linux, where ':' and '?' are legal, so names persist
    // identically on both hosts.
    private static bool IsUnsafeNameChar(char c) =>
        c < 0x20 || c is '<' or '>' or ':' or '"' or '/' or '\\' or '|' or '?' or '*';
}
