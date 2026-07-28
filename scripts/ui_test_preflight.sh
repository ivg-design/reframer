#!/bin/bash

set -euo pipefail

CONSOLE_USER="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
CURRENT_USER="$(/usr/bin/id -un)"

if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
    echo "error: UI tests require a logged-in macOS desktop session" >&2
    exit 77
fi

if [ "$CONSOLE_USER" != "$CURRENT_USER" ]; then
    echo "error: UI tests must run as the active console user ($CONSOLE_USER)" >&2
    exit 77
fi

if ! /usr/bin/pgrep -x WindowServer >/dev/null 2>&1; then
    echo "error: WindowServer is unavailable; UI tests cannot run headlessly" >&2
    exit 77
fi

SESSION_STATE="$(
    /usr/sbin/ioreg -n Root -d1 2>/dev/null || true
    /usr/sbin/ioreg -r -n CGSSession 2>/dev/null || true
)"
if /usr/bin/grep -Eq \
    '"IOConsoleLocked"[[:space:]]*=[[:space:]]*Yes|"CGSSessionScreenIsLocked"[[:space:]]*=[[:space:]]*Yes' \
    <<<"$SESSION_STATE"; then
    echo "error: UI tests require an unlocked macOS desktop session" >&2
    exit 77
fi

if [ "${REFRAMER_UI_RUNNER_AUTHORIZED:-0}" != "1" ]; then
    cat >&2 <<'MESSAGE'
error: UI runner authorization has not been acknowledged.

Approve Xcode/automation access through System Settings on this runner, then set:
  REFRAMER_UI_RUNNER_AUTHORIZED=1

This preflight intentionally does not edit TCC.db, restart tccd, remove
quarantine metadata, or re-sign build products.
MESSAGE
    exit 77
fi

echo "UI runner preflight passed for $CURRENT_USER."
