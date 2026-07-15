# Pythia Windows Codex 完整交接文档

> 面向接手 Windows 版 Pythia 的 Codex。请先完整阅读本文，再修改代码。
>
> 更新日期：2026-07-15  
> 产品版本：Pythia 1.0.0  
> Windows 目标：Windows 11 x64 / AMD64  
> 仓库：<https://github.com/douxy1994/Pythia>

## 0. 你接手的任务是什么

你的任务不是从零创建一个翻译器，也不是把 macOS 界面逐像素搬到 Windows。仓库中已经有一套可编译的 Flutter Windows 客户端和 Win32 原生宿主。你需要在真实 Windows 11 x64 环境中继续开发、调试和验收，使 Windows 版成为可以正式发布的完整桌面应用。

最终交付必须同时满足：

1. 使用真实 Windows 11 x64 机器构建、启动、安装、卸载和重启。
2. 保留现有跨平台数据、插件、语言路由和 WebDAV 契约。
3. 把已经实现但尚未实机验收的 Win32 能力逐项验证并修复。
4. 完成 Windows 11 风格的界面和桌面交互，不照搬 macOS Liquid Glass。
5. 生成 x64 安装程序和 SHA-256 文件。
6. 正式安装程序必须使用 Authenticode 签名；证书私钥不得进入仓库。
7. 发布包不得包含任何 API Key、密码、Cookie、WebDAV 凭据、证书私钥、用户历史或第三方插件。
8. 不得破坏已经工作的 macOS AppKit 应用和跨平台格式。

## 1. 仓库、分支与起点

### 1.1 正确仓库

只使用用户的 Pythia 仓库：

```text
https://github.com/douxy1994/Pythia.git
```

不要从原 Pot 仓库重新开始，也不要把项目名称改回 Pot。

### 1.2 正确基线

本交接发布后，默认分支 `master` 应包含提交 `dbae1b5` 及其后续文档和插件提交。克隆后先确认：

```powershell
git clone https://github.com/douxy1994/Pythia.git
Set-Location Pythia
git switch master
git pull --ff-only
git merge-base --is-ancestor dbae1b5 HEAD
if ($LASTEXITCODE -ne 0) {
  throw "当前 master 不包含 Windows 最终验收基线 dbae1b5"
}
```

为 Windows 工作创建独立分支：

```powershell
git switch -c codex/windows-final
```

如果默认分支尚未合并本交接提交，则临时从下面的分支开始：

```powershell
git fetch origin codex/final-acceptance
git switch -c codex/windows-final origin/codex/final-acceptance
```

### 1.3 已验证基线

提交 `dbae1b522e8a3d995c8e87699da99cd39882c91a` 已通过 Windows x64 GitHub Actions：

- Workflow：`Windows x64`
- Run：<https://github.com/douxy1994/Pythia/actions/runs/29406318371>
- Runner：`windows-2025`
- Flutter：`3.44.5 stable`
- Dart/Flutter 测试：85 项
- 架构：PE machine `0x8664`，即 AMD64
- 完成实际 release 构建
- 完成 Inno Setup 安装程序构建
- 完成安装程序 SHA-256 复核
- 完成未安装版本启动两次的冒烟测试
- 完成临时目录静默安装、启动、静默卸载冒烟测试
- 完成发布包插件和敏感材料排除检查

这说明现有代码可以在 CI 中构建，但不能代替真实 Windows 桌面的人工交互验收。

## 2. 不可更改的产品身份

| 项目 | 固定值 |
| --- | --- |
| 产品名 | `Pythia` |
| 当前版本 | `1.0.0` |
| Flutter build number | `100` |
| Windows 架构 | x64 / AMD64 only |
| Windows EXE | `Pythia.exe` |
| Windows 安装程序 | `Pythia-1.0.0-windows-x64.exe` |
| 校验文件 | `Pythia-1.0.0-windows-x64.exe.sha256` |
| Inno Setup AppId | `{6F96CE7A-6729-4F43-9878-FF171728A2D4}` |
| GitHub Release 地址 | `https://github.com/douxy1994/Pythia/releases` |
| 插件格式 | `.pythia` 优先，`.potext` 只用于兼容和迁移 |
| WebDAV 根目录 | `/Pythia/` |
| 历史文件 | `/Pythia/history/history.json` |
| 可移植备份 | `/Pythia/settings/portable-backup.json` |

不要：

- 改成 `Pot`、`Pot Native`、`Pythia Windows Test` 等名称。
- 同时发布 x86、ARM64 或 AnyCPU 包。
- 修改 Inno Setup `AppId`，否则升级会被当作另一款应用。
- 为绕过问题而把凭据写回 JSON。
- 引入 Tauri/Electron 作为第二套 Windows 客户端。
- 在 Windows 任务中修改 macOS 签名身份、Bundle Identifier 或 TCC/辅助功能策略。

## 3. 工作范围与边界

### 3.1 主要允许修改

```text
Windows/Pythia.Windows/
Docs/
Core/Schemas/
examples/plugins/
script/
.github/workflows/windows-x64.yml
README.md
README.zh-CN.md
```

### 3.2 谨慎修改

如果修改跨平台格式，必须同步检查 macOS：

```text
Core/PythiaCore/
Pythia/Services/PluginRuntime.swift
Pythia/Services/WebDAVHistorySyncService.swift
Pythia/Stores/HistoryStore.swift
```

只有确实需要更改共享契约时才碰这些文件，并同时运行 Swift 测试。不要为了 Windows UI 重构 macOS 文件。

### 3.3 不能提交的内容

