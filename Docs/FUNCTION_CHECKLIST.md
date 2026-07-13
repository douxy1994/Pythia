# Function Checklist

This checklist tracks visible actions and whether they map to real behavior.

## macOS Main Window

- Translate: real. Runs enabled translation services and shows per-service results.
- Clear: real. Clears source/result content.
- Copy result: real. Copies the selected or first successful translation result.
- Speak: real. Uses macOS speech or configured TTS service.
- Collection: real entry point. Sends current source and successful target payload to configured collection plugins.
- History: real. Opens the history window.
- Settings: real. Opens the settings window.
- Source/target language controls: real. Saved preferences affect translation behavior.
- Multi-service picker: real. Enabled service list and order affect translation requests.

## macOS Settings

- General appearance/theme color: real for macOS UI preferences.
- Translation behavior: real for target language, smart target routing, delete-newline, dynamic/incremental preferences where implemented.
- Services: real for built-in and local legacy service selection/order/configuration.
- OCR: real for macOS Vision and configured OCR plugin fallback order.
- TTS: real for macOS Speech and compatible service entries.
- Collection: real for configured collection plugins.
- Hotkeys: real Carbon/global monitor registration for selection/input/OCR actions.
- Backup: real local export/import, WebDAV backup/restore, and WebDAV history sync with manual/startup/periodic/local-change-debounced/best-effort-exit triggers.
- Portable backup parity: macOS and Windows encode the same schema-v1 allowlist and history structure. macOS maps native provider names to canonical service IDs, validates product/schema/sensitive omission before restoring, creates a pre-restore history backup, merges rather than overwrites, and uploads through temporary PUT plus MOVE/fallback PUT. Legacy macOS config backups remain import-only.
- Proxy: real for built-in translation/WebDAV sessions and plugin child-process proxy environment without exposing proxy password.
- Window: real for close-on-blur, always-on-top, remember size/position where supported.
- Migration: real for local legacy configuration and plugin import.
- Update check: real, points to Pythia GitHub releases.

## macOS Menu / Status Item

- Show translator: real.
- Selection translate: real if Accessibility can read selection or clipboard fallback works.
- Input translate: real; focuses source field.
- Screenshot translate/OCR: real; uses screenshot selection and OCR.
- Settings/history: real.
- Clipboard monitor toggle: real.
- Quit: real.

## Windows Scaffolded Actions

