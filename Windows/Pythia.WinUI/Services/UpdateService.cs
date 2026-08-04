using System.Diagnostics;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security;
using System.Security.Cryptography;
using System.Text.Json;

namespace Pythia.Services;

public sealed record PythiaUpdateInfo(
    Version Version,
    string Tag,
    string ReleaseUrl,
    string InstallerName,
    string InstallerUrl,
    string ChecksumUrl,
    string Notes);

public static class UpdateService
{
    private const long MaximumInstallerBytes = 512L * 1024 * 1024;
    private const string LatestReleaseApi = "https://api.github.com/repos/douxy1994/Pythia/releases/latest";
    public const string RepositoryUrl = "https://github.com/douxy1994/Pythia";

    public static Version CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(1, 0, 0);

    public static async Task<PythiaUpdateInfo?> CheckAsync(CancellationToken cancellationToken = default)
    {
        using var client = CreateClient(TimeSpan.FromSeconds(20));
        using var response = await client.GetAsync(LatestReleaseApi, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = document.RootElement;
        var tag = root.GetProperty("tag_name").GetString()?.Trim() ?? string.Empty;
        if (!TryParseVersion(tag, out var version) || version <= CurrentVersion) return null;
        var releaseUrl = root.GetProperty("html_url").GetString() ?? string.Empty;
        var notes = root.TryGetProperty("body", out var body) ? body.GetString() ?? string.Empty : string.Empty;
        var expectedInstallerName = ExpectedInstallerName(version);
        string? installerName = null;
        string? installerUrl = null;
        string? checksumUrl = null;
        foreach (var asset in root.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? string.Empty;
            var url = asset.GetProperty("browser_download_url").GetString() ?? string.Empty;
            if (name.Equals(expectedInstallerName, StringComparison.OrdinalIgnoreCase))
            {
                installerName = name;
                installerUrl = url;
            }
        }
        if (installerName is null || installerUrl is null) return null;
        foreach (var asset in root.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? string.Empty;
            if (name.Equals(installerName + ".sha256", StringComparison.OrdinalIgnoreCase))
                checksumUrl = asset.GetProperty("browser_download_url").GetString();
        }
        if (string.IsNullOrWhiteSpace(checksumUrl))
            throw new InvalidDataException("更新发布缺少 SHA-256 校验文件，已拒绝下载。");
        return new PythiaUpdateInfo(
            version,
            tag,
            releaseUrl,
            installerName,
            installerUrl,
            checksumUrl,
            notes.Length <= 2_000 ? notes : notes[..2_000] + "…");
    }

    public static string ExpectedInstallerName(Version version) =>
        $"Pythia-{version.ToString(3)}-windows-x64.exe";

    public static async Task<string> DownloadInstallerAsync(
        PythiaUpdateInfo update,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient(TimeSpan.FromMinutes(10));
        var checksumText = await client.GetStringAsync(update.ChecksumUrl, cancellationToken);
        var expectedHash = checksumText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault()?.Trim().ToLowerInvariant();
        if (expectedHash is null || expectedHash.Length != 64 || !expectedHash.All(Uri.IsHexDigit))
            throw new InvalidDataException("更新校验文件格式无效。");

        var directory = Path.Combine(Path.GetTempPath(), "Pythia", "Updates");
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, Path.GetFileName(update.InstallerName));
        if (File.Exists(destination) &&
            string.Equals(await HashFileAsync(destination, cancellationToken), expectedHash, StringComparison.OrdinalIgnoreCase))
            return destination;

        var temporary = destination + ".download";
        var completed = false;
        try
        {
            using var response = await client.GetAsync(update.InstallerUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();
            var length = response.Content.Headers.ContentLength;
            if (length is > MaximumInstallerBytes)
                throw new InvalidDataException("更新安装包超过 512 MiB 安全限制。");
            await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
            await using (var output = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                var buffer = new byte[128 * 1024];
                long total = 0;
                while (true)
                {
                    var read = await input.ReadAsync(buffer, cancellationToken);
                    if (read == 0) break;
                    total += read;
                    if (total > MaximumInstallerBytes)
                        throw new InvalidDataException("更新安装包超过 512 MiB 安全限制。");
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    if (length is > 0) progress?.Report((double)total / length.Value);
                }
                await output.FlushAsync(cancellationToken);
            }
            var actualHash = await HashFileAsync(temporary, cancellationToken);
            if (!string.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new CryptographicException("更新安装包 SHA-256 校验失败。");
            // SHA-256 proves the bytes match the release; Authenticode additionally proves the
            // bytes come from the expected publisher and haven't been tampered with in flight.
            // Both checks are required before the installer is allowed to run (goal §IV.6).
            var status = AuthenticodeVerifier.VerifyFile(temporary, out var subject);
            var decision = AuthenticodeVerifier.Evaluate(status, subject, AuthenticodeVerifier.ExpectedPublisher);
            if (!decision.Accepted)
                throw new SecurityException($"更新安装包被拒绝：{decision.Reason}");
            File.Move(temporary, destination, true);
            completed = true;
            return destination;
        }
        finally
        {
            if (!completed)
            {
                try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            }
        }
    }

    public static void LaunchInstaller(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("更新安装包不存在。", path);
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    public static bool TryParseVersion(string value, out Version version)
    {
        var normalized = value.Trim().TrimStart('v', 'V').Split('-', '+')[0];
        return Version.TryParse(normalized, out version!);
    }

    private static HttpClient CreateClient(TimeSpan timeout)
    {
        var client = new HttpClient { Timeout = timeout };
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("Pythia-Windows", "1.0"));
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        return client;
    }

    private static async Task<string> HashFileAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexStringLower(hash);
    }
}
