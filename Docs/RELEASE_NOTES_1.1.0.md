# Pythia 1.1.0

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.1.0 重点更新 macOS 客户端的设置体验、插件管理和应用内更新流程。界面使用 AppKit 与 SwiftUI 官方控件，并在系统支持时自动采用 macOS 27 Liquid Glass 外观。

### 设置与界面

- 重构设置侧边栏与全部二级页面：统一大标题、图标、说明文字、按钮和表单的左侧网格，保留滚动条前的右侧留白。
- 使用更紧凑的扁平化 macOS 设置风格；除“关于”页外不使用卡片容器，并为侧边栏项目与翻译窗口按钮增加原生悬停反馈。
- 大标题颜色跟随主题色；单一内容组不再重复显示小标题，多组内容仍保留清晰分区。
- 所有设置在更改后自动保存，移除与滚动条重叠的全局“保存”按钮；插件配置同样自动持久化。
- “关于”页采用响应式介绍文本与卡片式“最近版本更新 / 关于本软件”，显示正式版本和源码分支版本号。
- 检查更新及其他提醒统一为非模态顶部信息条，五秒自动关闭，避免重复状态与弹窗打断。

### 插件管理

- “插件”页直接列出全部已安装插件；点击展开箭头即可查看和修改配置。
- 插件元数据、配置字段和操作按钮统一左对齐，并保留右侧滚动安全间距。
- 支持在列表中刷新、打开插件目录和直接删除插件。

### 启动检查与热更新

- “启动时自动检查更新”在主窗口出现后执行，不再自动打开设置窗口。
- 发现新正式版本时，在主页 `Pythia` 标题右侧显示“下载更新”按钮。
- 点击后直接下载 GitHub Release 的 macOS DMG，校验应用代码签名及稳定身份，替换 `/Applications/Pythia.app` 并自动重新启动；旧版本会保留到新进程通过启动存活检查，失败时自动回滚并重新打开旧版本。
- 若应用不在可写的 `/Applications` 中，则打开已下载的 DMG 供手动安装；签名不匹配时会终止更新。

### 兼容性与下载

- `Pythia-1.1.0-macos-arm64.dmg`：macOS 14 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.1.0-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。
- 使用 Xcode 27 beta 构建；在 macOS 27 上使用系统 Liquid Glass，在较早系统上自动采用原生兼容外观。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 安全与隐私

应用、DMG 和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。

## English

Pythia 1.1.0 focuses on the macOS Settings experience, plugin management, and in-app updates. The UI uses official AppKit and SwiftUI controls and automatically adopts the macOS 27 Liquid Glass appearance where available.

### Settings and UI

- Rebuilt the Settings sidebar and every detail page around one leading alignment grid for titles, icons, descriptions, actions, and form controls, with breathing room before vertical scrollers.
- Adopted a compact, flat macOS settings style. Cards are reserved for About; sidebar items and translation-window controls now provide native hover feedback.
- Page-title color follows the configured theme color. A lone section no longer repeats a redundant subtitle, while multi-section pages keep clear headings.
- Settings persist automatically after each change. The global Save button that overlapped the scroller is gone, and plugin configuration autosaves as well.
- About now uses responsive introduction text, card-based release/software sections, and displays both the marketing version and source revision.
- Update checks and other notices use non-modal top banners that dismiss after five seconds instead of duplicate status text and dialogs.

### Plugin management

- The Plugins page lists every installed plugin and expands each item in place for configuration.
- Plugin metadata, fields, and actions follow the same leading grid and preserve a safe inset from the scroller.
- Refresh, open-directory, and direct removal actions are available from the list.

### Startup check and hot update

- “Check for updates at startup” runs after the main window appears and no longer opens Settings.
- When a newer stable release is available, a “下载更新” (Download Update) button appears beside the main `Pythia` title.
- The button downloads the macOS DMG from GitHub Releases, verifies the app's code signature and stable identity, replaces `/Applications/Pythia.app`, and relaunches automatically. The old bundle remains available until the new process passes a startup health window; failure restores and reopens the previous version.
- When Pythia is not running from a writable `/Applications`, the downloaded DMG opens for manual installation. A signature mismatch aborts the update.

### Compatibility and downloads

- `Pythia-1.1.0-macos-arm64.dmg`: macOS 14 or later on Apple silicon (`arm64`).
- `Pythia-1.1.0-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.
- Built with Xcode 27 beta. macOS 27 uses system Liquid Glass, while earlier systems receive the native compatibility appearance.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Security and privacy

The app, DMG, and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets.
