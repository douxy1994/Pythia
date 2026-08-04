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
- Compact translation window: real. Selection and screenshot-OCR translation can show only result cards with retry/copy, synchronized multi-service selection, and a one-click expansion into the full window.

## macOS Settings

- General appearance/theme color: real for macOS UI preferences.
- General compact-window toggle: real. Controls the default presentation for selection and screenshot-OCR translation.
- Translation behavior: real for target language, smart target routing, delete-newline, dynamic/incremental preferences where implemented.
- Services: real for built-in and local legacy service selection/order/configuration. Custom LLM translation services support configurable OpenAI Chat Completions or Anthropic Messages interfaces, name, base URL, model, and private API key.
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
- Screenshot translate/OCR: real; preflights and requests screen-recording access, relaunches after first grant, captures to a temporary PNG, and distinguishes cancellation from capture failure.
- Settings/history: real.
- Clipboard monitor toggle: real.
- Quit: real.

## Windows WinUI 3 Actions

- Home translation: native C# implementation for Google, Baidu, Youdao, OpenAI-compatible, DeepL, LibreTranslate, and installed `.pythia` plugins. Enter submits, Shift+Enter inserts a line break, IME composition and repeated-key submission are suppressed, and a single-flight gate prevents duplicate batches.
- Home tools: copy source, paste, merge line breaks, clear, selection translation, full-virtual-screen OCR/translation, image-file OCR, copy all, favorite, speech, pin, language swap, result expand/collapse, per-result copy, and plugin retry are connected to real handlers.
- Smart language routing: source `auto` routes pure Chinese to English, pure English to Simplified Chinese, and mixed Chinese/English according to the selected target, matching macOS.
- Service selection and ordering: the same dialog owns enabled state and persisted order. Native `ListView` drag-reorder and Ctrl+Up/Ctrl+Down keyboard reordering are supported; translation dispatch and result order follow the saved order.
- Icons: homepage, navigation, settings, plugins, and history actions use packaged Fluent SVG resources with accessible names and tooltips. Installed plugins display their packaged SVG/PNG/JPEG/ICO icon or the Pythia fallback icon. See `WINDOWS_ICON_MAPPING.md`.
- Plugins: `.pythia` manifest, archive, path, payload, process, timeout, output-size, secret-redaction, and response validation are implemented. Configuration secrets use Windows Credential Manager. Connectivity runs for at most 30 seconds, retries at most once, and reports an exact classified state. Reinstalling the same ID is an atomic update with rollback.
- History: search, load back to Home, favorite, copy, CSV export, logical delete, clear, and persistence are implemented. Tombstones remain in storage for cross-device synchronization.
- WebDAV: connection test, manual sync, periodic sync, local-change debounce, tray sync, merge/conflict handling, `/Pythia/history/history.json`, and pre-sync local snapshots are implemented. Local and WebDAV portable backup/restore use schema v1 and omit credentials.
- Global hotkeys: four recorder fields generate canonical combinations. `RegisterHotKey` replacement validates formats and duplicates, attempts the complete new set, and restores the previous runtime set if any registration fails.
- Selection translation: UI Automation TextPattern is primary. Controlled Ctrl+C fallback requires the clipboard sequence number to change, restores the previous clipboard payload in `finally`, and never translates stale clipboard text.
- OCR: image-file OCR and a frozen multi-monitor drag-region overlay use Windows Runtime `OcrEngine`; reverse drag, Esc/right-click cancellation, minimum selection size, missing language packs, empty text, and capture failures return actionable status.
- Window and shell: single instance, tray show/quick input/history/sync/settings/exit, startup Run entry, close-to-tray, hide-on-blur, always-on-top, and multi-monitor-clamped window placement are implemented.
- Update flow: Settings checks the official GitHub latest release, requires the exact Windows x64 installer and same-name SHA-256 file, streams with a 512 MiB bound, verifies SHA-256, asks in-app confirmation, then launches the installer and exits. Production Authenticode signing remains a release requirement; the locally installed test build is intentionally unsigned.

Live tests requiring real credentials, a WebDAV account, an OCR language pack, audio output, third-party selection controls, or a signed production installer remain environment-dependent and must be reported rather than inferred.
