using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// The executable plant for the binding mutation run (D00 T02 §36 item 1,
// §28 R3-F1): a covering-shaped test whose assertion is a constant local
// assigned after the press. It satisfies the static rule and passes
// whatever the chord does, so the mutation run must read it as survived.
// It runs only inside that run (the fenced
// BindingMutationTests.PlantedConstantLocalSurvivesTheMutationRun sets
// SCRATCHPAD_MUTATION_PLANT=1 on the child); everywhere else it reports
// Skipped with that reason, so it never presses a key in the default run.
internal sealed class MutationPlantFactAttribute : FactAttribute
{
    public const string Variable = "SCRATCHPAD_MUTATION_PLANT";

    public MutationPlantFactAttribute()
    {
        if (Environment.GetEnvironmentVariable(Variable) != "1")
        {
            Skip = "Mutation plant: runs only inside the binding mutation run (D00 T02 §36).";
        }
    }
}

[Collection("UI tests")]
public sealed class MutationPlantTests
{
    [MutationPlantFact]
    public void PlantedConstantLocalAssertion()
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        using var app = UiLaunch.LaunchApp();
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        Assert.NotNull(window);
        try
        {
            UiInput.Press(window, VirtualKeyShort.KEY_G, withControl: true, withShift: true);
            int observed = 0;
            Assert.Equal(0, observed);
        }
        finally
        {
            if (!app.HasExited)
            {
                app.Kill();
            }
        }
    }
}