- `%APPDATA%\Pythia`、`%LOCALAPPDATA%\Pythia` 或用户目录快照。
- `settings.json`、`history.json`、`plugin-state.json` 的真实用户副本。
- API Key、AppID、Secret、Token、密码、Authorization Header。
- WebDAV 地址、账号、密码或应用专属密码。
- `.pfx`、`.p12`、`.pem`、`.key`、证书导出文件。
- 真实翻译原文和用户历史。
- 已安装的第三方 `.pythia` 或 `.potext` 插件。
- 本机 Node、Flutter、Visual Studio 或 Inno Setup 安装目录。
- `build/`、`dist/`、`.dart_tool/`、日志和崩溃转储。

公开可下载插件只放在仓库根目录 `Plugins/`，它们不是应用发布包的一部分。

## 4. Windows 开发环境

### 4.1 推荐系统

- Windows 11 24H2 或更新版本，x64。
- 中文和英文语言包。
- 至少一个 100% DPI 显示器。
- 最好再连接一个不同缩放比例的显示器，例如 125% 或 150%。
- 普通用户账户运行；不要把管理员权限当作常态。

### 4.2 必需工具

- Git for Windows。
- Flutter `3.44.5 stable`。先与 CI 保持完全一致，再考虑升级。
- Visual Studio 2022 或当前稳定版 Visual Studio，安装：
  - Desktop development with C++
  - MSVC x64/x86 build tools
  - Windows 11 SDK
  - CMake tools for Windows
- Node.js。开发校验可用系统 Node；正式应用使用脚本准备的固定运行时。
- Inno Setup 6。
- GitHub CLI `gh`，用于 Actions、Release 和 PR。
- 可选：Windows SDK `signtool.exe`，正式签名必需。

### 4.3 环境自检

```powershell
git --version
flutter --version
flutter doctor -v
node --version
cmake --version
gh --version
gh auth status
```

`flutter doctor -v` 中 Windows desktop toolchain 必须通过。不要看到 Android 或浏览器缺失就转去安装与任务无关的组件。

## 5. 第一次拉取后的基线命令

```powershell
Set-Location Windows\Pythia.Windows
flutter config --enable-windows-desktop
flutter pub get
node ..\..\script\validate_pythia_plugins.mjs
flutter analyze
flutter test
.\tool\prepare_plugin_runtime.ps1
flutter build windows --release
dart run tool\verify_release_package.dart build\windows\x64\runner\Release
```

随后构建安装程序：

```powershell
.\tool\build_windows_installer.ps1
```

再运行完整冒烟：

```powershell
.\tool\smoke_windows_release.ps1 `
  -ReleaseDirectory build\windows\x64\runner\Release `
  -InstallerPath dist\Pythia-1.0.0-windows-x64.exe
```

如果基线失败：

1. 先记录 `git rev-parse HEAD`、`flutter --version`、`flutter doctor -v` 和 Visual Studio 版本。
2. 区分环境失败与代码失败。
3. 不要直接删除架构检查、发布检查或测试来让流水线变绿。
4. 不要把整个 Windows runner 重新生成后覆盖现有 C++ 集成。

## 6. 代码结构地图

### 6.1 Dart 入口与界面

| 文件 | 责任 |
| --- | --- |
| `lib/main.dart` | 应用入口、主窗口、设置、历史、翻译工作流、平台能力装配 |
| `lib/ui/hotkey_recorder_field.dart` | Windows 快捷键录制控件 |
| `lib/ui/plugin_settings_panel.dart` | 插件安装、配置、测试、启用和删除 UI |

`main.dart` 当前较大。可以按页面和工作流拆分，但必须小步进行并保持测试通过。不要一次性重写全部状态管理。

### 6.2 核心逻辑

| 文件 | 责任 |
| --- | --- |
| `lib/core/settings_model.dart` | 非敏感设置模型、默认值、规范化、自动同步间隔 |
| `lib/core/translation_service.dart` | 内置翻译服务、语言路由、多服务调用 |
| `lib/core/history_record.dart` | 跨平台历史模型与 JSON |
| `lib/core/history_sync.dart` | 本地/远端历史合并与冲突规则 |
| `lib/core/local_storage.dart` | 本地设置、历史、备份、设备 ID |
| `lib/core/webdav_sync.dart` | WebDAV 历史同步和连接测试 |
| `lib/core/webdav_portable_backup.dart` | WebDAV 可移植备份上传和恢复 |
| `lib/core/portable_backup.dart` | 版本化、白名单、可移植本地备份 |
| `lib/core/webdav_sync_schedule.dart` | 分钟/小时/天/周精确换算 |
| `lib/core/webdav_auto_sync_scheduler.dart` | 定时自动同步 |
| `lib/core/history_change_sync_scheduler.dart` | 历史变化防抖同步 |
| `lib/core/webdav_sync_retry.dart` | 瞬时错误有限重试 |
| `lib/core/plugin_system.dart` | `.pythia` 管理、`.potext` 转换、Node 隔离运行 |
| `lib/core/update_checker.dart` | GitHub Release 检查 |
| `lib/core/update_installer.dart` | 下载、SHA-256、资产选择和安装确认 |
| `lib/core/release_package_verifier.dart` | AMD64、插件排除、敏感内容发布门禁 |
| `lib/core/hotkey_accelerator.dart` | 快捷键语法规范化和校验 |

### 6.3 Dart 平台接口

| 文件 | 责任 |
| --- | --- |
| `lib/platform/platform_services.dart` | Win32 MethodChannel 接口和异常映射 |
| `lib/platform/credential_store.dart` | Credential Manager MethodChannel 接口 |
| `lib/platform/tray_action_dispatcher.dart` | 托盘动作到业务工作流的路由 |

### 6.4 Win32 宿主

