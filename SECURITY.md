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

Global shortcuts use macOS registered hot keys. Reframer registers only the
enabled lock and frame-step chords and receives no other keyboard input from
other applications. This path requires neither Accessibility nor Input
Monitoring permission. An exclusive-registration conflict is shown in
Shortcut Settings; the user can change the chord or close the conflicting app
and retry.

Files are opened only after the user chooses, drops, or opens them with
Reframer. The release build uses Hardened Runtime and the two allowlisted
sandbox entitlements, is signed with Developer ID, and is notarized. Reframer
must never write directly to `TCC.db`, restart `tccd`, or add a broad keyboard
event monitor. Any future network, updater, scripting, or third-party codec
feature requires a fresh review of the
[threat model](docs/THREAT_MODEL.md) before release.
