# macOS AppKit Test Runner Setup

A dedicated Mac laptop on the local network runs all builds and UI tests, keeping the main Mac focus-free.

## Executive Overview

This setup uses SSH to trigger test runs on a "runner" Mac. The runner keeps an active login session (required for AppKit UI tests), pulls the latest code via git, runs xcodebuild, and stores artifacts. The main Mac never opens any windows - it just prints a summary when tests complete.

**Key Components:**
- Runner Mac: Logged-in session, SSH enabled, Xcode installed
- Main Mac: SSH client, driver script
- Communication: SSH only (no screen sharing needed)
- Artifacts: Test logs, xcresult bundles, summary files

---

## A) Runner Setup Checklist (on the laptop)

### 1. Create a dedicated user (recommended)

```bash
# Run as admin on runner Mac
sudo sysadminctl -addUser ci-runner -fullName "CI Runner" -password "CHANGE_THIS_PASSWORD" -admin
```

Why: Isolates Keychain, notifications, and login items from personal account.

**Fallback:** Use your existing account if user creation isn't allowed.

### 2. Enable Remote Login (SSH)

**macOS Ventura+:**
- System Settings → General → Sharing → Remote Login → ON
- Allow access for: "All users" or specifically "ci-runner"

**Verify from main Mac:**
```bash
ssh ci-runner@RUNNER_HOSTNAME.local 'whoami'
# Should print: ci-runner
```

### 3. Set up SSH key authentication (passwordless)

On main Mac:
```bash
# Generate key if you don't have one
ssh-keygen -t ed25519 -C "ci-runner-key"

# Copy to runner
ssh-copy-id ci-runner@RUNNER_HOSTNAME.local
```

### 4. Keep runner session active (required for UI tests)

**Log in to the ci-runner account on the runner Mac** (physically or via Screen Sharing once).

Then run these commands AS the ci-runner user:

```bash
# Prevent sleep
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset -a displaysleep 0

# Prevent screen lock (run as logged-in user)
defaults write com.apple.screensaver idleTime 0
defaults -currentHost write com.apple.screensaver idleTime 0

# Disable screen saver
defaults write com.apple.screensaver askForPassword -int 0
```

### 5. Verify Xcode

```bash
xcodebuild -version
# Should show Xcode version

# Accept license if needed
sudo xcodebuild -license accept

# Ensure xcode-select points correctly
xcode-select -p
# Should show /Applications/Xcode.app/Contents/Developer
```

### 6. One-time permissions (manual approval required)

When you first run UI tests, macOS will prompt for:

1. **Developer Tools access**: Click "Allow" when prompted
2. **Accessibility permissions**: System Settings → Privacy & Security → Accessibility → Allow your test app/xcodebuild
3. **Input Monitoring**: May be needed for UI tests

These prompts require physical interaction ONCE. After approval, subsequent runs work automatically.

---

## B) Main Mac Setup Checklist

### 1. Verify SSH works

```bash
ssh ci-runner@RUNNER_HOSTNAME.local 'echo "SSH works"'
```

### 2. Set up environment variables (optional)

Add to `~/.zshrc` or `~/.bashrc`:
```bash
export CI_RUNNER_HOST="ci-runner@RUNNER_HOSTNAME.local"
export CI_RUNNER_REPO_PATH="~/Developer/Reframer"
```

---

## C) Scripts

### C1: runner_bootstrap.sh (run ONCE on runner)

```bash
#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_URL="https://github.com/YOUR_ORG/YOUR_REPO.git"
REPO_PATH="$HOME/Developer/Reframer"
ARTIFACTS_DIR="$HOME/ci_artifacts"
# ======================================

echo "=== CI Runner Bootstrap ==="

# Create directories
mkdir -p "$REPO_PATH"
mkdir -p "$ARTIFACTS_DIR"

# Clone repo if not exists
if [ ! -d "$REPO_PATH/.git" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_PATH"
else
    echo "Repository already exists at $REPO_PATH"
fi

# Verify Xcode
echo "Checking Xcode..."
xcodebuild -version || {
    echo "ERROR: Xcode not found. Install Xcode from App Store."
    exit 1
}

# Accept license
sudo xcodebuild -license accept 2>/dev/null || true

# Set power management (prevent sleep)
echo "Configuring power settings..."
sudo pmset -a sleep 0
sudo pmset -a disksleep 0

# Create marker file
touch "$HOME/.ci_runner_bootstrapped"

echo ""
echo "=== Bootstrap Complete ==="
echo "Repo path: $REPO_PATH"
echo "Artifacts: $ARTIFACTS_DIR"
echo ""
echo "NEXT STEPS:"
echo "1. Log in to this user account on the runner Mac (physically)"
echo "2. Run the app once manually to approve any permission prompts"
echo "3. Approve Accessibility permissions if prompted"
```

