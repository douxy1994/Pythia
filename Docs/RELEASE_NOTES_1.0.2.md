# Pythia 1.0.2

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.0.2 是 macOS 客户端的修复版本，包含翻译窗口失焦隐藏和自动语言方向识别两项修复。

### 修复内容

- 修复输入原文时翻译窗口偶发自行消失、需要从 Dock 重新点开的问题：此前窗口一旦失去 key window 状态就立即隐藏，启动后的更新提示弹窗、第三方输入法候选窗、菜单追踪等瞬态抢焦都会误触发。现在失焦隐藏改为延迟确认——窗口重新获得焦点会取消隐藏，且只有在本应用确实没有任何 key window（真正切换到其他应用）时才执行。
- 修复中英混排文本的自动翻译方向误判：此前只要文本里同时出现一个中文字符和一个英文字母，就放弃方向推断并沿用当前目标语言，导致"中文为主、夹杂少量英文术语或缩写"的文本被当成英文翻成中文。现在改为统计中文字符数与英文单词数，按主导语言决定方向——中文占主导翻成英文，英文占主导翻成中文，两者相当时才沿用用户选择的目标语言。

### 下载与安装

- `Pythia-1.0.2-macos-arm64.dmg`：macOS 26 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.0.2-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 插件

应用和 DMG 不捆绑第三方插件。经过清理、不含用户配置的插件可从仓库的 [`Plugins/`](../Plugins/README.md) 目录单独下载。新插件应优先使用 `.pythia` 格式，开发者请阅读 [Pythia 插件开发指南](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。

### 安全与隐私

Release 资产和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 的本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。没有生成或发布 updater bundle。

## English

Pythia 1.0.2 is a bug-fix release of the macOS client covering close-on-blur window behavior and automatic translation direction detection.

### Fixes

- Fixed the translation window occasionally vanishing while typing, forcing the user to reopen it from the Dock: the window previously hid itself the moment it lost key-window status, so transient focus steals (the startup update alert, third-party IME candidate windows, menu tracking) all triggered a hide. Close-on-blur is now deferred — regaining focus cancels the pending hide, and the window only hides when the app genuinely has no key window left (a real switch to another app).
- Fixed automatic direction detection for mixed Chinese/English text: previously a single Chinese character plus a single ASCII letter disabled direction inference and kept the selected target, so Chinese-dominant text with a few embedded English terms or abbreviations was treated as English and translated into Chinese. Detection now counts Chinese characters versus English words and follows the dominant script — Chinese-dominant text translates to English, English-dominant to Chinese, and only an exact tie falls back to the user's selected target.

### Downloads

- `Pythia-1.0.2-macos-arm64.dmg`: macOS 26 or later on Apple silicon (`arm64`).
- `Pythia-1.0.2-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Plugins

Third-party plugins are not bundled in the app or DMG. Sanitized, configuration-free packages can be downloaded separately from the repository's [`Plugins/`](../Plugins/README.md) directory. New plugins should use `.pythia`; developers should read the [Pythia Plugin Development Guide](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).

### Security and privacy

Release assets and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets. No updater bundle is generated or published.
