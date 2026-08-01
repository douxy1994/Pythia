# Windows 功能差异清单（基于 WinUI 3 客户端）

- 生成日期：2026-08-01
- 候选分支：`codex/windows-final`（HEAD `0fc2d1b`，未推送 GitHub）
- 正式客户端：`Windows/Pythia.WinUI/`（WinUI 3 / C# 14 / .NET 10 / Windows App SDK 2.3.1 / win-x64 / unpackaged / self-contained）
- 旧工程：`Windows/Pythia.Windows/`（Flutter/Win32）—— 保留为兼容参考，不再新增功能
- 依据：目标文档（用户 2026-08-01 粘贴）、`Docs/WINDOWS_WINUI_PARITY_AUDIT.md`、`Docs/WINDOWS_ACCEPTANCE_2026-07-16.md`、WinUI 源码审计

> 技术路线说明：用户已于 2026-07-16 决定将 Windows 客户端迁移至 WinUI 3。目标文档第二章中强制 Flutter 的条款视为已被该决策覆盖；其余所有章节（功能对齐、安全边界、Windows 11 UI、验收、禁止无限开发、完成定义）原样适用于本 WinUI 客户端。

## 分级口径

- **P0**：阻断正式发布的核心功能缺陷，必须在阶段二修复并附复现测试。
- **P1**：影响发布质量或安全要求，必须在阶段三关闭。
- **P2**：视觉/体验优化，以验收标准为界，不做无止境调整。
- **外部阻塞**：非代码问题，依赖证书、账户、人工实机验收或第三方服务。

---

## P0 — 阻断缺陷

| # | 项目 | 现状（代码审计） | 目标依据 | 修复方向 |
|---|---|---|---|---|
| P0-1 | 系统通知未真正实现 | `NotificationsEnabled` 设置项与托盘 icon 数据结构存在，但全工程**从未调用 `Shell_NotifyIcon` 的气泡消息（NIF_INFO）或系统 Toast 发送任何通知**。 | 目标 IV.5「系统通知」 | 在 `WindowsShellService` 扫描区按设置调用 `Shell_NotifyIcon` 的 `NIF_INFO` 气泡，或改用 `ToastNotificationManager`；附「收到通知」的自动化断言。 |

> 经审计，翻译主流程（Enter/Shift+Enter/IME、混合语言路由、多服务并行、独立结果卡、排序、凭据读取、划词、截图 OCR、全局快捷键、托盘、窗口行为、插件、WebDAV）在代码层面均已实现并有 smoke 断言覆盖（见 `WINDOWS_WINUI_PARITY_AUDIT.md`「Implemented parity work」17 项与回归证据）。这些不列为 P0 代码缺陷，但其中依赖人工实机的项见「外部阻塞」。

---

## P1 — 发布质量与安全

| # | 项目 | 现状 | 目标依据 | 修复方向 |
|---|---|---|---|---|
| P1-1 | OCR 语言包覆盖与缺失提示 | `OcrService` 仅调用 `OcrEngine.TryCreateFromUserProfileLanguages()`，依赖用户已安装的 OS 语言包；**不显式枚举/强制 zh 与 en，缺语言包时无明确提示**。 | 目标 IV.5「中文和英文 OCR 语言包」 | 枚举可用语言，优先 zh/en；当两者皆不可用时给出可操作的缺失提示（指向语言包安装）。 |
| P1-2 | Authenticode 签名完全缺失 | csproj、`installer/Pythia.WinUI.iss`、`tool/build-installer.ps1` **均无 `signtool` 调用**，无 `SignedInstaller`，无证书引用。 | 目标 IV.6「更新程序必须校验下载文件、SHA-256 和 Authenticode 签名」、阶段四「Authenticode 签名」 | 1) 取得证书后，在 `.iss` 配置 `SignTool`、在发布脚本对 exe 与安装包签名；2) `UpdateService` 在 SHA-256 校验通过后追加 `WinVerifyTrust` 调用验证 Authenticode 链。**依赖证书，见外部阻塞 EXT-1。** |
| P1-3 | 发布体积与单文件选项 | `PublishSingleFile=false`，当前安装包约 121 MB。 | 目标 VIII「只包含运行所必需的程序」（非硬性体积上限） | 评估启用 `PublishSingleFile`+`IncludeNativeLibrariesForSelfExtract` 或保留框架依赖形态的体积/启动权衡；以验收为准，不强制。 |

---

## P2 — 视觉与体验（以验收为界）

| # | 项目 | 现状 | 目标依据 |
|---|---|---|---|
| P2-1 | `AboutPage.xaml` 为游离文件 | 独立 `AboutPage.xaml(.cs)` 存在但实际未用作导航页，「关于」以 `SettingsPage` 内联 `AboutSection` 呈现（测试已断言此约定）。 | 目标 IV.6「关于页面显示版本信息」已由内联区满足 | 删除游离 `AboutPage` 文件或在文档中明确其弃用，避免混淆。 |
| P2-2 | 高 DPI / 键盘 Tab 顺序 / Tooltip / 辅助功能标签 | 代码具备 `PerMonitorV2`、`IconSemantics`（38 项）、`AutomationProperties`，但 100/125/150/200% 全 DPI 与多显示器组合仍需人工实机核对。 | 目标 V「DPI 不截断/模糊/错位」「Tab 焦点顺序」 | 阶段四实机验收中逐项核对，发现的具体错位再针对性修复。 |