| 文件 | 责任 |
| --- | --- |
| `windows/runner/pythia_platform_channel.cpp` | 选中文本、托盘、窗口、快捷键、通知、更新安装 |
| `windows/runner/pythia_credential_channel.cpp` | Windows Credential Manager |
| `windows/runner/screenshot_ocr.cpp` | 虚拟桌面截图选择和 Windows.Media.Ocr |
| `windows/runner/screenshot_geometry.h` | 多显示器选择区域计算 |
| `windows/runner/tray_action_map.*` | 原生托盘命令到 Dart action |
| `windows/runner/flutter_window.*` | Flutter 窗口和通道注册 |
| `windows/runner/win32_window.*` | Win32 基础窗口 |
| `windows/runner/main.cpp` | Windows 进程入口 |

### 6.5 构建与发布

| 文件 | 责任 |
| --- | --- |
| `tool/prepare_plugin_runtime.ps1` | 下载/验证并准备 `runtime/node.exe` |
| `tool/build_windows_installer.ps1` | 构建 Inno 安装程序、可选 Authenticode 签名、SHA-256 |
| `tool/smoke_windows_release.ps1` | release、安装、启动、卸载冒烟 |
| `tool/verify_release_package.dart` | 调用发布门禁 |
| `installer/Pythia.iss` | 安装路径、架构、快捷方式和卸载配置 |
| `.github/workflows/windows-x64.yml` | Windows x64 CI 真构建和产物验证 |

## 7. 当前已实现的能力

不要先重写下列能力。应先实机运行、复现、定位，再做最小修复。

### 7.1 翻译服务

- Local 诊断服务。
- Google。
- 百度翻译。
- 有道翻译。
- OpenAI-compatible Chat Completions。
- DeepL。
- LibreTranslate。
- 所有已启用 `.pythia` 翻译插件。
- 多服务顺序和多结果。
- 服务凭据从 Credential Manager 读取。
- 服务失败相互隔离：部分成功时显示成功结果，全部失败才整体报错。
- 普通网络请求超时为 120 秒。

### 7.2 语言策略

`TranslationServiceRegistry.resolvedLanguages` 已实现：

1. 源语言不是 `auto` 时，尊重用户明确选择。
2. 纯中文 + 自动检测：目标优先为英文 `en`。
3. 纯英文 + 自动检测：目标优先为简体中文 `zh-CN`。
4. 中英文混合 + 自动检测：以用户当前目标语言为准。
5. 中英文混合且目标是英文：将源侧提示为中文，目标保持英文。
6. 中英文混合且目标是中文：将源侧提示为英文，目标保持中文。

不要让单个服务再次把已解析的目标语言改回输入语言。

### 7.3 历史

- 保存、搜索、收藏、逻辑删除、清空。
- 删除和收藏可以同步。
- 数据损坏保护。
- 同步前本地备份。
- 每条历史有稳定 `id`、`deviceId`、`updatedAt` 和同步状态。

### 7.4 WebDAV

- 连接测试。
- 手动同步。
- 启动同步。
- 周期自动同步。
- 历史变化 10 秒防抖同步。
- 退出前尽力完成同步。
- 瞬时错误有限重试。
- 鉴权或损坏远端文件时停止，不覆盖本地。
- 任意正整数间隔和分钟/小时/天/周单位。
- 可移植设置和历史备份。

### 7.5 Windows 原生能力

- Credential Manager。
- UI Automation 选中文本读取。
- 模拟复制的剪贴板回退，并检测剪贴板序列，避免旧文本误判。
- 虚拟桌面截图选区。
- Windows.Media.Ocr。
- `RegisterHotKey` 和 `WM_HOTKEY`。
- 通知区域托盘图标、左键显示、右键菜单。
- 开机启动 Run 注册表项。
- 置顶、关闭到托盘、失焦隐藏、窗口位置保存恢复。
- 系统通知。
- 更新安装程序 Authenticode 验证和启动。

### 7.6 插件

- 原生 `.pythia` 包安装。
- `.potext` 文件名不需要以 `plugin` 开头，只按扩展名识别。
- 手动安装 `.potext` 时优先转换，保留原包备份，失败时兼容运行。
- 从旧 Pot 的“迁移”流程应直接生成 `.pythia`，成功后 Pythia 侧不保留旧包。
- 每个插件独立配置、启用、禁用、测试、删除和重新转换。
- 插件密钥进入 Credential Manager。
- 插件在独立 Node 进程运行。
- 正式包包含运行时，不包含第三方插件。

## 8. 当前明确存在或尚未验收的缺口

以下不是推测，是接手后应优先处理的任务。

### 8.1 主界面布局

当前 `main.dart` 中原文框和译文区域都放在 `Expanded` 中。垂直拉伸窗口时两者都会增长。产品要求：

- 原文框使用固定、合理的高度，并在长文本时显示内部滚动条。
- 垂直拉伸窗口只增加译文结果区域。
- 每个翻译服务有独立结果卡片。
- 卡片内容高度按译文自适应，不强制统一最小高度。
- 每张卡可展开和收起。
- 多结果完整显示，区域整体可滚动。
- 深色模式译文使用可读的浅色文字，浅色模式使用深色文字。

### 8.2 Enter、Shift+Enter 和输入法

当前多行 `TextField` 仅使用 `onSubmitted`，不足以保证 Windows 中文输入法行为。必须实现并实机验证：

- Enter：翻译。
- Shift+Enter：插入换行。
- 输入法候选窗口处于 composing 状态时，Enter 只提交候选词，不触发翻译。
- 候选词提交后再次按 Enter 才翻译。
- 拼音、微软五笔和至少一种第三方中文输入法不应被拦截。
- 快捷键打开“输入翻译”时先清空原文和旧结果，再聚焦输入框。

不要只根据 `HardwareKeyboard.instance` 判断。应结合 `TextEditingValue.composing`、Focus 和 KeyEvent 流程写可测试的输入动作判定。

### 8.3 Windows 11 UI

