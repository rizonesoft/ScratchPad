using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §29: explicit-encoding open. The option list is pinned verbatim
// against the expanded-picker capture, forced decode bypasses detection
// (invalid sequences render U+FFFD, never throw), Auto-Detect is exactly
// the §4 path, and the forced name flows open-tab-save for §5's handoff.
public sealed class FileOpenEncodingTests
{
    static string Fixture(params string[] parts) =>
        Path.Combine([AppContext.BaseDirectory, "Fixtures", ..parts]);

    static readonly string[] FixtureFiles =
    [
        "utf8-bom.bin", "utf8-nobom-ascii.bin", "utf8-nobom-nonascii.bin",
        "utf16le-bom.bin", "utf16be-bom.bin", "utf16le-nobom.bin", "utf16be-nobom.bin",
        "ansi-1252.bin", "invalid-utf8.bin", "utf32le-bom.bin", "utf32be-bom.bin",
        "empty.bin",
    ];

    [Fact]
    public void EncodingOptionsMatchStockCaptureVerbatim()
    {
        // Capture resources/baseline/stock/notepad-open-encoding-items-*.png
        // plus the live UIA dump: Auto-Detect first, then the §5 list.
        Assert.Equal(
            ["Auto-Detect", "ANSI", "UTF-16 LE", "UTF-16 BE", "UTF-8", "UTF-8 with BOM"],
            OpenDialogDefaults.EncodingOptions);
        Assert.Equal(OpenDialogDefaults.AutoDetectName, OpenDialogDefaults.EncodingOptions[0]);
        Assert.Equal(SaveDialogDefaults.OfferedEncodings, OpenDialogDefaults.EncodingOptions.Skip(1));
    }

    [Fact]
    public void ForcedEncodingDefaultsToAutoDetect()
    {
        var options = new OpenOptions(OpenOptions.DefaultMaxBytes, "stamp");
        Assert.Null(options.ForcedEncoding);
    }

    [Fact]
    public void ForcedUtf8On1252ShowsReplacementCharacters()
    {
        byte[] bytes = File.ReadAllBytes(Fixture("encodings", "ansi-1252.bin"));
        DetectedFile detected = FileOpen.Detect(bytes);
        DetectedFile forced = FileOpen.Detect(bytes, FileOpen.Utf8Name);
        Assert.Equal(FileOpen.Utf8Name, forced.EncodingName);
        Assert.Contains("\uFFFD", forced.Text, StringComparison.Ordinal);
        Assert.NotEqual(detected.Text, forced.Text);
    }

    [Fact]
    public void ForcedUtf8OnInvalidBytesShowsExactReplacements()
    {
        byte[] bytes = File.ReadAllBytes(Fixture("encodings", "invalid-utf8.bin"));
        DetectedFile forced = FileOpen.Detect(bytes, FileOpen.Utf8Name);
        Assert.Equal("abc\uFFFDdefg\r\n", forced.Text);
    }

    [Fact]
    public void ForcedCorrectEncodingMatchesDetection()
    {
        byte[] bytes = File.ReadAllBytes(Fixture("encodings", "utf16le-bom.bin"));
        DetectedFile detected = FileOpen.Detect(bytes);
        DetectedFile forced = FileOpen.Detect(bytes, FileOpen.Utf16LeName);
        Assert.Equal(detected.Text, forced.Text);
        Assert.Equal(detected.HasBom, forced.HasBom);
        Assert.True(forced.HasBom);
    }

    [Fact]
    public void ForcedMismatchedBomDecodesAsText()
    {
        byte[] bytes = File.ReadAllBytes(Fixture("encodings", "utf8-bom.bin"));
        DetectedFile forced = FileOpen.Detect(bytes, FileOpen.AnsiName);
        Assert.Equal(FileOpen.AnsiName, forced.EncodingName);
        Assert.False(forced.HasBom);
        Assert.StartsWith("\u00EF\u00BB\u00BF", forced.Text, StringComparison.Ordinal);
    }

    [Fact]
    public void ForcedUnknownNameThrows()
    {
        byte[] bytes = File.ReadAllBytes(Fixture("encodings", "empty.bin"));
        Assert.Throws<ArgumentOutOfRangeException>(() => FileOpen.Detect(bytes, "UTF-32 LE"));
    }

    [Fact]
    public void AutoDetectEquivalenceAcrossFixtureMatrix()
    {
        foreach (string file in FixtureFiles)
        {
            byte[] bytes = File.ReadAllBytes(Fixture("encodings", file));
            Assert.Equal(FileOpen.Detect(bytes), FileOpen.Detect(bytes, null));
        }
    }

    [Fact]
    public async Task ForcedEncodingFlowsFromOpenThroughTabToSave()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "forced.txt");
            await File.WriteAllBytesAsync(path, await File.ReadAllBytesAsync(Fixture("encodings", "invalid-utf8.bin")));
            var options = new OpenOptions(OpenOptions.DefaultMaxBytes, "stamp") { ForcedEncoding = FileOpen.Utf8Name };
            OpenResult result = await FileOpen.OpenFileAsync(path, options);
            var opened = Assert.IsType<OpenSuccess>(result);
            Assert.Equal(FileOpen.Utf8Name, opened.EncodingName);
            var model = new TabModel();
            Tab tab = model.OpenTab(path, new DetectedFile(opened.Text, opened.EncodingName, opened.HasBom, opened.LineEnding));
            Assert.Equal(FileOpen.Utf8Name, tab.Encoding);
            string saved = Path.Combine(dir, "saved.txt");
            SaveResult save = FileSave.SaveFile(saved, opened.Text, new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding));
            Assert.IsType<SaveSuccess>(save);
            Assert.Equal("abc\uFFFDdefg\r\n", await File.ReadAllTextAsync(saved));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
