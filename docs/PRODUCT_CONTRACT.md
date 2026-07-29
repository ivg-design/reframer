# Reframer product contract

This document is the human-readable authority for Reframer 0.11.0 build 4.
Its machine-readable counterpart is
[`product-contract.json`](product-contract.json).

## Sources and capabilities

Reframer accepts local WebM, MP4/M4V/MOV, AVI, DV, MPEG/MPEG-2/transport-
stream, and 3GP/3G2 containers. A recognized extension is not a guarantee that
every embedded codec is usable.

Native containers are preflighted and played through AVFoundation. Reframer
selects the first enabled usable video track, or the first usable fallback
track. Playback, Core Image filtering, dimensions, nominal rate, and exact or
estimated navigation all use that same track.

VP8 and VP9 WebM media is prepared through the bundled universal
`Contents/Helpers/reframer-ffmpeg`, built from FFmpeg 8.1.2 and libvpx 1.16.0
with network protocols disabled. The app holds the user-selected read-only
lease, opens the input, and gives the helper an inherited descriptor. The
temporary output is ProRes 4444 with PCM audio so alpha is preserved and the
normal AVFoundation pipeline can provide playback, navigation, filters, and
audio. Preparation requires at least 2 GB of temporary capacity, is capped at
64 GB, stops after five minutes without output progress or 12 hours total,
supports cancellation, and cleans output after cancellation, replacement,
failure, termination, and stale-output discovery at launch.

YouTube is an explicit network source. Before any player HTML is created, the
user accepts the first-use privacy and terms notice. Reframer stores only the
accepted notice version locally; it does not retain the pasted URL or viewing
history. Reframer then sends the video identifier to YouTube Data API
`videos.list` for the required per-video Made for Kids check, with the API key
in the `X-Goog-Api-Key` header. Google also necessarily receives ordinary
HTTPS request and network metadata such as the source IP address. Missing
credentials, rejected requests, unavailable videos, and unknown status fail
closed. An approved source uses the
privacy-enhanced YouTube IFrame Player in a nonpersistent `WKWebView`. It never
autoplays, and Reframer clears the ephemeral website data store before each
embed. YouTube chooses adaptive quality; its supported embed API does not let
Reframer force maximum quality.

| Capability | Local native/prepared | YouTube |
|---|---:|---:|
| Play/pause, time seek, mute, volume | Yes | Yes |
| Exact or labeled estimated frame navigation | Yes | No |
| Zoom and pan | Yes | No |
| Core Image filters | Yes | No |
| Reframer opacity transform | Yes | No |
| Window move/resize | Yes | Yes |
| Always on Top When Unlocked | Yes | Yes |
| Click-through Lock | Yes | No |

YouTube's standard controls, links, branding, ads, settings, and fullscreen UI
remain visible and unobscured, and WebKit element fullscreen is enabled. From
pending compliance preflight through active playback, Reframer disables every
filter and transform control that could affect or obscure the embed. Reframer
pauses it when hidden or occluded and does not automatically resume it.
The web view fills the complete video canvas and remains at least 200×200
points; YouTube owns its internal aspect fit and letterboxing. Reframer does
not request or store YouTube credentials, pasted-link history, or viewing
history. Its nonpersistent web view can hold session cookies or player data
while a player is running, but never persists them and clears all website data
before each embed.

Click-through Lock is unavailable from pending YouTube preflight through
playback. If the overlay was locked, Reframer unlocks before the preflight.
This is required because YouTube's standard controls, captions, settings,
fullscreen, and links must remain interactive. Always on Top When Unlocked is
the topmost YouTube option.

YouTube timeline-drag previews call the player without seek-ahead; releasing
the scrubber and discrete time seeks allow seek-ahead. The ready snapshot may
initialize the live embedded-player controls but must not overwrite saved
native-media volume or mute preferences. Muting uses the official player mute
state without setting retained player volume to zero, so the embedded
player's own Unmute control restores the prior audible level.

## Overlay window

The video surface and control bar are one canonical, externally managed
`NSWindow`. Reframer must not expose a separately targetable control window.
While unlocked, macOS or a third-party window manager such as Mosaic moves or
resizes the entire overlay.

The preferred initial width is 1,060 points and the minimum supported width is
640 points. At 920 points or wider, the control bar is one 48-point row. Below
920 points through the minimum, it is two 48-point rows with a total height of
96 points. No action, field, slider, status metadata, or accessibility element
may be hidden or unreachable by that change.

Always on Top When Unlocked is a persisted preference available to every
source. For native or prepared local media, Lock mode overrides it
and atomically applies all of the following:

- the complete overlay uses the public `NSWindow.Level.statusBar` tier above
  all ordinary application windows, including normal, floating, modal, and
  utility windows;
- the complete overlay, including its video and control bar, ignores pointer
  events;
- moving and resizing are disabled;
- the enabled registered global lock shortcut restores interaction from the
  app underneath.

Entering click-through is permitted only when the exact configured global
Lock/Unlock chord is successfully registered. If that registration disappears
or conflicts, is suspended during recording, or global shortcuts are disabled,
Reframer must immediately unlock and present the configured chord plus
recovery guidance. System pop-up menus, drag UI, the screen saver, and
assistive-technology windows retain precedence.

## Commands and Shortcut Settings

