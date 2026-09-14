// Scripted fake ACP agent over stdio. Test-only fixture owned by D00 T02 §4.
// Speaks newline-delimited JSON-RPC 2.0: https://agentclientprotocol.com/protocol/v1/transports
// Method shapes: https://agentclientprotocol.com/protocol/v1/schema
using System.Text.Json;
using System.Text.Json.Nodes;

var options = LoopbackOptions.Parse(args);
JsonObject script;
try
{
    script = JsonNode.Parse(File.ReadAllText(options.ScriptPath))!.AsObject();
}
catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
{
    Console.Error.WriteLine($"acp-loopback: cannot load script '{options.ScriptPath}': {ex.Message}");
    return 3;
}
string sessionId = script["sessionId"]?.GetValue<string>() ?? "sess_loopback_001";
string[] chunks = script["chunks"]?.AsArray().Select(n => n!.GetValue<string>()).ToArray() ?? [];
string stopReason = script["stopReason"]?.GetValue<string>() ?? "end_turn";

bool garbageEmitted = false;
string? line;
while ((line = Console.In.ReadLine()) != null)
{
    if (string.IsNullOrWhiteSpace(line))
    {
        continue;
    }
    JsonObject request;
    try
    {
        request = JsonNode.Parse(line)!.AsObject();
    }
    catch (JsonException ex)
    {
        // Loud failure: stderr plus a nonzero exit, and nothing but valid ACP on stdout.
        Console.Error.WriteLine($"acp-loopback: rejected malformed JSON: {ex.Message}");
        return 2;
    }
    string? version = request["jsonrpc"]?.GetValueKind() == JsonValueKind.String ? request["jsonrpc"]!.GetValue<string>() : null;
    string? name = request["method"]?.GetValueKind() == JsonValueKind.String ? request["method"]!.GetValue<string>() : null;
    if (version != "2.0" || name is null)
    {
        Console.Error.WriteLine($"acp-loopback: rejected envelope violation (need jsonrpc 2.0 + method): {line}");
        return 2;
    }
    string method = name;
    JsonNode? id = request["id"];
    JsonNode? paramsNode = request["params"];
    if (paramsNode is not null && paramsNode is not JsonObject)
    {
        Console.Error.WriteLine($"acp-loopback: rejected non-object params for {method}: {line}");
        return 2;
    }
    JsonObject? error = ValidateParams(method, (JsonObject?)paramsNode);
    if (error is not null)
    {
        Console.Error.WriteLine($"acp-loopback: rejected invalid params for {method}: {error["message"]}");
        if (id is not null)
        {
            Write(new JsonObject { ["jsonrpc"] = "2.0", ["id"] = JsonNode.Parse(id.ToJsonString()), ["error"] = error });
        }
        continue;
    }
    if (id is null)
    {
        // Client notification (e.g. session/cancel): validated, no response owed.
        continue;
    }
    if (options.DropMethod == method)
    {
        Console.Error.WriteLine($"acp-loopback: fault drop armed, ignoring {method} id {id}");
        continue;
    }
    if (options.EmitGarbage && !garbageEmitted)
    {
        garbageEmitted = true;
        Console.Out.WriteLine("{oops this is not json");
        Console.Out.Flush();
    }
    Dispatch(method, id, (JsonObject?)paramsNode ?? new JsonObject());
}
return 0;

