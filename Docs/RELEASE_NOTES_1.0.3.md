# Pythia 1.0.3

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.0.3 是 macOS 客户端的修复版本，解决了一个导致应用闪退的 TextKit 2 崩溃。

### 修复内容

- 修复使用过程中偶发闪退的问题：崩溃发生在窗口显示周期内，TextKit 2 正在枚举文本布局元素时底层文本存储被修改（`NSRLEArray objectAtRunIndex:length:` 异常），多个翻译服务几乎同时返回结果时概率显著放大。具体改动：
  - 外观（深浅色等）变化回调中对文本存储的全量属性修改延迟到下一个 runloop 执行，不再在系统布局/显示周期内改动文本存储；
  - 结果卡片的高度测量改用完全离屏的独立 TextKit 测量栈，不再通过 TextKit 1 兼容层对存活文本视图强制同步布局；
  - 翻译结果回写后的高度刷新统一走防抖合并，多服务同时完成只产生一轮测量与布局，不再交错强制布局。

### 下载与安装

- `Pythia-1.0.3-macos-arm64.dmg`：macOS 26 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.0.3-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 插件

应用和 DMG 不捆绑第三方插件。经过清理、不含用户配置的插件可从仓库的 [`Plugins/`](../Plugins/README.md) 目录单独下载。新插件应优先使用 `.pythia` 格式，开发者请阅读 [Pythia 插件开发指南](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。

### 安全与隐私

Release 资产和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 的本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。没有生成或发布 updater bundle。

## English

Pythia 1.0.3 is a bug-fix release of the macOS client that resolves a TextKit 2 crash causing occasional application exits.

### Fixes

- Fixed an intermittent crash during normal use: the text storage was being mutated while TextKit 2 was enumerating layout elements inside the window display cycle (`NSRLEArray objectAtRunIndex:length:`), with the odds rising sharply when several translation services returned at nearly the same moment. Concretely:
  - Full-text attribute updates triggered by appearance (dark/light mode) changes are now deferred to the next runloop turn instead of mutating the text storage during the system layout/display cycle;
  - Result-card height measurement now uses a fully offscreen, private TextKit stack instead of forcing synchronous layout on the live text view through the TextKit 1 compatibility shim;
  - Height refresh after writing translation results is now debounced and coalesced, so services finishing back-to-back produce a single measure-and-layout pass instead of interleaved forced layouts.

### Downloads

- `Pythia-1.0.3-macos-arm64.dmg`: macOS 26 or later on Apple silicon (`arm64`).
- `Pythia-1.0.3-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Plugins

Third-party plugins are not bundled in the app or DMG. Sanitized, configuration-free packages can be downloaded separately from the repository's [`Plugins/`](../Plugins/README.md) directory. New plugins should use `.pythia`; developers should read the [Pythia Plugin Development Guide](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).

### Security and privacy

Release assets and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets. No updater bundle is generated or published.