当前是基础 Material 3 外壳。目标不是伪造 macOS Liquid Glass，而是使用 Windows 11 设计语言：

- 系统、浅色、深色三种真实主题。
- 可在支持环境使用 Mica/Acrylic 或 Flutter 中与系统一致的材料，但正文背景必须保持可读，不得整窗透明。
- 使用 Fluent 风格间距、层级、圆角和图标。
- Hover 时按钮出现明确但克制的底色/阴影反馈。
- 选中态持续显示主题色，不是闪一下。
- 设置左侧导航位置固定、选中项清晰、右侧内容尺寸稳定。
- 安装插件区域与已安装插件操作分开。
- 历史是独立页面，标题左对齐。
- 所有布局在 100%、125%、150%、200% 缩放下无重叠和截断。
- 不能仅靠固定像素让某一台机器看起来正常。

### 8.4 服务选择与排序

需要实现或确认：

- 首页“服务”按钮打开可持续多选的面板。
- 选择一个服务后面板不自动关闭。
- 点击面板外部才关闭。
- 面板显示当前可用且已启用的内置服务和每一个独立插件实例。
- 允许直接拖动或使用明确排序控件调整结果顺序。
- 新启用的服务插入当前排序最上方，不重置其他服务顺序。
- 设置页与首页使用同一个服务 ID 和同一份顺序。
- 结果卡顺序严格等于 `translateServiceOrder`。

### 8.5 真实平台验收

CI 不能证明以下交互正确：

- UI Automation 在不同应用中的选区。
- 剪贴板回退是否完整恢复用户剪贴板。
- 截图选区和 OCR 语言包。
- 多显示器不同 DPI。
- 全局快捷键冲突和重注册。
- 托盘左键、右键菜单、设置和历史动作。
- 开机启动实际登录后启动。
- Credential Manager 读写和删除。
- WebDAV 与 macOS 同账号双向同步。
- Authenticode 签名安装和更新。

## 9. 推荐实施顺序

### P0：建立可复现基线

完成标准：

- 基线命令全部通过。
- Debug 和 Release 均能启动。
- 记录 Windows build、Flutter、Visual Studio、SDK 和 DPI。
- 不修改代码也能复现 CI 产物。

### P1：修复阻断使用的问题

优先级：

1. Enter/Shift+Enter/IME。
2. 原文固定高度、译文区域自适应。
3. 多服务选择、排序和独立结果卡。
4. 实际服务凭据读取和翻译。
5. UI Automation 划词。
6. 截图 OCR。
7. 托盘、快捷键和窗口行为。
8. 插件安装、运行、迁移和删除。
9. WebDAV 自动同步。

每一项都必须先写可自动化的核心测试，再做人工桌面测试。

### P2：Windows 11 体验和稳定性

- 拆分过大的 `main.dart`。
- 完成 Fluent/Mica 视觉。
- 完成键盘导航、屏幕阅读器标签和焦点顺序。
- 验证高 DPI、多屏、主题切换和窗口恢复。
- 错误反馈面向用户，不显示长堆栈。
- 诊断日志不泄露原文或密钥。

### P3：发布候选

- 全部自动测试通过。
- 完整人工验收表通过。
- 使用正式 Authenticode 证书签名。
- 安装/升级/卸载通过。
- 发布包门禁通过。
- 创建 GitHub Release，并同时上传 EXE 和 `.sha256`。

## 10. 主窗口详细验收标准

### 10.1 标题和工具栏

- 标题为 `Pythia`。
- 使用 Pythia 图标。
- 置顶按钮使用图标，不使用“置顶”文字。
- 按钮有 Tooltip。
- Hover、Pressed、Disabled 状态清晰。
- 操作栏在窄窗口可换行或自适应，不截断。

### 10.2 语言选择

- 源语言和目标语言都使用下拉框，不允许用户靠自由输入语言代码完成常规操作。
- 源语言包含自动检测。
- 目标语言不能是自动检测。
- 交换按钮使用图标。
- 自动检测下纯中文优先译成英文，纯英文优先译成中文。
- 中英文混合以目标语言为准。
- 标题显示 `原文（语言）` 和 `译文（语言）`。

### 10.3 原文输入

- 高度固定，长文滚动。
- Enter 翻译，Shift+Enter 换行。
- IME composing 时不翻译。
- 翻译按钮在进行中禁用，避免重复请求。
- 快捷键输入翻译先清空。
- 划词或 OCR 成功后填入原文并开始翻译。

### 10.4 译文

- 一个服务一个结果卡。
- 卡片标题显示用户可见服务名或插件改名后的名称。
- 每张卡有复制、展开/收起；可选朗读。
- 单服务失败只在该服务卡中展示错误，其他服务结果仍显示。
- 长译文完整可滚动查看。
- 窗口拉伸只扩展结果区域。
- 文字颜色跟随主题。
- 服务排序与首页面板一致。

## 11. 设置页详细验收标准

建议至少分为：

1. 通用
2. 翻译服务
3. 插件
4. OCR
5. 快捷键
6. 备份与同步
7. 窗口
8. 关于与更新

### 通用

- 系统/浅色/深色真实生效。
- 开机启动真实生效，切换后立即更新 Run 注册表项。
- 保存后有明确成功反馈。

### 翻译服务

- 每个内置服务单独启用。
- 服务普通配置写 JSON，秘密写 Credential Manager。
- 新启用服务加入排序顶部，不能重置已有顺序。

### 插件

- 顶部独立安装区：说明优先 `.pythia`、兼容 `.potext`。
- 按钮名称为“安装插件”。
- 同一区域提供“打开插件目录”。
- 同一区域提供插件开发指南链接。
- 已安装插件列表中提供启用、改名、配置、测试、重新转换和删除。
- 删除按钮只出现在插件页。

