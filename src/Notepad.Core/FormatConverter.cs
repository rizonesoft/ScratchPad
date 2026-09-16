using System.Text;

namespace Notepad.Core;

// Cross-format converter, owned by D01 T01 §18 and shared with copy-as.
// Input is buffer text read as Markdown source; the supported subset is ATX
// headings, `*` emphasis, `**` strong, single-backtick code spans,
// `[text](url)` links, flat `-`/`*` and `1.` lists, and paragraphs.
// Everything else (underscores, images, nested or indented lists, unmatched
// markers) passes through literally. Markdown output is line-break-normalized
// identity; plain output strips the markers; HTML output renders structure.
// Copy-as consumes the fragment; export wraps it in a document shell.
public enum ExportFormat
{
    Markdown,
    Html,
    PlainText,
}

public static class FormatConverter
{
    public static string ExtensionFor(ExportFormat format) => format switch
    {
        ExportFormat.Markdown => ".md",
        ExportFormat.Html => ".html",
        ExportFormat.PlainText => ".txt",
        _ => throw new ArgumentOutOfRangeException(nameof(format)),
    };

    public static string ToMarkdown(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return NormalizeBreaks(text);
    }

    public static string ToPlainText(string markdown)
    {
        ArgumentNullException.ThrowIfNull(markdown);
        var plain = new StringBuilder();
        bool first = true;
        foreach (string line in NormalizeBreaks(markdown).Split('\n'))
        {
            if (!first)
            {
                plain.Append('\n');
            }

            first = false;
            plain.Append(StripBlockMarker(line));
        }

        return plain.ToString();
    }

    public static string ToHtmlFragment(string markdown)
    {
        ArgumentNullException.ThrowIfNull(markdown);
        string[] lines = NormalizeBreaks(markdown).Split('\n');
        var html = new StringBuilder();
        int i = 0;
        while (i < lines.Length)
        {
            if (lines[i].Length == 0)
            {
                i++;
                continue;
            }

            if (TryHeading(lines[i], out int level, out string heading))
            {
                html.Append("<h").Append(level).Append('>');
                html.Append(InlineToHtml(heading));
                html.Append("</h").Append(level).Append(">\n");
                i++;
            }
            else if (IsListItem(lines[i], out bool ordered))
            {
                html.Append(ordered ? "<ol>\n" : "<ul>\n");
                while (i < lines.Length && IsListItem(lines[i], out bool next) && next == ordered)
                {
                    html.Append("<li>").Append(InlineToHtml(ListItemText(lines[i]))).Append("</li>\n");
                    i++;
                }

                html.Append(ordered ? "</ol>\n" : "</ul>\n");
            }
            else
            {
                html.Append("<p>");
                bool firstLine = true;
                while (i < lines.Length && lines[i].Length != 0
                    && !IsHeadingLine(lines[i]) && !IsListItem(lines[i], out _))
                {
                    if (!firstLine)
                    {
                        html.Append('\n');
                    }

                    firstLine = false;
                    html.Append(InlineToHtml(lines[i]));
                    i++;
                }

                html.Append("</p>\n");
            }
        }

        return html.ToString();
    }

    public static string ToHtmlDocument(string title, string markdown)
    {
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(markdown);
        return "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>"
            + EscapeHtml(title)
            + "</title>\n</head>\n<body>\n"
            + ToHtmlFragment(markdown)
            + "</body>\n</html>\n";
    }

