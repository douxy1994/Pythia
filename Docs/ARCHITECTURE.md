# Pythia Cross-Platform Architecture

## Current Decision

Pythia keeps the current macOS native application instead of replacing it with a cross-platform shell. The next Windows implementation should be built as a separate Windows-native or near-native client that consumes the same schemas and service contracts.

The project is split into these layers:

- `Core`: platform-neutral data models, history merge logic, schema definitions, error categories, provider request contracts, and sync contracts.
- `Platform`: system integrations such as secure storage, global shortcuts, selected-text reading, screenshot capture, OCR, tray/status item, login item, notifications, file locations, and update hooks.
- `UI`: macOS AppKit/Liquid Glass windows and menus; Windows should use a Windows 11 design system with Mica/Acrylic or equivalent material.
- `Storage`: local settings, history, cache, plugin metadata, logs, and schema migrations.
- `Sync`: WebDAV directory layout, metadata, history merge, retry, corruption handling, and status reporting.
- `Release`: build scripts, signing, versioning, update checks, release notes, and plugin exclusion checks.

## Technology Route

The macOS client remains Swift/AppKit because that is the only current implementation with real working selection translation, screenshot OCR, status bar behavior, signing, and Accessibility permission handling.

The Windows client should not reuse macOS UI code. Recommended route:

1. Build Windows UI with Flutter for Windows if the development machine has Flutter installed.
2. Continue validating the implemented Windows platform channels on real Windows x64 hardware. Credential Manager, selected-text fallback, screenshot OCR, startup, topmost, complete tray callbacks, close-to-tray, hide-on-blur, global hotkeys, window placement, system notifications, hotkey recording, and verified update installation now have concrete implementations.
3. Keep provider contracts and WebDAV schemas in `Core/Schemas` as the source of truth.
4. Port `PythiaCore` history merge behavior into Dart tests or move the core to Rust later if both platforms need a single binary library.

Alternatives considered:

- Swift on Windows: attractive for model reuse, but Windows Swift GUI/tooling and platform integrations add too much risk.
- Electron: faster to bootstrap, but conflicts with the requirement to avoid a rough web shell and increases package size.
- Qt/C++: good native reach, but makes macOS Swift parity harder and adds C++ maintenance overhead.
- React Native Windows: viable, but smaller ecosystem for desktop-specific OCR/tray/hotkey details than Flutter/WinUI.
- Rust core plus native UIs: strong long-term option, but a larger migration than is justified before the Windows UI exists.

## Current Gap

The existing macOS app has a WebDAV backup/restore feature, not the full bidirectional history sync required by the cross-platform objective. `Core/PythiaCore` now contains the first shared history record model and merge algorithm; macOS still needs to migrate its current `TranslationRecord` persistence to the cross-platform record format.
