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

On the home page, Enter translates and Shift+Enter inserts a line break. The
service picker enables, disables, and drag-reorders built-in and plugin services.
Plugin result cards show packaged provider icons and expose a single-service retry
action. Selection translation reads UI Automation TextPattern first and uses a
clipboard-preserving copy fallback only when necessary. Screenshot actions freeze
the multi-monitor desktop, accept a drag region, run Windows OCR, and optionally
translate the recognized text.

Settings includes hotkey recording with atomic conflict rollback, Windows
Credential Manager-backed secrets, manual/automatic WebDAV history sync, local
and WebDAV portable backup/restore, and an SHA-256-verified GitHub update flow.
Portable backups omit passwords and API keys.

## Build

```powershell
dotnet build .\Pythia.WinUI.csproj -c Release -p:Platform=x64
```

## Smoke tests

```powershell
$env:PYTHIA_NETWORK_TEST = "1"
dotnet run --project ..\Pythia.WinUI.Tests\Pythia.WinUI.Tests.csproj -c Release
```

## Installer

```powershell
.\tool\build-installer.ps1 -Version 1.0.0
```
