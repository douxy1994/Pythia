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

- Build the Windows client.
- Port the WebDAV history sync implementation to Windows.
- Add richer conflict log UI and cross-platform sync status views.
- Implement platform-secure credential storage without repeated macOS prompts.
- Perform live Windows x64 runtime checks on the now CI-built installer, then Authenticode-sign the production installer from the Windows certificate store.
