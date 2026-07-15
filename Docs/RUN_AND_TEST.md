# Run and Test

## macOS

Build, install, sign, launch, and verify:

```sh
./script/build_and_run.sh --verify
```

Check local control routes:

```sh
curl -sS --max-time 5 http://127.0.0.1:60828/config
curl -sS --max-time 20 -X POST --data 'hello' http://127.0.0.1:60828/translate
```

Package:

```sh
./script/package_release.sh
hdiutil verify release/Pythia/Pythia.dmg
```

Shared core tests:

```sh
cd Core/PythiaCore
swift test
```

## Windows

Windows cannot be built on this macOS machine with the currently installed tools.

On a Windows development machine, follow `Docs/WINDOWS_DEVELOPMENT.md`. The expected commands after Flutter setup are:

```powershell
flutter test
flutter build windows --release
dart run tool/verify_release_package.dart build\windows\x64\runner\Release
```

The platform-independent native tray action map and Windows x64 CMake guard can be checked from the macOS development host:

```sh
cd Windows/Pythia.Windows
./tool/test_native_contracts.sh
```

Before Windows release, verify every Windows row in `Docs/FEATURE_MATRIX.md` and every Windows gate in `Docs/RELEASE_CHECKLIST.md`.
