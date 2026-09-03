# Pythia 1.2.3

Pythia 1.2.3 is a Windows-only patch release for flexible global shortcuts and Google translation reliability. The macOS release remains at 1.2.2.

## 中文

- 全局快捷键不再强制要求 Ctrl、Alt、Shift 或 Win 修饰键；现在可以直接录入 Insert、Home 等单一按键。
- 新增独立的“输入翻译”快捷键设置，默认 `Ctrl+Alt+T`；触发后清空旧内容并聚焦输入页。
- 扩展主键支持范围：方向键、Page Up/Page Down、Insert/Delete、Home/End、Esc、Tab、Enter、Space、F1–F24、字母、数字与数字小键盘按键均可使用，也继续支持原有组合键。
- 录入框可截获已被其他程序占用的按键；单键与组合键保存时都会检查系统级占用，设置页会显示明确提示并自动恢复原快捷键。
- 快捷键输入框会生成统一格式；无效按键和同一设置内的重复快捷键仍会被拦截。
- Google 翻译改用网页 RPC 主通道，并在其不可用时回退到 Chrome 字典接口，避免旧匿名接口持续返回 HTTP 429。

## English

- Global shortcuts no longer require Ctrl, Alt, Shift, or Win; a single key such as Insert or Home can now be recorded directly.
- Added a separate Input Translation shortcut, defaulting to `Ctrl+Alt+T`; it clears previous content and focuses the input page.
- Main-key support now includes arrows, Page Up/Page Down, Insert/Delete, Home/End, Escape, Tab, Enter, Space, F1–F24, letters, digits, and numeric-keypad keys while retaining modifier combinations.
- The recorder now sees keys already owned by another application. Single-key and modified shortcuts both check system-level ownership; conflicts show a clear Settings alert and restore the previous shortcut automatically.
- The recorder emits canonical shortcut strings. Invalid and duplicate shortcuts are still rejected.
- Google Translate now uses the web RPC endpoint first and falls back to the Chrome dictionary endpoint instead of relying on the legacy endpoint that can return HTTP 429.

## Windows download

- `Pythia-1.2.3-windows-x64.exe`
- `Pythia-1.2.3-windows-x64.exe.sha256`

The Windows installer is not Authenticode-signed and may trigger Microsoft Defender SmartScreen. Verify the SHA-256 sidecar before installation. Release packages contain no third-party plugins or user credentials.
