#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-$HOME/github/video-overlay/Reframer-filters}"
PROJECT_DIR="${PROJECT_DIR:-$REPO_PATH/Reframer}"
SCHEME="${SCHEME:-Reframer}"
DESTINATION="${DESTINATION:-platform=macOS}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-$HOME/ci_artifacts/reframer}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3600}"
BRANCH="${BRANCH:-feature/video-filters}"

LABEL="com.reframer.uitest"
UID_CURRENT=$(id -u)
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$ARTIFACTS_BASE/launchd"
STDOUT_LOG="$LOG_DIR/runner.out.log"
STDERR_LOG="$LOG_DIR/runner.err.log"
DONE_FILE="$LOG_DIR/runner.done"

mkdir -p "$LOG_DIR"
rm -f "$DONE_FILE"

RUN_CMD="REPO_PATH=\"$REPO_PATH\" PROJECT_DIR=\"$PROJECT_DIR\" ARTIFACTS_BASE=\"$ARTIFACTS_BASE\" SCHEME=\"$SCHEME\" DESTINATION=\"$DESTINATION\" BRANCH=\"$BRANCH\" DONE_FILE=\"$DONE_FILE\" $REPO_PATH/scripts/runner_test.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>$RUN_CMD</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$STDOUT_LOG</string>
    <key>StandardErrorPath</key>
    <string>$STDERR_LOG</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_CURRENT" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$UID_CURRENT" "$PLIST"
launchctl kickstart -k "gui/$UID_CURRENT/$LABEL"

elapsed=0
while [ ! -f "$DONE_FILE" ] && [ $elapsed -lt $TIMEOUT_SECONDS ]; do
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ -f "$DONE_FILE" ]; then
    echo "LaunchAgent run completed. Logs:"
    echo "  stdout: $STDOUT_LOG"
    echo "  stderr: $STDERR_LOG"
    tail -n 120 "$STDOUT_LOG" 2>/dev/null || true
    exit 0
fi

echo "Timeout waiting for LaunchAgent test run (>${TIMEOUT_SECONDS}s)."
exit 1
