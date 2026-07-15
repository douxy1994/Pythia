# Pythia 1.0.0

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.0.0 是全新原生 macOS 客户端的首个正式版本。本次 Release 先提供 macOS Apple silicon 构建；Windows x64 安装包将在完成 Windows 实机验收后另行发布。

### 主要功能

- 原生 Swift/AppKit 界面，支持浅色、深色和跟随系统外观。
- 同时启用多个翻译服务，并以可展开、可收起的独立译文卡片展示结果。
- 支持划词翻译、输入翻译、截图 OCR、截图翻译、全局快捷键、状态栏和窗口置顶。
- 支持历史记录、生词本、TTS、服务排序、插件管理、本地备份和 WebDAV 自动同步。
- 自动检测中文时优先翻译为英文，自动检测英文时优先翻译为中文；中英文混合内容以当前目标语言为准。
- 设置侧栏新增“关于”页，紧接“迁移”排列，集中展示 Logo、版本、检查更新和 GitHub 项目入口。
- 缩放窗口时译文卡片会重新计算高度，避免首行被裁切；快捷键重新打开窗口时会保留用户设置的窗口尺寸。
- macOS 运行时不再访问系统钥匙串；服务、插件和 WebDAV 密钥使用仅当前用户可读写的本地凭据文件，避免反复要求输入钥匙串密码。
- 原生支持 `.pythia` 插件，并可在迁移旧 Pot 配置时将 `.potext` 插件转换为 `.pythia`。

### 下载与安装

- `Pythia-1.0.0-macos-arm64.dmg`：macOS 26 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.0.0-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 插件

应用和 DMG 不捆绑第三方插件。经过清理、不含用户配置的插件可从仓库的 [`Plugins/`](../Plugins/README.md) 目录单独下载。新插件应优先使用 `.pythia` 格式，开发者请阅读 [Pythia 插件开发指南](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。

### 安全与隐私

Release 资产和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 的本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。没有生成或发布 updater bundle。

## English

Pythia 1.0.0 is the first formal release of the new native macOS client. This release currently ships the macOS Apple silicon build only. A Windows x64 installer will be published separately after live Windows acceptance is complete.

### Highlights

- Native Swift/AppKit interface with light, dark, and system appearance modes.
- Multiple translation services can run together, with each result shown in its own expandable and collapsible card.
- Selected-text translation, input translation, screenshot OCR, screenshot translation, global hotkeys, status-bar actions, and always-on-top behavior.
- History, collection, TTS, service ordering, plugin management, local backup, and scheduled WebDAV synchronization.
- Chinese detected in automatic mode defaults to English, English defaults to Chinese, and mixed Chinese/English input follows the selected target language.
- A new About page follows Migration in Settings and provides the app logo, version, update check, and GitHub project link.
- Result cards recalculate their height while the window is resized so the first line is never clipped, and hotkey reopening preserves the user's remembered window size.
- The macOS app no longer accesses system Keychain at runtime. Service, plugin, and WebDAV secrets use an owner-only local credential file to eliminate repeated Keychain password prompts.
- First-class `.pythia` plugin support, including `.potext` conversion during legacy Pot migration.

### Downloads

- `Pythia-1.0.0-macos-arm64.dmg`: macOS 26 or later on Apple silicon (`arm64`).
- `Pythia-1.0.0-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Plugins

Third-party plugins are not bundled in the app or DMG. Sanitized, configuration-free packages can be downloaded separately from the repository's [`Plugins/`](../Plugins/README.md) directory. New plugins should use `.pythia`; developers should read the [Pythia Plugin Development Guide](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).

### Security and privacy

Release assets and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets. No updater bundle is generated or published.
