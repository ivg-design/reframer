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
    Reframer/Reframer/Resources/Reframer.entitlements

python3 -m json.tool Reframer/Reframer.xctestplan >/dev/null
python3 -m json.tool docs/product-contract.json >/dev/null

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

if rg -n 'clipping its content' "$IBTOOL_LOG"; then
    cat "$IBTOOL_LOG"
    echo "error: Interface Builder reports clipped controls" >&2
    exit 65
fi

if rg -n \
    'sqlite3[^[:cntrl:]]*TCC|INSERT OR REPLACE INTO access|killall[[:space:]]+tccd|codesign[^[:cntrl:]]*--force[^[:cntrl:]]*--sign[[:space:]]+-' \
    scripts .github Reframer \
    --glob '!validate_repository.sh'; then
    echo "error: unsafe privacy or signing mutation found" >&2
    exit 65
fi

if rg -n \
    'NSEvent\.addGlobalMonitorForEvents|AXIsProcessTrusted|AXIsProcessTrustedWithOptions|CGEvent\.tapCreate' \
    Reframer/Reframer \
    --glob '*.swift'; then
    echo "error: broad or permission-gated global keyboard observation found" >&2
    exit 65
fi

if rg -n \
    'PBXFileSystemSynchronizedRootGroup|MainMenu\.xib|default\.profraw|ControlBar\.xib\.new' \
    Reframer/Reframer.xcodeproj/project.pbxproj; then
    echo "error: obsolete or internal resources remain in the app target" >&2
    exit 65
fi

if ! rg -q 'ENABLE_HARDENED_RUNTIME = YES;' Reframer/Reframer.xcodeproj/project.pbxproj; then
    echo "error: Hardened Runtime is not enabled in the Xcode project" >&2
    exit 65
fi

if rg -n \
    'com\.apple\.security\.get-task-allow|com\.apple\.security\.cs\.disable-library-validation' \
    Reframer/Reframer/Resources; then
    echo "error: prohibited release entitlement is present" >&2
    exit 65
fi

RELEASE_WORKFLOW=".github/workflows/release.yml"
for required_release_gate in \
    "needs: [quality, ui]" \
    "name: Unit tests" \
    "name: Static analysis" \
    "name: Build documentation" \
    "name: Run UI tests serially" \
    "name: Package release"; do
    if ! grep -Fq "$required_release_gate" "$RELEASE_WORKFLOW"; then
        echo "error: release workflow is missing gate: $required_release_gate" >&2
        exit 65
    fi
done

if [ -e default.profraw ] &&
   git ls-files --error-unmatch default.profraw >/dev/null 2>&1; then
    echo "error: code-coverage output must not be tracked" >&2
    exit 65
fi

git diff --check
echo "Repository validation passed."
