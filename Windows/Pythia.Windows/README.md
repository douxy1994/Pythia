# Pythia Windows x64

This is the 64-bit x64 Flutter Windows client for Pythia 1.0.0, including the native Windows host files required to build and register platform channels. The CMake project rejects non-x64 toolchains, the release verifier requires `Pythia.exe` to use PE machine `0x8664` (AMD64), and GitHub Actions now builds and packages the verified candidate.

This macOS workspace can run Flutter/Dart logic tests, but cannot build or run the Windows executable because it lacks a Windows runtime and Visual Studio Build Tools. The files here are structured so a Windows development machine can run:

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
dart run tool/verify_release_package.dart build\windows\x64\runner\Release
```

## Implemented In This Scaffold

- `lib/main.dart`: Material 3 Windows-facing app shell with translation input, language selectors, result cards, copy, clear, settings dialog, searchable/favorite/delete-capable history sidebar, and manual history sync action.
- `lib/core/history_record.dart`: cross-platform history model matching `Core/Schemas/history-record.schema.json`.
- `lib/core/history_sync.dart`: Dart port of the macOS/Core merge strategy.
- `lib/core/webdav_sync.dart`: WebDAV `/Pythia/history/history.json` sync and connection-test implementation.
- `lib/core/local_storage.dart`: local JSON settings/history storage using app support directory, including logical deletion, favorite toggling, clear-history, and search helpers.
- `lib/core/translation_service.dart`: provider interface plus Local, Google, Baidu, Youdao, OpenAI-compatible, DeepL, and LibreTranslate providers.
- `lib/core/settings_model.dart`: persisted non-secret provider settings, enabled states, and service order.
- `lib/core/update_checker.dart`: Pythia GitHub latest-release checker for version `1.0.0`.
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

Do not bundle plugins in the Windows release package.

Build the release installer on Windows with `powershell -File tool/build_windows_installer.ps1`. It produces `dist/Pythia-1.0.0-windows-x64.exe` and the required `.sha256` sidecar. Set `PYTHIA_WINDOWS_CERT_SHA1` to a certificate already installed in the Windows certificate store for a production Authenticode-signed build; no certificate or private key belongs in this repository.
