#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
# Set these via environment or edit here:
RUNNER_HOST="${CI_RUNNER_HOST:-ci-runner@runner.local}"  # CHANGE THIS
RUNNER_REPO_PATH="${CI_RUNNER_REPO_PATH:-~/Developer/Reframer}"
RUNNER_SCRIPTS_DIR="$RUNNER_REPO_PATH/scripts"
# ======================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "CI Test Driver - Run tests on remote Mac runner"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  run       Run full test suite on runner and print summary"
    echo "  status    Check runner connectivity and status"
    echo "  logs      Show latest test logs from runner"
    echo "  artifacts List recent artifact directories on runner"
    echo "  summary   Print summary of latest run"
    echo ""
    echo "Configuration:"
    echo "  CI_RUNNER_HOST     Runner SSH target (default: $RUNNER_HOST)"
    echo "  CI_RUNNER_REPO_PATH Repo path on runner (default: $RUNNER_REPO_PATH)"
    echo ""
}

check_ssh() {
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$RUNNER_HOST" 'exit 0' 2>/dev/null; then
        echo -e "${RED}ERROR: Cannot connect to runner at $RUNNER_HOST${NC}"
        echo "Check that:"
        echo "  1. Runner Mac is powered on and connected to network"
        echo "  2. SSH is enabled on runner (System Settings → Sharing → Remote Login)"
        echo "  3. SSH key is set up (run: ssh-copy-id $RUNNER_HOST)"
        exit 1
    fi
}

cmd_status() {
    echo "=== Runner Status ==="
    check_ssh
    ssh "$RUNNER_HOST" "
        echo 'Hostname:    '\$(hostname)
        echo 'User:        '\$(whoami)
        echo 'Xcode:       '\$(xcodebuild -version 2>/dev/null | head -1 || echo 'Not found')
        echo 'Repo:        $RUNNER_REPO_PATH'
        if [ -d '$RUNNER_REPO_PATH' ]; then
            cd '$RUNNER_REPO_PATH'
            echo 'Git commit:  '\$(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')
            echo 'Git branch:  '\$(git branch --show-current 2>/dev/null || echo 'N/A')
        else
            echo 'Repo:        NOT FOUND'
        fi
        echo ''
        echo 'Recent artifacts:'
        ls -lt ~/ci_artifacts/ 2>/dev/null | head -6 || echo '  (none)'
    "
}

cmd_run() {
    echo "=========================================="
    echo "=== CI Test Run ==="
    echo "=========================================="
    echo "Runner: $RUNNER_HOST"
    echo ""

    check_ssh

    # Run tests via SSH (with pseudo-terminal for live output)
    EXIT_CODE=0
    ssh -t "$RUNNER_HOST" "bash $RUNNER_SCRIPTS_DIR/runner_test.sh" || EXIT_CODE=$?

    echo ""
    echo "=========================================="
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ TESTS PASSED${NC}"
    else
        echo -e "${RED}❌ TESTS FAILED (exit code $EXIT_CODE)${NC}"
    fi
    echo "=========================================="
    echo ""
    echo "View details: $0 logs"
    echo "List runs:    $0 artifacts"

    return $EXIT_CODE
}

cmd_logs() {
    echo "=== Latest Test Logs ==="
    check_ssh
    ssh "$RUNNER_HOST" "
        LATEST=\$(ls -dt ~/ci_artifacts/*/ 2>/dev/null | head -1)
        if [ -n \"\$LATEST\" ]; then
            echo 'Artifact: '\$LATEST
            echo ''
            echo '--- Last 80 lines of build.log ---'
            tail -80 \"\${LATEST}build.log\" 2>/dev/null || echo 'No log found'
        else
            echo 'No artifacts found'
        fi
    "
}

cmd_artifacts() {
    echo "=== Recent Artifacts ==="
    check_ssh
    ssh "$RUNNER_HOST" "
        echo 'Location: ~/ci_artifacts/'
        echo ''
        ls -lt ~/ci_artifacts/ 2>/dev/null | head -15 || echo '(empty)'
    "
}

cmd_summary() {
    echo "=== Latest Test Summary ==="
    check_ssh
    ssh "$RUNNER_HOST" "
        LATEST=\$(ls -dt ~/ci_artifacts/*/ 2>/dev/null | head -1)
        if [ -n \"\$LATEST\" ] && [ -f \"\${LATEST}summary.txt\" ]; then
            cat \"\${LATEST}summary.txt\"
        else
            echo 'No summary found'
        fi
    "
}

# Main
case "${1:-}" in
    run)
        cmd_run
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    artifacts)
        cmd_artifacts
        ;;
    summary)
        cmd_summary
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
