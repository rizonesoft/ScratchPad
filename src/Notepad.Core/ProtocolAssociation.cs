namespace Notepad.Core;

// Custom protocol registration plans, owned by D01 T01 §26. Mirrors the
// FileAssociation shape: pure plans in Core, executed against HKCU by the
// app registrar, driven through verbs. The scheme carries absolute paths
// as `intelligent-notepad://<url-encoded absolute path>`; the launch
// parser maps well-formed links to files and ignores the rest.
public static class ProtocolAssociation
{
    public const string Scheme = "intelligent-notepad";

    public const string Description = "URL:ScratchPad Protocol";

    public static string SchemeKey => @"Software\Classes\" + Scheme;

    public static string BackupKey => FileAssociation.BackupRoot + @"\protocol-" + Scheme;

    // The click contract: quoted exe plus quoted %1 (the shell substitutes
    // the link URL), the same shape as the §8 double-click contract.
    public static string OpenCommand(string exePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        return "\"" + exePath + "\" \"%1\"";
    }

    // Maps a raw argv entry to the carried path, or null when it is not a
    // well-formed link of our scheme. Parsed by hand: strip the prefix,
    // unescape, require a rooted path. Malformed links (empty, relative,
    // bad escapes) and other schemes return null; the caller ignores them.
    public static string? TryParseLink(string arg)
    {
        ArgumentNullException.ThrowIfNull(arg);
        string prefix = Scheme + "://";
        if (!arg.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        string encoded = arg[prefix.Length..];
        if (encoded.Length == 0)
        {
            return null;
        }

        string path;
        try
        {
            path = Uri.UnescapeDataString(encoded);
        }
        catch (Exception ex) when (ex is ArgumentException or FormatException)
        {
            return null;
        }

        // The shell appends a trailing slash to the substituted URL
        // (observed 2026-09-16: ...shellprobe26.txt/); without the trim
        // the path fails File.Exists and misroutes to the missing offer.
        path = path.TrimEnd('/', '\\');
        return WindowsPath.IsRooted(path) ? path : null;
    }

    public static IReadOnlyList<RegistrySetValue> PlanBackup(string? priorDefault, string? priorCommand) =>
    [
        new RegistrySetValue(BackupKey, "HadPrior", priorCommand is null ? "0" : "1"),
        new RegistrySetValue(BackupKey, "PriorDefault", priorDefault ?? string.Empty),
        new RegistrySetValue(BackupKey, "PriorCommand", priorCommand ?? string.Empty),
    ];

    public static IReadOnlyList<RegistrySetValue> PlanRegister(string exePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        return
        [
            new RegistrySetValue(SchemeKey, string.Empty, Description),
            // The URL Protocol marker is presence, conventionally empty.
            new RegistrySetValue(SchemeKey, "URL Protocol", string.Empty),
            new RegistrySetValue(SchemeKey + @"\shell\open\command", string.Empty, OpenCommand(exePath)),
        ];
    }

    // Release plan given the live current default and the filed backup.
    // Ours (default reads our description) plus a prior backup restores
    // it; ours with no backup deletes the tree; anything foreign is left
    // alone and only the stale backup goes.
    public static (IReadOnlyList<RegistrySetValue> Sets, IReadOnlyList<RegistryDeleteValue> Deletes, bool DeleteTree) PlanRelease(
        string? currentDefault, bool hadPrior, string? priorDefault, string? priorCommand)
    {
        var sets = new List<RegistrySetValue>();
        var deletes = new List<RegistryDeleteValue>
        {
            new(BackupKey, "HadPrior"), new(BackupKey, "PriorDefault"), new(BackupKey, "PriorCommand"),
        };
        if (!string.Equals(currentDefault, Description, StringComparison.Ordinal))
        {
            return (sets, deletes, false);
        }

        if (hadPrior && priorDefault is not null && priorCommand is not null)
        {
            sets.Add(new RegistrySetValue(SchemeKey, string.Empty, priorDefault));
            sets.Add(new RegistrySetValue(SchemeKey + @"\shell\open\command", string.Empty, priorCommand));
            return (sets, deletes, false);
        }

        return (sets, deletes, true);
    }
}
