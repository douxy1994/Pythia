# Change Summary

> **2026-07-16 起，Windows 客户端迁移至 WinUI 3**（`Windows/Pythia.WinUI/`，
> C# 14 / .NET 10 / Windows App SDK 2.3.1）。旧 Flutter 工程
> `Windows/Pythia.Windows/` 保留为兼容参考。差异清单见
> [`WINDOWS_DIFF_LIST.md`](WINDOWS_DIFF_LIST.md)。

## Added

- macOS 1.2.2 adaptive compact/full window placement across mixed-size displays, a bounded scrollable compact service picker, broader WPS PDF clipboard-first selection capture, and a default-off non-activating Pythia floating selection button.
- Windows 1.2.2 per-monitor DPI-aware full/compact window placement, WPS-compatible selection capture, a default-off experimental floating selection button, and a bounded scrollable compact service picker.
- macOS 1.2.1 custom-LLM long-document pipeline with numeric/grapheme-safe chunking, exact source reconstruction, whitespace restoration, 300-second full-response attempts, bounded retry/Retry-After, sanitized N/M errors, and active request/backoff cancellation.
- macOS 1.2 compact translation window for selection and screenshot-OCR workflows, including synchronized multi-service selection and expansion to the full window.
- Configurable LLM translation service with OpenAI Chat Completions and Anthropic Messages protocol support.
- Screen-recording permission recovery with preflight/request, automatic relaunch after grant, and temporary-file OCR capture.
- Cross-platform history record schema.
- Cross-platform history collection schema.
- Cross-platform sync metadata schema.
- `PythiaCore` Swift package with platform-neutral history merge logic and tests.
- Windows development handoff under `Docs/WINDOWS_DEVELOPMENT.md` and `Windows/Pythia.Windows/README.md`.
- Architecture, WebDAV sync, feature matrix, function checklist, known issues, and release checklist documents.

## macOS Refactoring Status

- Existing macOS code is already split into `App`, `Models`, `Stores`, `Services`, and `Views`.
- The macOS app now compiles the shared `Core/PythiaCore/Sources/PythiaCore/HistorySync.swift` file into the app target. `TranslationRecord` is a compatibility alias for `PythiaHistoryRecord`, and local history writes use cross-platform fields. The next macOS refactor should route WebDAV history sync through the shared merge logic.

## Removed / Cleaned

- README no longer describes the repository as a macOS-only target.
- README now describes Pythia 1.0.0 as a cross-platform target with macOS currently buildable and Windows in development.

## Remaining Major Work

- Add richer conflict log UI and cross-platform sync status views.
- Complete the remaining user-driven Windows acceptance matrix for IME, representative selection targets, screenshot OCR language packs, tray/hotkey conflicts, mixed-DPI displays, live provider credentials, WebDAV cross-device sync, and startup-after-login.
- Add Authenticode signing in a later release; Windows 1.2.2 is published unsigned with an explicit SmartScreen warning and SHA-256 sidecar.
