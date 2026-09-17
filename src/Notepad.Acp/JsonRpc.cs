using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Notepad.Acp;

// JSON-RPC 2.0 message layer, owned by D03 T01 §1. Codec plus envelope
// validation plus id correlation; the stdio byte mover is §2's.
public abstract record JsonRpcMessage;

public sealed record JsonRpcRequestMessage(JsonRpcId Id, string Method, JsonElement? Params) : JsonRpcMessage;

public sealed record JsonRpcNotificationMessage(string Method, JsonElement? Params) : JsonRpcMessage;

public sealed record JsonRpcResponseMessage(JsonRpcId Id, JsonElement? Result, JsonRpcErrorDetail? Error) : JsonRpcMessage;

public sealed record JsonRpcErrorDetail(int Code, string Message, JsonElement? Data);

// What receipt returns instead of throwing: transport data is untrusted,
// so every violation shape arrives here with its JSON-RPC code.
public sealed record JsonRpcFault(int Code, string Message);

public sealed record DecodeResult(JsonRpcMessage? Message, JsonRpcFault? Fault)
{
    public bool Success => Message is not null;

    public static DecodeResult Ok(JsonRpcMessage message)
    {
        ArgumentNullException.ThrowIfNull(message);
        return new(message, null);
    }

    public static DecodeResult Fail(int code, string message)
    {
        ArgumentNullException.ThrowIfNull(message);
        return new(null, new JsonRpcFault(code, message));
    }
}

public static class RpcErrorCodes
{
    public const int ParseError = -32700;
    public const int InvalidRequest = -32600;
    public const int MethodNotFound = -32601;
    public const int InvalidParams = -32602;
    public const int InternalError = -32603;
}

// Request ids: integers we generate, strings agents may send, null only on
// responses whose request could not be identified. Fractional numbers are
// rejected: no peer sends them and they break value equality.
public readonly record struct JsonRpcId
{
    private readonly string? text;
    private readonly long number;
    private readonly byte kind;

    private JsonRpcId(string? text, long number, byte kind)
    {
        this.text = text;
        this.number = number;
        this.kind = kind;
    }

    public static JsonRpcId Null => default;

    public static JsonRpcId FromNumber(long value) => new(null, value, 1);

    public static JsonRpcId FromString(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return new(value, 0, 2);
    }

    public bool IsNull => kind == 0;

    public override string ToString() => kind switch
    {
        1 => number.ToString("D", CultureInfo.InvariantCulture),
        2 => text ?? string.Empty,
        _ => "null",
    };

    internal void WriteValue(Utf8JsonWriter writer)
    {
        ArgumentNullException.ThrowIfNull(writer);
        switch (kind)
        {
            case 1:
                writer.WriteNumberValue(number);
                break;
            case 2:
                writer.WriteStringValue(text);
                break;
            default:
                writer.WriteNullValue();
                break;
        }
    }
}

public static class JsonRpc
{
    public static string EncodeRequest(JsonRpcId id, string method, JsonNode? parameters = null)
    {
        ArgumentNullException.ThrowIfNull(method);
        if (id.IsNull)
        {
            throw new ArgumentException("Request ids must not be null.", nameof(id));
        }

        if (method.Length == 0)
        {
            throw new ArgumentException("Method must not be empty.", nameof(method));
        }

        ValidateParameters(parameters);
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);
        writer.WriteStartObject();
        writer.WriteString("jsonrpc", "2.0");
        writer.WritePropertyName("id");
        id.WriteValue(writer);
        writer.WriteString("method", method);
        if (parameters is not null)
        {
            writer.WritePropertyName("params");
            parameters.WriteTo(writer);
        }

