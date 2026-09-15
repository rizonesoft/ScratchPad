using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §5: atomic save, the Save As encode matrix, preserve round-trips
// over the §4 fixtures, failure mapping, new-file defaults, Save All order.
public sealed class FileSaveTests
{
    static string Fixture(params string[] parts) =>
        Path.Combine([AppContext.BaseDirectory, "Fixtures", ..parts]);

    static string NewTempPath() => Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".txt");

    [Fact]
    public void SaveWritesAtomicallyViaTempAndRename()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            var spec = new SaveSpec(FileOpen.Utf8Name, false, LineEndings.Crlf);
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, "one\r\ntwo\r\n", spec));
            Assert.Equal("one\r\ntwo\r\n", File.ReadAllText(path));
            Assert.IsType<SaveSuccess>(FileSave.SaveFile(path, "replaced\r\n", spec));
            Assert.Equal("replaced\r\n", File.ReadAllText(path));
            string[] leftovers = Directory.GetFiles(dir);
            Assert.Single(leftovers);
            Assert.Equal(path, leftovers[0]);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void FaultBeforeCommitKeepsOldBytesIntact()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            File.WriteAllText(path, "original\r\n");
            var spec = new SaveSpec(FileOpen.Utf8Name, false, LineEndings.Crlf);
            Assert.Throws<InvalidOperationException>(() => FileSave.SaveFile(path, "new\r\n", spec, faultBeforeCommit: static () => throw new InvalidOperationException("boom")));
            Assert.Equal("original\r\n", File.ReadAllText(path));
            // A true crash orphans its temp file (nothing runs to delete it);
            // the guarantee is old-or-new bytes, never a mix. The recursive
            // delete below stands in for the operator.
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    public static TheoryData<string, string> OfferedMatrix()
    {
        var data = new TheoryData<string, string>();
        foreach (string encoding in SaveDialogDefaults.OfferedEncodings)
        {
            data.Add(encoding, LineEndings.Crlf);
            data.Add(encoding, LineEndings.Lf);
            data.Add(encoding, LineEndings.Cr);
        }

        return data;
    }

    [Theory]
    [MemberData(nameof(OfferedMatrix))]
    public void SaveAsMatrixHonorsEveryOfferedCombination(string encoding, string eol)
    {
        bool bom = encoding == FileOpen.Utf8BomName;
        byte[] bytes = FileSave.Encode("Héllo\r\nwörld\rlast\n", encoding, bom, eol);
        DetectedFile detected = FileOpen.Detect(bytes);
        Assert.Equal(encoding, detected.EncodingName);
        Assert.Equal(bom, detected.HasBom);
        Assert.Equal(eol, detected.LineEnding.Dominant);
        (int crlf, int lf, int cr) = (detected.LineEnding.Crlf, detected.LineEnding.Lf, detected.LineEnding.Cr);
        Assert.Equal(3, crlf + lf + cr);
    }

    [Fact]
    public void BomFlagRoundTripsIndependentOfName()
    {
        foreach (bool bom in new[] { false, true })
        {
            byte[] bytes = FileSave.Encode("Hi\r\n", FileOpen.Utf16LeName, bom, LineEndings.Crlf);
            Assert.Equal(bom, FileOpen.Detect(bytes).HasBom);
        }
    }

    [Fact]
    public void OpenSaveRoundTripsAcrossDetectionMatrix()
    {
        string[] fixtures =
        [
            "utf8-bom.bin", "utf8-nobom-ascii.bin", "utf8-nobom-nonascii.bin",
            "utf16le-bom.bin", "utf16be-bom.bin", "utf16le-nobom.bin", "utf16be-nobom.bin",
            "ansi-1252.bin", "invalid-utf8.bin",
            "utf32le-bom.bin", "utf32be-bom.bin", "empty.bin",
        ];
        foreach (string fixture in fixtures)
        {
            byte[] original = File.ReadAllBytes(Fixture("encodings", fixture));
            DetectedFile detected = FileOpen.Detect(original);
            byte[] saved = FileSave.Encode(detected.Text, detected.EncodingName, detected.HasBom, detected.LineEnding.Dominant);
            Assert.True(original.SequenceEqual(saved), $"round-trip differs for {fixture}");
        }
    }

    [Fact]
    public void RedirectMapCoversDestinationsAndPassesThroughUnknown()
    {
        Assert.True(FileSave.RedirectsToSaveAs(new UnauthorizedAccessException()));
        Assert.True(FileSave.RedirectsToSaveAs(new IOException()));
        Assert.False(FileSave.RedirectsToSaveAs(new DirectoryNotFoundException()));
        Assert.False(FileSave.RedirectsToSaveAs(new PathTooLongException()));
        Assert.False(FileSave.RedirectsToSaveAs(new InvalidOperationException()));
    }

    // POSIX rename succeeds over open handles, so the locked-redirect
    // end-to-end is Windows-only; the mapping above covers other OSes.
    [WindowsOnlyFact]
    public void LockedSaveRedirectsToSaveAsAndKeepsBytesIntact()
    {
        string path = NewTempPath();
        try
        {
            File.WriteAllText(path, "held\r\n");
            var spec = new SaveSpec(FileOpen.Utf8Name, false, LineEndings.Crlf);
            using (var hold = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                SaveResult result = FileSave.SaveFile(path, "new\r\n", spec);
                var redirect = Assert.IsType<SaveRedirect>(result);
                Assert.False(string.IsNullOrEmpty(redirect.Detail));
            }

            Assert.Equal("held\r\n", File.ReadAllText(path));
            Assert.Empty(Directory.GetFiles(Path.GetTempPath(), ".~*.tmp"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [WindowsOnlyFact]
    public void ReadOnlyAttributeSaveRedirects()
    {
        string path = NewTempPath();
        try
        {
            File.WriteAllText(path, "ro\r\n");
            File.SetAttributes(path, FileAttributes.ReadOnly);
            var spec = new SaveSpec(FileOpen.Utf8Name, false, LineEndings.Crlf);
            try
            {
                SaveResult result = FileSave.SaveFile(path, "new\r\n", spec);
                var redirect = Assert.IsType<SaveRedirect>(result);
                Assert.False(string.IsNullOrEmpty(redirect.Detail));
            }
            finally
            {
                File.SetAttributes(path, FileAttributes.Normal);
            }

            Assert.Equal("ro\r\n", File.ReadAllText(path));
        }
        finally
        {
            File.SetAttributes(path, FileAttributes.Normal);
            File.Delete(path);
        }
    }

    [Fact]
    public void UnmappedFailureReportsOsMessage()
    {
        string path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "gone.txt");
        var spec = new SaveSpec(FileOpen.Utf8Name, false, LineEndings.Crlf);
        SaveResult result = FileSave.SaveFile(path, "x", spec);
        var failed = Assert.IsType<SaveFailed>(result);
        Assert.False(string.IsNullOrEmpty(failed.Detail));
        Assert.Equal("Notepad", SaveMessages.DialogTitle);
    }

    [Fact]
    public void NewTabDefaultsToUtf8WithoutBomAndCrlf()
    {
        Tab tab = new TabModel().NewTab();
        Assert.Equal(FileOpen.Utf8Name, tab.Encoding);
        Assert.False(tab.HasBom);
        Assert.Equal(LineEndings.Crlf, tab.LineEnding);
        Assert.Equal(FileOpen.Utf8Name, SaveDialogDefaults.DefaultEncoding);
    }

    [Fact]
    public void SaveDialogPrefillAppendsTxtToDisplayName()
    {
        Assert.Equal("ZCOMBO-w5.txt", SaveDialogDefaults.FileNameFor("ZCOMBO-w5"));
        Assert.Equal("Untitled.txt", SaveDialogDefaults.FileNameFor(string.Empty));
        Assert.Equal("Untitled.txt", SaveDialogDefaults.FileNameFor("   "));
        Assert.Equal(2, SaveDialogDefaults.FileTypeFilter.Count);
        Assert.Equal(".txt", SaveDialogDefaults.FileTypeFilter[0]);
        Assert.Equal("*", SaveDialogDefaults.FileTypeFilter[1]);
        Assert.Equal(5, SaveDialogDefaults.OfferedEncodings.Count);
        Assert.Equal(FileOpen.AnsiName, SaveDialogDefaults.OfferedEncodings[0]);
        Assert.Equal(FileOpen.Utf16LeName, SaveDialogDefaults.OfferedEncodings[1]);
        Assert.Equal(FileOpen.Utf16BeName, SaveDialogDefaults.OfferedEncodings[2]);
        Assert.Equal(FileOpen.Utf8Name, SaveDialogDefaults.OfferedEncodings[3]);
        Assert.Equal(FileOpen.Utf8BomName, SaveDialogDefaults.OfferedEncodings[4]);
    }

    [Fact]
    public void SaveAllWalksTabOrderAndContinuesPastCancel()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string pathA = Path.Combine(dir, "a.txt");
            File.WriteAllText(pathA, "A0");
            string pathD = Path.Combine(dir, "d.txt");
            var model = new TabModel();
            Tab tabA = model.OpenTab(pathA, new DetectedFile("A0", FileOpen.Utf8Name, false, new LineEndingInfo(0, 0, 0, LineEndings.Crlf)));
            Tab tabB = model.NewTab();
            Tab tabC = model.NewTab();
            Tab tabD = model.NewTab();
            tabA.NotifyEdited("A1");
            tabB.NotifyEdited("B1");
            tabD.NotifyEdited("D1");
            tabC.NotifyEdited("C1");
            tabC.MarkSaved();
            var calls = new List<string>();
            string TextOf(Tab tab)
            {
                calls.Add("text:" + (ReferenceEquals(tab, tabA) ? "A" : ReferenceEquals(tab, tabB) ? "B" : "D"));
                return ReferenceEquals(tab, tabA) ? "A1" : ReferenceEquals(tab, tabB) ? "B1" : "D1";
            }

            SaveAsChoice? SaveAs(Tab tab)
            {
                calls.Add("choice:" + (ReferenceEquals(tab, tabB) ? "B" : "D"));
                return ReferenceEquals(tab, tabB) ? null : new SaveAsChoice(pathD, FileOpen.Utf8Name, false, LineEndings.Crlf);
            }

            IReadOnlyList<SaveAllEntry> entries = FileSave.SaveAll(model, TextOf, SaveAs);
            Assert.Equal(["text:A", "text:B", "choice:B", "text:D", "choice:D"], calls);
            Assert.Equal(3, entries.Count);
            Assert.Equal(SaveAllOutcome.Saved, entries[0].Outcome);
            Assert.Equal(SaveAllOutcome.Skipped, entries[1].Outcome);
            Assert.Equal(SaveAllOutcome.Saved, entries[2].Outcome);
            Assert.Equal("A1", File.ReadAllText(pathA));
            Assert.Equal("D1", File.ReadAllText(pathD));
            Assert.False(tabA.IsDirty);
            Assert.True(tabB.IsDirty);
            Assert.False(tabD.IsDirty);
            Assert.Equal(pathD, tabD.FilePath);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void SaveAllContinuesPastFailure()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string goneDir = Path.Combine(dir, "gone");
            string pathA = Path.Combine(goneDir, "a.txt");
            string pathB = Path.Combine(dir, "b.txt");
            var model = new TabModel();
            Tab tabA = model.NewTab();
            tabA.FilePath = pathA;
            tabA.NotifyEdited("A1");
            Tab tabB = model.NewTab();
            tabB.NotifyEdited("B1");
            IReadOnlyList<SaveAllEntry> entries = FileSave.SaveAll(model, tab => ReferenceEquals(tab, tabA) ? "A1" : "B1", tab => ReferenceEquals(tab, tabB) ? new SaveAsChoice(pathB, FileOpen.Utf8Name, false, LineEndings.Crlf) : null);
            Assert.Equal(2, entries.Count);
            Assert.Equal(SaveAllOutcome.Failed, entries[0].Outcome);
            Assert.False(string.IsNullOrEmpty(entries[0].Detail));
            Assert.Equal(SaveAllOutcome.Saved, entries[1].Outcome);
            Assert.True(tabA.IsDirty);
            Assert.Equal("B1", File.ReadAllText(pathB));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    // A mid-All redirect prompts inline Save As for that tab (default,
    // mirrors single-save). Windows-only: POSIX rename ignores the lock.
    [WindowsOnlyFact]
    public void SaveAllRedirectPromptsInlineSaveAs()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string locked = Path.Combine(dir, "locked.txt");
            File.WriteAllText(locked, "L0");
            var model = new TabModel();
            Tab tabL = model.OpenTab(locked, new DetectedFile("L0", FileOpen.Utf8Name, false, new LineEndingInfo(0, 0, 0, LineEndings.Crlf)));
            tabL.NotifyEdited("L1");
            string alt = Path.Combine(dir, "alt.txt");
            using (var hold = new FileStream(locked, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                IReadOnlyList<SaveAllEntry> entries = FileSave.SaveAll(model, _ => "L1", _ => new SaveAsChoice(alt, FileOpen.Utf8Name, false, LineEndings.Crlf));
                Assert.Single(entries);
                Assert.Equal(SaveAllOutcome.Saved, entries[0].Outcome);
            }

            Assert.Equal("L1", File.ReadAllText(alt));
            Assert.Equal("L0", File.ReadAllText(locked));
            Assert.Equal(alt, tabL.FilePath);
            Assert.False(tabL.IsDirty);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
