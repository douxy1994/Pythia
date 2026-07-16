# Pythia

[English](README.md) | [简体中文](README.zh-CN.md)

Pythia 是一款面向 macOS 和 Windows 的现代桌面翻译软件。macOS 端使用原生 Swift/AppKit，Windows 端使用 Flutter 和独立 Win32 宿主。两个平台共用历史记录、WebDAV、语言路由、备份和 `.pythia` 插件契约。

当前版本：**1.0.0**

## 下载

### macOS

[下载 Pythia 1.0.0 macOS Apple silicon 版](https://github.com/douxy1994/Pythia/releases/download/v1.0.0/Pythia-1.0.0-macos-arm64.dmg)

- 需要 macOS 26 或更高版本。
- 仅支持 Apple silicon（`arm64`）。
- 当前构建使用项目稳定的本地代码签名身份，尚未使用 Apple Developer ID 进行公证。
- DMG 和 SHA-256 校验文件同时发布在 [v1.0.0 Release 页面](https://github.com/douxy1994/Pythia/releases/tag/v1.0.0)。

### Windows

Windows x64 源码、原生宿主、安装包流水线和自动测试已经在仓库中。当前 Release 暂不提供正式 Windows 安装程序，Windows 端后续开发请直接阅读 [WINDOWS_CODEX_HANDOFF.md](WINDOWS_CODEX_HANDOFF.md)。

## 主要功能

- 在主窗口中同时显示多个翻译服务的独立译文卡片。
- 支持源语言、目标语言选择和中英文混合文本的目标语言优先路由。
- 通过平台辅助功能或 UI Automation 读取选中文本，并提供剪贴板回退。
- 支持截图 OCR 和截图翻译。
- 支持历史记录搜索、收藏和删除状态。
- 支持全局快捷键、状态栏/托盘、置顶、开机启动和窗口行为。
- 支持本地和 WebDAV 备份恢复。
- 使用统一的 `/Pythia/history/history.json` 格式同步历史记录。
- 支持浅色、深色和跟随系统外观。
- 原生支持 `.pythia` 插件，并兼容 `.potext` 转换。

## 插件下载

Pythia 应用和安装包不会捆绑第三方插件。仓库的 [`Plugins/`](Plugins/README.md) 目录提供经过清理、可单独下载的插件包。

| 插件 | 下载 | 需要的凭据 |
| --- | --- | --- |
| 阿里云 Qwen3.5-35B-A3B | [`.pythia`](Plugins/aliyun-qwen3.5-35b-a3b-1.1.0.pythia) | 阿里云百炼 API Key |
| DeepSeek | [`.pythia`](Plugins/deepseek-1.1.0.pythia) | DeepSeek API Key |
| 七牛 GLM 4.5 Air（free） | [`.pythia`](Plugins/qiniu-glm-4.5-air-free-1.1.0.pythia) | 七牛 API Key |
| SenseNova | [`.pythia`](Plugins/sensenova-1.1.0.pythia) | SenseNova API Key |
| SiliconFlow | [`.pythia`](Plugins/siliconflow-1.1.0.pythia) | SiliconFlow API Key |
| Xiaomi MiMo | [`.pythia`](Plugins/xiaomi-mimo-1.1.0.pythia) | Xiaomi MiMo API Key |

安装方式：打开 **设置 > 插件 > 安装插件**，选择下载的 `.pythia` 文件，安装后再在 Pythia 中填写自己的凭据。公开插件包不包含用户配置、API Key、WebDAV 信息、历史记录或本机路径。

插件说明、来源和 SHA-256 位于 [插件目录说明](Plugins/README.md)。

## 开发 Pythia 插件

新插件应优先使用 `.pythia` 格式。`.potext` 只用于兼容和迁移。

- [完整 Pythia 插件开发指南](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [可运行插件示例](examples/plugins/README.md)
- [公开插件下载目录](Plugins/README.md)

开发指南完整说明包结构、Manifest、配置和秘密字段、请求响应协议、网络权限、隔离运行时、错误模型、旧插件转换、测试、打包命令和发布检查表。

## macOS 构建

### 环境要求

- macOS 26 或更高版本。
- Apple silicon Mac。
- Xcode 26.6 或更高版本。
- 本开发机器上名为 `Pot Local Code Signing` 的本地签名身份。

保留这个本地签名名称是为了维持已安装应用的辅助功能/TCC 身份。不要随意修改签名要求或 Bundle Identifier。

### 构建并运行

```sh
./script/build_and_run.sh --verify
```

### 打包

```sh
./script/package_release.sh
```

输出：

```text
release/Pythia/Pythia.app
release/Pythia/Pythia.dmg
```

### 验证

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
codesign -d -r- /Applications/Pythia.app 2>&1
hdiutil verify release/Pythia/Pythia.dmg
```

## Windows 开发

Windows 客户端只支持 x64/AMD64，源码位于 [`Windows/Pythia.Windows`](Windows/Pythia.Windows/README.md)，包括：

- Flutter UI 和核心逻辑。
- Credential Manager、划词、截图 OCR、快捷键、托盘、启动项、通知、更新安装和窗口行为的 Win32 平台通道。
- Inno Setup 安装包。
- 强制 PE machine `0x8664` 并排除插件和私密材料的发布门禁。
- 真实构建、安装、启动、卸载和上传候选包的 Windows CI。

交给 Windows 端 Codex 的完整开发交接文档是：

**[WINDOWS_CODEX_HANDOFF.md](WINDOWS_CODEX_HANDOFF.md)**

其中包含正确分支基线、工具链、源码地图、原生 MethodChannel 契约、测试命令、当前 UI/输入法缺口、平台验收矩阵、WebDAV/插件契约和完成定义。

Windows 基本命令：

```powershell
Set-Location Windows\Pythia.Windows
flutter pub get
node ..\..\script\validate_pythia_plugins.mjs
flutter analyze
flutter test
.\tool\prepare_plugin_runtime.ps1
flutter build windows --release
dart run tool\verify_release_package.dart build\windows\x64\runner\Release
.\tool\build_windows_installer.ps1
```

## 插件契约验证

校验全部示例，并确认 macOS 和 Windows 插件运行器保持字节一致：

```sh
node script/validate_pythia_plugins.mjs
```

共享 Swift Core 测试：

```sh
cd Core/PythiaCore
swift test
```

## 仓库结构

```text
Pythia.xcodeproj/        macOS 原生 Xcode 工程
Pythia/                  macOS AppKit 应用
Core/PythiaCore/         共享 Swift 模型和合并测试
Core/Schemas/            跨平台 JSON Schema
Windows/Pythia.Windows/  Flutter Windows 客户端和 Win32 宿主
Plugins/                 不含用户配置的公开 .pythia 下载
examples/plugins/        插件源码示例
Docs/                    架构、同步、Windows、插件和发布文档
script/                  构建、打包和校验脚本
WINDOWS_CODEX_HANDOFF.md Windows 完整交接文档
```

## 安全与隐私

- macOS 密钥保存在 `~/Library/Application Support/Pythia/credentials.json`，权限固定为仅当前用户可读写（`0600`）；Pythia 运行时不访问 macOS 钥匙串。
- Windows 秘密使用 Windows Credential Manager。
- 插件 `secret` 字段与普通设置 JSON 分离，并使用同一份 macOS 私有凭据文件。
- 可移植备份不包含 API Key、WebDAV 凭据、快捷键、启动项和窗口状态。
- 应用发布包不包含第三方插件。
- 仓库和 Release 资产不得包含私钥、API Key、密码、用户历史或本机配置。
- Windows 正式安装程序必须使用构建环境中已经安装的证书完成 Authenticode 签名，证书文件不能进入 Git。

## 文档

- [Windows Codex 完整交接](WINDOWS_CODEX_HANDOFF.md)
- [Pythia 1.0.0 发布说明](Docs/RELEASE_NOTES_1.0.0.md)
- [Pythia 插件开发指南](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [公开插件目录](Plugins/README.md)
- [跨平台架构](Docs/ARCHITECTURE.md)
- [WebDAV 同步](Docs/WEBDAV_SYNC.md)
- [Windows 开发](Docs/WINDOWS_DEVELOPMENT.md)
- [功能矩阵](Docs/FEATURE_MATRIX.md)
- [运行与测试](Docs/RUN_AND_TEST.md)
- [发布检查表](Docs/RELEASE_CHECKLIST.md)

## 许可证

Pythia 使用 [GNU General Public License v3.0](LICENSE) 发布。