### 快捷键

- 真实录制组合键。
- 拒绝无修饰键、重复动作和系统不支持组合。
- 保存时先校验全部组合，再替换注册，失败时回滚或给出明确状态。

### 备份与同步

- WebDAV 地址、用户名是普通设置。
- 密码只进入 Credential Manager。
- 连接测试切换目录后可直接成功，不依赖先做一次备份。
- 手动备份包含可移植设置和历史。
- 恢复前确认，恢复失败不破坏当前数据。
- 自动同步使用任意正整数和单位下拉：分钟、小时、天、周。
- 精确换算，不使用近似天数。
- 保存后立即重新配置计时器。
- 显示最后同步时间、状态和错误。

### 窗口

- 关闭到托盘。
- 始终置顶。
- 失焦隐藏。
- 窗口位置和大小恢复。
- 恢复位置必须在现有显示器可见区域内。

## 12. MethodChannel 契约

### 12.1 平台通道

通道名：

```text
pythia/windows_platform
```

| Dart -> native method | 参数 | 结果 |
| --- | --- | --- |
| `hotkey.register` | `{action, accelerator}` | void |
| `hotkey.unregisterAll` | none | void |
| `selection.readText` | none | selected string |
| `screenshot.captureAndRecognize` | `{translateAfterRecognition}` | OCR string |
| `tray.install` | none | void |
| `tray.updateMenu` | none | void |
| `startup.setLaunchAtStartup` | `{enabled}` | void |
| `window.show` | none | void |
| `window.setAlwaysOnTop` | `{enabled}` | void |
| `window.setCloseToTray` | `{enabled}` | void |
| `window.setHideOnBlur` | `{enabled}` | void |
| `window.restorePlacement` | none | void |
| `window.savePlacement` | none | void |
| `notification.show` | `{title, body, level}` | void |
| `update.launchInstaller` | `{path}` | void |
| `app.quit` | none | void |

Native -> Dart：

| method | 参数 |
| --- | --- |
| `hotkey.triggered` | action string |
| `tray.action` | action string |

稳定 action：

```text
window.show
selection.translate
screenshot.translate
translate.input
settings.open
history.open
history.sync
app.quitRequested
```

修改方法名或参数必须同步更新：

- Dart 接口。
- C++ handler。
- `test/platform_services_test.dart`。
- `test/tray_action_dispatcher_test.dart`。
- 本文档。

### 12.2 凭据通道

通道名：

```text
pythia/credential_store
```

| method | 参数 | 结果 |
| --- | --- | --- |
| `readSecret` | `{key}` | string or null |
| `writeSecret` | `{key, value}` | void |
| `deleteSecret` | `{key}` | void |

C++ 使用 `CRED_TYPE_GENERIC`，目标名称前缀为 `Pythia/`，持久性为 `CRED_PERSIST_LOCAL_MACHINE`。

## 13. 凭据和隐私边界

固定 Credential key：

```text
webdav.password
provider.baidu.appId
provider.baidu.secret
provider.youdao.appKey
provider.youdao.secret
provider.openai-compatible.apiKey
provider.deepl.apiKey
provider.libretranslate.apiKey
plugin.<plugin-id>.<field-key>
```

规则：

1. `settings.json` 只保存 URL、模型、开关、排序、用户名等非秘密信息。
2. 备份不包含秘密、WebDAV 凭据、快捷键、启动项和窗口状态。
3. 插件 `secret` 字段只进 Credential Manager。
4. 日志不得打印整个配置 Map。
5. 错误信息必须遮蔽已知 secret 值。
6. 删除服务或插件时应删除相应凭据。
7. 安装和更新不能反复弹系统认证窗口；Windows Credential Manager 正常读写不应要求用户重复输入 Windows 密码。

## 14. 划词翻译验收

优先路径：UI Automation TextPattern。回退路径：模拟复制。

至少测试：

| 应用 | 选区类型 | 期望 |
| --- | --- | --- |
| Notepad | 纯文本 | 直接读取 |
| Word | 富文本 | 读取可见选区 |
| Edge | 网页文字 | 读取选区或安全回退 |
| Chrome | 网页文字 | 读取选区或安全回退 |
| Windows Terminal | 终端选区 | 不读取旧剪贴板 |
| PDF 阅读器 | PDF 文本 | 能读则翻译，不能读则明确提示 |
| 密码框 | 受保护文字 | 不读取、不复制 |

剪贴板回退必须：

1. 保存当前剪贴板可恢复格式。
2. 记录序列号。
3. 发送复制动作。
4. 等待序列变化，不能立即读旧值。
5. 读取非空新文本。
6. 尽力恢复原剪贴板。
7. 不把剪贴板内容写入日志。

## 15. 截图 OCR 验收

至少覆盖：

- 单显示器 100% DPI。
- 多显示器，副屏位于主屏左侧或上方，包含负坐标。
- 不同显示器不同缩放。
- 中文、英文和混合文字。
- 取消操作。
- 极小选区。
- 空白选区。
- Pythia 窗口截图前隐藏，结束后按原状态恢复。
- OCR 语言包缺失时提供可理解错误。
- 截图后原文正确填充并翻译。

不要把截图保存到永久文件；临时位图使用后立即释放。

## 16. 快捷键、托盘和窗口行为

默认快捷键：

```text
显示窗口：Ctrl+Alt+P
划词翻译：Ctrl+Alt+E
截图翻译：Ctrl+Alt+S
```

快捷键验收：

- 注册成功。
- 冲突时显示明确错误。
- 修改后旧组合立即注销。
- 重启后重新注册。
- 快捷键显示窗口时不会创建重复窗口。
- 输入翻译入口会清空原文。

托盘验收：

