using System.Net;
using System.Net.Http.Headers;
using System.Text;

namespace Pythia.Services;

public static class WebDavService
{
    public static async Task TestConnectionAsync(string url, string username, string password)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
            throw new InvalidOperationException("请输入有效的 HTTP 或 HTTPS WebDAV 地址。");
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        using var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), uri);
        request.Headers.Add("Depth", "0");
        request.Headers.UserAgent.ParseAdd("Pythia-Windows/1.0");
        if (!string.IsNullOrEmpty(username))
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic",
                Convert.ToBase64String(Encoding.UTF8.GetBytes(username + ":" + password)));
        using var response = await client.SendAsync(request);
        if (response.StatusCode is HttpStatusCode.OK or HttpStatusCode.MultiStatus or HttpStatusCode.NoContent)
            return;
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            throw new InvalidOperationException("身份验证失败，请检查用户名和密码。");
        throw new HttpRequestException($"服务器返回 HTTP {(int)response.StatusCode}。");
    }
}
