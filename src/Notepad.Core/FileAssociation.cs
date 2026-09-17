namespace Notepad.Core;

// File-association claim as plannable data, owned by D01 T01 §8. Stock
// 11.2607.14.0 claims .txt .log .ini .inf .ps1 .psd1 .psm1 .scp .wtx
// (AppxManifest FileTypeAssociation, probed 2026-09-15); we claim the same
// nine through one ProgId plus an Open-With entry, all under HKCU so no
// elevation is needed. Everything here is pure data: the app-side executor
// reads current state and applies the plans, which keeps the backup,
// restore, and foreign-claim rules unit-pinned on every OS. Two rules are
// load-bearing: register backs up each prior default before claiming, and
// unregister restores the backup only when the current claim is still ours
// (a foreign claim means the user moved on, and their choice wins).
public sealed record RegistrySetValue(string KeyPath, string ValueName, string Value);

public sealed record RegistryDeleteValue(string KeyPath, string ValueName);

public sealed record RegistryDeleteKey(string KeyPath);

public static class FileAssociation
{
    public const string ProgId = "ScratchPad.Document";

    public const string FriendlyTypeName = "ScratchPad Document";

    public const string BackupRoot = @"Software\ScratchPad\AssocBackup";

    public static readonly IReadOnlyList<string> ClaimedExtensions =
        [".txt", ".log", ".ini", ".inf", ".ps1", ".psd1", ".psm1", ".scp", ".wtx"];

    // The double-click contract: exactly what Explorer runs for a defaulted
    // extension. Quoted exe plus quoted %1 (the shell substitutes the path).
    public static string OpenCommand(string exePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        return "\"" + exePath + "\" \"%1\"";
    }

    public static string ExtensionKey(string extension) => @"Software\Classes\" + extension;

    public static string BackupKey(string extension) => BackupRoot + "\\" + extension;

    // Backup writes for one extension. priorDefault null means the key had
    // no default value; the HadPrior flag tells restore apart from delete.
    public static IReadOnlyList<RegistrySetValue> PlanBackup(string extension, string? priorDefault) =>
    [
        new RegistrySetValue(BackupKey(extension), "HadPrior", priorDefault is null ? "0" : "1"),
        new RegistrySetValue(BackupKey(extension), "PriorDefault", priorDefault ?? string.Empty),
    ];

    public static RegistrySetValue PlanClaim(string extension, string progId = ProgId) =>
        new(ExtensionKey(extension), string.Empty, progId);

    public static IReadOnlyList<RegistrySetValue> PlanProgId(string exePath, string progId = ProgId)
    {
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        string root = @"Software\Classes\" + progId;
        return
        [
            new RegistrySetValue(root, string.Empty, FriendlyTypeName),
            new RegistrySetValue(root + @"\shell\open\command", string.Empty, OpenCommand(exePath)),
            new RegistrySetValue(root + @"\DefaultIcon", string.Empty, "\"" + exePath + "\",0"),
        ];
    }

    public static IReadOnlyList<RegistrySetValue> PlanOpenWith(string exeFileName, IEnumerable<string> extensions)
    {
        ArgumentException.ThrowIfNullOrEmpty(exeFileName);
        ArgumentNullException.ThrowIfNull(extensions);
        string root = @"Software\Classes\Applications\" + exeFileName;
        var writes = new List<RegistrySetValue>();
        foreach (string extension in extensions)
        {
            writes.Add(new RegistrySetValue(root + @"\SupportedTypes", extension, string.Empty));
        }

        return writes;
    }

    public static RegistryDeleteValue PlanOpenWithRemoval(string exeFileName, string extension) =>
        new(@"Software\Classes\Applications\" + exeFileName + @"\SupportedTypes", extension);

    // Release plan for one extension given the live current default and the
    // filed backup. Ours plus a prior backup restores it; ours with no
    // backup deletes the default value; anything foreign is left alone and
    // only the stale backup goes.
    public static (IReadOnlyList<RegistrySetValue> Sets, IReadOnlyList<RegistryDeleteValue> Deletes) PlanRelease(
        string extension, string? currentDefault, bool hadPrior, string? priorDefault, string progId = ProgId)
    {
        var sets = new List<RegistrySetValue>();
        var deletes = new List<RegistryDeleteValue> { new(BackupKey(extension), "HadPrior"), new(BackupKey(extension), "PriorDefault") };
        if (!string.Equals(currentDefault, progId, StringComparison.Ordinal))
        {
            return (sets, deletes);
        }

        if (hadPrior && priorDefault is not null)
        {
            sets.Add(new RegistrySetValue(ExtensionKey(extension), string.Empty, priorDefault));
        }
        else
        {
            deletes.Add(new RegistryDeleteValue(ExtensionKey(extension), string.Empty));
        }

        return (sets, deletes);
    }

    // Tree removal. progId is scoped so the scratch-extension drive can
    // prove full removal against a test ProgId without touching the real
    // claim; exeFileName always names the real exe (Open-With display).
    // Callers targeting a subset delete only their own extents and leave
    // the shared trees; the full unregister (extensions null) removes all.
    public static IReadOnlyList<RegistryDeleteKey> PlanUnregisterTrees(string exeFileName, string progId = ProgId) =>
    [
        new RegistryDeleteKey(@"Software\Classes\" + progId),
        new RegistryDeleteKey(@"Software\Classes\Applications\" + exeFileName),
        new RegistryDeleteKey(BackupRoot),
    ];
}
