# Pythia Windows 同步交接：macOS 1.2.4 翻译行为

更新日期：2026-10-02（Asia/Singapore）。本文件交接本轮增量，不要求重写 Windows 客户端。

## 1. 接手目标与基线

将 macOS 1.2.4 的换行保护、受控分段并发、逐服务等待动画及请求生命周期保护同步到 **Windows 原生 WinUI 3 客户端**。

- 仓库：[douxy1994/Pythia](https://github.com/douxy1994/Pythia)，默认分支 `master`。
- 功能基线：`aa8035cd1f1403c970f5ec34bd581d78f7ac9857`。
- 已发布：[macOS v1.2.4](https://github.com/douxy1994/Pythia/releases/tag/v1.2.4)，只有 macOS arm64 DMG 和 SHA-256 资产。
- Windows 当前源码版本：`1.2.3`，见 [Pythia.WinUI.csproj](Windows/Pythia.WinUI/Pythia.WinUI.csproj)。本轮 Windows 同步尚未实现、构建或实机验收。
- 正式目标：`Windows/Pythia.WinUI/`，C# 14、.NET 10、WinUI 3、Windows App SDK 2.3.1、x64。
- `Windows/Pythia.Windows/` 的 Flutter 工程保留兼容用途；其中的 Node runner 仍被 WinUI 工程链接。不要把 Flutter 当作本轮正式 UI 开发目标。
- [WINDOWS_CODEX_HANDOFF.md](WINDOWS_CODEX_HANDOFF.md) 含早期 Flutter、版本和发布要求，只作历史参考；本次增量以本文件和当前 WinUI 源码为准。

建议在仓库根目录开始，保留本机未提交修改：

```powershell
git fetch origin --tags
git switch master
git pull --ff-only
git merge-base --is-ancestor aa8035cd1f1403c970f5ec34bd581d78f7ac9857 HEAD
if ($LASTEXITCODE -ne 0) { throw "缺少 macOS 1.2.4 功能基线" }
git switch -c codex/windows-translation-parity
```

## 2. 已完成与待完成的边界

macOS 已实现并发布的行为：

1. `translateDeleteNewline=false` 时，将源文本中的换行分隔符保留在本地，服务只翻译非空正文；结果按原顺序拼回，保留内部换行、空行和缩进。
2. 开启删除换行时，最终输出继续压缩空白；每次翻译及单卡重试在请求开始时固定设置值。
3. 每个服务的分段最多两个请求并发，完成顺序不改变输出顺序。
4. 复用配置兼容的网络连接；代理、noProxy 或超时配置改变后不误用旧配置。
5. 每个服务卡片显示原生等待动画，成功、失败、超时、取消、清空及重试都有结束处理。
6. 单卡重试记录请求代次，清空或新请求之后，迟到的旧响应不再覆盖新卡片。

**尚未确认的部分：** 原文取词阶段如果已经丢失换行，翻译层不负责凭空重建段落。macOS 的具体 Codex 多段选区取词路径尚未独立复核。Windows 必须单独验证 UI Automation 与剪贴板回退的原始文本，应分别记录 macOS 服务层测试与 Windows 划词实机证据。

## 3. 参考实现与 Windows 修改入口

| 行为 | macOS 参考 | Windows 当前入口及差距 |
| --- | --- | --- |
| 分隔符保存和重组 | [TranslationChunkPolicy.swift](Core/PythiaCore/Sources/PythiaCore/TranslationChunkPolicy.swift)：`linePreservingChunks`、`reassemble` | [TranslationCoordinator.cs](Windows/Pythia.WinUI/Services/TranslationCoordinator.cs)：`TranslateAsync`、`CustomLlmChunks`、`WhitespaceEnvelope`；目前正文换行仍进入服务请求，LLM 段落串行执行 |
| 设置固定与结果处理 | [TranslationService.swift](Pythia/Services/TranslationService.swift)：`translateService`；[TranslatorWindowController.swift](Pythia/Views/TranslatorWindowController.swift) | [PythiaSettings.cs](Windows/Pythia.WinUI/Models/PythiaSettings.cs)、[SettingsPage.xaml](Windows/Pythia.WinUI/Pages/SettingsPage.xaml)、[SettingsPage.xaml.cs](Windows/Pythia.WinUI/Pages/SettingsPage.xaml.cs)；目前原生设置模型没有对应的翻译结果删除换行字段 |
| 逐服务动画及代次 | `resultProgressIndicators`、`setServiceLoading`、`resultRetryGenerations` | [HomePage.xaml](Windows/Pythia.WinUI/Pages/HomePage.xaml)、[HomePage.xaml.cs](Windows/Pythia.WinUI/Pages/HomePage.xaml.cs)、[TranslationResult.cs](Windows/Pythia.WinUI/Models/TranslationResult.cs)；目前有全局页脚 ProgressRing，但结果在整批完成后统一加入，单卡缺少加载状态 |
| 取词与上下文 | [SelectionReader.swift](Pythia/Services/SelectionReader.swift)、[PythiaAppDelegate.swift](Pythia/App/PythiaAppDelegate.swift)：`translateSelection` | [SelectionCaptureService.cs](Windows/Pythia.WinUI/Services/SelectionCaptureService.cs)：`PrepareCaptureAsync`、`CaptureAsync`；[MainWindow.xaml.cs](Windows/Pythia.WinUI/MainWindow.xaml.cs)：`TranslateSelectionAsync`、`ShowHomeTextAsync` |
| 插件、取消、超时 | `TranslationCancellation`、`translateRawService` | [PluginService.cs](Windows/Pythia.WinUI/Services/PluginService.cs)：`TranslateAsync` 已接收 CancellationToken，并使用文本长度相关超时，需继续传递取消信号 |
| 回归测试 | [TranslationChunkPolicyTests.swift](Core/PythiaCore/Tests/PythiaCoreTests/TranslationChunkPolicyTests.swift)、[test_translation_pipeline.sh](script/test_translation_pipeline.sh) | [Program.cs](Windows/Pythia.WinUI.Tests/Program.cs)，现有可执行测试入口；参考 Swift 测试意图，用 Windows 可运行的测试实现 |

## 4. 换行设置与数据兼容

新增对应的 Windows 原生设置，建议 C# 属性 `TranslateDeleteNewline`，默认 `false`。这是**待新增字段**，不是现有 API。

[LocalStore.cs](Windows/Pythia.WinUI/Services/LocalStore.cs) 使用 camelCase JSON，建议持久化为 `translateDeleteNewline`，与 macOS 命名保持一致。旧 settings.json 缺失此字段时应得到默认关闭状态；保留其他设置、服务顺序、插件配置、历史和凭据。

- 设置页显示“翻译结果删除换行”，明确作用于译文。
- 主界面的 `RemoveLineBreaks_Click` 是用户主动合并**原文**的按钮，不与自动删除译文换行共用状态。
- 每次主翻译、单卡重试开始时读取一次设置值；中途改变设置不修改已开始请求的行为。
- 自动取词、语言路由、去除文本外边缘空白均须保留内部换行。
- 新字段需要经过保存、重启、旧设置加载测试。若扩展可移植备份白名单，应另行核对 schema 与跨平台消费者；本次不改已有格式版本或凭据契约。

## 5. 分段及重组要求

实现平台原生的纯文本规划函数，供所有内置服务、两种 LLM API 与翻译插件共同使用，避免只修自定义 LLM。

关闭删除换行时：

1. 识别并保存 `\n`、`\r\n`、单独 `\r` 和 Unicode 行/段分隔符；`\r\n` 作为一个分隔符保存。
2. 将分隔符从提供给服务的正文中移出。空行或仅含空白的片段原样保存，不发请求。
3. 保存正文外侧的缩进和空白；长正文继续按现有长度上限及安全边界分段。
4. 对长片段保持数字、日期、版本号、指数表示和 Unicode 字符安全；Swift 字符计数与 C# UTF-16 长度不同，需要针对 C# 单独测试代理对和组合字符。
5. 结果按源片段索引写入，恢复保存的空白与分隔符，用直接连接完成重组，避免人为添加统一 `\n\n`。
6. 保留服务生成的正文内容；最终删除换行只在用户开启选项时执行。

LLM 的短文本、长文本提示都要求保留段落、列表和换行，但提示词只是补充措施，正确性来自本地结构保护。

示例：输入 `First paragraph.\r\n\r\n  - Second item.\nThird.`，离线服务把正文转大写且主动合并换行；关闭选项的期望值是 `FIRST PARAGRAPH.\r\n\r\n  - SECOND ITEM.\nTHIRD.`。

边界：源文本本身缺少分隔符时，不根据句号猜测段落；应检查取词路径并报告证据。

## 6. 并发、连接复用和取消

`TranslationCoordinator` 已有复用的 `_http`、`_customLlmHttp`，以及四个服务的并发门。保留已实现的连接复用，不要复制 macOS“从每次新建 session 改成复用”的旧实现过程。

- 在服务内部增加最多两个分段请求并发，保留原有服务并发限制。四服务乘两分段最多产生八个分段请求，应明确区分“每服务两个”与“全局两个”；实测并记录总体与单服务峰值，必要时增加独立的全局请求限流。
- 分段按索引回填，避免按完成顺序追加；语言方向按整个源文本解析一次，避免各段单独检测导致目标语言漂移。
- 主翻译、单卡重试、HTTP 请求及插件调用使用同一套文本规划和设置语义，检查所有 `TranslateAsync` 调用点。
- 撤销操作取消在途请求、重试等待和插件进程；取消后不启动尚未执行的分段。
- 对失败、超时和取消保证每个服务只进入一次终态；清理 CancellationTokenSource、超时任务和等待状态。
- 保留现有 LLM 五分钟单次超时、重试次数、Retry-After 支持；用户取消应作为取消终态处理，避免进入网络重试。
- 保留 Windows 1.2.3 的 Google 网页 RPC 和 Chrome 字典回退链路，不退回 macOS 旧匿名接口。
- 若以后实现代理配置热更新，应确保 handler/client 对应正确配置且在途请求正常完成，不把代理凭据写入日志。

性能测量分别记录首个服务出结果时间、整批完成时间、请求数量和并发峰值。同一固定文本、服务、设置和网络条件下比较；短多行文本拆成多请求可能变慢，需要如实说明。macOS 四段离线模拟约 0.507 秒降到 0.254 秒，仅证明调度行为，不能作为 Windows 或真实接口的速度承诺。

## 7. 每服务动画与迟到响应保护

Windows 主翻译目前 `Results.Clear()` 后等待整批结果，`RetryResult_Click` 按旧索引替换结果。需要调整：

- 请求开始即按服务顺序创建等待卡片；单个服务完成后立即更新自己的卡片，不等待最慢服务。
- 为卡片增加可通知的加载状态、终态及重试可用状态。修改属性时触发 `INotifyPropertyChanged`，XAML 用实时绑定；当前 `TranslationResult.Text/Error` 的普通 setter 需要额外通知才能更新视图。
- 使用 WinUI 原生 `ProgressRing` 或等效控件，完整窗口和 `SetCompactMode` 简约模式都可见。页脚动画不能替代卡片动画。
- 成功、失败、超时、取消、清空、离开页面、关闭窗口、重试结束都关闭对应动画；失败保留错误文本和重试入口。
- 使用批次 ID、每服务重试代次及独立取消源。清空、源文变化后提交新批次、旧页卸载时使旧代次失效。
- 单卡重试完成时根据服务 ID 与代次确认卡片身份，不直接使用重试前记录的旧索引。
- 所有 UI 更新调度到窗口 DispatcherQueue；占位卡片和失败卡片不作为成功译文写入历史、复制或收藏。
- 多服务部分失败时保留其余成功卡片，状态说明成功数量；供应商配置错误不代表整个应用失败。

## 8. 真正的划词路径验收

当前 Windows UI Automation 读取使用 `TextPattern.GetSelection()`，逐范围 `GetText(-1).Trim()` 后用 `\n` 拼接；另有剪贴板序列号变化检查与回退。这些都需要实际验证，多个选区范围之间原本的间隔须按来源应用的实际文本结构记录。

按以下五个阶段检查，而不是只看最终截图：

1. 来源应用选中的原始段落；
2. UI Automation 获取的字符串、范围数量、换行与空行数量；
3. 剪贴板回退取得的字符串及剪贴板恢复情况；
4. 进入 `TranslationCoordinator` 的 SourceText；
5. 提供给服务的各片段，以及最终 UI、复制结果与历史结果。

使用测试文本，不记录真实用户原文、API Key、Authorization Header 或剪贴板敏感内容。至少在记事本、浏览器、Word、WPS/PDF 和一款聊天或 Electron 类客户端完成实机选区验证；记录每个应用实际可用的取词路径与差异。

需要覆盖全局快捷键、主页划词按钮、实验浮动划词按钮、完整窗口和简约窗口；应分别验收直接翻译调用、HTTP 接口和真实划词选区。

## 9. 最小自动化回归矩阵

| 测试 | 通过标准 |
| --- | --- |
| 开关关闭 + 服务主动压缩换行 | 本地保存的内部分隔符、空行、缩进按源顺序恢复 |
| 开关开启 | 译文最终没有换行，保持已有空白压缩语义 |
| 开关中途变化 | 只影响后续请求，当前请求与开始时固定的值一致 |
| 旧设置缺少新字段 | 默认关闭，其余配置保持不变 |
| LF、CRLF、CR、Unicode 分隔符 | 内部结构按各自分隔符恢复，不把 CRLF 拆成两次换行 |
| 空输入、纯空白、连续空行 | 空输入正确处理；空白片段不发服务请求 |
| 列表缩进、长行、数字与 Unicode | 原文可无损重组，数字/字符不在片段边界损坏 |
| 服务响应乱序 | 最终译文顺序与源文一致，单服务分段并发峰值 ≤ 2 |
| 取消、超时、错误 | 服务终态仅一次，动画结束，无迟到响应覆盖，无取消后新增请求 |
| 单卡重试后清空或重新提交 | 旧索引/旧代次不替换新卡片，其他服务卡片不受影响 |
| 多服务部分失败、简约模式 | 成功卡片尽早展示，失败卡片可重试，等待提示在简约模式可见 |
| 设置恢复与持久化 | 测试结束设置恢复；重启后的实际设置与 UI、译文行为一致 |
| 真实选区、剪贴板回退 | 每个输入阶段的结构有证据，用户剪贴板恢复，旧剪贴板不误作选区 |

离线测试服务故意合并换行、打乱返回顺序，并用确定性的延迟控制并发；真实接口测试单独记录。测试结束必须恢复所有临时设置：本轮 macOS 曾因开启状态对照测试未及时恢复，造成用户再次看到换行被删除，本轮须在每次对照测试后立即恢复并复核设置。

## 10. Windows 构建与验收命令

以下命令从仓库根目录执行，需 Windows x64 开发环境、.NET 10、Windows App SDK/WinUI 工具链和 Inno Setup。它们是接手后的执行入口，本轮未在 Windows 上运行。

```powershell
dotnet build .\Pythia.Windows.slnx -c Release -p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw "Windows Release 构建失败" }

dotnet run --project .\Windows\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
if ($LASTEXITCODE -ne 0) { throw "Windows 回归测试失败" }

# 在已配置测试接口的环境下额外运行真实网络用例。
$previousNetworkTest = $env:PYTHIA_NETWORK_TEST
$env:PYTHIA_NETWORK_TEST = "1"
try {
    dotnet run --project .\Windows\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
    if ($LASTEXITCODE -ne 0) { throw "Windows 网络用例失败" }
} finally {
    if ($null -eq $previousNetworkTest) {
        Remove-Item Env:PYTHIA_NETWORK_TEST -ErrorAction SilentlyContinue
    } else {
        $env:PYTHIA_NETWORK_TEST = $previousNetworkTest
    }
}

node .\script\validate_pythia_plugins.mjs
if ($LASTEXITCODE -ne 0) { throw "插件协议验证失败" }
```

还需真实 Windows 桌面上的启动、选区、取消、重试、清空、窗口模式、升级安装、重启及卸载验收。保留配置与历史备份，仅对测试数据执行清理，回滚脚本需在独立副本中演练。

## 11. Windows 版本与发布要求

本次交接不修改 Windows 版本号，也不替 Windows 发布二进制。Windows 接手者完成实现及实机验证后，再按其会话中的发布指令发布。

建议使用下一个空闲补丁版本 **1.2.5（Windows-only）**，发布前重新查询远端确认未被占用。这样不重写 macOS 已发布的 v1.2.4 标签，也避免 Windows 新代码与旧发布标签的源代码不一致。若 Windows 会话指定其他版本，以其明确要求为准，并确保二进制、版本信息和发布标签对应同一源码提交。

统一修改以下版本面：

- `Windows/Pythia.WinUI/Pythia.WinUI.csproj`：Version、FileVersion、InformationalVersion。
- `Windows/Pythia.WinUI/installer/Pythia.WinUI.iss`：默认 AppVersion，保留既有 AppId。
- `Windows/Pythia.WinUI/tool/build-installer.ps1`：默认版本值。
- `.github/workflows/windows-x64.yml`：构建版本、检查文件名、上传资产名称。
- 相关 Windows README、主 README 的 Windows 下载段及发布说明；保留 macOS 当前 1.2.4 下载链接。

示例打包和校验（选择 1.2.5 时，从仓库根目录运行）：

```powershell
.\Windows\Pythia.WinUI\tool\build-installer.ps1 -Version 1.2.5
if ($LASTEXITCODE -ne 0) { throw "Windows 安装包构建失败" }

$installer = ".\Windows\Pythia.WinUI\dist\Pythia-1.2.5-windows-x64.exe"
$sidecar = "$installer.sha256"
$expected = ((Get-Content $sidecar -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
$actual = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "安装包 SHA-256 不一致" }
Get-AuthenticodeSignature $installer | Format-List Status, StatusMessage
```

现行打包脚本支持环境变量提供 Authenticode 签名，无证书时输出未签名安装包；若配置签名后失败则中止发布。维持这个已存在的事实，明确报告签名状态与 SmartScreen 提示，不把未签名包写成已签名，也不提交证书材料。

发布完成后重新下载 GitHub 资产，核对本地与下载文件 SHA-256 和字节一致性，验证安装版本和原设置恢复。保留 macOS v1.2.4 原资产与标签，公开包排除凭据、真实历史及第三方插件。

## 12. 最终交付给用户的证据

- Windows 实现提交、采用的版本号，以及改动入口。
- 本节回归矩阵的逐项通过/失败/待验状态；失败记录明确服务配置、取词、调度或 UI 层。
- 实际 Windows 构建/测试命令、输入、字面输出、退出状态和 CI 地址（确有运行时再填写）。
- 原设置备份与恢复校验，剪贴板恢复证据；公开材料使用测试文本。
- 安装包、校验文件、签名状态、重新下载核验结果及可运行回滚。
- 真实选区尚未验收时明确列出来源应用与路径；本轮 macOS 的 49 项核心测试、UI 合约测试及实机翻译结果只作为 macOS 参考证据。

功能完成后停止本轮同步；不因某个供应商失效而擅自删除用户服务或更换模型，不顺带重构历史、WebDAV、凭据或整个 UI。
