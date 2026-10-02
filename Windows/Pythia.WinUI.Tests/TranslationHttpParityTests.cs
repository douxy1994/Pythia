using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Pythia.Models;
using Pythia.Services;

internal static class TranslationHttpParityTests
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        await SnapshotAndEarlyCompletionAsync(check);
        await FailureAsync(check);
        await CancellationAsync(check);
        Console.WriteLine("HTTP parity: loopback requests verify snapshot, language routing, early callback, peak=2, failures and cancellation.");
    }

    private static async Task SnapshotAndEarlyCompletionAsync(Action<bool, string> check)
    {
        var firstTwo = Signal();
        var release = Signal();
        await using var server = new LoopbackServer(async (request, ct) =>
        {
            if (request.Index == 2) firstTwo.TrySetResult();
            await release.Task.WaitAsync(ct);
            // Reverse the first pair so assembly cannot accidentally use completion order.
            if (request.Index == 1) await Task.Delay(50, ct);
            return (200, request.Text.ToUpperInvariant());
        });
        var settings = new PythiaSettings { LibreTranslateBaseUrl = server.BaseUrl, TranslateDeleteNewline = false };
        var coordinator = new TranslationCoordinator(new CredentialStore());
        var callbacks = new ConcurrentQueue<TranslationResult>();
        var unsupportedDone = Signal();
        const string source = "  First paragraph.\r\n\r\n  第二段正文。\nThird.\nFourth.  ";
        var run = coordinator.TranslateAsync(source, "auto", "zh-CN", ["libretranslate", "unsupported-test-provider"], settings,
            onServiceCompleted: result =>
            {
                callbacks.Enqueue(result);
                if (result.ServiceId == "unsupported-test-provider") unsupportedDone.TrySetResult();
            });
        await Task.WhenAll(firstTwo.Task, unsupportedDone.Task).WaitAsync(TimeSpan.FromSeconds(10));
        check(!run.IsCompleted && callbacks.Count == 1 && callbacks.Single().Error is not null,
            "HTTP: failed service callback arrives before delayed batch");
        check(server.Requests.Count == 2 && server.Peak == 2, "HTTP: only two requests start while service is blocked");
        settings.TranslateDeleteNewline = true;
        release.SetResult();
        var batch = await run.WaitAsync(TimeSpan.FromSeconds(10));
        var success = batch.Results.Single(item => item.ServiceId == "libretranslate");
        check(success.Error is null && success.Text == source.Trim().ToUpperInvariant(),
            "HTTP: snapshot keeps original separators after settings change and reversed completion");
        check(batch.SourceText == source.Trim(), "HTTP: coordinator trims only outer source whitespace");
        var pair = TranslationCoordinator.ResolveLanguages(source.Trim(), "auto", "zh-CN");
        check(server.Requests.Count == 4 && server.Requests.All(request =>
            request.Source == pair.Source && request.Target == pair.Target),
            "HTTP: all chunks use whole-source language routing");
        check(server.Requests.All(request => !request.Text.Any(c => "\r\n\u0085\u2028\u2029".Contains(c))),
            "HTTP: provider receives body without original separators");
        check(server.Peak == 2, "HTTP: per-service request peak remains two");
        check(callbacks.Count == 2 && callbacks.GroupBy(item => item.ServiceId).All(group => group.Count() == 1),
            "HTTP: partial failure and success each complete once");

        // A fresh request observes the changed option and performs output compaction.
        var next = await coordinator.TranslateAsync("Alpha\n\n  Beta", "en", "zh-CN", ["libretranslate"], settings)
            .WaitAsync(TimeSpan.FromSeconds(10));
        check(next.Results.Single().Text == "ALPHA BETA", "HTTP: next request uses changed newline option");
    }

    private static async Task FailureAsync(Action<bool, string> check)
    {
        var firstTwo = Signal();
        await using var server = new LoopbackServer(async (request, ct) =>
        {
            if (request.Index == 2) firstTwo.TrySetResult();
            await firstTwo.Task.WaitAsync(ct);
            if (request.Index == 1) return (500, "");
            await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            return (200, request.Text);
        });
        var settings = new PythiaSettings { LibreTranslateBaseUrl = server.BaseUrl };
        var callbacks = new ConcurrentQueue<TranslationResult>();
        var batch = await new TranslationCoordinator(new CredentialStore()).TranslateAsync(
            "one\ntwo\nthree\nfour", "en", "zh-CN", ["libretranslate"], settings,
            onServiceCompleted: callbacks.Enqueue).WaitAsync(TimeSpan.FromSeconds(10));
        await Task.Delay(100);
        check(batch.Results.Single().Error?.Contains("500", StringComparison.Ordinal) == true,
            "HTTP: provider failure retained as failed service");
        check(callbacks.Count == 1 && callbacks.Single().Error is not null,
            "HTTP: provider failure produces exactly one terminal callback");
        check(server.Requests.Count == 2, "HTTP: failure cancels sibling and never starts queued chunks");
    }

    private static async Task CancellationAsync(Action<bool, string> check)
    {
        var firstTwo = Signal();
        await using var server = new LoopbackServer(async (request, ct) =>
        {
            if (request.Index == 2) firstTwo.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            return (200, request.Text);
        });
        using var cancel = new CancellationTokenSource();
        var callbacks = new ConcurrentQueue<TranslationResult>();
        var run = new TranslationCoordinator(new CredentialStore()).TranslateAsync(
            "one\ntwo\nthree\nfour", "en", "zh-CN", ["libretranslate"],
            new PythiaSettings { LibreTranslateBaseUrl = server.BaseUrl }, cancel.Token, callbacks.Enqueue);
        await firstTwo.Task.WaitAsync(TimeSpan.FromSeconds(10));
        cancel.Cancel();
        try
        {
            await run.WaitAsync(TimeSpan.FromSeconds(10));
            check(false, "HTTP: caller cancellation propagates");
        }
        catch (OperationCanceledException) { check(true, "HTTP: caller cancellation propagates"); }
        await Task.Delay(100);
        check(server.Requests.Count == 2 && callbacks.IsEmpty,
            "HTTP: cancellation stops pending chunks and emits no late success callback");
    }

    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private sealed record Request(int Index, string Text, string Source, string Target);

    /// <summary>Minimal local HTTP endpoint: no request payload, credential or header is ever logged.</summary>
    private sealed class LoopbackServer : IAsyncDisposable
    {
        private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource _stop = new(TimeSpan.FromSeconds(30));
        private readonly ConcurrentBag<Task> _connections = [];
        private readonly Func<Request, CancellationToken, Task<(int Status, string Text)>> _reply;
        private readonly Task _accept;
        private int _active;
        private int _peak;
        private int _next;
        public ConcurrentQueue<Request> Requests { get; } = new();
        public int Peak => Volatile.Read(ref _peak);
        public string BaseUrl { get; }

        public LoopbackServer(Func<Request, CancellationToken, Task<(int Status, string Text)>> reply)
        {
            _reply = reply;
            _listener.Start();
            BaseUrl = $"http://127.0.0.1:{((IPEndPoint)_listener.LocalEndpoint).Port}";
            _accept = AcceptAsync();
        }

        private async Task AcceptAsync()
        {
            try
            {
                while (!_stop.IsCancellationRequested)
                {
                    var client = await _listener.AcceptTcpClientAsync(_stop.Token);
                    _connections.Add(HandleAsync(client));
                }
            }
            catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
        }

        private async Task HandleAsync(TcpClient client)
        {
            using (client)
            {
                var active = Interlocked.Increment(ref _active);
                int old;
                do { old = Volatile.Read(ref _peak); }
                while (active > old && Interlocked.CompareExchange(ref _peak, active, old) != old);
                try
                {
                    var stream = client.GetStream();
                    var header = new List<byte>();
                    var single = new byte[1];
                    while (header.Count < 16384)
                    {
                        await stream.ReadExactlyAsync(single, _stop.Token);
                        header.Add(single[0]);
                        if (header.Count >= 4 && header[^4] == 13 && header[^3] == 10 && header[^2] == 13 && header[^1] == 10) break;
                    }
                    var headerText = Encoding.ASCII.GetString(header.ToArray());
                    var lengthHeader = headerText.Split("\r\n").Single(line => line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase));
                    var length = int.Parse(lengthHeader[(lengthHeader.IndexOf(':') + 1)..].Trim());
                    if (length < 0 || length > 65536) throw new InvalidOperationException("Unexpected loopback body length.");
                    var body = new byte[length];
                    await stream.ReadExactlyAsync(body, _stop.Token);
                    Request request;
                    using (var document = JsonDocument.Parse(body))
                    {
                        // Only synthetic text and resolved languages are retained; ignore credentials.
                        var root = document.RootElement;
                        request = new(Interlocked.Increment(ref _next), root.GetProperty("q").GetString()!,
                            root.GetProperty("source").GetString()!, root.GetProperty("target").GetString()!);
                    }
                    Array.Clear(body);
                    Requests.Enqueue(request);
                    var reply = await _reply(request, _stop.Token);
                    var payload = JsonSerializer.SerializeToUtf8Bytes(new { translatedText = reply.Text });
                    var responseHeader = Encoding.ASCII.GetBytes($"HTTP/1.1 {reply.Status} Test\r\nContent-Type: application/json\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n");
                    await stream.WriteAsync(responseHeader, _stop.Token);
                    await stream.WriteAsync(payload, _stop.Token);
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
                catch (IOException) { /* A canceled HTTP client closes its local connection. */ }
                finally { Interlocked.Decrement(ref _active); }
            }
        }

        public async ValueTask DisposeAsync()
        {
            await _stop.CancelAsync();
            await _accept;
            _listener.Stop();
            await Task.WhenAll(_connections);
            _stop.Dispose();
        }
    }
}
