# Pythia Windows 本机验收记录（2026-07-16）

本记录描述 `codex/windows-final` 在真实 Windows x64 开发机上的第一轮开发、构建、安装和自动化验收。它不把尚未执行的人工场景标记为完成。

## 环境

- 系统：Windows 11 25H2，build `26200.8875`，x64。
- 显示缩放：150%（`AppliedDPI=144`）。
- Flutter：`3.44.5 stable`，Dart `3.12.2`。
- Visual Studio Build Tools：18.3.2，x64 C++ 工作负载。
- Windows SDK：`10.0.26100.0`。
- 插件运行时：Node `v24.18.0` x64，使用仓库固定 SHA-256 下载。
- Inno Setup：6.7.3，当前用户安装。

`flutter doctor -v` 的 Windows desktop toolchain、Windows 设备和网络资源均通过。Android SDK 缺失与本 Windows desktop 任务无关。

## 本轮实现

- 新增可测试的 Enter/Shift+Enter/IME composing 提交策略。
- 原文编辑器固定为 176 logical pixels，高度不随窗口垂直拉伸，长文本使用内部滚动。
- 垂直空间只分配给译文结果区域。
- 每个服务使用独立、内容自适应、可展开/收起的结果卡；深浅主题使用对应前景色。
- 部分服务失败时保留服务顺序并显示独立错误卡；成功结果仍可保存历史。
- 首页服务面板保持打开以便持续多选，支持明确的上移/下移排序；新服务加入顶部且不重置已有顺序。
- 浅色和深色主题使用 Segoe UI、不透明 surface、Fluent 风格圆角与填充控件；顶部工具栏可在窄窗口换行，语言交换按钮执行真实交换。
- 打包脚本同时发现 Program Files、当前用户目录和 `PATH` 中的 Inno Setup。

## 自动验证结果

- `node ..\..\script\validate_pythia_plugins.mjs`：3 个示例、2 份 bundled runner 和 6 个公开插件包通过。
- `flutter analyze`：无问题。
- `flutter test`：103 项全部通过（基线 85 项，本轮新增 18 项）。
- `flutter build windows --debug`：成功，Debug `Pythia.exe` 创建响应窗口。
- `flutter build windows --release`：成功生成 `Pythia.exe`。
- `dart run tool\verify_release_package.dart build\windows\x64\runner\Release`：AMD64、插件排除和敏感材料门禁通过。
- `tool\build_windows_installer.ps1`：成功生成安装程序和同名 SHA-256 sidecar。
- 安装程序 SHA-256：`8290871dacd5883485f706ac23f986323d0ee54e8c6ba2a11ad07e884d734d08`。
- `tool\smoke_windows_release.ps1`：raw release 启动、重启、临时目录静默安装、已安装版本启动、静默卸载全部通过。
- 当前用户正式安装：`%LOCALAPPDATA%\Programs\Pythia\Pythia.exe`，版本 `1.0.0`，进程创建响应窗口。
- 已安装目录含 `runtime\node.exe`，未发现 `.pythia`、`.potext`、证书或私钥文件。

## 尚未计为通过

- 拼音、微软五笔和第三方中文输入法候选窗口中的 Enter 行为。
- 100%、125%、200% DPI，以及不同缩放比例的多显示器。
- Notepad、Word、Edge、Chrome、Terminal 和 PDF 阅读器的 UI Automation/剪贴板回退。
- 中文、英文和混合语言截图 OCR，以及缺少语言包时的提示。
- 全局快捷键冲突、托盘全部菜单、开机启动后重新登录、窗口失焦/恢复场景。
- 真实 Google、百度、有道、OpenAI-compatible、DeepL、LibreTranslate 凭据和 Credential Manager 重启持久化。
- 与 macOS 使用同一 WebDAV 账号的双向同步和损坏远端保护。
- Authenticode 签名安装与自动更新。当前本机安装包是未签名测试候选，不能作为正式发布资产。

在上述场景由用户完成并记录之前，文档和发布说明不得声称 Windows 版已完成全部人工验收。