- 左键单击显示并前置窗口。
- 右键菜单含显示、快速翻译、历史、同步历史、设置、退出。
- 设置和历史动作真实打开对应页面。
- 退出不是“隐藏”，必须真正结束进程。
- 开启关闭到托盘时，标题栏关闭只隐藏。
- 托盘菜单打开时不触发失焦隐藏。

开机启动验收：

- 开启后 Run 项存在并指向当前安装位置。
- 关闭后 Run 项删除。
- 升级到新目录时路径更新。
- 用户重新登录后实际启动。
- 卸载后无残留无效启动项。

## 17. 历史 JSON 契约

`PythiaHistoryRecord` schema version 为 `1`：

```json
{
  "id": "stable-id",
  "sourceText": "Hello",
  "translatedText": "你好",
  "sourceLanguage": "en",
  "targetLanguage": "zh-CN",
  "service": "Google",
  "model": null,
  "createdAt": "2026-07-15T00:00:00.000Z",
  "updatedAt": "2026-07-15T00:00:00.000Z",
  "isFavorite": false,
  "deviceId": "device-id",
  "syncStatus": "pendingUpload",
  "deletedAt": null,
  "schemaVersion": 1
}
```

`syncStatus` 可选值：

```text
local
pendingUpload
pendingDelete
synced
conflict
```

合并规则：

1. 按 `id` 合并。
2. 有删除墓碑时，删除优先。
3. 无删除时，较新的 `updatedAt` 胜出。
4. 同一时间但内容不同，标记冲突。
5. 保留墓碑用于跨设备删除传播。
6. 输出按 `createdAt`、`updatedAt` 倒序。

不要把多服务结果拆成多条不同 `id`，除非同时修改 macOS、Schema 和迁移策略。当前实现把一次翻译的结果组合保存在一条历史中。

## 18. WebDAV 契约

### 18.1 路径

如果用户填写的 URL 已以 `/Pythia` 结尾，不再重复添加。否则使用：

```text
<base>/Pythia/history/history.json
<base>/Pythia/settings/portable-backup.json
```

### 18.2 连接测试

连接测试应：

1. 确保 `/Pythia/` 和 `/Pythia/history/` 存在。
2. 允许 `MKCOL` 返回 405 或必要时 409。
3. 尝试读取 `history.json`。
4. 404 视为远端历史为空，不是连接失败。
5. 不能修改本地历史。
6. 切换 WebDAV 文件夹后第一次测试就应正常，不依赖先执行备份。

### 18.3 同步

1. 下载远端。
2. 远端损坏则停止，不能覆盖本地。
3. 同步前备份本地。
4. 合并本地和远端。
5. 写入本地。
6. 上传完整 collection。
7. 更新最后同步状态。

超时：

- `MKCOL`：15 秒。
- 下载/上传：45 秒。

自动同步单位：

```text
minute = 60 seconds
hour   = 3600 seconds
day    = 86400 seconds
week   = 604800 seconds
```

值必须大于 0，最长不超过 366 天。不要用 30 天代表月，也不要在单位切换时丢失用户输入。

### 18.4 双平台实测

使用测试账号完成：

1. macOS 创建记录，Windows 同步可见。
2. Windows 创建记录，macOS 同步可见。
3. 两端同时新增，合并不丢失。
4. 收藏状态同步。
5. 删除状态同步。
6. 网络中断后本地仍完整，恢复后可同步。
7. 远端 JSON 人为损坏时，本地不被覆盖。
8. 密码错误时不无限重试。

测试数据不得提交。

## 19. 可移植备份

可移植备份包括：

- 非敏感翻译设置。
- 服务启用和顺序。
- 历史记录。

不包括：

- API Key。
- WebDAV 地址、账号和密码。
- 快捷键。
- 开机启动。
- 窗口位置和状态。
- 第三方插件包和插件密钥。

远端备份先上传 `portable-backup.tmp.json`，再使用 MOVE 替换正式文件；服务器不支持 MOVE 时回退 PUT。恢复前必须校验版本和结构，再合并，不要先清空当前数据。

## 20. `.pythia` 插件契约

完整开发文档：

```text
Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md
```

公开示例：

```text
examples/plugins/echo-translator.pythia
examples/plugins/text-preprocessor.pythia
examples/plugins/openai-compatible-translator.pythia
```

公开可下载插件：

```text
Plugins/
```

### 20.1 Manifest 必需字段

```text
schemaVersion
id
name
version
description
author
type
entry
minimumPythiaVersion
supportedPlatforms
permissions
configuration
capabilities
```

Pythia 1.0.0 限制：

- `schemaVersion` 必须 `1.0`。
- `type` 必须 `translator`。
- `capabilities` 包含 `translate`。
- `entry` 是包内安全相对 `.js` 路径。
- 当前权限只允许 `network`。
- 配置类型只允许 `text`、`secret`、`select`。
- `secret` 不得有真实默认值。

### 20.2 统一请求

```json
{
  "schemaVersion": "1.0",
  "requestId": "unique-id",
  "type": "translate",
  "input": {
    "text": "Hello",
    "sourceLanguage": "en",
    "targetLanguage": "zh-CN",
    "detectedLanguage": "en"
  },
  "context": {
    "platform": "windows",
    "pythiaVersion": "1.0.0"
  }
}
```

### 20.3 统一响应

成功：

```json
{
  "schemaVersion": "1.0",
  "requestId": "unique-id",
  "success": true,
  "data": { "text": "你好" }
}
```

失败：

```json
{
  "schemaVersion": "1.0",
  "requestId": "unique-id",
  "success": false,
  "error": {
    "code": "NETWORK_ERROR",
    "message": "请求失败",
    "retryable": true
  }
}
```

### 20.4 运行时

