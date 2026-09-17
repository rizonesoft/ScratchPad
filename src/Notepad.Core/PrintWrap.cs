using System;
using System.Collections.Generic;

namespace Notepad.Core;

// Print line-breaking, owned by D01 T02 §5. Greedy word wrap over explicit
// advance widths: the Windows side measures with Graphics and feeds the
// numbers here, so the algorithm stays pure and fixture-testable. A word
// longer than the line starts its own line and overflows (no mid-word
// break; default, cost: one stock probe printing an overlong word).
public static class PrintWrap
{
    // Returns lines as (start word index, word count) ranges. words and
    // widths run in the same order; spaceWidth is the inter-word gap.
    public static IReadOnlyList<(int Start, int Count)> WrapWords(
        IReadOnlyList<string> words,
        IReadOnlyList<float> widths,
        float spaceWidth,
        float maxWidth)
    {
        ArgumentNullException.ThrowIfNull(words);
        ArgumentNullException.ThrowIfNull(widths);
        if (words.Count != widths.Count)
        {
            throw new ArgumentException("words and widths must run in the same order.", nameof(widths));
        }

        var lines = new List<(int Start, int Count)>();
        int start = 0;
        float used = 0;
        for (int i = 0; i < words.Count; i++)
        {
            float need = widths[i] + (i > start ? spaceWidth : 0);
            if (i > start && used + need > maxWidth)
            {
                lines.Add((start, i - start));
                start = i;
                used = 0;
                need = widths[i];
            }

            used += need;
        }

        if (words.Count > 0)
        {
            lines.Add((start, words.Count - start));
        }
        else
        {
            lines.Add((0, 0));
        }

        return lines;
    }
}