| Command | Default | Shortcut Settings | Guard |
|---|---|---|---|
| Open local video | Command-O | Fixed menu command | App active |
| Open YouTube video | Option-Command-O | Fixed menu command | App active; consent, configured API key, and Made for Kids preflight |
| Play / Pause | Space | Customizable | Source ready |
| Step forward 1 | Command-Page Down | Customizable | Local media with sample navigation; global only when loaded and locked |
| Step backward 1 | Command-Page Up | Customizable | Local media with sample navigation; global only when loaded and locked |
| Step forward / backward 10 | Add Shift | Customizable multiplier | Same guard as frame step |
| Pan 1 / 10 / 100 | Arrow / Shift-Arrow / Command-Shift-Arrow | Customizable multipliers | Local media, unlocked |
| Reset zoom / view | 0 / R | Customizable | Local media, unlocked |
| Toggle lock locally / globally | L / Command-Shift-L | Customizable | Native/prepared local media only; entry requires exact registered recovery chord |
| Shortcut Settings | H | Customizable | App active |
| Documentation | Command-? | Fixed Help command | App active |
| Filter panel | F | Customizable | Local media ready |
| Close current panel or recording | Escape | Customizable | Contextual |

The 14 actions represented by editable rows are Play/Pause, both frame-step
directions, four pan directions, Reset Zoom, Reset View, local Lock, global
Lock, Shortcut Settings, Close Current Panel, and Filter Panel. Command-O,
Option-Command-O, and Command-? are fixed menu/Help commands and do not appear
as editable Shortcut Settings rows. Shift-scroll and Command-Shift-scroll are
fixed pointer gestures rather than shortcut rows.

The enabled global lock chord stays registered in every video and lock state.
The four global frame variants are registered only while local media is loaded,
the overlay is locked, and exact or estimated navigation is available. At all
other times they are neither registered nor swallowed through Reframer's
global path. Registered hot keys require no Accessibility or Input Monitoring
permission.

Shortcut editing rejects collisions, reserved system chords, modifier collapse,
and unsafe unmodified global keys. A customized chord replaces its old chord.
Clearing, disabling, resetting, and multiplier choices persist.

Shortcut Settings is resizable from 700×520 through 1100×1100 points, prefers
780×1020, remembers a validated size, and scrolls vertically at compact
heights. One shared five-column grid aligns enabled state, shortcut, action,
multiplier, and clear controls across all sections. Keyboard traversal is
row-major; Tab advances focus and is never recorded as a binding.

## State, navigation, and accessibility

Loading, ready, playing, paused, ended, and failed are distinct. A replacement
stops prior playback and lands paused. New generations invalidate stale load,
seek, filter, and scrub callbacks. Playback intent is main-thread-owned and
revisioned so a delayed player or seek completion cannot undo a newer Pause.

Exact local navigation uses presentation timestamps from the selected track.
While indexing, when cursors are unavailable, or after the 2,000,000-sample
ceiling, Reframer presents a labeled constant-rate estimate. A released scrub
resolves to the nearest active boundary. YouTube is time-seek only and exposes
no frame-navigation claim.

Controls expose task-oriented names, states, values, ranges, orientation, and
actions. Focus enters and returns from panels predictably. Reduce Motion,
Increase Contrast, and Reduce Transparency updates remain live. Decorative
overlays do not intercept pointer input.

The documentation window renders bundled Help HTML as native AppKit content.
Help does not launch a WebKit process or fetch network content. Only allowlisted
YouTube and Google policy links can leave Help, and they open in the system
browser.

## Privacy and release

The app entitlement allowlist is exactly:

- `com.apple.security.app-sandbox`;
- `com.apple.security.files.user-selected.read-only`;
- `com.apple.security.network.client`.

The helper entitlement allowlist is exactly App Sandbox plus
`com.apple.security.inherit`. Inheritance may include the app's network-client
sandbox profile, but the helper binary itself is compiled without networking
and exposes only file/pipe protocols. Third-party source revisions, download
locations, licenses, patent
grant, and source-offer details ship in `ThirdPartyLicenses` and are described
in [Third-party software](THIRD_PARTY.md).

The network entitlement supports only the explicit YouTube workflow:
ephemeral Data API preflight and privacy-enhanced playback from YouTube,
Google API, and YouTube media hosts. There is no analytics, updater, telemetry,
or native executable-download channel. The YouTube player necessarily
downloads remote web content and IFrame API JavaScript inside WebKit.
The only YouTube-related preference stored locally is the accepted consent
notice version. The Data API query contains the parsed video identifier and
sends the API key in the `X-Goog-Api-Key` header; Google still receives
ordinary HTTPS request/network metadata such as source IP. The player uses a
nonpersistent website data store. Session cookies and player data may exist
while it is running, but are never persisted and are cleared before every
embed.

A release must be universal arm64/x86_64, use Hardened Runtime and Developer ID
signing, sign the nested helper with its exact inherited-sandbox entitlements,
pass exact bundle allowlists, and pass notarization, stapling, Gatekeeper, and
final-ZIP round-trip checks. The Data API key is supplied as the secret
`REFRAMER_YOUTUBE_DATA_API_KEY`, injected as `YOUTUBE_DATA_API_KEY`, and must
never be committed. A desktop key is extractable; restrict it by API/quota and
prefer a production preflight backend when stronger credential control is
needed.
