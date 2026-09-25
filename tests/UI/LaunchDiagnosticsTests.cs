using System.Text.Json;
using FlaUI.Core;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §18 item 7: launch records quote the v1 schema on every
// launch. Redaction pins six shapes; a forced failure quotes all
// seven fields with nulls plus the error; a real launch quotes pid,
// window, monitor, and the seed move.
[Collection("UI tests")]
public sealed class LaunchDiagnosticsTests
{
    [Theory]
    [InlineData("--file x.txt", "--file x.txt")]
    [InlineData("--password hunter2", "--password ***")]
    [InlineData("token=abc123", "token=***")]
    [InlineData("--api-key: \"quoted secret\"", "--api-key: ***")]
    [InlineData("auth hunter2", "auth ***")]
    [InlineData("Bearer abc.def.ghi", "Bearer ***")]
    public void RedactArgsShapes(string args, string expected)
    {
        Assert.Equal(expected, UiLaunchDiagnostics.RedactArgs(args));
    }

    [Fact]
    public void ForcedFailureQuotesAllSeven()
    {
        string missing = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".exe");
        var thrown = Assert.ThrowsAny<Exception>(() => UiLaunch.LaunchAppWithExe(missing, string.Empty));
        Assert.NotNull(thrown);
        JsonElement record = TailRecord(nameof(ForcedFailureQuotesAllSeven));
        Assert.Equal("launch-diagnostics/2", record.GetProperty("schema").GetString());
        Assert.Empty(record.GetProperty("sweep").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, record.GetProperty("pid").ValueKind);
        Assert.Contains("Exception", record.GetProperty("error").GetString(), StringComparison.Ordinal);
        Assert.Equal(JsonValueKind.Null, record.GetProperty("hwnd").ValueKind);
        Assert.Equal(JsonValueKind.Null, record.GetProperty("bounds").ValueKind);
        Assert.Empty(record.GetProperty("hwndLineage").EnumerateArray());
        Assert.Equal("unknown", record.GetProperty("monitor").GetString());
        Assert.Equal("launch-failed", record.GetProperty("move").GetString());
    }

    [Fact]
    public void SuccessRecordQuotesFields()
    {
        string? saved = Environment.GetEnvironmentVariable(UiLaunch.BackgroundVariable);
        try
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, "1");
            UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
            using var app = UiLaunch.LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            Assert.NotNull(window);
            try
            {
                JsonElement record = TailRecord(nameof(SuccessRecordQuotesFields));
                Assert.Equal("launch-diagnostics/2", record.GetProperty("schema").GetString());
                Assert.Equal(app.ProcessId, record.GetProperty("pid").GetInt32());
                // D00 T02 §41 item 8: the record quotes its birth's sweep line
                // (generation, attribution, reasons, and move readbacks).
                long main = window.Properties.NativeWindowHandle.Value.ToInt64();
                var sweep = record.GetProperty("sweep").EnumerateArray().Select(e => e.GetString() ?? string.Empty).ToList();
                Assert.Contains(sweep, l => l.StartsWith($"sweep main=0x{main:X} ", StringComparison.Ordinal) && l.Contains(" gen=", StringComparison.Ordinal) && l.Contains(" skipped=", StringComparison.Ordinal));
                // R3-F3: the delayed pass is in the record, or named missing.
                Assert.Contains(sweep, l => l.StartsWith($"sweep-late main=0x{main:X} ", StringComparison.Ordinal));
                Assert.Equal("seeded-offscreen", record.GetProperty("move").GetString());
                Assert.NotNull(record.GetProperty("hwnd").ValueKind == JsonValueKind.Number
                    ? record.GetProperty("hwnd")
                    : null);
            }
            finally
            {
                CloseAll(app, automation);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable(UiLaunch.BackgroundVariable, saved);
        }
    }

    static JsonElement TailRecord(string testName)
    {
        string path = UiLaunchDiagnostics.LogPath();
        Assert.True(File.Exists(path), $"no diagnostics log at {path}");
        foreach (string line in File.ReadLines(path).Reverse())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            using var document = JsonDocument.Parse(line);
            JsonElement root = document.RootElement.Clone();
            if ((root.GetProperty("test").GetString() ?? string.Empty).EndsWith(":" + testName, StringComparison.Ordinal))
            {
                return root;
            }
        }

        throw new InvalidOperationException($"no record for {testName}");
    }

    [Fact]
    public void PruneOldLaunchesKeepsFresh()
    {
        // C-A1: daily launch logs prune past 30 days like bundles.
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string old = Path.Combine(dir, "launches-20200101.jsonl");
            string fresh = Path.Combine(dir, $"launches-{DateTime.UtcNow:yyyyMMdd}.jsonl");
            string other = Path.Combine(dir, "notes.txt");
            File.WriteAllText(old, "{}");
            File.WriteAllText(fresh, "{}");
            File.WriteAllText(other, "{}");
            UiLaunchDiagnostics.PruneOldLaunches(dir);
            Assert.False(File.Exists(old));
            Assert.True(File.Exists(fresh));
            Assert.True(File.Exists(other));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    static void CloseAll(Application app, UIA3Automation automation)
    {
        foreach (var window in app.GetAllTopLevelWindows(automation))
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
            }
        }

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!app.HasExited && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(100);
        }

        if (!app.HasExited)
        {
            app.Kill();
        }
    }
}
