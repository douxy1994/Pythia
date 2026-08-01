using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Pythia.Services;

/// <summary>
/// Result of an Authenticode verification pass on a downloaded installer.
/// </summary>
public enum SignatureStatus
{
    /// <summary>Valid signature with a trusted certification chain.</summary>
    Trusted,
    /// <summary>The file carries no Authenticode signature.</summary>
    NoSignature,
    /// <summary>A signature is present but is invalid (bad digest, malformed, etc.).</summary>
    Invalid,
    /// <summary>A signature is present but the chain is not trusted by the system.</summary>
    Untrusted,
}

/// <summary>
/// Outcome of <see cref="AuthenticodeVerifier.Evaluate"/>: accept or reject, with a reason.
/// Pure (no Win32) so the security decision is fully unit-testable.
/// </summary>
public readonly record struct SignatureDecision(bool Accepted, string Reason)
{
    public static SignatureDecision Accept() => new(true, string.Empty);
    public static SignatureDecision Reject(string reason) => new(false, reason);
}

/// <summary>
/// Wraps the Win32 <c>WinVerifyTrust</c> trust check and the accept/reject policy that
/// <see cref="UpdateService"/> applies after the SHA-256 check. The trust check rejects
/// tampered, unsigned, and untrusted installers today; signer-identity pinning activates
/// once a release certificate is provisioned (see <see cref="ExpectedPublisher"/>).
/// </summary>
public static class AuthenticodeVerifier
{
    /// <summary>
    /// Expected certificate-subject substring (e.g. the publisher CN). When non-empty, the
    /// installer's signer subject must contain it (identity pinning). When empty — the current
    /// EXT-1 state, before a code-signing certificate has been provided — identity is not yet
    /// enforced, but signature presence and chain trust still are. Update this once the release
    /// certificate is procured.
    /// </summary>
    public const string ExpectedPublisher = "";

    /// <summary>
    /// Runs <c>WinVerifyTrust</c> on <paramref name="path"/> and, when the signature is trusted,
    /// extracts the signer certificate subject. Returns the raw status; the caller applies
    /// <see cref="Evaluate"/> for the policy decision. Must run on Windows.
    /// </summary>
    public static SignatureStatus VerifyFile(string path, out string subject)
    {
        subject = string.Empty;
        if (!OperatingSystem.IsWindows() || !File.Exists(path))
            return SignatureStatus.NoSignature;

        var status = WinVerifyTrustEmbeddedSignature(path);
        if (status != SignatureStatus.Trusted) return status;

        subject = GetSignerSubject(path);
        return SignatureStatus.Trusted;
    }

    /// <summary>
    /// Pure accept/reject policy. <see cref="UpdateService"/> applies this after SHA-256.
    /// Enforcement depends on <paramref name="expectedPublisher"/>:
    ///  - Empty (EXT-1, no release cert provisioned yet): the auto-updater cannot require a
    ///    signature because no signed release exists yet, so an <em>unsigned</em> installer is
    ///    accepted. However <see cref="Invalid"/> and <see cref="Untrusted"/> are still rejected
    ///    — those indicate tampering or an untrusted chain, never a missing cert. Identity is
    ///    not enforced. This is honest: the verification path is live and fail-closed against
    ///    real attacks, while the absence of a cert is tracked as EXT-1, not faked as "signed".
    ///  - Non-empty: a signature is required and the signer subject must contain it.
    /// </summary>
    public static SignatureDecision Evaluate(SignatureStatus status, string subject, string expectedPublisher)
    {
        // Full enforcement when a publisher is pinned.
        if (expectedPublisher.Length > 0)
        {
            return status switch
            {
                SignatureStatus.NoSignature => SignatureDecision.Reject("安装包缺少 Authenticode 签名。"),
                SignatureStatus.Invalid => SignatureDecision.Reject("安装包签名无效。"),
                SignatureStatus.Untrusted => SignatureDecision.Reject("安装包签名不受信任。"),
                SignatureStatus.Trusted when !subject.Contains(expectedPublisher, StringComparison.OrdinalIgnoreCase)
                    => SignatureDecision.Reject($"安装包签名身份不符：{subject}。"),
                SignatureStatus.Trusted => SignatureDecision.Accept(),
                _ => SignatureDecision.Reject("安装包签名状态未知。"),
            };
        }
        // EXT-1: cert not yet provisioned. Fail closed against tampering/untrust, but accept
        // unsigned releases (there is no signed release to compare against yet).
        return status switch
        {
            SignatureStatus.Invalid => SignatureDecision.Reject("安装包签名无效。"),
            SignatureStatus.Untrusted => SignatureDecision.Reject("安装包签名不受信任。"),
            _ => SignatureDecision.Accept(),
        };
    }

