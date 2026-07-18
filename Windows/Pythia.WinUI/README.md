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
service picker enables, disables, and reorders built-in and plugin services.
Plugin result cards expose a single-service retry action. Selection translation
temporarily hides Pythia, copies the selection from the previously focused app,
and restores Pythia with the translation result.

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
