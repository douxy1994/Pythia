# Pythia

[English](README.md) | [简体中文](README.zh-CN.md)

Pythia is a modern desktop translation application for macOS and Windows. The macOS client is a native Swift/AppKit application. The Windows client uses C# 14, .NET 10, WinUI 3, and Windows App SDK. Both clients share the same history, WebDAV, language-routing, backup, and `.pythia` plugin contracts.

Current version: **1.2.0**

## Download

### macOS

[Download Pythia 1.2.0 for macOS Apple silicon](https://github.com/douxy1994/Pythia/releases/download/v1.2.0/Pythia-1.2.0-macos-arm64.dmg)

- Requires macOS 14 or later.
- Apple silicon (`arm64`) only.
- The current build uses the project's stable local code-signing identity and is not Apple Developer ID notarized.
- The DMG and its SHA-256 checksum are published together on the [v1.2.0 release page](https://github.com/douxy1994/Pythia/releases/tag/v1.2.0).

### Windows

[Download Pythia 1.2.0 for Windows x64](https://github.com/douxy1994/Pythia/releases/download/v1.2.0/Pythia-1.2.0-windows-x64.exe)

- Requires 64-bit Windows 10 or Windows 11.
- The installer and its SHA-256 checksum are published alongside the macOS assets on the [v1.2.0 release page](https://github.com/douxy1994/Pythia/releases/tag/v1.2.0).
- The installer contains the Pythia application and its isolated runtime only. No third-party plugin or `.pythia` package is bundled.
- The Windows 1.2.0 installer is not Authenticode-signed yet and might trigger a Microsoft Defender SmartScreen warning. Verify its SHA-256 checksum before installation.

## What Pythia Does

- Shows independent translation result cards from multiple services at the same time.
- Supports source and target language selection and target-first Chinese/English mixed-text routing.
- Reads selected text through platform accessibility/UI Automation APIs with clipboard fallback.
- Provides screenshot OCR and screenshot translation.
- Stores searchable translation history with favorite and deletion state.
- Supports configurable global hotkeys, tray/status-bar actions, always-on-top, startup, and window behavior.
- Provides local and WebDAV backup/restore.
- Synchronizes history through the shared `/Pythia/history/history.json` format.
- Supports light, dark, and system appearance modes.
- Supports first-class `.pythia` plugins and compatible `.potext` conversion.

## Downloadable Plugins

Pythia does not bundle third-party plugins in the application or installer. The repository provides separately downloadable, configuration-free packages in [`Plugins/`](Plugins/README.md).

| Plugin | Download | Credentials required |
| --- | --- | --- |
| Alibaba Cloud Qwen3.5-35B-A3B | [`.pythia`](Plugins/aliyun-qwen3.5-35b-a3b-1.0.0.pythia) | Alibaba Cloud Model Studio API Key |
| DeepSeek | [`.pythia`](Plugins/deepseek-1.0.0.pythia) | DeepSeek API Key |
| Qiniu GLM 4.5 Air (free) | [`.pythia`](Plugins/qiniu-glm-4.5-air-free-1.0.0.pythia) | Qiniu API Key |
| SenseNova | [`.pythia`](Plugins/sensenova-1.0.0.pythia) | SenseNova API Key |
| SiliconFlow | [`.pythia`](Plugins/siliconflow-1.0.0.pythia) | SiliconFlow API Key |
| Xiaomi MiMo | [`.pythia`](Plugins/xiaomi-mimo-1.0.0.pythia) | Xiaomi MiMo API Key |

Install a package from **Settings > Plugins > Install Plugin** in the Windows client, then configure credentials from its plugin card. The packages contain no user credentials, API keys, WebDAV settings, history, or local machine paths.

See the [plugin catalog and checksums](Plugins/README.md) for package details.

## Build a Pythia Plugin

New plugins should use the `.pythia` format. `.potext` is accepted only for compatibility and migration.

- [Complete Pythia plugin development guide](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [Runnable plugin examples](examples/plugins/README.md)
- [Downloadable plugin catalog](Plugins/README.md)

The guide defines the package layout, Manifest schema, configuration and secret fields, request/response protocol, network permissions, isolated runtime, error model, conversion behavior, tests, packaging commands, and publication checklist.

## macOS Build

### Requirements

- macOS 26 or later.
- Apple silicon Mac.
- Xcode 26.6 or later.
- Local code-signing identity named `Pot Local Code Signing` for this development machine.

The retained local identity preserves the installed app's Accessibility/TCC identity during local updates. Do not casually change the signing requirement or bundle identifier.

### Build and Run

```sh
./script/build_and_run.sh --verify
```

### Package

```sh
./script/package_release.sh
```

Generated files:

```text
release/Pythia/Pythia.app
release/Pythia/Pythia.dmg
```

### Verify

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
codesign -d -r- /Applications/Pythia.app 2>&1
hdiutil verify release/Pythia/Pythia.dmg
```

## Windows Development

The Windows client is x64/AMD64 only. Its current native source is under [`Windows/Pythia.WinUI`](Windows/Pythia.WinUI/README.md) and includes:

- A native Windows 11 WinUI 3 interface and C# translation core.
- Credential Manager, UI Automation/clipboard selection, Windows OCR, global hotkeys, tray, and startup integration.
- A byte-identical isolated JavaScript plugin runner plus compatible `.pythia` configuration and secret handling.
- Self-contained x64 publishing and Inno Setup packaging.
- `Windows/Pythia.Windows` retained as the older Flutter/Win32 implementation and compatibility reference.

The complete continuation document for a Windows Codex agent is:

**[WINDOWS_CODEX_HANDOFF.md](WINDOWS_CODEX_HANDOFF.md)**

It includes the exact branch baseline, toolchain, source map, native MethodChannel contract, test commands, known UI/IME gaps, platform acceptance matrix, WebDAV/plugin contracts, and definition of done.

Basic Windows commands:

```powershell
Set-Location Windows\Pythia.WinUI
node ..\..\script\validate_pythia_plugins.mjs
dotnet build .\Pythia.WinUI.csproj -c Release -r win-x64
dotnet run --project ..\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
.\tool\build-installer.ps1 -Version 1.2.0
```

The native Windows client passes x64 compilation, plugin sandbox tests, public-plugin validation, installer and SHA-256 creation, silent installation, and launch verification. Release packaging rejects third-party plugin packages from the publish tree. Authenticode signing remains planned for a later release.

## Plugin Contract Verification

Validate all runnable examples and ensure the macOS and Windows plugin runners remain byte-identical:

```sh
node script/validate_pythia_plugins.mjs
```

Shared Swift core tests:

```sh
cd Core/PythiaCore
swift test
```

## Repository Layout

```text
Pythia.xcodeproj/        Native macOS Xcode project
Pythia/                  macOS AppKit application
Core/PythiaCore/         Shared Swift models and merge tests
Core/Schemas/            Cross-platform JSON schemas
Windows/Pythia.Windows/  Flutter Windows client and Win32 host
Plugins/                 Public, credential-free .pythia downloads
examples/plugins/        Source-level plugin examples
Docs/                    Architecture, sync, Windows, plugin, and release docs
script/                  Build, package, and validation scripts
WINDOWS_CODEX_HANDOFF.md Complete Windows continuation document
```

## Security and Privacy

- macOS secrets are stored in `~/Library/Application Support/Pythia/credentials.json` with owner-only `0600` permissions. Pythia does not access macOS Keychain at runtime.
- Windows secrets use Windows Credential Manager.
- Plugin `secret` fields are separated from normal settings JSON and use the same private macOS credential file.
- Portable backups exclude API keys, WebDAV credentials, shortcuts, startup state, and window state.
- Application release packages contain no third-party plugins.
- The repository and release assets must contain no private keys, API keys, passwords, user history, or local configuration.
- Windows production installers must be Authenticode-signed using a certificate already installed in the build environment; no certificate file belongs in Git.

## Documentation

- [Windows Codex handoff](WINDOWS_CODEX_HANDOFF.md)
- [Pythia 1.2.0 release notes](Docs/RELEASE_NOTES_1.2.0.md)
- [Pythia plugin development guide](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [Public plugin catalog](Plugins/README.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [WebDAV synchronization](Docs/WEBDAV_SYNC.md)
- [Windows development](Docs/WINDOWS_DEVELOPMENT.md)
- [Feature matrix](Docs/FEATURE_MATRIX.md)
- [Run and test](Docs/RUN_AND_TEST.md)
- [Release checklist](Docs/RELEASE_CHECKLIST.md)

## License

Pythia is distributed under the [GNU General Public License v3.0](LICENSE).
