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

Reframer is a sandboxed AppKit application. It does not include an updater,
analytics, a plug-in loader, or a downloaded native executable-code path. Native and prepared
local playback uses AVFoundation and Core Image. VP8/VP9 WebM preparation uses
the bundled, separately signed `reframer-ffmpeg` helper built from FFmpeg 8.1.2
and libvpx 1.16.0; its build disables network protocols and produces a local
temporary ProRes 4444/PCM intermediate.

The app's only file entitlement is user-selected, read-only access. Each load
owns one balanced security-scoped lease. A replacement acquires its lease
before the prior player is dismantled, and the prior lease is released only
after its player graph and cancelling asynchronous work finish. Reframer does
not persist security-scoped bookmarks or reopen videos after relaunch. The app
opens a selected WebM while its lease is active and passes an inherited
read-only descriptor to the helper instead of granting the helper a reusable
path. Preparation checks temporary capacity, enforces a 64 GB output limit,
supports cancellation, stops a helper that makes no output progress for five
minutes or runs for 12 hours, and removes prepared output on replacement,
cancellation, termination, and stale-output cleanup at launch.

The app has the outbound network-client entitlement for one explicit feature:
YouTube playback. Before any player HTML is created, the user must accept the
first-use notice and Reframer performs the required per-video Made for Kids
lookup through an ephemeral YouTube Data API request. The query contains the
parsed video identifier, the key is sent in `X-Goog-Api-Key`, and Google
necessarily receives ordinary HTTPS request/network metadata such as source
IP. Missing credentials, rejected requests, unavailable videos, and unknown
status fail closed. An
authorized link uses YouTube's privacy-enhanced embed in a nonpersistent
`WKWebView`; YouTube can still receive the IP address, user agent, app identity,
and video identifier and can present controls, links, branding, ads, settings,
and fullscreen UI. Reframer stores only the accepted consent-notice version,
not YouTube login credentials, pasted-link history, or viewing history. The
ephemeral website data store is cleared before every embed and never persists
cookies or player data, although session data can exist while the player is
running. It does not autoplay.
The embedded player necessarily downloads and executes YouTube web content and
IFrame API JavaScript inside the isolated WebKit process; that is distinct from
downloading native app code, helpers, or plug-ins.

The Data API key is injected at release build time, sent to Google's API in
the `X-Goog-Api-Key` request header rather than the URL, and is not committed.
Because a key embedded in any desktop app can be extracted, release operators
must apply API restrictions, quota limits, and monitoring. A small production
backend that performs the Made for Kids preflight is recommended when stronger
credential control is required.

Global shortcuts use macOS registered hot keys. The enabled lock chord remains
registered during normal operation. Frame-step chords exist only while local
media is loaded, the overlay is locked, and exact or estimated sample
navigation is available; outside that state Reframer does not receive or
swallow those keys through the global path while another app is active. It
receives no unrelated keyboard input from other applications. This path
requires no Accessibility or Input Monitoring permission. Registration
conflicts are shown in Shortcut Settings with a retry action.

Release acceptance requires Hardened Runtime, the exact app entitlements—App
Sandbox, user-selected read-only files, and outbound network client—the
helper's App Sandbox plus inherited-sandbox entitlements, Developer ID signing,
notarization, stapling, and Gatekeeper assessment. The Apple checks are not
implied by local repository or unsigned-build validation. Reframer must never
write directly to `TCC.db`, restart `tccd`, or add a broad keyboard event
monitor. Any future updater, scripting, credential-storage, or codec feature
requires a fresh review of the
[threat model](docs/THREAT_MODEL.md) before release.
