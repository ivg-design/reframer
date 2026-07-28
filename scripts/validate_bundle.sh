#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-}"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "usage: $0 /path/to/Reframer.app" >&2
    exit 64
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
RESOURCES="$APP_PATH/Contents/Resources"
EXECUTABLE="$APP_PATH/Contents/MacOS/Reframer"
HELP_BOOK="$RESOURCES/Reframer.help"
HELP_INFO="$HELP_BOOK/Contents/Info.plist"
HELP_RESOURCES="$HELP_BOOK/Contents/Resources"
SOURCE_ENTITLEMENTS="$REPO_PATH/Reframer/Reframer/Resources/Reframer.entitlements"
CONTRACT_PATH="$REPO_PATH/docs/product-contract.json"

if [ ! -f "$INFO_PLIST" ] || [ ! -x "$EXECUTABLE" ]; then
    echo "error: incomplete Reframer bundle at $APP_PATH" >&2
    exit 65
fi

FIRST_SYMLINK="$(find "$APP_PATH" -type l -print -quit)"
if [ -L "$EXECUTABLE" ] || [ -n "$FIRST_SYMLINK" ]; then
    echo "error: release bundle must not contain symbolic links" >&2
    exit 65
fi

EXPECTED_CONTENTS="$(
    printf '%s\n' \
        Info.plist \
        MacOS \
        PkgInfo \
        Resources
    if [ -d "$APP_PATH/Contents/_CodeSignature" ]; then
        printf '%s\n' _CodeSignature
    fi
)"
ACTUAL_CONTENTS="$(
    find "$APP_PATH/Contents" -mindepth 1 -maxdepth 1 -print |
        while IFS= read -r entry; do basename "$entry"; done |
        LC_ALL=C sort
)"
EXPECTED_CONTENTS="$(printf '%s\n' "$EXPECTED_CONTENTS" | LC_ALL=C sort)"
if [ "$ACTUAL_CONTENTS" != "$EXPECTED_CONTENTS" ]; then
    echo "error: app Contents do not equal the executable/resource allowlist" >&2
    echo "expected:" >&2
    echo "$EXPECTED_CONTENTS" >&2
    echo "actual:" >&2
    echo "$ACTUAL_CONTENTS" >&2
    exit 65
fi

SIGNATURE_DIRECTORY="$APP_PATH/Contents/_CodeSignature"
if [ -d "$SIGNATURE_DIRECTORY" ]; then
    ACTUAL_SIGNATURE_FILES="$(
        find "$SIGNATURE_DIRECTORY" -mindepth 1 -maxdepth 1 -print |
            while IFS= read -r entry; do basename "$entry"; done |
            LC_ALL=C sort
    )"
    if [ "$ACTUAL_SIGNATURE_FILES" != "CodeResources" ] ||
       [ ! -f "$SIGNATURE_DIRECTORY/CodeResources" ]; then
        echo "error: _CodeSignature must contain only CodeResources" >&2
        echo "actual:" >&2
        echo "$ACTUAL_SIGNATURE_FILES" >&2
        exit 65
    fi
fi

ACTUAL_EXECUTABLES="$(
    find "$APP_PATH/Contents/MacOS" -mindepth 1 -maxdepth 1 -print |
        while IFS= read -r entry; do basename "$entry"; done |
        LC_ALL=C sort
)"
if [ "$ACTUAL_EXECUTABLES" != "Reframer" ]; then
    echo "error: Contents/MacOS must contain only the Reframer executable" >&2
    echo "actual:" >&2
    echo "$ACTUAL_EXECUTABLES" >&2
    exit 65
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
CONTRACT_VERSION="$(
    /usr/bin/python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1]))["product"]["version"])' \
        "$CONTRACT_PATH"
)"

if [ "$VERSION" != "$CONTRACT_VERSION" ]; then
    echo "error: bundle version $VERSION does not match contract $CONTRACT_VERSION" >&2
    exit 65
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]] || [ "$MINIMUM_OS" != "15.0" ] || [ "$BUNDLE_ID" != "com.reframer.app" ]; then
    echo "error: bundle metadata does not match the product contract" >&2
    exit 65
fi

if [ ! -d "$HELP_BOOK" ] || [ ! -f "$HELP_INFO" ]; then
    echo "error: Apple Help Book is missing from the app bundle" >&2
    exit 65
fi

