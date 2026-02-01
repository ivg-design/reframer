#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-$HOME/github/video-overlay/Reframer-filters}"
PROJECT_DIR="${PROJECT_DIR:-$REPO_PATH/Reframer}"
SCHEME="${SCHEME:-Reframer}"
DESTINATION="${DESTINATION:-platform=macOS}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-$HOME/ci_artifacts/reframer}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3600}"
BRANCH="${BRANCH:-feature/video-filters}"

LOG_DIR="$ARTIFACTS_BASE/launchd"
STDOUT_LOG="$LOG_DIR/runner.out.log"
STDERR_LOG="$LOG_DIR/runner.err.log"
DONE_FILE="$LOG_DIR/runner.done"
RUNNER_SCRIPT="$LOG_DIR/runner.command"

mkdir -p "$LOG_DIR"
rm -f "$DONE_FILE"

RUN_CMD="REPO_PATH=\"$REPO_PATH\" PROJECT_DIR=\"$PROJECT_DIR\" ARTIFACTS_BASE=\"$ARTIFACTS_BASE\" SCHEME=\"$SCHEME\" DESTINATION=\"$DESTINATION\" BRANCH=\"$BRANCH\" DONE_FILE=\"$DONE_FILE\" $REPO_PATH/scripts/runner_test.sh >\"$STDOUT_LOG\" 2>\"$STDERR_LOG\""

cat > "$RUNNER_SCRIPT" <<SCRIPT
#!/bin/bash
set -euo pipefail
$RUN_CMD
SCRIPT

chmod +x "$RUNNER_SCRIPT"
open -a Terminal "$RUNNER_SCRIPT"

elapsed=0
while [ ! -f "$DONE_FILE" ] && [ $elapsed -lt $TIMEOUT_SECONDS ]; do
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ -f "$DONE_FILE" ]; then
    echo "Terminal run completed. Logs:"
    echo "  stdout: $STDOUT_LOG"
    echo "  stderr: $STDERR_LOG"
    tail -n 120 "$STDOUT_LOG" 2>/dev/null || true
    exit 0
fi

echo "Timeout waiting for Terminal test run (>${TIMEOUT_SECONDS}s)."
exit 1
