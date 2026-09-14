// Minimal JSON-RPC-over-stdio driver for the AcpLoopback fixture. Test scaffolding only:
// real client coverage arrives with D03, which consumes the same fixture.
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace IntelligentNotepad.Protocol.Tests;

sealed class AcpTestClient : IAsyncDisposable
{
    private readonly Process _process;
    private readonly Queue<JsonObject> _notifications = new();
    private readonly StringBuilder _stderr = new();
    private long _nextId;

    public int SkippedLineCount { get; private set; }

    public string StderrText
    {
        get
        {
            lock (_stderr)
            {
                return _stderr.ToString();
            }
        }
    }

    public bool HasExited => _process.HasExited;

    public int ExitCode => _process.ExitCode;

    private AcpTestClient(Process process) => _process = process;

    public static async Task<AcpTestClient> StartAsync(string script, string extraArgs = "")
    {
        string dir = AppContext.BaseDirectory;
        string fixture = Path.Combine(dir, "AcpLoopback.dll");
        string scriptPath = Path.Combine(dir, "Scripts", script);
        if (!File.Exists(fixture))
        {
            throw new FileNotFoundException($"Loopback fixture missing from test output: {fixture}");
        }
        string exe = OperatingSystem.IsWindows() ? "dotnet.exe" : "dotnet";
        string? root = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        string host = root is not null && File.Exists(Path.Combine(root, exe)) ? Path.Combine(root, exe) : exe;
        var start = new ProcessStartInfo(host, $"\"{fixture}\" --script \"{scriptPath}\" {extraArgs}".Trim())
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            // No BOM preamble: ACP messages are bare UTF-8 lines, and a BOM would corrupt the first one.
            StandardInputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            UseShellExecute = false,
        };
        var process = Process.Start(start) ?? throw new InvalidOperationException("Could not spawn AcpLoopback.");
        var client = new AcpTestClient(process);
        _ = Task.Run(() => client.DrainStderrAsync());
        await Task.CompletedTask;
        return client;
    }

    public async Task<long> SendRequestAsync(string method, JsonObject @params)
    {
        long id = Interlocked.Increment(ref _nextId);
        await SendAsync(new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["method"] = method, ["params"] = @params });
        return id;
    }

    public Task SendRawAsync(string line) => SendLineAsync(line);

    // Sends a request and reads until its response arrives, stashing notifications for TryTakeNotification.
    public async Task<JsonObject> ExchangeAsync(string method, JsonObject @params, TimeSpan timeout)
    {
        long id = await SendRequestAsync(method, @params);
        while (true)
        {
            JsonObject message = await ReadAsync(timeout);
            if (message["id"]?.GetValue<long>() == id)
            {
                return message;
            }
            _notifications.Enqueue(message);
        }
    }

    public bool TryTakeNotification(out JsonObject notification)
    {
        if (_notifications.Count > 0)
        {
            notification = _notifications.Dequeue();
            return true;
        }
        notification = null!;
        return false;
    }

    // Next parsed stdout message. Unparseable lines are skipped and counted, never fatal.
    public async Task<JsonObject> ReadAsync(TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        while (true)
        {
            string? line;
            try
            {
                line = await _process.StandardOutput.ReadLineAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                throw new TimeoutException($"No ACP message within {timeout.TotalSeconds}s.");
            }
            if (line is null)
            {
                throw new EndOfStreamException(
                    $"Fixture stdout closed (exited={_process.HasExited}, code={(_process.HasExited ? _process.ExitCode : "?")}). Stderr: {StderrText}");
            }
            try
            {
                return JsonNode.Parse(line)!.AsObject();
            }
            catch (Exception ex) when (ex is JsonException or InvalidOperationException)
            {
                SkippedLineCount++;
            }
        }
    }

    public async Task WaitForExitAsync(TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            await _process.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            throw new TimeoutException($"Fixture still running after {timeout.TotalSeconds}s.");
        }
    }

    private async Task SendAsync(JsonObject message) => await SendLineAsync(message.ToJsonString());

    private async Task SendLineAsync(string line)
    {
        await _process.StandardInput.WriteLineAsync(line);
        await _process.StandardInput.FlushAsync();
    }

    private async Task DrainStderrAsync()
    {
        string? line;
        while ((line = await _process.StandardError.ReadLineAsync()) is not null)
        {
            lock (_stderr)
            {
                _stderr.AppendLine(line);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (!_process.HasExited)
        {
            try
            {
                await _process.StandardInput.DisposeAsync();
            }
            catch (IOException)
            {
                // Pipe already broken; fall through to the exit wait.
            }
        }
        if (!_process.HasExited)
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                await _process.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                _process.Kill(entireProcessTree: true);
            }
            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        _process.Dispose();
    }
}
