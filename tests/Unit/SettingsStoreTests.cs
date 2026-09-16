using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T02 §2: the single-writer settings store. Every test drives an
// isolated store over a temp path; the production file is never touched.
public sealed class SettingsStoreTests
{
    [Fact]
    public void FreshProfileMatchesRecordedDefaults()
    {
        string dir = NewTempDir();
        try
        {
            var store = new SettingsStore(Path.Combine(dir, "settings.json"));
            Assert.False(store.WasResetFromCorrupt);
            Assert.Equal(1, store.Current.Version);
            Assert.Equal("Consolas", store.Current.FontFamily);
            Assert.Equal("Regular", store.Current.FontStyle);
            Assert.Equal(11, store.Current.FontSize);
            Assert.True(store.Current.WordWrap);
            Assert.True(store.Current.ShowStatusBar);
            Assert.Equal(100, store.Current.ZoomDefault);
            Assert.Equal("system", store.Current.Theme);
            Assert.Equal("new-tab", store.Current.OpenIn);
            Assert.Equal("continue", store.Current.WhenStarts);
            Assert.Empty(store.Current.RecentFiles);
            Assert.Empty(store.Current.PinnedFiles);
            Assert.False(File.Exists(Path.Combine(dir, "settings.json")));
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void UpdatePersistsAtomicallyAndNotifiesReaders()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            var store = new SettingsStore(path);
            int first = 0;
            int second = 0;
            store.Changed += (_, _) => first++;
            store.Changed += (_, _) => second++;
            store.Update(current => current.Theme = "dark");
            Assert.Equal(1, first);
            Assert.Equal(1, second);
            Assert.Equal("dark", store.Current.Theme);
            Assert.Equal(1, store.Current.Version);
            Assert.False(File.Exists(path + ".tmp"));
            var reopened = new SettingsStore(path);
            Assert.Equal("dark", reopened.Current.Theme);
            Assert.False(reopened.WasResetFromCorrupt);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void UpdateMergesOutOfBandFileChanges()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            var store = new SettingsStore(path);
            store.Update(current => current.Theme = "dark");
            File.WriteAllText(path, """{"Version":1,"Theme":"dark","WordWrap":false}""");
            store.Update(current => current.FontSize = 14);
            Assert.False(store.Current.WordWrap);
            Assert.Equal(14, store.Current.FontSize);
            Assert.Equal("dark", store.Current.Theme);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void UpdateFromInsideChangedThrows()
    {
        string dir = NewTempDir();
        try
        {
            var store = new SettingsStore(Path.Combine(dir, "settings.json"));
            store.Changed += (_, _) => store.Update(current => current.Theme = "light");
            Assert.Throws<InvalidOperationException>(() => store.Update(current => current.Theme = "dark"));
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void CorruptFileResetsToDefaultsWithNotice()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            File.WriteAllText(path, "{not json!!!");
            var store = new SettingsStore(path);
            Assert.True(store.WasResetFromCorrupt);
            Assert.Equal("Consolas", store.Current.FontFamily);
            Assert.True(store.Current.WordWrap);
            Assert.Equal("system", store.Current.Theme);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void NullDocumentResetsToDefaultsWithNotice()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            File.WriteAllText(path, "null");
            var store = new SettingsStore(path);
            Assert.True(store.WasResetFromCorrupt);
            Assert.Equal(11, store.Current.FontSize);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void UnversionedFileMigratesKeysForward()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            File.WriteAllText(path, """{"Theme":"dark","RecentFiles":["a.txt"],"WordWrap":false}""");
            var store = new SettingsStore(path);
            Assert.False(store.WasResetFromCorrupt);
            Assert.Equal(1, store.Current.Version);
            Assert.Equal("dark", store.Current.Theme);
            Assert.Equal(["a.txt"], store.Current.RecentFiles);
            Assert.False(store.Current.WordWrap);
            Assert.Equal("Consolas", store.Current.FontFamily);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void FutureVersionResetsToDefaultsWithNotice()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            File.WriteAllText(path, """{"Version":99,"Theme":"dark"}""");
            var store = new SettingsStore(path);
            Assert.True(store.WasResetFromCorrupt);
            Assert.Equal("system", store.Current.Theme);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void UnknownKeysRoundTripUntouched()
    {
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            File.WriteAllText(path, """{"Theme":"dark","ai.copilot":{"on":true}}""");
            var store = new SettingsStore(path);
            Assert.False(store.WasResetFromCorrupt);
            store.Update(current => current.Theme = "light");
            string roundTripped = File.ReadAllText(path);
            Assert.Contains("ai.copilot", roundTripped, StringComparison.Ordinal);
            Assert.Contains("light", roundTripped, StringComparison.Ordinal);
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    [Fact]
    public void WriteSnapshotRoundTripsAtomically()
    {
        // The single write implementation every persist flows through
        // (ShellSettings.Save delegates to it; production mutates through
        // Update): atomic temp-plus-move with no litter left behind.
        string dir = NewTempDir();
        try
        {
            string path = Path.Combine(dir, "settings.json");
            SettingsStore.WriteSnapshot(new ShellSettings { Theme = "dark" }, path);
            var store = new SettingsStore(path);
            Assert.Equal("dark", store.Current.Theme);
            Assert.False(File.Exists(path + ".tmp"));
        }
        finally
        {
            DeleteDir(dir);
        }
    }

    static string NewTempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void DeleteDir(string dir)
    {
        try
        {
            Directory.Delete(dir, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }
}
