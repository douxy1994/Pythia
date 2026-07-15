# Pythia 插件开发指南

本文档适用于 Pythia 1.0.0 的 `.pythia` 插件。读者不需要阅读 Pythia 主工程源码，只要具备基础 JavaScript 和 JSON 知识，就可以创建、测试和分发翻译插件。

Pythia 同时接受 `.pythia` 与旧版 `.potext`，但新插件应优先使用 `.pythia`。`.potext` 仅用于兼容：安装时 Pythia 会先尝试转换为 `.pythia`，转换失败才使用兼容适配层运行原插件。

## 1. 最小可运行插件

目录名必须以 `.pythia` 结尾，目录内至少有两个文件：

```text
echo-translator.pythia/
├── manifest.json
└── main.js
```

`manifest.json`：

```json
{
  "schemaVersion": "1.0",
  "id": "com.example.echo",
  "name": "Echo Translator",
  "version": "1.0.0",
  "description": "Returns the source text for testing.",
  "author": "Example Author",
  "type": "translator",
  "entry": "main.js",
  "minimumPythiaVersion": "1.0.0",
  "supportedPlatforms": ["macos", "windows"],
  "permissions": [],
  "configuration": [],
  "capabilities": ["translate"]
}
```

`main.js`：

```js
module.exports.translate = async function translate(request) {
  const { text, sourceLanguage, targetLanguage } = request.input;
  return {
    success: true,
    data: {
      text: `[${sourceLanguage}->${targetLanguage}] ${text}`
    }
  };
};
```

完整文件位于 [`examples/plugins/echo-translator.pythia`](../examples/plugins/echo-translator.pythia)。

## 2. 包格式

Pythia 支持两种等价的 `.pythia` 形态：

1. 名称以 `.pythia` 结尾的目录。
2. ZIP 压缩包，文件扩展名改为 `.pythia`。

压缩包可以直接在根目录放置 `manifest.json`，也可以只有一个顶层插件目录。禁止绝对路径、`..` 路径、符号链接逃逸或多个候选插件根目录。

推荐布局：

```text
plugin-name.pythia/
├── manifest.json
├── main.js
├── README.md               # 可选
└── LICENSE                 # 可选
```

Pythia 1.0.0 不向插件开放任意文件读取接口；插件不能依赖包内运行时资源、Pythia 主工程源码或本机路径，不能把 API Key 写入包内，也不能附带 `node_modules`、可执行程序或安装脚本。

## 3. Manifest 字段

Pythia 1.0.0 要求以下字段全部存在。

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `schemaVersion` | string | 当前必须是 `1.0`。 |
| `id` | string | 3-128 个字符，只能包含字母、数字、`.`、`_`、`-`，安装和配置都以此为稳定标识。 |
| `name` | string | 用户可见名称，不要附加“插件”等重复后缀。 |
| `version` | string | SemVer，例如 `1.2.0` 或 `1.2.0-beta.1`。 |
| `description` | string | 简短说明插件用途。 |
| `author` | string | 作者或组织名称。 |
| `type` | string | Pythia 1.0.0 完整支持 `translator`。不要声明尚未实现的类型。 |
| `entry` | string | 相对插件根目录的 `.js` 文件，不能包含 `..` 或绝对路径。 |
| `minimumPythiaVersion` | string | 最低兼容 Pythia 版本。 |
| `supportedPlatforms` | string[] | 可选值为 `macos`、`windows`；至少包含当前运行平台。 |
| `permissions` | string[] | 目前可声明 `network`。不需要联网时必须留空。 |
| `configuration` | object[] | 插件设置字段，详见下一节。 |
| `capabilities` | string[] | 翻译插件必须包含 `translate`。 |

同一 `id` 同时存在 `.pythia` 和 `.potext` 时，Pythia 只加载 `.pythia`。升级插件时保持 `id` 不变，只提升 `version`。

## 4. 配置与安全存储

配置字段结构：

```json
{
  "key": "apiKey",
  "label": "API Key",
  "type": "secret",
  "required": true,
  "defaultValue": null,
  "options": null
}
```

