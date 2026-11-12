# Pythia 1.2.5

macOS-only patch release. Windows stays at 1.2.4; its existing assets remain on the v1.2.4 release page.

## 中文

- 修复划词原文在取词阶段丢失段落的问题：辅助功能可能返回全部文字却合并段落，旧版本遇到非空结果便直接翻译，导致简约窗口中首段独立、后续内容合并，或整篇合为一段。
- 取词统一核对本次复制结果，不再仅对 Word/WPS 采用复制路径；仅接受剪贴板已更新后的内容，读取后恢复原剪贴板，复制失败则回退到辅助功能结果。
- 对相同文字选择换行更完整的表示，支持辅助功能文本、剪贴板纯文本及 RTF，避免结构较少的版本覆盖完整段落。
- 保持现有换行设置：关闭“翻译结果删除换行”时，本地保存和还原段落、空行与缩进；开启时继续输出紧凑文本。简约窗口、完整窗口共用修复后的取词路径。
- 取词复制与剪贴板恢复期间暂停剪贴板自动翻译，避免旧剪贴板内容覆盖本次划词结果。
- 更新应用内“最近版本更新”，新增取词和多段翻译回归检查。

## English

- Fix paragraph loss during selection capture. A nonempty Accessibility result can contain all selected words but omit paragraph separators; the previous early return passed that flattened source into translation.
- Check a fresh clipboard copy for every source app, retain the existing clipboard change detection and restoration, and fall back to Accessibility when copying fails.
- Prefer the more structured representation of identical text across Accessibility, copied plain text and RTF.
- Keep Remove Line Breaks behavior unchanged. Both compact and full windows use the corrected capture path.
- Update in-app release notes and add offline selection-to-translation and RTF regression checks.

## Validation

- Core tests, production selection-method fixtures, private-pasteboard RTF checks, translation dispatcher regressions and macOS UI source contracts are checked for this release.
- Selection fixtures cover a four-paragraph source with only the first boundary left in Accessibility, all boundaries removed, copying failure, missing Accessibility text, and a more structured Accessibility result.
- The fixture provider deliberately removes newlines; source separators are still restored in order by the production chunk policy.
- These automated checks do not establish a complete cross-application desktop selection matrix. If neither Accessibility nor the copied representations contain the original boundaries, the app does not invent them from punctuation.

## Download

- `Pythia-1.2.5-macos-arm64.dmg`
- `Pythia-1.2.5-macos-arm64.dmg.sha256`

Requires macOS 14 or later on Apple silicon. Uses the project's stable local signing identity, without Apple Developer ID notarization. No user credentials, history or third-party plugins are bundled.
