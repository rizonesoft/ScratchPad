using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §36 item 1: covering-test outcome evidence proved by
// execution. The theory runs each covered row's covering test in a
// child test run with the row's command swapped for a different host
// member and requires an assertion after the press to fail; the plant
// fact runs a constant-local test the same way and requires it to read
// survived (both fenced: the children press physical chords, so they
// run in the quiet window and are Night-owed). The pure facts pin the
// case table, the targets, the outcome parse, and the verdict rules.
public sealed class BindingMutationTests
{
    public static TheoryData<string, string, string> CoveredCases()
    {
        var data = new TheoryData<string, string, string>();
        foreach (var c in LiveCases())
        {
            data.Add(c.Chord, c.Command, $"{c.TestClass}.{c.TestMethod}");
        }

        return data;
    }

    [InteractiveTheory]
    [Trait("Category", "Interactive")]
    [MemberData(nameof(CoveredCases))]
    public void CoveringTestFailsWithItsCommandSwapped(string chord, string command, string test)
    {
        var c = Assert.Single(LiveCases(), x => x.Chord == chord && x.Command == command && $"{x.TestClass}.{x.TestMethod}" == test);
        var (_, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{c.TestClass}.{c.TestMethod}", MutationEnv(c.Target, plant: false), TimeSpan.FromMinutes(4));
        Assert.Null(BindingMutation.Problem(c, BindingMutation.ParseOutcome(output, c.TestClass, c.TestMethod)));
    }

    // The plant, executed: it passes with Ctrl+Shift+G's command swapped,
    // so the mutation run reads it as survived.
    [InteractiveFact]
    [Trait("Category", "Interactive")]
    public void PlantedConstantLocalSurvivesTheMutationRun()
    {
        string src = PlantSource();
        Assert.True(BindingManifest.AssertsAfterPress(src, nameof(MutationPlantTests.PlantedConstantLocalAssertion), "Ctrl+Shift+G"), "the plant no longer satisfies the static rule, so it proves nothing");
        var c = new BindingMutation.Case("Ctrl+Shift+G", "MenuToolsStats", nameof(MutationPlantTests), nameof(MutationPlantTests.PlantedConstantLocalAssertion), "MenuToolsStats",
            BindingMutation.PressLine(src, nameof(MutationPlantTests.PlantedConstantLocalAssertion), "Ctrl+Shift+G"));
        var (_, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{c.TestClass}.{c.TestMethod}", MutationEnv(c.Target, plant: true), TimeSpan.FromMinutes(4));
        var outcome = BindingMutation.ParseOutcome(output, c.TestClass, c.TestMethod);
        Assert.True(outcome.Passed == 1, $"the plant did not run to a pass under mutation: {outcome.Tail}");
        Assert.Contains("observes nothing that tells the command apart", BindingMutation.Problem(c, outcome), StringComparison.Ordinal);
    }

    // The child-run plumbing, focus-free: a child run of a pure fact in
    // this assembly resolves dotnet and the assembly, passes the filter
    // and the environment, and its summary parses as one passed test.
    [Fact]
    public void ChildRunReadsAPassingPureTest()
    {
        var (exit, output) = UiLaunch.RunChildTest("FullyQualifiedName=UI.BindingMutationTests.TargetsNameTheMenuItemOrTheAcceleratorKey", MutationEnv("MenuFileNewTab", plant: false), TimeSpan.FromMinutes(2));
        var outcome = BindingMutation.ParseOutcome(output, nameof(BindingMutationTests), nameof(TargetsNameTheMenuItemOrTheAcceleratorKey));
        Assert.True(exit == 0 && outcome.Passed == 1 && outcome.Failed == 0, $"child run exit {exit}: {outcome.Tail}");
    }

    [Fact]
    public void EveryCoveredRowHasAMutationCaseWithItsPressLine()
    {
        var cases = LiveCases();
        var rows = LiveRows().Where(r => r.Class == "covered").ToList();
        Assert.NotEmpty(rows);
        Assert.All(rows, r => Assert.Contains(cases, c => c.Chord == r.Chord && c.Command == r.Command));
        Assert.All(cases, c => Assert.True(c.PressLine > 0, $"{c.TestClass}.{c.TestMethod} has no press of {c.Chord}"));
    }

    [Fact]
    public void TargetsNameTheMenuItemOrTheAcceleratorKey()
    {
        Assert.Equal("MenuFileNewTab", BindingMutation.Target("Ctrl+N", "MenuFileNewTab"));
        Assert.Equal("vk:84:1", BindingMutation.Target("Ctrl+T", "Tabs.NewTab"));
        Assert.Equal("vk:9:5", BindingMutation.Target("Ctrl+Shift+Tab", "Tabs.CyclePrevious"));
        Assert.Equal("vk:49:1", BindingMutation.Target("Ctrl+1", "Tabs.GotoNumber(1)"));
    }

    [Fact]
    public void VerdictsSeparateKilledSurvivedAndInconclusive()
    {
        var c = new BindingMutation.Case("Ctrl+N", "MenuFileNewTab", "MenuBarTests", "FileMenuLiveAcceleratorsWork", "MenuFileNewTab", 40);
        const string Summary = "Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1";
        string Failure(string message, int line) => $"  Failed UI.MenuBarTests.FileMenuLiveAcceleratorsWork [9 s]\n  Error Message:\n   {message}\n  Stack Trace:\n     at UI.MenuBarTests.FileMenuLiveAcceleratorsWork() in R:\\x\\tests\\UI\\MenuBarTests.cs:line {line}\n{Summary}";
        BindingMutation.ChildOutcome Parse(string output) => BindingMutation.ParseOutcome(output, "MenuBarTests", "FileMenuLiveAcceleratorsWork");
        Assert.Null(BindingMutation.Problem(c, Parse(Failure("Assert.Equal() Failure: Values differ", 44))));
        Assert.Contains("not after the press", BindingMutation.Problem(c, Parse(Failure("Assert.NotNull() Failure: Value is null", 30))), StringComparison.Ordinal);
        Assert.Contains("not on an assertion", BindingMutation.Problem(c, Parse(Failure("System.TimeoutException : UIA Timeout", 44))), StringComparison.Ordinal);
        Assert.Contains("passed with its command swapped", BindingMutation.Problem(c, Parse("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1")), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, Parse("Passed!  - Failed:     0, Passed:     0, Skipped:     1, Total:     1")), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, Parse("No test matches the given testcase filter")), StringComparison.Ordinal);
    }

    static Dictionary<string, string> MutationEnv(string target, bool plant)
    {
        var env = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [TestMutation.Variable] = target,
            [LaunchCapture.RunMarkerVariable] = "1",
        };
        if (plant)
        {
            env[MutationPlantFactAttribute.Variable] = "1";
        }

        return env;
    }

    static string PlantSource() => File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "tests", "UI", "MutationPlantTests.cs"));

    static List<BindingManifest.AuditRow> LiveRows()
    {
        var rows = BindingManifest.ParseAudit(File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "docs", "ui-input-audit.md")), out var parse);
        Assert.Empty(parse);
        return rows;
    }

    static List<BindingMutation.Case> LiveCases()
    {
        string root = BindingManifestTests.RepoRoot();
        var byClass = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string file in Directory.EnumerateFiles(Path.Combine(root, "tests", "UI"), "*.cs"))
        {
            string text = File.ReadAllText(file);
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(text, "\\bclass (\\w+)"))
            {
                byClass.TryAdd(m.Groups[1].Value, text);
            }
        }

        return BindingMutation.Cases(LiveRows(), cls => byClass.TryGetValue(cls, out string? src) ? src : null);
    }
}
