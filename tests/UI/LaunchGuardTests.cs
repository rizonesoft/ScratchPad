using Xunit;

namespace UI;

// D00 T02 §18 item 6: the launch guard fails planted bypasses and
// passes the migrated tree. Each bypass shape the item names
// (direct, alias, wrapper, renamed, instance, inline-new,
// per-file, static-using, reflection, P/Invoke) trips at least one
// violation; the sanctioned helper path stays exempt.
// live tests/UI tree scans clean.
public sealed class LaunchGuardTests
{
    [Theory]
    [InlineData("using System.Diagnostics; class P { void M() { Process.Start(\"x\"); } }")]
    [InlineData("class P { void M() { System.Diagnostics.Process.Start(\"x\"); } }")]
    [InlineData("using FlaUI.Core; class P { void M() { Application.Launch(\"e\", \"a\"); } }")]
    [InlineData("using P = System.Diagnostics.Process; class Q { void M() { P.Start(\"x\"); } }")]
    [InlineData("using A = FlaUI.Core.Application; class Q { void M() { A.Launch(\"e\", \"a\"); } }")]
    [InlineData("class Q { void MyLauncher() { FlaUI.Core.Application.Launch(\"e\", \"a\"); } }")]
    [InlineData("class Q { void M() { var p = new System.Diagnostics.Process(); p.Start(); } }")]
    [InlineData("class Q { void M() { new System.Diagnostics.Process().Start(); } }")]
    [InlineData("class Q { void M() { var p = new System.Diagnostics.Process(); var alias = p; alias.Start(); } }")]
    [InlineData("class Q { void LaunchApp() {} }")]
    [InlineData("class Q { void SeedSettings() {} }")]
    [InlineData("using static System.Diagnostics.Process; class Q { void M() { Start(\"x\"); } }")]
    [InlineData("class Q { void M() { var m = typeof(System.Diagnostics.Process).GetMethod(\"Start\"); } }")]
    [InlineData("class Q { void M() { object? r = typeof(Q).Assembly.CreateInstance(\"Q\"); } }")]
    [InlineData("class Q { void M(System.Reflection.MethodInfo m, object o) { m.Invoke(o, null); } }")]
    [InlineData("class Q { void M() { dynamic p = null; p.Start(); } }")]
    [InlineData("using System.Runtime.InteropServices; class Q { [DllImport(\"kernel32.dll\")] static extern bool CreateProcessW(); }")]
    [InlineData("using System.Runtime.InteropServices; class Q { [DllImport(\"shell32.dll\", EntryPoint = \"ShellExecuteW\")] static extern int OpenIt(); }")]
    public void PlantedBypassFailsTheGuard(string snippet)
    {
        Assert.NotEmpty(LaunchGuard.FindViolations(snippet, "plant.cs"));
    }

    [Theory]
    [InlineData("class Q { void M() { var ps = System.Diagnostics.Process.GetProcessesByName(\"x\"); } }")]
    [InlineData("class Q { void M() { var a = FlaUI.Core.Application.Attach(5); } }")]
    [InlineData("class Q { [Xunit.Fact] public void LaunchAppendsTab() { UiLaunch.LaunchAppWithArgs(\"\"); } }")]
    [InlineData("class Q { void M() { var x = new System.Collections.Generic.List<int>(); x.Add(1); } }")]
    [InlineData("using System.Reflection; class Q { void M() { foreach (Type t in typeof(Q).Assembly.GetTypes()) { foreach (MethodInfo m in t.GetMethods()) { } } } }")]
    [InlineData("class Q { void M(FlaUI.Core.AutomationElements.Button b) { b.Invoke(); } }")]
    public void LegitimateShapesPassTheGuard(string snippet)
    {
        Assert.Empty(LaunchGuard.FindViolations(snippet, "clean.cs"));
    }

    [Theory]
    [InlineData("class Q { void M() { System.Diagnostics.Process.Start(\"x\"); } }", "tests/UI/UiLaunch.cs", true)]
    [InlineData("class Q { void M() { System.Diagnostics.Process.Start(\"x\"); } }", "tests/UI/MyUiLaunch.cs", false)]
    [InlineData("class Q { void M() { System.Diagnostics.Process.Start(\"x\"); } }", "tests/UI/Sub/Helper.cs", false)]
    public void ExemptionAppliesOnlyToTheSanctionedPath(string snippet, string fileName, bool clean)
    {
        ArgumentNullException.ThrowIfNull(fileName);
        if (clean)
        {
            Assert.Empty(LaunchGuard.FindViolations(snippet, fileName));
        }
        else
        {
            Assert.NotEmpty(LaunchGuard.FindViolations(snippet, fileName));
        }
    }

    [Fact]
    public void LiveTreeScansClean()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null && !Directory.Exists(Path.Combine(dir, "tests", "UI")))
        {
            dir = Path.GetDirectoryName(dir);
        }

        Assert.NotNull(dir);
        var failures = new List<string>();
        foreach (string file in Directory.EnumerateFiles(Path.Combine(dir!, "tests", "UI"), "*.cs", SearchOption.AllDirectories))
        {
            string rel = Path.GetRelativePath(dir!, file).Replace(Path.DirectorySeparatorChar, '/');
            foreach (string violation in LaunchGuard.FindViolations(File.ReadAllText(file), rel))
            {
                failures.Add(violation);
            }
        }

        Assert.Empty(failures);
    }
}
