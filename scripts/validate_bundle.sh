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
HELPER_DIRECTORY="$APP_PATH/Contents/Helpers"
HELPER_EXECUTABLE="$HELPER_DIRECTORY/reframer-ffmpeg"
HELP_BOOK="$RESOURCES/Reframer.help"
HELP_INFO="$HELP_BOOK/Contents/Info.plist"
HELP_RESOURCES="$HELP_BOOK/Contents/Resources"
SOURCE_ENTITLEMENTS="$REPO_PATH/Reframer/Reframer/Resources/Reframer.entitlements"
SOURCE_HELPER_ENTITLEMENTS="$REPO_PATH/Reframer/Reframer/Resources/ReframerHelper.entitlements"
CONTRACT_PATH="$REPO_PATH/docs/product-contract.json"
PROJECT_FILE="$REPO_PATH/Reframer/Reframer.xcodeproj/project.pbxproj"
SOURCE_HELPER="$REPO_PATH/Reframer/Reframer/Helpers/reframer-ffmpeg"
SOURCE_RECORD="$REPO_PATH/Reframer/Reframer/Resources/ThirdPartyLicenses/SOURCE.md"
VALIDATION_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reframer-bundle-validation.XXXXXX")"
cleanup() {
    rm -rf "$VALIDATION_TEMP_DIR"
}
trap cleanup EXIT

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
        Helpers \
        MacOS \
        PkgInfo \
        Resources
    if [ -e "$APP_PATH/Contents/CodeResources" ]; then
        printf '%s\n' CodeResources
    fi
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

STAPLED_TICKET="$APP_PATH/Contents/CodeResources"
if [ -e "$STAPLED_TICKET" ]; then
    if [ ! -f "$STAPLED_TICKET" ] || [ ! -s "$STAPLED_TICKET" ]; then
        echo "error: stapled ticket must be a non-empty regular file" >&2
        exit 65
    fi
    if ! STAPLER_OUTPUT="$(xcrun stapler validate "$APP_PATH" 2>&1)"; then
        echo "$STAPLER_OUTPUT" >&2
        echo "error: Contents/CodeResources is not a valid stapled ticket" >&2
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

ACTUAL_HELPERS="$(
    find "$HELPER_DIRECTORY" -mindepth 1 -maxdepth 1 -print |
        while IFS= read -r entry; do basename "$entry"; done |
        LC_ALL=C sort
)"
if [ "$ACTUAL_HELPERS" != "reframer-ffmpeg" ] ||
   [ ! -f "$HELPER_EXECUTABLE" ] ||
   [ ! -x "$HELPER_EXECUTABLE" ]; then
    echo "error: Contents/Helpers must contain only executable reframer-ffmpeg" >&2
    echo "actual:" >&2
    echo "$ACTUAL_HELPERS" >&2
    exit 65
fi

if ! /usr/bin/codesign --verify --strict --verbose=2 "$HELPER_EXECUTABLE"; then
    echo "error: WebM helper signature is invalid" >&2
    exit 65
