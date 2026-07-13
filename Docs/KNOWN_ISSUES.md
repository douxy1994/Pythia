# Known Issues

## Cross-Platform

- Windows x64 compilation and installer packaging are verified by the fork's GitHub Actions Windows runner. This macOS workspace still cannot launch the executable, so interactive runtime verification remains outstanding.
- Flutter/Dart tests and platform-independent native contracts run locally. Windows-only tray, hotkey, OCR, Credential Manager, WebDAV, startup, and installer behavior still require live Windows x64 checks.
- WebDAV sync is implemented in both apps but is not yet end-to-end verified with one live account across macOS and Windows x64.
- macOS history now writes the cross-platform `PythiaHistoryRecord` fields, can migrate older local `history.json` records, and has manual/startup/periodic/local-change-debounced/best-effort-exit WebDAV history sync. Conflict log UI and live Windows-side sync verification are still missing.
- Portable settings backup is separated from device-specific and sensitive fields. Automatic settings synchronization remains intentionally disabled; users explicitly trigger local or WebDAV backup/restore.

## macOS

- The macOS app is AppKit-based. The objective mentions SwiftUI, but the current real implementation uses AppKit windows and controls with Liquid Glass-inspired material views.
- API keys and WebDAV passwords are stored locally outside Keychain because repeated Keychain prompts were unacceptable to the user. This conflicts with the ideal cross-platform security requirement and must be revisited with a no-repeat-prompt design before final sync release.
- Some legacy plugin compatibility depends on local user plugin files and is best effort.
- Original plugin APIs that require private binary execution remain unsupported.
- Legacy macOS `/pot/pythia-config-backup.json` and `/pot/pot-config-backup.json` paths remain as read-only restore fallbacks. New backups use `/Pythia/settings/portable-backup.json`.

## Release

- macOS release packaging exists and excludes bundled plugins.
- Windows x64 packaging and CI are build-verified, including Inno Setup output, SHA-256 sidecar generation/recalculation, AMD64/package-content verification, and artifact upload. The current Actions artifact is an unsigned CI candidate; production release still requires Authenticode signing and live install/uninstall/update checks.
- The repository still contains compatibility strings referring to legacy Pot migration/plugin import. Product-facing release text should avoid presenting these as current branding.
