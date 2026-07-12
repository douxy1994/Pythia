# Pythia

Pythia is a modern translation app project for macOS and Windows. It was created after the original product idea behind Pot stopped receiving active updates, and is being rebuilt as a cleaner Pythia codebase with native platform experiences, cross-platform data contracts, and a maintainable release process.

Pythia 1.0.0 is the current version target.

## Current State

- macOS: native AppKit application, currently buildable and runnable on this machine.
- Windows x64: Flutter client and native Win32 host are present under `Windows/Pythia.Windows`; executable builds still require an x64 Windows development environment with Flutter and Visual Studio Build Tools.
- Shared contracts: history sync schemas and a tested Swift `PythiaCore` merge model live under `Core/`.
- Plugins: release packages must not bundle plugins. Legacy plugin compatibility is local user data only.

## Features

- Multi-service translation results in one main window.
- Source and target language selection.
- Smart target language selection with a configurable second target language.
- Selection translation through platform selection APIs or clipboard fallback.
- Screenshot translation and OCR.
- Clipboard monitoring.
- Translation history.
- Text-to-speech and collection service entry points.
- Configurable global shortcuts.
- Local config backup and restore.
- WebDAV backup/restore and macOS WebDAV history sync using the shared `/Pythia/history/history.json` format.
- Proxy settings.
- Light, dark, and system appearance modes.
- Custom theme color.
- Native macOS status-bar behavior and Windows notification-area tray behavior.
- External HTTP endpoints for automation on macOS.

## Requirements

### macOS

- macOS 26 or later.
- Apple silicon Mac.
- Xcode 26.6 or later.
- Local code-signing identity named `Pot Local Code Signing`.

The local signing identity name is retained only to keep existing macOS Accessibility/TCC trust stable across updates on this machine. Changing it would make macOS treat the app as a new accessibility client.

### Windows

The Windows x64 client has Flutter/Dart logic tests that can run in this macOS workspace, but executable builds still require an x64 Windows runtime and Visual Studio Build Tools. CMake rejects non-x64 toolchains, and the release verifier checks that `Pythia.exe` uses PE machine `0x8664` (AMD64). On Windows, follow `Docs/WINDOWS_DEVELOPMENT.md` and `Windows/Pythia.Windows/README.md`.

## Build

Build, install, sign, launch, and verify the macOS app:

```sh
./script/build_and_run.sh --verify
```

Create a macOS release app and DMG:

```sh
./script/package_release.sh
```

Release output:

```text
release/Pythia/Pythia.app
release/Pythia/Pythia.dmg
```

## Verification

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
codesign -d -r- /Applications/Pythia.app 2>&1
hdiutil verify release/Pythia/Pythia.dmg
```

Shared core tests:

```sh
cd Core/PythiaCore
swift test
```

Windows logic tests and release package gate:

```sh
cd Windows/Pythia.Windows
flutter test
./tool/test_native_contracts.sh
dart run tool/verify_release_package.dart build/windows/x64/runner/Release
```

Run the Windows release package gate after `flutter build windows --release` on an x64 Windows machine. The gate rejects non-AMD64 executables, bundled plugins, and private key/token markers.

## Repository Layout

```text
Pythia.xcodeproj/       macOS Xcode project
Pythia/App/             macOS app delegate, menu bar, status item
Pythia/Models/          macOS model definitions still used by the native app
Pythia/Stores/          macOS preferences and history storage
Pythia/Services/        macOS translation, OCR, backup, HTTP, hotkeys, updates
Pythia/Views/           macOS window controllers and reusable controls
Pythia/Resources/       app and status-bar icons
Core/PythiaCore/        platform-neutral Swift core model and merge tests
Core/Schemas/           cross-platform JSON schemas
Windows/Pythia.Windows/ Flutter Windows scaffold
Docs/                   architecture, sync, Windows, and release documents
script/                 macOS build, install, and package scripts
release/                generated local release artifacts
```

## Update Checks

Pythia checks releases from:

```text
https://github.com/douxy1994/Pythia/releases
```

## Documents

- `Docs/ARCHITECTURE.md`
- `Docs/WEBDAV_SYNC.md`
- `Docs/WINDOWS_DEVELOPMENT.md`
- `Docs/FEATURE_MATRIX.md`
- `Docs/RELEASE_CHECKLIST.md`

## Known Limits

- Windows has a Flutter scaffold but is not yet build-verified in this workspace.
- macOS WebDAV history sync exists; live cross-device macOS/Windows sync still needs Windows build verification and a WebDAV test account.
- macOS runtime credential storage was intentionally kept out of Keychain after repeated password prompts; this must be revisited carefully before cross-platform sync release.
- macOS Accessibility permission is required for selection translation.
- Screen Recording permission is required for screenshot OCR and screenshot translation.
- Release packages do not include plugins.
