using System.Text.Json.Nodes;
using Xunit;

namespace ScratchPad.Protocol.Tests;

// D00 T02 §4 item 2: each injected fault has a test proving the client survives it.
public sealed class LoopbackFaultTests
{
    private static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task MalformedJsonSkippedAndTurnCompletes()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json", "--emit-garbage");

        JsonObject init = await client.ExchangeAsync("initialize", new JsonObject { ["protocolVersion"] = 1 }, ReadTimeout);
        Assert.Equal(1, init["result"]?["protocolVersion"]?.GetValue<int>());
        Assert.Equal(1, client.SkippedLineCount);
    }

    [Fact]
    public async Task DroppedResponseSurfacesTimeoutInsteadOfHanging()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json", "--drop session/prompt");

        JsonObject created = await client.ExchangeAsync("session/new", new JsonObject { ["cwd"] = Path.GetTempPath(), ["mcpServers"] = new JsonArray() }, ReadTimeout);
        Assert.Equal("sess_loopback_001", created["result"]?["sessionId"]?.GetValue<string>());

        await client.SendRequestAsync("session/prompt", new JsonObject
        {
            ["sessionId"] = "sess_loopback_001",
            ["prompt"] = new JsonArray { new JsonObject { ["type"] = "text", ["text"] = "hello" } },
        });
        await Assert.ThrowsAsync<TimeoutException>(() => client.ReadAsync(TimeSpan.FromSeconds(5)));
        Assert.False(client.HasExited);
    }

    [Fact]
    public async Task SlowStreamTurnStillCompletes()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json", "--chunk-delay-ms 300");

        long promptId = await client.SendRequestAsync("session/prompt", new JsonObject
        {
            ["sessionId"] = "sess_loopback_001",
            ["prompt"] = new JsonArray { new JsonObject { ["type"] = "text", ["text"] = "hello" } },
        });
        int updates = 0;
        while (true)
        {
            JsonObject message = await client.ReadAsync(TimeSpan.FromSeconds(30));
            if (message["id"]?.GetValue<long>() == promptId)
            {
                Assert.Equal("end_turn", message["result"]?["stopReason"]?.GetValue<string>());
                break;
            }
            updates++;
        }
        Assert.Equal(2, updates);
    }
}
