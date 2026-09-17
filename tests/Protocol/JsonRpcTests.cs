using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Notepad.Acp;
using Xunit;

namespace ScratchPad.Protocol.Tests;

// D03 T01 §1: codec, envelope validation both directions, and id
// correlation. Pure and in-process: no loopback needed at this layer.
public sealed class JsonRpcTests
{
    [Fact]
    public void EncodeRequestRoundTripsThroughDecode()
    {
        var parameters = new JsonObject { ["sessionId"] = "sess_1" };
        string line = JsonRpc.EncodeRequest(JsonRpcId.FromNumber(7), "session/prompt", parameters);
        DecodeResult decoded = JsonRpc.DecodeLine(line);
        Assert.True(decoded.Success);
        var request = Assert.IsType<JsonRpcRequestMessage>(decoded.Message);
        Assert.Equal(JsonRpcId.FromNumber(7), request.Id);
        Assert.Equal("session/prompt", request.Method, StringComparer.Ordinal);
        Assert.Equal("{\"sessionId\":\"sess_1\"}", request.Params?.GetRawText());
    }

    [Fact]
    public void EncodeNotificationHasNoId()
    {
        string line = JsonRpc.EncodeNotification("session/update", new JsonArray { 1, 2 });
        Assert.DoesNotContain("\"id\"", line, StringComparison.Ordinal);
        DecodeResult decoded = JsonRpc.DecodeLine(line);
        var notification = Assert.IsType<JsonRpcNotificationMessage>(decoded.Message);
        Assert.Equal("session/update", notification.Method, StringComparer.Ordinal);
        Assert.Equal("[1,2]", notification.Params?.GetRawText());
    }

    [Fact]
    public void EncodeResponseAndErrorResponsesRoundTrip()
    {
        DecodeResult ok = JsonRpc.DecodeLine(JsonRpc.EncodeResponse(JsonRpcId.FromNumber(3), new JsonObject { ["done"] = true }));
        var response = Assert.IsType<JsonRpcResponseMessage>(ok.Message);
        Assert.Equal(JsonRpcId.FromNumber(3), response.Id);
        Assert.Equal("{\"done\":true}", response.Result?.GetRawText());
        Assert.Null(response.Error);

        DecodeResult failed = JsonRpc.DecodeLine(JsonRpc.EncodeErrorResponse(
            JsonRpcId.FromString("abc-1"), RpcErrorCodes.MethodNotFound, "No such method.", new JsonObject { ["wanted"] = "x" }));
        var error = Assert.IsType<JsonRpcResponseMessage>(failed.Message);
        Assert.Equal(JsonRpcId.FromString("abc-1"), error.Id);
        Assert.Null(error.Result);
        Assert.NotNull(error.Error);
        Assert.Equal(RpcErrorCodes.MethodNotFound, error.Error.Code);
        Assert.Equal("No such method.", error.Error.Message, StringComparer.Ordinal);
        Assert.Equal("{\"wanted\":\"x\"}", error.Error.Data?.GetRawText());
    }

    [Fact]
    public void EncodeErrorResponseAcceptsNullIdForUnknownRequests()
    {
        DecodeResult decoded = JsonRpc.DecodeLine(JsonRpc.EncodeErrorResponse(JsonRpcId.Null, RpcErrorCodes.ParseError, "Malformed."));
        var response = Assert.IsType<JsonRpcResponseMessage>(decoded.Message);
        Assert.True(response.Id.IsNull);
        Assert.Equal(RpcErrorCodes.ParseError, response.Error?.Code);
    }

    [Fact]
    public void EncodeRejectsEmptyMethodAndBadParams()
    {
        Assert.Throws<ArgumentException>(() => JsonRpc.EncodeRequest(JsonRpcId.FromNumber(1), string.Empty));
        Assert.Throws<ArgumentException>(() => JsonRpc.EncodeNotification(string.Empty));
        Assert.Throws<ArgumentException>(() => JsonRpc.EncodeRequest(JsonRpcId.FromNumber(1), "m", JsonValue.Create(42)));
        Assert.Throws<ArgumentException>(() => JsonRpc.EncodeErrorResponse(JsonRpcId.FromNumber(1), 0, string.Empty));
        Assert.Throws<ArgumentException>(() => JsonRpc.EncodeRequest(JsonRpcId.Null, "m"));
    }

    [Fact]
    public void EncodedMessagesContainNoLiteralNewlines()
    {
        var parameters = new JsonObject { ["text"] = "line one\nline two\r\nline three" };
        string line = JsonRpc.EncodeRequest(JsonRpcId.FromNumber(1), "m", parameters);
        Assert.DoesNotContain('\n', line);
        Assert.DoesNotContain('\r', line);
        DecodeResult decoded = JsonRpc.DecodeLine(line);
        Assert.True(decoded.Success);
    }

    [Theory]
    [InlineData("", RpcErrorCodes.ParseError)]
    [InlineData("   ", RpcErrorCodes.ParseError)]
    [InlineData("{oops", RpcErrorCodes.ParseError)]
    [InlineData("[{\"jsonrpc\":\"2.0\",\"method\":\"m\"}]", RpcErrorCodes.InvalidRequest)]
    [InlineData("42", RpcErrorCodes.InvalidRequest)]
    [InlineData("\"just a string\"", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"method\":\"m\"}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"1.0\",\"method\":\"m\"}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\"}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"method\":\"\",\"id\":1}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"method\":42,\"id\":1}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"id\":null}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"id\":1.5}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"params\":42}", RpcErrorCodes.InvalidParams)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":1,\"error\":{\"code\":1,\"message\":\"m\"}}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"result\":1}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"message\":\"m\"}}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":\"x\",\"message\":\"m\"}}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":1}}", RpcErrorCodes.InvalidRequest)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":42}", RpcErrorCodes.InvalidRequest)]
    public void MalformedIncomingLinesReturnStructuredFaults(string line, int code)
    {
        DecodeResult decoded = JsonRpc.DecodeLine(line);
        Assert.False(decoded.Success);
        Assert.Null(decoded.Message);
        Assert.NotNull(decoded.Fault);
        Assert.Equal(code, decoded.Fault.Code);
        Assert.NotEmpty(decoded.Fault.Message);
    }
}
