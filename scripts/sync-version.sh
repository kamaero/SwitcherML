#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Info.plist"
CODE_PATH="Sources/SwitcherLM"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Info.plist not found at ${INFO_PLIST}"
    exit 1
fi

current_short="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$current_short" ]]; then
    current_short="1.0.0"
fi

IFS='.' read -r major minor current_patch <<< "$current_short"
major="${major:-1}"
minor="${minor:-0}"
current_patch="${current_patch:-0}"

if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
        patch="$(git -C "$PROJECT_DIR" rev-list --count HEAD -- "$CODE_PATH")"
    else
        patch="$current_patch"
    fi
else
    patch="$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "0") + 0 ))"
fi

new_version="${major}.${minor}.${patch}"
current_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$current_short" == "$new_version" && "$current_build" == "$new_version" ]]; then
    echo "Version is up to date: ${new_version}"
    exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${new_version}" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${new_version}" "$INFO_PLIST"

echo "Updated version to ${new_version}"
