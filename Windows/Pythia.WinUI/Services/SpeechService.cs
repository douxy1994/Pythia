using System.Runtime.InteropServices;

namespace Pythia.Services;

public static class SpeechService
{
    public static string NormalizeText(string text) => text.Trim();

    public static Task SpeakAsync(string text, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeText(text);
        if (normalized.Length == 0) throw new ArgumentException("没有可朗读的译文。", nameof(text));
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            var voiceType = Type.GetTypeFromProgID("SAPI.SpVoice")
                ?? throw new PlatformNotSupportedException("Windows 语音服务不可用。");
            var voice = Activator.CreateInstance(voiceType)
                ?? throw new InvalidOperationException("无法启动 Windows 语音服务。");
            try
            {
                voiceType.InvokeMember("Speak",
                    System.Reflection.BindingFlags.InvokeMethod,
                    null,
                    voice,
                    [normalized, 0]);
            }
            finally
            {
                if (Marshal.IsComObject(voice)) Marshal.FinalReleaseComObject(voice);
            }
        }, cancellationToken);
    }
}