    static string NormalizeBreaks(string text) =>
        text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);

    static string StripBlockMarker(string line)
    {
        if (TryHeading(line, out _, out string heading))
        {
            return InlineToPlain(heading);
        }

        return InlineToPlain(line);
    }

    static bool IsHeadingLine(string line) => TryHeading(line, out _, out _);

    static bool TryHeading(string line, out int level, out string text)
    {
        level = 0;
        text = string.Empty;
        int hashes = 0;
        while (hashes < line.Length && hashes < 6 && line[hashes] == '#')
        {
            hashes++;
        }

        if (hashes == 0 || hashes == line.Length || line[hashes] != ' ')
        {
            return false;
        }

        level = hashes;
        text = line[(hashes + 1)..];
        return true;
    }

    static bool IsListItem(string line, out bool ordered)
    {
        ordered = false;
        if (line.StartsWith("- ", StringComparison.Ordinal) || line.StartsWith("* ", StringComparison.Ordinal))
        {
            return true;
        }

        int digits = 0;
        while (digits < line.Length && char.IsAsciiDigit(line[digits]))
        {
            digits++;
        }

        if (digits == 0 || digits + 1 >= line.Length || line[digits] != '.' || line[digits + 1] != ' ')
        {
            return false;
        }

        ordered = true;
        return true;
    }

    static string ListItemText(string line)
    {
        if (line.StartsWith("- ", StringComparison.Ordinal) || line.StartsWith("* ", StringComparison.Ordinal))
        {
            return line[2..];
        }

        int digits = 0;
        while (digits < line.Length && char.IsAsciiDigit(line[digits]))
        {
            digits++;
        }

        return line[(digits + 2)..];
    }

    static string InlineToHtml(string text)
    {
        var html = new StringBuilder();
        int i = 0;
        while (i < text.Length)
        {
            if (text[i] == '`' && FindClosing(text, i + 1, '`') is int codeEnd)
            {
                html.Append("<code>").Append(EscapeHtml(text[(i + 1)..codeEnd])).Append("</code>");
                i = codeEnd + 1;
            }
            else if (text[i] == '!' && i + 1 < text.Length && text[i + 1] == '['
                && TryLink(text, i + 1, out _, out _, out int imageEnd))
            {
                html.Append(EscapeHtml(text[i..imageEnd]));
                i = imageEnd;
            }
            else if (text[i] == '[' && TryLink(text, i, out string linkText, out string url, out int linkEnd))
            {
                html.Append("<a href=\"").Append(EscapeHtml(url)).Append("\">");
                html.Append(InlineToHtml(linkText));
                html.Append("</a>");
                i = linkEnd;
            }
            else if (text[i] == '*' && i + 1 < text.Length && text[i + 1] == '*'
                && FindStrongClosing(text, i + 2) is int strongEnd)
            {
                html.Append("<strong>").Append(InlineToHtml(text[(i + 2)..strongEnd])).Append("</strong>");
                i = strongEnd + 2;
            }
            else if (text[i] == '*' && FindEmphasisClosing(text, i + 1) is int emEnd)
            {
                html.Append("<em>").Append(InlineToHtml(text[(i + 1)..emEnd])).Append("</em>");
                i = emEnd + 1;
            }
            else
            {
                html.Append(EscapeHtmlChar(text[i]));
                i++;
            }
        }

        return html.ToString();
    }

    static string InlineToPlain(string text)
    {
        var plain = new StringBuilder();
        int i = 0;
        while (i < text.Length)
        {
            if (text[i] == '`' && FindClosing(text, i + 1, '`') is int codeEnd)
            {
                plain.Append(text[(i + 1)..codeEnd]);
                i = codeEnd + 1;
            }
            else if (text[i] == '!' && i + 1 < text.Length && text[i + 1] == '['
                && TryLink(text, i + 1, out _, out _, out int imageEnd))
            {
                plain.Append(text[i..imageEnd]);
                i = imageEnd;
            }
            else if (text[i] == '[' && TryLink(text, i, out string linkText, out string url, out int linkEnd))
            {
                plain.Append(InlineToPlain(linkText)).Append(" (").Append(url).Append(')');
                i = linkEnd;
            }
            else if (text[i] == '*' && i + 1 < text.Length && text[i + 1] == '*'
                && FindStrongClosing(text, i + 2) is int strongEnd)
            {
                plain.Append(InlineToPlain(text[(i + 2)..strongEnd]));
                i = strongEnd + 2;
            }
            else if (text[i] == '*' && FindEmphasisClosing(text, i + 1) is int emEnd)
            {
                plain.Append(InlineToPlain(text[(i + 1)..emEnd]));
                i = emEnd + 1;
            }
            else
            {
                plain.Append(text[i]);
                i++;
            }
        }

        return plain.ToString();
    }

    static int? FindClosing(string text, int start, char marker)
    {
        for (int i = start; i < text.Length; i++)
        {
            if (text[i] == marker)
            {
                return i;
            }
        }

        return null;
    }

    static int? FindStrongClosing(string text, int start)
    {
        for (int i = start; i + 1 < text.Length; i++)
        {
            if (text[i] == '*' && text[i + 1] == '*')
            {
                return i;
            }
        }

        return null;
    }

    // A closing `*` must not touch another `*`, so `*a **b** c*` keeps the
    // strong pair instead of ending the emphasis at its first star.
    static int? FindEmphasisClosing(string text, int start)
    {
        for (int i = start; i < text.Length; i++)
        {
            if (text[i] != '*')
            {
                continue;
            }

            bool leftStar = i > 0 && text[i - 1] == '*';
            bool rightStar = i + 1 < text.Length && text[i + 1] == '*';
            if (!leftStar && !rightStar)
            {
                return i;
            }
        }

        return null;
    }

    static bool TryLink(string text, int open, out string linkText, out string url, out int end)
    {
        linkText = string.Empty;
        url = string.Empty;
        end = open;
        int sep = text.IndexOf("](", open + 1, StringComparison.Ordinal);
        if (sep < 0)
        {
            return false;
        }

        int close = text.IndexOf(')', sep + 2);
        if (close < 0)
        {
            return false;
        }

        linkText = text[(open + 1)..sep];
        url = text[(sep + 2)..close];
        end = close + 1;
        return true;
    }

    static string EscapeHtml(string text)
    {
        var escaped = new StringBuilder(text.Length);
        foreach (char c in text)
        {
            escaped.Append(EscapeHtmlChar(c));
        }

        return escaped.ToString();
    }

    static string EscapeHtmlChar(char c) => c switch
    {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        _ => c.ToString(),
    };
}
