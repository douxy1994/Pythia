# Change Summary

## Added

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

- Port the macOS 1.2 compact window and Anthropic-compatible custom LLM provider to Windows, then complete live Windows verification.
- Add richer conflict log UI and cross-platform sync status views.
- Perform live Windows x64 runtime checks on the now CI-built installer, then Authenticode-sign the production installer from the Windows certificate store.