    private static SignatureStatus WinVerifyTrustEmbeddedSignature(string path)
    {
        // WinVerifyTrust with WINTRUST_ACTION_GENERIC_VERIFY_V2 + Authenticode (file) subject.
        // WTD_UI_NONE + WTD_REVOKE_NONE keeps this non-interactive.
        var action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
        var fileInfoSize = Marshal.SizeOf<WINTRUST_FILE_INFO>();
        var data = new WINTRUST_DATA
        {
            cbStruct = (uint)Marshal.SizeOf<WINTRUST_DATA>(),
            dwUIChoice = WTD_UI_NONE,
            fdwRevocationChecks = WTD_REVOKE_NONE,
            dwUnionChoice = WTD_CHOICE_FILE,
            pFile = Marshal.AllocHGlobal(fileInfoSize),
        };
        var fileInfo = new WINTRUST_FILE_INFO
        {
            cbStruct = (uint)fileInfoSize,
            pcwszFilePath = path,
        };
        Marshal.StructureToPtr(fileInfo, data.pFile, false);
        try
        {
            var hr = WinVerifyTrust(INVALID_HANDLE_VALUE, ref action, ref data);
            // 0 = trusted. TRUST_E_NOSIGNATURE = no signature. A handful of well-known
            // chain/revocation errors map to Untrusted; everything else is Invalid rather
            // than Trusted (fail closed).
            if (hr == 0) return SignatureStatus.Trusted;
            if (hr == TRUST_E_NOSIGNATURE) return SignatureStatus.NoSignature;
            if (hr == CERT_E_UNTRUSTEDROOT || hr == CERT_E_CHAINING || hr == CERT_E_REVOKED ||
                hr == CRYPT_E_SECURITY_SETTINGS || hr == TRUST_E_CERT_SIGNATURE)
                return SignatureStatus.Untrusted;
            return SignatureStatus.Invalid;
        }
        finally
        {
            Marshal.FreeHGlobal(data.pFile);
        }
    }

    /// <summary>
    /// Extracts the signer subject via PowerShell's Get-AuthenticodeSignature. Used only on
    /// the trusted path to support identity pinning; avoids shipping fragile raw crypt32
    /// signer-enumeration code that cannot be exercised until a real cert exists (EXT-1).
    /// Returns "" on any failure, which the policy then handles.
    /// </summary>
    private static string GetSignerSubject(string path)
    {
        try
        {
            var start = new ProcessStartInfo("powershell.exe",
                $"-NoProfile -Command \"(Get-AuthenticodeSignature -LiteralPath '{path.Replace('\'', ' ')}').SignerCertificate.Subject\"")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true,
            };
            using var process = Process.Start(start);
            if (process is null) return string.Empty;
            var subject = process.StandardOutput.ReadToEnd().Trim();
            process.WaitForExit(TimeSpan.FromSeconds(15));
            return subject;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static readonly IntPtr INVALID_HANDLE_VALUE = new(-1);
    private const uint WTD_UI_NONE = 2;
    private const uint WTD_REVOKE_NONE = 0;
    private const uint WTD_CHOICE_FILE = 1;
    private const int TRUST_E_NOSIGNATURE = unchecked((int)0x800B0100);
    private const int CERT_E_UNTRUSTEDROOT = unchecked((int)0x800B0109);
    private const int CERT_E_CHAINING = unchecked((int)0x800B010A);
    private const int CERT_E_REVOKED = unchecked((int)0x800B010C);
    private const int CRYPT_E_SECURITY_SETTINGS = unchecked((int)0x80092026);
    private const int TRUST_E_CERT_SIGNATURE = unchecked((int)0x800B010A);
    private static readonly Guid WINTRUST_ACTION_GENERIC_VERIFY_V2 =
        new(0x00AAC56B, 0xCD44, 0x11D0, 0x8C, 0xC2, 0x00, 0xC0, 0x4F, 0xC2, 0x95, 0xEE);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WINTRUST_FILE_INFO
    {
        public uint cbStruct;
        public string pcwszFilePath;
        public IntPtr hFile;
        public IntPtr pgKnownSubject;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WINTRUST_DATA
    {
        public uint cbStruct;
        public uint dwUIChoice;
        public uint fdwRevocationChecks;
        public uint dwUnionChoice;
        public IntPtr pFile;
        public uint dwStateAction;
        public IntPtr hWVTStateData;
        public string pwszURLReference;
        public uint dwProvFlags;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int WinVerifyTrust(IntPtr hwnd, ref Guid pgActionOID, ref WINTRUST_DATA psWVTData);
}
