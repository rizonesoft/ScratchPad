using Xunit;

namespace UI;

// The operator-idle gate (UiOperatorIdle) is pure apart from its probe and
// sleep, so these drive it with scripted idle readings and a recording
// sleep: nothing waits for real and nothing reads the live input clock.
[Collection("UI tests")]
public sealed class OperatorIdleTests
{
    static readonly TimeSpan Required = TimeSpan.FromSeconds(60);
    static readonly TimeSpan MaxWait = TimeSpan.FromSeconds(900);
    static readonly int[] TypingThenAway = [10, 2, 61];

    [Fact]
    public void IdleOperatorPassesWithoutWaiting()
    {
        var slept = new List<TimeSpan>();
        string? skip = UiOperatorIdle.WaitForIdle(() => TimeSpan.FromSeconds(75), Required, MaxWait, slept.Add);
        Assert.Null(skip);
        Assert.Empty(slept);
    }

    [Fact]
    public void ActiveOperatorIsWaitedOutThenPasses()
    {
        // 10 s idle, then typing resets it to 2 s, then the operator leaves.
        var readings = new Queue<TimeSpan>(TypingThenAway.Select(s => TimeSpan.FromSeconds(s)));
        var slept = new List<TimeSpan>();
        string? skip = UiOperatorIdle.WaitForIdle(() => readings.Dequeue(), Required, MaxWait, slept.Add);
        Assert.Null(skip);
        Assert.Equal(new[] { TimeSpan.FromSeconds(50), TimeSpan.FromSeconds(58) }, slept);
    }

    [Fact]
    public void BusyOperatorSkipsAfterTheMaxWaitAndNeverSleepsPastIt()
    {
        var slept = new List<TimeSpan>();
        string? skip = UiOperatorIdle.WaitForIdle(() => TimeSpan.Zero, Required, TimeSpan.FromSeconds(150), slept.Add);
        Assert.NotNull(skip);
        Assert.StartsWith("Operator active", skip, StringComparison.Ordinal);
        Assert.Equal(TimeSpan.FromSeconds(150), slept.Aggregate(TimeSpan.Zero, (a, b) => a + b));
    }

    [Fact]
    public void UnreadableIdleTimeFailsClosed()
    {
        string? skip = UiOperatorIdle.WaitForIdle(() => null, Required, MaxWait, _ => { });
        Assert.NotNull(skip);
        Assert.Contains("unreadable", skip, StringComparison.Ordinal);
    }

    [Fact]
    public void ZeroIdleRequirementDisablesTheGate()
    {
        string? skip = UiOperatorIdle.WaitForIdle(() => TimeSpan.Zero, TimeSpan.Zero, MaxWait, _ => throw new InvalidOperationException("must not sleep"));
        Assert.Null(skip);
    }

    [Theory]
    [InlineData("30", 30)]
    [InlineData("0", 0)]
    [InlineData("", 60)]
    [InlineData("-5", 60)]
    [InlineData("soon", 60)]
    public void IdleSecondsParseWithTheDefaultAsFallback(string value, int expected)
    {
        Assert.Equal(TimeSpan.FromSeconds(expected), UiOperatorIdle.ReadSeconds(value, UiOperatorIdle.DefaultIdle));
    }

    [Fact]
    public void UnforcedRunsNeverConsultTheIdleGate()
    {
        // Outside the window the window skip answers; inside it an unforced
        // run (a focus-free gate run at night) must not stall on idle.
        string? force = Environment.GetEnvironmentVariable(UiQuietHours.ForceVariable);
        string? window = Environment.GetEnvironmentVariable(UiQuietHours.WindowVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiQuietHours.ForceVariable, null);
            Environment.SetEnvironmentVariable(UiQuietHours.WindowVariable, null);
            Assert.StartsWith("Outside the foreground window", UiQuietHours.SkipUnlessForegroundFree(new DateTime(2026, 10, 14, 12, 0, 0)), StringComparison.Ordinal);
            Assert.Null(UiQuietHours.SkipUnlessForegroundFree(new DateTime(2026, 10, 14, 3, 0, 0)));
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiQuietHours.ForceVariable, force);
            Environment.SetEnvironmentVariable(UiQuietHours.WindowVariable, window);
        }
    }

    [Fact]
    public void ChildTestRunsNeverReGateButCallersStillWin()
    {
        var plain = UiLaunch.ChildEnvironment(new Dictionary<string, string> { ["SCRATCHPAD_TEST_MUTATE"] = "x" });
        Assert.Equal("0", plain[UiOperatorIdle.IdleVariable]);
        Assert.Equal("x", plain["SCRATCHPAD_TEST_MUTATE"]);
        var driven = UiLaunch.ChildEnvironment(new Dictionary<string, string> { [UiOperatorIdle.IdleVariable] = "30" });
        Assert.Equal("30", driven[UiOperatorIdle.IdleVariable]);
    }

    [Fact]
    public void ListingNeverWaits()
    {
        string? prior = Environment.GetEnvironmentVariable(GatedTheoryAttribute.ListingVariable);
        try
        {
            Environment.SetEnvironmentVariable(GatedTheoryAttribute.ListingVariable, "1");
            Assert.Null(UiOperatorIdle.SkipUnlessIdle());
        }
        finally
        {
            Environment.SetEnvironmentVariable(GatedTheoryAttribute.ListingVariable, prior);
        }
    }
}
