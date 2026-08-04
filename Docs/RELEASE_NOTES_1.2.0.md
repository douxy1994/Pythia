# Pythia 1.2.0

发布日期：2026-08-04

## Windows 功能对齐

- 新增简约翻译窗口：仅保留同步的多选服务栏、译文卡片、单服务重试、复制和展开完整窗口。
- “设置 → 通用”新增“划词翻译或截图 OCR 翻译时默认打开简约窗口”。
- 自定义大模型翻译服务支持 OpenAI Chat Completions 与 Anthropic Messages，可配置显示名称、接口类型、API 基础地址、模型和 API Key。
- API Key 继续只保存在 Windows Credential Manager，不进入设置 JSON、便携备份、日志或发布资产。
- 翻译请求并发数设为有界的 4 路，避免同时启动过多网络请求或插件进程。
- UI Automation 选区读取移出窗口消息线程，并使用 300–350 ms 有界等待；不再遍历 Chromium 的整棵 UIA 子树。
- 截图选区不再预先复制完整虚拟桌面位图；OCR 捕获限制为约 2000 万像素，避免多屏/高 DPI/混合显卡机器出现显存与内存峰值。
- Windows 程序、安装器和 CI 产物版本统一为 `1.2.0`。

## 体积优化

- Windows Release 关闭 ReadyToRun 预编译，以更小的发布树换取可接受的首次 JIT 成本。
- 安装器排除 PDB、DBG 和 XML 文档文件，只保留英文与简体中文卫星资源。
- 保持 `PublishTrimmed=false`，避免 WinUI 3/XAML 反射裁剪导致运行时缺失。
- 安装器不包含任何第三方插件、`.pythia` 或 `.potext` 包；插件继续从仓库目录单独下载。

## macOS

macOS 1.2.0 同步提供简约翻译窗口、自定义大模型 API，以及改进的截图权限和临时文件处理。Apple silicon DMG 与 SHA-256 校验文件见 GitHub `v1.2.0` Release。

## 下载

- `Pythia-1.2.0-windows-x64.exe`：Windows 10/11 x64 安装程序。
- `Pythia-1.2.0-windows-x64.exe.sha256`：Windows 安装程序的 SHA-256 校验文件。
- `Pythia-1.2.0-macos-arm64.dmg`：macOS 14 或更高版本 Apple silicon 安装镜像。
- `Pythia-1.2.0-macos-arm64.dmg.sha256`：macOS DMG 的 SHA-256 校验文件。

Windows 1.2.0 安装程序暂未进行 Authenticode 签名，可能触发 Microsoft Defender SmartScreen 提示；请在安装前核对 SHA-256。

---

## English

Pythia 1.2.0 brings the Windows x64 WinUI client into feature and version parity with macOS.

### Windows parity

- Adds a result-focused compact translation window with synchronized multi-service selection, per-service retry and copy actions, and one-click expansion to the full window.
- Adds configurable OpenAI Chat Completions and Anthropic Messages endpoints with display name, base URL, model, and API key fields.
- Keeps API keys in Windows Credential Manager and excludes them from settings, portable backups, logs, and release assets.
- Bounds translation concurrency and UI Automation waits, and limits OCR capture size to prevent resource spikes on high-DPI and multi-display systems.
- Aligns the application, installer, and CI artifact version at `1.2.0`.

### Packaging

- Reduces package size by disabling ReadyToRun and excluding symbols, XML documentation, and unused satellite resources.
- Keeps trimming disabled to preserve WinUI 3/XAML runtime behavior.
- Bundles no third-party plugins, `.pythia`, or `.potext` packages; plugins remain separate downloads.

### Downloads

- `Pythia-1.2.0-windows-x64.exe`: Windows 10/11 x64 installer.
- `Pythia-1.2.0-windows-x64.exe.sha256`: SHA-256 checksum for the Windows installer.
- `Pythia-1.2.0-macos-arm64.dmg`: macOS 14 or later on Apple silicon.
- `Pythia-1.2.0-macos-arm64.dmg.sha256`: SHA-256 checksum for the macOS DMG.

The Windows 1.2.0 installer is not Authenticode-signed yet and might trigger Microsoft Defender SmartScreen. Verify its SHA-256 checksum before installation.
