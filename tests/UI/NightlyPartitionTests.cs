using System.Reflection;
using Xunit;
using Xunit.Abstractions;

namespace UI;

[Collection("UI tests")]
public sealed class NightlyPartitionTests
{
    private readonly ITestOutputHelper _output;

    public NightlyPartitionTests(ITestOutputHelper output)
    {
        _output = output;
    }

    [Fact]
    public void EveryUiTestBelongsToExactlyOneNightlyLeg()
    {
        // Exhaustive partition (D00 T02 §15, D00-T02-S13-PR11): every UI
        // test method lands in exactly one nightly leg by its Category
        // trait (Interactive, Primary, or neither for Run A), and the
        // union covers the suite, so a future trait change cannot
        // silently drop coverage. Traits are method-level, so the check
        // counts methods, not theory cases. The partition line below is
        // the green-run quote (it lands in the trx output).
        var both = new List<string>();
        int runA = 0;
        int runB = 0;
        int interactive = 0;
        foreach (Type type in typeof(NightlyPartitionTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                if (!method.GetCustomAttributes().Any(a => a is FactAttribute))
                {
                    continue;
                }

                var categories = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Where(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category")
                    .Select(a => a.ConstructorArguments[1].Value?.ToString())
                    .ToHashSet(StringComparer.Ordinal);
                bool isInteractive = categories.Contains("Interactive");
                bool isPrimary = categories.Contains("Primary");
                if (isInteractive && isPrimary)
                {
                    both.Add($"{type.Name}.{method.Name}");
                    continue;
                }

                if (isInteractive)
                {
                    interactive++;
                }
                else if (isPrimary)
                {
                    runB++;
                }
                else
                {
                    runA++;
                }
            }
        }

        int total = runA + runB + interactive;
        _output.WriteLine($"partition: run-a={runA} run-b={runB} interactive={interactive} total={total}");
        Assert.True(both.Count == 0, $"Tests in two legs at once: {string.Join(", ", both)}");
        Assert.True(total > 0, "Partition found no test methods; discovery is broken, not green.");
    }
}
