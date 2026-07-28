#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$REPO_PATH/Reframer/Reframer.xcodeproj"
SCHEME="Reframer"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application certificate name}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer team identifier}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

if [ -n "$(git -C "$REPO_PATH" status --porcelain --untracked-files=normal)" ]; then
    echo "error: release packaging requires a clean Git worktree" >&2
    exit 65
fi

VERSION="$(
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Release \
        -showBuildSettings |
        awk '/ MARKETING_VERSION = / { print $3; exit }'
)"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: MARKETING_VERSION is not a three-part semantic version" >&2
    exit 65
fi

if [ -n "${RELEASE_VERSION:-}" ] && [ "$RELEASE_VERSION" != "$VERSION" ]; then
    echo "error: requested release $RELEASE_VERSION does not match project version $VERSION" >&2
    exit 65
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reframer-release.XXXXXX")"
cleanup() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

ARCHIVE_PATH="$WORK_DIR/Reframer.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Reframer.app"
SUBMISSION_ZIP="$WORK_DIR/Reframer-notarization.zip"
DIST_DIR="$REPO_PATH/dist"
FINAL_ZIP="$DIST_DIR/Reframer-$VERSION-macOS.zip"

xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    OTHER_CODE_SIGN_FLAGS='--timestamp'

"$SCRIPT_DIR/validate_bundle.sh" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_INFO="$(/usr/bin/codesign --display --verbose=4 "$APP_PATH" 2>&1)"
echo "$SIGNATURE_INFO"
if ! /usr/bin/grep -q 'flags=.*runtime' <<<"$SIGNATURE_INFO"; then
    echo "error: release signature does not enable Hardened Runtime" >&2
    exit 65
fi

ENTITLEMENT_INFO="$(/usr/bin/codesign --display --entitlements :- "$APP_PATH" 2>/dev/null || true)"
if /usr/bin/grep -Eq \
    'com\.apple\.security\.get-task-allow|com\.apple\.security\.cs\.disable-library-validation' \
    <<<"$ENTITLEMENT_INFO"; then
    echo "error: release contains a prohibited debugging or library-validation entitlement" >&2
    exit 65
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/Reframer")"
if [[ " $ARCHITECTURES " != *" arm64 "* ]] || [[ " $ARCHITECTURES " != *" x86_64 "* ]]; then
    echo "error: release executable is not universal: $ARCHITECTURES" >&2
    exit 65
fi

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

NOTARY_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE")
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
fi

xcrun notarytool submit "$SUBMISSION_ZIP" "${NOTARY_ARGUMENTS[@]}" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

echo "Release artifact: $FINAL_ZIP"