支持的 `type`：

| 类型 | 用途 |
| --- | --- |
| `text` | 普通文本、URL、模型名、数值字符串。 |
| `secret` | API Key、Token、密码。Pythia 使用 macOS Keychain 或 Windows Credential Manager/DPAPI 保存，不写入普通设置、备份或日志。 |
| `select` | 固定选项；`options` 为值到显示名称的对象。 |

`defaultValue` 只能用于非敏感默认值。严禁给 `secret` 提供真实默认值。

运行时通过 `context.config` 读取当前插件自己的配置：

```js
const { apiKey, model } = context.config;
```

插件只能收到自己的配置。它不能读取 Pythia 数据库、WebDAV 凭据、其他插件配置或任意本机文件。

## 5. 请求协议

Pythia 每次调用插件时生成独立请求：

```json
{
  "schemaVersion": "1.0",
  "requestId": "A-UNIQUE-REQUEST-ID",
  "type": "translate",
  "input": {
    "text": "Hello",
    "sourceLanguage": "en",
    "targetLanguage": "zh-CN",
    "detectedLanguage": "en"
  },
  "context": {
    "platform": "macos",
    "pythiaVersion": "1.0.0"
  }
}
```

规则：

- `text` 是原文，必须原样处理，不能拼接到日志。
- `sourceLanguage` 可能是 `auto`。
- `targetLanguage` 是最终目标语言；中英文混合文本也必须以它为准。
- `detectedLanguage` 是宿主检测结果，只能作为参考。
- 插件不得缓存 `requestId`，每次调用都必须独立。

常见语言代码：`auto`、`zh-CN`、`zh-TW`、`en`、`ja`、`ko`、`fr`、`de`、`es`、`ru`。插件应把未知代码原样传给兼容服务，或者返回明确错误，不能静默改成其他语言。

## 6. 入口与运行上下文

入口必须使用 CommonJS 导出以下任意一种形式：

```js
module.exports.translate = async function (request, context) { /* ... */ };
```

```js
module.exports = async function (request, context) { /* ... */ };
```

`context` 当前提供：

```text
context.config   当前插件配置的只读副本
context.fetch    受权限、超时和协议限制的网络请求函数
context.signal   宿主取消或超时时触发的 AbortSignal
```

插件运行在独立进程和受限 JavaScript 上下文中。默认不提供 `require`、`process`、文件系统、子进程、动态代码生成或 WebAssembly。一个插件崩溃、超时或返回超大响应不会终止 Pythia，也不会影响其他插件。

只有 Manifest 声明 `network` 时，`context.fetch` 才能访问 `http` 或 `https`。没有权限时调用会抛出错误。

## 7. 响应协议

推荐返回完整成功响应：

```json
{
  "success": true,
  "data": {
    "text": "你好"
  }
}
```

也可以直接返回字符串，Pythia 会包装为成功响应：

```js
return "你好";
```

失败响应：

```json
{
  "success": false,
  "error": {
    "code": "AUTHENTICATION_FAILED",
    "message": "API Key 无效。",
    "retryable": false
  }
}
```

插件也可以抛出 `Error`。错误信息不得包含完整 API Key、Authorization 请求头、原文全文或服务端返回的敏感数据。

建议错误代码：

| 错误代码 | 含义 | `retryable` |
| --- | --- | --- |
| `INVALID_REQUEST` | 请求字段无效 | `false` |
| `CONFIGURATION_REQUIRED` | 缺少配置 | `false` |
| `AUTHENTICATION_FAILED` | 密钥无效或权限不足 | `false` |
| `RATE_LIMITED` | 服务限流 | `true` |
| `NETWORK_ERROR` | DNS、TLS、连接或 HTTP 错误 | 视状态而定 |
| `TIMEOUT` | 插件或网络超时 | `true` |
| `CANCELLED` | 用户取消 | `false` |
| `INVALID_RESPONSE` | 上游响应缺字段或格式错误 | `false` |
| `RUNTIME_ERROR` | 未分类运行时异常 | `false` |