---

## 外部阻塞（非代码）

| # | 项目 | 阻塞原因 | 解除条件 |
|---|---|---|---|
| EXT-1 | Authenticode 证书 | 无 `.pfx`/证书链 | 用户提供代码签名证书后，P1-2 与发布签名才能进行 |
| EXT-2 | 真实翻译服务凭据 | 内置 Google/Baidu/Youdao/OpenAI/DeepL/LibreTranslate 与各插件凭据需真实账户 | 用户提供有效凭据后做端到端验收 |
| EXT-3 | WebDAV 端点 | 与 macOS 双向同步需真实 WebDAV 账户 | 用户提供端点后做双向/冲突/损坏远端验收 |
| EXT-4 | GitHub Release 签名资产 | 自动更新验收需已签名的 Release 安装包 | 依赖 EXT-1，再推送分支并发布 Release |
| EXT-5 | IME 候选窗 Enter 行为 | 微软拼音/五笔/第三方输入法的候选确认 Enter 需人工实机 | 阶段四在真实输入法下逐项验收 |
| EXT-6 | 多 DPI / 多显示器组合 | 100/125/150/200% 与不同缩放多显示器需人工实机 | 阶段四实机验收 |
| EXT-7 | 划词翻译在多个应用中 | Notepad/Word/Edge/Chrome/Terminal/PDF 阅读器的 UI Automation 与剪贴板回退需人工实机 | 阶段四实机验收 |

---

## 已完成项（不计为差异，仅备案）

依据 `WINDOWS_WINUI_PARITY_AUDIT.md` 与代码审计，以下已实现并通过 smoke 断言，不进入修复队列（除非后续修改造成回归）：

- Enter 提交 / Shift+Enter 换行 / IME composing 不误触发 / 重复抑制 / 单次去重（`HomeInteractionPolicy` + `HomePage.xaml` `PreviewKeyDown`）
- 中英文及混合文本自动方向路由（`TranslationCoordinator.ResolveLanguages`）
- 多服务并行（`Task.WhenAll`）、单服务失败不影响其他、独立结果卡、顺序持久化
- 凭据存入 Windows Credential Manager（`CredentialStore`，`CredWriteW/CredReadW`，UTF-8 blob）
- UI Automation 划词 + 剪贴板回退 + 原剪贴板恢复（`SelectionCaptureService`）
- 截图选区 + Windows.Media.Ocr + 反向拖拽 + 取消（`OcrService` + `ScreenRegionSelector`）
- 4 组全局快捷键 + 冲突检测 + 原子回滚（`WindowsShellService`，`RegisterHotKey`/`MOD_NOREPEAT`）
- 托盘菜单（6 项）/ 开机启动（HKCU Run）/ 关闭到托盘 / 失焦隐藏 / 窗口置顶 / 多显示器窗口位置恢复
- `.pythia` 插件格式、严格校验、进程隔离、Node 运行时、密钥脱敏、原子更新回滚、连通性分类测试
- 历史：逻辑删除/墓碑、收藏时间戳、冲突合并、周期/本地变化/托盘触发 WebDAV 同步、同步前备份
- 可移植备份的导出/上传/下载/恢复（省略凭据与设备私密信息）
- GitHub 更新检查、精确匹配 windows-x64 资产、同名 SHA-256 校验、有界下载
- Mica 背景、Fluent 图标（`IconSemantics` 38 项）、应用图标同步、浅色/深色主题

## 已完成的自动化验证（截至 2026-07-18）

- Release 构建：0 warning / 0 error
- 原生 smoke 套件（~70 断言）：通过
- 安装程序生成 + 同名 SHA-256 sidecar：通过
- 安装/卸载/重装/双开单实例/EXE 哈希一致：通过
- 发布树敏感材料门禁（无 `.pythia`/`.potext`/凭据/私钥/用户插件）：通过

## 测试命令对照（Flutter → WinUI）

目标文档第七章列出的命令为 Flutter 专用，WinUI 客户端对应如下：

| 目标文档命令（Flutter） | WinUI 对应 |
|---|---|
| `flutter analyze` | `dotnet build -nr:false`（编译期分析）+ IDE 分析器；可选 Roslyn analyzer |
| `flutter test` | `dotnet run --project Windows/Pythia.WinUI.Tests`（原生 smoke 套件） |
| `flutter build windows --release` | `dotnet publish Windows/Pythia.WinUI -c Release -r win-x64 --self-contained` |
| `dart run tool\verify_release_package.dart ...` | 发布树敏感材料门禁（见 smoke 套件内置检查） |
| `.\tool\build_windows_installer.ps1` | `Windows/Pythia.WinUI/tool/build-installer.ps1` |
| `node ..\..\script\validate_pythia_plugins.mjs` | 不变（仍校验 `.pythia` 包） |
| `.\tool\prepare_plugin_runtime.ps1` | 由 WinUI 构建复制 `pythia-plugin-runner.cjs` + 固定 Node 运行时 |
