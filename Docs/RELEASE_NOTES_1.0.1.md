# Pythia 1.0.1

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.0.1 是 macOS 客户端的修复版本，包含划词翻译、翻译结果卡片和插件语言路由三项修复。本次 Release 仍然只提供 macOS Apple silicon 构建；Windows x64 安装包将在完成 Windows 实机验收后另行发布。

### 修复内容

- 修复在 Microsoft Word 中划词翻译时，跨页选区只识别到后一页文字的问题：对 Word 改为优先通过剪贴板读取选区（读取后自动恢复原剪贴板内容），读不到再回退到辅助功能接口。
- 每个翻译服务的结果卡片在复制按钮左侧新增“重新翻译”按钮：该服务翻译完成（成功或失败）后可点击，用当前输入和语言设置只重译这一个服务，不影响其他卡片。
- 修复 GLM 等大模型插件偶发“输入英文、译文也是英文”的问题：此前宿主把 `zh-CN` 这类语言代码原样传给插件，部分模型会忽略裸代码并照抄原文。现在 `.pythia` 管线和 `.potext` 兼容层都会先把语言代码映射为自然语言名称（如“Simplified Chinese”）再交给插件。

### 下载与安装

- `Pythia-1.0.1-macos-arm64.dmg`：macOS 26 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.0.1-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 插件

应用和 DMG 不捆绑第三方插件。经过清理、不含用户配置的插件可从仓库的 [`Plugins/`](../Plugins/README.md) 目录单独下载。新插件应优先使用 `.pythia` 格式，开发者请阅读 [Pythia 插件开发指南](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。

### 安全与隐私

Release 资产和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 的本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。没有生成或发布 updater bundle。

## English

Pythia 1.0.1 is a bug-fix release of the macOS client covering selected-text translation, translation result cards, and plugin language routing. This release still ships the macOS Apple silicon build only. A Windows x64 installer will be published separately after live Windows acceptance is complete.

### Fixes

- Fixed selected-text translation in Microsoft Word losing everything before a page break when a selection spans pages: Word now reads the selection through the clipboard first (restoring the original clipboard afterwards) and falls back to the Accessibility API only when the copy reads nothing.
- Each translation service result card gains a re-translate button to the left of the copy button. It becomes clickable once that service finishes (successfully or not) and re-runs only that service with the current input and language settings, leaving the other cards untouched.
- Fixed LLM-backed plugins (such as GLM) occasionally answering English input with English output: the host previously forwarded bare codes like `zh-CN` to plugins, and some models ignore the code and echo the source text. Both the `.pythia` pipeline and the `.potext` compatibility layer now map language codes to natural-language names (such as "Simplified Chinese") before invoking the plugin.

### Downloads

- `Pythia-1.0.1-macos-arm64.dmg`: macOS 26 or later on Apple silicon (`arm64`).
- `Pythia-1.0.1-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Plugins

Third-party plugins are not bundled in the app or DMG. Sanitized, configuration-free packages can be downloaded separately from the repository's [`Plugins/`](../Plugins/README.md) directory. New plugins should use `.pythia`; developers should read the [Pythia Plugin Development Guide](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).

### Security and privacy

Release assets and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets. No updater bundle is generated or published.
