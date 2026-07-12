# Pythia Release Checklist

## Shared

- Version is `1.0.0`.
- Update checks point to `https://github.com/douxy1994/Pythia/releases`.
- Release artifacts are named `Pythia`.
- Release artifacts contain no bundled plugins.
- README describes Pythia and does not link to the original project.
- Sensitive values are not included in app bundles, archives, release notes, or generated logs.

## macOS

- `./script/build_and_run.sh --verify` succeeds.
- `/Applications/Pythia.app` launches and exits cleanly.
- `curl http://127.0.0.1:60828/config` returns `OK`.
- `POST /translate` returns a translation for `hello`.
- App verifies with the stable local signing identity.
- `./script/package_release.sh` produces `release/Pythia/Pythia.app` and `release/Pythia/Pythia.dmg`.
- `hdiutil verify release/Pythia/Pythia.dmg` succeeds.
- Accessibility selection translation does not prompt repeatedly after updates signed by the same identity.

## Windows

- Windows project builds with an x64 Visual Studio toolchain; non-x64 CMake configuration is rejected.
- `Pythia.exe` is AMD64 (`PE machine 0x8664`), verified by the release package gate.
- App starts, exits, and restarts.
- Main translation flow works.
- Settings save and change behavior.
- API keys and WebDAV credentials are stored via Credential Manager or DPAPI.
- Tray menu exposes translate, settings, history, sync, and quit.
- Global hotkeys work.
- Screenshot translation has a real implementation or clear unavailable-state message.
- Release package contains no plugins.
- `dart run tool/verify_release_package.dart build\windows\x64\runner\Release` succeeds before upload, including x64, plugin exclusion, and secret scans.
- `powershell -File tool/build_windows_installer.ps1` creates `dist/Pythia-1.0.0-windows-x64.exe` and its same-name `.sha256` sidecar.
- Production installer is Authenticode-signed by setting `PYTHIA_WINDOWS_CERT_SHA1` to a certificate already in the Windows certificate store before packaging.
- Both installer and `.sha256` are uploaded to the same GitHub Release; certificate and private-key files are never uploaded or committed.

## Sync

- WebDAV connection test works.
- Manual sync works.
- Automatic sync works.
- macOS-created history appears on Windows.
- Windows-created history appears on macOS.
- Concurrent additions merge.
- Delete/favorite state syncs.
- Corrupt remote data does not overwrite local history.
- Network failure does not lose local history.
