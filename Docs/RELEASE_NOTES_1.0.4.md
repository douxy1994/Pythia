# Pythia 1.0.4

[简体中文](#简体中文) | [English](#english)

## 简体中文

Pythia 1.0.4 是 macOS 客户端的修复版本，修复 DeepL、有道、LibreTranslate 三个内置翻译服务的语言代码缺陷，并在设置中新增内置服务连通性验证。

### 修复内容

- 修复 DeepL 翻译必定失败的问题：此前发送的 `target_lang`/`source_lang` 会把语言代码中的连字符替换成下划线（如 `zh-CN` 变成 `ZH_CN`），而 DeepL 官方只接受 `ZH-HANS`/`ZH-HANT`/`EN-US`/`PT-BR` 等连字符代码，导致默认中文目标下 DeepL 开箱必挂。现在按官方契约正确映射：目标侧输出 `ZH-HANS`/`ZH-HANT`/`EN-US`/`EN-GB`/`PT-BR`/`PT-PT`，源语言侧降级为 DeepL 接受的根码（`ZH`/`EN`/`PT`），其余带区域后缀的代码统一收敛为 BCP-47 根码。
- 修复有道翻译的源语言参数：此前 `from` 直接透传 `zh-CN` 等界面代码，有道期望 `zh-CHS`，中英文混合文本会触发方向推断后报错。同时繁体中文（zh-TW 等）不再被静默降级为简体，正确映射为 `zh-CHT`。
- 修复 LibreTranslate 的语言代码与错误提示：`source` 参数补上规范化；中文映射更新为服务现行的 `zh-Hans`/`zh-Hant`（裸 `zh` 已不在官方实例支持列表）；请求失败时不再把原始 JSON 错误体抛给用户，改为解析服务器返回的 `error` 字段并给出可读信息。
- 设置 →「服务」页新增「验证服务」区域：OpenAI / DeepL / 百度 / 有道 / LibreTranslate 各有一个验证按钮，点击会先按当前输入保存，再发起一次真实翻译测试，显示连通结果或具体失败原因（缺 Key、鉴权失败、服务错误等）。以上服务均需自行注册账号获取 API Key；LibreTranslate 公共实例已强制要求 Key，也可改为自托管实例地址。

### 下载与安装

- `Pythia-1.0.4-macos-arm64.dmg`：macOS 26 或更高版本，Apple silicon（`arm64`）。
- `Pythia-1.0.4-macos-arm64.dmg.sha256`：DMG 的 SHA-256 校验文件。

当前 macOS 构建使用项目稳定的本地代码签名身份，以保持本机更新后的辅助功能权限身份一致；它尚未使用 Apple Developer ID 公证。首次打开时如被系统拦截，请在“系统设置 > 隐私与安全性”中确认打开。

### 插件

应用和 DMG 不捆绑第三方插件。经过清理、不含用户配置的插件可从仓库的 [`Plugins/`](../Plugins/README.md) 目录单独下载。新插件应优先使用 `.pythia` 格式，开发者请阅读 [Pythia 插件开发指南](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。

### 安全与隐私

Release 资产和公开插件不包含 API Key、密码、WebDAV 凭据、历史记录、用户插件配置、私钥或本机绝对路径。macOS 的本地 `credentials.json` 权限为 `0600`，不进入可移植备份或 Release。没有生成或发布 updater bundle。

## English

Pythia 1.0.4 is a bug-fix release of the macOS client that repairs language-code handling in the built-in DeepL, Youdao, and LibreTranslate providers, and adds a connectivity check for built-in services in Settings.

### Fixes

- Fixed DeepL translation failing unconditionally: the provider previously replaced hyphens with underscores in `target_lang`/`source_lang` (turning `zh-CN` into `ZH_CN`), while DeepL only accepts hyphenated codes such as `ZH-HANS`/`ZH-HANT`/`EN-US`/`PT-BR` — so DeepL was broken out of the box with the default Chinese target. Codes are now mapped per the official contract: targets produce `ZH-HANS`/`ZH-HANT`/`EN-US`/`EN-GB`/`PT-BR`/`PT-PT`, sources degrade to the root codes DeepL accepts (`ZH`/`EN`/`PT`), and any other region-suffixed code collapses to its BCP-47 root.
- Fixed the Youdao `from` parameter: it previously passed UI codes like `zh-CN` through verbatim while Youdao expects `zh-CHS`, breaking requests after direction inference on mixed Chinese/English text. Traditional Chinese (zh-TW and friends) is also no longer silently downgraded to Simplified — it now maps to `zh-CHT`.
- Fixed LibreTranslate language codes and error reporting: the `source` parameter is now normalized; Chinese maps to the service's current `zh-Hans`/`zh-Hant` codes (bare `zh` is no longer listed by the official instance); failures no longer surface the raw JSON error body — the server's `error` field is parsed into a readable message.
- Settings → 服务 gains a “验证服务” (verify) section: OpenAI, DeepL, Baidu, Youdao, and LibreTranslate each get a verify button that first saves the typed values, then runs one real translation and reports the outcome (missing key, auth failure, server error, ...). All of these services require registering your own API key; the public LibreTranslate instance now mandates a key, and a self-hosted base URL can be configured instead.

### Downloads

- `Pythia-1.0.4-macos-arm64.dmg`: macOS 26 or later on Apple silicon (`arm64`).
- `Pythia-1.0.4-macos-arm64.dmg.sha256`: SHA-256 checksum for the DMG.

The current macOS build uses the project's stable local signing identity so locally updated builds retain the same Accessibility identity. It is not yet Apple Developer ID notarized. If macOS blocks the first launch, explicitly allow it in System Settings > Privacy & Security.

### Plugins

Third-party plugins are not bundled in the app or DMG. Sanitized, configuration-free packages can be downloaded separately from the repository's [`Plugins/`](../Plugins/README.md) directory. New plugins should use `.pythia`; developers should read the [Pythia Plugin Development Guide](PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).

### Security and privacy

Release assets and public plugins contain no API keys, passwords, WebDAV credentials, history, user plugin configuration, private keys, or machine-specific absolute paths. The local macOS `credentials.json` is mode `0600` and is excluded from portable backups and Release assets. No updater bundle is generated or published.
