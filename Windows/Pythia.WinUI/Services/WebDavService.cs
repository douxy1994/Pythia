using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed record WebDavHistorySyncResult(
    IReadOnlyList<HistoryRecord> Records,
    int DownloadedCount,
    int UploadedCount,
    int VisibleCount,
    int ConflictCount,
    int HttpCode);

public static class WebDavService
{
    private const int MaximumRemoteBytes = 16 * 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public static async Task TestConnectionAsync(
        string url,
        string username,
        string password,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient();
        var root = NormalizeRootUrl(url);
        var auth = CreateAuthorization(username, password);
        await EnsureFolderAsync(client, root, auth, cancellationToken);
        var historyFolder = new Uri(root, "history/");
        await EnsureFolderAsync(client, historyFolder, auth, cancellationToken);
        _ = await FetchRemoteHistoryAsync(client, new Uri(historyFolder, "history.json"), auth, cancellationToken);
    }

    public static async Task<WebDavHistorySyncResult> SyncHistoryAsync(
        string url,
        string username,
        string password,
        IReadOnlyList<HistoryRecord> localRecords,
        string deviceId,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient();
        var root = NormalizeRootUrl(url);
        var auth = CreateAuthorization(username, password);
        await EnsureFolderAsync(client, root, auth, cancellationToken);
        var historyFolder = new Uri(root, "history/");
        await EnsureFolderAsync(client, historyFolder, auth, cancellationToken);
        var file = new Uri(historyFolder, "history.json");
        var remote = await FetchRemoteHistoryAsync(client, file, auth, cancellationToken);
        var merged = HistorySyncService.Merge(localRecords, remote.Records);
        var collection = new WebDavHistoryCollection
        {
            DeviceId = deviceId,
            UpdatedAt = DateTimeOffset.UtcNow,
            Records = merged.Records.Select(HistorySyncService.Clone).ToList(),
        };
        using var request = new HttpRequestMessage(HttpMethod.Put, file)
        {
            Content = new StringContent(JsonSerializer.Serialize(collection, JsonOptions), Encoding.UTF8, "application/json"),
        };
        AddAuthorization(request, auth);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        await RequireSuccessAsync(response, "上传 WebDAV 历史", cancellationToken);
        return new WebDavHistorySyncResult(
            merged.Records,
            remote.Records.Count,
            merged.Records.Count,
            merged.Records.Count(record => record.DeletedAt is null),
            merged.ConflictCount,
            (int)response.StatusCode);
    }

