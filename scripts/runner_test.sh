#!/bin/bash

# Runs Reframer tests without modifying signing state, quarantine metadata, or
# macOS privacy databases. UI tests must run from an already-authorized,
# interactive self-hosted runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="${REPO_PATH:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_PATH="$REPO_PATH/Reframer/Reframer.xcodeproj"
SCHEME="${SCHEME:-Reframer}"
DESTINATION="${DESTINATION:-platform=macOS}"
TEST_SCOPE="${TEST_SCOPE:-unit}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-$REPO_PATH/.artifacts}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
ARTIFACT_DIR="$ARTIFACTS_BASE/$RUN_ID"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ARTIFACT_DIR/DerivedData}"
XCRESULT_PATH="$ARTIFACT_DIR/ReframerTests.xcresult"
LOG_PATH="$ARTIFACT_DIR/xcodebuild.log"

case "$TEST_SCOPE" in
    unit)
        TEST_SELECTION=("-only-testing:ReframerTests")
        SIGNING_ARGUMENTS=("CODE_SIGNING_ALLOWED=NO")
        ;;
    ui)
        "$SCRIPT_DIR/ui_test_preflight.sh"
        TEST_SELECTION=("-only-testing:ReframerUITests")
        SIGNING_ARGUMENTS=()
        ;;
    all)
        "$SCRIPT_DIR/ui_test_preflight.sh"
        TEST_SELECTION=()
        SIGNING_ARGUMENTS=()
        ;;
    *)
        echo "error: TEST_SCOPE must be one of: unit, ui, all" >&2
        exit 64
        ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: Xcode command-line tools are unavailable" >&2
    exit 69
fi

if [ ! -f "$PROJECT_PATH/project.pbxproj" ]; then
    echo "error: Reframer project not found at $PROJECT_PATH" >&2
    exit 66
fi

mkdir -p "$ARTIFACT_DIR"

{
    echo "Reframer test run"
    echo "Commit:      $(git -C "$REPO_PATH" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "Scope:       $TEST_SCOPE"
    echo "Destination: $DESTINATION"
    echo "Artifacts:   $ARTIFACT_DIR"
    xcodebuild -version
} | tee "$LOG_PATH"

set +e
xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$XCRESULT_PATH" \
    -parallel-testing-enabled NO \
    "${SIGNING_ARGUMENTS[@]}" \
    "${TEST_SELECTION[@]}" \
    2>&1 | tee -a "$LOG_PATH"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [ "$TEST_STATUS" -ne 0 ]; then
    echo "Reframer tests failed. Result bundle: $XCRESULT_PATH" >&2
    exit "$TEST_STATUS"
fi

echo "Reframer tests passed. Result bundle: $XCRESULT_PATH"
