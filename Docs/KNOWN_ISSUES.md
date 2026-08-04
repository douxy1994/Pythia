# Known Issues

> **2026-08-01 更新：Windows 客户端已迁移至 WinUI 3（`Windows/Pythia.WinUI/`）。**
> 当前已确认的代码缺口为「系统通知未真正发送」(P0) 与「OCR 语言包枚举/缺失提示」(P1)；
> Authenticode 签名为外部阻塞（待证书）。完整清单见
> [`WINDOWS_DIFF_LIST.md`](WINDOWS_DIFF_LIST.md)。下文早期条目描述的是旧 Flutter
> 客户端，WinUI 客户端已实现其中大部分能力（见 `WINDOWS_WINUI_PARITY_AUDIT.md`）。

## Cross-Platform

- Windows x64 compilation and installer packaging are verified by GitHub Actions and by a local Windows 11 build/install smoke run. User-driven interaction verification remains outstanding for IME candidate windows, mixed-DPI displays, representative third-party applications, and credentialed network services.
- Flutter/Dart tests, the release package gate, raw start/restart, and silent install/start/uninstall pass locally. Windows-only tray, hotkey conflicts, OCR language packs, Credential Manager persistence, WebDAV cross-device sync, startup-after-login, and signed updates still require live scenario checks.
- WebDAV sync is implemented in both apps but is not yet end-to-end verified with one live account across macOS and Windows x64.
- macOS history now writes the cross-platform `PythiaHistoryRecord` fields, can migrate older local `history.json` records, and has manual/startup/periodic/local-change-debounced/best-effort-exit WebDAV history sync. Conflict log UI and live Windows-side sync verification are still missing.
- Portable settings backup is separated from device-specific and sensitive fields. Automatic settings synchronization remains intentionally disabled; users explicitly trigger local or WebDAV backup/restore.

## macOS

- Pythia 1.2.0 is currently distributed for Apple silicon only. The compact translation window and Anthropic-compatible custom LLM interface are not yet present in the Windows Preview client.
- The macOS app is AppKit-based. The objective mentions SwiftUI, but the current real implementation uses AppKit windows and controls with Liquid Glass-inspired material views.
- API keys and WebDAV passwords are intentionally stored in `~/Library/Application Support/Pythia/credentials.json` with `0600` permissions. This removes all runtime Keychain prompts, but it is local access control rather than encrypted-at-rest storage; anyone who fully compromises the macOS user account can read the file.
- Some legacy plugin compatibility depends on local user plugin files and is best effort.
- Original plugin APIs that require private binary execution remain unsupported.
- Legacy macOS `/pot/pythia-config-backup.json` and `/pot/pot-config-backup.json` paths remain as read-only restore fallbacks. New backups use `/Pythia/settings/portable-backup.json`.

## Release

- macOS release packaging exists and excludes bundled plugins.
- Windows x64 packaging and CI are build-verified, including Inno Setup output, SHA-256 sidecar generation/recalculation, AMD64/package-content verification, and artifact upload. The current Actions artifact is an unsigned CI candidate; production release still requires Authenticode signing and live install/uninstall/update checks.
- The repository still contains compatibility strings referring to legacy Pot migration/plugin import. Product-facing release text should avoid presenting these as current branding.
