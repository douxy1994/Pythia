# Pythia 1.2.2

Pythia 1.2.2 focuses on reliable selection translation and compact-window behavior across varied Windows displays. The Windows x64 installer is available now; the matching macOS package will be added to this same Release after its port is built and verified.

## 中文

- 完整窗口与简约窗口现在按当前显示器的工作区及每显示器 DPI 自适应，在多屏、不同尺寸和不同缩放比例之间切换时会保持可见，并将简约窗口放在选区附近。
- 修复简约窗口“翻译服务与顺序”列表显示不全且无法滚动的问题；列表高度会随可用空间变化，并始终支持纵向滚动。
- 增强 WPS Office 划词兼容性：在 Pythia 激活前优先通过剪贴板取得选区，并在完成后恢复用户原有剪贴板内容。
- 新增默认关闭的“实验性悬浮划词按钮”。在 Word、常见 PDF 阅读器、浏览器和聊天软件中拖选文字后，会显示 34 DIP 的 Pythia 图标；按钮不抢占焦点、5 秒后自动消失，仅在用户点击后读取文字并打开简约翻译窗口。

## English

- Full and compact windows now adapt to the active monitor's work area and per-monitor DPI, remain visible across mixed-size/mixed-scale displays, and place compact translation near the selection.
- Fixed the compact “Translation services and order” picker being clipped without a scrollbar. Its height is bounded by available space and vertical scrolling remains available.
- Improved WPS Office selection capture by using clipboard-first extraction before Pythia activates and restoring the user's clipboard afterward.
- Added a default-off experimental floating selection button. After a drag selection in Word, common PDF readers, browsers, or chat clients, a 34-DIP Pythia icon appears without stealing focus, hides after five seconds, and reads/translates only after an explicit click.

## Windows download

- `Pythia-1.2.2-windows-x64.exe`
- `Pythia-1.2.2-windows-x64.exe.sha256`

The Windows installer is not Authenticode-signed and may trigger Microsoft Defender SmartScreen. Verify the SHA-256 sidecar before installation. Release packages contain no third-party plugins or user credentials.
