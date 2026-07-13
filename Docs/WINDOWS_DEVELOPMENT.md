# Windows x64 Development Plan

This repository contains a 64-bit x64 Flutter Windows client under `Windows/Pythia.Windows`, including the native Windows host/CMake files needed to register platform channels. Local macOS runs Flutter/Dart tests and native contract checks; the fork's GitHub Actions Windows runner now compiles and packages the AMD64 release. Interactive runtime verification still requires Windows x64.

## Architecture Requirement

- Supported release architecture: x64/AMD64 only.
- `cmake/PythiaWindowsArchitecture.cmake` stops configuration unless the toolchain is 64-bit and reports `x64`, `AMD64`, or `x86_64`.
- `tool/verify_release_package.dart` parses the PE header and requires `Pythia.exe` machine `0x8664` before upload.
- `tool/test_native_contracts.sh` verifies the architecture guard and tray command mapping from macOS or Linux.

## Recommended Stack

Use Flutter for Windows for the first Windows client:

- Native Windows window, tray, clipboard, screenshot, and credential features through platform channels.
- Dart UI can match Windows 11 style without copying the macOS interface.
- Shared data contracts come from `Core/Schemas`.
- History merge behavior must match `Core/PythiaCore`.

## Project Layout

```text
Windows/Pythia.Windows/
  README.md
  pubspec.yaml
  lib/
    main.dart
    core/
      history_record.dart
      history_sync.dart
      local_storage.dart
      settings_model.dart
      translation_service.dart
      update_checker.dart
      webdav_sync.dart
    platform/
      credential_store.dart
      global_hotkeys.dart
      selected_text_reader.dart
      screenshot_ocr.dart
      tray_service.dart
      window_behavior.dart
  windows/
    CMakeLists.txt
    flutter/
      CMakeLists.txt
      generated_plugin_registrant.cc
      generated_plugin_registrant.h
      generated_plugins.cmake
    runner/
      flutter_window.h
      flutter_window.cpp
      main.cpp
      pythia_credential_channel.h
      pythia_credential_channel.cpp
      pythia_platform_channel.h
      pythia_platform_channel.cpp
      win32_window.h
      win32_window.cpp
  test/
      history_sync_test.dart
      release_package_verifier_test.dart
      update_checker_test.dart
```

## Windows Platform Modules

- `CredentialStore`: MethodChannel wrapper for Windows Credential Manager. API keys and WebDAV passwords must never be stored in plain settings JSON. The native channel is registered by the included Windows runner.
- `GlobalHotkeys`: native `RegisterHotKey` support is implemented for show-window, selection-translate, and screenshot-translate actions. Settings use a real keyboard recorder, normalize to the native accelerator grammar, and reject malformed or duplicate combinations before saving; live Windows validation is still required.
- `SelectedTextReader`: first try UI Automation, then clipboard copy fallback, then return a clear failure reason.
- `ScreenshotOCR`: implemented with a virtual-desktop region-selection overlay, GDI capture, and the installed Windows OCR language packs through `Windows.Media.Ocr`.
- `TrayService`: tray icon, left-click restore, close-to-tray, and right-click actions for show, quick input translation, settings, history, WebDAV history sync, and quit are implemented. Native `tray.action` events route through `TrayActionDispatcher` into real Dart workflows.
- `SystemNotificationService`: `notification.show` reuses the installed notification-area icon and maps informational/error results to native Windows notifications. The persisted General setting controls background WebDAV startup/periodic sync notifications.
- `WindowBehavior`: close-to-tray, always-on-top, launch-at-startup, hide-on-blur, and window placement persistence are implemented in the native runner. Restored placement is validated against connected monitors before applying. Hide-on-blur uses `WM_ACTIVATE` and excludes the tray-menu interaction window.

## Current Scaffold

