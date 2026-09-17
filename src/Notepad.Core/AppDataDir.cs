namespace Notepad.Core;

// Application-data home, owned by the ScratchPad rename. Every store
// (settings, session, templates, launch-drops) lives under Root; the
// legacy IntelligentNotepad folder migrates once, on first access, and
// only when the new home has nothing of its own. Lazy and thread-safe,
// so app, tests, and tools all migrate through the same path without a
// startup call. Migration is best-effort per file: a failed copy never
// blocks startup (that store simply starts fresh), and the legacy folder
// is left in place, never deleted, so nothing is ever lost to the move.
public static class AppDataDir
{
    public const string FolderName = "ScratchPad";

    const string LegacyFolderName = "IntelligentNotepad";

    static readonly Lazy<string> RootValue = new(() =>
    {
        string baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string current = Path.Combine(baseDir, FolderName);
        MigrateDirectory(Path.Combine(baseDir, LegacyFolderName), current);
        return current;
    });

    public static string Root => RootValue.Value;

    // Public for the migration fixtures; production calls flow through Root.
    public static void MigrateDirectory(string legacy, string current)
    {
        if (Directory.Exists(current) || !Directory.Exists(legacy))
        {
            return;
        }

        Directory.CreateDirectory(current);
        foreach (string file in Directory.EnumerateFiles(legacy, "*", SearchOption.AllDirectories))
        {
            try
            {
                string relative = Path.GetRelativePath(legacy, file);
                string target = Path.Combine(current, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                File.Copy(file, target);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Best-effort: one unreadable legacy file must not block
                // startup or lose the rest of the migration.
            }
        }
    }
}
