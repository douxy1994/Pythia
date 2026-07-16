# Change Summary

## Added

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
- Authenticode-sign the production Windows installer from the Windows certificate store before publishing it.
