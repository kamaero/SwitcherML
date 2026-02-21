#!/bin/bash
set -euo pipefail

APP_NAME="SwitcherLM"
APP_BUNDLE="${APP_NAME}.app"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Info.plist"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_DIR="${PROJECT_DIR}/.build"
STAGING_APP="${BUILD_DIR}/${APP_BUNDLE}"
SYNC_VERSION_SCRIPT="${PROJECT_DIR}/scripts/sync-version.sh"

CONFIG="release"
VERBOSE=0
SKIP_RELEASE=0
DRAFT=0

for arg in "$@"; do
    case "$arg" in
        --debug)
            CONFIG="debug"
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --no-release)
            SKIP_RELEASE=1
            ;;
        --draft)
            DRAFT=1
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./scripts/package.sh [--debug] [--verbose] [--no-release] [--draft]"
            exit 1
            ;;
    esac
done

run() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "+ $*"
    fi
    "$@"
}

if ! command -v pkgbuild >/dev/null 2>&1; then
    echo "ERROR: pkgbuild is not available. Install Xcode Command Line Tools first."
    exit 1
fi

cd "$PROJECT_DIR"

if [[ -x "$SYNC_VERSION_SCRIPT" ]]; then
    run "$SYNC_VERSION_SCRIPT"
fi

echo "==> Build (${CONFIG})"
if [[ "$VERBOSE" -eq 1 ]]; then
    run swift build -c "$CONFIG"
else
    swift build -c "$CONFIG"
fi

BINARY="${BUILD_DIR}/${CONFIG}/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found at ${BINARY}"
    exit 1
fi

echo "==> Assemble app bundle"
rm -rf "$STAGING_APP"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
cp "$BINARY" "$STAGING_APP/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST" "$STAGING_APP/Contents/Info.plist"
printf "APPL????" > "$STAGING_APP/Contents/PkgInfo"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
    VERSION="1.0.0"
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="com.switcherlm.app"
fi

mkdir -p "$DIST_DIR"
PKG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
rm -f "$PKG_PATH"

echo "==> Build installer package"
run pkgbuild \
    --component "$STAGING_APP" \
    --install-location "/Applications" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    "$PKG_PATH"

echo ""
echo "Package created:"
echo "  ${PKG_PATH}"

# ── GitHub release ─────────────────────────────────────────────────────────────

if [[ "$SKIP_RELEASE" -eq 1 ]]; then
    echo ""
    echo "Skipping GitHub release (--no-release)."
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo ""
    echo "WARNING: gh CLI not found — skipping GitHub release."
    echo "         Install with: brew install gh"
    exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
    echo ""
    echo "WARNING: gh CLI is not authenticated — skipping GitHub release."
    echo "         Run: gh auth login"
    exit 0
fi

TAG="v${VERSION}"

# Create and push the git tag (skip if it already exists)
if git -C "$PROJECT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "==> Tag ${TAG} already exists, reusing"
else
    echo "==> Tag ${TAG}"
    run git -C "$PROJECT_DIR" tag "$TAG"
    run git -C "$PROJECT_DIR" push origin "$TAG"
fi

echo "==> GitHub release ${TAG}"
RELEASE_ARGS=(
    "$TAG"
    --title "SwitcherLM ${TAG}"
    --generate-notes
    "$PKG_PATH"
)
if [[ "$DRAFT" -eq 1 ]]; then
    RELEASE_ARGS+=(--draft)
fi

run gh release create "${RELEASE_ARGS[@]}"

echo ""
echo "Release published:"
echo "  https://github.com/kamaero/SwitcherML/releases/tag/${TAG}"
