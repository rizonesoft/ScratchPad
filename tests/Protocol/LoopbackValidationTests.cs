using System.Text.Json.Nodes;
using Xunit;

namespace ScratchPad.Protocol.Tests;

// D00 T02 §4 item 3: the fixture validates incoming messages and fails loudly on violations.
public sealed class LoopbackValidationTests
{
    private static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task PromptMissingSessionIdReturnsInvalidParams()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json");

        // Deliberately malformed: session/prompt without its required sessionId.
        JsonObject response = await client.ExchangeAsync("session/prompt", new JsonObject { ["prompt"] = new JsonArray() }, ReadTimeout);
        Assert.Equal(-32602, response["error"]?["code"]?.GetValue<int>());
    }

    [Fact]
    public async Task UnknownMethodReturnsMethodNotFound()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json");

        JsonObject response = await client.ExchangeAsync("session/definitely-not-real", new JsonObject(), ReadTimeout);
        Assert.Equal(-32601, response["error"]?["code"]?.GetValue<int>());
    }

    [Fact]
    public async Task NonObjectInputRejectedLoudly()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json");

        await client.SendRawAsync("123");
        await client.WaitForExitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(2, client.ExitCode);
        Assert.Contains("rejected non-object message", client.StderrText, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GarbageInputKillsFixtureLoudly()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json");

        await client.SendRawAsync("{oops this is not json");
        await client.WaitForExitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(2, client.ExitCode);
        Assert.Contains("rejected malformed JSON", client.StderrText, StringComparison.Ordinal);
    }
}