Pythia 限制单次响应为 8 MiB，并按输入长度设置有上限的执行超时。

## 8. OpenAI-compatible 完整示例

完整示例位于 [`examples/plugins/openai-compatible-translator.pythia`](../examples/plugins/openai-compatible-translator.pythia)。核心实现：

```js
module.exports.translate = async function translate(request, context) {
  const { text, sourceLanguage, targetLanguage } = request.input;
  const { apiKey, baseURL, model } = context.config;
  if (!apiKey) throw new Error("AUTHENTICATION_FAILED: 请先配置 API Key。");

  const response = await context.fetch(`${baseURL}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      stream: false,
      messages: [
        { role: "system", content: "Translate accurately. Return only the translation." },
        { role: "user", content: `Translate from ${sourceLanguage} to ${targetLanguage}:\n\n${text}` }
      ]
    }),
    signal: context.signal
  });

  const payload = await response.json();
  if (!response.ok) throw new Error(`NETWORK_ERROR: HTTP ${response.status}`);
  const translated = payload.choices?.[0]?.message?.content?.trim();
  if (!translated) throw new Error("INVALID_RESPONSE: 服务未返回译文。");
  return { success: true, data: { text: translated } };
};
```

注意：示例实现会规范化 API 地址，实际开发时应直接使用仓库中的完整文件，不要重复添加 `/chat/completions`。

## 9. 文本预处理完整示例

[`examples/plugins/text-preprocessor.pythia`](../examples/plugins/text-preprocessor.pythia) 展示不联网的确定性处理：统一换行符、清理每行首尾空白、合并连续空白。它声明 `translate` 和 `preprocess` 能力，因此在 Pythia 1.0.0 中仍以独立翻译结果服务显示。

该示例适合测试：

- 无网络权限插件能否运行。
- `select` 配置能否保存并传入。
- 多行文本是否保持稳定。
- 相同输入是否得到确定结果。

## 10. 本地校验

在 Pythia 仓库根目录可以一次校验三个示例、Manifest、JavaScript 语法、无密钥运行结果以及 macOS/Windows 运行器一致性：

```bash
node script/validate_pythia_plugins.mjs
```

先进行静态检查：

```bash
cd examples/plugins/echo-translator.pythia
jq empty manifest.json
node --check main.js
```

检查必要字段：

```bash
jq -e '
  .schemaVersion == "1.0" and
  (.id | type == "string" and length >= 3) and
  .type == "translator" and
  (.supportedPlatforms | type == "array") and
  (.capabilities | index("translate") != null)
' manifest.json
```

不要只做语法检查。至少还要验证：

1. Manifest 入口真实存在。
2. 无配置时返回明确错误。
3. 正确配置时能翻译短文本和多行文本。
4. 401/403、429、500、超时、断网和无效 JSON 均有明确错误。
5. 日志中搜索不到 API Key。
6. 返回空字符串或超大响应时宿主能拒绝。
7. 一个插件失败后其他服务仍能继续翻译。

## 11. 使用 Pythia 运行器测试

构建 Pythia 后，运行器位于应用包资源目录。以下命令不需要 API Key，可测试回显示例：

```bash
export PYTHIA_PLUGIN_REQUEST='{
  "schemaVersion":"1.0",
  "requestId":"local-test",
  "type":"translate",
  "input":{
    "text":"hello",
    "sourceLanguage":"en",
    "targetLanguage":"zh-CN",
    "detectedLanguage":"en"
  }
}'
export PYTHIA_PLUGIN_CONFIG='{}'
export PYTHIA_PLUGIN_TIMEOUT_MS='10000'

node /Applications/Pythia.app/Contents/Resources/pythia-plugin-runner.cjs \
  "$PWD/examples/plugins/echo-translator.pythia" main.js
