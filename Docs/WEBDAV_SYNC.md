# WebDAV Sync Design

## Remote Layout

The stable cross-platform WebDAV root is `/Pythia/`:

```text
/Pythia/
  metadata.json
  history/
    history.json
  settings/
    sync-settings.json
  logs/
  attachments/
```

Portable settings/history backup uses
`/Pythia/settings/portable-backup.json` and
`Core/Schemas/portable-backup.schema.json`. It is separate from automatic
history sync. Upload writes `portable-backup.tmp.json` first and attempts a
WebDAV `MOVE`; servers without `MOVE` support receive a final-file `PUT` and
best-effort temporary-file cleanup.

The portable settings object is an explicit allowlist. It excludes provider
API keys, WebDAV address/user/password, global shortcuts, login item, window
behavior/placement, sync status, and notification preferences. Restore parses
the complete file before mutation, creates a local history backup, merges by
the shared conflict strategy, and preserves current device-specific settings.

Both clients now read and write the same portable backup at `/Pythia/settings/portable-backup.json`. macOS still searches legacy `/pot/pythia-config-backup.json` and `/pot/pot-config-backup.json` only as read-only restore fallbacks. Both clients target `/Pythia/history/history.json` and run manual, startup, periodic, local-change-debounced, and best-effort exit synchronization when automatic history sync is enabled. Windows uses a single-flight guard and waits for the active/final sync before native tray exit.

## History Record

History records must match `Core/Schemas/history-record.schema.json`:

- `id`
- `sourceText`
- `translatedText`
- `sourceLanguage`
- `targetLanguage`
- `service`
- `model`
- `createdAt`
- `updatedAt`
- `isFavorite`
- `deviceId`
- `syncStatus`
- `deletedAt`
- `schemaVersion`

## Merge Strategy

1. Parse remote data into a temporary model. If parsing fails, keep local data unchanged and surface a corruption error.
2. Back up the current local history file before writing merged data.
3. Merge by `id`.
4. Logical deletion wins over non-deleted records.
5. If neither side is deleted, the newer `updatedAt` wins.
6. If `updatedAt` is equal but content differs, keep one record, mark conflict, and write a conflict log.
7. Different IDs are always retained.
8. Mark successfully merged non-conflict records as `synced`.
9. Write local data atomically.
10. Upload the merged history after local write succeeds.

## Sync Triggers

- App startup on macOS when WebDAV backup and automatic history sync are enabled.
- App startup on Windows when automatic history sync is enabled and an address is configured.
- Local history add/favorite/delete/clear after a 10-second debounce on both platforms.
- Best-effort application exit sync. Windows tray quit waits for the current/final single-flight before shutdown.
- Windows transient failures (`-1`, HTTP 408, 429, and 5xx) retry up to three total attempts with 1-second then 3-second delay. Authentication, permission, and corrupt-remote responses do not retry.
- Manual sync button on macOS.
- Periodic automatic sync on both platforms using a persisted positive integer plus a selectable minute/hour/day/week unit. Both implementations convert the selected schedule to exact seconds, rebuild the timer immediately after settings change, run startup sync, and invoke the existing protected history-sync path when the timer fires.
- App exit best-effort sync on macOS.
- After local history changes on macOS, using a 10-second debounce.

## Failure Rules

- Network failure must not delete local data.
- Authentication failure must show a clear credential error.
- Missing remote directory should be created with `MKCOL`.
- Damaged remote JSON should be moved or copied to `logs/` when possible, then reported.
- Upload should use a temporary remote name and rename/copy when the server supports it; otherwise upload only after the merged local backup exists.

## Security

macOS does not access Keychain at runtime because repeated authorization prompts are unacceptable:

- macOS: store WebDAV passwords in `~/Library/Application Support/Pythia/credentials.json`, enforce `0600`, and never include this file in portable backup/sync payloads.
- Windows: use Credential Manager or DPAPI, never plain JSON for API keys or WebDAV passwords.
- Exported sync settings must omit API keys, provider secrets, proxy passwords, and WebDAV passwords.

## Tests Required

- First upload.
- First download.
- Manual sync.
- Automatic sync.
- Authentication failure.
- Network interruption.
- Missing remote directory.
- Corrupt remote history.
- Local and remote add different records.
- Local and remote delete same record.
- Favorite state update.
- Same ID conflict.
- Duplicate record merge.
