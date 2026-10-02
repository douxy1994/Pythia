# Pythia 1.2.4

This shared patch release includes macOS arm64 and Windows x64. Windows assets
were added after the macOS release; the original macOS tag is retained. The
Windows build's source commit is recorded in the GitHub release and executable
informational version.

## 中文

- 修复关闭“翻译结果删除换行”时，多段翻译仍可能被服务端合并成一行的问题。换行、空行及缩进在本地保存并按原顺序还原。
- 分段翻译最多并发两个请求，并复用匹配代理配置的网络连接；完成顺序不影响译文顺序。
- 翻译服务卡片增加原生等待动画；成功、失败、取消及清空时结束动画，重新翻译也显示提示。
- 单卡重新翻译增加请求代次检查及取消、超时清理，避免旧请求覆盖新结果。
- 为换行设置、分段顺序、并发上限、取消处理及连接复用增加离线回归测试。

## English

- Preserve line separators, blank lines and indentation locally when Remove Line Breaks is disabled, even when the provider flattens the input.
- Run up to two translation segments concurrently and reuse connections with matching proxy settings while retaining source order.
- Show a native spinner in each service card during translation and retry, stopping it on completion, failure, cancellation or clearing.
- Guard per-card retries against stale responses and clean up cancellation and timeout state.
- Add offline regression checks for newline preferences, ordering, concurrency, cancellation and connection reuse.

## macOS download

- `Pythia-1.2.4-macos-arm64.dmg`
- `Pythia-1.2.4-macos-arm64.dmg.sha256`

Requires macOS 14 or later on Apple silicon. Packages contain no third-party plugins or user credentials. The app uses the project's stable local signing identity, without Apple Developer ID notarization.

Preserving every line separator requires separate line requests and may increase request counts for short multiline selections. Real-world latency depends on the provider and network; offline timing is not a production speed guarantee.

## Windows x64

- Synchronize local newline/indentation preservation across built-in services,
  OpenAI/Anthropic-compatible APIs and plugins; the new output option defaults off.
- Limit each service to two concurrent segments and each batch to four services;
  preserve source order, numeric tokens and Unicode grapheme boundaries.
- Show progress and completed results per service in full and compact windows.
  Cancel and invalidate previous batches and retries on clear, navigation or close.
- Preserve the existing Google RPC/dictionary fallback and five-minute LLM retry
  policy. Settings, history, credentials and plugins retain their existing format.
- Assets: `Pythia-1.2.4-windows-x64.exe` and matching `.sha256`.
- Windows packages are not Authenticode-signed and may trigger SmartScreen.
  Existing macOS assets and tag are unchanged.