- 正式包的 Node 位于 `runtime/node.exe`。
- `prepare_plugin_runtime.ps1` 负责准备并校验运行时。
- 不依赖用户 PATH 中的 `node`。
- 每次调用使用独立进程。
- 请求和配置通过环境变量传入。
- stdout 只接受统一 JSON 响应。
- stderr 错误在显示前遮蔽秘密。
- 响应最大 8 MiB，错误最大 1 MiB。
- 超时后终止子进程。

不得为解决 `env: node: No such file or directory` 而退回到依赖系统 PATH。

## 21. `.potext` 安装与旧 Pot 迁移

有两个不同工作流，不能混淆。

### 21.1 用户手动安装 `.potext`

为了兼容，允许：

1. 安全解压。
2. 校验 `info.json` 和 `main.js`。
3. 自动转换到 `.pythia`。
4. 保留原 `.potext` 备份。
5. 转换失败时使用兼容层。

文件名只需扩展名为 `.potext`，不限制是否以 `plugin` 开头。

### 21.2 设置中的“从旧 Pot 迁移”

产品要求更严格：

1. 扫描旧 Pot 配置和插件位置。
2. 只把支持的 translate 插件转换成 `.pythia`。
3. 成功后 Pythia 侧只保留 `.pythia`。
4. 不保留 Pythia 侧 `Legacy`、`Legacy Backups`、`.potext`、`legacy-main.js` 或旧 `info.json`。
5. 转换失败的插件不以兼容旧格式导入。
6. 不删除或修改旧 Pot 自己的源目录。
7. 可迁移配置必须做字段映射，不导入私密配置到普通 JSON。

Windows 端如尚未有完整迁移 UI，应按这个规则实现，并添加测试。

## 22. 更新和发布安全

### 22.1 更新资产

Windows 更新器只能选择：

```text
Pythia-<version>-windows-x64.exe
Pythia-<version>-windows-x64.exe.sha256
```

必须：

- HTTPS。
- GitHub 允许域名和受控重定向。
- 文件大小限制。
- SHA-256 与 sidecar 一致。
- 用户确认。
- Native `WinVerifyTrust` Authenticode 验证。
- 签名有效后才启动安装程序。

不能：

- 只依赖文件名。
- 只依赖 SHA-256 而忽略签名来源。
- 运行 `.ps1`、`.bat`、`.cmd` 或任意下载内容。
- 把更新签名私钥放进应用或仓库。

### 22.2 正式 Authenticode

证书应预先安装在 Windows 证书存储中。只向构建进程提供指纹：

```powershell
$env:PYTHIA_WINDOWS_CERT_SHA1 = "CERTIFICATE_THUMBPRINT"
.\tool\build_windows_installer.ps1
```

脚本使用 SHA-256 和时间戳服务。不要提交指纹以外的证书材料；最好连固定指纹也由 CI secret/environment 注入。

### 22.3 发布门禁

```powershell
dart run tool\verify_release_package.dart build\windows\x64\runner\Release
```

门禁必须继续拒绝：

- 非 AMD64 EXE。
- `.potext`、`.pythia` 和第三方插件目录。
- 旧插件源码树。
- 私钥头。
- 常见 API token 标记。

## 23. 自动测试要求

现有测试位于：

```text
Windows/Pythia.Windows/test/
```

当前包括：

- history record/sync
- WebDAV sync/schedule/retry/auto sync/change debounce
- portable backup/WebDAV backup
- translation providers/language routing
- settings normalization
- update checker/installer
- hotkey parser/recorder
- platform MethodChannel
- tray dispatcher
- plugin system
- release verifier
- native x64 guard/tray map/screenshot geometry

每个修复至少添加一个能失败后转绿的测试。重点新增：

- IME composing + Enter。
- Shift+Enter。
- 原文/译文布局的 Widget 测试。
- 服务新增不重置顺序。
- 服务多选面板不因单次勾选关闭。
- 插件迁移不保留 Pythia 侧 legacy 文件。
- WebDAV 切换目录后第一次连接测试。
- 托盘设置/历史动作。
- Credential Manager key 映射。

常用命令：

```powershell
flutter analyze
flutter test
flutter test test\plugin_system_test.dart
flutter test test\translation_service_test.dart
flutter test test\platform_services_test.dart
```

## 24. 人工验收矩阵

每一项记录：Windows build、DPI、应用版本、操作、结果、截图或日志位置。不得记录密钥。

### 安装生命周期

- [ ] 全新安装。
- [ ] 从旧 1.0.0 候选覆盖安装。
- [ ] 安装后启动。
- [ ] 重启系统后启动项。
- [ ] 普通卸载。
- [ ] 静默安装和卸载。
- [ ] 卸载后无无效启动项和运行进程。

### UI

- [ ] 浅色、深色、跟随系统。
- [ ] 100%、125%、150%、200% DPI。
- [ ] 最小窗口尺寸。
- [ ] 拉宽和拉高。
- [ ] 原文固定、译文增长。
- [ ] 中英文 UI 无截断。
- [ ] 键盘 Tab 焦点顺序。

### 输入和翻译

- [ ] Enter 翻译。
- [ ] Shift+Enter 换行。
- [ ] 中文 IME 候选 Enter 不翻译。
- [ ] 纯中文自动到英文。
- [ ] 纯英文自动到中文。
- [ ] 混合文字按目标语言。
- [ ] 多服务部分失败。
- [ ] 长文本。
- [ ] 多行、URL、代码、emoji。

### 平台能力

- [ ] 划词 UIA。
- [ ] 划词剪贴板回退和恢复。
- [ ] 截图 OCR。
- [ ] 多显示器和不同 DPI。
- [ ] 三个全局快捷键。
- [ ] 快捷键冲突。
- [ ] 托盘左键、右键所有动作。
- [ ] 置顶、关闭到托盘、失焦隐藏。
- [ ] 窗口位置恢复。

