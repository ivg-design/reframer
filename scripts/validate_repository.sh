#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reframer-validation.XXXXXX")"

cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

cd "$REPO_PATH"

for script in scripts/*.sh; do
    bash -n "$script"
    if [ ! -x "$script" ]; then
        echo "error: script is not executable: $script" >&2
        exit 65
    fi
done

python3 scripts/validate_product_contract.py

plutil -lint \
    Reframer/Reframer.xcodeproj/project.pbxproj \
    Reframer/Reframer/Resources/Info.plist \
    Reframer/Reframer/Resources/Reframer.entitlements \
    Reframer/Reframer/Reframer.help/Contents/Info.plist

python3 -m json.tool Reframer/Reframer.xctestplan >/dev/null
python3 -m json.tool docs/product-contract.json >/dev/null

if ! grep -Fq '"key" : "REFRAMER_UI_RUNNER_AUTHORIZED"' \
        Reframer/Reframer.xctestplan ||
   ! grep -Fq '"value" : "$(REFRAMER_UI_RUNNER_AUTHORIZED)"' \
        Reframer/Reframer.xctestplan ||
   ! grep -Fq \
        '"REFRAMER_UI_RUNNER_AUTHORIZED=$REFRAMER_UI_RUNNER_AUTHORIZED"' \
        scripts/runner_test.sh; then
    echo "error: UI-runner authorization is not forwarded to XCTest" >&2
    exit 65
fi

xmllint --noout \
    Reframer/Reframer.xcodeproj/xcshareddata/xcschemes/Reframer.xcscheme

IBTOOL_LOG="$TEMP_DIR/ibtool.log"
if ! xcrun ibtool \
    --warnings \
    --errors \
    --notices \
    --compile "$TEMP_DIR/ControlBar.nib" \
    Reframer/Reframer/Resources/ControlBar.xib >"$IBTOOL_LOG"; then
    cat "$IBTOOL_LOG"
    exit 65
fi

if /usr/bin/grep -En 'clipping its content' "$IBTOOL_LOG"; then
    cat "$IBTOOL_LOG"
    echo "error: Interface Builder reports clipped controls" >&2
    exit 65
fi

if /usr/bin/grep -ERnI \
    --exclude=validate_repository.sh \
    'sqlite3[^[:cntrl:]]*TCC|INSERT OR REPLACE INTO access|killall[[:space:]]+tccd|codesign[^[:cntrl:]]*--force[^[:cntrl:]]*--sign[[:space:]]+-' \
    scripts .github Reframer; then
    echo "error: unsafe privacy or signing mutation found" >&2
    exit 65
fi

if /usr/bin/grep -ERnI \
    --include='*.swift' \
    'NSEvent\.addGlobalMonitorForEvents|AXIsProcessTrusted|AXIsProcessTrustedWithOptions|CGEvent\.tapCreate' \
    Reframer/Reframer; then
    echo "error: broad or permission-gated global keyboard observation found" >&2
    exit 65
fi

if /usr/bin/grep -En \
    'PBXFileSystemSynchronizedRootGroup|MainMenu\.xib|default\.profraw|ControlBar\.xib\.new' \
    Reframer/Reframer.xcodeproj/project.pbxproj; then
    echo "error: obsolete or internal resources remain in the app target" >&2
    exit 65
fi

if ! /usr/bin/grep -Fq \
    'ENABLE_HARDENED_RUNTIME = YES;' \
    Reframer/Reframer.xcodeproj/project.pbxproj; then
    echo "error: Hardened Runtime is not enabled in the Xcode project" >&2
    exit 65
fi

if /usr/bin/grep -ERnI \
    'com\.apple\.security\.get-task-allow|com\.apple\.security\.cs\.disable-library-validation' \
    Reframer/Reframer/Resources; then
    echo "error: prohibited release entitlement is present" >&2
    exit 65
fi

CHECKOUT_ACTION="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
UPLOAD_ACTION="actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
while IFS= read -r action_reference; do
    if ! [[ "$action_reference" =~ @[0-9a-f]{40}$ ]]; then
        echo "error: workflow action is not pinned to a full commit SHA: $action_reference" >&2
        exit 65
    fi
done < <(
    /usr/bin/grep -ERho 'uses:[[:space:]]+[^[:space:]#]+' .github/workflows |
        awk '{ print $2 }'
)

while IFS= read -r action_reference; do
    if [ "$action_reference" != "$CHECKOUT_ACTION" ] &&
       [ "$action_reference" != "$UPLOAD_ACTION" ]; then
        echo "error: workflow action is not pinned to the reviewed SHA: $action_reference" >&2
        exit 65
    fi
done < <(
    /usr/bin/grep -ERho 'actions/(checkout|upload-artifact)@[A-Za-z0-9._-]+' \
        .github/workflows
)

for workflow in .github/workflows/*.yml; do
    if ! grep -A1 '^permissions:$' "$workflow" |
        grep -Fxq '  contents: read'; then
        echo "error: workflow must default to contents: read: $workflow" >&2
        exit 65
    fi
    if ! grep -Fq "uses: $CHECKOUT_ACTION" "$workflow" ||
       ! grep -Fq "uses: $UPLOAD_ACTION" "$workflow"; then
        echo "error: workflow is missing a reviewed action pin: $workflow" >&2
        exit 65
    fi
done

CHECKOUT_COUNT="$(
    /usr/bin/grep -hFc "uses: $CHECKOUT_ACTION" .github/workflows/*.yml |
        awk '{ total += $1 } END { print total + 0 }'
)"
NONPERSISTENT_CHECKOUT_COUNT="$(
    /usr/bin/grep -hFc 'persist-credentials: false' .github/workflows/*.yml |
        awk '{ total += $1 } END { print total + 0 }'
)"
if [ "$CHECKOUT_COUNT" -ne "$NONPERSISTENT_CHECKOUT_COUNT" ]; then
    echo "error: every checkout must disable persisted credentials" >&2
    exit 65
fi

RELEASE_WORKFLOW=".github/workflows/release.yml"
for required_release_gate in \
    "needs: [quality, ui]" \
    "environment: release" \
    "contents: write" \
    "name: Verify release source" \
    "checkout did not provide origin/main" \
    "release source is not on origin/main" \
    "git merge-base --is-ancestor" \
    "release tag does not resolve to the event commit" \
    "name: Reverify release checkout" \
    "release checkout does not match the event commit" \
    "remote release tag no longer resolves to the event commit" \
    "--target \"\$GITHUB_SHA\"" \
    "changelog must contain exactly one" \
    "is still Unreleased" \
    "changelog entry for" \
    "umask 077" \
    "reframer-notary-key.p8" \
    "rm -f" \
    "name: Unit tests" \
    "name: Static analysis" \
    "name: Build documentation" \
    "name: Run UI tests serially" \
    "name: Package release"; do
    if ! grep -Fq -- "$required_release_gate" "$RELEASE_WORKFLOW"; then
        echo "error: release workflow is missing gate: $required_release_gate" >&2
        exit 65
    fi
done

if ! grep -Fq \
    "github.event.pull_request.head.repo.full_name == github.repository" \
    .github/workflows/ui-tests.yml; then
    echo "error: self-hosted PR UI tests must reject forked source" >&2
    exit 65
fi

for universal_workflow in .github/workflows/ci.yml .github/workflows/release.yml; do
    if ! grep -Fq "ARCHS='arm64 x86_64'" "$universal_workflow" ||
       ! grep -Fq "ONLY_ACTIVE_ARCH=NO" "$universal_workflow"; then
        echo "error: Release build is not explicitly universal: $universal_workflow" >&2
        exit 65
    fi
done

BUNDLE_VALIDATOR="scripts/validate_bundle.sh"
for required_bundle_gate in \
    "release bundle must not contain symbolic links" \
    "app Contents do not equal the executable/resource allowlist" \
    "_CodeSignature must contain only CodeResources" \
    "Contents/CodeResources is not a valid stapled ticket" \
    "Contents/MacOS must contain only the Reframer executable" \
    "project does not declare one numeric build version" \
    "release bundle source stamp is dirty" \
    "runtime resources do not equal the allowlist" \
    "Apple Help files do not equal the allowlist"; do
    if ! grep -Fq "$required_bundle_gate" "$BUNDLE_VALIDATOR"; then
        echo "error: bundle validator is missing gate: $required_bundle_gate" >&2
        exit 65
    fi
done

PACKAGE_SCRIPT="scripts/package_release.sh"
PACKAGE_BUNDLE_VALIDATION_COUNT="$(
    grep -Fc '"$SCRIPT_DIR/validate_bundle.sh"' "$PACKAGE_SCRIPT"
)"
if [ "$PACKAGE_BUNDLE_VALIDATION_COUNT" -lt 3 ] ||
   [ "$(grep -Fc 'REQUIRE_CLEAN_BUILD_STAMP=1' "$PACKAGE_SCRIPT")" -lt 3 ] ||
   ! grep -Fq -- '-derivedDataPath "$DERIVED_DATA_PATH"' "$PACKAGE_SCRIPT" ||
   ! grep -Fq -- '-exec "$LSREGISTER" -u' "$PACKAGE_SCRIPT" ||
   ! grep -Fq 'local release packaging requires the main branch' "$PACKAGE_SCRIPT" ||
   ! grep -Fq 'local release packaging requires HEAD to equal origin/main' \
        "$PACKAGE_SCRIPT" ||
   ! grep -Fq 'package-round-trip' "$PACKAGE_SCRIPT" ||
   ! grep -Fq 'xcrun stapler validate "$ROUND_TRIP_APP"' "$PACKAGE_SCRIPT" ||
   ! grep -Fq 'spctl --assess --type execute --verbose=2 "$ROUND_TRIP_APP"' \
        "$PACKAGE_SCRIPT"; then
    echo "error: release packager must validate the app before and after stapling and after ZIP extraction" >&2
    exit 65
fi

HELP_SOURCE="Reframer/Reframer/Reframer.help/Contents/Resources/en.lproj"
HELP_INDEX="$HELP_SOURCE/search.cshelpindex"
if [ ! -s "$HELP_INDEX" ] || [ -e "$HELP_SOURCE/search.helpindex" ]; then
    echo "error: Apple Help must contain only the modern CoreSpotlight index" >&2
    exit 65
fi
if ! /usr/bin/file -b "$HELP_INDEX" | grep -Fq 'compressed tables'; then
    echo "error: Apple Help search index is not a compiled Help index" >&2
    exit 65
fi
HELP_INDEX_LOG="$TEMP_DIR/help-index.log"
if ! hiutil \
    -I corespotlight \
    -C \
    -agv \
    -s en \
    -l en_US \
    -f "$TEMP_DIR/search.cshelpindex" \
    "$HELP_SOURCE" >"$HELP_INDEX_LOG" 2>&1; then
    cat "$HELP_INDEX_LOG"
    echo "error: Apple Help search index could not be regenerated" >&2
    exit 65
fi

TRACKED_HELP_PLIST="$TEMP_DIR/tracked-help-index.plist"
FRESH_HELP_PLIST="$TEMP_DIR/fresh-help-index.plist"
if ! /usr/bin/compression_tool \
        -decode \
        -i "$HELP_INDEX" \
        -o "$TRACKED_HELP_PLIST" ||
   ! /usr/bin/compression_tool \
        -decode \
        -i "$TEMP_DIR/search.cshelpindex" \
        -o "$FRESH_HELP_PLIST"; then
    echo "error: Apple Help search index could not be decoded" >&2
    exit 65
fi

python3 - "$TRACKED_HELP_PLIST" "$FRESH_HELP_PLIST" <<'PY'
import hashlib
import plistlib
import re
import sys

uuid_pattern = re.compile(
    rb"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}"
)


def searchable_item_hashes(path: str) -> list[str]:
    with open(path, "rb") as index_file:
        archive = plistlib.load(index_file)
    chunks = [
        uuid_pattern.sub(b"<UUID>", value)
        for value in archive.get("$objects", [])
        if isinstance(value, bytes)
    ]
    return sorted(hashlib.sha256(chunk).hexdigest() for chunk in chunks)


tracked = searchable_item_hashes(sys.argv[1])
fresh = searchable_item_hashes(sys.argv[2])
if not tracked or tracked != fresh:
    raise SystemExit(
        "error: Apple Help search index is stale; regenerate it with hiutil"
    )
PY

if [ -e default.profraw ] &&
   git ls-files --error-unmatch default.profraw >/dev/null 2>&1; then
    echo "error: code-coverage output must not be tracked" >&2
    exit 65
fi

git diff --check
echo "Repository validation passed."