EXPECTED_TOP_LEVEL_RESOURCES="$(
    printf '%s\n' \
        AppIcon.icns \
        Assets.car \
        ControlBar.nib \
        Reframer.help
)"
ACTUAL_TOP_LEVEL_RESOURCES="$(
    find "$RESOURCES" -mindepth 1 -maxdepth 1 -print |
        while IFS= read -r resource; do basename "$resource"; done |
        LC_ALL=C sort
)"
if [ "$ACTUAL_TOP_LEVEL_RESOURCES" != "$EXPECTED_TOP_LEVEL_RESOURCES" ]; then
    echo "error: runtime resources do not equal the allowlist" >&2
    echo "expected:" >&2
    echo "$EXPECTED_TOP_LEVEL_RESOURCES" >&2
    echo "actual:" >&2
    echo "$ACTUAL_TOP_LEVEL_RESOURCES" >&2
    exit 65
fi

EXPECTED_HELP_FILES="$(
    printf '%s\n' \
        Contents/Info.plist \
        Contents/Resources/en.lproj/filters.html \
        Contents/Resources/en.lproj/getting-started.html \
        Contents/Resources/en.lproj/index.html \
        Contents/Resources/en.lproj/loading-videos.html \
        Contents/Resources/en.lproj/lock-mode.html \
        Contents/Resources/en.lproj/opacity.html \
        Contents/Resources/en.lproj/playback.html \
        Contents/Resources/en.lproj/search.cshelpindex \
        Contents/Resources/en.lproj/shortcuts.html \
        Contents/Resources/en.lproj/zoom-pan.html \
        Contents/Resources/shared/styles.css
)"
ACTUAL_HELP_FILES="$(
    find "$HELP_BOOK" -type f -print |
        sed "s#^$HELP_BOOK/##" |
        LC_ALL=C sort
)"
if [ "$ACTUAL_HELP_FILES" != "$EXPECTED_HELP_FILES" ]; then
    echo "error: Apple Help files do not equal the allowlist" >&2
    echo "expected:" >&2
    echo "$EXPECTED_HELP_FILES" >&2
    echo "actual:" >&2
    echo "$ACTUAL_HELP_FILES" >&2
    exit 65
fi

HELP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HELP_INFO")"
HELP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$HELP_INFO")"
HELP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HELP_INFO")"
HELP_INDEX="$(/usr/libexec/PlistBuddy -c 'Print :HPDBookIndexPath' "$HELP_INFO")"
if [ "$HELP_VERSION" != "$VERSION" ] ||
   [ "$HELP_BUILD" != "$BUILD" ] ||
   [ "$HELP_IDENTIFIER" != "com.reframer.help" ] ||
   [ "$HELP_INDEX" != "search.cshelpindex" ] ||
   [ ! -s "$HELP_RESOURCES/en.lproj/$HELP_INDEX" ]; then
    echo "error: Apple Help metadata or modern search index is invalid" >&2
    exit 65
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$EXECUTABLE")"
for required_architecture in arm64 x86_64; do
    if [[ " $ARCHITECTURES " != *" $required_architecture "* ]]; then
        echo "error: release executable is missing $required_architecture: $ARCHITECTURES" >&2
        exit 65
    fi

    SLICE_MINIMUM="$(
        xcrun vtool -show-build -arch "$required_architecture" "$EXECUTABLE" |
            awk '/^[[:space:]]*minos / { print $2; exit }'
    )"
    if [ "$SLICE_MINIMUM" != "$MINIMUM_OS" ]; then
        echo "error: $required_architecture minimum OS is $SLICE_MINIMUM, expected $MINIMUM_OS" >&2
        exit 65
    fi
done

/usr/bin/python3 - "$SOURCE_ENTITLEMENTS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as entitlement_file:
    actual = plistlib.load(entitlement_file)

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-only": True,
}
if actual != expected:
    raise SystemExit(
        f"error: source entitlements do not equal the privacy allowlist: {actual}"
    )
PY

GIT_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :ReframerGitCommit' "$INFO_PLIST")"
BUILD_TIMESTAMP="$(/usr/libexec/PlistBuddy -c 'Print :ReframerBuildTimestamp' "$INFO_PLIST")"
GIT_DIRTY="$(/usr/libexec/PlistBuddy -c 'Print :ReframerGitDirty' "$INFO_PLIST")"
if ! [[ "$GIT_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] ||
   ! [[ "$BUILD_TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
   [[ "$GIT_DIRTY" != "true" && "$GIT_DIRTY" != "false" ]]; then
    echo "error: source build stamp is missing or malformed" >&2
    exit 65
fi

if git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    EXPECTED_COMMIT="$(git -C "$REPO_PATH" rev-parse --short HEAD)"
    if [ "$GIT_COMMIT" != "$EXPECTED_COMMIT" ]; then
        echo "error: bundle was built from $GIT_COMMIT, current source is $EXPECTED_COMMIT" >&2
        exit 65
    fi
fi

echo "Bundle contract passed: Reframer $VERSION ($BUILD), macOS $MINIMUM_OS+, $ARCHITECTURES"
