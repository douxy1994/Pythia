# Pythia for Windows (native)

This is the native Windows client for Pythia. It uses C# 14, .NET 10, WinUI 3,
and Windows App SDK 2.3.1. The unpackaged self-contained build keeps the existing
Inno Setup installation flow and does not require Developer Mode or a test MSIX
certificate.

The client reads the existing Windows settings, history, plugin, runtime, and
credential locations, so upgrading from `Pythia.Windows` preserves local data.

Translation plugins use the same `.pythia` package, manifest, Node runner,
`plugin-state.json`, and `Pythia/plugin.<id>.<key>` credential convention as the
cross-platform client. Existing Pot configurations are imported idempotently
from `%APPDATA%\com.pot-app.desktop\config.json`; secret fields are moved
directly into Windows Credential Manager and are never written to JSON.

On the home page, the real multiline input intercepts Enter with
`PreviewKeyDown` before WinUI inserts a line break; Shift+Enter still inserts a
line break, and the shortcut guidance lives in the input placeholder. The
service picker enables, disables, and drag-reorders built-in and plugin services.
Plugin result cards show packaged provider icons and expose a single-service retry
action. Plugin subprocess output is decoded as strict UTF-8. Selection translation
freezes the external target before Pythia hides, reads UI Automation TextPattern
first, waits for global-hotkey modifiers to be released, and uses a
clipboard-preserving copy fallback only when necessary. Screenshot actions freeze
the multi-monitor desktop, accept a drag region, run Windows OCR, and optionally
translate the recognized text.

Settings shows one category at a time. Plugins have one canonical entry in the
main sidebar, where they can be installed, configured, enabled, disabled, removed,
and connectivity-tested. About and updates live only in Settings. Settings also includes
hotkey recording with atomic conflict rollback, Windows
Credential Manager-backed secrets, manual/automatic WebDAV history sync, local
and WebDAV portable backup/restore, and an SHA-256-verified GitHub update flow.
Portable backups omit passwords and API keys.

## Build

```powershell
dotnet build ..\..\Pythia.Windows.slnx -c Release
```

The solution is supported by Visual Studio Community 2026 with the `WinUI
application development` workload.

## Smoke tests

```powershell
$env:PYTHIA_NETWORK_TEST = "1"
dotnet run --project ..\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
```

## Installer

```powershell
.\tool\build-installer.ps1 -Version 1.0.0
```
