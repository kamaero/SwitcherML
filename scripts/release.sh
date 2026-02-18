#!/bin/bash
set -euo pipefail

APP_NAME="SwitcherLM"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Info.plist"

usage() {
    echo "Usage: $0 [--major|--minor|--patch] [--debug] [--reset-permissions]"
}

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Info.plist not found at ${INFO_PLIST}"
    exit 1
fi

BUMP="patch"
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --major|--minor|--patch)
            BUMP="${arg#--}"
            ;;
        --debug|--reset-permissions)
            ARGS+=("$arg")
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown аргумент: $arg"
            usage
            exit 1
            ;;
    esac
done

current_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")

IFS='.' read -r major minor patch <<< "$current_version"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}

case "$BUMP" in
    major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    minor)
        minor=$((minor + 1))
        patch=0
        ;;
    patch)
        patch=$((patch + 1))
        ;;
esac

new_version="${major}.${minor}.${patch}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_version" "$INFO_PLIST"

echo "Version bump: ${current_version} -> ${new_version}"

if ((${#ARGS[@]})); then
    "${PROJECT_DIR}/scripts/install.sh" "${ARGS[@]}"
else
    "${PROJECT_DIR}/scripts/install.sh"
fi
