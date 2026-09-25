using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §36 item 1: covering-test outcome evidence proved by
// execution. The theory runs each covered row's covering test in a
// child test run with the row's command suppressed and requires it to
// fail (fenced: the child presses physical chords, so it runs in the
// quiet window and is Night-owed). The pure facts pin the case table,
// the targets, the outcome parse, and the planted constant-local
// assertion: it satisfies the static rule, and a passing child run
// under mutation reads as survived, never as coverage.
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
    public void CoveringTestFailsWithItsCommandSuppressed(string chord, string command, string test)
    {
        var c = Assert.Single(LiveCases(), x => x.Chord == chord && x.Command == command && $"{x.TestClass}.{x.TestMethod}" == test);
        var env = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [TestMutation.Variable] = c.Target,
            [LaunchCapture.RunMarkerVariable] = "1",
        };
        var (_, output) = UiLaunch.RunChildTest($"FullyQualifiedName=UI.{c.TestClass}.{c.TestMethod}", env, TimeSpan.FromMinutes(4));
        Assert.Null(BindingMutation.Problem(c, BindingMutation.ParseOutcome(output)));
    }

    // The child-run plumbing, focus-free: a child run of a pure fact in
    // this assembly resolves dotnet and the assembly, passes the filter
    // and the environment, and its summary parses as one passed test.
    [Fact]
    public void ChildRunReadsAPassingPureTest()
    {
        var env = new Dictionary<string, string>(StringComparer.Ordinal) { [TestMutation.Variable] = "MenuFileNewTab" };
        var (exit, output) = UiLaunch.RunChildTest("FullyQualifiedName=UI.BindingMutationTests.TargetsNameTheMenuItemOrTheAcceleratorKey", env, TimeSpan.FromMinutes(2));
        var outcome = BindingMutation.ParseOutcome(output);
        Assert.True(exit == 0 && outcome.Passed == 1 && outcome.Failed == 0, $"child run exit {exit}: {outcome.Tail}");
    }

    [Fact]
    public void EveryCoveredRowHasAMutationCase()
    {
        var cases = LiveCases();
        var rows = LiveRows().Where(r => r.Class == "covered").ToList();
        Assert.NotEmpty(rows);
        Assert.All(rows, r => Assert.Contains(cases, c => c.Chord == r.Chord && c.Command == r.Command));
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
    public void OutcomeParseSeparatesKilledSurvivedAndInconclusive()
    {
        var c = new BindingMutation.Case("Ctrl+N", "MenuFileNewTab", "MenuBarTests", "FileMenuLiveAcceleratorsWork", "MenuFileNewTab");
        Assert.Null(BindingMutation.Problem(c, BindingMutation.ParseOutcome("Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 9 s - UI.dll (net10.0)")));
        Assert.Contains("passed with the command suppressed", BindingMutation.Problem(c, BindingMutation.ParseOutcome("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1")), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, BindingMutation.ParseOutcome("Passed!  - Failed:     0, Passed:     0, Skipped:     1, Total:     1")), StringComparison.Ordinal);
        Assert.Contains("did not run under mutation", BindingMutation.Problem(c, BindingMutation.ParseOutcome("No test matches the given testcase filter")), StringComparison.Ordinal);
    }

    // The planted constant-local assertion (§28 R3-F1): it presses the
    // chord and asserts a local assigned after the press, so the static
    // rule credits it; its assertion reads no app state, so it passes
    // whatever the command did, and the mutation verdict for a passing
    // child run is survived: the gate the static rule could not be.
    [Fact]
    public void PlantedConstantLocalPassesTheStaticRuleButFailsTheMutationRun()
    {
        const string plant = """
            class Plant
            {
                [InteractiveFact]
                [Trait("Category", "Interactive")]
                public void ChordCtrlShiftGOpensStats()
                {
                    UiInput.Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
                    int observed = 0;
                    Assert.Equal(0, observed);
                }
            }
            """;
        Assert.True(BindingManifest.AssertsAfterPress(plant, "ChordCtrlShiftGOpensStats", "Ctrl+Shift+G"));
        var c = new BindingMutation.Case("Ctrl+Shift+G", "MenuToolsStats", "Plant", "ChordCtrlShiftGOpensStats", BindingMutation.Target("Ctrl+Shift+G", "MenuToolsStats"));
        string? problem = BindingMutation.Problem(c, BindingMutation.ParseOutcome("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1"));
        Assert.NotNull(problem);
        Assert.Contains("observes nothing the command did", problem, StringComparison.Ordinal);
    }

    static List<BindingManifest.AuditRow> LiveRows()
    {
        var rows = BindingManifest.ParseAudit(File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "docs", "ui-input-audit.md")), out var parse);
        Assert.Empty(parse);
        return rows;
    }

    static List<BindingMutation.Case> LiveCases() => BindingMutation.Cases(LiveRows());
}
