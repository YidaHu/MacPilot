#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_CONFIG="$ROOT_DIR/.macpilot-local.env"
if [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_CONFIG"
fi

: "${MACPILOT_CODESIGN_IDENTITY:?Set MACPILOT_CODESIGN_IDENTITY in .macpilot-local.env}"

LABEL="com.huyida.macpilot.fanhelper"
BUILD_DIR="$ROOT_DIR/build/fan-helper"
CONFIG_DIR="$BUILD_DIR/config"
HELPER_INFO="$CONFIG_DIR/Info.plist"
LAUNCHD_PLIST="$CONFIG_DIR/launchd.plist"
IDENTITY_LOWER="$(printf '%s' "$MACPILOT_CODESIGN_IDENTITY" | tr '[:upper:]' '[:lower:]')"
APP_REQUIREMENT="identifier \"com.huyida.macpilot\" and certificate leaf = H\"$IDENTITY_LOWER\""

rm -rf "$BUILD_DIR"
mkdir -p "$CONFIG_DIR"
cp "$ROOT_DIR/Resources/MacPilotFanHelper-Info.plist" "$HELPER_INFO"
cp "$ROOT_DIR/Resources/com.huyida.macpilot.fanhelper.plist" "$LAUNCHD_PLIST"
/usr/bin/plutil -replace MacPilotClientRequirement -string "$APP_REQUIREMENT" "$HELPER_INFO"
/usr/libexec/PlistBuddy -c "Add :SMAuthorizedClients array" "$HELPER_INFO"
/usr/bin/plutil -insert SMAuthorizedClients.0 -string "$APP_REQUIREMENT" "$HELPER_INFO"

swift build -c release --package-path "$ROOT_DIR" --product MacPilotFanHelper \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$HELPER_INFO" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __launchd_plist -Xlinker "$LAUNCHD_PLIST" >&2

HELPER_PATH="$BUILD_DIR/$LABEL"
cp "$ROOT_DIR/.build/release/MacPilotFanHelper" "$HELPER_PATH"
chmod 755 "$HELPER_PATH"
codesign --force --sign "$MACPILOT_CODESIGN_IDENTITY" --identifier "$LABEL" "$HELPER_PATH"
codesign --verify --strict --verbose=2 "$HELPER_PATH"
printf '%s\n' "$HELPER_PATH"
