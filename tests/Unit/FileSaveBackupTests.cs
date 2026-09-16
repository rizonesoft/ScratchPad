using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §20: every save keeps the pre-save bytes in a timestamped sibling
// first, capped at five with oldest-first rotation.
public sealed class FileSaveBackupTests
{
    static SaveSpec Utf8() => new(FileOpen.Utf8Name, false, LineEndings.Crlf);

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    [Fact]
    public void SecondSaveKeepsPreSaveBytesInSibling()
    {
        string dir = NewTempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, "one\r\n", Utf8()));
            Assert.Empty(FileSave.BackupSiblings(path));
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, "two\r\n", Utf8()));
            string sibling = Assert.Single(FileSave.BackupSiblings(path));
            Assert.Equal("one\r\n", File.ReadAllText(sibling));
            Assert.Equal("two\r\n", File.ReadAllText(path));
            Assert.Matches(@"note\.txt\.\d{8}-\d{9}(-\d+)?\.bak", Path.GetFileName(sibling));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void RetentionRotatesPastFive()
    {
        string dir = NewTempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            for (int i = 0; i < 7; i++)
            {
                Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, $"v{i}\r\n", Utf8()));
            }

            IReadOnlyList<string> siblings = FileSave.BackupSiblings(path);
            Assert.Equal(FileSave.MaxBackups, siblings.Count);
            Assert.DoesNotContain(siblings, s => File.ReadAllText(s) == "v0\r\n");
            Assert.Contains(siblings, s => File.ReadAllText(s) == "v5\r\n");
            Assert.Equal("v6\r\n", File.ReadAllText(path));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void ForeignBakFilesAreLeftAlone()
    {
        string dir = NewTempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            string foreign = Path.Combine(dir, "note.txt.old.bak");
            File.WriteAllText(foreign, "mine");
            for (int i = 0; i < 7; i++)
            {
                Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, $"v{i}\r\n", Utf8()));
            }

            Assert.Equal("mine", File.ReadAllText(foreign));
            Assert.Equal(FileSave.MaxBackups, FileSave.BackupSiblings(path).Count);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void FaultBeforeCommitLeavesSiblingAndOriginalIntact()
    {
        string dir = NewTempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, "before\r\n", Utf8()));
            Assert.Throws<InvalidOperationException>(() => FileSave.SaveFile(
                path, "after\r\n", Utf8(), () => throw new InvalidOperationException("boom")));
            Assert.Equal("before\r\n", File.ReadAllText(path));
            string sibling = Assert.Single(FileSave.BackupSiblings(path));
            Assert.Equal("before\r\n", File.ReadAllText(sibling));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void SaveBytesBacksUpToo()
    {
        string dir = NewTempDir();
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.bin");
            Assert.IsType<SaveSuccess>(FileSave.SaveBytes(path, [0x01]));
            Assert.Empty(FileSave.BackupSiblings(path));
            Assert.IsType<SaveSuccess>(FileSave.SaveBytes(path, [0x02]));
            string sibling = Assert.Single(FileSave.BackupSiblings(path));
            Assert.Equal([0x01], File.ReadAllBytes(sibling));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
