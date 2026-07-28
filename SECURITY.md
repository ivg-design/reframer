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

The app is intentionally not sandboxed in version 0.10 because its
user-configurable global keyboard shortcuts and click-through overlay need to
observe keyboard events while another app is active. macOS controls that
capability through its privacy consent UI. Reframer must never write directly
to `TCC.db`, restart `tccd`, or attempt to bypass that consent.

Files are opened only after the user chooses or drops them. The release build
uses Hardened Runtime, has no private entitlements, is signed with Developer
ID, and is notarized. Any future network, updater, scripting, or third-party
codec feature requires a fresh threat-model review before release.
