# Run and Test

> **Windows 客户端已于 2026-07-16 转向 WinUI 3。** Windows 的运行与测试命令以
> `Windows/Pythia.WinUI/`（C#/.NET）为准：`dotnet build`、
> `dotnet run --project Windows/Pythia.WinUI.Tests`、
> `dotnet publish Windows/Pythia.WinUI -c Release -r win-x64 --self-contained`，
> 安装包由 `Windows/Pythia.WinUI/tool/build-installer.ps1` 生成。
> 完整命令对照见 [`WINDOWS_DIFF_LIST.md`](WINDOWS_DIFF_LIST.md) 末尾。
> 下文 Windows 段落中的 `flutter` 命令仅适用于旧兼容参考工程 `Windows/Pythia.Windows/`。

## macOS

Build, install, sign, launch, and verify:

```sh
./script/build_and_run.sh --verify
```

Check local control routes:

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
```

Package:

```sh
./script/package_release.sh
hdiutil verify release/Pythia/Pythia-1.2.0-macos-arm64.dmg
shasum -a 256 -c release/Pythia/Pythia-1.2.0-macos-arm64.dmg.sha256
```

Run the macOS UI contracts for the compact/full-window synchronization, custom LLM protocols, and screenshot-permission flow:

```sh
./script/test_macos_ui_contracts.sh
```

Shared core tests:

```sh
cd Core/PythiaCore
swift test
```

## Windows

Windows cannot be built on this macOS machine with the currently installed tools.

On a Windows development machine, follow `Docs/WINDOWS_DEVELOPMENT.md`. The expected commands after Flutter setup are:

```powershell
flutter test
flutter build windows --release
dart run tool/verify_release_package.dart build\windows\x64\runner\Release
```

The platform-independent native tray action map and Windows x64 CMake guard can be checked from the macOS development host:

```sh
cd Windows/Pythia.Windows
./tool/test_native_contracts.sh
```

Before Windows release, verify every Windows row in `Docs/FEATURE_MATRIX.md` and every Windows gate in `Docs/RELEASE_CHECKLIST.md`.
