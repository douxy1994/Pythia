# Pythia 1.2.1

发布日期：2026-08-04

## 中文

Pythia 1.2.1 修复 Windows 自定义大模型 API 翻译长文档时，因服务响应超过固定 30 秒而被取消或显示超时的问题。本次先发布 Windows x64 安装包；macOS 完成同策略移植后，其 1.2.1 arm64 资产将追加到同一个 GitHub Release。

### 长文档大模型翻译

- OpenAI Chat Completions 与 Anthropic Messages 自定义服务统一使用有序的长文本分段流程。
- 文档以约 1,800 字符为软上限，优先在换行、句末标点和自然语义边界处分段。
- 分段不会切断 UTF-16 代理项、小数、日期、时间、版本号、带符号数值或科学计数法。
- 每段独立翻译并按原顺序拼接，保留段首、段尾空白和列表/段落结构。
- 自定义大模型请求不再复用普通翻译服务的固定 30 秒超时；每次尝试最长等待 5 分钟，响应正文也受相同超时约束。
- 超时、网络异常、HTTP 408/409/425/429 和 5xx 临时错误最多尝试三次，并尊重服务端 `Retry-After`（最长 60 秒）。
- HTTP 400/401/403 等请求、配置或鉴权错误不会重试；用户主动取消会立即终止当前请求、退避等待和后续分段。
- 失败信息包含当前分段序号，便于定位长文档中的失败位置。

### 验证与发布

- Windows 原生解决方案 Release 构建通过，0 警告、0 错误。
- 原生 smoke tests 覆盖长文本精确重组、科学计数法边界、Unicode 代理项和临时 HTTP 状态分类。
- Windows 安装包继续排除第三方插件、`.pythia`、`.potext`、调试符号和私密材料。
- `Pythia-1.2.1-windows-x64.exe` 暂未进行 Authenticode 签名，可能触发 Microsoft Defender SmartScreen；安装前请核对随附 SHA-256。

### 下载

- `Pythia-1.2.1-windows-x64.exe`：Windows 10/11 x64 安装程序。
- `Pythia-1.2.1-windows-x64.exe.sha256`：Windows 安装程序的 SHA-256 校验文件。
- macOS 1.2.1 arm64 安装资产将在同步实现和 macOS 端验证完成后追加到本 Release。

---

## English

Pythia 1.2.1 fixes Windows custom-LLM translation being cancelled or reported as timed out when a long document makes the provider exceed the previous fixed 30-second limit. This release initially ships the Windows x64 installer; the macOS 1.2.1 arm64 assets will be added to the same GitHub Release after the strategy is ported and verified.

### Long-document LLM translation

- Custom OpenAI Chat Completions and Anthropic Messages services now share an ordered long-text chunking pipeline.
- Documents use an approximately 1,800-character soft limit, preferring newlines, sentence punctuation, and natural semantic boundaries.
- Chunk boundaries do not split UTF-16 surrogate pairs, decimals, dates, times, versions, signed values, or scientific notation.
- Chunks are translated sequentially and recombined in source order while preserving leading/trailing whitespace and paragraph/list structure.
- Custom LLM requests no longer share the fixed 30-second timeout used by ordinary translation providers. Each attempt may wait up to five minutes, including the response body.
- Timeouts, network failures, HTTP 408/409/425/429, and 5xx responses receive at most three attempts and honor `Retry-After` up to 60 seconds.
- HTTP 400/401/403 request, configuration, and authentication failures are not retried. Explicit user cancellation immediately stops the active request, backoff, and remaining chunks.
- Failure messages include the current chunk index for easier diagnosis.

### Verification and packaging

- The Windows native Release solution builds with zero warnings and zero errors.
- Native smoke tests cover exact long-text recombination, scientific-notation boundaries, Unicode surrogate pairs, and transient HTTP classification.
- The Windows installer continues to exclude third-party plugins, `.pythia`, `.potext`, debug symbols, and private material.
- `Pythia-1.2.1-windows-x64.exe` is not yet Authenticode-signed and may trigger Microsoft Defender SmartScreen. Verify the accompanying SHA-256 checksum before installation.

### Downloads

- `Pythia-1.2.1-windows-x64.exe`: Windows 10/11 x64 installer.
- `Pythia-1.2.1-windows-x64.exe.sha256`: SHA-256 checksum for the Windows installer.
- The macOS 1.2.1 arm64 assets will be added to this Release after the port and macOS verification are complete.
