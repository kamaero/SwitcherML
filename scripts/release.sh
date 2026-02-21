#!/bin/bash
set -euo pipefail

APP_NAME="SwitcherLM"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="${PROJECT_DIR}/.build/release/${APP_NAME}"
STAGING="${PROJECT_DIR}/.build/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
SYNC_VERSION_SCRIPT="${PROJECT_DIR}/scripts/sync-version.sh"

cd "$PROJECT_DIR"

if [[ -x "$SYNC_VERSION_SCRIPT" ]]; then
    "$SYNC_VERSION_SCRIPT"
fi

echo "==> Build"
swift build -c release

[[ -f "$BINARY" ]] || { echo "ERROR: binary not found at $BINARY"; exit 1; }

echo "==> Stop running instance"
killall "$APP_NAME" 2>/dev/null || true

echo "==> Assemble .app"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BINARY"  "$STAGING/Contents/MacOS/$APP_NAME"
cp Info.plist "$STAGING/Contents/Info.plist"
printf "APPL????" > "$STAGING/Contents/PkgInfo"

echo "==> Install to /Applications"
rm -rf "$INSTALL_PATH"
cp -R "$STAGING" "$INSTALL_PATH"
xattr -cr "$INSTALL_PATH" 2>/dev/null || true

echo "==> Launch"
open "$INSTALL_PATH"

echo ""
echo "Done. Look for ⌨ in the menu bar."
echo "First run: System Settings → Privacy & Security → Accessibility → $APP_NAME"
