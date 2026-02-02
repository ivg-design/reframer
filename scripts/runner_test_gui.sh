#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-$HOME/github/video-overlay/Reframer-filters}"
PROJECT_DIR="${PROJECT_DIR:-$REPO_PATH/Reframer}"
SCHEME="${SCHEME:-Reframer}"
DESTINATION="${DESTINATION:-platform=macOS}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-$HOME/ci_artifacts/reframer}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3600}"
BRANCH="${BRANCH:-feature/video-filters}"
ONLY_TESTS="${ONLY_TESTS:-}"
UITEST_MPV_VIDEO_PATH="${UITEST_MPV_VIDEO_PATH:-}"
UITEST_AV1_VIDEO_PATH="${UITEST_AV1_VIDEO_PATH:-}"
UITEST_YOUTUBE_URL="${UITEST_YOUTUBE_URL:-}"
UITEST_CLEAN_MPV="${UITEST_CLEAN_MPV:-}"
UITEST_CLEAN_MPV_YT="${UITEST_CLEAN_MPV_YT:-}"

LOG_DIR="$ARTIFACTS_BASE/launchd"
ENV_FILE="${ENV_FILE:-$LOG_DIR/runner.env}"
STDOUT_LOG="$LOG_DIR/runner.out.log"
STDERR_LOG="$LOG_DIR/runner.err.log"
DONE_FILE="$LOG_DIR/runner.done"
RUNNER_SCRIPT="$LOG_DIR/runner.command"
TERMINAL_APP="/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"

mkdir -p "$LOG_DIR"
rm -f "$DONE_FILE"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$ENV_FILE"
    set +a
fi

if command -v sqlite3 >/dev/null 2>&1 && command -v csreq >/dev/null 2>&1 && [ -x "$TERMINAL_APP" ]; then
    TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -f "$TCC_DB" ]; then
        REQ=$(codesign -dr - "$TERMINAL_APP" 2>/dev/null | sed -n -E 's/^#?[[:space:]]*designated => //p')
        if [ -n "$REQ" ]; then
            TMP_REQ=$(mktemp)
            /usr/bin/csreq -r "=$REQ" -b "$TMP_REQ" 2>/dev/null || true
            if [ -s "$TMP_REQ" ]; then
                CSREQ_BLOB=$(xxd -p "$TMP_REQ" | tr -d '\n')
                sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier) VALUES ('kTCCServiceListenEvent', 'com.apple.Terminal', 0, 2, 1, 1, X'$CSREQ_BLOB', 'UNUSED');" 2>/dev/null || true
                sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier) VALUES ('kTCCServiceAccessibility', 'com.apple.Terminal', 0, 2, 1, 1, X'$CSREQ_BLOB', 'UNUSED');" 2>/dev/null || true
                killall tccd >/dev/null 2>&1 || true
            fi
            rm -f "$TMP_REQ"
        fi
    fi
fi

ENV_EXPORTS=()
for var in ONLY_TESTS UITEST_MPV_VIDEO_PATH UITEST_AV1_VIDEO_PATH UITEST_YOUTUBE_URL UITEST_CLEAN_MPV UITEST_CLEAN_MPV_YT; do
    value="${!var:-}"
    if [ -n "$value" ]; then
        ENV_EXPORTS+=("$var=\"$value\"")
    fi
done

RUN_CMD="REPO_PATH=\"$REPO_PATH\" PROJECT_DIR=\"$PROJECT_DIR\" ARTIFACTS_BASE=\"$ARTIFACTS_BASE\" SCHEME=\"$SCHEME\" DESTINATION=\"$DESTINATION\" BRANCH=\"$BRANCH\" DONE_FILE=\"$DONE_FILE\" ${ENV_EXPORTS[*]} $REPO_PATH/scripts/runner_test.sh >\"$STDOUT_LOG\" 2>\"$STDERR_LOG\""

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
