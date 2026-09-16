using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §16: the snapshot store over temp files. Byte-identity means the
// take holds exactly what FileSave would write for the same buffer; the
// dialog half drives take/list/restore/retention in the room.
public sealed class SnapshotStoreTests
{
    static readonly SaveSpec Utf8Crlf = new("UTF-8", false, "CRLF");

    static string NewTempFile()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "note16.txt");
    }

    static void DeleteTree(string file)
    {
        try
        {
            Directory.Delete(Path.GetDirectoryName(file)!, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup; the test result does not depend on it.
        }
    }

    [Fact]
    public void TakeStoresSaveIdenticalBytes()
    {
        string file = NewTempFile();
        try
        {
            const string text = "line one\r\nline two";
            SnapshotEntry entry = SnapshotStore.Take(file, "v1", text, Utf8Crlf);
            string reference = file + ".reference";
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(reference, text, Utf8Crlf));
            Assert.Equal(File.ReadAllBytes(reference), SnapshotStore.ReadBytes(file, entry.Id));
            Assert.Equal("v1", entry.Name);
            Assert.Equal("UTF-8", entry.EncodingName);
            Assert.False(entry.HasBom);
            Assert.Equal("CRLF", entry.LineEnding);
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void ListIsEmptyWhenNoStoreExists()
    {
        string file = NewTempFile();
        try
        {
            Assert.Empty(SnapshotStore.List(file));
            Assert.False(Directory.Exists(SnapshotStore.StoreDirFor(file)));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void DuplicateNameThrowsCaseInsensitively()
    {
        string file = NewTempFile();
        try
        {
            SnapshotStore.Take(file, "Version", "a", Utf8Crlf);
            Assert.Throws<InvalidOperationException>(() => SnapshotStore.Take(file, "VERSION", "b", Utf8Crlf));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void EmptyAndOverlongNamesThrow()
    {
        string file = NewTempFile();
        try
        {
            Assert.Throws<ArgumentException>(() => SnapshotStore.Take(file, "  ", "a", Utf8Crlf));
            Assert.Throws<ArgumentException>(() => SnapshotStore.Take(file, new string('n', 81), "a", Utf8Crlf));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void RetentionEvictsOldestPastTen()
    {
        string file = NewTempFile();
        try
        {
            for (int i = 1; i <= 11; i++)
            {
                SnapshotStore.Take(file, $"s{i:00}", $"text {i}", Utf8Crlf);
            }

            var names = SnapshotStore.List(file).Select(entry => entry.Name).ToList();
            Assert.Equal(10, names.Count);
            Assert.DoesNotContain("s01", names);
            Assert.Equal("s02", names[0]);
            Assert.Equal("s11", names[9]);
            Assert.False(File.Exists(Path.Combine(SnapshotStore.StoreDirFor(file), "snap-0001.bin")));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void CorruptManifestHealsAndTakeStillWorks()
    {
        string file = NewTempFile();
        try
        {
            SnapshotStore.Take(file, "v1", "a", Utf8Crlf);
            File.WriteAllText(Path.Combine(SnapshotStore.StoreDirFor(file), "manifest.json"), "{oops");
            Assert.Empty(SnapshotStore.List(file));
            SnapshotEntry entry = SnapshotStore.Take(file, "v2", "b", Utf8Crlf);
            Assert.Equal(2, entry.Id);
            Assert.Single(SnapshotStore.List(file));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void ReadBytesMissingIdThrows()
    {
        string file = NewTempFile();
        try
        {
            SnapshotStore.Take(file, "v1", "a", Utf8Crlf);
            Assert.Throws<FileNotFoundException>(() => SnapshotStore.ReadBytes(file, 999));
        }
        finally
        {
            DeleteTree(file);
        }
    }

    [Fact]
    public void SuggestNameFormatsUtcInvariant()
    {
        Assert.Equal("2026-09-16 02:30", SnapshotStore.SuggestName(new DateTime(2026, 9, 16, 2, 30, 0, DateTimeKind.Utc)));
    }
}
