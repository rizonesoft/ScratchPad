using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §8: association claim plans. The registry executor lives in the
// app (Windows-only) and is driven by the UI suite on a scratch extension;
// these pin the backup, restore, and foreign-claim rules as data.
public sealed class FileAssociationTests
{
    [Fact]
    public void ClaimedExtensionsMatchStockManifest()
    {
        Assert.Equal(
            [".txt", ".log", ".ini", ".inf", ".ps1", ".psd1", ".psm1", ".scp", ".wtx"],
            FileAssociation.ClaimedExtensions);
    }

    [Fact]
    public void OpenCommandQuotesExeAndPercentOne()
    {
        Assert.Equal(
            "\"C:\\app\\IN.exe\" \"%1\"",
            FileAssociation.OpenCommand("C:\\app\\IN.exe"));
    }

    [Fact]
    public void BackupPlansRecordPriorOrItsAbsence()
    {
        Assert.Equal(
            [
                new RegistrySetValue(FileAssociation.BackupKey(".x8"), "HadPrior", "1"),
                new RegistrySetValue(FileAssociation.BackupKey(".x8"), "PriorDefault", "txtfile"),
            ],
            FileAssociation.PlanBackup(".x8", "txtfile"));
        Assert.Equal(
            [
                new RegistrySetValue(FileAssociation.BackupKey(".x8"), "HadPrior", "0"),
                new RegistrySetValue(FileAssociation.BackupKey(".x8"), "PriorDefault", string.Empty),
            ],
            FileAssociation.PlanBackup(".x8", null));
    }

    [Fact]
    public void ReleaseRestoresPriorWhenClaimIsOurs()
    {
        (IReadOnlyList<RegistrySetValue> sets, IReadOnlyList<RegistryDeleteValue> deletes) =
            FileAssociation.PlanRelease(".x8", FileAssociation.ProgId, hadPrior: true, priorDefault: "txtfile");
        Assert.Equal([new RegistrySetValue(FileAssociation.ExtensionKey(".x8"), string.Empty, "txtfile")], sets);
        Assert.Contains(deletes, d => d.ValueName == "HadPrior");
    }

    [Fact]
    public void ReleaseDeletesDefaultWhenNoPriorExisted()
    {
        (IReadOnlyList<RegistrySetValue> sets, IReadOnlyList<RegistryDeleteValue> deletes) =
            FileAssociation.PlanRelease(".x8", FileAssociation.ProgId, hadPrior: false, priorDefault: null);
        Assert.Empty(sets);
        Assert.Contains(deletes, d => d.KeyPath == FileAssociation.ExtensionKey(".x8") && d.ValueName.Length == 0);
    }

    [Fact]
    public void ReleaseLeavesForeignClaimsAlone()
    {
        (IReadOnlyList<RegistrySetValue> sets, IReadOnlyList<RegistryDeleteValue> deletes) =
            FileAssociation.PlanRelease(".x8", "OtherApp.Doc", hadPrior: true, priorDefault: "txtfile");
        Assert.Empty(sets);
        Assert.DoesNotContain(deletes, d => d.KeyPath == FileAssociation.ExtensionKey(".x8"));
        Assert.Contains(deletes, d => d.ValueName == "HadPrior");
    }

    [Fact]
    public void UnregisterTreesCoverProgIdOpenWithAndBackup()
    {
        Assert.Equal(
            [
                new RegistryDeleteKey(@"Software\Classes\" + FileAssociation.ProgId),
                new RegistryDeleteKey(@"Software\Classes\Applications\IN.exe"),
                new RegistryDeleteKey(FileAssociation.BackupRoot),
            ],
            FileAssociation.PlanUnregisterTrees("IN.exe"));
    }
}
