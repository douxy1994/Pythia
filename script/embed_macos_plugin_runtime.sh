#!/bin/sh
set -eu

destination="${1:?missing destination directory}"
node_runtime="${PYTHIA_NODE_RUNTIME:-}"
if [ -z "$node_runtime" ]; then
  node_runtime="$(command -v node || true)"
fi
if [ -z "$node_runtime" ] || [ ! -x "$node_runtime" ]; then
  echo "error: Node.js is required to embed the Pythia plugin runtime." >&2
  exit 1
fi

resolved_runtime="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$node_runtime")"
if ! /usr/bin/lipo "$resolved_runtime" -verify_arch arm64 >/dev/null 2>&1; then
  echo "error: Pythia macOS requires an arm64 Node.js runtime: $resolved_runtime" >&2
  exit 1
fi

runtime_directory="$destination/runtime"
mkdir -p "$runtime_directory"
/bin/cp -f "$resolved_runtime" "$runtime_directory/node"
/bin/chmod 755 "$runtime_directory/node"

node_version="$($resolved_runtime --version)"
/usr/bin/plutil -create xml1 "$runtime_directory/runtime.plist"
/usr/bin/plutil -insert version -string "$node_version" "$runtime_directory/runtime.plist"
/usr/bin/plutil -insert architecture -string "arm64" "$runtime_directory/runtime.plist"

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$runtime_directory/node"
else
  /usr/bin/codesign --force --sign - --timestamp=none "$runtime_directory/node"
fi
