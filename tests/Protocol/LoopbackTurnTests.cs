using System.Text.Json.Nodes;
using Xunit;

namespace ScratchPad.Protocol.Tests;

// D00 T02 §4 item 1: a full prompt turn against the scripted fake agent.
public sealed class LoopbackTurnTests
{
    private static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task ScriptedPromptTurnCompletes()
    {
        await using var client = await AcpTestClient.StartAsync("prompt-turn.json");

        JsonObject init = await client.ExchangeAsync("initialize", new JsonObject { ["protocolVersion"] = 1 }, ReadTimeout);
        Assert.Equal(1, init["result"]?["protocolVersion"]?.GetValue<int>());
        Assert.NotNull(init["result"]?["agentCapabilities"]);

        JsonObject created = await client.ExchangeAsync("session/new", new JsonObject { ["cwd"] = Path.GetTempPath(), ["mcpServers"] = new JsonArray() }, ReadTimeout);
        Assert.Equal("sess_loopback_001", created["result"]?["sessionId"]?.GetValue<string>());

        long promptId = await client.SendRequestAsync("session/prompt", new JsonObject
        {
            ["sessionId"] = "sess_loopback_001",
            ["prompt"] = new JsonArray { new JsonObject { ["type"] = "text", ["text"] = "hello" } },
        });
        var text = new System.Text.StringBuilder();
        int chunks = 0;
        while (true)
        {
            JsonObject message = await client.ReadAsync(ReadTimeout);
            if (message["id"]?.GetValue<long>() == promptId)
            {
                Assert.Equal("end_turn", message["result"]?["stopReason"]?.GetValue<string>());
                break;
            }
            Assert.Equal("session/update", message["method"]?.GetValue<string>());
            Assert.Equal("agent_message_chunk", message["params"]?["update"]?["sessionUpdate"]?.GetValue<string>());
            text.Append(message["params"]?["update"]?["content"]?["text"]?.GetValue<string>());
            chunks++;
        }

        Assert.Equal(2, chunks);
        Assert.Equal("Hello from the loopback agent. This turn is fully scripted.", text.ToString());
        Assert.Equal(0, client.SkippedLineCount);
    }
}