- Main translate/copy/clear/language actions: implemented in Flutter. The provider registry includes Local, Google, Baidu, Youdao, OpenAI-compatible, DeepL, and LibreTranslate services when enabled in settings.
- Smart mixed-language routing: scaffolded. When source is auto and the input mixes Chinese and English, Windows uses the selected target language to choose the effective source (`zh-CN` for English targets, `en` for Chinese targets), matching macOS behavior.
- Service selection: scaffolded. The home page has multi-select service chips that persist through `enabledTranslateServices`; first-time OpenAI-compatible enablement inserts the service at the top, and later chip changes remain under user control.
- Settings persistence: scaffolded as local JSON settings for non-secret fields, including OpenAI-compatible service display name, base URL, model, enabled state, and service order.
- Credential storage: MethodChannel plus C++ Credential Manager implementation are wired into the included Windows runner; live Windows verification still required.
- API Key storage: OpenAI-compatible, DeepL, LibreTranslate, Baidu, and Youdao credentials write through `CredentialStore` under provider-specific keys; none are written to `settings.json`.
- History save/read/search/delete/favorite/clear/sidebar display: scaffolded. Delete and clear use logical deletion with pending sync status; favorite changes are marked for upload. Live Windows verification still required.
- WebDAV history sync: service class, manual UI trigger, connection-test UI, automatic sync timer, last-sync status display, and clear-WebDAV action are scaffolded for `/Pythia/history/history.json`; WebDAV password reads from CredentialStore instead of settings JSON. Live Windows verification still required.
- Automatic-sync schedule: both platforms use a numeric field plus minute/hour/day/week unit selector. Settings persist value/unit separately, retain a legacy total-minute field for migration, reject non-positive or longer-than-366-day intervals, and rebuild an exact-second periodic timer after saving. Windows scheduler tests prove the timer callback invokes the existing WebDAV sync action.
- Windows sync reliability: transient timeout/HTTP 408/429/5xx failures retry at most three attempts with bounded 1s/3s delays; authentication, permission, and corrupt-remote failures are not retried. Translation history add/favorite/delete/clear operations schedule one sync after a 10-second debounce. Tray quit performs a Dart handshake, waits for the current or final sync single-flight, then requests native shutdown.
- Windows backup/restore: Settings exposes local export/import through native file dialogs and WebDAV upload/download at `/Pythia/settings/portable-backup.json`. The versioned allowlist contains portable translation settings and history only. Restore validates before mutation, creates a local pre-restore history backup, merges records, preserves device settings, and marks restored records pending sync.
- Launch at startup: macOS General uses `SMAppService.mainApp`; Windows General calls the native current-user Run-key channel. Changes are applied after save rather than remaining display-only preferences.
- Update/install: settings offer installation only when an exact Windows x64 EXE/MSIX and same-name `.sha256` pair exists. Download is streamed with progress, every redirect remains on GitHub HTTPS, size/SHA-256 are checked, confirmation is required, and native `WinVerifyTrust` rejects unsigned/untrusted installers before Shell launch and app exit. Live signed Windows verification is pending.
- Release package verification: real Dart CLI/test path. `tool/verify_release_package.dart` requires an AMD64 `Pythia.exe` (PE machine `0x8664`) and rejects bundled `.potext` packages, legacy Pot plugin runner/source trees, and common private-key/API-token markers before Windows release upload. Live verification against a Windows-built release directory is still required.
- Selection translation: visible main-window action and global hotkey call `selection.readText`. The native runner first reads every selected `IUIAutomationTextRange` from the focused element's TextPattern without changing the clipboard. Unsupported controls fall back to simulated copy; a clipboard sequence-number change is required, so an unchanged old clipboard value can never be translated as the current selection. Live application compatibility verification remains required.
- Screenshot translation: the main-window action calls a native multi-monitor selection overlay, GDI capture, and Windows Runtime OCR path, then fills the source field and translates. Cancel, small selection, capture failure, missing OCR language pack, and empty OCR output return explicit feedback; live Windows verification is pending.
- Theme/window behavior settings: scaffolded. Theme selection is real in Flutter. Launch-at-startup, always-on-top, tray install/update, close-to-tray, hide-on-blur, and window placement save/restore have native Windows handlers.
- Tray menu: native/Dart path implemented. `tray.install` creates a notification-area icon, left-click restores the window, and the right-click menu exposes show, quick input translation, settings, history, WebDAV history sync, and quit. `tray.action` routes business commands to tested Dart handlers; quick translation clears and focuses the source field, settings opens the real dialog, history focuses history search, and sync invokes the existing WebDAV flow. Live Windows verification is still required.
- System notifications: the Windows General settings page persists a real notification switch (enabled by default). Startup and periodic WebDAV history sync report success or failure through the installed notification-area icon using `Shell_NotifyIconW`; manual sync remains quiet to avoid duplicate feedback, and notification failures never change sync state.
- Global hotkeys: settings provide a keyboard recorder for show-window, selection-translate, and screenshot-translate. It supports the exact key set understood by the native parser, canonicalizes modifier aliases/order, rejects bare or malformed shortcuts, and blocks duplicate actions before saving. The native runner registers them with `RegisterHotKey`; `WM_HOTKEY` routes callbacks to Dart. Live OS-level conflict verification is still required.
- Hide-on-blur: native/Dart path implemented. Settings changes call `window.setHideOnBlur`; the runner hides the window on inactive `WM_ACTIVATE` events and keeps it visible while its tray menu is open. Live Windows verification is still required.

Visible Windows actions may exist when backed by real Dart behavior. Platform-only actions must keep explicit unsupported errors until their Windows channel implementation exists.