fi
for helper_signing_architecture in arm64 x86_64; do
    if ! /usr/bin/codesign --verify --strict --verbose=2 \
        --architecture "$helper_signing_architecture" \
        "$HELPER_EXECUTABLE"; then
        echo "error: WebM helper $helper_signing_architecture signature is invalid" >&2
        exit 65
    fi
    HELPER_IDENTIFIER="$(
        /usr/bin/codesign --display --verbose=4 \
            --architecture "$helper_signing_architecture" \
            "$HELPER_EXECUTABLE" 2>&1 |
            sed -n 's/^Identifier=//p'
    )"
    if [ "$HELPER_IDENTIFIER" != "com.reframer.app.ffmpeg" ]; then
        echo "error: WebM helper $helper_signing_architecture identifier is $HELPER_IDENTIFIER, expected com.reframer.app.ffmpeg" >&2
        exit 65
    fi

    HELPER_ENTITLEMENTS="$VALIDATION_TEMP_DIR/helper-$helper_signing_architecture-entitlements.plist"
    if ! /usr/bin/codesign --display \
        --architecture "$helper_signing_architecture" \
        --entitlements - \
        --xml \
        "$HELPER_EXECUTABLE" \
        >"$HELPER_ENTITLEMENTS" \
        2>"$VALIDATION_TEMP_DIR/helper-$helper_signing_architecture-codesign.log"; then
        echo "error: could not read WebM helper $helper_signing_architecture entitlements" >&2
        exit 65
    fi
    /usr/bin/python3 - "$HELPER_ENTITLEMENTS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as entitlement_file:
    actual = plistlib.load(entitlement_file)

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.inherit": True,
}
if actual != expected:
    raise SystemExit(
        f"error: embedded helper entitlements do not equal the privacy allowlist: {actual}"
    )
PY
done
"$SCRIPT_DIR/validate_media_helper.sh" \
    "$HELPER_EXECUTABLE" \
    "$RESOURCES/ThirdPartyLicenses/SOURCE.md"
REQUIRE_RECORDED_SHA=1 \
    "$SCRIPT_DIR/validate_media_helper.sh" \
    "$SOURCE_HELPER" \
    "$SOURCE_RECORD"

NORMALIZED_BUNDLE_HELPER="$VALIDATION_TEMP_DIR/reframer-ffmpeg-bundle"
NORMALIZED_SOURCE_HELPER="$VALIDATION_TEMP_DIR/reframer-ffmpeg-source"
/bin/cp "$HELPER_EXECUTABLE" "$NORMALIZED_BUNDLE_HELPER"
/bin/cp "$SOURCE_HELPER" "$NORMALIZED_SOURCE_HELPER"
for normalized_helper in \
    "$NORMALIZED_BUNDLE_HELPER" \
    "$NORMALIZED_SOURCE_HELPER"; do
    /usr/bin/codesign --remove-signature "$normalized_helper"
    /usr/bin/codesign --force --sign - --timestamp=none --options runtime \
        --entitlements "$SOURCE_HELPER_ENTITLEMENTS" \
        --identifier com.reframer.app.ffmpeg \
        "$normalized_helper"
done
if ! /usr/bin/cmp -s "$NORMALIZED_BUNDLE_HELPER" "$NORMALIZED_SOURCE_HELPER"; then
    echo "error: WebM helper code does not match the recorded canonical helper after deterministic ad hoc re-signing" >&2
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
EXPECTED_BUILD="$(
    sed -n \
        's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);.*/\1/p' \
        "$PROJECT_FILE" |
        LC_ALL=C sort -u
)"

if [ "$VERSION" != "$CONTRACT_VERSION" ]; then
    echo "error: bundle version $VERSION does not match contract $CONTRACT_VERSION" >&2
    exit 65
fi

if ! [[ "$EXPECTED_BUILD" =~ ^[0-9]+$ ]]; then
    echo "error: project does not declare one numeric build version" >&2
    exit 65
fi

if [ "$BUILD" != "$EXPECTED_BUILD" ] ||
   [ "$MINIMUM_OS" != "15.0" ] ||
   [ "$BUNDLE_ID" != "com.reframer.app" ]; then
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
        Reframer.help \
        ThirdPartyLicenses
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
        Contents/Resources/en.lproj/youtube-privacy.html \
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

HELPER_ARCHITECTURES="$(/usr/bin/lipo -archs "$HELPER_EXECUTABLE")"
for required_architecture in arm64 x86_64; do
    if [[ " $HELPER_ARCHITECTURES " != *" $required_architecture "* ]]; then
        echo "error: WebM helper is missing $required_architecture: $HELPER_ARCHITECTURES" >&2
        exit 65
    fi

    HELPER_SLICE_MINIMUM="$(
        xcrun vtool -show-build -arch "$required_architecture" "$HELPER_EXECUTABLE" |
            awk '/^[[:space:]]*minos / { print $2; exit }'
    )"
    if [ "$HELPER_SLICE_MINIMUM" != "$MINIMUM_OS" ]; then
        echo "error: WebM helper $required_architecture minimum OS is $HELPER_SLICE_MINIMUM, expected $MINIMUM_OS" >&2
        exit 65
    fi
