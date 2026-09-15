namespace IntelligentNotepad;

// Print-request seam, owned by D01 T01 §8 and bound by D01 T02 §5. The /p
// and /pt flags parse in §8 (stock 11.2607.14.0 recognizes both, probed
// 2026-09-15) and exit print-then-close shaped; until §5 binds this seam
// the call is a silent no-op (declared gap: stock would print). T02 §5
// item 5 absorbs this file into PrintService.cs.
internal static class PrintSeam
{
    public static void Print(string file, string? printer)
    {
        ArgumentException.ThrowIfNullOrEmpty(file);
        _ = printer;
    }
}
