#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Pythia.xcodeproj"
DERIVED_DATA="$ROOT/build/PythiaDerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/Pythia.app"
APP="/Applications/Pythia.app"
SIGN_IDENTITY="Pot Local Code Signing"
EXPECTED_REQUIREMENT='identifier "com.douxy.pythia" and certificate leaf = H"a493ef6f181ec595f5216b01a4e2008778c4a592"'

verify_stable_identity() {
  local app="$1"
  codesign --verify --deep --strict "$app"
  local requirement
  requirement="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
  if [[ "$requirement" != "$EXPECTED_REQUIREMENT" ]]; then
    echo "Unexpected Pythia signing requirement:" >&2
    echo "  $requirement" >&2
    echo "Expected:" >&2
    echo "  $EXPECTED_REQUIREMENT" >&2
    exit 1
  fi
}

security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null

if pgrep -x Pythia >/dev/null 2>&1; then
  pkill -x Pythia
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme Pythia \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  build

rm -rf "$APP"
/usr/bin/ditto "$BUILT_APP" "$APP"
/usr/bin/codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" --entitlements "$ROOT/Pythia/Pythia.entitlements" "$APP"
verify_stable_identity "$APP"
/usr/bin/open -n "$APP"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 1
  pgrep -x Pythia >/dev/null
  verify_stable_identity "$APP"
  plutil -p "$APP/Contents/Info.plist" | grep -E 'CFBundleDisplayName|CFBundleIdentifier|CFBundleName'
fi