- `main.dart` provides the first real UI shell: input, language pickers, translate, copy, clear, settings, searchable history list, favorite/delete/clear history actions, and manual history sync action.
- `history_record.dart` and `history_sync.dart` port the shared history schema and merge behavior.
- `webdav_sync.dart` implements `/Pythia/history/history.json` sync with local backup before merge/write and a connection-test path that confirms the remote folders and history file without mutating local history.
- `portable_backup.dart` implements the versioned allowlist backup and transactional merge restore. Settings uses `file_selector_windows` for native local dialogs; `webdav_portable_backup.dart` stores the same payload at `/Pythia/settings/portable-backup.json` using temporary upload plus MOVE/fallback PUT.
- `local_storage.dart` persists settings and history as local JSON using the app support directory. History deletion is logical deletion for sync safety; favorite changes mark records pending upload; clear history marks all visible records pending delete.
- WebDAV settings include manual sync, connection test, automatic interval sync, last-sync status/error fields, and a clear-WebDAV action. Automatic intervals persist a positive integer and minute/hour/day/week unit, convert to exact seconds, and reconfigure the periodic scheduler immediately after save. WebDAV passwords still go through Credential Manager, not `settings.json`.
- WebDAV reliability includes bounded transient retry, a 10-second local-history-change debounce, a single-flight guard, and a tray-quit handshake that waits for active/final synchronization before native shutdown.
- `translation_service.dart` includes real Google, Baidu, Youdao, OpenAI-compatible Chat Completions, DeepL, and LibreTranslate providers plus the local diagnostic provider. `main.dart` wires enabled providers into the active registry, settings persist only non-secret configuration, and provider credentials use Windows Credential Manager. The registry also mirrors the macOS mixed Chinese/English target-priority routing before sending requests or saving history.
- `update_checker.dart` and the settings dialog include a real latest-release check against `https://api.github.com/repos/douxy1994/Pythia/releases/latest`, compare it with version `1.0.0`, and display the release URL or a clear error.
- Platform interfaces are explicit. Credential storage has a MethodChannel and C++ Credential Manager implementation registered by the native runner. Selection translation reads focused UI Automation TextPattern selections first and uses a clipboard-copy fallback only when needed; screenshot translation uses a virtual-desktop selection overlay, GDI capture, and Windows Runtime `OcrEngine`; launch-at-startup writes the current user Run key; always-on-top calls `SetWindowPos`; tray install/update creates a native notification-area icon and complete action menu; close-to-tray hides the window on `WM_CLOSE`; hide-on-blur reacts to inactive `WM_ACTIVATE`; global hotkeys use `RegisterHotKey` and dispatch native callbacks back to Dart; window placement is saved/restored through HKCU `Software\\Pythia`.
- `release_package_verifier.dart` plus `tool/verify_release_package.dart` provide the Windows release gate for x64 architecture, "no bundled plugins", and "no private release secrets". The verifier requires PE machine `0x8664`, rejects `.potext` packages, legacy plugin runner/source trees, and common private-key/API-token markers while allowing normal Flutter Windows release files.
- `history_sync_test.dart` covers merge behavior and corrupt remote protection. `translation_service_test.dart` covers Google response joining, Baidu MD5 signing, Youdao v3 SHA-256 signing, OpenAI-compatible request construction, credential lookup, missing-key failure behavior, and mixed Chinese/English language routing. `update_checker_test.dart` covers release parsing, multi-segment version comparison, and API failure reporting. `platform_services_test.dart` covers platform-channel method names and argument contracts. `release_package_verifier_test.dart` covers clean package, plugin payload, legacy source tree, secret marker, and missing-directory cases.

## Next Milestone

1. Download the verified `Pythia-1.0.0-windows-x64` Actions artifact or build locally with the pinned Flutter version.
2. Run the installer and verify startup, restart, uninstall, Credential Manager, UI Automation selection, screenshot OCR, launch-at-startup, tray, hotkeys, WebDAV, and always-on-top behavior.
3. Verify screenshot OCR, global-hotkey conflicts, and the Authenticode-signed updater on a real Windows installation with Chinese/English language packs. The recorder UI, tray callbacks, hide-on-blur, secure download/install channel, and release check UI are implemented in code.
4. Add the remaining macOS first-party provider presets beyond DeepL and LibreTranslate, including provider-specific settings and contract tests.
5. Exercise WebDAV connection test/manual sync/automatic sync on a real Windows machine and with the same WebDAV account used by macOS.
6. Build release artifacts and verify plugin exclusion.

## Verification

Run on Windows:

```powershell
flutter test
flutter build windows --release
dart run tool/verify_release_package.dart build\windows\x64\runner\Release
```

Then verify the feature matrix in `Docs/FEATURE_MATRIX.md` and the release gates in `Docs/RELEASE_CHECKLIST.md`.
