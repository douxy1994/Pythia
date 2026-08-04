# Pythia 1.2.0

发布日期：2026-08-04

## 中文

Pythia 1.2.0 在 macOS 与 Windows x64 上同步提供简约翻译窗口和自定义大模型翻译服务，并强化截图、划词与资源占用控制。两个平台的安装资产合并发布在同一个 Release。

### Windows 功能对齐与稳定性

- 原生 WinUI 3 客户端版本、安装程序和更新检查统一为 `1.2.0`。
- 简约窗口以译文为核心，保留同步的多选服务栏、单服务重试、复制和展开完整窗口。
- UI Automation 选区读取使用有界等待且不遍历 Chromium 整棵子树；翻译并发限制为 4 路。
- OCR 捕获限制约 2000 万像素，避免高 DPI、多屏和混合显卡机器出现内存/显存峰值。
- 关闭 ReadyToRun，并排除符号、XML 文档和无关卫星资源以缩小安装包。
- 安装包不包含任何第三方插件、`.pythia` 或 `.potext` 包；插件继续独立下载。

### 简约翻译窗口

- 划词翻译和截图 OCR 翻译可默认使用简约窗口，只显示译文结果、重试和复制按钮。
- 右上角展开按钮可把当前内容无缝切换到完整 Pythia 窗口。
- 简约窗口提供可多选的翻译服务选择栏，并与完整窗口的服务选择、顺序实时同步。
- “设置 → 通用”新增默认打开简约窗口的开关。

### 自定义大模型翻译服务

- 可配置显示名称、接口类型、API 基础地址、模型和 API Key。
- 支持 OpenAI Chat Completions 与 Anthropic Messages 两种接口格式及其兼容服务。
- API Key 只写入本机私有凭据文件，不进入可移植备份、日志或 Release 资产。

### 截图与屏幕录制权限

- 截图前同时执行系统权限预检与授权请求，不再仅依据旧状态判断。
- 首次获得屏幕录制权限后自动重启 Pythia，使新权限立即绑定到当前签名应用实例。
- 截图 OCR 改用受控临时 PNG，避免剪贴板竞争导致的空截图或旧内容。
- 用户取消选区与真正的权限/捕获失败分别提示。

### 下载

- `Pythia-1.2.0-windows-x64.exe`：Windows 10/11 x64 安装程序。
- `Pythia-1.2.0-windows-x64.exe.sha256`：Windows 安装程序的 SHA-256 校验文件。
- `Pythia-1.2.0-macos-arm64.dmg`：macOS 14 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.2.0-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

Windows 1.2.0 安装程序暂未进行 Authenticode 签名，可能触发 Microsoft Defender SmartScreen；请在安装前核对 SHA-256。

---

## English

Pythia 1.2.0 brings the compact translation window and configurable LLM services to both macOS and Windows x64, with stronger capture reliability and bounded resource usage. Assets for both platforms are published in one Release.

### Windows parity and stability

- Aligns the native WinUI 3 application, installer, and updater at version `1.2.0`.
- Keeps compact mode result-focused while retaining synchronized multi-service selection, retry, copy, and expand actions.
- Bounds UI Automation selection reads, avoids full Chromium subtree scans, and limits translation concurrency to four.
- Caps OCR capture at approximately 20 million pixels to prevent memory and GPU spikes on high-DPI and multi-display systems.
- Reduces package size by disabling ReadyToRun and excluding symbols, XML documentation, and unused satellite resources.
- Bundles no third-party plugins, `.pythia`, or `.potext` packages; plugins remain separate downloads.

### Compact translation window

- Selection and screenshot-OCR translation can open a compact window that shows only results, retry, and copy actions.
- The expand button opens the full Pythia window without losing the current translation.
- The compact window includes a multi-select service picker synchronized with the full window's selection and ordering.
- A new General setting controls whether selection and screenshot-OCR translation use the compact window by default.

### Configurable LLM translation services

- Configure a display name, API type, base URL, model, and API key.
- Supports OpenAI Chat Completions and Anthropic Messages request formats and compatible providers.
- API keys remain in the private local credentials file and are excluded from portable backups, logs, and release assets.

### Screenshot and screen-recording permission

- Screenshot capture now performs both the system preflight check and the permission request instead of relying on stale state.
- Pythia restarts automatically after screen-recording access is first granted so the permission applies to the current signed app instance.
- OCR capture uses a controlled temporary PNG to avoid clipboard races and stale images.
- User cancellation is reported separately from permission and capture failures.

### Downloads

- `Pythia-1.2.0-windows-x64.exe`: Windows 10/11 x64 installer.
- `Pythia-1.2.0-windows-x64.exe.sha256`: SHA-256 checksum for the Windows installer.
- `Pythia-1.2.0-macos-arm64.dmg`: macOS 14 or later on Apple silicon (`arm64`).
- `Pythia-1.2.0-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The Windows 1.2.0 installer is not Authenticode-signed yet and might trigger Microsoft Defender SmartScreen. Verify its SHA-256 checksum before installation.
