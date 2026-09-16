using System;

namespace Notepad.Core;

// Status-bar math, owned by D01 T02 §4. Pure functions over explicit
// inputs; the StatusBar control feeds them from the active tab's box.
// Every rule below is probed against stock 11.2607.14.0 (see the §4
// review) unless marked as a recorded default with its cost.
public static class StatusSegments
{
    // Caret position, 1-based. Breaks are \r\n (one), \r, or \n; a tab
    // counts one column (probed: right-arrow across "a\tb" reads columns
    // 1, 2, 3, 4). Out-of-range carets clamp (defensive; the box keeps
    // SelectionStart in range, tests may not).
    public static (int Line, int Column) LineColumn(string text, int caretOffset)
    {
        ArgumentNullException.ThrowIfNull(text);
        int offset = Math.Clamp(caretOffset, 0, text.Length);
        int line = 1;
        int column = 1;
        for (int i = 0; i < offset; i++)
        {
            char c = text[i];
            if (c == '\r')
            {
                line++;
                column = 1;
                if (i + 1 < text.Length && text[i + 1] == '\n')
                {
                    i++;
                }
            }
            else if (c == '\n')
            {
                line++;
                column = 1;
            }
            else
            {
                column++;
            }
        }

        return (line, column);
    }

    // Document character count. Each line break counts exactly one
    // (probed: "a"+Enter reads 2, "a\tb\r\ncde\r\n" reads 8, "aa\rbb\r"
    // reads 6). Default: astral-plane scalars count per UTF-16 code unit
    // (unprobed; cost one probe plus one branch).
    public static int CountCharacters(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        int count = 0;
        for (int i = 0; i < text.Length; i++)
        {
            count++;
            if (text[i] == '\r' && i + 1 < text.Length && text[i + 1] == '\n')
            {
                i++;
            }
        }

        return count;
    }

    // No-selection total. Singular only at exactly one (probed: "0
    // characters", "1 character", "2 characters").
    public static string TotalText(int total) => total switch
    {
        0 => "0 characters",
        1 => "1 character",
        _ => $"{total} characters",
    };

    // Selection count over the same engine as the total (probed:
    // "8 of 8 characters", "4 of 4 characters", "1 of 4 characters":
    // plural even for a single selected char). Default: a partial
    // selection spanning a break counts it as one, like the total
    // (unprobed; cost one probe plus one branch).
    public static string SelectionText(string selectedText, int total) =>
        $"{CountCharacters(selectedText)} of {total} characters";

    // Line-ending display (probed). The UIA name carries a leading
    // space stock's visual text lacks; see UiaEolName.
    public static string EolDisplay(string lineEnding) => lineEnding switch
    {
        LineEndings.Crlf => "Windows (CRLF)",
        LineEndings.Lf => "Unix (LF)",
        LineEndings.Cr => "Macintosh (CR)",
        _ => throw new ArgumentOutOfRangeException(nameof(lineEnding), lineEnding, "Unknown line ending."),
    };

    public static string UiaEolName(string lineEnding) => " " + EolDisplay(lineEnding);

    // Encoding display is the detection name verbatim (probed: ANSI,
    // UTF-16 LE, UTF-16 BE, UTF-8, UTF-8 with BOM). Unknown names throw:
    // a new encoding ships only with its parity proof. The UIA name
    // carries a leading space stock's visual text lacks.
    public static string EncodingDisplay(string encodingName)
    {
        if (encodingName != FileOpen.AnsiName
            && encodingName != FileOpen.Utf16LeName
            && encodingName != FileOpen.Utf16BeName
            && encodingName != FileOpen.Utf8Name
            && encodingName != FileOpen.Utf8BomName)
        {
            throw new ArgumentOutOfRangeException(nameof(encodingName), encodingName, "Unknown encoding.");
        }

        return encodingName;
    }

    public static string UiaEncodingName(string encodingName) => " " + EncodingDisplay(encodingName);

    public static string ZoomText(int percent) => $"{percent}%";

    // The zoom UIA name is the bare word even though the visual shows
    // the percent (probed: name "Zoom" beside visual "100%").
    public static string UiaZoomName(int percent)
    {
        _ = percent;
        return "Zoom";
    }

    // Mode segment. Plain text is static; Markdown files show the view
    // switch, which ships disabled here and enables with D02 T04 §3.
    // Default: .md only (the probe covered .md and .txt; cost one
    // branch per further Markdown extension).
    public static bool IsMarkdownFile(string? path) =>
        path is not null && path.EndsWith(".md", StringComparison.OrdinalIgnoreCase);

    public static string ModeText(bool isMarkdown) => isMarkdown ? "Formatted" : "Plain text";

    // Visual line/column text ("Ln 1, Col 1"). The UIA name carries a
    // newline ("Line 1,\nColumn 1", stock verbatim); see UiaLineColumnName.
    public static string LineColumnText(int line, int column) => $"Ln {line}, Col {column}";

    public static string UiaLineColumnName(int line, int column) => $"Line {line},\nColumn {column}";
}

// One rendered status frame, computed neutrally so fixtures pin it.
public sealed record StatusView(
    string LineColumn,
    string LineColumnName,
    string Count,
    string Mode,
    bool ModeIsButton,
    string Zoom,
    string ZoomName,
    string Eol,
    string EolName,
    string Encoding,
    string EncodingName)
{
    public static StatusView Compute(
        string text,
        int caretOffset,
        int selectionStart,
        int selectionLength,
        string encoding,
        string lineEnding,
        int zoomPercent,
        bool isMarkdown)
    {
        ArgumentNullException.ThrowIfNull(text);
        (int line, int column) = StatusSegments.LineColumn(text, caretOffset);
        int total = StatusSegments.CountCharacters(text);
        int start = Math.Clamp(selectionStart, 0, text.Length);
        int length = Math.Clamp(selectionLength, 0, text.Length - start);
        string count = length == 0
            ? StatusSegments.TotalText(total)
            : StatusSegments.SelectionText(text.Substring(start, length), total);
        return new StatusView(
            StatusSegments.LineColumnText(line, column),
            StatusSegments.UiaLineColumnName(line, column),
            count,
            StatusSegments.ModeText(isMarkdown),
            isMarkdown,
            StatusSegments.ZoomText(zoomPercent),
            StatusSegments.UiaZoomName(zoomPercent),
            StatusSegments.EolDisplay(lineEnding),
            StatusSegments.UiaEolName(lineEnding),
            StatusSegments.EncodingDisplay(encoding),
            StatusSegments.UiaEncodingName(encoding));
    }

    // Zero-tab default (stock has no zero-tab state per D01 T01 §27, so
    // there is nothing to match; cost: one branch if stock ever grows one).
    public static StatusView Empty(int zoomPercent) => new(
        StatusSegments.LineColumnText(1, 1),
        StatusSegments.UiaLineColumnName(1, 1),
        StatusSegments.TotalText(0),
        StatusSegments.ModeText(false),
        false,
        StatusSegments.ZoomText(zoomPercent),
        StatusSegments.UiaZoomName(zoomPercent),
        StatusSegments.EolDisplay(LineEndings.Crlf),
        StatusSegments.UiaEolName(LineEndings.Crlf),
        StatusSegments.EncodingDisplay(FileOpen.Utf8Name),
        StatusSegments.UiaEncodingName(FileOpen.Utf8Name));
}
