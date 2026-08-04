# Pythia 1.2.1 Release Notes

发布日期：2026-08-04

## 中文

Pythia 1.2.1 为 Windows x64 与 macOS Apple silicon 同步提供自定义大模型 API 长文档翻译修复，两个安装资产位于同一个 GitHub Release。

### 长文档大模型翻译

- OpenAI Chat Completions 与 Anthropic Messages 自定义服务共用顺序分段管线；Google、DeepL 等普通服务保持原逻辑。
- 文本按约 1800 个字符的软上限分段，优先段落、换行与句末标点，并避免切断 Swift Character、连续数字、小数、千位数、日期、时间、版本号、正负数及科学计数法。
- 分段原文可精确重组；段首、段尾空白在请求外保存并恢复，维持空白行、段落和 Markdown 列表结构。
- 多段提示包含当前 N/M 位置，并继续要求只返回译文。

### 超时、重试与取消

- macOS 每次尝试最多等待 300 秒，并覆盖完整响应正文读取；主窗口按分段数延长服务生命周期，总上限 7200 秒。
- 最多三次尝试，仅重试临时网络错误、超时、HTTP 408/409/425/429 与 5xx。
- 支持 Retry-After 秒数与 HTTP 日期，等待限制为 0.75–60 秒；没有响应头时采用约 0.75 秒、2 秒的有界退避。
- HTTP 400/401/403/404 等请求、鉴权、模型或配置错误不重试。
- 用户取消会终止当前请求、退避等待和后续分段，界面明确显示“已取消”。
- 最终分段错误只显示“第 N/M 段翻译失败”和安全状态信息，不包含 API Key、Authorization、完整原文或服务端正文。

### 凭据与下载

API Key 的保存方式不变：macOS 继续仅写入本地私有 `credentials.json`，Windows 继续使用 Credential Manager；凭据不会进入偏好设置、日志、备份或 Release。

- `Pythia-1.2.1-macos-arm64.dmg` 与 `.sha256`
- `Pythia-1.2.1-windows-x64.exe` 与 `.sha256`

---

## English

Pythia 1.2.1 brings the custom-LLM long-document translation fix to Windows x64 and macOS Apple silicon, with both installers published in the same GitHub Release.

### Long-document LLM translation

- Custom OpenAI Chat Completions and Anthropic Messages services share an ordered segmentation pipeline; Google, DeepL, and other regular providers keep their existing paths.
- Text is split at a soft limit of about 1,800 characters, preferring paragraphs, newlines, and sentence punctuation while protecting grapheme clusters, digit runs, decimals, grouped numbers, dates, times, versions, signed values, and scientific notation.
- Source chunks reconstruct exactly. Leading and trailing whitespace is kept outside each model request and restored to preserve blank lines, paragraphs, and Markdown lists.
- Multi-segment prompts identify segment N/M and still request translation-only output.

### Timeout, retry, and cancellation

- Each macOS attempt has a 300-second full-response deadline, including response-body reading; the main window scales the service lifetime by segment count up to 7,200 seconds.
- At most three attempts are made, limited to transient URLSession failures, timeouts, HTTP 408/409/425/429, and 5xx responses.
- Retry-After accepts seconds or an HTTP date and is clamped to 0.75–60 seconds; bounded fallback delays are about 0.75 and 2 seconds.
- Request, authentication, model, and configuration failures such as HTTP 400/401/403/404 are not retried.
- User cancellation terminates the active request, backoff delay, and remaining segments, and the UI reports “已取消”.
- Final errors identify segment N/M with sanitized status text and never expose API keys, Authorization headers, the full source, or server response bodies.

### Credentials and downloads

Credential storage is unchanged: macOS keeps secrets only in the private local `credentials.json`, while Windows uses Credential Manager. Secrets are excluded from preferences, logs, backups, and release assets.

- `Pythia-1.2.1-macos-arm64.dmg` and `.sha256`
- `Pythia-1.2.1-windows-x64.exe` and `.sha256`