        writer.WriteEndObject();
        writer.Flush();
        return NoNewlines(Encoding.UTF8.GetString(stream.ToArray()));
    }

    public static string EncodeNotification(string method, JsonNode? parameters = null)
    {
        ArgumentNullException.ThrowIfNull(method);
        if (method.Length == 0)
        {
            throw new ArgumentException("Method must not be empty.", nameof(method));
        }

        ValidateParameters(parameters);
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);
        writer.WriteStartObject();
        writer.WriteString("jsonrpc", "2.0");
        writer.WriteString("method", method);
        if (parameters is not null)
        {
            writer.WritePropertyName("params");
            parameters.WriteTo(writer);
        }

        writer.WriteEndObject();
        writer.Flush();
        return NoNewlines(Encoding.UTF8.GetString(stream.ToArray()));
    }

    public static string EncodeResponse(JsonRpcId id, JsonNode result)
    {
        ArgumentNullException.ThrowIfNull(result);
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);
        writer.WriteStartObject();
        writer.WriteString("jsonrpc", "2.0");
        writer.WritePropertyName("id");
        id.WriteValue(writer);
        writer.WritePropertyName("result");
        result.WriteTo(writer);
        writer.WriteEndObject();
        writer.Flush();
        return NoNewlines(Encoding.UTF8.GetString(stream.ToArray()));
    }

    public static string EncodeErrorResponse(JsonRpcId id, int code, string message, JsonNode? data = null)
    {
        ArgumentNullException.ThrowIfNull(message);
        if (message.Length == 0)
        {
            throw new ArgumentException("Error messages must not be empty.", nameof(message));
        }

        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream);
        writer.WriteStartObject();
        writer.WriteString("jsonrpc", "2.0");
        writer.WritePropertyName("id");
        id.WriteValue(writer);
        writer.WriteStartObject("error");
        writer.WriteNumber("code", code);
        writer.WriteString("message", message);
        if (data is not null)
        {
            writer.WritePropertyName("data");
            data.WriteTo(writer);
        }

        writer.WriteEndObject();
        writer.WriteEndObject();
        writer.Flush();
        return NoNewlines(Encoding.UTF8.GetString(stream.ToArray()));
    }

    private static void ValidateParameters(JsonNode? parameters)
    {
        if (parameters is not null && parameters is not JsonObject and not JsonArray)
        {
            throw new ArgumentException("Params must be an object or an array.", nameof(parameters));
        }
    }

    private static string NoNewlines(string message)
    {
        if (message.Contains('\r', StringComparison.Ordinal) || message.Contains('\n', StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Encoded messages must not contain newlines.");
        }

        return message;
    }

    // Receipt never throws on transport data: malformed lines, batches, and
    // envelope violations all return faults. Only a null argument (caller
    // misuse, not transport data) throws.
    public static DecodeResult DecodeLine(string line)
    {
        ArgumentNullException.ThrowIfNull(line);
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(line);
        }
        catch (JsonException)
        {
            return DecodeResult.Fail(RpcErrorCodes.ParseError, "Malformed JSON.");
        }

        using (document)
        {
            JsonElement root = document.RootElement;
            if (root.ValueKind == JsonValueKind.Array)
            {
                return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Batch requests are not supported.");
            }

            if (root.ValueKind != JsonValueKind.Object)
            {
                return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Messages must be JSON objects.");
            }

            if (!root.TryGetProperty("jsonrpc", out JsonElement version)
                || version.ValueKind != JsonValueKind.String
                || version.GetString() != "2.0")
            {
                return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Missing or invalid jsonrpc version.");
            }

            if (root.TryGetProperty("method", out JsonElement methodElement))
            {
                return DecodeCall(root, methodElement);
            }

            return DecodeResponse(root);
        }
    }

    private static DecodeResult DecodeCall(JsonElement root, JsonElement methodElement)
    {
        if (methodElement.ValueKind != JsonValueKind.String
            || methodElement.GetString() is not { Length: > 0 } method)
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Method must be a non-empty string.");
        }

        JsonElement? parameters = null;
        if (root.TryGetProperty("params", out JsonElement paramsElement))
        {
            if (paramsElement.ValueKind is not (JsonValueKind.Object or JsonValueKind.Array))
            {
                return DecodeResult.Fail(RpcErrorCodes.InvalidParams, "Params must be an object or an array.");
            }

            parameters = paramsElement.Clone();
        }

        if (root.TryGetProperty("id", out JsonElement idElement))
        {
            if (!TryReadId(idElement, out JsonRpcId id) || id.IsNull)
            {
                return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Request ids must be strings or integers.");
            }

            return DecodeResult.Ok(new JsonRpcRequestMessage(id, method, parameters));
        }

        return DecodeResult.Ok(new JsonRpcNotificationMessage(method, parameters));
    }

    private static DecodeResult DecodeResponse(JsonElement root)
    {
        if (!root.TryGetProperty("id", out JsonElement idElement))
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Responses must carry an id.");
        }

        if (!TryReadId(idElement, out JsonRpcId id))
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Response ids must be strings, integers, or null.");
        }

        bool hasResult = root.TryGetProperty("result", out JsonElement result);
        bool hasError = root.TryGetProperty("error", out JsonElement error);
        if (hasResult == hasError)
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Responses carry exactly one of result or error.");
        }

        if (hasError)
        {
            return DecodeError(id, error);
        }

        return DecodeResult.Ok(new JsonRpcResponseMessage(id, result.Clone(), null));
    }

    private static DecodeResult DecodeError(JsonRpcId id, JsonElement error)
    {
        if (error.ValueKind != JsonValueKind.Object)
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Errors must be objects.");
        }

        if (!error.TryGetProperty("code", out JsonElement codeElement)
            || codeElement.ValueKind != JsonValueKind.Number
            || !codeElement.TryGetInt32(out int code))
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Errors carry an integer code.");
        }

        if (!error.TryGetProperty("message", out JsonElement messageElement)
            || messageElement.ValueKind != JsonValueKind.String
            || messageElement.GetString() is not string message)
        {
            return DecodeResult.Fail(RpcErrorCodes.InvalidRequest, "Errors carry a string message.");
        }

        JsonElement? data = error.TryGetProperty("data", out JsonElement dataElement) ? dataElement.Clone() : null;
        return DecodeResult.Ok(new JsonRpcResponseMessage(id, null, new JsonRpcErrorDetail(code, message, data)));
    }

    private static bool TryReadId(JsonElement element, out JsonRpcId id)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Number when element.TryGetInt64(out long number):
                id = JsonRpcId.FromNumber(number);
                return true;
            case JsonValueKind.String when element.GetString() is string text:
                id = JsonRpcId.FromString(text);
                return true;
            case JsonValueKind.Null:
                id = JsonRpcId.Null;
                return true;
            default:
                id = JsonRpcId.Null;
                return false;
        }
    }
}

// Correlates responses with waiting callers across threads. Timeouts are
// §6's; this registry only routes what arrives.
public sealed class PendingRequestRegistry
{
    private readonly ConcurrentDictionary<JsonRpcId, TaskCompletionSource<JsonRpcResponseMessage>> pending = new();
    private long nextId;

    public int PendingCount => pending.Count;

    public JsonRpcId NextId() => JsonRpcId.FromNumber(Interlocked.Increment(ref nextId));

    public Task<JsonRpcResponseMessage> Register(JsonRpcId id)
    {
        if (id.IsNull)
        {
            throw new ArgumentException("Null ids cannot wait for responses.", nameof(id));
        }

        var completion = new TaskCompletionSource<JsonRpcResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!pending.TryAdd(id, completion))
        {
            throw new InvalidOperationException($"Duplicate request id: {id}.");
        }

        return completion.Task;
    }

    public bool Complete(JsonRpcResponseMessage response)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (response.Id.IsNull)
        {
            return false;
        }

        if (!pending.TryRemove(response.Id, out TaskCompletionSource<JsonRpcResponseMessage>? completion))
        {
            return false;
        }

        return completion.TrySetResult(response);
    }
}
