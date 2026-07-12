# Windows Credential Channel

Pythia Windows must not store API keys or WebDAV passwords in `settings.json`.
The Flutter scaffold uses:

```dart
const MethodChannel('pythia/credential_store')
```

The native C++ implementation is provided and already registered by the included Windows runner:

```text
Windows/Pythia.Windows/windows/runner/pythia_credential_channel.h
Windows/Pythia.Windows/windows/runner/pythia_credential_channel.cpp
```

`windows/runner/flutter_window.cpp` calls `RegisterPythiaCredentialChannel` after the Flutter engine is created, and `windows/CMakeLists.txt` links the runner with `Advapi32`.

## Channel Methods

- `readSecret({key}) -> String?`
- `writeSecret({key, value})`
- `deleteSecret({key})`

Secrets are stored as generic Windows credentials with target names prefixed by:

```text
Pythia/
```

Current keys used by the scaffold:

```text
webdav.password
provider.openai-compatible.apiKey
provider.deepl.apiKey
provider.libretranslate.apiKey
provider.baidu.appId
provider.baidu.secret
provider.youdao.appKey
provider.youdao.secret
```

## Verification

On Windows:

```powershell
flutter test
flutter run -d windows
```

Then verify:

1. Saving a WebDAV password does not modify `settings.json`.
2. The sync button can read the saved password after app restart.
3. Deleting the credential from Windows Credential Manager causes sync to show a credential error.
4. No API key or WebDAV password appears in logs, backup files, or exported settings.
