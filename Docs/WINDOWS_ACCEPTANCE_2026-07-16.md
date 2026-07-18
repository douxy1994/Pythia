# Pythia Windows 本机验收记录（2026-07-16）

本记录描述 `codex/windows-final` 在真实 Windows x64 开发机上的开发、构建、安装和自动化验收，以及根据 macOS 界面完成的第二轮布局修复。它不把尚未执行的人工场景标记为完成。

最终复验日期：2026-07-18。

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

## macOS 对照修复

- 复现 150% 缩放下 1180×760 物理窗口仅有 789×538 logical pixels；原固定 320 px 历史栏会把翻译工作区压窄并导致状态文本溢出。
- 主窗口改为自适应 Translate/History 导航：常规宽度使用 NavigationRail，窄宽度使用底部 NavigationBar；历史记录成为完整页面并补齐加载、收藏、删除、清空、同步和 JSON 导出。
- 设置从单个 520 px 长表单改为“通用、翻译服务、插件、OCR、快捷键、备份与同步、窗口、关于与更新”八个侧栏页面，内容与按钮区独立滚动/换行。
- 按 macOS 翻译窗补齐复制原文、粘贴、删除换行、清空原文、截图 OCR（不自动翻译）、复制全部译文、收藏到本地历史和朗读译文入口。
- Windows 原生宿主增加 SAPI 朗读通道；Dart MethodChannel 合同已有自动化测试，实际语音和语言选择仍列为人工验证。
- 修复新用户第一次翻译保存历史时 `Cannot remove from an unmodifiable list`；空历史现在返回可变集合，并有真实文件回归测试。

## 自动验证结果

- `node ..\..\script\validate_pythia_plugins.mjs`：3 个示例、2 份 bundled runner 和 6 个公开插件包通过。
- `flutter analyze`：无问题。
- `flutter test`：114 项全部通过。
- `flutter build windows --debug`：成功，Debug `Pythia.exe` 创建响应窗口。
- `flutter build windows --release`：成功生成 `Pythia.exe`。
- `dart run tool\verify_release_package.dart build\windows\x64\runner\Release`：AMD64、插件排除和敏感材料门禁通过。
- `tool\build_windows_installer.ps1`：成功生成安装程序和同名 SHA-256 sidecar。
- 最终安装程序 SHA-256：`2d7e34ce9aa3beae1cfe73a96c14db6c802ebaf871aa2bfb4434a198c3c171ab`，大小 `33,749,251` bytes。
- `tool\smoke_windows_release.ps1`：raw release 启动、重启、临时目录静默安装、已安装版本启动、启动项清理和静默卸载全部通过。
- 当前用户正式安装：`%LOCALAPPDATA%\Programs\Pythia\Pythia.exe`，版本 `1.0.0`，进程创建响应窗口；已安装 EXE SHA-256 `63dd4928fdb69adef31cc9a68dd085f0ef3388f843f257432aac82a18315f234` 与 Release EXE 完全一致。
- 开始菜单使用顶层 `Pythia.lnk`，绕过本机 Windows 11/Inno Setup 对旧式 `{group}` 程序组卸载通知的卡死；安装、卸载和快捷方式清理已回归通过。
- 默认截图 OCR 快捷键改为本机可注册的 `Ctrl+Alt+Shift+R`；最终安装版可访问树状态为“就绪”，没有快捷键注册警告。
- 已安装目录含 `runtime\node.exe`，未发现 `.pythia`、`.potext`、证书或私钥文件。

## 尚未计为通过

- 拼音、微软五笔和第三方中文输入法候选窗口中的 Enter 行为。
- 100%、125%、200% DPI，以及不同缩放比例的多显示器。
- Notepad、Word、Edge、Chrome、Terminal 和 PDF 阅读器的 UI Automation/剪贴板回退。
- 中文、英文和混合语言截图 OCR，以及缺少语言包时的提示。
- 全局快捷键实际触发、托盘全部菜单、开机启动后重新登录、窗口失焦/恢复场景。
- 真实 Google、百度、有道、OpenAI-compatible、DeepL、LibreTranslate 凭据和 Credential Manager 重启持久化。
- 与 macOS 使用同一 WebDAV 账号的双向同步和损坏远端保护。
- Authenticode 签名安装与自动更新。当前本机安装包是未签名测试候选，不能作为正式发布资产。

在上述场景由用户完成并记录之前，文档和发布说明不得声称 Windows 版已完成全部人工验收。