### C2: runner_watch_or_pull.sh (git pull strategy)

```bash
#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_PATH="$HOME/Developer/Reframer"
BRANCH="main"
# ======================================

cd "$REPO_PATH"

echo "=== Updating Repository ==="
echo "Path: $REPO_PATH"
echo "Branch: $BRANCH"

# Fetch and reset to match remote
git fetch origin
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"
git clean -fd

echo "Updated to: $(git rev-parse --short HEAD)"
echo "Commit: $(git log -1 --format='%s')"
```

### C3: runner_test.sh (main test runner)

```bash
#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_PATH="$HOME/Developer/Reframer"
PROJECT_DIR="$REPO_PATH/Reframer"
SCHEME="Reframer"
DESTINATION="platform=macOS"
ARTIFACTS_BASE="$HOME/ci_artifacts"
KEEP_ARTIFACTS=10
# ======================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARTIFACT_DIR="$ARTIFACTS_BASE/$TIMESTAMP"
LOG_FILE="$ARTIFACT_DIR/build.log"
SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"
XCRESULT_PATH="$ARTIFACT_DIR/TestResults.xcresult"

mkdir -p "$ARTIFACT_DIR"

echo "=== CI Test Run ===" | tee "$SUMMARY_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$SUMMARY_FILE"
echo "Scheme: $SCHEME" | tee -a "$SUMMARY_FILE"
echo "Artifact Dir: $ARTIFACT_DIR" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

cd "$PROJECT_DIR"

# Update repo first
"$REPO_PATH/scripts/runner_watch_or_pull.sh" 2>&1 | tee -a "$LOG_FILE"

echo "Git commit: $(git rev-parse --short HEAD)" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

# Run tests
echo "=== Running Tests ===" | tee -a "$LOG_FILE"

set +e
xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -resultBundlePath "$XCRESULT_PATH" \
    2>&1 | tee -a "$LOG_FILE"
TEST_EXIT_CODE=$?
set -e

# Extract summary from xcresult
echo "" | tee -a "$SUMMARY_FILE"
echo "=== Test Results ===" | tee -a "$SUMMARY_FILE"

if [ -d "$XCRESULT_PATH" ]; then
    # Get test summary using xcresulttool
    xcrun xcresulttool get --format human-readable --path "$XCRESULT_PATH" 2>/dev/null | \
        grep -E "(Test Suite|passed|failed|skipped)" | \
        head -50 | tee -a "$SUMMARY_FILE" || true

    # Count pass/fail
    PASSED=$(grep -c "passed" "$LOG_FILE" 2>/dev/null || echo "0")
    FAILED=$(grep -c "failed" "$LOG_FILE" 2>/dev/null || echo "0")

    echo "" | tee -a "$SUMMARY_FILE"
    echo "Passed: $PASSED" | tee -a "$SUMMARY_FILE"
    echo "Failed: $FAILED" | tee -a "$SUMMARY_FILE"
else
    echo "No xcresult bundle found" | tee -a "$SUMMARY_FILE"
fi

# Final status
echo "" | tee -a "$SUMMARY_FILE"
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "STATUS: SUCCESS" | tee -a "$SUMMARY_FILE"
else
    echo "STATUS: FAILED (exit code $TEST_EXIT_CODE)" | tee -a "$SUMMARY_FILE"
fi

# Cleanup old artifacts
echo ""
echo "=== Cleanup ==="
cd "$ARTIFACTS_BASE"
ls -dt */ 2>/dev/null | tail -n +$((KEEP_ARTIFACTS + 1)) | xargs rm -rf 2>/dev/null || true
echo "Kept last $KEEP_ARTIFACTS artifact runs"

# Print artifact location
echo ""
echo "=== Artifacts ==="
echo "Directory: $ARTIFACT_DIR"
echo "Log: $LOG_FILE"
echo "Summary: $SUMMARY_FILE"
echo "xcresult: $XCRESULT_PATH"

# Return test exit code
exit $TEST_EXIT_CODE
```

### C4: driver.sh (on main Mac)

