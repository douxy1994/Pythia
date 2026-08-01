# Pythia Release Checklist

> **Windows 客户端已于 2026-07-16 转向 WinUI 3。** Windows 段落已重写为 WinUI 等价物
> （`dotnet publish`、`Windows/Pythia.WinUI/`、原生 smoke 套件、
> `Windows/Pythia.WinUI/tool/build-installer.ps1`）。Authenticode 代码路径已就绪，
> 真实签名待 EXT-1 证书，详见 [`WINDOWS_DIFF_LIST.md`](WINDOWS_DIFF_LIST.md)。

## Shared

- Version is `1.0.0`.
- Update checks point to `https://github.com/douxy1994/Pythia/releases`.
- Release artifacts are named `Pythia`.
- Release artifacts contain no bundled plugins.
- README describes Pythia and does not link to the original project.
- Sensitive values are not included in app bundles, archives, release notes, or generated logs.
- `.pythia` examples and development guide pass `node script/validate_pythia_plugins.mjs`.
- Public packages in `Plugins/` contain only their Manifest, JavaScript entry, optional icon, and GPL license; checksums match `Plugins/catalog.json` and no user configuration or secret is present.
- Manual `.potext` installation creates a validated `.pythia`, preserves the original backup, and retains a usable compatibility path after conversion failure.
- Settings migration converts old Pot plugins directly to `.pythia`; successful conversions leave no Pythia-side legacy copy or `.potext` backup, while failures are not imported.

## macOS

- `./script/build_and_run.sh --verify` succeeds.
- `/Applications/Pythia.app` launches and exits cleanly.
- `curl http://127.0.0.1:60828/config` returns `OK`.
- `POST /translate` returns a translation for `hello`.
- App verifies with the stable local signing identity.
- `./script/package_release.sh` produces `release/Pythia/Pythia.app` and `release/Pythia/Pythia.dmg`.
- `hdiutil verify release/Pythia/Pythia.dmg` succeeds.
- Accessibility selection translation does not prompt repeatedly after updates signed by the same identity.
- Service, WebDAV, proxy, and plugin credentials migrate out of UserDefaults into `credentials.json`; the file is `0600`, portable backups omit it, and the app contains no `SecItem` runtime calls.

## Windows

> WinUI 3 客户端（`Windows/Pythia.WinUI/`）。阶段二已关闭 P0 系统通知与 P1 OCR 语言包；
> Authenticode 代码路径已就绪，真实签名待 EXT-1 证书（见 [`WINDOWS_DIFF_LIST.md`](WINDOWS_DIFF_LIST.md)）。

- `dotnet build Windows/Pythia.WinUI -c Debug` 与 `-c Release` 均通过（0 warning / 0 error）。
- `dotnet run --project Windows/Pythia.WinUI.Tests` 通过（83 项原生 smoke 断言）。
- `node script/validate_pythia_plugins.mjs` 通过（Git Bash 下需用 Windows 原生 `tar` 或改用 cmd/PowerShell）。
- `dotnet publish Windows/Pythia.WinUI -c Release -r win-x64 --self-contained` 通过；发布树为 win-x64、自包含、不含 Flutter/Dart 运行时、不含插件/凭据/私钥/测试项目。
- `Windows/Pythia.WinUI/tool/build-installer.ps1` 生成 `dist/Pythia-<version>-windows-x64.exe` 与同名 `.sha256` sidecar。
- 系统通知：`NotificationsEnabled` 真实门控气泡；更新发现/后台 WebDAV 同步/OCR 缺语言包三个流程接入气泡（人工实机验收见 EXT-8）。
- OCR：显式枚举 zh/en 语言包，缺首选包回退并提示，两者皆无才中止（人工实机验收见 EXT-9）。
- Authenticode 签名（**待 EXT-1 证书**）：配置 `PYTHIA_WIN_CERT_FILE`+`PYTHIA_WIN_CERT_PASSWORD`（或 `PYTHIA_WIN_CERT_SHA1`，可选 `PYTHIA_WIN_TIMESTAMP_URL`）后，`build-installer.ps1` 自动签名 exe 与安装包；签名失败中止正式发布构建。证书与私钥文件绝不提交或上传。
- Authenticode 校验：`UpdateService` 在 SHA-256 通过后执行 `WinVerifyTrust`（`AuthenticodeVerifier`）；配置 `ExpectedPublisher` 后启用签名身份锁定；签名无效/不可信/身份不符时拒绝更新。
- App starts, exits, restarts; 单实例运行通过。
- 主翻译流程、设置保存与行为、Credential Manager 凭据存储、托盘菜单（6 项）、4 组全局快捷键均工作。
- 卸载移除当前用户 `Pythia` Run 值且不影响既存值；卸载后无残留启动项或运行进程。
- 安装包与 `.sha256` 一同上传至同一 GitHub Release。

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