```

期望输出：

```json
{"schemaVersion":"1.0","requestId":"local-test","success":true,"data":{"text":"[en->zh-CN] hello"}}
```

调试时只能使用测试密钥。不要把真实密钥写进命令历史、截图、Issue、测试文件或 Git 提交。

## 12. 打包

### macOS

在插件目录内执行：

```bash
cd echo-translator.pythia
zip -r ../echo-translator.pythia manifest.json main.js README.md LICENSE
```

只列出真实存在的可选文件。不要把外层父目录、`.DS_Store`、Git 数据或密钥文件打入包中。

### Windows PowerShell

```powershell
Compress-Archive -Path manifest.json,main.js,README.md,LICENSE -DestinationPath ..\echo-translator.zip
Rename-Item ..\echo-translator.zip echo-translator.pythia
```

安装前再解压一次，确认根目录能直接找到 `manifest.json` 和 `main.js`。

## 13. 在 Pythia 中安装和调试

1. 打开“设置 -> 插件”。
2. 点击“安装插件”。
3. 选择 `.pythia` 目录、`.pythia` 压缩包或兼容 `.potext`。
4. 查看格式、版本、作者、权限和兼容性状态。
5. 填写配置并保存。
6. 点击“测试连通性”。
7. 在首页“服务”中启用插件并调整顺序。
8. 修改代码后点击“刷新插件”；需要重新安装时保持相同 `id`。
9. 对自动转换的旧插件，可点击“重新转换 .potext”重新生成适配包，原始备份不会被覆盖。

插件目录：

- macOS：`~/Library/Application Support/Pythia/Plugins`
- Windows：`%APPDATA%\Pythia\Plugins`

不要直接修改 `plugin-configs.json` 或系统凭据。开发调试也应通过设置页写入配置。

## 14. `.potext` 自动转换

导入 `.potext` 时，Pythia 执行以下步骤：

1. 安全解压并拒绝路径穿越。
2. 校验 `info.json`、`main.js` 和 `plugin_type`。
3. 仅对 `translate` 生成 Pythia 1.0.0 `translator` Manifest。
4. 把 `info.json.needs` 映射到 `configuration`。
5. 优先读取显式 `secret: true` 或密码输入类型；缺少声明时，仅把明确的 `apiKey`、`accessToken`、`secretKey`、`password` 等凭据名称转成 `secret`。`max_tokens` 等普通参数不会被误判。
6. 检测旧源码是否使用网络；需要时声明 `network`。
7. 保留原 `main.js` 为 `legacy-main.js`。
8. 生成使用统一请求、响应和 `context.fetch` 的适配入口。
9. 写入 `conversion.json`，记录来源、时间、警告和备份名。
10. 保存原 `.potext`，不覆盖、不删除。
11. 校验转换包后优先加载 `.pythia`。

转换后的目录通常为：

```text
plugin.id.pythia/
├── manifest.json
├── main.js
├── legacy-main.js
├── conversion.json
├── info.json
└── 原插件资源...
```

原始备份位于 `Plugins/Legacy Backups`。转换失败时 Pythia 保留旧插件并使用兼容层；失败不会阻止安装，也不会删除原文件。

手动迁移时，推荐直接重写入口使用 `request` 和 `context`，然后删除兼容适配代码。不要机械替换变量名而不测试 HTTP 错误、流式响应、配置默认值和语言代码。

## 15. 安全要求

- 包内不得包含真实密钥、Cookie、账号、WebDAV 凭据或私有证书。
- `secret` 只通过设置页保存，只从 `context.config` 读取。
- 日志不得输出完整配置、请求头、原文全文或服务端敏感响应。
- 只声明实际需要的权限。
- 不得尝试访问 Pythia 数据库、其他插件目录或系统命令。
- 对 URL、模型名、数值范围和服务端响应做校验。
- 所有网络请求都应支持 `context.signal`。
- 捕获上游错误后返回稳定错误码，不要吞掉异常并返回空译文。
- 不要无限重试；限流和临时网络错误最多进行少量有上限的退避重试。

## 16. 发布前检查清单

- [ ] `manifest.json` 是有效 UTF-8 JSON。
- [ ] `id` 唯一且升级时保持不变。
- [ ] `version` 使用 SemVer。
- [ ] `entry` 是包内相对 `.js` 路径。
- [ ] `supportedPlatforms` 与实际测试平台一致。
- [ ] `permissions` 只包含实际使用项。
- [ ] API Key 配置使用 `secret`。
- [ ] 没有把密钥、测试账号或私有 URL 提交到仓库。
- [ ] 成功响应包含非空 `data.text`。
- [ ] 认证、限流、断网、超时和无效响应都有明确错误。
- [ ] 短文本、长文本、多行、中文、英文和中英混合输入均已测试。
- [ ] macOS 和 Windows 至少完成静态校验；声明支持的平台应完成真实运行测试。
- [ ] 压缩包解压后结构正确，不含多余父目录。
- [ ] 插件失败不会影响 Pythia 或其他插件。

## 17. 交给 Codex、Claude Code 或其他模型的通用提示词

下面的提示词可以直接使用，只需替换方括号内容：

```text
请为 Pythia 1.0.0 创建一个可发布的 .pythia 翻译插件。

