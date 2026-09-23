using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 4: explicit geometry wins over background
// seeding, in every seeding shape. Full, partial, and
// degenerate rects survive SeedSettings untouched under
// SCRATCHPAD_BACKGROUND=1; the string-seeded path
// (SeedSettingsFile) applies the same rule. Default-valued
// explicit rects (50,50) map off-screen like untouched
// defaults (R1-F3: the store carries no explicitness flag,
// and background births must stay off-screen), and
// foreground defaults stay at the cascade origin.
[Collection("UI tests")]
public sealed class SeedPrecedenceTests
{
    [Fact]
    public void FullExplicitGeometryWins()
    {
        WithBackground(() =>
        {
            UiLaunch.SeedSettings(new ShellSettings { X = 100, Y = 200, WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            Assert.Equal(100, loaded.X);
            Assert.Equal(200, loaded.Y);
        });
    }

    [Fact]
    public void ExplicitDefaultValuedGeometrySeedsOffScreen()
    {
        // Degenerate explicit (D00 T02 §18 R1-F3): values equal
        // to the 50,50 defaults map off-screen in background
        // mode, exactly like untouched defaults. The store
        // carries no explicitness flag, and background births
        // must stay off-screen, so the seeder maps rather than
        // honors an on-screen value here; the mapping is
        // protective, and this pin fails a future leak.
        WithBackground(() =>
        {
            UiLaunch.SeedSettings(new ShellSettings { X = 50, Y = 50, WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            UiLaunch.ScreenBounds screen = UiLaunch.ReadVirtualScreen();
            Assert.False(
                UiLaunch.WindowIntersects(screen, loaded.X, loaded.Y, loaded.Width, loaded.Height),
                $"seeded {loaded.X},{loaded.Y} intersects the virtual screen");
        });
    }

    [Fact]
    public void PartialExplicitGeometryWins()
    {
        WithBackground(() =>
        {
            UiLaunch.SeedSettings(new ShellSettings { X = 100, WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            Assert.Equal(100, loaded.X);
            Assert.Equal(50, loaded.Y);
        });
    }

    [Fact]
    public void MalformedExplicitGeometryWins()
    {
        // Degenerate but explicit: the seeder does not second-guess
        // caller geometry, so negative origins survive seeding.
        WithBackground(() =>
        {
            UiLaunch.SeedSettings(new ShellSettings { X = -50, Y = -50, WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            Assert.Equal(-50, loaded.X);
            Assert.Equal(-50, loaded.Y);
        });
    }

    [Fact]
    public void StringSeededExplicitGeometryWins()
    {
        WithBackground(() =>
        {
            string path = UiLaunch.SeedSettingsFile(new ShellSettings { X = 300, Y = 400, WhatsNewSeen = true });
            Assert.Equal(ShellSettings.FilePath, path);
            ShellSettings loaded = ShellSettings.Load();
            Assert.Equal(300, loaded.X);
            Assert.Equal(400, loaded.Y);
        });
    }

    [Fact]
    public void UntouchedDefaultsSeedOffScreen()
    {
        WithBackground(() =>
        {
            UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            UiLaunch.ScreenBounds screen = UiLaunch.ReadVirtualScreen();
            Assert.False(
                UiLaunch.WindowIntersects(screen, loaded.X, loaded.Y, loaded.Width, loaded.Height),
                $"seeded {loaded.X},{loaded.Y} intersects the virtual screen");
        });
    }

    [Fact]
    public void ForegroundDefaultsStayAtCascadeOrigin()
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "0");
            UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
            ShellSettings loaded = ShellSettings.Load();
            Assert.Equal(50, loaded.X);
            Assert.Equal(50, loaded.Y);
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }

    static void WithBackground(Action seed)
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
            seed();
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }
}
