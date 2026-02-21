#!/bin/bash
set -euo pipefail

APP_NAME="SwitcherLM"
BUNDLE_ID="com.switcherlm.app"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"
INSTALL_PATH="${INSTALL_DIR}/${APP_BUNDLE}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Info.plist"
SYNC_VERSION_SCRIPT="${PROJECT_DIR}/scripts/sync-version.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

VERBOSE=0
NO_LAUNCH=0
NON_INTERACTIVE=0

for arg in "$@"; do
    case "$arg" in
        --verbose)
            VERBOSE=1
            ;;
        --no-launch)
            NO_LAUNCH=1
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            NO_LAUNCH=1
            ;;
    esac
done

run() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "+ $*"
    fi
    "$@"
}

# ── 1. Build ────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  ${APP_NAME} — Build & Install"
echo "═══════════════════════════════════════════"
echo ""

cd "$PROJECT_DIR"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
    warn "Building in DEBUG mode"
fi

if [[ -x "$SYNC_VERSION_SCRIPT" ]]; then
    run "$SYNC_VERSION_SCRIPT"
fi

log "Building (${CONFIG})..."
if [[ "$VERBOSE" -eq 1 ]]; then
    run swift build -c "$CONFIG"
else
    swift build -c "$CONFIG" 2>&1 | tail -5
fi

BINARY=".build/${CONFIG}/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    err "Build failed — binary not found at ${BINARY}"
fi

log "Build succeeded."

# ── 2. Kill running instance ────────────────────────────────
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    warn "Stopping running ${APP_NAME}..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# ── 3. Assemble .app bundle ────────────────────────────────
STAGING="${PROJECT_DIR}/.build/${APP_BUNDLE}"
rm -rf "$STAGING"

MACOS_DIR="${STAGING}/Contents/MacOS"
RESOURCES_DIR="${STAGING}/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Binary
cp "$BINARY" "${MACOS_DIR}/${APP_NAME}"

# Info.plist
cp "$INFO_PLIST" "${STAGING}/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "${STAGING}/Contents/PkgInfo"

log "App bundle assembled at .build/${APP_BUNDLE}"

# ── 4. Install to /Applications ─────────────────────────────
if [[ -d "$INSTALL_PATH" ]]; then
    warn "Removing previous installation..."
    rm -rf "$INSTALL_PATH"
fi

log "Installing to ${INSTALL_PATH}..."
run cp -R "$STAGING" "$INSTALL_PATH"

# ── 5. Clear quarantine (important for CGEvent tap) ─────────
run xattr -cr "$INSTALL_PATH" 2>/dev/null || true

# ── 6. Reset TCC if requested ──────────────────────────────
if [[ "${1:-}" == "--reset-permissions" || "${2:-}" == "--reset-permissions" ]]; then
    warn "Resetting Accessibility permissions for ${BUNDLE_ID}..."
    run tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    log "Permissions reset. You will be prompted again on launch."
fi

# ── 7. Launch ───────────────────────────────────────────────
echo ""
log "Installation complete."
echo ""

if [[ "$NO_LAUNCH" -eq 1 ]]; then
    echo "Launch skipped (--no-launch)."
    echo "To launch manually:"
    echo "   open ${INSTALL_PATH}"
    echo ""
    exit 0
fi

if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    exit 0
fi

read -rp "Launch ${APP_NAME} now? [Y/n] " answer
if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
    run open "$INSTALL_PATH"
    log "Launched. Look for the ⌨ icon in the menu bar."
    echo ""
    warn "If this is the first run, grant Accessibility access:"
    echo "   System Settings → Privacy & Security → Accessibility → ${APP_NAME}"
else
    echo ""
    echo "To launch manually:"
    echo "   open ${INSTALL_PATH}"
fi

echo ""
