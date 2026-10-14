using System.Reflection;
using System.Text.RegularExpressions;
using Xunit;

namespace UI;

// Pins the golden contract (UiGolden, operator decision 2026-10-14): a
// capture committed to resources/baseline/app/ is a regression test, not a
// file nobody reads; every golden test is tagged so the section gate's
// Visual=Golden filter finds it; and every golden test is focus-free, so
// that filter can run in every section without taking the screen.
[Collection("UI tests")]
public sealed partial class GoldenInventoryTests
{
    [Fact]
    public void EveryCommittedGoldenHasATestAndReachesTheOutput()
    {
        string root = BindingManifestTests.RepoRoot();
        string sources = string.Join("\n", Directory.GetFiles(Path.Combine(root, "tests", "UI"), "*.cs")
            .Where(f => !f.EndsWith("UiGolden.cs", StringComparison.Ordinal))
            .Select(File.ReadAllText));
        var called = new HashSet<string>(AssertMatchesName().Matches(sources).Select(m => m.Groups[1].Value), StringComparer.Ordinal);

        var problems = new List<string>();
        foreach (string file in Directory.GetFiles(Path.Combine(root, "resources", "baseline", "app"), "*.png"))
        {
            string name = Path.GetFileNameWithoutExtension(file);
            if (name.EndsWith("-evidence", StringComparison.Ordinal))
            {
                continue;
            }

            if (!called.Contains(name))
            {
                problems.Add($"{name}.png has no UiGolden.AssertMatches(..., \"{name}\", ...) test");
            }

            if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "goldens", $"{name}.png")))
            {
                problems.Add($"{name}.png is not copied to the test output (UI.csproj goldens item)");
            }
        }

        Assert.True(problems.Count == 0, string.Join("; ", problems));
    }

    [Fact]
    public void EveryGoldenComparisonIsATaggedTest()
    {
        string root = BindingManifestTests.RepoRoot();
        int calls = Directory.GetFiles(Path.Combine(root, "tests", "UI"), "*.cs")
            .Where(f => !f.EndsWith("UiGolden.cs", StringComparison.Ordinal))
            .Sum(f => AssertMatchesName().Count(File.ReadAllText(f)));
        int tagged = GoldenTests().Count();
        Assert.True(calls == tagged, $"{calls} UiGolden.AssertMatches call sites but {tagged} tests carry [Trait(\"{UiGolden.TraitName}\", \"{UiGolden.TraitValue}\")]: tag each golden test once");
    }

    [Fact]
    public void EveryGoldenTestIsFocusFree()
    {
        var fenced = GoldenTests()
            .Where(m => m.GetCustomAttributes().Any(a => a is InteractiveFactAttribute or InteractiveTheoryAttribute or HookFactAttribute or PrimaryFactAttribute)
                || Traits(m).Any(t => t.Name == "Category" && t.Value is "Interactive" or "Primary"))
            .Select(m => $"{m.DeclaringType?.Name}.{m.Name}")
            .ToList();
        Assert.True(fenced.Count == 0, $"Golden tests must be focus-free so every section gate runs them: {string.Join(", ", fenced)}");
    }

    static IEnumerable<MethodInfo> GoldenTests() =>
        typeof(GoldenInventoryTests).Assembly.GetTypes()
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            .Where(m => Traits(m).Any(t => t.Name == UiGolden.TraitName && t.Value == UiGolden.TraitValue));

    static IEnumerable<(string? Name, string? Value)> Traits(MethodInfo method) =>
        method.GetCustomAttributesData()
            .Where(a => a.AttributeType.Name == nameof(TraitAttribute) && a.ConstructorArguments.Count == 2)
            .Select(a => (a.ConstructorArguments[0].Value?.ToString(), a.ConstructorArguments[1].Value?.ToString()));

    [GeneratedRegex("""UiGolden\.AssertMatches\([^,]+,\s*"([^"]+)"\s*,""")]
    private static partial Regex AssertMatchesName();
}
