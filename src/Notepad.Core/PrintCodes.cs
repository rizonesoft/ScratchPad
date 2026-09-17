using System;

namespace Notepad.Core;

// Print context for header/footer code expansion: explicit strings keep the
// expansion pure and deterministic (the caller formats date/time in locale).
public sealed record PrintContext(string Date, string Time, string FileName, int Page);

// Header/footer code expansion, owned by D01 T02 §5. Codes follow the
// documented set (support.microsoft.com print-codes article, cited in §5):
// &l &c &r switch the active part, &d &t &f &p expand, && is a literal &.
// Text before any alignment code lands left (stock default placement).
// Unknown codes and a trailing & stay literal (default, cost: one stock
// probe printing "&q" and a trailing "&").
public static class PrintCodes
{
    public const string DefaultHeader = "&f";

    public const string DefaultFooter = "Page &p";

    public static (string Left, string Center, string Right) ExpandParts(string template, PrintContext context)
    {
        ArgumentNullException.ThrowIfNull(template);
        ArgumentNullException.ThrowIfNull(context);
        var left = new System.Text.StringBuilder();
        var center = new System.Text.StringBuilder();
        var right = new System.Text.StringBuilder();
        System.Text.StringBuilder active = left;
        for (int i = 0; i < template.Length; i++)
        {
            char c = template[i];
            if (c != '&' || i + 1 >= template.Length)
            {
                active.Append(c);
                continue;
            }

            char code = template[i + 1];
            switch (code)
            {
                case 'l': active = left; i++; break;
                case 'c': active = center; i++; break;
                case 'r': active = right; i++; break;
                case 'd': active.Append(context.Date); i++; break;
                case 't': active.Append(context.Time); i++; break;
                case 'f': active.Append(context.FileName); i++; break;
                case 'p': active.Append(context.Page); i++; break;
                case '&': active.Append('&'); i++; break;
                default: active.Append(c); break;
            }
        }

        return (left.ToString(), center.ToString(), right.ToString());
    }
}
