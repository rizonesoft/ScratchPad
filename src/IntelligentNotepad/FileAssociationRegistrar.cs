using System.Runtime.InteropServices;
using Microsoft.Win32;
using Notepad.Core;

namespace IntelligentNotepad;

// Executes FileAssociation plans against HKCU, owned by D01 T01 §8. All
// keys live under HKEY_CURRENT_USER (per-user, no elevation, fully
// reversible): the extension defaults, one ProgId tree, the Open-With entry,
// and the prior-default backups. Register reads each live default before
// claiming so unregister can restore it; when the live claim is foreign,
// unregister leaves it alone (FileAssociation.PlanRelease). Explorer is
// notified after each run so Default Apps and Open With refresh.
internal static class FileAssociationRegistrar
{
    public static void Register(string exePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(exePath);
        foreach (string ext in FileAssociation.ClaimedExtensions)
        {
            string? prior = ReadDefault(FileAssociation.ExtensionKey(ext));
            foreach (RegistrySetValue write in FileAssociation.PlanBackup(ext, prior))
            {
                WriteString(write.KeyPath, write.ValueName, write.Value);
            }

            RegistrySetValue claim = FileAssociation.PlanClaim(ext);
            WriteString(claim.KeyPath, claim.ValueName, claim.Value);
        }

        foreach (RegistrySetValue write in FileAssociation.PlanProgId(exePath))
        {
            WriteString(write.KeyPath, write.ValueName, write.Value);
        }

        foreach (RegistrySetValue write in FileAssociation.PlanOpenWith(Path.GetFileName(exePath), FileAssociation.ClaimedExtensions))
        {
            WriteString(write.KeyPath, write.ValueName, write.Value);
        }

        NotifyShell();
    }

    public static void Unregister(string exeFileName)
    {
        ArgumentException.ThrowIfNullOrEmpty(exeFileName);
        foreach (string ext in FileAssociation.ClaimedExtensions)
        {
            string? current = ReadDefault(FileAssociation.ExtensionKey(ext));
            string backupKey = FileAssociation.BackupKey(ext);
            bool hadPrior = ReadString(backupKey, "HadPrior") == "1";
            string? prior = ReadString(backupKey, "PriorDefault");
            (IReadOnlyList<RegistrySetValue> sets, IReadOnlyList<RegistryDeleteValue> deletes) =
                FileAssociation.PlanRelease(ext, current, hadPrior, prior);
            foreach (RegistrySetValue write in sets)
            {
                WriteString(write.KeyPath, write.ValueName, write.Value);
            }

            foreach (RegistryDeleteValue delete in deletes)
            {
                DeleteValue(delete.KeyPath, delete.ValueName);
            }

            DeleteTree(backupKey);
        }

        foreach (RegistryDeleteKey tree in FileAssociation.PlanUnregisterTrees(exeFileName))
        {
            DeleteTree(tree.KeyPath);
        }

        NotifyShell();
    }

    public static string? CurrentClaim(string extension) => ReadDefault(FileAssociation.ExtensionKey(extension));

    static string? ReadDefault(string keyPath) => ReadString(keyPath, string.Empty);

    static string? ReadString(string keyPath, string valueName)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
        return key?.GetValue(valueName) as string;
    }

    static void WriteString(string keyPath, string valueName, string value)
    {
        using RegistryKey key = Registry.CurrentUser.CreateSubKey(keyPath);
        key.SetValue(valueName, value, RegistryValueKind.String);
    }

    static void DeleteValue(string keyPath, string valueName)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath, writable: true);
        try
        {
            key?.DeleteValue(valueName, throwOnMissingValue: false);
        }
        catch (ArgumentException)
        {
            // No such value (or no such key): already absent, which is the goal.
        }
    }

    static void DeleteTree(string keyPath)
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(keyPath, throwOnMissingSubKey: false);
        }
        catch (ArgumentException)
        {
            // Malformed handle state under concurrent edits: the subtree is
            // gone or going; unregister stays idempotent either way.
        }
    }

    static void NotifyShell() => SHChangeNotify(0x08000000, 0x1000, IntPtr.Zero, IntPtr.Zero);

    [DllImport("shell32.dll", ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