done

EXPECTED_LICENSE_FILES="$(
    printf '%s\n' \
        FFmpeg-LGPL-2.1.txt \
        FFmpeg-LICENSE.md \
        SOURCE.md \
        libvpx-LICENSE.txt \
        libvpx-PATENTS.txt
)"
ACTUAL_LICENSE_FILES="$(
    find "$RESOURCES/ThirdPartyLicenses" -mindepth 1 -maxdepth 1 -type f -print |
        while IFS= read -r entry; do basename "$entry"; done |
        LC_ALL=C sort
)"
EXPECTED_LICENSE_FILES="$(printf '%s\n' "$EXPECTED_LICENSE_FILES" | LC_ALL=C sort)"
if [ "$ACTUAL_LICENSE_FILES" != "$EXPECTED_LICENSE_FILES" ]; then
    echo "error: ThirdPartyLicenses files do not equal the allowlist" >&2
    echo "expected:" >&2
    echo "$EXPECTED_LICENSE_FILES" >&2
    echo "actual:" >&2
    echo "$ACTUAL_LICENSE_FILES" >&2
    exit 65
fi

/usr/bin/python3 - "$SOURCE_ENTITLEMENTS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as entitlement_file:
    actual = plistlib.load(entitlement_file)

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-only": True,
    "com.apple.security.network.client": True,
}
if actual != expected:
    raise SystemExit(
        f"error: source entitlements do not equal the privacy allowlist: {actual}"
    )
PY

/usr/bin/python3 - "$SOURCE_HELPER_ENTITLEMENTS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as entitlement_file:
    actual = plistlib.load(entitlement_file)

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.inherit": True,
}
if actual != expected:
    raise SystemExit(
        f"error: source helper entitlements do not equal the privacy allowlist: {actual}"
    )
PY

YOUTUBE_API_KEY="$(
    /usr/libexec/PlistBuddy -c 'Print :ReframerYouTubeDataAPIKey' "$INFO_PLIST" \
        2>/dev/null || true
)"
if [[ "$YOUTUBE_API_KEY" == *'$('* ]] ||
   [[ "$YOUTUBE_API_KEY" == *'${'* ]]; then
    echo "error: bundled YouTube Data API key is an unexpanded build setting" >&2
    exit 65
fi
if [ "${REQUIRE_YOUTUBE_API_KEY:-0}" = "1" ] &&
   ! [[ "$YOUTUBE_API_KEY" =~ ^[A-Za-z0-9_-]{20,128}$ ]]; then
    echo "error: release bundle is missing a valid YouTube Data API key" >&2
    exit 65
fi

GIT_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :ReframerGitCommit' "$INFO_PLIST")"
BUILD_TIMESTAMP="$(/usr/libexec/PlistBuddy -c 'Print :ReframerBuildTimestamp' "$INFO_PLIST")"
GIT_DIRTY="$(/usr/libexec/PlistBuddy -c 'Print :ReframerGitDirty' "$INFO_PLIST")"
if ! [[ "$GIT_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] ||
   ! [[ "$BUILD_TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
   [[ "$GIT_DIRTY" != "true" && "$GIT_DIRTY" != "false" ]]; then
    echo "error: source build stamp is missing or malformed" >&2
    exit 65
fi

if [ "${REQUIRE_CLEAN_BUILD_STAMP:-0}" = "1" ] &&
   [ "$GIT_DIRTY" != "false" ]; then
    echo "error: release bundle source stamp is dirty" >&2
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
