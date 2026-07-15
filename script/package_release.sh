#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Pythia.xcodeproj"
DERIVED_DATA="$ROOT/build/PythiaDerivedData"
CONFIGURATION="Release"
PRODUCTS="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP="$PRODUCTS/Pythia.app"
DIST="$ROOT/release/Pythia"
DMG="$DIST/Pythia.dmg"
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

rm -rf "$DIST"
mkdir -p "$DIST"
security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null

xcodebuild \
  -project "$PROJECT" \
  -scheme Pythia \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

cp -R "$APP" "$DIST/Pythia.app"
codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" --entitlements "$ROOT/Pythia/Pythia.entitlements" "$DIST/Pythia.app"
verify_stable_identity "$DIST/Pythia.app"

if find "$DIST/Pythia.app" \( -iname "*.potext" -o -iname "*.pythia" -o -path "*/Plugins/*" \) | grep -q .; then
  echo "Release app must not include third-party plugin packages." >&2
  find "$DIST/Pythia.app" \( -iname "*.potext" -o -iname "*.pythia" -o -path "*/Plugins/*" \) >&2
  exit 1
fi

if rg -Il \
  --glob '*.{json,js,cjs,plist,txt,md,env,pem,key}' \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|gh[pousr]_[A-Za-z0-9]{20,})' \
  "$DIST/Pythia.app" | grep -q .; then
  echo "Release app contains material matching a private credential pattern." >&2
  exit 1
fi

hdiutil create \
  -volname "Pythia" \
  -srcfolder "$DIST/Pythia.app" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null

echo "$DIST/Pythia.app"
echo "$DMG"