void Dispatch(string method, JsonNode id, JsonObject @params)
{
    switch (method)
    {
        case "initialize":
            Write(new JsonObject
            {
                ["jsonrpc"] = "2.0",
                ["id"] = Clone(id),
                ["result"] = new JsonObject
                {
                    ["protocolVersion"] = 1,
                    // AgentCapabilities default verbatim from the v1 schema docs: no capabilities claimed.
                    ["agentCapabilities"] = JsonNode.Parse("""{"loadSession":false,"promptCapabilities":{"image":false,"audio":false,"embeddedContext":false},"mcpCapabilities":{"http":false,"sse":false},"sessionCapabilities":{},"auth":{}}"""),
                },
            });
            break;
        case "session/new":
            Write(new JsonObject
            {
                ["jsonrpc"] = "2.0",
                ["id"] = Clone(id),
                ["result"] = new JsonObject { ["sessionId"] = sessionId },
            });
            break;
        case "session/prompt":
            int n = 0;
            foreach (string chunk in chunks)
            {
                if (options.ChunkDelayMs > 0)
                {
                    Thread.Sleep(options.ChunkDelayMs);
                }
                Write(new JsonObject
                {
                    ["jsonrpc"] = "2.0",
                    ["method"] = "session/update",
                    ["params"] = new JsonObject
                    {
                        ["sessionId"] = sessionId,
                        ["update"] = new JsonObject
                        {
                            ["sessionUpdate"] = "agent_message_chunk",
                            ["content"] = new JsonObject { ["type"] = "text", ["text"] = chunk },
                        },
                    },
                });
                n++;
            }
            if (options.ChunkDelayMs > 0)
            {
                Thread.Sleep(options.ChunkDelayMs);
            }
            Write(new JsonObject
            {
                ["jsonrpc"] = "2.0",
                ["id"] = Clone(id),
                ["result"] = new JsonObject { ["stopReason"] = stopReason },
            });
            Console.Error.WriteLine($"acp-loopback: prompt turn done, {n} chunks, stopReason {stopReason}");
            break;
        default:
            Write(new JsonObject
            {
                ["jsonrpc"] = "2.0",
                ["id"] = Clone(id),
                ["error"] = new JsonObject { ["code"] = -32601, ["message"] = $"Method not found: {method}" },
            });
            break;
    }
}

void Write(JsonObject message)
{
    Console.Out.WriteLine(message.ToJsonString(new JsonSerializerOptions { WriteIndented = false }));
    Console.Out.Flush();
}

JsonNode Clone(JsonNode node) => JsonNode.Parse(node.ToJsonString())!;

// Structural validation coded from the v1 schema (schema.md): required params per method.
// Returns a JSON-RPC error object when the params violate the schema, else null.
JsonObject? ValidateParams(string method, JsonObject? @params) => method switch
{
    "initialize" when @params?["protocolVersion"]?.GetValueKind() != JsonValueKind.Number
        => Err(-32602, "initialize params need numeric protocolVersion"),
    "session/new" when @params?["cwd"]?.GetValue<string>() is not string
        => Err(-32602, "session/new params need string cwd"),
    "session/prompt" when @params?["sessionId"]?.GetValue<string>() is not string
        => Err(-32602, "session/prompt params need string sessionId"),
    "session/prompt" when @params?["prompt"] is not JsonArray
        => Err(-32602, "session/prompt params need array prompt"),
    _ => null,
};

JsonObject Err(int code, string message) => new() { ["code"] = code, ["message"] = message };

sealed record LoopbackOptions(string ScriptPath, bool EmitGarbage, string? DropMethod, int ChunkDelayMs)
{
    public static LoopbackOptions Parse(string[] args)
    {
        string? script = null;
        bool garbage = false;
        string? drop = null;
        int delay = 0;
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--script" when i + 1 < args.Length:
                    script = args[++i];
                    break;
                case "--emit-garbage":
                    garbage = true;
                    break;
                case "--drop" when i + 1 < args.Length:
                    drop = args[++i];
                    break;
                case "--chunk-delay-ms" when i + 1 < args.Length && int.TryParse(args[i + 1], out int ms):
                    delay = ms;
                    i++;
                    break;
                default:
                    Console.Error.WriteLine($"acp-loopback: bad argument '{args[i]}'");
                    Environment.Exit(3);
                    break;
            }
        }
        if (script is null)
        {
            Console.Error.WriteLine("acp-loopback: missing required --script <path>");
            Environment.Exit(3);
        }
        return new LoopbackOptions(script!, garbage, drop, delay);
    }
}
