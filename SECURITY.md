# Security policy

## Supported versions

Until the first signed release is published, security fixes are applied to the
`main` branch. After publication, fixes are applied to `main` and the latest
release.

## Reporting a vulnerability

Email private reports to [ilyav@gusinski.us](mailto:ilyav@gusinski.us). Include
the affected Reframer version, macOS version, reproduction steps, and the impact
you observed. If GitHub private vulnerability reporting is enabled for this
repository, its Security tab is also an approved private channel. Do not open a
public issue for an undisclosed vulnerability.

## Security posture

Reframer is a local AppKit application. It does not include an updater,
analytics, a network client, a plug-in loader, or a downloaded-code path.
Video decoding and filtering use Apple’s AVFoundation and Core Image
frameworks.

The app runs in App Sandbox. Its only file entitlement is user-selected,
read-only access. Each load owns one balanced security-scoped lease. A
replacement acquires its lease before the prior player is dismantled, and the
prior lease is released only after its player graph and any cancelling
asynchronous work have finished. Reframer does not persist security-scoped
bookmarks or reopen videos after relaunch.

Global shortcuts use macOS registered hot keys. The enabled lock chord remains
registered during normal operation. Frame-step chords exist only while a video
is loaded, the overlay is locked, and exact or estimated sample navigation is
available; outside that state Reframer does not receive or swallow those keys
through the global path while another app is active. It receives no unrelated
keyboard input from other applications. This path requires neither
Accessibility nor Input Monitoring permission. An exclusive-registration
conflict is shown in Shortcut Settings; the user can change the chord or close
the conflicting app and retry.

Files are opened only after the user chooses, drops, or opens them with
Reframer. Release acceptance requires Hardened Runtime, the two allowlisted
sandbox entitlements, Developer ID signing, notarization, stapling, and
Gatekeeper assessment. The last four are external checks and are not implied
by local repository or unsigned-build validation. Reframer must never write
directly to `TCC.db`, restart `tccd`, or add a broad keyboard event monitor.
Any future network, updater, scripting, or third-party codec feature requires a
fresh review of the
[threat model](docs/THREAT_MODEL.md) before release.
