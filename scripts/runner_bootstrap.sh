#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_URL="https://github.com/YOUR_ORG/Reframer.git"  # CHANGE THIS
REPO_PATH="$HOME/Developer/Reframer"
ARTIFACTS_DIR="$HOME/ci_artifacts"
# ======================================

echo "=== CI Runner Bootstrap ==="
echo "This script sets up the runner Mac for CI testing."
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$REPO_PATH"
mkdir -p "$ARTIFACTS_DIR"

# Clone repo if not exists
if [ ! -d "$REPO_PATH/.git" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_PATH"
else
    echo "Repository already exists at $REPO_PATH"
    cd "$REPO_PATH"
    git fetch origin
    echo "Current commit: $(git rev-parse --short HEAD)"
fi

# Verify Xcode
echo ""
echo "Checking Xcode..."
if ! xcodebuild -version > /dev/null 2>&1; then
    echo "ERROR: Xcode not found. Install Xcode from the App Store."
    exit 1
fi
xcodebuild -version

# Accept license
echo ""
echo "Accepting Xcode license..."
sudo xcodebuild -license accept 2>/dev/null || true

# Set power management (prevent sleep)
echo ""
echo "Configuring power settings to prevent sleep..."
sudo pmset -a sleep 0 2>/dev/null || echo "Could not set sleep=0"
sudo pmset -a disksleep 0 2>/dev/null || echo "Could not set disksleep=0"

# Create marker file
touch "$HOME/.ci_runner_bootstrapped"

echo ""
echo "=========================================="
echo "=== Bootstrap Complete ==="
echo "=========================================="
echo ""
echo "Repo path:   $REPO_PATH"
echo "Artifacts:   $ARTIFACTS_DIR"
echo ""
echo "IMPORTANT: One-time manual steps required:"
echo "1. Log in to this user account on the runner Mac (required for UI tests)"
echo "2. Run the app once manually from Xcode to approve permission prompts"
echo "3. In System Settings → Privacy & Security → Accessibility, allow:"
echo "   - Xcode"
echo "   - Your test app (if prompted)"
echo ""
