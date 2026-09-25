using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Notepad.Core;

namespace UI;

// The binding mutation run (D00 T02 §36 item 1). The static rule
// (BindingManifest.AssertsAfterPress) is a cheap pre-check: an assertion
// over a local assigned after the press passes it even when the local is
// a constant. Execution closes that gap: for each covered row, the
// covering test runs in a child test run whose app swaps the row's
// command for a different host member (Notepad.Core.TestMutation: a new
// tab, or a new window or the next tab when the command itself opens a
// tab), and it must fail. A test that still passes observes nothing that
// tells the command apart, so it covers nothing. The kill is counted only
// when the failure is an assertion raised in the covering method after
// the chord's press (from the child's stack trace), so a launch or setup
// failure before the press never certifies coverage, and only when the
// same test passes unmutated (a baseline child run per covering test,
// cached for the run), so a failure the swap did not cause never counts
// (§36 R2-F1).
internal static class BindingMutation
{
    internal sealed record Case(string Chord, string Command, string TestClass, string TestMethod, string Target, int PressLine);

    internal sealed record ChildOutcome(int Passed, int Failed, int Skipped, string? FailureMessage, int? FailureLine, string Tail);

    // One case per (covered row, covering test), with the line of the
    // covering method's first press of the row's chord (0 when unknown).
    internal static List<Case> Cases(IEnumerable<BindingManifest.AuditRow> rows, Func<string, string?> testSource)
    {
        var cases = new List<Case>();
        foreach (var row in rows.Where(r => r.Class == "covered"))
        {
            foreach (Match t in Regex.Matches(row.Detail, "`(\\w+)\\.(\\w+)`"))
            {
                string cls = t.Groups[1].Value;
                string method = t.Groups[2].Value;
                string? src = testSource(cls);
                int line = src is null ? 0 : PressLine(src, method, row.Chord);
                cases.Add(new Case(row.Chord, row.Command, cls, method, Target(row.Chord, row.Command), line));
            }
        }

        return cases;
    }

    // The 1-based line of the method's first press whose chord is `chord`.
    internal static int PressLine(string source, string method, string chord)
    {
        SyntaxTree tree = CSharpSyntaxTree.ParseText(source);
        foreach (MethodDeclarationSyntax m in tree.GetRoot().DescendantNodes().OfType<MethodDeclarationSyntax>().Where(m => m.Identifier.Text == method))
        {
            foreach (InvocationExpressionSyntax call in m.DescendantNodes().OfType<InvocationExpressionSyntax>()
                .Where(c => c.Expression.ToString() is "UiInput.Press" or "UiInput.PressKey").OrderBy(c => c.SpanStart))
            {
                string one = "class P { " + m.RemoveNodes(
                    m.DescendantNodes().OfType<InvocationExpressionSyntax>()
                        .Where(c => c.Expression.ToString() is "UiInput.Press" or "UiInput.PressKey" && c != call)
                        .Select(c => c.Parent).OfType<ExpressionStatementSyntax>(),
                    SyntaxRemoveOptions.KeepNoTrivia)!.ToFullString() + " }";
                if (BindingManifest.PressedChords(one, method).Contains(chord))
                {
                    return tree.GetLineSpan(call.Span).StartLinePosition.Line + 1;
                }
            }
        }

        return 0;
    }

    // A menu item mutates by its AutomationId; a programmatic tab
    // accelerator by its virtual key and modifier bits (Control 1, Menu
    // 2, Shift 4, as Windows.System.VirtualKeyModifiers).
    internal static string Target(string chord, string command)
    {
        if (command.StartsWith("Menu", StringComparison.Ordinal))
        {
            return command;
        }

        var (vk, mods) = VirtualKeyOf(chord);
        return TestMutation.Key(vk, mods);
    }

