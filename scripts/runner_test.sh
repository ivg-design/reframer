#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_PATH="${REPO_PATH:-$HOME/Developer/Reframer}"
PROJECT_DIR="${PROJECT_DIR:-$REPO_PATH/Reframer}"
SCHEME="${SCHEME:-Reframer}"
DESTINATION="${DESTINATION:-platform=macOS}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-$HOME/ci_artifacts}"
KEEP_ARTIFACTS="${KEEP_ARTIFACTS:-10}"
# ======================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARTIFACT_DIR="$ARTIFACTS_BASE/$TIMESTAMP"
LOG_FILE="$ARTIFACT_DIR/build.log"
SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"
XCRESULT_PATH="$ARTIFACT_DIR/TestResults.xcresult"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ARTIFACT_DIR/DerivedData}"

mkdir -p "$ARTIFACT_DIR"

# Header
{
    echo "=== CI Test Run ==="
    echo "Timestamp:    $TIMESTAMP"
    echo "Scheme:       $SCHEME"
    echo "Destination:  $DESTINATION"
    echo "DerivedData:  $DERIVED_DATA_PATH"
    echo "Artifact Dir: $ARTIFACT_DIR"
    echo ""
} | tee "$SUMMARY_FILE"

cd "$PROJECT_DIR"

# Update repo first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/runner_watch_or_pull.sh" ]; then
    REPO_PATH="$REPO_PATH" "$SCRIPT_DIR/runner_watch_or_pull.sh" 2>&1 | tee -a "$LOG_FILE"
fi

{
    echo "Git commit: $(git rev-parse --short HEAD)"
    echo "Git message: $(git log -1 --format='%s')"
    echo ""
} | tee -a "$SUMMARY_FILE"

# Discover available schemes if needed
echo "=== Available Schemes ===" >> "$LOG_FILE"
xcodebuild -list 2>&1 | tee -a "$LOG_FILE" | grep -A 20 "Schemes:" | head -10 || true
echo "" >> "$LOG_FILE"

# Build for testing first (allows us to remove quarantine before running UI tests)
echo "=== Build For Testing ===" | tee -a "$LOG_FILE"
echo "Command: xcodebuild build-for-testing -scheme $SCHEME -destination '$DESTINATION'" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

TEST_EXIT_CODE=0
xcodebuild build-for-testing \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    2>&1 | tee -a "$LOG_FILE" || TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    # Remove quarantine if present (fixes "damaged" UI test runner app)
    xattr -dr com.apple.quarantine "$DERIVED_DATA_PATH" 2>/dev/null || true

    # Ad-hoc re-sign built apps to avoid Gatekeeper launch failures in UI tests
    if [ -d "$DERIVED_DATA_PATH/Build/Products" ]; then
        while IFS= read -r app; do
            if [ -n "$app" ]; then
                codesign --force --deep --sign - "$app" 2>/dev/null || true
            fi
        done < <(find "$DERIVED_DATA_PATH/Build/Products" -name "Reframer*.app" -print 2>/dev/null)
    fi

    # Ensure Accessibility/Input Monitoring permissions for UI test runner (prevents automation prompt hang)
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$HOME/Library/Application Support/com.apple.TCC/TCC.db" ] && command -v csreq >/dev/null 2>&1; then
        TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

        tcc_insert() {
            local service="$1"
            local client="$2"
            local client_type="$3"
            local csreq_blob="$4"
            sqlite3 "$TCC_DB" \
                "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier) VALUES ('$service', '$client', $client_type, 2, 1, 1, X'$csreq_blob', 'UNUSED');" \
                2>/dev/null || true
        }

        tcc_csreq_for() {
            local target="$1"
            local req
            req=$(codesign -dr - "$target" 2>/dev/null | sed -n 's/^# designated => //p')
            if [ -n "$req" ]; then
                local tmp_req
                tmp_req=$(mktemp)
                /usr/bin/csreq -r "$req" -b "$tmp_req" 2>/dev/null || true
                if [ -s "$tmp_req" ]; then
                    xxd -p "$tmp_req" | tr -d '\n'
                fi
                rm -f "$tmp_req"
            fi
        }

        RUNNER_APP=$(find "$DERIVED_DATA_PATH/Build/Products" -name "ReframerUITests-Runner.app" -print -quit 2>/dev/null || true)
        if [ -n "$RUNNER_APP" ]; then
            CSREQ_BLOB=$(tcc_csreq_for "$RUNNER_APP")
            if [ -n "$CSREQ_BLOB" ]; then
                tcc_insert "kTCCServiceAccessibility" "com.reframer.app.ReframerUITests.xctrunner" 0 "$CSREQ_BLOB"
            fi
        fi

        XCODE_APP="/Applications/Xcode.app/Contents/MacOS/Xcode"
        DTSERVICEHUB="/Applications/Xcode.app/Contents/SharedFrameworks/DVTInstrumentsFoundation.framework/Versions/A/Resources/DTServiceHub"
        if [ -x "$XCODE_APP" ]; then
            CSREQ_BLOB=$(tcc_csreq_for "$XCODE_APP")
            if [ -n "$CSREQ_BLOB" ]; then
                tcc_insert "kTCCServiceListenEvent" "com.apple.dt.Xcode" 0 "$CSREQ_BLOB"
                tcc_insert "kTCCServiceAccessibility" "com.apple.dt.Xcode" 0 "$CSREQ_BLOB"
            fi
        fi
        if [ -x "$DTSERVICEHUB" ]; then
            CSREQ_BLOB=$(tcc_csreq_for "$DTSERVICEHUB")
            if [ -n "$CSREQ_BLOB" ]; then
                tcc_insert "kTCCServiceListenEvent" "$DTSERVICEHUB" 1 "$CSREQ_BLOB"
            fi
        fi

        killall tccd >/dev/null 2>&1 || true
    fi

    echo "=== Running Tests ===" | tee -a "$LOG_FILE"
    echo "Command: xcodebuild test-without-building -scheme $SCHEME -destination '$DESTINATION'" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    xcodebuild test-without-building \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -resultBundlePath "$XCRESULT_PATH" \
        2>&1 | tee -a "$LOG_FILE" || TEST_EXIT_CODE=$?
