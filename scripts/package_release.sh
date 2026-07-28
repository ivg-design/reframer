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

if [ "${GITHUB_ACTIONS:-false}" != "true" ]; then
    CURRENT_BRANCH="$(git -C "$REPO_PATH" branch --show-current)"
    if [ "$CURRENT_BRANCH" != "main" ]; then
        echo "error: local release packaging requires the main branch" >&2
        exit 65
    fi
    if ! git -C "$REPO_PATH" rev-parse --verify --quiet origin/main >/dev/null; then
        echo "error: local release packaging requires origin/main" >&2
        exit 65
    fi
    if [ "$(git -C "$REPO_PATH" rev-parse HEAD)" != \
         "$(git -C "$REPO_PATH" rev-parse origin/main)" ]; then
        echo "error: local release packaging requires HEAD to equal origin/main" >&2
        exit 65
    fi
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
DERIVED_DATA_PATH="$WORK_DIR/DerivedData"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        if [ -x "$LSREGISTER" ]; then
            find "$WORK_DIR" \
                -type d \
                -name 'Reframer.app' \
                -prune \
                -exec "$LSREGISTER" -u '{}' \; \
                >/dev/null 2>&1 || true
        fi
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

ARCHIVE_PATH="$WORK_DIR/Reframer.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Reframer.app"
SUBMISSION_ZIP="$WORK_DIR/Reframer-notarization.zip"
NOTARY_RESULT="$WORK_DIR/notarization-result.json"
DIST_DIR="$REPO_PATH/dist"
FINAL_ZIP="$DIST_DIR/Reframer-$VERSION-macOS.zip"
NOTARY_RECORD="$DIST_DIR/Reframer-$VERSION-notarization.json"
CHECKSUM_FILE="$DIST_DIR/SHA256SUMS.txt"

xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    OTHER_CODE_SIGN_FLAGS='--timestamp'

REQUIRE_CLEAN_BUILD_STAMP=1 "$SCRIPT_DIR/validate_bundle.sh" "$APP_PATH"
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

ENTITLEMENT_PATH="$WORK_DIR/Reframer-release-entitlements.plist"
/usr/bin/codesign --display --entitlements :- "$APP_PATH" >"$ENTITLEMENT_PATH" 2>/dev/null
/usr/bin/python3 - "$ENTITLEMENT_PATH" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as entitlement_file:
    actual = plistlib.load(entitlement_file)
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-only": True,
}
if actual != expected:
    raise SystemExit(
        f"error: release entitlements do not equal the allowlist: {actual}"
    )
PY

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

xcrun notarytool submit \
    "$SUBMISSION_ZIP" \
    "${NOTARY_ARGUMENTS[@]}" \
    --wait \
    --output-format json |
    tee "$NOTARY_RESULT"

NOTARY_ID="$(
    /usr/bin/python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' \
        "$NOTARY_RESULT"
)"
NOTARY_STATUS="$(
    /usr/bin/python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' \
        "$NOTARY_RESULT"
)"
if [ -z "$NOTARY_ID" ] || [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "error: notarization was not accepted: id=$NOTARY_ID status=$NOTARY_STATUS" >&2
    exit 65
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
REQUIRE_CLEAN_BUILD_STAMP=1 "$SCRIPT_DIR/validate_bundle.sh" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
/bin/rm -f "$FINAL_ZIP" "$NOTARY_RECORD" "$CHECKSUM_FILE"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"
/usr/bin/install -m 0644 "$NOTARY_RESULT" "$NOTARY_RECORD"

ROUND_TRIP_DIR="$WORK_DIR/package-round-trip"
ROUND_TRIP_APP="$ROUND_TRIP_DIR/Reframer.app"
mkdir -p "$ROUND_TRIP_DIR"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$ROUND_TRIP_DIR"
REQUIRE_CLEAN_BUILD_STAMP=1 "$SCRIPT_DIR/validate_bundle.sh" "$ROUND_TRIP_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$ROUND_TRIP_APP"
xcrun stapler validate "$ROUND_TRIP_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$ROUND_TRIP_APP"

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 \
        "$(basename "$FINAL_ZIP")" \
        "$(basename "$NOTARY_RECORD")" >"$(basename "$CHECKSUM_FILE")"
)

echo "Notarization submission: $NOTARY_ID"
echo "Release artifact: $FINAL_ZIP"
echo "Release checksums: $CHECKSUM_FILE"
