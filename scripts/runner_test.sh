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

mkdir -p "$ARTIFACT_DIR"

# Header
{
    echo "=== CI Test Run ==="
    echo "Timestamp:    $TIMESTAMP"
    echo "Scheme:       $SCHEME"
    echo "Destination:  $DESTINATION"
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

# Run tests
echo "=== Running Tests ===" | tee -a "$LOG_FILE"
echo "Command: xcodebuild test -scheme $SCHEME -destination '$DESTINATION'" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

TEST_EXIT_CODE=0
xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -resultBundlePath "$XCRESULT_PATH" \
    2>&1 | tee -a "$LOG_FILE" || TEST_EXIT_CODE=$?

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
    PASSED=$(grep -c " passed " "$LOG_FILE" 2>/dev/null || echo "0")
    FAILED=$(grep -c " failed " "$LOG_FILE" 2>/dev/null || echo "0")
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