fi

# Extract summary from xcresult
{
    echo ""
    echo "=== Test Results ==="
} | tee -a "$SUMMARY_FILE"

if [ -d "$XCRESULT_PATH" ]; then
    # Try to get human-readable summary
    xcrun xcresulttool get --format human-readable --path "$XCRESULT_PATH" 2>/dev/null | \
        grep -E "(Test Suite|passed|failed|skipped|Test case)" | \
        head -100 | tee -a "$SUMMARY_FILE" || true

    # Count pass/fail from log
    PASSED=$(grep -c " passed " "$LOG_FILE" 2>/dev/null || true)
    FAILED=$(grep -c " failed " "$LOG_FILE" 2>/dev/null || true)
    PASSED=${PASSED:-0}
    FAILED=${FAILED:-0}
    TOTAL=$((PASSED + FAILED))

    {
        echo ""
        echo "Summary: $PASSED passed, $FAILED failed (total: $TOTAL)"
    } | tee -a "$SUMMARY_FILE"
else
    echo "WARNING: No xcresult bundle found at $XCRESULT_PATH" | tee -a "$SUMMARY_FILE"
fi

# Final status
{
    echo ""
    if [ $TEST_EXIT_CODE -eq 0 ]; then
        echo "STATUS: ✅ SUCCESS"
    else
        echo "STATUS: ❌ FAILED (exit code $TEST_EXIT_CODE)"
    fi
    echo ""
} | tee -a "$SUMMARY_FILE"

# Cleanup old artifacts (keep last N)
echo "=== Cleanup ===" >> "$LOG_FILE"
cd "$ARTIFACTS_BASE"
OLD_ARTIFACTS=$(ls -dt */ 2>/dev/null | tail -n +$((KEEP_ARTIFACTS + 1)) | wc -l | tr -d ' ')
if [ "$OLD_ARTIFACTS" -gt 0 ]; then
    ls -dt */ 2>/dev/null | tail -n +$((KEEP_ARTIFACTS + 1)) | xargs rm -rf 2>/dev/null || true
    echo "Removed $OLD_ARTIFACTS old artifact directories" >> "$LOG_FILE"
fi
echo "Keeping last $KEEP_ARTIFACTS runs" >> "$LOG_FILE"

# Print artifact locations
{
    echo "=== Artifacts ==="
    echo "Directory: $ARTIFACT_DIR"
    echo "Log:       $LOG_FILE"
    echo "Summary:   $SUMMARY_FILE"
    echo "xcresult:  $XCRESULT_PATH"
} | tee -a "$SUMMARY_FILE"

exit $TEST_EXIT_CODE
