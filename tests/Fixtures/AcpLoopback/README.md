# AcpLoopback

Scripted fake ACP agent over stdio. Test-only: protocol suites spawn it through the .NET host (`dotnet AcpLoopback.dll --script <file>`) and drive prompt turns with no network, no API keys, and no real agent. Owner: D00 T02 §4.

Wire format follows ACP v1: newline-delimited JSON-RPC 2.0 on stdin/stdout, UTF-8, diagnostics on stderr only (https://agentclientprotocol.com/protocol/v1/transports). Method shapes follow the v1 schema (https://agentclientprotocol.com/protocol/v1/schema): `initialize`, `session/new`, `session/prompt`, `session/update` notifications, `{"stopReason": "end_turn"}` prompt results.

Script file shape:

```json
{
  "sessionId": "sess_loopback_001",
  "chunks": ["first chunk text", "second chunk text"],
  "stopReason": "end_turn"
}
```

CLI flags:

- `--script <path>` (required): script file described above.
- `--emit-garbage`: write one malformed line to stdout before the first response (fault: client must skip it and complete the turn).
- `--drop <method>`: accept but never answer the named method (fault: client must time out, not hang).
- `--chunk-delay-ms <n>`: sleep n ms between streamed `session/update` notifications (fault: slow streams must still complete).

Validation (fails loudly): an unparseable line, a valid-JSON non-object line, or a JSON-RPC envelope violation (missing `jsonrpc: "2.0"`, missing `method`, non-object `params`) is reported on stderr and the process exits 2 without writing stdout garbage. An unloadable script (missing file, bad JSON, wrong field types) exits 3. A well-formed request with invalid params (`initialize` without numeric `protocolVersion`, `session/new` without string `cwd`, `session/prompt` without string `sessionId` and array `prompt`) gets a JSON-RPC error response (`-32602`) plus a stderr note; an unknown method gets `-32601`.
