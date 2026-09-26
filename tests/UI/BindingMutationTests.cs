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
[Collection("UI tests")]
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
        var baseline = Baseline(c.TestClass, c.TestMethod, plant: false);
        var (env, log) = MutationEnv(c.Target, plant: false);
        var (exit, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{c.TestClass}.{c.TestMethod}", env, TimeSpan.FromMinutes(4));
        string[] lines = LogLines(log);
        Assert.Null(BindingMutation.Problem(c, baseline, BindingMutation.ParseOutcome(output, c.TestClass, c.TestMethod), BindingMutation.EvidenceOf(lines, c.Target), BindingMutation.ArmedIn(lines, c.Target), killedAtBound: exit == -1));
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
        var baseline = Baseline(c.TestClass, c.TestMethod, plant: true);
        var (env, log) = MutationEnv(c.Target, plant: true);
        var (exit, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{c.TestClass}.{c.TestMethod}", env, TimeSpan.FromMinutes(4));
        var outcome = BindingMutation.ParseOutcome(output, c.TestClass, c.TestMethod);
        Assert.True(outcome.Passed == 1, $"the plant did not run to a pass under mutation: {outcome.Tail}");
        string[] lines = LogLines(log);
        Assert.Contains("observes nothing that tells the command apart", BindingMutation.Problem(c, baseline, outcome, BindingMutation.EvidenceOf(lines, c.Target), BindingMutation.ArmedIn(lines, c.Target), killedAtBound: exit == -1), StringComparison.Ordinal);
    }

    // The child-run plumbing, focus-free: a child run of a pure fact in
    // this assembly resolves dotnet and the assembly, passes the filter
    // and the environment, and its summary parses as one passed test.
    [Fact]
    public void ChildRunReadsAPassingPureTest()
    {
        var (exit, output) = UiLaunch.RunChildTest("FullyQualifiedName=UI.BindingMutationTests.TargetsNameTheMenuItemOrTheAcceleratorKey", MutationEnv("MenuFileNewTab", plant: false).Env, TimeSpan.FromMinutes(2));
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
        var green = BindingMutation.ParseOutcome("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1", "MenuBarTests", "FileMenuLiveAcceleratorsWork");
        const string Summary = "Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1";
        string Failure(string message, int line) => $"  Failed UI.MenuBarTests.FileMenuLiveAcceleratorsWork [9 s]\n  Error Message:\n   {message}\n  Stack Trace:\n     at UI.MenuBarTests.FileMenuLiveAcceleratorsWork() in R:\\x\\tests\\UI\\MenuBarTests.cs:line {line}\n{Summary}";
        BindingMutation.ChildOutcome Parse(string output) => BindingMutation.ParseOutcome(output, "MenuBarTests", "FileMenuLiveAcceleratorsWork");
        Assert.Null(BindingMutation.Problem(c, green, Parse(Failure("Assert.Equal() Failure: Values differ", 44)), BindingMutation.SwapEvidence.Completed));
        // §43 item 1: without swap evidence a failure and a pass are both
        // inconclusive, never killed or survived.
        Assert.Contains("is inconclusive: the swap never activated", BindingMutation.Problem(c, green, Parse(Failure("Assert.Equal() Failure: Values differ", 44)), BindingMutation.SwapEvidence.None), StringComparison.Ordinal);
        Assert.Contains("is inconclusive: the swap never activated", BindingMutation.Problem(c, green, Parse("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1"), BindingMutation.SwapEvidence.None), StringComparison.Ordinal);
        Assert.Contains("did not pass unmutated", BindingMutation.Problem(c, Parse(Failure("Assert.Equal() Failure: Values differ", 44)), Parse(Failure("Assert.Equal() Failure: Values differ", 44)), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("not after the press", BindingMutation.Problem(c, green, Parse(Failure("Assert.NotNull() Failure: Value is null", 30)), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("not on an assertion", BindingMutation.Problem(c, green, Parse(Failure("System.TimeoutException : UIA Timeout", 44)), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("passed with its command swapped", BindingMutation.Problem(c, green, Parse("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1"), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, green, Parse("Passed!  - Failed:     0, Passed:     0, Skipped:     1, Total:     1"), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, green, Parse("No test matches the given testcase filter"), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
    }

    // D00 T02 §51 items 1, 2, 3, and 11: a started but uncompleted swap, an
    // unarmed child, a child killed at its bound, an infrastructure failure
    // after the press, and a failure in the covering method's finally block
    // are each inconclusive; a suppress cell needs zero dispatch and an
    // unchanged window count.
    [Fact]
    public void ExecutionAcknowledgmentAttributionAndNegativeRouting()
    {
        const string Src = "class FixtureAttributionTests { void FixtureCoveringMethod() {\n var a = 1;\n try {\n UiInput.Press(x, \"Ctrl+N\");\n Assert.Equal(1, a);\n }\n finally {\n Assert.True(true);\n }\n } }";
        var cleanup = BindingMutation.CleanupLinesOf(Src, "FixtureCoveringMethod");
        Assert.Equal(new HashSet<int> { 7, 8, 9 }, cleanup.ToHashSet());
        var c = new BindingMutation.Case("Ctrl+N", "MenuFileNewTab", "FixtureAttributionTests", "FixtureCoveringMethod", "MenuFileNewTab", 4, cleanup);
        var green = BindingMutation.ParseOutcome("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1", "FixtureAttributionTests", "FixtureCoveringMethod");
        BindingMutation.ChildOutcome Fail(string message, int line) => BindingMutation.ParseOutcome($"  Failed UI.FixtureAttributionTests.FixtureCoveringMethod [9 s]\n  Error Message:\n   {message}\n  Stack Trace:\n     at UI.FixtureAttributionTests.FixtureCoveringMethod() in R:\\x\\FixtureAttributionTests.cs:line {line}\nFailed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1", "FixtureAttributionTests", "FixtureCoveringMethod");
        Assert.Null(BindingMutation.Problem(c, green, Fail("Assert.Equal() Failure: Values differ", 5), BindingMutation.SwapEvidence.Completed));
        Assert.Contains("substitute never completed", BindingMutation.Problem(c, green, Fail("Assert.Equal() Failure: Values differ", 5), BindingMutation.SwapEvidence.Started), StringComparison.Ordinal);
        Assert.Contains("never armed its target", BindingMutation.Problem(c, green, Fail("Assert.Equal() Failure: Values differ", 5), BindingMutation.SwapEvidence.Completed, armed: false), StringComparison.Ordinal);
        Assert.Contains("outlived its bound and was killed", BindingMutation.Problem(c, green, Fail("Assert.Equal() Failure: Values differ", 5), BindingMutation.SwapEvidence.Completed, killedAtBound: true), StringComparison.Ordinal);
        Assert.Contains("failed on infrastructure", BindingMutation.Problem(c, green, Fail("Assert.True() Failure: the app did not open a tab within 5 s (timeout)", 5), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Contains("failed in the covering method's cleanup", BindingMutation.Problem(c, green, Fail("Assert.True() Failure", 8), BindingMutation.SwapEvidence.Completed), StringComparison.Ordinal);
        Assert.Equal(BindingMutation.SwapEvidence.Completed, BindingMutation.EvidenceOf(["armed:MenuFileNewTab", "swap:MenuFileNewTab", "swap-done:MenuFileNewTab"], "MenuFileNewTab"));
        Assert.Equal(BindingMutation.SwapEvidence.Started, BindingMutation.EvidenceOf(["swap:MenuFileNewTab"], "MenuFileNewTab"));
        Assert.True(BindingMutation.ArmedIn(["armed:MenuFileNewTab"], "MenuFileNewTab") && !BindingMutation.ArmedIn(["armed:MenuFileOpen"], "MenuFileNewTab"));
        Assert.Null(BindingMutation.RoutingProblem("Ctrl+N", "MenuFileNewTab", "modal", "suppress", [], 1, 1));
        Assert.Contains("dispatched MenuFileOpen", BindingMutation.RoutingProblem("Ctrl+N", "MenuFileNewTab", "modal", "suppress", ["MenuFileOpen"], 1, 1), StringComparison.Ordinal);
        Assert.Contains("window count changed", BindingMutation.RoutingProblem("Ctrl+N", "MenuFileNewTab", "modal", "suppress", [], 1, 2), StringComparison.Ordinal);
        Assert.Null(BindingMutation.RoutingProblem("Ctrl+N", "MenuFileNewTab", "editor", "execute", ["MenuFileNewTab"], 1, 1));
    }

    // One unmutated child run per covering test, cached for the run (the
    // theory's cases share covering tests), so every case knows the test
    // passes without the swap (§36 R2-F1).
    static readonly Dictionary<string, BindingMutation.ChildOutcome> Baselines = new(StringComparer.Ordinal);

    static BindingMutation.ChildOutcome Baseline(string cls, string method, bool plant)
    {
        string key = $"{cls}.{method}";
        lock (Baselines)
        {
            if (!Baselines.TryGetValue(key, out var outcome))
            {
                var env = new Dictionary<string, string>(StringComparer.Ordinal) { [TestMutation.Variable] = string.Empty };
                if (plant)
                {
                    env[MutationPlantFactAttribute.Variable] = "1";
                }

                var (_, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{key}", env, TimeSpan.FromMinutes(4));
                outcome = BindingMutation.ParseOutcome(output, cls, method);
                Baselines[key] = outcome;
            }

            return outcome;
        }
    }

    // A fresh child environment per case (§43 item 1): the target set
    // explicitly (never inherited) and its own dispatch log for the swap
    // evidence.
    static (Dictionary<string, string> Env, string Log) MutationEnv(string target, bool plant)
    {
        string log = Path.Combine(Path.GetTempPath(), $"scratchpad-swap-{Guid.NewGuid():N}.log");
        var env = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [TestMutation.Variable] = target,
            [TestMutation.DispatchLogVariable] = log,
            [LaunchCapture.RunMarkerVariable] = "1",
        };
        if (plant)
        {
            env[MutationPlantFactAttribute.Variable] = "1";
        }

        return (env, log);
    }

    // The child's dispatch log, read once and deleted (a fresh log per
    // case, §43 item 1): swap, swap-done, and armed lines (§51 items 1, 11).
    static string[] LogLines(string log)
    {
        try
        {
            return File.Exists(log) ? File.ReadAllLines(log) : [];
        }
        finally
        {
            try
            {
                File.Delete(log);
            }
            catch (IOException)
            {
                // Best effort: a leftover temp log changes no verdict.
            }
        }
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
