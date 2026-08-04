<div align="center">
  <img src="./Docs/images/app-icon.png" width="132" alt="Pythia app icon">

  # Pythia

  **Every translation service, one native window — select, shoot, translate.**

  A local-first desktop translator for macOS and Windows: multi-service result cards, screenshot OCR, global hotkeys, syncable history, and a real plugin system.

  [![Version](https://img.shields.io/badge/Version-1.2.2-80B847)](#download)
  [![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](#macos)
  [![Windows](https://img.shields.io/badge/Windows_x64-1.2.2-0078D4?logo=windows11&logoColor=white)](#windows)
  [![Swift](https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white)](#macos-build)
  [![WinUI](https://img.shields.io/badge/C%23-WinUI_3-512BD4?logo=dotnet&logoColor=white)](#windows-development)
  [![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-2ea44f.svg)](./LICENSE)

  [English](README.md) | [简体中文](README.zh-CN.md)

  <br>
  <img src="./Docs/images/screenshot-macos.png" width="920" alt="Pythia translator window on macOS">
</div>

## What is Pythia?

Desktop translation is usually one window, one service, one opinion. When the result reads wrong you open a browser, paste the text again, and compare by hand. Pythia removes that loop: one hotkey captures text from anywhere — selection, input, or screenshot — and every enabled service answers **side by side**, so you pick the best rendering instead of trusting the only one you got.

| Everyday friction | How Pythia handles it |
| --- | --- |
| One service, take it or leave it | Independent result cards per service; re-translate any single card on demand |
| Selected text trapped in apps | Accessibility / UI Automation reading with clipboard fallback — including Microsoft Word across page breaks |
| Screenshots full of text | Screenshot OCR and screenshot translation via macOS Vision |
| Mixed Chinese/English misrouted | Dominant-script routing: embedded English terms no longer flip Chinese text onto the wrong direction |
| History stuck on one machine | WebDAV sync with merge, favorites, and deletion state through a shared `/Pythia/history/history.json` format |
| Keys pasted into random apps | Local `credentials.json` at `0600` on macOS, Windows Credential Manager — verified in Settings before use |
| Service X is missing | First-class `.pythia` plugins (`.potext` auto-converts), with an isolated runtime and a development guide |

## One keystroke, every service

```mermaid
flowchart LR
    A["Select text · Type · Screenshot<br/>⇧⌘E / ⇧⌘D / ⇧⌘O"] --> B["Pythia translator window"]
    B --> C["Google · DeepL · Baidu<br/>Youdao · OpenAI · LibreTranslate"]
    B --> D[".pythia plugins<br/>Qwen · DeepSeek · MiMo · …"]
    C --> E["Side-by-side result cards"]
    D --> E
    E --> F["Copy · Re-translate · Favorite"]
    F --> G["Searchable history"]
    G <--> H["WebDAV / local backup<br/>macOS ↔ Windows"]
```

## Core capabilities

### Multi-service translation

- Selection and screenshot-OCR translation can open a compact result-only window with retry, copy, synchronized multi-service selection, and one-click expansion.
- Google works out of the box; custom LLM APIs support OpenAI Chat Completions and Anthropic Messages on both platforms.
- Custom LLM translation splits long documents at semantic boundaries and applies bounded retries for timeouts, rate limits, and transient upstream failures. On macOS, the shared pipeline also guarantees numeric/grapheme-safe ~1,800-character segments, exact source reconstruction, 300-second full-response attempts, and immediate cancellation. DeepL, Baidu, Youdao, and LibreTranslate keep their existing paths.
- Windows includes a default-off experimental floating selection button: selecting text in Word, common PDF readers, browsers, or chat clients shows a small Pythia icon that opens compact translation only after an explicit click.
- **Settings → Services → Verify** runs a real translation against the values you just typed — no guessing whether a key works.
- Dominant-script Chinese/English routing picks the right direction for mixed text; smart target language follows detection.
- Result cards support per-card copy, re-translate, TTS, and automatic copy rules.

### Capture from anywhere

- Global hotkeys for selection translate, input translate, screenshot OCR, and screenshot translation — all configurable.
- Selected-text reading falls back to the clipboard when an app blocks accessibility APIs.
- OCR runs on macOS Vision with auto language recognition; legacy OCR plugins still work.

### History, sync, and backup

- Searchable history with favorites and deletion state, or turn history off entirely.
- Incremental WebDAV sync merges concurrent additions from macOS and Windows without losing records.
- Portable backups exclude keys, WebDAV credentials, hotkeys, and window state.

### A real plugin system

- `.pythia` packages: Manifest, JavaScript entry, isolated Node runtime, declared network permissions, typed errors.
- `.potext` files are converted and validated automatically, with a compatibility fallback.
- Plugin `secret` config fields live in the same private credential store, never in settings JSON.
- The macOS and Windows plugin runners are kept byte-identical and validated by `script/validate_pythia_plugins.mjs`.

## Platforms

<table>
  <tr>
    <td width="50%" align="center">
      <img src="./Docs/images/platform-macos.svg" width="100%" alt="Pythia for macOS">
      <h3 id="macos">macOS</h3>
      <p><strong>Native · current release 1.2.1</strong></p>
      <p>Swift · AppKit · macOS 14+ · Apple silicon</p>
      <p>Menu-bar app, multi-service cards, OCR, hotkeys, history sync, plugins, verified release packaging.</p>
    </td>
    <td width="50%" align="center">
      <img src="./Docs/images/platform-windows.svg" width="100%" alt="Pythia for Windows">
      <h3 id="windows">Windows</h3>
      <p><strong>Native WinUI 3 · current release 1.2.2</strong></p>
      <p>C# 14 · .NET 10 · x64 · Windows 10/11</p>
      <p>Compact translation, multi-service cards, Windows OCR, hotkeys, history sync, plugins, and Inno Setup packaging.</p>
    </td>
  </tr>
</table>

## Download

### macOS

[Download Pythia 1.2.1 for macOS Apple silicon](https://github.com/douxy1994/Pythia/releases/download/v1.2.1/Pythia-1.2.1-macos-arm64.dmg)

- Requires macOS 14 or later, Apple silicon (`arm64`).
- The current build uses the project's stable local code-signing identity and is not Apple Developer ID notarized — if macOS blocks the first launch, allow it in System Settings > Privacy & Security.
- The DMG and its SHA-256 checksum are published together on the [v1.2.1 release page](https://github.com/douxy1994/Pythia/releases/tag/v1.2.1).

### Windows

[Download Pythia 1.2.2 for Windows x64](https://github.com/douxy1994/Pythia/releases/download/v1.2.2/Pythia-1.2.2-windows-x64.exe)

- Requires 64-bit Windows 10 or Windows 11.
- The installer and SHA-256 checksum are published on the [v1.2.2 release page](https://github.com/douxy1994/Pythia/releases/tag/v1.2.2); the macOS 1.2.2 arm64 assets will be added to that same Release after the port is complete.
- The installer contains Pythia and its isolated runtime only; it bundles no third-party plugin or `.pythia` package.
- The Windows 1.2.2 installer is not Authenticode-signed yet and might trigger Microsoft Defender SmartScreen. Verify its SHA-256 checksum before installation.

## Downloadable plugins

Pythia does not bundle third-party plugins. Configuration-free packages live in [`Plugins/`](Plugins/README.md):

| Plugin | Download | Credentials required |
| --- | --- | --- |
| Alibaba Cloud Qwen3.5-35B-A3B | [`.pythia`](Plugins/aliyun-qwen3.5-35b-a3b-1.1.1.pythia) | Alibaba Cloud Model Studio API Key |
| DeepSeek | [`.pythia`](Plugins/deepseek-1.1.1.pythia) | DeepSeek API Key |
| Qiniu GLM 4.5 Air (free) | [`.pythia`](Plugins/qiniu-glm-4.5-air-free-1.1.1.pythia) | Qiniu API Key |
| SenseNova | [`.pythia`](Plugins/sensenova-1.1.1.pythia) | SenseNova API Key |
| SiliconFlow | [`.pythia`](Plugins/siliconflow-1.1.1.pythia) | SiliconFlow API Key |
| Xiaomi MiMo | [`.pythia`](Plugins/xiaomi-mimo-1.1.1.pythia) | Xiaomi MiMo API Key |

Install from **Settings > Plugins > Install Plugin**, then configure credentials inside Pythia. Packages contain no user credentials, history, or local paths. See the [plugin catalog and checksums](Plugins/README.md) for details.

## Build a Pythia plugin

New plugins should use the `.pythia` format; `.potext` is accepted only for compatibility and migration.

- [Complete plugin development guide](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [Runnable plugin examples](examples/plugins/README.md)
- [Downloadable plugin catalog](Plugins/README.md)

The guide covers package layout, Manifest schema, configuration and secret fields, request/response protocol, network permissions, isolated runtime, error model, conversion behavior, tests, packaging commands, and the publication checklist.

## macOS build

### Requirements

- macOS 14 or later, Apple silicon Mac, Xcode 27 beta or later.
- Local code-signing identity named `Pot Local Code Signing` — it preserves the installed app's Accessibility/TCC identity across local updates; do not casually change the signing requirement or bundle identifier.

### Build, run, package, verify

```sh
./script/build_and_run.sh --verify   # build + install to /Applications + launch
./script/package_release.sh          # signed release/Pythia/Pythia.app + Pythia.dmg
```

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
codesign -d -r- /Applications/Pythia.app 2>&1
hdiutil verify release/Pythia/Pythia.dmg
```

## Windows development

The current Windows client is x64/AMD64 only, under [`Windows/Pythia.WinUI`](Windows/Pythia.WinUI/README.md). It uses C# 14, .NET 10, WinUI 3, Windows App SDK, Credential Manager, UI Automation, Windows OCR, global hotkeys, tray/startup integration, Inno Setup packaging, and release gates that reject plugins and private material. `Windows/Pythia.Windows` is retained only as a legacy compatibility reference.

The complete continuation document for a Windows Codex agent is **[WINDOWS_CODEX_HANDOFF.md](WINDOWS_CODEX_HANDOFF.md)** — branch baseline, toolchain, source map, MethodChannel contract, test commands, known gaps, acceptance matrix, and definition of done.

```powershell
Set-Location Windows\Pythia.WinUI
node ..\..\script\validate_pythia_plugins.mjs
dotnet build .\Pythia.WinUI.csproj -c Release -p:Platform=x64
dotnet run --project ..\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
.\tool\build-installer.ps1 -Version 1.2.2
```

## Data and privacy

| Platform | Default data location | Credentials |
| --- | --- | --- |
| macOS | `~/Library/Application Support/Pythia` | `credentials.json`, owner-only `0600` — no Keychain prompts |
| Windows | `%LOCALAPPDATA%` app directory | Windows Credential Manager |

- Portable backups exclude API keys, WebDAV credentials, shortcuts, startup state, and window state.
- Release packages contain no third-party plugins and are scanned for private material before publishing.
- The repository and release assets must never contain private keys, API keys, passwords, user history, or local configuration.
- Windows 1.2.2 is published without Authenticode signing; signing remains planned, and certificate files must never enter Git.

## Repository layout

```text
Pythia.xcodeproj/        Native macOS Xcode project
Pythia/                  macOS AppKit application
Core/PythiaCore/         Shared Swift models and merge tests
Core/Schemas/            Cross-platform JSON schemas
Windows/Pythia.WinUI/    Native WinUI 3 Windows client
Windows/Pythia.Windows/  Legacy Flutter/Win32 compatibility reference
Plugins/                 Public, credential-free .pythia downloads
examples/plugins/        Source-level plugin examples
Docs/                    Architecture, sync, Windows, plugin, and release docs
script/                  Build, package, and validation scripts
WINDOWS_CODEX_HANDOFF.md Complete Windows continuation document
```

## Development branch

Active development happens on the `master` branch of [github.com/douxy1994/Pythia](https://github.com/douxy1994/Pythia) (remote `douxy`). Historical `codex/*` branches are archived experiments and must not be used as a development base; deprecated branches carry an in-tree `DEPRECATED.md` notice.

## Documentation

- [Pythia 1.2.2 release notes](Docs/RELEASE_NOTES_1.2.2.md)
- [Pythia 1.2.1 release notes](Docs/RELEASE_NOTES_1.2.1.md)
- [Pythia 1.2.0 release notes](Docs/RELEASE_NOTES_1.2.0.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Feature matrix](Docs/FEATURE_MATRIX.md)
- [Plugin development guide](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [Public plugin catalog](Plugins/README.md)
- [WebDAV synchronization](Docs/WEBDAV_SYNC.md)
- [Windows development](Docs/WINDOWS_DEVELOPMENT.md) · [Windows Codex handoff](WINDOWS_CODEX_HANDOFF.md)
- [Run and test](Docs/RUN_AND_TEST.md) · [Release checklist](Docs/RELEASE_CHECKLIST.md)

## License

Pythia is distributed under the [GNU Affero General Public License v3.0](LICENSE).

Copyright © 2026 douxy1994.
