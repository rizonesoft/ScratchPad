using System.Globalization;
using System.Text.RegularExpressions;
using Notepad.Core;

namespace UI;

// The binding mutation run (D00 T02 §36 item 1). The static rule
// (BindingManifest.AssertsAfterPress) is a cheap pre-check: an assertion
// over a local assigned after the press passes it even when the local is
// a constant. Execution closes that gap: for each covered row, the
// covering test runs in a child test run whose app suppresses the row's
// command (Notepad.Core.TestMutation), and it must fail. A test that
// still passes observes nothing the command did, so it covers nothing.
// Recorded default: the mutation is suppression (the handler returns
// before its host call, the tab accelerator is handled and does
// nothing), not a swap to another host member; a swap would also catch
// assertions satisfied by any command, at the cost of choosing a
// harmless substitute per command. Cost of changing: a substitute table
// beside BindingManifest.HostCalls.
internal static class BindingMutation
{
    internal sealed record Case(string Chord, string Command, string TestClass, string TestMethod, string Target);

    internal sealed record ChildOutcome(int Passed, int Failed, int Skipped, string Tail);

    // One case per (covered row, covering test).
    internal static List<Case> Cases(IEnumerable<BindingManifest.AuditRow> rows)
    {
        var cases = new List<Case>();
        foreach (var row in rows.Where(r => r.Class == "covered"))
        {
            foreach (Match t in Regex.Matches(row.Detail, "`(\\w+)\\.(\\w+)`"))
            {
                cases.Add(new Case(row.Chord, row.Command, t.Groups[1].Value, t.Groups[2].Value, Target(row.Chord, row.Command)));
            }
        }

        return cases;
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
        return TestMutation.Key(vk, mods);
    }

    // The child run's summary line (dotnet test prints one per assembly).
    internal static ChildOutcome ParseOutcome(string output)
    {
        Match m = Regex.Match(output, "Failed:\\s+(\\d+), Passed:\\s+(\\d+), Skipped:\\s+(\\d+)");
        string tail = string.Join(" | ", output.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).TakeLast(3));
        return m.Success
            ? new ChildOutcome(Int(m.Groups[2].Value), Int(m.Groups[1].Value), Int(m.Groups[3].Value), tail)
            : new ChildOutcome(0, 0, 0, tail);
    }

    static int Int(string s) => int.Parse(s, CultureInfo.InvariantCulture);

    // The verdict for one case: killed (the test failed, good), survived
    // (it passed under mutation, so it covers nothing), or inconclusive
    // (it did not run: skipped, filtered out, or no summary).
    internal static string? Problem(Case c, ChildOutcome o) =>
        o.Failed > 0 ? null
        : o.Passed > 0 ? $"{c.Chord} -> {c.Command}: {c.TestClass}.{c.TestMethod} passed with the command suppressed ({c.Target}), so it observes nothing the command did"
        : $"{c.Chord} -> {c.Command}: {c.TestClass}.{c.TestMethod} did not run under mutation (passed 0, failed 0, skipped {o.Skipped}): {o.Tail}";
}