### 数据和网络

- [ ] 所有内置服务真实调用。
- [ ] Credential Manager 重启后读取。
- [ ] API Key 修改和删除。
- [ ] 本地备份恢复。
- [ ] WebDAV 连接测试。
- [ ] WebDAV 手动和自动同步。
- [ ] macOS/Windows 双向同步。
- [ ] 损坏远端保护。
- [ ] 网络中断恢复。

### 插件

- [ ] 安装仓库 `Plugins/` 中至少两个 `.pythia`。
- [ ] 插件配置保存到正确位置。
- [ ] 同时启用多个插件。
- [ ] 改名、排序、禁用、删除。
- [ ] 任意文件名 `.potext` 安装。
- [ ] `.potext` 自动转换。
- [ ] 迁移流程不保留 Pythia 侧旧包。
- [ ] 缺少 `runtime/node.exe` 时给明确错误，正式包中运行时存在。

## 25. 日志和诊断

可以记录：

- 版本、平台、架构、Windows build。
- 操作名称和成功/失败。
- HTTP 状态码。
- 插件 ID 和错误分类。
- 耗时和重试次数。

不能记录：

- 原文或完整译文。
- API Key、密码、Cookie、Authorization。
- 完整插件配置。
- 完整 WebDAV URL 中的用户名或私密路径。
- 用户文档路径。

向 GitHub Issue 提交日志前先做自动遮蔽和人工检查。

## 26. 提交和 PR 规则

1. 每个提交只解决一个可说明的问题。
2. 提交前运行相关测试，阶段结束运行全量测试。
3. 不使用 `git add -A` 吞入本机生成物。
4. 显式检查：

```powershell
git status --short
git diff --check
git diff --stat
```

5. 分支推送到用户仓库：

```powershell
git push -u origin codex/windows-final
```

6. PR 目标为 `master`。
7. PR 描述必须列出：改变、原因、测试、人工验收、仍未完成项。
8. 不要把“代码存在”写成“真实 Windows 已验证”。

## 27. 完成定义

Windows 版只有同时满足下列条件才算完成：

- [ ] `flutter analyze` 通过。
- [ ] `flutter test` 全部通过。
- [ ] 插件校验通过。
- [ ] Windows x64 release 构建通过。
- [ ] 发布包门禁通过。
- [ ] 安装程序和 SHA-256 生成。
- [ ] runtime 和安装/卸载冒烟通过。
- [ ] 本文人工验收矩阵通过。
- [ ] Authenticode 有效。
- [ ] 安装包无插件、凭据和私密材料。
- [ ] README 和功能矩阵与真实状态一致。
- [ ] GitHub Release 同时包含 EXE 和 `.sha256`。
- [ ] Windows 版与 macOS 使用同一历史、WebDAV 和插件契约。

## 28. 接手后第一轮应交付什么

第一轮不要声称“Windows 版全部完成”。应交付：

1. 基线环境报告。
2. Debug 和 Release 启动截图。
3. Enter/Shift+Enter/IME 修复与测试。
4. 原文固定高度、译文结果区域自适应修复。
5. 服务多选和排序修复。
6. 至少一次安装、启动、卸载实测。
7. 真实 Windows 未通过项列表和下一阶段计划。

## 29. 可直接给 Windows Codex 的启动提示词

```text
你正在 Windows 11 x64 机器上接手 Pythia Windows 客户端。

仓库：https://github.com/douxy1994/Pythia
请先完整阅读仓库根目录 WINDOWS_CODEX_HANDOFF.md，再阅读：
- Windows/Pythia.Windows/README.md
- Docs/WINDOWS_DEVELOPMENT.md
- Docs/FEATURE_MATRIX.md
- Docs/RELEASE_CHECKLIST.md
- Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md

先从 master 创建 codex/windows-final 分支，并确认 dbae1b5 是 HEAD 的祖先。不要从原 Pot 仓库开始，不要重写已经存在的 Flutter/Win32 架构，不要修改 macOS 签名和 TCC 身份。

第一步只做基线复现：flutter pub get、插件校验、flutter analyze、85 项测试、准备插件 runtime、Windows x64 release、发布包门禁、Inno 安装程序和安装/卸载冒烟。记录 Windows build、Flutter、Visual Studio、SDK 和 DPI。

随后优先修复并实机验证：
1. Enter 翻译、Shift+Enter 换行、中文输入法 composing 时 Enter 不触发翻译。
2. 原文框固定高度且长文滚动，窗口垂直拉伸只扩大译文区域。
3. 每个服务独立译文卡，可展开收起；服务面板持续多选并可排序，新服务插到顶部且不重置旧顺序。
4. Windows 11 Fluent/Mica 视觉、主题、高 DPI 和键盘可访问性。
5. UI Automation 划词、剪贴板回退、截图 OCR、全局快捷键、托盘、启动项、窗口行为。
6. Credential Manager、WebDAV 双向同步、自动同步、可移植备份。
7. .pythia 安装运行和旧 Pot 迁移纯 .pythia 结果。

每个修复先添加测试。不要提交任何密钥、用户历史、插件配置、证书或本机生成物。正式发布包不得包含插件。只有真实 Windows 人工验收通过的功能才能标记完成。
```

## 30. 相关文档

- [Windows 开发说明](Docs/WINDOWS_DEVELOPMENT.md)
- [Windows 工程 README](Windows/Pythia.Windows/README.md)
- [功能矩阵](Docs/FEATURE_MATRIX.md)
- [发布检查表](Docs/RELEASE_CHECKLIST.md)
- [跨平台架构](Docs/ARCHITECTURE.md)
- [WebDAV 同步](Docs/WEBDAV_SYNC.md)
- [Pythia 插件开发指南](Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)
- [公开插件下载](Plugins/README.md)
