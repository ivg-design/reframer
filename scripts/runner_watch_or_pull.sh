#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION - EDIT THESE =====
REPO_PATH="${REPO_PATH:-$HOME/Developer/Reframer}"
BRANCH="${BRANCH:-main}"
# ======================================

cd "$REPO_PATH"

echo "=== Updating Repository ==="
echo "Path:   $REPO_PATH"
echo "Branch: $BRANCH"

# Stash any local changes
git stash --quiet 2>/dev/null || true

# Fetch and reset to match remote
git fetch origin --quiet
git checkout "$BRANCH" --quiet 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH" --quiet

# Clean untracked files (except ignored)
git clean -fd --quiet

echo "Updated to: $(git rev-parse --short HEAD)"
echo "Commit:     $(git log -1 --format='%s')"