目标服务：[服务名称和官方 API 文档地址]
插件 ID：[反向域名，例如 com.example.translator]
显示名称：[插件名称]
默认模型：[模型名]
支持平台：macos、windows

必须遵守：
1. 输出完整目录，至少包含 manifest.json、main.js、README.md；不要只给代码片段。
2. Manifest schemaVersion 为 1.0，type 为 translator，capabilities 包含 translate。
3. entry 使用包内安全相对路径 main.js，version 使用 SemVer，minimumPythiaVersion 为 1.0.0。
4. API Key 必须声明为 configuration type=secret；不得在代码、默认值、日志或测试中包含真实密钥。
5. 只声明实际需要的 permissions；联网插件声明 network。
6. main.js 使用 CommonJS，导出 module.exports.translate = async (request, context) => ...。
7. 从 request.input 读取 text、sourceLanguage、targetLanguage、detectedLanguage；混合语言必须以 targetLanguage 为准。
8. 从 context.config 读取配置，只通过 context.fetch 联网，并传递 context.signal。
9. 成功返回 {success:true,data:{text:"..."}}；不得返回解释、Markdown 包裹或空字符串。
10. 明确处理缺少配置、401/403、429、5xx、断网、超时、取消、无效 JSON 和空响应，使用稳定错误码。
11. 不使用 require、process、文件系统、子进程、动态代码生成或未声明权限。
12. 提供本地静态校验、无密钥单元测试、打包命令和人工冒烟测试步骤。
13. 检查所有文件中不存在 API Key、Token、密码、私有证书或用户数据。
14. 按 Pythia 文档中的统一请求、响应、配置、权限和错误协议实现，不使用 Pot/Tauri 旧插件 API。

完成后列出：文件树、每个文件完整内容、测试命令、预期结果、已知限制。不要省略 Manifest 字段或错误处理。
```

## 18. 常见问题

### 安装时提示 Manifest 无效

先检查字段是否齐全、`schemaVersion` 是否为 `1.0`、`type` 是否为 `translator`、`entry` 是否存在，以及当前平台是否在 `supportedPlatforms` 中。

### 插件能安装但首页没有服务

确认 `capabilities` 包含 `translate`，插件已启用，并在首页“服务”面板中勾选。相同 `id` 的 `.pythia` 会覆盖 `.potext` 显示。

### `context.fetch` 提示无权限

在 Manifest 的 `permissions` 中加入 `network`，重新安装插件。不要为了消除错误声明不需要的权限。

### 返回 `INVALID_RESPONSE`

检查上游 JSON 路径，并确保最终 `data.text` 是非空字符串。不要捕获异常后返回 `""`。

### `.potext` 转换失败

查看插件页的转换状态和 `conversion.json`。不支持类型、缺少 `info.json`/`main.js`、非法路径或依赖私有二进制能力时不能自动转换；Pythia 会在安全允许的情况下继续使用兼容层。

### 插件在一个平台正常、另一个平台失败

不要依赖平台路径、Shell、系统命令或本地 Node 模块。使用 Pythia 提供的 `context` API，并在两个平台分别测试。未验证的平台不要写入 `supportedPlatforms`。
