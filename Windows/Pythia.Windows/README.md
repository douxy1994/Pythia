# Pythia Windows x64

This is the 64-bit x64 Flutter Windows client for Pythia. The repository/macOS release is `1.1.0`; the Windows client remains Preview at Flutter version `1.0.0+100` until its real-machine acceptance and release gates are complete. The CMake project rejects non-x64 toolchains, the release verifier requires `Pythia.exe` to use PE machine `0x8664` (AMD64), and GitHub Actions builds and packages the verified Windows candidate.

Before continuing Windows work, read the repository-level [Windows Codex handoff](../../WINDOWS_CODEX_HANDOFF.md). It is the authoritative continuation document and includes the correct branch baseline, exact toolchain, source map, platform-channel contract, known UI/IME gaps, manual Windows acceptance matrix, release rules, and definition of done.

This macOS workspace can run Flutter/Dart logic tests, but cannot build or run the Windows executable because it lacks a Windows runtime and Visual Studio Build Tools. The files here are structured so a Windows development machine can run:

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
dart run tool/verify_release_package.dart build\windows\x64\runner\Release
```

## Current Windows Baseline

- Git baseline: `0d286b1a85b5c0a8bfa8f66b53d861f13185e972` (`Release Pythia 1.1.0`).
- Latest verified workflow: [Windows x64 run 30703218631](https://github.com/douxy1994/Pythia/actions/runs/30703218631).
- CI passed Flutter `3.44.5 stable`, `flutter analyze`, 85 tests, plugin validation, x64 release verification, installer checksum verification, and Windows runtime/install/restart/uninstall smoke tests.
- This CI result does not replace the real Windows manual matrix. Continue with live UI Automation, OCR, hotkey, tray, Credential Manager, WebDAV, startup, signed-updater, and DPI/IME checks before changing the Windows version.

To inspect the exact CI evidence from a Windows checkout:

```powershell
gh run view 30703218631 --repo douxy1994/Pythia
```

The current published `.pythia` packages are under [`../../Plugins`](../../Plugins/README.md). The complete plugin contract is documented in [`../../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md`](../../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md). Public plugin downloads are for interactive testing and must never be copied into the application release directory.

## Implemented In This Scaffold

- `lib/main.dart`: Material 3 Windows-facing app shell with translation input, language selectors, result cards, copy, clear, settings dialog, searchable/favorite/delete-capable history sidebar, and manual history sync action.
- `lib/core/history_record.dart`: cross-platform history model matching `Core/Schemas/history-record.schema.json`.
- `lib/core/history_sync.dart`: Dart port of the macOS/Core merge strategy.
- `lib/core/webdav_sync.dart`: WebDAV `/Pythia/history/history.json` sync and connection-test implementation.
- `lib/core/local_storage.dart`: local JSON settings/history storage using app support directory, including logical deletion, favorite toggling, clear-history, and search helpers.
- `lib/core/translation_service.dart`: provider interface plus Local, Google, Baidu, Youdao, OpenAI-compatible, DeepL, and LibreTranslate providers.
- `lib/core/settings_model.dart`: persisted non-secret provider settings, enabled states, and service order.
- `lib/core/update_checker.dart`: Pythia GitHub latest-release checker for the current Windows Preview version `1.0.0`.
- `lib/core/release_package_verifier.dart` and `tool/verify_release_package.dart`: release gate that requires an AMD64 `Pythia.exe` and rejects bundled plugin payloads and private-key/API-token markers.
- `lib/platform/*`: explicit platform interfaces plus MethodChannel Credential Manager storage for secrets.
- `lib/platform/platform_services.dart`: MethodChannel contracts for selection translation, screenshot OCR, tray actions, hotkeys, startup, and window behavior.
- `lib/platform/tray_action_dispatcher.dart`: tested routing for quick input translation, settings, history, and WebDAV history sync tray actions.
- `windows/runner/*`: native Flutter Windows host, CMake project, Credential Manager channel, selected-text clipboard fallback, Windows Runtime screenshot OCR with a multi-monitor selection overlay, startup registration, always-on-top window handling, complete tray icon/menu callbacks, close-to-tray behavior, global hotkey registration/dispatch, and window placement persistence.
- `test/history_sync_test.dart`: merge behavior, corrupt-remote protection, and WebDAV connection-test behavior tests.
- `test/translation_service_test.dart`: provider request, language mapping, response parsing, and credential behavior tests.
- `test/update_checker_test.dart`: GitHub latest-release parsing, version comparison, and HTTP failure behavior tests.
- `test/platform_services_test.dart`: Windows platform MethodChannel method names and argument contracts.
- `test/tray_action_dispatcher_test.dart`: complete tray business-action routing.
- `test/native/tray_action_map_test.cpp`: platform-independent native command-to-Dart action mapping.
- `test/release_package_verifier_test.dart`: Windows x64 architecture plus release package plugin/secret exclusion tests.

## Still Required On Windows

- Verify the included native host on a real Windows Flutter environment with Visual Studio Build Tools.
- Verify screenshot OCR, global hotkeys, and signed update installation on Windows. The settings page has a real hotkey recorder and the updater downloads only paired x64 installer/SHA-256 assets, verifies them, checks Authenticode natively, and launches the installer.
- Verify UI Automation selected-text reading and its clipboard fallback across representative Windows applications.
- Verify Google, Baidu, Youdao, OpenAI-compatible, DeepL, and LibreTranslate against live Windows networking and Credential Manager.
- Run `dart run tool/verify_release_package.dart build\windows\x64\runner\Release` against the real release directory after `flutter build windows --release`. Update checks already point to `https://github.com/douxy1994/Pythia/releases`, but need live Windows verification.

Do not bundle plugins in the Windows release package. Public plugins remain separate downloads in the repository `Plugins/` directory.

Build the release installer on Windows with `powershell -File tool/build_windows_installer.ps1`. It produces `dist/Pythia-1.0.0-windows-x64.exe` and the required `.sha256` sidecar. Set `PYTHIA_WINDOWS_CERT_SHA1` to a certificate already installed in the Windows certificate store for a production Authenticode-signed build; no certificate or private key belongs in this repository.
