namespace Pythia.Models;

/// <summary>
/// Why a suitable OCR engine could not be produced. Drives the user-facing
/// message and the partial-capability fallback decision.
/// </summary>
public enum OcrUnavailableReason
{
    /// <summary>No OCR language pack is installed at all — OCR cannot run.</summary>
    NoLanguagePack,
    /// <summary>The Chinese OCR pack is missing — English (if present) is used instead.</summary>
    NoChinesePack,
    /// <summary>The English OCR pack is missing — Chinese (if present) is used instead.</summary>
    NoEnglishPack,
}

/// <summary>
/// Thrown by <c>OcrService</c> when the desired OCR language pack is unavailable.
/// <see cref="Reason"/> lets callers decide between aborting (NoLanguagePack) and
/// showing a non-fatal hint while proceeding with the other language.
/// </summary>
public sealed class OcrUnavailableException : Exception
{
    public OcrUnavailableReason Reason { get; }

    public OcrUnavailableException(OcrUnavailableReason reason, string message)
        : base(message) => Reason = reason;

    /// <summary>
    /// User-facing, actionable message for each reason, including the Windows
    /// Settings entry point for installing the missing OCR language pack.
    /// </summary>
    public static string Describe(OcrUnavailableReason reason) => reason switch
    {
        OcrUnavailableReason.NoLanguagePack =>
            "系统未安装任何 OCR 语言包。请在 Windows“设置 → 时间和语言 → 语言和区域 → 添加语言”中，为中文或英文启用“光学字符识别”可选功能后重试。",
        OcrUnavailableReason.NoChinesePack =>
            "缺少中文 OCR 语言包，本次改用英文识别。如需识别中文，请在 Windows“设置 → 时间和语言 → 语言和区域”中为中文添加“光学字符识别”可选功能。",
        OcrUnavailableReason.NoEnglishPack =>
            "缺少英文 OCR 语言包，本次改用中文识别。如需识别英文，请在 Windows“设置 → 时间和语言 → 语言和区域”中为英文添加“光学字符识别”可选功能。",
        _ => "OCR 语言包不可用。",
    };
}
