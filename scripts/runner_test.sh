#!/bin/bash

# Runs Reframer tests without modifying signing state, quarantine metadata, or
# macOS privacy databases. Built app products are ephemeral: the runner
# unregisters them from LaunchServices and removes its owned DerivedData on
# every exit. UI tests must run from an already-authorized, interactive
# self-hosted runner.

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
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
RUNNER_SENTINEL="$DERIVED_DATA_PATH/.reframer-test-runner-owned"

case "$TEST_SCOPE" in
    unit)
        TEST_SELECTION=("-only-testing:ReframerTests")
        ;;
    ui)
        "$SCRIPT_DIR/ui_test_preflight.sh"
        TEST_SELECTION=("-only-testing:ReframerUITests")
        ;;
    all)
        "$SCRIPT_DIR/ui_test_preflight.sh"
        TEST_SELECTION=()
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

case "$DERIVED_DATA_PATH" in
    ""|"/"|"$REPO_PATH"|"$ARTIFACTS_BASE")
        echo "error: unsafe DerivedData cleanup path: $DERIVED_DATA_PATH" >&2
        exit 64
        ;;
esac

if [ -e "$DERIVED_DATA_PATH" ] || [ -L "$DERIVED_DATA_PATH" ]; then
    echo "error: runner DerivedData path already exists: $DERIVED_DATA_PATH" >&2
    echo "Use a fresh RUN_ID or DERIVED_DATA_PATH." >&2
    exit 73
fi

mkdir -p "$ARTIFACT_DIR" "$DERIVED_DATA_PATH"
touch "$RUNNER_SENTINEL"

cleanup_runner_builds() {
    cleanup_status=$?
    set +e
    trap - EXIT INT TERM

    if [ -d "$DERIVED_DATA_PATH" ] && [ -x "$LSREGISTER" ]; then
        while IFS= read -r -d '' test_app; do
            "$LSREGISTER" -u "$test_app" >/dev/null 2>&1
        done < <(
            find "$DERIVED_DATA_PATH" \
                -type d \
                -name Reframer.app \
                -prune \
                -print0
        )
    fi

    if [ -f "$RUNNER_SENTINEL" ] && [ -d "$DERIVED_DATA_PATH" ]; then
        rm -rf "$DERIVED_DATA_PATH"
    fi

    exit "$cleanup_status"
}
trap cleanup_runner_builds EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

{
    echo "Reframer test run"
    echo "Commit:      $(git -C "$REPO_PATH" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "Scope:       $TEST_SCOPE"
    echo "Destination: $DESTINATION"
    echo "Artifacts:   $ARTIFACT_DIR"
    xcodebuild -version
} | tee "$LOG_PATH"

if [ "$TEST_SCOPE" = "unit" ]; then
    set +e
    xcodebuild build-for-testing \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        2>&1 | tee -a "$LOG_PATH"
    BUILD_STATUS=${PIPESTATUS[0]}
    set -e

    if [ "$BUILD_STATUS" -ne 0 ]; then
        echo "Reframer test build failed. Log: $LOG_PATH" >&2
        exit "$BUILD_STATUS"
    fi

    APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Reframer.app"
    TEST_BUNDLE="$APP_PATH/Contents/PlugIns/ReframerTests.xctest"
    DEBUG_DYLIB="$APP_PATH/Contents/MacOS/Reframer.debug.dylib"
    TEST_FRAMEWORKS="$TEST_BUNDLE/Contents/Frameworks"
    PROFILE_DIR="$DERIVED_DATA_PATH/coverage"

    if [ ! -x "$TEST_BUNDLE/Contents/MacOS/ReframerTests" ]; then
        echo "error: built unit-test bundle is missing at $TEST_BUNDLE" >&2
        exit 66
    fi

    mkdir -p "$TEST_FRAMEWORKS" "$PROFILE_DIR"
    if [ -f "$DEBUG_DYLIB" ]; then
        cp "$DEBUG_DYLIB" "$TEST_FRAMEWORKS/Reframer.debug.dylib"
    fi

    set +e
    (
        cd "$ARTIFACT_DIR"
        LLVM_PROFILE_FILE="$PROFILE_DIR/%p.profraw" \
            xcrun xctest "$TEST_BUNDLE"
    ) 2>&1 | tee -a "$LOG_PATH"
    TEST_STATUS=${PIPESTATUS[0]}
    set -e

    if [ "$TEST_STATUS" -ne 0 ]; then
        echo "Reframer unit tests failed. Log: $LOG_PATH" >&2
        exit "$TEST_STATUS"
    fi

    echo "Reframer unit tests passed. Log: $LOG_PATH"
    exit 0
fi

XCODEBUILD_ARGUMENTS=(
    test
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -resultBundlePath "$XCRESULT_PATH"
    -parallel-testing-enabled NO
)
if [ "${#TEST_SELECTION[@]}" -gt 0 ]; then
    XCODEBUILD_ARGUMENTS+=("${TEST_SELECTION[@]}")
fi
XCODEBUILD_ARGUMENTS+=(
    "REFRAMER_UI_RUNNER_AUTHORIZED=$REFRAMER_UI_RUNNER_AUTHORIZED"
)

set +e
xcodebuild "${XCODEBUILD_ARGUMENTS[@]}" 2>&1 | tee -a "$LOG_PATH"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [ "$TEST_STATUS" -ne 0 ]; then
    echo "Reframer tests failed. Result bundle: $XCRESULT_PATH" >&2
    exit "$TEST_STATUS"
fi

echo "Reframer tests passed. Result bundle: $XCRESULT_PATH"
