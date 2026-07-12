#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_CONFIG="$ROOT_DIR/.macpilot-local.env"
if [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_CONFIG"
fi
: "${MACPILOT_CODESIGN_IDENTITY:?Set MACPILOT_CODESIGN_IDENTITY in .macpilot-local.env}"

swift build -c release --package-path "$ROOT_DIR" --product MacPilotFanRecovery
RECOVERY_DIR="$ROOT_DIR/build/fan-recovery"
RECOVERY_PATH="$RECOVERY_DIR/MacPilotFanRecovery"
mkdir -p "$RECOVERY_DIR"
cp "$ROOT_DIR/.build/release/MacPilotFanRecovery" "$RECOVERY_PATH"
chmod 755 "$RECOVERY_PATH"
codesign --force --sign "$MACPILOT_CODESIGN_IDENTITY" --identifier com.huyida.macpilot "$RECOVERY_PATH"
exec "$RECOVERY_PATH"
