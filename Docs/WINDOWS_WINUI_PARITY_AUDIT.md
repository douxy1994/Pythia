# Windows WinUI parity audit — 2026-07-18

## Candidate

- Branch: `codex/windows-final`
- Client: `Windows/Pythia.WinUI` (WinUI 3, C# 14, .NET 10, x64)
- Installer: `Windows/Pythia.WinUI/dist/Pythia-1.0.0-windows-x64.exe`
- Size: `121089532` bytes
- SHA-256: `a9fdd028c53ac1963812e798eb893648ebed50761045a62c8eb086acba75bb10`
- Local install: `%LOCALAPPDATA%\Programs\Pythia\Pythia.exe`
- GitHub: not pushed

## Implemented parity work

- The real multiline input now intercepts Enter through `PreviewKeyDown` before WinUI consumes it as a line break; Shift+Enter, IME composition, repeat suppression, and single-flight duplicate prevention remain explicit.
- Settings now displays one category at a time and embeds a real translation-plugin console with installed-plugin selection, icons, enable/disable, install/remove, manifest-driven fields, credential preservation, configuration save, and connectivity testing.
- Native drag reorder plus keyboard reorder; enabled services and order share one persisted model.
- Smart auto-language direction for pure Chinese, pure English, and mixed Chinese/English.
- Audited Fluent action icons, accessible names/tooltips, synchronized application icon, packaged plugin icons, and Pythia fallback icon.
- Plugin retry on result cards and classified 30-second connectivity tests with one bounded retry.
- Strict `.pythia` manifest/archive/process/output validation, bundled Node-only production runtime, secret redaction, and atomic update rollback.
- UI Automation-first selection translation with clipboard-preserving sequence-checked fallback.
- Multi-monitor frozen screenshot drag selection, reverse drag, cancellation, image OCR, and optional translation.
- Source/result copy, line merge, clear, copy-all, favorite, speech, result expand/collapse, pin, screenshot, and image OCR actions.
- Logical history deletion/tombstones, favorite synchronization timestamps, conflict merge, periodic/local-change/tray WebDAV sync, and pre-sync backup.
- Local/WebDAV portable backup and restore with schema/product validation and omitted credentials.
- Hotkey recorder with canonical formatting, duplicate validation, atomic runtime replacement, and rollback.
- GitHub update check, exact Windows x64 asset selection, same-name SHA-256 requirement, bounded download, confirmation, and installer launch.
- Single instance, tray actions, close-to-tray, hide-on-blur, startup entry, always-on-top, and clamped multi-monitor placement.

## Regression evidence

The final rewrite regression passed after the real XAML event and settings controls changed:

- Release build: 0 warnings, 0 errors.
- Native smoke suite: passed.
- Exact homepage icon mapping assertions: passed.
- Enter/Shift/IME/repeat/dedup policy assertions and the real `HomePage.xaml` `PreviewKeyDown` binding contract: passed.
- The real `SettingsPage.xaml` plugin-console contract, dynamic configuration actions, and startup navigation routes: passed.
- First-to-last, last-to-first, invalid/cancelled reorder and persistence assertions: passed.
- Plugin protocol, timeout, redaction, unsafe archive, ordered dispatch, icon discovery, and classifier assertions: passed.
- History newest-wins, tombstone-wins, conflict, backup omission, schedule, and favorite timestamp assertions: passed.
- Screenshot reverse-drag geometry, hotkey parser, smart language routing, update version, and WebDAV URL assertions: passed.
- `git diff --check`: passed.
- Raw `FontIcon`/`Glyph` source scan: zero matches.

## Installed plugin connectivity

All six repository plugins are installed in the WinUI data directory and enabled in persisted service order.

| Plugin | Classified result | Attempts | Notes |
| --- | --- | ---: | --- |
| Alibaba Qwen3.5-35B-A3B | Success | 1 | Real response completed in about 0.6 seconds. |
| Qiniu GLM 4.5 Air free | Upstream service error | 2 | One bounded retry completed. |
| DeepSeek | Missing credential | 0 | Preflight stopped before network/process execution. |
| SenseNova | Missing credential | 0 | Preflight stopped before network/process execution. |
| SiliconFlow | Invalid credential | 1 | Authentication classification returned. |
| Xiaomi MiMo | Invalid credential | 1 | Authentication classification returned. |

Five packages contain provider artwork and render that file; SenseNova has no packaged image and uses the Pythia fallback icon. No secret-named configuration key is present in `plugin-state.json`.

## Package and install evidence

- Installer sidecar SHA-256 matches the installer.
- Published `Pythia.exe` PE machine is AMD64 `0x8664`.
- Pinned `Runtime\node.exe` and `Assets\pythia-plugin-runner.cjs` are present.
- Publish tree contains no `.pythia`, `.potext`, plugin state, settings, history, PEM/PFX/key, or user `Plugins` payload.
- Clean uninstall removed the executable and both shortcuts while preserving settings/history.
- Reinstall restored executable, pinned runtime, desktop shortcut, and Start menu shortcut.
- Launching the installed executable twice produced one Pythia process.
- Installed executable hash matches the published executable.
- Visual Studio Community 2026 `18.8.0` is installed with the official `Microsoft.VisualStudio.Workload.Universal` WinUI application-development workload; `Pythia.Windows.slnx` opens both Windows projects.
- Installer is intentionally unsigned for local testing; production publishing remains blocked on Authenticode signing.

## Environment-dependent acceptance still requiring a human/live account

- The Windows desktop automation helper activated the final installed executable and verified the rendered plugin settings page, including the installed provider, dynamic fields, save action, and connectivity action. Its keyboard injection did not deliver characters or Return to WinUI controls, so a human must still press Enter once and check Microsoft Pinyin candidate confirmation. Drag reorder, selection capture, screenshot overlay, hotkey dispatch, audio, and visual DPI review also remain human desktop checks.
- Credentialed built-in providers and missing/invalid plugin credentials need valid accounts before a success result is possible.
- WebDAV manual/periodic/cross-device sync needs a real WebDAV endpoint.
- Production updater acceptance needs a signed GitHub Release installer; the local candidate is not signed and was not pushed.

These items are reported as external acceptance dependencies, not inferred as passing.
