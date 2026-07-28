# Security policy

## Supported versions

Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Please use GitHub’s private vulnerability-reporting flow for this repository.
Include the affected Reframer version, macOS version, reproduction steps, and
the impact you observed. Do not open a public issue for an undisclosed
vulnerability.

## Security posture

Reframer is a local AppKit application. It does not include an updater,
analytics, a network client, a plug-in loader, or a downloaded-code path.
Video decoding and filtering use Apple’s AVFoundation and Core Image
frameworks.

The app runs in App Sandbox. Its only file entitlement is user-selected,
read-only access. Reframer holds a security-scoped URL only while that video is
the active reference and releases it when the video changes or the app exits.

Global shortcuts use macOS registered hot keys. The enabled lock chord remains
registered during normal operation. Frame-step chords exist only while a video
is loaded, the overlay is locked, and exact or estimated sample navigation is
available; outside that state Reframer does not receive or swallow those keys.
It receives no unrelated keyboard input from other applications. This path
requires neither Accessibility nor Input Monitoring permission. An
exclusive-registration conflict is shown in Shortcut Settings; the user can
change the chord or close the conflicting app and retry.

Files are opened only after the user chooses, drops, or opens them with
Reframer. Release acceptance requires Hardened Runtime, the two allowlisted
sandbox entitlements, Developer ID signing, notarization, stapling, and
Gatekeeper assessment. The last four are external checks and are not implied
by local repository or unsigned-build validation. Reframer must never write
directly to `TCC.db`, restart `tccd`, or add a broad keyboard event monitor.
Any future network, updater, scripting, or third-party codec feature requires a
fresh review of the
[threat model](docs/THREAT_MODEL.md) before release.
