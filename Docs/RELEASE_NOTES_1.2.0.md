# Pythia 1.2.0

发布日期：2026-08-04

## 中文

Pythia 1.2.0 为 macOS 带来简约翻译窗口、自定义大模型翻译服务，以及更可靠的截图权限处理。本次 Release 仅发布 macOS Apple silicon 资产；Windows 客户端仍保持 Preview `1.0.0+100`，后续按独立验收流程更新。

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

- `Pythia-1.2.0-macos-arm64.dmg`：macOS 14 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.2.0-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

---

## English

Pythia 1.2.0 adds a compact translation window, configurable LLM translation services, and more reliable screenshot-permission handling on macOS. This Release contains macOS Apple silicon assets only; the Windows client remains Preview `1.0.0+100` and will be updated through its separate acceptance process.

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

- `Pythia-1.2.0-macos-arm64.dmg`: macOS 14 or later on Apple silicon (`arm64`).
- `Pythia-1.2.0-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.
