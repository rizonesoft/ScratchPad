using Notepad.Core;
using Xunit;

namespace Unit;

// ScratchPad rename: the legacy IntelligentNotepad folder migrates once,
// on first access, and only into an empty new home. The legacy side is
// never deleted and an existing new home always wins.
public sealed class AppDataDirTests : IDisposable
{
    readonly string sandbox = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(sandbox))
        {
            Directory.Delete(sandbox, recursive: true);
        }
    }

    [Fact]
    public void MigrateCopiesLegacyFilesIncludingSubdirectories()
    {
        string legacy = Path.Combine(sandbox, "legacy");
        string current = Path.Combine(sandbox, "current");
        Directory.CreateDirectory(Path.Combine(legacy, "templates"));
        File.WriteAllText(Path.Combine(legacy, "settings.json"), "{}");
        File.WriteAllText(Path.Combine(legacy, "templates", "t.txt"), "t");
        AppDataDir.MigrateDirectory(legacy, current);
        Assert.Equal("{}", File.ReadAllText(Path.Combine(current, "settings.json")));
        Assert.Equal("t", File.ReadAllText(Path.Combine(current, "templates", "t.txt")));
    }

    [Fact]
    public void MigrateLeavesLegacyFolderInPlace()
    {
        string legacy = Path.Combine(sandbox, "legacy");
        string current = Path.Combine(sandbox, "current");
        Directory.CreateDirectory(legacy);
        File.WriteAllText(Path.Combine(legacy, "session.json"), "{}");
        AppDataDir.MigrateDirectory(legacy, current);
        Assert.True(Directory.Exists(legacy));
        Assert.True(File.Exists(Path.Combine(legacy, "session.json")));
    }

    [Fact]
    public void MigrateSkipsWhenCurrentHomeExists()
    {
        string legacy = Path.Combine(sandbox, "legacy");
        string current = Path.Combine(sandbox, "current");
        Directory.CreateDirectory(legacy);
        Directory.CreateDirectory(current);
        File.WriteAllText(Path.Combine(legacy, "settings.json"), """{"a":1}""");
        File.WriteAllText(Path.Combine(current, "settings.json"), """{"b":2}""");
        AppDataDir.MigrateDirectory(legacy, current);
        Assert.Equal("""{"b":2}""", File.ReadAllText(Path.Combine(current, "settings.json")));
    }

    [Fact]
    public void MigrateSkipsWhenLegacyHomeMissing()
    {
        string current = Path.Combine(sandbox, "current");
        AppDataDir.MigrateDirectory(Path.Combine(sandbox, "absent"), current);
        Assert.False(Directory.Exists(current));
    }

    [Fact]
    public void SecondMigrationRunIsANoOp()
    {
        string legacy = Path.Combine(sandbox, "legacy");
        string current = Path.Combine(sandbox, "current");
        Directory.CreateDirectory(legacy);
        File.WriteAllText(Path.Combine(legacy, "settings.json"), """{"a":1}""");
        AppDataDir.MigrateDirectory(legacy, current);
        File.WriteAllText(Path.Combine(current, "settings.json"), """{"b":2}""");
        AppDataDir.MigrateDirectory(legacy, current);
        Assert.Equal("""{"b":2}""", File.ReadAllText(Path.Combine(current, "settings.json")));
    }
}