```bash
#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
RUNNER_HOST="${CI_RUNNER_HOST:-ci-runner@runner.local}"
RUNNER_REPO_PATH="${CI_RUNNER_REPO_PATH:-~/Developer/Reframer}"
RUNNER_SCRIPTS_DIR="$RUNNER_REPO_PATH/scripts"
# ======================================

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  run       Run tests on runner and print summary"
    echo "  status    Check runner status"
    echo "  logs      Tail latest logs from runner"
    echo "  artifacts List recent artifacts"
    echo ""
}

cmd_status() {
    echo "=== Runner Status ==="
    ssh "$RUNNER_HOST" "
        echo 'Hostname:' \$(hostname)
        echo 'User:' \$(whoami)
        echo 'Xcode:' \$(xcodebuild -version 2>/dev/null | head -1 || echo 'Not found')
        echo 'Repo:' $RUNNER_REPO_PATH
        if [ -d '$RUNNER_REPO_PATH' ]; then
            cd '$RUNNER_REPO_PATH'
            echo 'Git commit:' \$(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')
        fi
    "
}

cmd_run() {
    echo "=== Starting Test Run on Runner ==="
    echo "Runner: $RUNNER_HOST"
    echo ""

    # Run tests via SSH
    ssh -t "$RUNNER_HOST" "bash $RUNNER_SCRIPTS_DIR/runner_test.sh"
    EXIT_CODE=$?

    echo ""
    echo "========================================"
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ TESTS PASSED"
    else
        echo "❌ TESTS FAILED (exit code $EXIT_CODE)"
    fi
    echo "========================================"

    return $EXIT_CODE
}

cmd_logs() {
    echo "=== Latest Logs ==="
    ssh "$RUNNER_HOST" "
        LATEST=\$(ls -dt ~/ci_artifacts/*/ 2>/dev/null | head -1)
        if [ -n \"\$LATEST\" ]; then
            echo 'Artifact: '\$LATEST
            echo ''
            tail -50 \"\${LATEST}build.log\" 2>/dev/null || echo 'No log found'
        else
            echo 'No artifacts found'
        fi
    "
}

cmd_artifacts() {
    echo "=== Recent Artifacts ==="
    ssh "$RUNNER_HOST" "ls -lt ~/ci_artifacts/ 2>/dev/null | head -11"
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
    *)
        usage
        exit 1
        ;;
esac
```

---

## D) LaunchAgent (optional - auto-start on login)

Create `~/Library/LaunchAgents/com.ci.runner.plist` on the runner Mac:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ci.runner</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>echo "CI Runner ready at $(date)" >> ~/ci_runner.log</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.ci.runner.plist
```

---

## E) Verification Steps

### 1. Verify SSH (from main Mac)

```bash
ssh ci-runner@RUNNER.local 'whoami && hostname'
# Expected: ci-runner and runner hostname
```

### 2. Verify Xcode on runner

```bash
ssh ci-runner@RUNNER.local 'xcodebuild -version'
# Expected: Xcode version info
```

### 3. Verify repo access

```bash
ssh ci-runner@RUNNER.local 'cd ~/Developer/Reframer && git status'
```

### 4. Run a test build

```bash
./driver.sh run
```

Expected:
- Tests run on runner via SSH
- No windows open on main Mac
- Summary printed to terminal
- Exit code reflects test pass/fail

### 5. Check artifacts exist

```bash
./driver.sh artifacts
# Should list timestamped directories

./driver.sh logs
# Should show build log content
```

---

## Troubleshooting

### "No schemes found"
```bash
ssh ci-runner@RUNNER.local 'cd ~/Developer/Reframer/Reframer && xcodebuild -list'
```
Update SCHEME in runner_test.sh accordingly.

### UI tests fail with "not permitted"
1. Log in to runner Mac physically
2. Run one UI test manually from Xcode
3. Approve the permission prompts that appear
4. Future runs will work via SSH

### Runner goes to sleep
```bash
ssh ci-runner@RUNNER.local 'caffeinate -d &'
```

### Permission denied on scripts
```bash
ssh ci-runner@RUNNER.local 'chmod +x ~/Developer/Reframer/scripts/*.sh'
```

---

## Quick Start Summary

**On Runner Mac (once):**
```bash
# 1. Enable SSH in System Settings
# 2. Log in as ci-runner user
# 3. Run bootstrap
./runner_bootstrap.sh
```

**On Main Mac:**
```bash
# 1. Set up SSH key
ssh-copy-id ci-runner@runner.local

# 2. Run tests
./driver.sh run
```
