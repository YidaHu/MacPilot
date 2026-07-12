#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_CONFIG="$ROOT_DIR/.macpilot-local.env"
if [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_CONFIG"
fi
: "${MACPILOT_CODESIGN_IDENTITY:?Set MACPILOT_CODESIGN_IDENTITY in .macpilot-local.env}"

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/MacPilot.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LAUNCH_SERVICES_DIR="$CONTENTS_DIR/Library/LaunchServices"
HELPER_LABEL="com.huyida.macpilot.fanhelper"
ESCAPED_HELPER_LABEL="${HELPER_LABEL//./\\.}"

HELPER_PATH="$(bash "$ROOT_DIR/scripts/build-fan-helper.sh")"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LAUNCH_SERVICES_DIR"
cp "$ROOT_DIR/.build/release/MacPilotApp" "$MACOS_DIR/MacPilotApp"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$HELPER_PATH" "$LAUNCH_SERVICES_DIR/$HELPER_LABEL"

HELPER_REQUIREMENT="$(codesign -d -r- "$HELPER_PATH" 2>&1 | sed -n 's/^designated => //p')"
/usr/libexec/PlistBuddy -c "Add :SMPrivilegedExecutables dict" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert "SMPrivilegedExecutables.$ESCAPED_HELPER_LABEL" -string "$HELPER_REQUIREMENT" "$CONTENTS_DIR/Info.plist"

chmod 755 "$MACOS_DIR/MacPilotApp"
codesign --force --sign "$MACPILOT_CODESIGN_IDENTITY" --entitlements "$ROOT_DIR/Resources/MacPilot.entitlements" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
