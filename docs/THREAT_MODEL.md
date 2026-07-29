# Reframer threat model

This model covers Reframer 0.11.0 build 4: local media, WebM preparation,
YouTube playback, overlay behavior, and registered shortcuts.

## Assets and trust boundaries

- User media remains outside the app container. App Sandbox grants read-only
  access only after the user selects, drops, or opens a file.
- Each local load owns a balanced security-scoped lease through preflight,
  player use, cancellation, and teardown. No persistent bookmark is stored.
- Native containers are decoded by AVFoundation. Core Image operates on the
  selected local track.
- `reframer-ffmpeg` is checked-in nested native code, not downloaded code. It is built
  from pinned FFmpeg 8.1.2 and libvpx 1.16.0 sources with network protocols
  disabled, is universal, and is signed with App Sandbox plus sandbox
  inheritance. Inheritance may include the parent network-client sandbox
  profile; the enforceable network reduction here is the helper binary's
  compile-time absence of network protocol implementations and exact
  file/pipe-only protocol surface.
- For WebM, the app opens the selected file while its lease is active and
  inherits that read-only descriptor into the helper. The child never receives
  a reusable security-scoped path. Output is a random temporary ProRes
  4444/PCM file.
- The app requires at least 2 GB of temporary capacity and enforces a 64 GB
  output ceiling. A no-progress watchdog stops the helper after five minutes,
  and an absolute watchdog stops it after 12 hours. Cancellation and watchdog
  stops terminate the helper, then use a bounded forced stop if needed.
  Partial/prepared output is removed on failure, replacement, cancellation,
  termination, and stale startup cleanup.
- License, patent, revision, source-download, and source-offer records ship
  next to the helper under `ThirdPartyLicenses`.

## Network and embedded content

The app has `com.apple.security.network.client` for an explicit YouTube
workflow. It has no analytics, telemetry, updater, or native executable-
download channel. The authorized YouTube player does download and execute
remote web content and IFrame API JavaScript inside WebKit.

Before any embed HTML is created:

1. the user enters a supported HTTPS YouTube link;
2. first use requires explicit privacy and terms consent;
3. an ephemeral `URLSession` puts only the parsed video identifier in the
   request query and sends the Data API key in the `X-Goog-Api-Key` request
   header—not the URL—to `www.googleapis.com/youtube/v3/videos`; Google also
   necessarily receives ordinary HTTPS request/network metadata such as the
   source IP address;
4. Reframer requires one matching item and a definite Made for Kids value;
5. any missing key, network/API error, quota rejection, unavailable item, or
   unknown value fails closed.

An authorized video uses YouTube's privacy-enhanced embed in a nonpersistent
`WKWebView`. YouTube and its media hosts can receive the IP address, user
agent, Reframer identity/Referer, and selected identifier and can render
controls, links, branding, ads, settings, and fullscreen UI. Reframer does not
autoplay, request YouTube login credentials, or retain pasted-link history,
or viewing history. It stores only the accepted consent-notice version as a
local preference. Session cookies and player storage can exist while the
nonpersistent web view is running, but are never persisted; Reframer clears
the website data store before each embed. The app pauses on hidden,
miniaturized, occluded, sleep, and session-resign paths and does not
automatically resume.

Player messages are accepted only from the main frame's expected synthetic
HTTPS origin with a per-load token and bridge version. Navigation is restricted
to the player and synthetic app origins; valid HTTPS links activated by the
user—including YouTube controls, ads, and policy links—open in the system
browser. Reframer does not overlay, transform, filter, or obscure YouTube's
player UI.

Reframer automatically unlocks before YouTube preflight and rejects Lock
commands through playback. Click-through would make required controls,
captions, settings, fullscreen, and links noninteractive; Always on Top When
Unlocked is the permitted topmost policy for YouTube.

A YouTube Data API key injected into a desktop binary is extractable even when
omitted from source. Restrict it by API, quota, and monitoring. For production
credential control, replace direct key use with a narrow backend that returns
only the preflight decision.

## Keyboard input

Reframer uses exclusive registered hot keys. The lock chord remains registered
during normal operation. Frame variants exist only while local media is loaded,
the overlay is locked, and exact or estimated navigation is available. They
are removed outside that state and never receive unrelated keys.

The app uses no global `NSEvent` monitor, event tap, Accessibility API, or
Input Monitoring permission. Registration conflicts are visible and
retryable. Shortcut recording suspends registrations and lock safety forces an
unlock if its exact recovery chord becomes unavailable.

## Documentation

Bundled Help HTML is parsed into native AppKit attributed text. The Help
renderer rejects traversal outside the Help root and never starts WebKit or
fetches network content. Only exact allowlisted YouTube/Google policy links can
leave Help, through the system browser.

## Release controls

The app entitlement allowlist is exactly App Sandbox, user-selected read-only
files, and outbound network client. The helper entitlement allowlist is exactly
App Sandbox and inherited sandbox. Release validation also requires:

- one arm64/x86_64 app and helper, each targeting macOS 15.0;
- Hardened Runtime and nested-code signature verification;
- exact Contents, Resources, Help, helper, license, and signature allowlists;
- no symbolic links or unexpected executable-bearing paths;
- a nonempty, non-placeholder YouTube API key injected only at build time;
- Developer ID signing, notarization, stapling, Gatekeeper, and final ZIP
  extraction/revalidation.

Historical build-3 Apple evidence does not validate build 4. Candidate-specific
evidence is recorded in [Build 4 Readiness](AUDIT_0.11.0_BUILD_4.md).