    public static async Task UploadPortableBackupAsync(
        string json,
        string url,
        string username,
        string password,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient();
        var root = NormalizeRootUrl(url);
        var auth = CreateAuthorization(username, password);
        await EnsureFolderAsync(client, root, auth, cancellationToken);
        var settingsFolder = new Uri(root, "settings/");
        await EnsureFolderAsync(client, settingsFolder, auth, cancellationToken);
        var temporary = new Uri(settingsFolder, "portable-backup.tmp.json");
        var destination = new Uri(settingsFolder, "portable-backup.json");
        await PutJsonAsync(client, temporary, json, auth, cancellationToken);

        using var move = new HttpRequestMessage(new HttpMethod("MOVE"), temporary);
        move.Headers.TryAddWithoutValidation("Destination", destination.ToString());
        move.Headers.TryAddWithoutValidation("Overwrite", "T");
        AddAuthorization(move, auth);
        using var moveResponse = await client.SendAsync(move, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (moveResponse.IsSuccessStatusCode) return;

        await PutJsonAsync(client, destination, json, auth, cancellationToken);
        try
        {
            using var delete = new HttpRequestMessage(HttpMethod.Delete, temporary);
            AddAuthorization(delete, auth);
            using var _ = await client.SendAsync(delete, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        catch { }
    }

    public static async Task<string> DownloadPortableBackupAsync(
        string url,
        string username,
        string password,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient();
        var file = new Uri(NormalizeRootUrl(url), "settings/portable-backup.json");
        using var request = new HttpRequestMessage(HttpMethod.Get, file);
        AddAuthorization(request, CreateAuthorization(username, password));
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotFound)
            throw new InvalidOperationException("远程没有可恢复的 Pythia 备份。");
        await RequireSuccessAsync(response, "下载 WebDAV 备份", cancellationToken);
        return Encoding.UTF8.GetString(await ReadBoundedAsync(response.Content, cancellationToken));
    }

    public static Uri NormalizeRootUrl(string value)
    {
        var trimmed = value.Trim().TrimEnd('/');
        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
            throw new InvalidOperationException("请输入有效的 HTTP 或 HTTPS WebDAV 地址。");
        if (uri.AbsolutePath.TrimEnd('/').EndsWith("/Pythia", StringComparison.OrdinalIgnoreCase))
            return new Uri(trimmed + "/", UriKind.Absolute);
        return new Uri(trimmed + "/Pythia/", UriKind.Absolute);
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(45) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Pythia-Windows/1.0");
        return client;
    }

    private static AuthenticationHeaderValue? CreateAuthorization(string username, string password) =>
        string.IsNullOrEmpty(username)
            ? null
            : new AuthenticationHeaderValue("Basic",
                Convert.ToBase64String(Encoding.UTF8.GetBytes(username + ":" + password)));

    private static void AddAuthorization(HttpRequestMessage request, AuthenticationHeaderValue? authorization)
    {
        if (authorization is not null) request.Headers.Authorization = authorization;
    }

    private static async Task EnsureFolderAsync(
        HttpClient client,
        Uri uri,
        AuthenticationHeaderValue? authorization,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(new HttpMethod("MKCOL"), uri);
        AddAuthorization(request, authorization);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.IsSuccessStatusCode || response.StatusCode is HttpStatusCode.MethodNotAllowed or HttpStatusCode.Conflict)
            return;
        await RequireSuccessAsync(response, "创建 WebDAV 目录", cancellationToken);
    }

    private static async Task<(List<HistoryRecord> Records, int HttpCode)> FetchRemoteHistoryAsync(
        HttpClient client,
        Uri file,
        AuthenticationHeaderValue? authorization,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, file);
        AddAuthorization(request, authorization);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotFound) return ([], 404);
        await RequireSuccessAsync(response, "读取 WebDAV 历史", cancellationToken);
        var bytes = await ReadBoundedAsync(response.Content, cancellationToken);
        if (bytes.Length == 0) return ([], (int)response.StatusCode);
        try
        {
            using var document = JsonDocument.Parse(bytes);
            List<HistoryRecord>? records = document.RootElement.ValueKind switch
            {
                JsonValueKind.Array => JsonSerializer.Deserialize<List<HistoryRecord>>(bytes, JsonOptions),
                JsonValueKind.Object when document.RootElement.TryGetProperty("records", out var node) =>
                    node.Deserialize<List<HistoryRecord>>(JsonOptions),
                _ => null,
            };
            return (records ?? throw new JsonException("缺少 records 数组。"), (int)response.StatusCode);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("远程历史文件损坏，已停止同步以保护本地数据。", exception);
        }
    }

    private static async Task PutJsonAsync(
        HttpClient client,
        Uri file,
        string json,
        AuthenticationHeaderValue? authorization,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, file)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
        AddAuthorization(request, authorization);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        await RequireSuccessAsync(response, "上传 WebDAV 备份", cancellationToken);
    }

    private static async Task<byte[]> ReadBoundedAsync(HttpContent content, CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength is > MaximumRemoteBytes)
            throw new InvalidDataException("远程文件超过 16 MiB 安全限制。");
        await using var stream = await content.ReadAsStreamAsync(cancellationToken);
        using var output = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await stream.ReadAsync(buffer, cancellationToken);
            if (read == 0) break;
            if (output.Length + read > MaximumRemoteBytes)
                throw new InvalidDataException("远程文件超过 16 MiB 安全限制。");
            output.Write(buffer, 0, read);
        }
        return output.ToArray();
    }

    private static async Task RequireSuccessAsync(
        HttpResponseMessage response,
        string action,
        CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode) return;
        await Task.CompletedTask;
        var message = response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "账号或密码错误；部分服务需要应用专用密码。",
            HttpStatusCode.Forbidden => "没有访问该 WebDAV 路径的权限。",
            HttpStatusCode.NotFound => "WebDAV 地址或文件不存在。",
            HttpStatusCode.MethodNotAllowed => "服务器不允许所需的 WebDAV 方法。",
            HttpStatusCode.Conflict => "WebDAV 父目录不存在或目录冲突。",
            _ => $"服务器返回 HTTP {(int)response.StatusCode}。",
        };
        throw new HttpRequestException($"{action}失败：{message}", null, response.StatusCode);
    }

    private sealed class WebDavHistoryCollection
    {
        public int SchemaVersion { get; set; } = 1;
        public string DeviceId { get; set; } = string.Empty;
        public DateTimeOffset UpdatedAt { get; set; }
        public List<HistoryRecord> Records { get; set; } = [];
    }
}
