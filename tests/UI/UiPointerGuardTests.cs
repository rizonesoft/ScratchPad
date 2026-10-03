using Xunit;

namespace UI;

// D00 T12 §2: the real cursor moves only through UiPointer, which reads
// and sets in physical pixels. A raw move elsewhere in tests/UI lands
// up-left of its target on a scaled display (the 2026-10-03 hover miss),
// so the guard fails planted raw moves, passes the sanctioned shapes, and
// scans the live tree clean.
public sealed class UiPointerGuardTests
{
    [Theory]
    [InlineData("class Q { void M(E e) { Mouse.MoveTo(e.GetClickablePoint()); } }")]
    [InlineData("class Q { void M(System.Drawing.Point p) { Mouse.Position = p; } }")]
    [InlineData("class Q { void M() { FlaUI.Core.Input.Mouse.Position=new System.Drawing.Point(1, 2); } }")]
    [InlineData("class Q { void M() { Mouse . MoveTo (new System.Drawing.Point(1, 2)); } }")]
    [InlineData("class Q { void M() { NativeMethods.SetCursorPos(1, 2); } }")]
    [InlineData("class Q { [System.Runtime.InteropServices.DllImport(\"user32.dll\")] static extern bool SetCursorPos(int x, int y); }")]
    public void PlantedRawMoveFailsTheGuard(string snippet)
    {
        IReadOnlyList<string> hits = UiPointer.FindRawMoves(snippet, "tests/UI/Plant.cs");
        string hit = Assert.Single(hits);
        Assert.StartsWith("tests/UI/Plant.cs:1: ", hit, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("class Q { void M(E e) { UiPointer.MoveTo(e); } }")]
    [InlineData("class Q { void M() { Mouse.Down(MouseButton.Left); Mouse.Up(MouseButton.Left); Mouse.Scroll(2); } }")]
    [InlineData("class Q { bool M(System.Drawing.Point p) => Mouse.Position == p; }")]
    [InlineData("// Mouse.MoveTo(e.GetClickablePoint()) in a comment is not a move")]
    public void SanctionedShapesPassTheGuard(string snippet)
    {
        Assert.Empty(UiPointer.FindRawMoves(snippet, "tests/UI/Clean.cs"));
    }

    [Fact]
    public void HitNamesItsLine()
    {
        const string source = "class Q\n{\n    void M(P p) { Mouse.Position = p; }\n}\n";
        Assert.Equal(["tests/UI/Plant.cs:3: void M(P p) { Mouse.Position = p; }"], UiPointer.FindRawMoves(source, "tests/UI/Plant.cs"));
    }

    [Fact]
    public void LiveTreeScansClean()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null && !Directory.Exists(Path.Combine(dir, "tests", "UI")))
        {
            dir = Path.GetDirectoryName(dir);
        }

        Assert.NotNull(dir);
        string root = Path.Combine(dir!, "tests", "UI");
        var failures = new List<string>();
        int scanned = 0;
        foreach (string file in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
        {
            string rel = Path.GetRelativePath(dir!, file).Replace(Path.DirectorySeparatorChar, '/');
            // The helper itself and this file's planted fixtures are the
            // two sanctioned sites.
            if (rel is "tests/UI/UiPointer.cs" or "tests/UI/UiPointerGuardTests.cs"
                || rel.Contains("/obj/", StringComparison.Ordinal) || rel.Contains("/bin/", StringComparison.Ordinal))
            {
                continue;
            }

            scanned++;
            failures.AddRange(UiPointer.FindRawMoves(File.ReadAllText(file), rel));
        }

        Assert.True(scanned > 50, $"scanned only {scanned} files under {root}");
        Assert.Empty(failures);
    }
}