    internal static (int Vk, int Mods) VirtualKeyOf(string chord)
    {
        string[] parts = chord.Split('+');
        int mods = 0;
        foreach (string m in parts[..^1])
        {
            mods |= m switch { "Ctrl" => 1, "Alt" => 2, "Shift" => 4, _ => throw new ArgumentException($"unknown modifier {m} in {chord}") };
        }

        string key = parts[^1];
        int vk = key switch
        {
            "Tab" => 9,
            _ when key.Length == 1 && char.IsAsciiLetterUpper(key[0]) => key[0],
            _ when key.Length == 1 && char.IsAsciiDigit(key[0]) => key[0],
            _ => throw new ArgumentException($"no virtual key for {key} in {chord}"),
        };
        return (vk, mods);
    }

    // The child run's summary line (dotnet test prints one per assembly),
    // plus the first failure's message and its line in the covering
    // method (the first stack frame in that class naming the method,
    // lambdas included).
    internal static ChildOutcome ParseOutcome(string output, string testClass, string testMethod)
    {
        string[] lines = output.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        Match m = Regex.Match(output, "Failed:\\s+(\\d+), Passed:\\s+(\\d+), Skipped:\\s+(\\d+)");
        string tail = string.Join(" | ", lines.Select(l => l.Trim()).Where(l => l.Length > 0).TakeLast(3));
        int msgAt = Array.FindIndex(lines, l => l.Trim() == "Error Message:");
        string? message = msgAt >= 0 ? lines.Skip(msgAt + 1).Select(l => l.Trim()).FirstOrDefault(l => l.Length > 0) : null;
        int? failLine = null;
        foreach (string l in lines)
        {
            Match frame = Regex.Match(l, $"at UI\\.{Regex.Escape(testClass)}\\.\\S*{Regex.Escape(testMethod)}\\S*\\(.*\\) in .*:line (\\d+)");
            if (frame.Success)
            {
                failLine = Int(frame.Groups[1].Value);
                break;
            }
        }

        return m.Success
            ? new ChildOutcome(Int(m.Groups[2].Value), Int(m.Groups[1].Value), Int(m.Groups[3].Value), message, failLine, tail)
            : new ChildOutcome(0, 0, 0, message, failLine, tail);
    }

    static int Int(string s) => int.Parse(s, CultureInfo.InvariantCulture);

    // The verdict for one case: killed (an assertion in the covering method
    // failed after the press: null, good), survived (it passed with its
    // command swapped, so it covers nothing), or inconclusive (it did not
    // run, or it failed before the press or outside an assertion).
    internal static string? Problem(Case c, ChildOutcome baseline, ChildOutcome o)
    {
        string at = $"{c.Chord} -> {c.Command}: {c.TestClass}.{c.TestMethod}";
        if (baseline.Passed < 1 || baseline.Failed > 0)
        {
            return $"{at} did not pass unmutated (passed {baseline.Passed}, failed {baseline.Failed}, skipped {baseline.Skipped}: {baseline.FailureMessage ?? baseline.Tail}), so a failure under mutation proves nothing about the command";
        }

        if (o.Failed > 0)
        {
            if (o.FailureMessage is null || !o.FailureMessage.StartsWith("Assert.", StringComparison.Ordinal))
            {
                return $"{at} failed under mutation, but not on an assertion ({o.FailureMessage ?? "no message"}), so the failure proves nothing about the command";
            }

            if (c.PressLine <= 0 || o.FailureLine is null || o.FailureLine <= c.PressLine)
            {
                return $"{at} failed under mutation at line {o.FailureLine?.ToString(CultureInfo.InvariantCulture) ?? "?"}, not after the press at line {c.PressLine}, so the failure proves nothing about the command";
            }

            return null;
        }

        return o.Passed > 0
            ? $"{at} passed with its command swapped ({c.Target}), so it observes nothing that tells the command apart"
            : $"{at} did not run under mutation (passed 0, failed 0, skipped {o.Skipped}): {o.Tail}";
    }
}
