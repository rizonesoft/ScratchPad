using System.Globalization;
using System.Reflection;
using Xunit;

namespace UI;

[Collection("UI tests")]
public sealed class QuietHoursTests
{
    [Theory]
    [InlineData("01:59", false)]
    [InlineData("02:00", true)]
    [InlineData("04:30", true)]
    [InlineData("06:49", true)]
    [InlineData("06:50", false)]
    [InlineData("00:00", false)]
    [InlineData("12:00", false)]
    [InlineData("23:59", false)]
    public void DefaultWindowAdmitsOnly0200To0650(string time, bool expected)
    {
        Assert.True(UiQuietHours.TryParseWindow(UiQuietHours.DefaultWindow, out TimeSpan start, out TimeSpan end));
        Assert.Equal(expected, UiQuietHours.IsInWindow(TimeSpan.Parse(time, CultureInfo.InvariantCulture), start, end));
    }

    [Theory]
    [InlineData("22:00-06:00", "23:00", true)]
    [InlineData("22:00-06:00", "05:59", true)]
    [InlineData("22:00-06:00", "06:00", false)]
    [InlineData("22:00-06:00", "12:00", false)]
    [InlineData("22:00-06:00", "21:59", false)]
    public void OvernightWindowWrapsPastMidnight(string window, string time, bool expected)
    {
        ArgumentNullException.ThrowIfNull(window);
        Assert.True(UiQuietHours.TryParseWindow(window, out TimeSpan start, out TimeSpan end));
        Assert.Equal(expected, UiQuietHours.IsInWindow(TimeSpan.Parse(time, CultureInfo.InvariantCulture), start, end));
    }

    [Theory]
    [InlineData("")]
    [InlineData("nope")]
    [InlineData("02:00")]
    [InlineData("02:00-06:50-extra")]
    public void UnparseableWindowFailsToParse(string window)
    {
        ArgumentNullException.ThrowIfNull(window);
        Assert.False(UiQuietHours.TryParseWindow(window, out _, out _));
    }

    [Fact]
    public void ForceVariableAllowsAnyTime()
    {
        string? prior = Environment.GetEnvironmentVariable(UiQuietHours.ForceVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiQuietHours.ForceVariable, "1");
            Assert.True(UiQuietHours.IsAllowed(new DateTime(2026, 9, 17, 12, 0, 0)));
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiQuietHours.ForceVariable, prior);
        }
    }

    [Fact]
    public void EveryGatedTestCarriesTheInteractiveTrait()
    {
        var missing = new List<string>();
        foreach (Type type in typeof(QuietHoursTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                if (!method.GetCustomAttributes().Any(a => a is InteractiveFactAttribute or HookFactAttribute))
                {
                    continue;
                }

                bool fenced = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Any(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category"
                        && a.ConstructorArguments[1].Value?.ToString() == "Interactive");
                if (!fenced)
                {
                    missing.Add($"{type.Name}.{method.Name}");
                }
            }
        }

        Assert.True(missing.Count == 0, $"Missing [Trait(\"Category\", \"Interactive\")]: {string.Join(", ", missing)}");
    }

    [Fact]
    public void EveryInteractiveTraitCarriesAGate()
    {
        // The reverse direction: a test fenced by trait but running under a
        // plain [Fact] would execute in an unfiltered daytime run and take
        // the foreground, so the trait must always pair with its gate.
        var missing = new List<string>();
        foreach (Type type in typeof(QuietHoursTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                bool fenced = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Any(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category"
                        && a.ConstructorArguments[1].Value?.ToString() == "Interactive");
                if (!fenced)
                {
                    continue;
                }

                if (!method.GetCustomAttributes().Any(a => a is InteractiveFactAttribute or HookFactAttribute))
                {
                    missing.Add($"{type.Name}.{method.Name}");
                }
            }
        }

        Assert.True(missing.Count == 0, $"Missing gate on [Trait(\"Category\", \"Interactive\")]: {string.Join(", ", missing)}");
    }

    [Fact]
    public void EveryPrimaryFactCarriesThePrimaryTrait()
    {
        var missing = new List<string>();
        foreach (Type type in typeof(QuietHoursTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                if (!method.GetCustomAttributes().Any(a => a is PrimaryFactAttribute))
                {
                    continue;
                }

                bool placed = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Any(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category"
                        && a.ConstructorArguments[1].Value?.ToString() == "Primary");
                if (!placed)
                {
                    missing.Add($"{type.Name}.{method.Name}");
                }
            }
        }

        Assert.True(missing.Count == 0, $"Missing [Trait(\"Category\", \"Primary\")]: {string.Join(", ", missing)}");
    }

    [Fact]
    public void EveryPrimaryTraitCarriesAGate()
    {
        var missing = new List<string>();
        foreach (Type type in typeof(QuietHoursTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                bool placed = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Any(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category"
                        && a.ConstructorArguments[1].Value?.ToString() == "Primary");
                if (!placed)
                {
                    continue;
                }

                if (!method.GetCustomAttributes().Any(a => a is PrimaryFactAttribute))
                {
                    missing.Add($"{type.Name}.{method.Name}");
                }
            }
        }

        Assert.True(missing.Count == 0, $"Missing gate on [Trait(\"Category\", \"Primary\")]: {string.Join(", ", missing)}");
    }

    [Fact]
    public void PrimarySetSizeIsPinned()
    {
        // Run B pins its population (D00 T02 §15, D00-T02-S13-subagent-A6):
        // a mistagged future test must trip placement policing, never slip
        // into (or out of) the placement run silently. Update the pin when
        // the set changes legitimately, alongside the fingerprint.
        var members = new List<string>();
        foreach (Type type in typeof(QuietHoursTests).Assembly.GetTypes())
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            {
                bool placed = method.GetCustomAttributesData()
                    .Where(a => a.AttributeType.Name == nameof(TraitAttribute))
                    .Any(a => a.ConstructorArguments.Count == 2
                        && a.ConstructorArguments[0].Value?.ToString() == "Category"
                        && a.ConstructorArguments[1].Value?.ToString() == "Primary");
                if (placed)
                {
                    members.Add($"{type.Name}.{method.Name}");
                }
            }
        }

        members.Sort(StringComparer.Ordinal);
        Assert.True(members.Count == 2, $"Primary set size drifted (want 2): {string.Join(", ", members)}");
    }
}
