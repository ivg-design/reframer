#!/bin/bash

set -euo pipefail

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "usage: $0 /path/to/Reframer.app" >&2
    exit 64
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
RESOURCES="$APP_PATH/Contents/Resources"
EXECUTABLE="$APP_PATH/Contents/MacOS/Reframer"

if [ ! -f "$INFO_PLIST" ] || [ ! -x "$EXECUTABLE" ]; then
    echo "error: incomplete Reframer bundle at $APP_PATH" >&2
    exit 65
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid semantic version in bundle: $VERSION" >&2
    exit 65
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]] || [ "$MINIMUM_OS" != "15.0" ] || [ "$BUNDLE_ID" != "com.reframer.app" ]; then
    echo "error: bundle metadata does not match the product contract" >&2
    exit 65
fi

if [ ! -d "$RESOURCES/Reframer.help" ]; then
    echo "error: Apple Help Book is missing from the app bundle" >&2
    exit 65
fi

if [ ! -f "$RESOURCES/Assets.car" ] || [ ! -f "$RESOURCES/ControlBar.nib" ]; then
    echo "error: required interface resources are missing" >&2
    exit 65
fi

PROHIBITED="$(
    find "$RESOURCES" -type f \( \
        -name '*.md' -o \
        -name '*.profraw' -o \
        -name '*.xcresult' -o \
        -name '*.xctestplan' -o \
        -name 'project.pbxproj' -o \
        -name 'MainMenu.nib' \
    \) -print
)"

if [ -n "$PROHIBITED" ]; then
    echo "error: internal files leaked into the release bundle:" >&2
    echo "$PROHIBITED" >&2
    exit 65
fi

echo "Bundle contract passed: Reframer $VERSION ($BUILD), macOS $MINIMUM_OS+"
